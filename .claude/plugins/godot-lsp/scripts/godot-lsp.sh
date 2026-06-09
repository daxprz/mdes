#!/bin/bash
# Starts Godot in headless mode with LSP enabled, then bridges stdio↔TCP.
# Used by Claude Code's LSP integration.
#
# Godot's LSP is TCP-based (--lsp-port), but Claude Code expects stdio transport.
# This script:
#   1. Starts Godot headless with --lsp-port if not already running
#   2. Waits for the port to be ready
#   3. Bridges stdin/stdout to the TCP socket using socat

# Resolve the Godot binary per-OS: honor $GODOT_BIN, then PATH, then well-known
# locations (macOS app bundle / Linux install dirs).
resolve_godot() {
    if [ -n "$GODOT_BIN" ] && [ -x "$GODOT_BIN" ]; then echo "$GODOT_BIN"; return; fi
    if command -v godot  >/dev/null 2>&1; then command -v godot;  return; fi
    if command -v godot4 >/dev/null 2>&1; then command -v godot4; return; fi
    case "$(uname -s)" in
        Darwin)
            for c in "/Applications/Godot.app/Contents/MacOS/Godot" \
                     "$HOME/Applications/Godot.app/Contents/MacOS/Godot"; do
                [ -x "$c" ] && { echo "$c"; return; }
            done ;;
        *)
            for c in /usr/local/bin/godot /usr/bin/godot /opt/godot/godot; do
                [ -x "$c" ] && { echo "$c"; return; }
            done ;;
    esac
}
GODOT="$(resolve_godot)"
PORT="${GODOT_LSP_PORT:-6005}"
PIDFILE="/tmp/godot-lsp-${PORT}.pid"

# Log for debugging (check /tmp/godot-lsp.log if things go wrong)
LOG="/tmp/godot-lsp.log"
log() { echo "$(date '+%H:%M:%S') $*" >> "$LOG"; }

# Determine project path
find_project() {
    # 1. CLAUDE_PROJECT_DIR (set by Claude Code for plugin processes)
    if [ -n "$CLAUDE_PROJECT_DIR" ]; then
        log "Project from CLAUDE_PROJECT_DIR: $CLAUDE_PROJECT_DIR"
        echo "$CLAUDE_PROJECT_DIR"
        return
    fi
    # 2. Walk up from PWD looking for project.godot
    local dir="${PWD}"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/project.godot" ]; then
            log "Project from PWD walk: $dir"
            echo "$dir"
            return
        fi
        dir="$(dirname "$dir")"
    done
    # 3. Walk up from script location
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    dir="$script_dir"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/project.godot" ]; then
            log "Project from script walk: $dir"
            echo "$dir"
            return
        fi
        dir="$(dirname "$dir")"
    done
    # 4. Check common locations
    for candidate in /var/tumu/workspace /Users/jeremy/dev/dax/test123; do
        if [ -f "$candidate/project.godot" ]; then
            log "Project from known location: $candidate"
            echo "$candidate"
            return
        fi
    done
    log "WARNING: No project.godot found, using PWD: $PWD"
    echo "${PWD}"
}

# Resolve symlinks — Godot needs the real path
PROJECT_PATH="$(cd "$(find_project)" 2>/dev/null && pwd -P)"

log "PWD=$PWD PROJECT_PATH=$PROJECT_PATH PORT=$PORT"

# Start Godot headless if not already running on this port
if nc -z localhost "$PORT" 2>/dev/null; then
    log "Port $PORT already open, bridging"
else
    # Kill stale PID if any
    if [ -f "$PIDFILE" ]; then
        kill "$(cat "$PIDFILE")" 2>/dev/null
        rm -f "$PIDFILE"
    fi

    log "Starting Godot headless: $GODOT --editor --headless --lsp-port $PORT --path $PROJECT_PATH"
    "$GODOT" --editor --headless --lsp-port "$PORT" --path "$PROJECT_PATH" >>/tmp/godot-lsp-godot.log 2>&1 &
    echo $! > "$PIDFILE"
    log "Godot PID: $(cat $PIDFILE)"

    # Wait for port to be ready (up to 20 seconds)
    for i in $(seq 1 40); do
        if nc -z localhost "$PORT" 2>/dev/null; then
            break
        fi
        sleep 0.5
    done

    if ! nc -z localhost "$PORT" 2>/dev/null; then
        log "FAILED: Port $PORT not open after 20s"
        echo "Failed to start Godot LSP on port $PORT" >&2
        rm -f "$PIDFILE"
        exit 1
    fi
    log "Godot LSP ready on port $PORT"
fi

# Bridge stdio ↔ TCP. socat keeps running as long as both ends are open.
exec socat STDIO TCP:localhost:"$PORT"
