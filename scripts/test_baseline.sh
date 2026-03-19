#!/bin/bash
# Baseline: measure damage dealt to dummy in 20s per scenario
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
sleep 1

SCENARIOS="
same_floor_near:800:885
same_floor_far:200:885
on_P1:550:745
on_P2:1400:745
on_P3:670:525
on_P4:1250:525
floor_to_P3:670:525
cross_P1_to_P2:1400:745
P1_to_P3:670:525
P2_to_P4:1250:525
"

TOTAL_DMG=0
PASS=0
FAIL=0

printf "%-20s %6s %6s %s\n" "SCENARIO" "DMG" "TIME" "MONSTER_POS"
printf "%-20s %6s %6s %s\n" "--------" "---" "----" "-----------"

for SCENE in $SCENARIOS; do
    LABEL=${SCENE%%:*}
    REST=${SCENE#*:}
    X=${REST%%:*}
    Y=${REST#*:}

    R "tp $X $Y" > /dev/null 2>&1
    R "resethp" > /dev/null 2>&1
    : > /tmp/godot_baseline.log
    sleep 0.3
    R "precog" > /dev/null 2>&1
    sleep 15
    HPLINE=$(R "hp")
    DMG=$(printf "%s" "$HPLINE" | grep -o 'damage_taken=[0-9]*' | cut -d= -f2)
    DMG=${DMG:-0}
    MPOS=$(R "enemies" | tail -1 | grep -o '([0-9]*,[0-9]*)' | head -1)

    if [ "$DMG" -gt 0 ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    TOTAL_DMG=$((TOTAL_DMG + DMG))

    printf "%-20s %5d %5ss %s\n" "$LABEL" "$DMG" "15" "monster=$MPOS"
done

printf "\n=== SUMMARY: %d/%d passed, total damage=%d ===\n" "$PASS" "$((PASS + FAIL))" "$TOTAL_DMG"
