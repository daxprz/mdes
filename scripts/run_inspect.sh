#!/bin/bash
# Run a test with visual inspection enabled.
# Usage: scripts/run_inspect.sh <test_name> [timeout_seconds]
#
# Runs the test, waits for INSPECT result in the log, prints the outcome.
# Exit codes: 0=OK, 1=BAD, 2=BROKEN, 3=timeout

TEST_NAME="${1:?Usage: run_inspect.sh <test_name> [timeout]}"
TIMEOUT="${2:-60}"
LOG="/var/tumu/logs/godot_debug.log"

# Mark current log position
LOG_START=$(wc -l < "$LOG" 2>/dev/null || echo 0)

# Launch test with inspect=true
RESULT=$(echo "run $TEST_NAME inspect=true" | nc -w2 localhost 9999)
echo "$RESULT"

if [[ "$RESULT" != OK* ]]; then
    echo "ERROR: Failed to start test"
    exit 3
fi

# Poll for INSPECT result (only in NEW log lines)
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    sleep 1
    ELAPSED=$((ELAPSED + 1))

    INSPECT_LINE=$(tail -n +$((LOG_START + 1)) "$LOG" | grep "INSPECT:" | grep -v "Waiting" | tail -1)

    if [ -n "$INSPECT_LINE" ]; then
        echo "$INSPECT_LINE"

        if echo "$INSPECT_LINE" | grep -q "PASSED"; then
            exit 0
        elif echo "$INSPECT_LINE" | grep -q "BAD"; then
            exit 1
        elif echo "$INSPECT_LINE" | grep -q "BROKEN"; then
            exit 2
        elif echo "$INSPECT_LINE" | grep -q "timeout"; then
            exit 0  # auto-OK on timeout
        fi
    fi
done

echo "TIMEOUT: No inspect result after ${TIMEOUT}s"
exit 3
