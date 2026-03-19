#!/bin/bash
# Edge case tests: corners + cliff edges. Full map reset each scenario.
set -e

R() { printf "%s\n" "$1" | nc -w 2 localhost 9999; }

pkill -9 -f "Godot.*dax" 2>/dev/null || true
sleep 1
/Applications/Godot.app/Contents/MacOS/Godot --path "/Users/jeremy/dev/dax/test123" > /tmp/godot_edge.log 2>&1 &
sleep 5

# Scenarios: label:dummy_x:dummy_y:monster_x:monster_y
# Monster positioned VERY NEAR the target
SCENARIOS="
corner_left:100:885:120:885
corner_right:1800:885:1780:885
cliff_left:120:600:140:885
cliff_right:1780:600:1760:885
corner_left_overlap:100:885:100:885
corner_right_overlap:1800:885:1800:885
cliff_left_close:120:600:120:750
cliff_right_close:1780:600:1780:750
"

printf "%-22s %5s %5s %5s %s\n" "SCENARIO" "DMG" "FPS" "mnFPS" "MONSTER"
printf "%-22s %5s %5s %5s %s\n" "--------" "---" "---" "-----" "-------"

for SCENE in $SCENARIOS; do
    IFS=: read -r LABEL DX DY MX MY <<< "$SCENE"

    # FULL RESET: kill everything, clear, respawn fresh
    R "clear" > /dev/null 2>&1
    R "clearplayers" > /dev/null 2>&1
    sleep 1
    R "spawn dummy $DX $DY" > /dev/null 2>&1
    sleep 0.5
    R "spawn monster $MX $MY" > /dev/null 2>&1
    sleep 2
    R "resethp" > /dev/null 2>&1
    : > /tmp/godot_edge.log

    # Let it run for 15 seconds
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

    # Show what the monster tried
    grep -a "PATHFIND\|EXECUTING\|ARRIVED\|SPRINT\|hop" /tmp/godot_edge.log | tail -3
    printf "\n"
done

printf "=== DONE ===\n"
