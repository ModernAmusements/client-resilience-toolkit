# Agent Context

Last updated: 2026-10-31
Repository: MHDDoS
Purpose: local development setup, web panel operation, and safe local testing.

This directory is tracked by git but excluded from deployment and Docker images.
The Docker build ignores `agents/`, and the release workflow copies an explicit file list, so agent
files never ship in images or release archives.

## Project state

- MHDDoS 2.4 stress-testing toolkit.
- The web control panel runs on the host, not inside Docker.
- Panel URL: http://127.0.0.1:5001
- Port 5000 is occupied by the macOS AirPlay Receiver, so `start.sh` falls back to 5001.
- Local test target: Next.js 16.4.2 dev server at http://127.0.0.1:3000/en.
- Docker image: `ghcr.io/matrixtm/mhddos:latest`, CLI only.

## Environment

- macOS 26.0, arm64.
- Python 3.13.12 in `.venv`. The system default is 3.15; 3.13 was chosen because the pinned dependencies have wheels for it.
- Node 24.5.0 and npm 11.5.1 via Homebrew.
- Volta was removed completely, freeing about 1.3 GB. Do not reintroduce Volta-specific assumptions.
- Docker 29.6.0 and Compose 5.1.4 via Colima. Run `colima start` if the daemon is not running.

## Main commands

```bash
./start.sh                  # install missing deps, build, start in the background
./start.sh --status         # show URL, PID, and log path
./start.sh --foreground     # run attached to the terminal
./start.sh --restart        # stop, rebuild, and start again
./start.sh --port 5010      # strict port, fails if busy
./start.sh --host 0.0.0.0   # bind all interfaces

./stop.sh                   # graceful shutdown
./stop.sh --all             # also stop the Docker Compose stack
./stop.sh --quiet           # only warnings and errors

.venv/bin/python start.py DOCTOR
docker compose run --rm mhddos DOCTOR
```

## start.sh behavior

1. Resolves the repository root from the script location.
2. Parses `--port`, `--host`, `--foreground`, `--status`, and `--restart`.
3. Finds Python 3.13, 3.12, 3.11, or `python3`, requiring version 3.11 or newer.
4. Creates `.venv` when missing.
5. Checks the required Python imports and runs `pip install -r web/requirements.txt` if any are missing.
6. Checks Node 18 or newer and resolves the real Node binary with `process.execPath`.
7. Runs `npm install` when `web/node_modules` is incomplete.
8. Builds the panel with `npm run build` (`tsc`).
9. Checks the port. If it is busy and no port was specified explicitly, it scans 5001 through 5010.
10. Starts `node dist/server.js` in a new session through a Python `os.setsid()` launcher, so the PID is the process group leader.
11. Writes `.run/web-panel.pid`, `.run/web-panel.port`, and `.run/web-panel.url`.
12. Waits for an HTTP response below 500 for up to 20 seconds. On failure it prints the last 20 log lines, kills the process group, and removes the state files.

## stop.sh behavior

1. Reads the PID and port from `.run/`.
2. Verifies the process working directory is `<repo>/web` and the command line contains `dist/server.js` or `src/server.ts`.
3. Falls back to the stored port, then scans 5000 through 5010 if the state files are missing.
4. Sends `SIGTERM` to the process group, waits up to 10 seconds, then uses `SIGKILL` if needed.
5. Removes the `.run/` state files.
6. With `--all`, runs `docker compose down --remove-orphans`.

The identity check prevents killing an unrelated process that reused the PID.

## Web panel

- Express server compiled from `web/src/server.ts` to `web/dist/server.js`.
- Serves the static UI from `web/public`.
- Auto-authenticates by calling `POST /api/auth/token` and storing the JWT in browser localStorage.
- Spawns `python start.py ...` for each task. The `.venv/bin` directory is on `PATH`, so `python` resolves to the project venv.
- Streams task output to the terminal view through SSE.
- `files/proxies/http.txt` is empty, so tasks run without proxies.
- The dashboard is a single command center: stats, launch form, active tasks, recent output, and resources in one view.
- Wide screens use a two-column grid. Below the 1280px breakpoint the dashboard stacks into one column.
- The launch form is compact. Proxy type, proxy file, RPC, and reflector live under the collapsed
  "Advanced settings" section.
