#!/bin/bash
set -e

RCON() { printf "%s\n" "$1" | nc -w 2 localhost 9999; }

pkill -9 -f "Godot.*dax" 2>/dev/null || true
sleep 1
/Applications/Godot.app/Contents/MacOS/Godot --path "/Users/jeremy/dev/dax/test123" > /tmp/godot_precog.log 2>&1 &
sleep 5

RCON "debug"
RCON "spawn dummy 670 520"
sleep 0.5
RCON "spawn monster 960 880"
sleep 1
RCON "tab 6"
RCON "status"

POSITIONS="960_520 400_740 1400_740 200_880 1600_880 670_520 1250_520"

for POS in $POSITIONS; do
    X=${POS%_*}
    Y=${POS#*_}
    printf "\n== TP dummy to %s %s ==\n" "$X" "$Y"
    RCON "tp $X $Y"
    sleep 1
    RCON "precog"
    sleep 6
    grep -a "PATH\|ARRIVED\|EXECUTING\|FAILED" /tmp/godot_precog.log | tail -3
    : > /tmp/godot_precog.log
done

printf "\n== DONE ==\n"
RCON "status"
