#!/bin/bash
# Edge case tests: measure TIME TO FIRST DAMAGE + total damage
set -e

R() { printf "%s\n" "$1" | nc -w 2 localhost 9999; }

pkill -9 -f "Godot.*dax" 2>/dev/null || true
sleep 1
/Applications/Godot.app/Contents/MacOS/Godot --path "/Users/jeremy/dev/dax/test123" > /tmp/godot_edge.log 2>&1 &
sleep 5

SCENARIOS="
floor_corner_left:220:870:500:870
floor_corner_right:1700:870:1400:870
cliff_ledge_left:200:580:500:870
cliff_ledge_right:1720:580:1400:870
near_corner_left:250:870:260:870
near_corner_right:1680:870:1670:870
near_cliff_left:220:580:250:750
near_cliff_right:1700:580:1680:750
"

printf "%-22s %5s %7s %5s %s\n" "SCENARIO" "DMG" "1stHIT" "FPS" "MONSTER"
printf "%-22s %5s %7s %5s %s\n" "--------" "---" "------" "---" "-------"

for SCENE in $SCENARIOS; do
    IFS=: read -r LABEL DX DY MX MY <<< "$SCENE"

    R "clear" > /dev/null 2>&1
    R "clearplayers" > /dev/null 2>&1
    sleep 1
    R "spawn dummy $DX $DY" > /dev/null 2>&1
    sleep 0.5
    R "spawn monster $MX $MY" > /dev/null 2>&1
    sleep 2
    R "resethp" > /dev/null 2>&1
    : > /tmp/godot_edge.log

    START=$(python3 -c "import time; print(time.time())")
    FIRST_HIT="NONE"

    for I in $(seq 1 20); do
        sleep 1
        HPLINE=$(R "hp")
        DMG_NOW=$(printf "%s" "$HPLINE" | grep -o 'damage_taken=[0-9]*' | cut -d= -f2)
        DMG_NOW=${DMG_NOW:-0}
        if [ "$DMG_NOW" -gt 0 ] && [ "$FIRST_HIT" = "NONE" ]; then
            NOW=$(python3 -c "import time; print(time.time())")
            FIRST_HIT=$(python3 -c "print('%.1f' % ($NOW - $START))")
        fi
    done

    HPLINE=$(R "hp")
    DMG=$(printf "%s" "$HPLINE" | grep -o 'damage_taken=[0-9]*' | cut -d= -f2)
    DMG=${DMG:-0}
    MPOS=$(R "enemies" | tail -1 | grep -o '([0-9]*,[0-9]*)' | head -1)
    END_FPS=$(R "fps" | grep -o '[0-9]*')

    printf "%-22s %5d %6ss %5s %s\n" "$LABEL" "$DMG" "$FIRST_HIT" "$END_FPS" "monster=$MPOS"
done

printf "\n=== DONE ===\n"
