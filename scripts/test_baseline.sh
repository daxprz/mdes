#!/bin/bash
# Baseline: damage + FPS + IK quality per scenario
set -e

R() { printf "%s\n" "$1" | nc -w 2 localhost 9999; }

pkill -9 -f "Godot.*dax" 2>/dev/null || true
sleep 1
/Applications/Godot.app/Contents/MacOS/Godot --path "/Users/jeremy/dev/dax/test123" > /tmp/godot_baseline.log 2>&1 &
sleep 5

R "debug"
R "clear"
sleep 2
R "spawn dummy 670 520"
sleep 1
R "spawn monster 960 880"
sleep 2

EC=$(R "enemies" | head -1 | grep -o '[0-9]*')
if [ "$EC" = "0" ]; then
    printf "FATAL: no monster\n"
    grep -a "ERROR\|Parse" /tmp/godot_baseline.log | head -5
    exit 1
fi
R "tab 1"
sleep 2

INIT_FPS=$(R "fps" | grep -o '[0-9]*')
printf "Initial FPS: %s\n\n" "$INIT_FPS"

SCENARIOS="
same_floor_near:800:885:0
same_floor_far:200:885:0
on_P1:550:745:1
on_P2:1400:745:1
on_P3:670:525:1
on_P4:1250:525:1
floor_to_P3:670:525:1
cross_P1_to_P2:1400:745:1
P1_to_P3:670:525:1
P2_to_P4:1250:525:1
"

TOTAL_DMG=0
PASS=0
FAIL=0
MIN_FPS=999
WORST_IK=0

printf "%-20s %5s %5s %5s %7s %s\n" "SCENARIO" "DMG" "FPS" "mnFPS" "IK_AVG" "MONSTER_POS"
printf "%-20s %5s %5s %5s %7s %s\n" "--------" "---" "---" "-----" "------" "-----------"

for SCENE in $SCENARIOS; do
    IFS=: read -r LABEL X Y FORCE <<< "$SCENE"

    R "tp $X $Y" > /dev/null 2>&1
    R "resethp" > /dev/null 2>&1
    R "ikreset" > /dev/null 2>&1
    : > /tmp/godot_baseline.log
    sleep 0.3
    if [ "$FORCE" = "1" ]; then
        R "precog" > /dev/null 2>&1
    fi

    SCENARIO_MIN_FPS=999
    for I in $(seq 1 15); do
        sleep 1
        FPS=$(R "fps" | grep -o '[0-9]*')
        FPS=${FPS:-0}
        if [ "$FPS" -lt "$SCENARIO_MIN_FPS" ]; then SCENARIO_MIN_FPS=$FPS; fi
        if [ "$FPS" -lt "$MIN_FPS" ]; then MIN_FPS=$FPS; fi
    done

    HPLINE=$(R "hp")
    DMG=$(printf "%s" "$HPLINE" | grep -o 'damage_taken=[0-9]*' | cut -d= -f2)
    DMG=${DMG:-0}
    MPOS=$(R "enemies" | tail -1 | grep -o '([0-9]*,[0-9]*)' | head -1)
    IKLINE=$(R "ik")
    IK_AVG=$(printf "%s" "$IKLINE" | grep -o 'ik_avg=[0-9]*' | cut -d= -f2)
    IK_AVG=${IK_AVG:-0}
    IK_PEAK=$(printf "%s" "$IKLINE" | grep -o 'ik_peak=[0-9]*' | cut -d= -f2)
    IK_PEAK=${IK_PEAK:-0}

    if [ "$DMG" -gt 0 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); fi
    TOTAL_DMG=$((TOTAL_DMG + DMG))
    if [ "$IK_PEAK" -gt "$WORST_IK" ]; then WORST_IK=$IK_PEAK; fi

    printf "%-20s %5d %5s %5d %4d/%d %s\n" "$LABEL" "$DMG" "$(R 'fps' | grep -o '[0-9]*')" "$SCENARIO_MIN_FPS" "$IK_AVG" "$IK_PEAK" "monster=$MPOS"
done

printf "\n=== SUMMARY: %d/%d hit, dmg=%d, min_fps=%d, worst_ik=%d ===\n" "$PASS" "$((PASS + FAIL))" "$TOTAL_DMG" "$MIN_FPS" "$WORST_IK"
