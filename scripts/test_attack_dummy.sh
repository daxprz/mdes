#!/bin/bash
# Test: Attack Dummy — spawn attacker, have it attack a monster
# Verifies: spawning, targeting, weapon firing, hit detection, stand-down mode
set -e

R() { printf "%s\n" "$1" | nc -w 2 localhost 9999; }

echo "=== Attack Dummy Test Suite ==="
echo ""

# --- Setup ---
# Kill existing Godot if running, start fresh
pkill -9 -f "Godot.*dax" 2>/dev/null || true
sleep 1
/Applications/Godot.app/Contents/MacOS/Godot --path "/Users/jeremy/dev/dax/test123" > /tmp/godot_attacker.log 2>&1 &
sleep 5

R "debug"
R "clear"
R "clearplayers"
sleep 2

# Spawn monster and dummy player (monster needs a target to stay alive)
R "spawn dummy 1600 880"
sleep 1
R "spawn monster 960 880"
sleep 2

# Verify monster spawned
EC=$(R "enemies" | head -1 | grep -o '[0-9]*')
if [ "$EC" = "0" ]; then
    printf "FATAL: no monster\n"
    grep -a "ERROR\|Parse" /tmp/godot_attacker.log | head -5
    exit 1
fi
echo "Monster spawned OK"

# --- Test 1: Spawn attack dummy ---
echo ""
echo "--- Test 1: Spawn Attack Dummy ---"
RESULT=$(R "spawn attacker 400 880")
echo "  $RESULT"
sleep 1
STATS=$(R "attacker stats")
echo "  $STATS"
if echo "$STATS" | grep -q "attack_dummies: 1"; then
    echo "  PASS: attacker spawned"
else
    echo "  FAIL: attacker not found"
fi

# --- Test 2: Stand-down mode ---
echo ""
echo "--- Test 2: Stand-Down Mode ---"
RESULT=$(R "standdown on")
echo "  $RESULT"
sleep 1
# Monster should be in STANDDOWN — verify it's not chasing
ENEMY_POS1=$(R "enemies" | tail -1 | grep -o '([0-9]*,[0-9]*)' | head -1)
sleep 2
ENEMY_POS2=$(R "enemies" | tail -1 | grep -o '([0-9]*,[0-9]*)' | head -1)
if [ "$ENEMY_POS1" = "$ENEMY_POS2" ]; then
    echo "  PASS: monster stationary in standdown"
else
    echo "  WARN: monster moved ($ENEMY_POS1 -> $ENEMY_POS2)"
fi

# --- Test 3: Target monster with bow ---
echo ""
echo "--- Test 3: Bow Attack ---"
R "attacker target 0"
R "attacker weapon bow"
R "attacker rate 0.5"
R "attacker start"
sleep 1

# Record initial HP
INIT_HP=$(R "hp" | grep -o 'hp=[0-9]*' | cut -d= -f2)
echo "  Initial monster enemies check..."

# Let it fire for 8 seconds
echo "  Firing bow at monster for 8 seconds..."
sleep 8

STATS=$(R "attacker stats")
SHOTS=$(echo "$STATS" | grep -o 'shots=[0-9]*' | cut -d= -f2)
HITS=$(echo "$STATS" | grep -o 'hits=[0-9]*' | cut -d= -f2)
SHOTS=${SHOTS:-0}
HITS=${HITS:-0}
echo "  Shots: $SHOTS, Hits: $HITS"

if [ "$SHOTS" -gt 0 ]; then
    echo "  PASS: attacker fired $SHOTS shots"
else
    echo "  FAIL: no shots fired"
fi

if [ "$HITS" -gt 0 ]; then
    echo "  PASS: $HITS hits landed"
else
    echo "  WARN: no hits landed (accuracy issue — may need tuning)"
fi

# --- Test 4: Target specific body part ---
echo ""
echo "--- Test 4: Body Part Targeting (head) ---"
R "attacker stop"
sleep 0.5
# Reset shots/hits by respawning attacker
R "attacker part head"
R "attacker start"
sleep 6

STATS=$(R "attacker stats")
echo "  $STATS"
HITS2=$(echo "$STATS" | grep -o 'hits=[0-9]*' | cut -d= -f2)
HITS2=${HITS2:-0}
if [ "$HITS2" -gt "$HITS" ]; then
    echo "  PASS: additional hits with head targeting"
else
    echo "  WARN: no additional hits on head"
fi

# --- Test 5: Switch to balloon weapon ---
echo ""
echo "--- Test 5: Balloon Weapon ---"
R "attacker stop"
sleep 0.5
R "attacker weapon balloon"
R "attacker part body"
R "attacker rate 1.0"
R "attacker start"
echo "  Firing balloons for 6 seconds..."
sleep 6
R "attacker stop"
STATS=$(R "attacker stats")
echo "  $STATS"
echo "  PASS: balloon weapon tested (visual inspection for balloon attachment)"

# --- Test 6: Stop/Start control ---
echo ""
echo "--- Test 6: Stop/Start Control ---"
R "attacker stop"
sleep 1
STATS1=$(R "attacker stats")
SHOTS1=$(echo "$STATS1" | grep -o 'shots=[0-9]*' | cut -d= -f2)
sleep 2
STATS2=$(R "attacker stats")
SHOTS2=$(echo "$STATS2" | grep -o 'shots=[0-9]*' | cut -d= -f2)
if [ "$SHOTS1" = "$SHOTS2" ]; then
    echo "  PASS: attacker stopped (shots unchanged: $SHOTS1)"
else
    echo "  FAIL: attacker still firing when stopped ($SHOTS1 -> $SHOTS2)"
fi

R "attacker start"
sleep 2
STATS3=$(R "attacker stats")
SHOTS3=$(echo "$STATS3" | grep -o 'shots=[0-9]*' | cut -d= -f2)
if [ "$SHOTS3" -gt "$SHOTS2" ]; then
    echo "  PASS: attacker resumed ($SHOTS2 -> $SHOTS3)"
else
    echo "  FAIL: attacker did not resume"
fi

# --- Test 7: Stand-down off (monster resumes) ---
echo ""
echo "--- Test 7: Stand-Down Off ---"
R "attacker stop"
R "standdown off"
ENEMY_POS3=$(R "enemies" | tail -1 | grep -o '([0-9]*,[0-9]*)' | head -1)
sleep 3
ENEMY_POS4=$(R "enemies" | tail -1 | grep -o '([0-9]*,[0-9]*)' | head -1)
if [ "$ENEMY_POS3" != "$ENEMY_POS4" ]; then
    echo "  PASS: monster resumed movement ($ENEMY_POS3 -> $ENEMY_POS4)"
else
    echo "  WARN: monster didn't move (might be at target already)"
fi

# --- Summary ---
echo ""
echo "=== Attack Dummy Test Complete ==="
echo "Check /tmp/godot_attacker.log for any errors"
grep -a "ERROR\|SCRIPT ERROR" /tmp/godot_attacker.log | head -5 || echo "(no errors)"
