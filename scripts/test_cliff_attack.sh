#!/bin/bash
# Cliff attack tests: dummy on cliff edges, monster at center
set -e

R() { printf "%s\n" "$1" | nc -w 2 localhost 9999; }

pkill -9 -f "Godot.*dax" 2>/dev/null || true
sleep 1
/Applications/Godot.app/Contents/MacOS/Godot --path "/Users/jeremy/dev/dax/test123" > /tmp/godot_cliff.log 2>&1 &
sleep 5

# Cave wall ledges are at ~y=603, x≈55 (left) and x≈1865 (right)
# Drop dummy from above the ledge so it lands on the surface
SCENARIOS="
cliff_left:60:500:960:880
cliff_right:1860:500:960:880
"

printf "%-22s %5s %6s %5s %6s %6s %s\n" "SCENARIO" "DMG" "1stHIT" "FPS" "BALL" "IK" "MONSTER"
printf "%-22s %5s %6s %5s %6s %6s %s\n" "--------" "---" "------" "---" "----" "--" "-------"

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
    R "ikreset" > /dev/null 2>&1
    : > /tmp/godot_cliff.log

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

    BALLLINE=$(R "ball")
    BALL_PK=$(printf "%s" "$BALLLINE" | grep -o 'ball_peak=[0-9]*' | cut -d= -f2)
    BALL_PK=${BALL_PK:-0}

    IKLINE=$(R "ik")
    IK_PK=$(printf "%s" "$IKLINE" | grep -o 'ik_peak=[0-9]*' | cut -d= -f2)
    IK_PK=${IK_PK:-0}

    printf "%-22s %5d %5ss %5s %5d %5d %s\n" "$LABEL" "$DMG" "$FIRST_HIT" "$END_FPS" "$BALL_PK" "$IK_PK" "monster=$MPOS"

    grep -a "PATHFIND\|EXECUTING\|ARRIVED\|hop\|SPRINT\|GRAB" /tmp/godot_cliff.log | tail -5
    printf "\n"
done

printf "=== DONE ===\n"
