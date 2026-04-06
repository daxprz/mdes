#!/bin/bash
# verify_audio.sh — Record a Strudel pattern and verify with spectral/temporal analysis.
#
# Usage:
#   scripts/verify_audio.sh <pattern> <cps> <slots> <expect_spec> [duration_sec]
#
# Example:
#   scripts/verify_audio.sh 'note("c2 ~ eb2 f2").s("sawtooth")' 0.5 4 \
#       "c2:0-500,~:500-1000,eb2:1000-1500,f2:1500-2000" 6
#
# The script:
#   1. Sends the pattern to Godot via RCON
#   2. Starts recording
#   3. Waits for the specified duration (default: 6s)
#   4. Stops recording
#   5. Runs analyze_wav.py with pitch tracking and validation
#   6. Exits with 0 if all checks pass, 1 otherwise

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ANALYZER="$SCRIPT_DIR/analyze_wav.py"
NC_TIMEOUT=2
GODOT_USER="$HOME/Library/Application Support/Godot/app_userdata/The Ultimate Muffin"

PATTERN="${1:?Usage: verify_audio.sh <pattern> <cps> <slots> <expect_spec> [duration_sec]}"
CPS="${2:?Missing cps}"
SLOTS="${3:?Missing slots}"
EXPECT="${4:?Missing expect spec}"
DURATION="${5:-6}"
RECORDING_NAME="verify_$(date +%s)"

echo "=== Audio Verification ==="
echo "  Pattern: $PATTERN"
echo "  CPS: $CPS  Slots: $SLOTS"
echo "  Expect: $EXPECT"
echo "  Duration: ${DURATION}s"
echo ""

# Check Godot is running
STATUS=$(echo "status" | nc -w$NC_TIMEOUT localhost 9999 2>/dev/null || true)
if [ -z "$STATUS" ]; then
    echo "ERROR: Godot not running (RCON on port 9999 not responding)"
    exit 1
fi

# Stop any current playback
echo "strudel stop" | nc -w$NC_TIMEOUT localhost 9999 >/dev/null 2>&1 || true
sleep 0.5

# Start the pattern
echo "strudel $PATTERN cps=$CPS" | nc -w$NC_TIMEOUT localhost 9999
sleep 1  # Let it stabilize for 1 cycle

# Record
echo "strudel record start" | nc -w$NC_TIMEOUT localhost 9999
sleep "$DURATION"
RESULT=$(echo "strudel record stop $RECORDING_NAME" | nc -w$NC_TIMEOUT localhost 9999)
echo "  Recording: $RESULT"

# Stop
echo "strudel stop" | nc -w$NC_TIMEOUT localhost 9999 >/dev/null 2>&1 || true

WAV_FILE="$GODOT_USER/$RECORDING_NAME.wav"
if [ ! -f "$WAV_FILE" ]; then
    echo "ERROR: Recording not found at $WAV_FILE"
    exit 1
fi

echo ""
echo "=== Analysis ==="

# Run full analysis with validation
python3 "$ANALYZER" "$WAV_FILE" \
    --pitchtrack \
    --summary \
    --temporal --cps "$CPS" --slots "$SLOTS" \
    --expect "$EXPECT"

# Also output JSON for programmatic consumption
echo ""
echo "=== JSON Output ==="
python3 "$ANALYZER" "$WAV_FILE" \
    --json \
    --cps "$CPS" --slots "$SLOTS" \
    --expect "$EXPECT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
v = data.get('validation', [])
passed = sum(1 for x in v if x['pass'])
total = len(v)
print(f'Validation: {passed}/{total} checks passed')
for x in v:
    status = 'PASS' if x['pass'] else 'FAIL'
    print(f'  [{status}] {x[\"detail\"]}')
if passed < total:
    sys.exit(1)
"

EXIT=$?
if [ $EXIT -eq 0 ]; then
    echo ""
    echo "=== PASS ==="
else
    echo ""
    echo "=== FAIL ==="
fi
exit $EXIT
