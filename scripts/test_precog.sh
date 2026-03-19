#!/bin/bash
set -e

RCON() { printf "%s\n" "$1" | nc -w 2 localhost 9999; }

pkill -9 -f "Godot.*dax" 2>/dev/null || true
sleep 1
/Applications/Godot.app/Contents/MacOS/Godot --path "/Users/jeremy/dev/dax/test123" > /tmp/godot_precog.log 2>&1 &
sleep 5

# Setup
RCON "debug"
RCON "clear"
sleep 2

RCON "spawn dummy 670 520"
sleep 1
RCON "spawn monster 960 880"
sleep 2

# Verify everything is ready before proceeding
ENEMY_COUNT=$(RCON "enemies" | head -1 | grep -o '[0-9]*')
PLAYER_COUNT=$(RCON "players" | head -1 | grep -o '[0-9]*')
printf "Verify: enemies=%s players=%s\n" "$ENEMY_COUNT" "$PLAYER_COUNT"

if [ "$ENEMY_COUNT" = "0" ]; then
    printf "ERROR: No enemy spawned. Retrying...\n"
    RCON "spawn monster 960 880"
    sleep 2
    ENEMY_COUNT=$(RCON "enemies" | head -1 | grep -o '[0-9]*')
    printf "Retry: enemies=%s\n" "$ENEMY_COUNT"
fi

if [ "$ENEMY_COUNT" = "0" ]; then
    printf "FATAL: Cannot spawn monster. Check for parse errors:\n"
    grep -a "ERROR\|Parse" /tmp/godot_precog.log | head -5
    exit 1
fi

RCON "tab 1"
STATUS=$(RCON "status")
printf "Status: %s\n" "$STATUS"

# Run test positions
POSITIONS="960_520 400_740 1400_740 200_880 670_520 1250_520"

for POS in $POSITIONS; do
    X=${POS%_*}
    Y=${POS#*_}
    printf "\n== Target at %s %s ==\n" "$X" "$Y"
    RCON "tp $X $Y"
    sleep 0.5
    RCON "precog"
    sleep 8
    grep -a "PATHFIND\|ARRIVED\|EXECUTING\|FAILED" /tmp/godot_precog.log | tail -5
    RCON "enemies"
    : > /tmp/godot_precog.log
done

printf "\n== ALL TESTS COMPLETE ==\n"
RCON "status"
