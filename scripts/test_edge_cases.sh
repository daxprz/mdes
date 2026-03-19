#!/bin/bash
# Edge case tests: corners + cliff edges. Full map reset each scenario.
set -e

R() { printf "%s\n" "$1" | nc -w 2 localhost 9999; }

pkill -9 -f "Godot.*dax" 2>/dev/null || true
sleep 1
/Applications/Godot.app/Contents/MacOS/Godot --path "/Users/jeremy/dev/dax/test123" > /tmp/godot_edge.log 2>&1 &
sleep 5

# Positions: cave wall curve starts ~180px from edges
# Cliff ledge at ~1/3 height (y~600) on each side
# Floor corners where cave wall meets floor (x~200, y~880)
# Monster starts on floor center, must reach target

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

printf "%-22s %5s %5s %5s %s\n" "SCENARIO" "DMG" "FPS" "mnFPS" "MONSTER"
printf "%-22s %5s %5s %5s %s\n" "--------" "---" "---" "-----" "-------"

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

    SCENARIO_MIN_FPS=999
    for I in $(seq 1 15); do
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

    printf "%-22s %5d %5s %5d %s\n" "$LABEL" "$DMG" "$END_FPS" "$SCENARIO_MIN_FPS" "monster=$MPOS"
    grep -a "PATHFIND\|EXECUTING\|ARRIVED\|hop\|SPRINT" /tmp/godot_edge.log | tail -3
    printf "\n"
done

printf "=== DONE ===\n"
