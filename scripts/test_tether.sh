#!/bin/bash
# Test: Tether system — create tethers via RCON, verify physics, sever
set -e

R() { printf "%s\n" "$1" | nc -w 2 localhost 9999; }

echo "=== Tether Test Suite ==="

pkill -9 -f "Godot.*dax" 2>/dev/null || true
sleep 1
/Applications/Godot.app/Contents/MacOS/Godot --path "/Users/jeremy/dev/dax/test123" > /tmp/godot_tether_test.log 2>&1 &
sleep 5

R "clear"
R "clearplayers"
sleep 1
R "spawn dummy 1600 880"
sleep 0.5
R "spawn monster 960 880"
sleep 2
R "standdown on"
sleep 0.5

echo "Setup OK"
echo ""

# --- Test 1: Tether enemy to floor ---
echo "--- Test 1: Enemy Head to Floor ---"
R "tether 0 head floor 80"
sleep 1
STATUS=$(R "tether status")
echo "  $STATUS"
TCOUNT=$(echo "$STATUS" | head -1 | grep -o '[0-9]*')
if [ "$TCOUNT" = "1" ]; then echo "  PASS: tether created"; else echo "  FAIL: expected 1 tether"; fi

# --- Test 2: Tether holds against balloons ---
echo ""
echo "--- Test 2: Tether vs Balloons ---"
EPOS1=$(R "enemies" | tail -1 | grep -o '([0-9]*,[0-9]*)' | head -1)
R "attach balloon head"
R "attach balloon head"
R "attach balloon head"
sleep 3
EPOS2=$(R "enemies" | tail -1 | grep -o '([0-9]*,[0-9]*)' | head -1)
echo "  Before balloons: $EPOS1"
echo "  After 3 balloons: $EPOS2"
# Monster should not have floated away significantly
Y1=$(echo "$EPOS1" | grep -o ',[0-9]*' | tr -d ',')
Y2=$(echo "$EPOS2" | grep -o ',[0-9]*' | tr -d ',')
Y1=${Y1:-890}
Y2=${Y2:-890}
DIFF=$((Y1 - Y2))
if [ "$DIFF" -lt 50 ]; then echo "  PASS: tether held (Y diff=$DIFF)"; else echo "  FAIL: monster floated (Y diff=$DIFF)"; fi

# --- Test 3: Tether status ---
echo ""
echo "--- Test 3: Tether Status ---"
STATUS=$(R "tether status")
echo "$STATUS" | head -5
if echo "$STATUS" | grep -q "tension"; then echo "  PASS: status shows tension"; else echo "  FAIL"; fi

# --- Test 4: Set tether length ---
echo ""
echo "--- Test 4: Adjust Length ---"
R "tether length 40"
sleep 1
STATUS=$(R "tether status")
LEN=$(echo "$STATUS" | grep -o '/[0-9]*' | head -1 | tr -d '/')
echo "  Target length: $LEN"
if [ "$LEN" = "40" ]; then echo "  PASS"; else echo "  WARN: expected 40, got $LEN"; fi

# --- Test 5: Sever tether ---
echo ""
echo "--- Test 5: Cut Tether ---"
R "tether cut"
sleep 0.5
STATUS=$(R "tether status")
TCOUNT=$(echo "$STATUS" | head -1 | grep -o '[0-9]*')
echo "  After cut: $TCOUNT tethers"
if [ "$TCOUNT" = "0" ]; then echo "  PASS"; else echo "  FAIL"; fi

# --- Test 6: Wall to wall tether ---
echo ""
echo "--- Test 6: Wall-to-Wall ---"
R "tether wall 400 500 1400 500 600"
sleep 1
STATUS=$(R "tether status")
echo "  $STATUS"
if echo "$STATUS" | grep -q "wall"; then echo "  PASS"; else echo "  FAIL"; fi
R "tether cut"

# --- Test 7: Multiple tethers ---
echo ""
echo "--- Test 7: Multiple Tethers ---"
R "tether 0 head floor 100"
R "tether 0 tail_tip floor 100"
R "tether 0 shoulders floor 100"
sleep 1
STATUS=$(R "tether status")
TCOUNT=$(echo "$STATUS" | head -1 | grep -o '[0-9]*')
echo "  Created 3 tethers: $TCOUNT"
if [ "$TCOUNT" = "3" ]; then echo "  PASS"; else echo "  FAIL"; fi
R "tether cut"

echo ""
echo "=== Tether Test Complete ==="
grep -a "ERROR\|SCRIPT ERROR" /tmp/godot_tether_test.log | head -5 || echo "(no errors)"
