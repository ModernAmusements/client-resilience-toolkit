#!/usr/bin/env bash
# Stop the MHDDoS web panel started by start.sh.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$ROOT_DIR/.run"
PID_FILE="$RUN_DIR/web-panel.pid"
PORT_FILE="$RUN_DIR/web-panel.port"
URL_FILE="$RUN_DIR/web-panel.url"

PORT=''
PORT_EXPLICIT=0
ALL=0
QUIET=0

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
Usage: ./stop.sh [options]

Stop the MHDDoS web panel started by start.sh.

Options:
  -p, --port PORT   Port to look on when the PID file is missing (default: 5000)
  -a, --all         Also stop the Docker Compose stack
  -q, --quiet       Only print warnings and errors
  -h, --help        Show this help
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
        -a | --all)
            ALL=1
            shift
            ;;
        -q | --quiet)
            QUIET=1
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

if [[ -n "$PORT" ]]; then
    [[ "$PORT" =~ ^[0-9]+$ ]] || die "Invalid port: $PORT"
    PORT=$((10#$PORT))
    if ((PORT < 1 || PORT > 65535)); then
        die "Port must be between 1 and 65535"
    fi
fi

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

if [[ -z "$PORT" ]]; then
    if [[ -f "$PORT_FILE" ]]; then
        PORT="$(cat "$PORT_FILE" 2>/dev/null)" || PORT=''
    fi
    if [[ -z "$PORT" ]]; then
        PORT=5000
    fi
fi

PID=''
if [[ -f "$PID_FILE" ]]; then
    candidate="$(cat "$PID_FILE" 2>/dev/null)" || candidate=''
    if pid_is_our_panel "$candidate"; then
        PID="$candidate"
    fi
fi

if [[ -z "$PID" ]]; then
    candidate="$(listener_pid "$PORT" || true)"
    if pid_is_our_panel "$candidate"; then
        PID="$candidate"
    fi
fi

# Last resort: scan the usual fallback range when no state file survived.
if [[ -z "$PID" && $PORT_EXPLICIT -eq 0 ]]; then
    for candidate_port in {5000..5010}; do
        candidate="$(listener_pid "$candidate_port" || true)"
        if pid_is_our_panel "$candidate"; then
            PID="$candidate"
            PORT="$candidate_port"
            break
        fi
    done
fi

if [[ -z "$PID" ]]; then
    if [[ $QUIET -eq 0 ]]; then
        info "MHDDoS web panel is not running."
    fi
else
    if [[ $QUIET -eq 0 ]]; then
        info "Stopping MHDDoS web panel (PID $PID)..."
    fi

    PGID="$(ps -o pgid= -p "$PID" 2>/dev/null | tr -d '[:space:]')" || PGID=''
    if [[ "$PGID" == "$PID" ]]; then
        kill -TERM -- "-$PID" 2>/dev/null || true
    else
        kill -TERM "$PID" 2>/dev/null || true
    fi

    for _ in {1..50}; do
        if ! kill -0 "$PID" 2>/dev/null; then
            break
        fi
        state="$(ps -p "$PID" -o stat= 2>/dev/null | tr -d '[:space:]')" || state=''
        if [[ "$state" == Z* ]]; then
            break
        fi
        sleep 0.2
    done

    if kill -0 "$PID" 2>/dev/null; then
        state="$(ps -p "$PID" -o stat= 2>/dev/null | tr -d '[:space:]')" || state=''
        if [[ "$state" != Z* ]]; then
            warn "Panel did not stop gracefully; forcing shutdown."
            if [[ "$PGID" == "$PID" ]]; then
                kill -KILL -- "-$PID" 2>/dev/null || true
            else
                kill -KILL "$PID" 2>/dev/null || true
            fi
        fi
    fi

    if [[ $QUIET -eq 0 ]]; then
        ok "MHDDoS web panel stopped."
    fi
fi

rm -f "$PID_FILE" "$PORT_FILE" "$URL_FILE"

if [[ $ALL -eq 1 ]]; then
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        if [[ $QUIET -eq 0 ]]; then
            info "Stopping Docker Compose stack..."
        fi
        if (cd "$ROOT_DIR" && docker compose down --remove-orphans); then
            if [[ $QUIET -eq 0 ]]; then
                ok "Docker Compose stack stopped."
            fi
        else
            warn "docker compose down failed."
        fi
    else
        if [[ $QUIET -eq 0 ]]; then
            warn "Docker daemon is not running; skipping Docker cleanup."
        fi
    fi
fi
