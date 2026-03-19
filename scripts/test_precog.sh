#!/bin/bash
# Automated quadruped monster test — all RCON commands inline via printf+nc
set -e

R() { printf "%s\n" "$1" | nc -w 2 localhost 9999; }

pkill -9 -f "Godot.*dax" 2>/dev/null || true
sleep 1
/Applications/Godot.app/Contents/MacOS/Godot --path "/Users/jeremy/dev/dax/test123" > /tmp/godot_precog.log 2>&1 &
sleep 5

R "debug"
R "clear"
sleep 2
R "spawn dummy 670 520"
sleep 1
R "spawn monster 960 880"
sleep 2

EC=$(R "enemies" | head -1 | grep -o '[0-9]*')
printf "enemies=%s\n" "$EC"
if [ "$EC" = "0" ]; then
    printf "ERROR: monster not spawned. Errors:\n"
    grep -a "ERROR\|Parse" /tmp/godot_precog.log | head -5
    exit 1
fi

R "tab 1"
R "status"

for POS in "960_520" "400_740" "1400_740" "200_880" "670_520" "1250_520"; do
    X=${POS%_*}
    Y=${POS#*_}
    printf "\n== Target at %s %s ==\n" "$X" "$Y"
    R "tp $X $Y"
    sleep 0.5
    R "precog"
    sleep 8
    grep -a "PATHFIND\|ARRIVED\|EXECUTING\|FAILED" /tmp/godot_precog.log | tail -3
    R "enemies"
    : > /tmp/godot_precog.log
done

printf "\n== ALL TESTS COMPLETE ==\n"
R "status"
