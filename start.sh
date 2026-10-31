#!/usr/bin/env bash
# Start the Client Resilience Toolkit panel.
#
# Checks/installs the Python and Node.js dependencies, builds the panel, starts it
# in the background with a PID file and log, and waits until it responds.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$ROOT_DIR/.run"
LOG_DIR="$ROOT_DIR/logs"
PID_FILE="$RUN_DIR/web-panel.pid"
PORT_FILE="$RUN_DIR/web-panel.port"
URL_FILE="$RUN_DIR/web-panel.url"
LOG_FILE="$LOG_DIR/web-panel.log"

HOST="${WEB_HOST:-127.0.0.1}"
PORT="${WEB_PORT:-5000}"
PORT_EXPLICIT=0
FOREGROUND=0
STATUS_ONLY=0
RESTART=0

if [[ -t 1 ]]; then
    C_DIM=$'\033[2m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'
    C_RESET=$'\033[0m'
else
    C_DIM=''
    C_GREEN=''
    C_YELLOW=''
    C_RED=''
    C_RESET=''
fi

info() { printf '%s[*]%s %s\n' "$C_DIM" "$C_RESET" "$*"; }
ok() { printf '%s[+]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die() { printf '%s[-]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: ./start.sh [options]

Start the Client Resilience Toolkit panel. Dependencies are installed automatically when missing.

Options:
  -p, --port PORT     Port to listen on (default: 5000, env: WEB_PORT)
  -H, --host HOST     Bind address (default: 127.0.0.1, env: WEB_HOST)
  -f, --foreground    Run attached to the terminal instead of in the background
  -s, --status        Show whether the panel is running
  -r, --restart       Stop a running panel first, then start it
  -h, --help          Show this help

Files:
  PID  .run/web-panel.pid
  Log  logs/web-panel.log
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p | --port)
            [[ $# -ge 2 ]] || die "--port requires a value"
            PORT="$2"
            PORT_EXPLICIT=1
            shift 2
            ;;
        --port=*)
            PORT="${1#*=}"
            PORT_EXPLICIT=1
            shift
            ;;
        -H | --host)
            [[ $# -ge 2 ]] || die "--host requires a value"
            HOST="$2"
            shift 2
            ;;
        --host=*)
            HOST="${1#*=}"
            shift
            ;;
        -f | --foreground)
            FOREGROUND=1
            shift
            ;;
        -s | --status)
            STATUS_ONLY=1
            shift
            ;;
        -r | --restart)
            RESTART=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            die "Unknown option: $1 (try --help)"
            ;;
    esac
done

