#!/bin/bash
# Starts Godot in headless mode with LSP enabled, then bridges stdio↔TCP.
# Used by Claude Code's LSP integration.
#
# Godot's LSP is TCP-based (--lsp-port), but Claude Code's stdio transport
# expects stdin/stdout. This script:
#   1. Starts Godot headless with --lsp-port if not already running
#   2. Waits for the port to be ready
#   3. Bridges stdin/stdout to the TCP socket using socat

GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
PORT="${GODOT_LSP_PORT:-6005}"
PROJECT_PATH="${1:-$(pwd)}"
PIDFILE="/tmp/godot-lsp-${PORT}.pid"

# Check if Godot LSP is already running on this port
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    # Already running, just bridge
    :
else
    # Start Godot headless with LSP
    "$GODOT" --editor --headless --lsp-port "$PORT" --path "$PROJECT_PATH" &>/dev/null &
    echo $! > "$PIDFILE"

    # Wait for port to be ready (up to 15 seconds)
    for i in $(seq 1 30); do
        if nc -z localhost "$PORT" 2>/dev/null; then
            break
        fi
        sleep 0.5
    done

    if ! nc -z localhost "$PORT" 2>/dev/null; then
        echo "Failed to start Godot LSP on port $PORT" >&2
        rm -f "$PIDFILE"
        exit 1
    fi
fi

# Bridge stdio to TCP
exec socat - TCP:localhost:"$PORT"
