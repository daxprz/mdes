#!/bin/bash
# Quick sanity check: spawn monster, verify it attacks, confirm no crashes.
# ~20 seconds total. Use after code changes to catch parse errors and basic regressions.
set -e

R() { printf "%s\n" "$1" | nc -w 2 localhost 9999; }

pkill -9 -f "Godot.*dax" 2>/dev/null || true
sleep 1
/Applications/Godot.app/Contents/MacOS/Godot --path "/Users/jeremy/dev/dax/test123" > /tmp/godot_quick.log 2>&1 &
sleep 5

# Check for parse errors
ERRORS=$(grep -c "SCRIPT ERROR\|Parse Error\|Failed to load" /tmp/godot_quick.log 2>/dev/null || true)
ERRORS=${ERRORS:-0}
if [ "$ERRORS" -gt 0 ]; then
    echo "FAIL: script errors on launch"
    grep -a "SCRIPT ERROR\|Parse Error\|Failed to load" /tmp/godot_quick.log | head -5
    exit 1
fi

R "clear"
R "clearplayers"
sleep 1
R "spawn dummy 800 880"
sleep 0.5
R "spawn monster 960 880"
sleep 2

EC=$(R "enemies" | head -1 | grep -o '[0-9]*')
if [ "$EC" = "0" ]; then
    echo "FAIL: no monster spawned"
    grep -a "ERROR\|Parse" /tmp/godot_quick.log | head -5
    exit 1
fi

R "resethp" > /dev/null
sleep 15

HPLINE=$(R "hp")
DMG=$(printf "%s" "$HPLINE" | grep -o 'damage_taken=[0-9]*' | cut -d= -f2)
DMG=${DMG:-0}
FPS=$(R "fps" | grep -o '[0-9]*')
FPS=${FPS:-0}

ERRORS2=$(grep -c "SCRIPT ERROR\|handle_crash" /tmp/godot_quick.log 2>/dev/null || true)
ERRORS2=${ERRORS2:-0}

if [ "$DMG" -gt 0 ] && [ "$FPS" -gt 20 ] && [ "$ERRORS2" = "0" ]; then
    echo "PASS: dmg=$DMG fps=$FPS errors=0"
else
    echo "FAIL: dmg=$DMG fps=$FPS errors=$ERRORS2"
    grep -a "SCRIPT ERROR\|handle_crash" /tmp/godot_quick.log | head -3
    exit 1
fi