[[ "$PORT" =~ ^[0-9]+$ ]] || die "Invalid port: $PORT"
PORT=$((10#$PORT))
if ((PORT < 1 || PORT > 65535)); then
    die "Port must be between 1 and 65535"
fi
[[ -n "$HOST" ]] || die "Host cannot be empty"

listener_pid() {
    command -v lsof >/dev/null 2>&1 || return 1
    lsof -nP -iTCP:"$1" -sTCP:LISTEN -t 2>/dev/null | head -n 1
}

pid_is_our_panel() {
    local pid="$1"
    local cwd=''
    local cmd=''

    [[ -n "$pid" ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    command -v lsof >/dev/null 2>&1 || return 1

    cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1)" || cwd=''
    [[ "$cwd" == "$ROOT_DIR/web" ]] || return 1

    cmd="$(ps -p "$pid" -o command= 2>/dev/null)" || cmd=''
    [[ "$cmd" == *"dist/server.js"* || "$cmd" == *"src/server.ts"* ]] || return 1
    return 0
}

port_busy() {
    local python_bin="$1"
    local port="$2"
    "$python_bin" - "$port" <<'PY'
import socket
import sys

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.settimeout(0.4)
try:
    sock.connect(("127.0.0.1", int(sys.argv[1])))
except OSError:
    raise SystemExit(1)
finally:
    sock.close()
raise SystemExit(0)
PY
}

http_ready() {
    local python_bin="$1"
    local url="$2"
    "$python_bin" - "$url" <<'PY' >/dev/null 2>&1
import sys
import urllib.request

try:
    with urllib.request.urlopen(sys.argv[1], timeout=1) as response:
        ok = response.status < 500
except Exception:
    ok = False
raise SystemExit(0 if ok else 1)
PY
}

RUNNING_PID=''
RUNNING_PORT=''
RUNNING_URL=''
read_state() {
    if [[ -f "$PID_FILE" ]]; then
        RUNNING_PID="$(cat "$PID_FILE" 2>/dev/null)" || RUNNING_PID=''
    fi
    if [[ -f "$PORT_FILE" ]]; then
        RUNNING_PORT="$(cat "$PORT_FILE" 2>/dev/null)" || RUNNING_PORT=''
    fi
    if [[ -f "$URL_FILE" ]]; then
        RUNNING_URL="$(cat "$URL_FILE" 2>/dev/null)" || RUNNING_URL=''
    fi
    return 0
}

if [[ $STATUS_ONLY -eq 1 ]]; then
    read_state
    pid="$RUNNING_PID"
    if [[ -z "$pid" ]] || ! pid_is_our_panel "$pid"; then
        candidate="$(listener_pid "${RUNNING_PORT:-$PORT}" || true)"
        if pid_is_our_panel "$candidate"; then
            pid="$candidate"
        fi
    fi

    if [[ -n "$pid" ]] && pid_is_our_panel "$pid"; then
        ok "Client Resilience Toolkit panel is running"
        printf '    URL:  %s\n' "${RUNNING_URL:-http://$HOST:${RUNNING_PORT:-$PORT}}"
        printf '    PID:  %s\n' "$pid"
        printf '    Log:  %s\n' "$LOG_FILE"
        exit 0
    fi

    rm -f "$PID_FILE" "$PORT_FILE" "$URL_FILE"
    warn "Client Resilience Toolkit panel is not running."
    exit 1
fi

if [[ $RESTART -eq 1 ]]; then
    info "Restarting the web panel..."
    stop_args=(--quiet)
    if [[ $PORT_EXPLICIT -eq 1 ]]; then
        stop_args+=(--port "$PORT")
    fi
    bash "$ROOT_DIR/stop.sh" "${stop_args[@]}" || true
fi

read_state
if [[ -n "$RUNNING_PID" ]] && pid_is_our_panel "$RUNNING_PID"; then
    ok "Client Resilience Toolkit panel is already running"
    printf '    URL:  %s\n' "${RUNNING_URL:-http://$HOST:${RUNNING_PORT:-$PORT}}"
    printf '    PID:  %s\n' "$RUNNING_PID"
    printf '    Stop: ./stop.sh\n'
    exit 0
fi
rm -f "$PID_FILE" "$PORT_FILE" "$URL_FILE"

info "Checking Python..."
SYS_PYTHON="$(command -v python3.13 || true)"
if [[ -z "$SYS_PYTHON" ]]; then
    SYS_PYTHON="$(command -v python3.12 || true)"
fi
if [[ -z "$SYS_PYTHON" ]]; then
    SYS_PYTHON="$(command -v python3.11 || true)"
fi
if [[ -z "$SYS_PYTHON" ]]; then
    SYS_PYTHON="$(command -v python3 || true)"
fi
[[ -n "$SYS_PYTHON" ]] || die "Python 3.11+ is required (https://python.org)"
"$SYS_PYTHON" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' ||
    die "Python 3.11+ is required (found $("$SYS_PYTHON" --version 2>&1))"

VENV_PY="$ROOT_DIR/.venv/bin/python"
if [[ ! -x "$VENV_PY" ]]; then
    info "Creating virtual environment (.venv)..."
    "$SYS_PYTHON" -m venv "$ROOT_DIR/.venv" || die "Could not create .venv"
fi

if ! "$VENV_PY" - <<'PY' >/dev/null 2>&1
import importlib

for module in (
    "cloudscraper",
    "dns",
    "icmplib",
    "impacket",
    "psutil",
    "requests",
    "yarl",
    "jwt",
    "PyRoxy",
    "flask",
):
    importlib.import_module(module)
PY
then
    info "Installing Python dependencies..."
    "$VENV_PY" -m pip install --upgrade pip --quiet || warn "pip upgrade failed; continuing"
    "$VENV_PY" -m pip install -r "$ROOT_DIR/web/requirements.txt" ||
        die "Python dependency installation failed"
fi
ok "Python $("$VENV_PY" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')"

info "Checking Node.js..."
command -v node >/dev/null 2>&1 || die "Node.js 18+ is required (https://nodejs.org)"
command -v npm >/dev/null 2>&1 || die "npm is required"
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
if [[ ! "$NODE_MAJOR" =~ ^[0-9]+$ ]] || ((NODE_MAJOR < 18)); then
    die "Node.js 18+ is required (found $(node --version))"
fi
# Resolve the real binary: some version managers install a shim that spawns a
# child process, which would make PID tracking and shutdown unreliable.
REAL_NODE="$(node -p 'process.execPath')"
[[ -x "$REAL_NODE" ]] || die "Could not resolve the Node.js executable"

if [[ ! -x "$ROOT_DIR/web/node_modules/.bin/tsc" ]] ||
    [[ ! -x "$ROOT_DIR/web/node_modules/.bin/tailwindcss" ]] ||
    [[ ! -d "$ROOT_DIR/web/node_modules/express" ]] ||
    [[ ! -d "$ROOT_DIR/web/node_modules/typescript" ]]; then
    info "Installing web panel dependencies..."
    (cd "$ROOT_DIR/web" && npm install --prefer-offline) || die "npm install failed"
fi
ok "Node.js $(node --version)"

info "Building web panel..."
(cd "$ROOT_DIR/web" && npm run build --silent) || die "Web panel build failed"

if port_busy "$SYS_PYTHON" "$PORT"; then
    pid="$(listener_pid "$PORT" || true)"
    if pid_is_our_panel "$pid"; then
        mkdir -p "$RUN_DIR"
        printf '%s\n' "$pid" >"$PID_FILE"
        printf '%s\n' "$PORT" >"$PORT_FILE"
        printf '%s\n' "http://$HOST:$PORT" >"$URL_FILE"
        ok "Client Resilience Toolkit panel is already running on port $PORT"
        printf '    URL:  %s\n' "http://$HOST:$PORT"
        printf '    PID:  %s\n' "$pid"
        printf '    Stop: ./stop.sh\n'
        exit 0
    fi

    if [[ $PORT_EXPLICIT -eq 1 ]]; then
        if [[ -n "$pid" ]]; then
            die "Port $PORT is already in use (PID $pid). Choose another with --port."
        fi
        die "Port $PORT is already in use. Choose another with --port."
    fi

    warn "Port $PORT is busy (macOS AirPlay Receiver often uses 5000)."
    PORT_FOUND=0
    for candidate in {5001..5010}; do
        if ! port_busy "$SYS_PYTHON" "$candidate"; then
            PORT="$candidate"
            PORT_FOUND=1
            break
        fi
    done
    if [[ $PORT_FOUND -ne 1 ]]; then
        die "No free port found in 5001-5010. Use --port to choose one."
    fi
    ok "Using port $PORT instead."
fi

DISPLAY_HOST="$HOST"
if [[ "$DISPLAY_HOST" == "0.0.0.0" || "$DISPLAY_HOST" == "::" ]]; then
    DISPLAY_HOST="127.0.0.1"
fi
URL="http://$DISPLAY_HOST:$PORT"

mkdir -p "$RUN_DIR" "$LOG_DIR"
if [[ -f "$LOG_FILE" ]] && (($(wc -c <"$LOG_FILE") > 10485760)); then
    mv -f "$LOG_FILE" "$LOG_FILE.1"
fi

export PATH="$ROOT_DIR/.venv/bin:$PATH"

if [[ $FOREGROUND -eq 1 ]]; then
    info "Starting Client Resilience Toolkit panel in the foreground at $URL"
    info "Press Ctrl+C to stop."

    "$VENV_PY" -c '
import os
import sys

os.chdir(sys.argv[1])
os.setsid()
os.execvp(sys.argv[2], sys.argv[2:])
' "$ROOT_DIR/web" "$REAL_NODE" "dist/server.js" --host "$HOST" --port "$PORT" </dev/null &
    PANEL_PID=$!

    printf '%s\n' "$PANEL_PID" >"$PID_FILE"
    printf '%s\n' "$PORT" >"$PORT_FILE"
    printf '%s\n' "$URL" >"$URL_FILE"

    trap 'kill -TERM -- "-$PANEL_PID" 2>/dev/null || kill -TERM "$PANEL_PID" 2>/dev/null || true; wait "$PANEL_PID" 2>/dev/null || true; rm -f "$PID_FILE" "$PORT_FILE" "$URL_FILE"; exit 130' INT TERM
    set +e
    wait "$PANEL_PID"
    status=$?
    set -e
    rm -f "$PID_FILE" "$PORT_FILE" "$URL_FILE"
    exit "$status"
fi

info "Starting Client Resilience Toolkit panel..."
"$VENV_PY" -c '
import os
import sys

os.chdir(sys.argv[1])
os.setsid()
os.execvp(sys.argv[2], sys.argv[2:])
' "$ROOT_DIR/web" "$REAL_NODE" "dist/server.js" --host "$HOST" --port "$PORT" </dev/null >>"$LOG_FILE" 2>&1 &
PANEL_PID=$!

printf '%s\n' "$PANEL_PID" >"$PID_FILE"
printf '%s\n' "$PORT" >"$PORT_FILE"
printf '%s\n' "$URL" >"$URL_FILE"

READY=0
for _ in {1..40}; do
    if ! kill -0 "$PANEL_PID" 2>/dev/null; then
        break
    fi
    if http_ready "$VENV_PY" "http://$DISPLAY_HOST:$PORT/"; then
        READY=1
        break
    fi
    sleep 0.5
done

if [[ $READY -ne 1 ]]; then
    warn "Client Resilience Toolkit panel failed to start."
    if [[ -s "$LOG_FILE" ]]; then
        printf '\n--- last 20 log lines ---\n' >&2
        tail -n 20 "$LOG_FILE" >&2 || true
    fi
    kill -TERM -- "-$PANEL_PID" 2>/dev/null || kill -TERM "$PANEL_PID" 2>/dev/null || true
    rm -f "$PID_FILE" "$PORT_FILE" "$URL_FILE"
    exit 1
fi

ok "Client Resilience Toolkit panel is running"
printf '    URL:  %s\n' "$URL"
printf '    PID:  %s\n' "$PANEL_PID"
printf '    Log:  %s\n' "$LOG_FILE"
printf '    Stop: ./stop.sh\n'
