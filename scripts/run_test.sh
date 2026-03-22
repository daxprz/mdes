#!/bin/bash
# Run a test via RCON and report results.
# Usage: ./scripts/run_test.sh <test_name> [max_wait_seconds]
# Example: ./scripts/run_test.sh chained_upper_platform_etz 60
#
# Polls zones every 1s until all ETZs are entered or timeout.

TEST_NAME="${1:?Usage: run_test.sh <test_name> [max_wait_seconds]}"
MAX_WAIT="${2:-60}"
PORT=9999

rcon() {
    echo "$1" | nc -w 2 localhost $PORT 2>/dev/null
}

echo "=== Running test: $TEST_NAME (max ${MAX_WAIT}s) ==="

# Start the test
rcon "run $TEST_NAME"

# Wait for setup to complete before polling
sleep 5

# Poll every 1s
ELAPSED=5
while [ $ELAPSED -lt $MAX_WAIT ]; do
    sleep 1
    ELAPSED=$((ELAPSED + 1))

    # Check zones status
    ZONES=$(rcon "zones")
    TOTAL=$(echo "$ZONES" | grep -c "ETZ\|DAZ")

    # Skip polling if no zones defined yet
    if [ "$TOTAL" -eq 0 ]; then
        continue
    fi

    # Count remaining un-entered ETZs
    REMAINING=$(echo "$ZONES" | grep -c "ETZ.*: ?")
    ENTERED=$(echo "$ZONES" | grep -c "ETZ.*: OK")
    DAZ_VIOLATIONS=$(echo "$ZONES" | grep -c "DAZ.*: FAIL")

    # Print progress every 5s or on change
    if [ $((ELAPSED % 5)) -eq 0 ] || [ "$REMAINING" -eq 0 ] || [ "$DAZ_VIOLATIONS" -gt 0 ]; then
        echo "[${ELAPSED}s] ETZ entered: $ENTERED, remaining: $REMAINING, DAZ violations: $DAZ_VIOLATIONS"
    fi

    # Early exit if all ETZs entered or DAZ violated
    if [ "$REMAINING" -eq 0 ] || [ "$DAZ_VIOLATIONS" -gt 0 ]; then
        echo "Early exit at ${ELAPSED}s"
        break
    fi
done

# Final results
echo ""
echo "=== FINAL RESULTS ==="
echo "--- Zones ---"
rcon "zones"
echo ""
echo "--- HP ---"
rcon "hp"
echo ""
echo "--- Enemies ---"
rcon "enemies"
echo ""
echo "--- Status ---"
rcon "status"
