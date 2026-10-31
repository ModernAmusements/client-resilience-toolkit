<div align="center">

# Client Resilience Toolkit

### A ModernAmusements public safety project

Authorized resilience testing for infrastructure you own.

</div>

---

## Public safety commitment

This project exists to help defenders protect public and private infrastructure. It is built for
controlled, authorized testing inside the client's own environment.

- Test only systems you own or have explicit written permission to test.
- Keep every test scoped, supervised, and contained.
- Never target third-party, public, or shared infrastructure.
- Do not use this project to harass, disrupt, or extort anyone.
- Report vulnerabilities responsibly.

> [!WARNING]
> Unauthorized use of this software may violate computer misuse, network protection, and data
> protection laws. The operator is responsible for authorization, scope, and legal compliance.

## What this project is

The Client Resilience Toolkit is a self-hosted validation platform. It helps a client answer one
question:

> Can our own service stay available and correct when it receives hostile or extreme traffic?

It combines a Python test engine, a web dashboard, a CLI, and Docker packaging. The dashboard is the
main operating surface. The CLI and Docker image support automation and isolated runs.

## What this project is not

- It is not a public attack service.
- It is not a DDoS-for-hire platform.
- It is not a replacement for authorization, legal review, or a rules-of-engagement document.
- It is not a benchmark replacement. Use `k6`, `wrk`, or `autocannon` for latency and throughput
  measurement.

## Capabilities

### Resilience testing

- Layer 7 HTTP request patterns, including slow-connection and malformed-request behavior.
- Layer 3 and Layer 4 transport behavior, including TCP, UDP, SYN, and ICMP.
- Protocol checks for DNS, NTP, memcached, and selected game and voice services.
- Proxy support for HTTP, SOCKS4, and SOCKS5.
- Configurable thread counts, duration, requests per connection, and proxy lists.

Run `python start.py --help` for the full method list.

### Diagnostics

- `PING` - reachability and latency.
- `CHECK` - HTTP response status.
- `DNS` - A, AAAA, MX, NS, TXT, CNAME, and SOA records.
- `HEADERS` - HTTP response and security headers.
- `INFO` - geolocation and ASN.
- `DSTAT` - live network, CPU, and memory statistics.
- `PROXYCHECK` - validate a proxy list.
- `CFIP` - find the real IP behind Cloudflare.
- `TSSRV` - TeamSpeak SRV records.

### Operations

- Single command-center dashboard built with Tailwind CSS.
- Start and stop scripts with dependency bootstrapping, logs, and PID tracking.
- JWT-protected panel API.
- Docker image for the CLI, with `NET_RAW` for raw-socket methods.
- Local `.venv` for the Python engine and Node.js for the panel.

## Dashboard

The dashboard brings the main workflow into one view:

- System stats: CPU, RAM, sent bytes, and active tasks.
- Launch form: preset, layer, method, target, threads, and duration.
- Advanced settings: proxy type, proxy file, RPC, and reflector.
- Active tasks with per-task stop controls.
- Recent output and a link to the full terminal.
- Bundled resources: user agents, referers, and proxy lists.

### Intensity presets

| Preset | Threads | Duration | RPC |
| --- | ---: | ---: | ---: |
| Easy | 5 | 10s | 1 |
| Medium | 10 | 15s | 1 |
| Hard | 25 | 30s | 5 |
| Stress | 50 | 60s | 10 |

`Medium` is the default for local testing. Manual edits to threads, duration, or RPC switch the preset
to `Custom`. `Hard` and `Stress` can slow a local machine. Use them only on systems you own.

## Quick start

### Requirements

- Python 3.11 or newer.
- Node.js 18 or newer.
- Git, because the PyRoxy dependency is installed from git.
- Docker is optional.

### Install and start

```bash
git clone https://github.com/ModernAmusements/client-resilience-toolkit.git
cd client-resilience-toolkit
./start.sh
```

`start.sh` creates `.venv`, installs missing Python and Node.js dependencies, builds the dashboard,
and starts the panel in the background.

Default panel URL:

```text
http://127.0.0.1:5001
```

Port 5000 is often occupied by the macOS AirPlay Receiver, so the script falls back to 5001 through
5010. The actual URL is printed after startup.

### Status and stop

```bash
./start.sh --status
./stop.sh
```

### Manual setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python start.py DOCTOR
python start.py WEB
```

The installer for the web panel can also be run directly:

```bash
bash web/scripts/install.sh
```

## Safety model

The toolkit is designed to run inside the client's boundary:

- The panel binds to `127.0.0.1` by default.
- Tests run as local processes controlled by the client.
- No traffic is sent to a third-party testing service.
- The dashboard includes low, medium, hard, and stress presets with visible warnings.
- Raw-socket methods require root or Docker with `NET_RAW`.

Production deployments should add controls that fit the client's governance:

- Target allowlists and environment tags.
- Approval workflows before a test can run.
- Role-based access control.
- Audit logs for every target, method, parameter, and operator.
- Rate and duration caps.
- A kill switch.
- Network segmentation between the test runner and production systems.
- Legal review and signed authorization for every scope.

These controls are deployment requirements. They are not a substitute for written authorization.

## CLI

The CLI is useful for diagnostics and automation.

```bash
source .venv/bin/activate
python start.py --help
python start.py DOCTOR
python start.py tools
```

`DOCTOR` checks the Python environment, configuration, wordlists, proxy directory, web panel scripts,
and raw-socket access. A non-root host normally reports `15/16`; raw sockets need root or Docker.

## Docker

Build the CLI image:

```bash
docker compose build
docker compose run --rm mhddos DOCTOR
```

The Docker image contains the CLI only. The web panel runs from the repository checkout.

## Configuration

- `config.json` - proxy providers and Minecraft protocol settings.
- `files/useragent.txt` - user-agent wordlist.
- `files/referers.txt` - referer wordlist.
- `files/proxies/` - proxy lists. An empty file means no proxies are used.
- `web/` - Express panel, Tailwind UI, and API.

## Project structure

```text
start.py              Test engine and CLI
web/                  Web panel
  public/             Dashboard assets
  src/                Express server and Tailwind source
  dist/               Compiled server
files/                Wordlists and proxy lists
agents/               Internal agent context. Excluded from deployment.
start.sh              Start the panel
stop.sh               Stop the panel
Dockerfile            CLI image
docker-compose.yml    Compose configuration
```

## Development

```bash
cd web
npm install
npm run build
npm run dev -- --port 5001
```

`npm run build` compiles TypeScript and builds `web/src/tailwind.css` into
`web/public/tailwind.css`. Commit the generated CSS so release archives include the dashboard layout.

## Security

- Do not open public issues for security vulnerabilities. Follow `SECURITY.md`.
- Do not commit secrets, proxy lists, or runtime state.
- Keep the panel bound to localhost unless you add authentication and network controls.
- Review every test target and scope before running a test.

## Attribution

This project builds on MHDDoS by MatrixTM, licensed under the MIT License:

https://github.com/MatrixTM/MHDDoS

ModernAmusements additions include the command-center dashboard, Tailwind layout, intensity presets,
start and stop scripts, public safety documentation, and local deployment tooling.

## License

MIT. See `LICENSE`.

---

<div align="center">

**ModernAmusements**

Public safety through authorized resilience testing.

</div>