- The sidebar keeps detailed Tasks, Tools, and Terminal views.
- Layout uses Tailwind CSS 4.3.3, installed locally with no CDN. `npm run build` runs `tsc` and builds
  `web/src/tailwind.css` into `web/public/tailwind.css`.
- `start.sh` verifies the Tailwind binary and rebuilds the CSS on every start.

### Dashboard preset

Fixed defaults:

```text
Layer:       L7
Method:      GET
Target:      http://127.0.0.1:3000/en
SOCKS type:  0
Proxy file:  http.txt
```

Intensity presets:

| Preset | Threads | Duration | RPC |
| --- | ---: | ---: | ---: |
| Easy | 5 | 10s | 1 |
| Medium | 10 | 15s | 1 |
| Hard | 25 | 30s | 5 |
| Stress | 50 | 60s | 10 |

`Medium` is selected by default. Manual edits to threads, duration, or RPC switch the preset to
`Custom`. The defaults live in `web/public/index.html` and `web/public/app.js`.

### Method notes

- Use `GET` for the local Next.js site. `APACHE` produces `Errno 32` broken pipe and `Errno 54` connection reset errors against Next.js.
- Keep local tests at 10 threads and 15 seconds. The tool warns above 1000 threads; 5000 can exhaust the machine.
- Raw-socket methods (`SYN`, `ICMP`, amplification) need root or Docker with `NET_RAW`.
- Next.js dev mode compiles routes on demand and is not representative of production. Use a production build for meaningful results.
- For real benchmarks, prefer `k6`, `wrk`, or `autocannon`.

## Changes made in this session

- Added `start.sh` and `stop.sh`.
- Added `.run/` to `.gitignore`; `logs/` was already ignored.
- Made `README.md` ASCII-only and removed all emojis.
- Added the Start & Stop Scripts and Command Reference sections to the README.
- Removed Volta and cleaned its lines from `~/.profile`.
- Removed the VS Code status bar color override from `~/Library/Application Support/Code/User/settings.json`. The Mac Dark theme default is now used.
- Preset the dashboard defaults in `web/public/index.html` and `web/public/app.js`.
- Rebuilt the dashboard as a single command center with a Tailwind layout, intensity presets, live tasks, recent output, and resources.
- Added Tailwind CSS build tooling: `web/src/tailwind.css`, `web/public/tailwind.css`, and npm scripts.
- Updated the web panel, locale, and server log text to ASCII punctuation where edited.

## Constraints

- ASCII only in documentation and scripts. No emojis.
- Only test systems you own or have explicit written permission to test.
- Do not run high thread counts against a local dev machine.
- Do not commit secrets, proxy lists, or runtime state.

## Verification

```bash
./start.sh --status
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:5001/
.venv/bin/python start.py DOCTOR
docker compose run --rm mhddos DOCTOR
```

Expected results:

- Panel returns HTTP 200.
- `http://127.0.0.1:5001/tailwind.css` returns HTTP 200.
- Host doctor reports 15/16 without root; raw sockets need root.
- Docker doctor reports 15/16 because the image is CLI-only and does not include the web panel.
- Browser check: dashboard active, method `GET`, preset `medium`, no JavaScript console errors.

## Deployment

Local panel deployment:

```bash
./start.sh --restart
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:5001/
```

Docker image deployment:

```bash
docker compose build
docker compose run --rm mhddos DOCTOR
```

Notes:

- The Docker image contains the CLI only. The web panel runs from the repository checkout.
- `agents/` is excluded from Docker builds and release archives.
- Commit `web/public/tailwind.css` so release archives include the dashboard layout.
- The configured git remote is the upstream project. Do not push local client presets or agent context
  without an explicit deployment target.

## Files

- `start.sh`, `stop.sh`: panel lifecycle.
- `.run/`: PID, port, and URL state. Gitignored.
- `logs/web-panel.log`: panel log. Gitignored.
- `web/public/index.html`: command-center layout and form defaults.
- `web/public/app.js`: method, proxy-type, and intensity presets.
- `web/public/style.css`: existing component styles.
- `web/src/tailwind.css`: Tailwind source.
- `web/public/tailwind.css`: generated Tailwind output. Commit it for release archives.
- `README.md`: user-facing documentation.
- `.dockerignore`: excludes `agents/` from deployment.
