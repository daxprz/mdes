#!/bin/bash
# Test: Damage system — weak spots, tiered damage states, gameplay penalties
set -e

R() { printf "%s\n" "$1" | nc -w 2 localhost 9999; }

echo "=== Damage & Weak Spots Test Suite ==="

pkill -9 -f "Godot.*dax" 2>/dev/null || true
sleep 1
/Applications/Godot.app/Contents/MacOS/Godot --path "/Users/jeremy/dev/dax/test123" > /tmp/godot_damage.log 2>&1 &
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
R "spawn attacker 400 880"
sleep 1
R "attacker target 0"

# Verify setup
EC=$(R "enemies" | head -1 | grep -o '[0-9]*')
if [ "$EC" = "0" ]; then
    echo "FATAL: no monster"
    grep -a "ERROR\|Parse" /tmp/godot_damage.log | head -5
    exit 1
fi
echo "Setup OK: monster in standdown, attacker spawned"
echo ""

# --- Test 1: Part damage states ---
echo "--- Test 1: Damage State Thresholds ---"
# Head: 60 HP. Medium at <40 (66%), High at <20 (33%)
R "partdmg head 25" > /dev/null
sleep 0.3
STATUS=$(R "partstatus" | grep "head:")
HP=$(echo "$STATUS" | grep -o '[0-9]*/60' | cut -d/ -f1)
STATE=$(echo "$STATUS" | grep -o '(MEDIUM)\|(HIGH)\|(NONE)')
echo "  Head after 25 dmg: $HP/60 $STATE"
if echo "$STATE" | grep -q "MEDIUM"; then echo "  PASS"; else echo "  FAIL: expected MEDIUM"; fi

R "partdmg head 25" > /dev/null
sleep 0.3
STATUS=$(R "partstatus" | grep "head:")
STATE=$(echo "$STATUS" | grep -o '(MEDIUM)\|(HIGH)\|(NONE)')
echo "  Head after 50 dmg: $STATE"
if echo "$STATE" | grep -q "HIGH"; then echo "  PASS"; else echo "  FAIL: expected HIGH"; fi

# --- Test 2: Tail damage disables grab ---
echo ""
echo "--- Test 2: Tail → Grab Disabled ---"
GRAB_BEFORE=$(R "partstatus" | grep "grab_disabled" | grep -o 'true\|false')
echo "  grab_disabled before: $GRAB_BEFORE"
R "partdmg tail 40" > /dev/null
sleep 0.3
GRAB_AFTER=$(R "partstatus" | grep "grab_disabled" | grep -o 'true\|false')
echo "  grab_disabled after 40 dmg to tail: $GRAB_AFTER"
if [ "$GRAB_AFTER" = "true" ]; then echo "  PASS"; else echo "  FAIL"; fi

# --- Test 3: Torso damage → continuous bleeding ---
echo ""
echo "--- Test 3: Torso → Bleeding ---"
BLEED_BEFORE=$(R "partstatus" | grep "torso_bleeding" | grep -o 'true\|false')
echo "  bleeding before: $BLEED_BEFORE"
R "partdmg body 160" > /dev/null
sleep 0.3
BLEED_AFTER=$(R "partstatus" | grep "torso_bleeding" | grep -o 'true\|false')
echo "  bleeding after 160 dmg to body: $BLEED_AFTER"
if [ "$BLEED_AFTER" = "true" ]; then echo "  PASS"; else echo "  FAIL"; fi

# --- Test 4: Leg damage → leap reduction ---
echo ""
echo "--- Test 4: Rear Legs → Leap Reduction ---"
R "partdmg leg2 30" > /dev/null
sleep 0.3
MULT1=$(R "partstatus" | grep "leap_mult" | grep -o 'leap_mult=[0-9.]*' | cut -d= -f2)
echo "  1 rear leg HIGH: leap_mult=$MULT1"
if [ "$MULT1" = "0.75" ]; then echo "  PASS"; else echo "  FAIL: expected 0.75"; fi

R "partdmg leg3 30" > /dev/null
sleep 0.3
MULT2=$(R "partstatus" | grep "leap_mult" | grep -o 'leap_mult=[0-9.]*' | cut -d= -f2)
echo "  2 rear legs HIGH: leap_mult=$MULT2"
if [ "$MULT2" = "0.50" ]; then echo "  PASS"; else echo "  FAIL: expected 0.50"; fi

# --- Test 5: Arm damage → slash reduction ---
echo ""
echo "--- Test 5: Arms → Slash Reduction ---"
R "partdmg leg0 30" > /dev/null
sleep 0.3
SMULT1=$(R "partstatus" | grep "slash_mult" | grep -o 'slash_mult=[0-9.]*' | cut -d= -f2)
echo "  1 arm HIGH: slash_mult=$SMULT1"
if [ "$SMULT1" = "0.50" ]; then echo "  PASS"; else echo "  FAIL: expected 0.50"; fi

R "partdmg leg1 30" > /dev/null
sleep 0.3
SMULT2=$(R "partstatus" | grep "slash_mult" | grep -o 'slash_mult=[0-9.]*' | cut -d= -f2)
echo "  2 arms HIGH: slash_mult=$SMULT2"
if [ "$SMULT2" = "0.25" ]; then echo "  PASS"; else echo "  FAIL: expected 0.25"; fi

# --- Test 6: Attack dummy fires at monster ---
echo ""
echo "--- Test 6: Attack Dummy → Monster ---"
# Respawn fresh monster for attack test
R "clear"
R "portal off"
sleep 0.5
R "spawn monster 960 880"
sleep 1
R "standdown on"
sleep 0.5
R "attacker target 0"
R "attacker weapon bow"
R "attacker part head"
R "attacker rate 0.5"
R "attacker start"
echo "  Firing at head for 6 seconds..."
sleep 6
STATS=$(R "attacker stats")
HITS=$(echo "$STATS" | grep -o 'hits=[0-9]*' | cut -d= -f2)
HITS=${HITS:-0}
echo "  Hits: $HITS"
if [ "$HITS" -gt 0 ]; then echo "  PASS: landed $HITS hits"; else echo "  WARN: no hits"; fi

# Check that head took damage
HSTATUS=$(R "partstatus" | grep "head:")
echo "  $HSTATUS"

echo ""
echo "=== Damage Test Complete ==="
grep -a "ERROR\|SCRIPT ERROR" /tmp/godot_damage.log | head -5 || echo "(no errors)"
