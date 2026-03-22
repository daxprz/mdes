#!/bin/bash
# Run test suites sequentially via RCON.
# Usage: ./scripts/run_suites.sh [suite1 suite2 ...]
# Default: combat chained
PORT=9999

rcon() {
    echo "$1" | nc -w 2 localhost $PORT 2>/dev/null
}

get_wait() {
    case "$1" in
        combat) echo 260 ;;
        chained) echo 180 ;;
        *) echo 300 ;;
    esac
}

# Kill any existing Godot first
pkill -f "Godot.*test123" 2>/dev/null
sleep 2

# Start Godot
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/jeremy/dev/dax/test123 &
GODOT_PID=$!
echo "Started Godot (PID=$GODOT_PID)"
sleep 5

SUITES="${@:-combat chained}"

for SUITE in $SUITES; do
    WAIT=$(get_wait "$SUITE")
    echo ""
    echo "========================================"
    echo "  SUITE: $SUITE (waiting ${WAIT}s)"
    echo "========================================"
    rcon "suite $SUITE"

    # Poll every 10s for status
    ELAPSED=0
    while [ $ELAPSED -lt $WAIT ]; do
        sleep 10
        ELAPSED=$((ELAPSED + 10))
        STATUS=$(rcon "status")
        echo "  [${ELAPSED}s] $STATUS"
    done
done

echo ""
echo "========================================"
echo "  ALL SUITES COMPLETE"
echo "========================================"

# Quit the game
rcon "quit"
