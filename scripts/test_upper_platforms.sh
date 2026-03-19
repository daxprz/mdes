#!/bin/bash
# Focused test: monster on floor, dummy on upper platforms
# Tests the hardest scenario — climbing from floor to upper level
set -e

R() { printf "%s\n" "$1" | nc -w 2 localhost 9999; }

pkill -9 -f "Godot.*dax" 2>/dev/null || true
sleep 1
/Applications/Godot.app/Contents/MacOS/Godot --path "/Users/jeremy/dev/dax/test123" > /tmp/godot_upper.log 2>&1 &
sleep 5

R "debug"
R "clear"
sleep 2

# Each scenario: clear everything, spawn fresh monster on floor, dummy on upper platform
SCENARIOS="
P3_center:670:525:500:880
P3_left:530:525:300:880
P3_right:770:525:900:880
P4_center:1250:525:1500:880
P4_left:1130:525:1400:880
P4_right:1370:525:960:880
P3_from_P1:670:525:550:745
P4_from_P2:1250:525:1400:745
"

printf "%-18s %5s %5s %5s %s\n" "SCENARIO" "DMG" "FPS" "mnFPS" "MONSTER"
printf "%-18s %5s %5s %5s %s\n" "--------" "---" "---" "-----" "-------"

for SCENE in $SCENARIOS; do
    IFS=: read -r LABEL DX DY MX MY <<< "$SCENE"

    # Fresh setup: clear everything, spawn new pair
    R "clear" > /dev/null 2>&1
    R "clearplayers" > /dev/null 2>&1
    sleep 1
    R "spawn dummy $DX $DY" > /dev/null 2>&1
    sleep 0.5
    R "spawn monster $MX $MY" > /dev/null 2>&1
    sleep 2
    R "tab 1" > /dev/null 2>&1
    R "resethp" > /dev/null 2>&1
    : > /tmp/godot_upper.log
    R "precog" > /dev/null 2>&1

    SCENARIO_MIN_FPS=999
    for I in $(seq 1 20); do
        sleep 1
        FPS=$(R "fps" | grep -o '[0-9]*')
        FPS=${FPS:-0}
        if [ "$FPS" -lt "$SCENARIO_MIN_FPS" ]; then SCENARIO_MIN_FPS=$FPS; fi
    done

    HPLINE=$(R "hp")
    DMG=$(printf "%s" "$HPLINE" | grep -o 'damage_taken=[0-9]*' | cut -d= -f2)
    DMG=${DMG:-0}
    MPOS=$(R "enemies" | tail -1 | grep -o '([0-9]*,[0-9]*)' | head -1)
    END_FPS=$(R "fps" | grep -o '[0-9]*')

    printf "%-18s %5d %5s %5d %s\n" "$LABEL" "$DMG" "$END_FPS" "$SCENARIO_MIN_FPS" "monster=$MPOS"
    grep -a "PRECOG\|EXECUTING\|PATHFIND\|PATH \[" /tmp/godot_upper.log | tail -3
    printf "\n"
done

printf "=== DONE ===\n"
