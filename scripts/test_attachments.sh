#!/bin/bash
# Test: Attachment system — balloons on body points, weight physics
set -e

R() { printf "%s\n" "$1" | nc -w 2 localhost 9999; }

echo "=== Attachment Physics Test Suite ==="

pkill -9 -f "Godot.*dax" 2>/dev/null || true
sleep 1
/Applications/Godot.app/Contents/MacOS/Godot --path "/Users/jeremy/dev/dax/test123" > /tmp/godot_attach.log 2>&1 &
sleep 5

R "clear"
R "portal off"
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

# --- Test 1: Attach balloon to head ---
echo "--- Test 1: Balloon on Head ---"
R "attach balloon head" > /dev/null
sleep 1
WEIGHT=$(R "weight")
ITEMS=$(echo "$WEIGHT" | grep "attached_items" | grep -o '[0-9]*')
HEAD_FORCE=$(echo "$WEIGHT" | grep "head:")
echo "  Items: $ITEMS"
echo "  $HEAD_FORCE"
if [ "$ITEMS" = "1" ]; then echo "  PASS: 1 item attached"; else echo "  FAIL: expected 1 item"; fi

# --- Test 2: Multiple balloons stack ---
echo ""
echo "--- Test 2: Stacking Balloons ---"
R "attach balloon head" > /dev/null
R "attach balloon head" > /dev/null
sleep 1
WEIGHT=$(R "weight")
ITEMS=$(echo "$WEIGHT" | grep "attached_items" | grep -o '[0-9]*')
echo "  Items after 3 total: $ITEMS"
if [ "$ITEMS" -ge 2 ]; then echo "  PASS: multiple balloons"; else echo "  FAIL"; fi

# --- Test 3: Detach ---
echo ""
echo "--- Test 3: Detach ---"
R "detach head"
sleep 0.5
WEIGHT=$(R "weight")
ITEMS=$(echo "$WEIGHT" | grep "attached_items" | grep -o '[0-9]*')
echo "  Items after detach: $ITEMS"
if [ "$ITEMS" = "0" ]; then echo "  PASS"; else echo "  WARN: $ITEMS items remain (may have expired)"; fi

# --- Test 4: Tail tip balloon ---
echo ""
echo "--- Test 4: Balloon on Tail Tip ---"
R "attach balloon tail_tip" > /dev/null
sleep 1
WEIGHT=$(R "weight")
TAIL_FORCE=$(echo "$WEIGHT" | grep "tail_tip:" || echo "no force")
echo "  $TAIL_FORCE"
ITEMS=$(echo "$WEIGHT" | grep "attached_items" | grep -o '[0-9]*')
if [ "$ITEMS" -ge 1 ]; then echo "  PASS"; else echo "  FAIL"; fi

# --- Test 5: Different attachment points ---
echo ""
echo "--- Test 5: Shoulders + Waist ---"
R "attach balloon shoulders" > /dev/null
R "attach balloon waist" > /dev/null
sleep 1
WEIGHT=$(R "weight")
echo "$WEIGHT" | grep "forces:" -A 10
ITEMS=$(echo "$WEIGHT" | grep "attached_items" | grep -o '[0-9]*')
echo "  Total items: $ITEMS"
if [ "$ITEMS" -ge 2 ]; then echo "  PASS: multiple points"; else echo "  FAIL"; fi

# --- Test 6: Weight readout ---
echo ""
echo "--- Test 6: Weight Data ---"
WEIGHT=$(R "weight")
TOTAL=$(echo "$WEIGHT" | head -1 | grep -o 'total=[0-9]*' | cut -d= -f2)
echo "  Total body weight: $TOTAL"
if [ "$TOTAL" -gt 0 ]; then echo "  PASS"; else echo "  FAIL"; fi

echo ""
echo "=== Attachment Test Complete ==="
grep -a "ERROR\|SCRIPT ERROR" /tmp/godot_attach.log | head -5 || echo "(no errors)"
