#!/bin/bash
# FULL TEST SUITE: baseline + edge cases + cliff attacks
# Scores: DMG, 1stHIT, FPS, BALL, IK, THRASH
set -e

R() { printf "%s\n" "$1" | nc -w 2 localhost 9999; }

pkill -9 -f "Godot.*dax" 2>/dev/null || true
sleep 1
/Applications/Godot.app/Contents/MacOS/Godot --path "/Users/jeremy/dev/dax/test123" > /tmp/godot_all.log 2>&1 &
sleep 5

run_scenario() {
    local LABEL=$1 DX=$2 DY=$3 MX=$4 MY=$5 FORCE_PRECOG=$6

    R "clear" > /dev/null 2>&1
    R "clearplayers" > /dev/null 2>&1
    sleep 1
    R "spawn dummy $DX $DY" > /dev/null 2>&1
    sleep 0.5
    R "spawn monster $MX $MY" > /dev/null 2>&1
    sleep 2
    R "resethp" > /dev/null 2>&1
    R "ikreset" > /dev/null 2>&1
    : > /tmp/godot_all.log
    if [ "$FORCE_PRECOG" = "1" ]; then
        R "precog" > /dev/null 2>&1
    fi

    local START=$(python3 -c "import time; print(time.time())")
    local FIRST_HIT="NONE"
    local SCENARIO_MIN_FPS=999

    for I in $(seq 1 20); do
        sleep 1
        local FPS=$(R "fps" | grep -o '[0-9]*')
        FPS=${FPS:-0}
        if [ "$FPS" -lt "$SCENARIO_MIN_FPS" ]; then SCENARIO_MIN_FPS=$FPS; fi
        local HPLINE=$(R "hp")
        local DMG_NOW=$(printf "%s" "$HPLINE" | grep -o 'damage_taken=[0-9]*' | cut -d= -f2)
        DMG_NOW=${DMG_NOW:-0}
        if [ "$DMG_NOW" -gt 0 ] && [ "$FIRST_HIT" = "NONE" ]; then
            local NOW=$(python3 -c "import time; print(time.time())")
            FIRST_HIT=$(python3 -c "print('%.1f' % ($NOW - $START))")
        fi
    done

    local HPLINE=$(R "hp")
    local DMG=$(printf "%s" "$HPLINE" | grep -o 'damage_taken=[0-9]*' | cut -d= -f2)
    DMG=${DMG:-0}
    local MPOS=$(R "enemies" | tail -1 | grep -o '([0-9]*,[0-9]*)' | head -1)
    local BALLLINE=$(R "ball")
    local BALL_PK=$(printf "%s" "$BALLLINE" | grep -o 'ball_peak=[0-9]*' | cut -d= -f2)
    BALL_PK=${BALL_PK:-0}
    local IKLINE=$(R "ik")
    local IK_PK=$(printf "%s" "$IKLINE" | grep -o 'ik_peak=[0-9]*' | cut -d= -f2)
    IK_PK=${IK_PK:-0}
    local THRASHLINE=$(R "thrash")
    local THRASH=$(printf "%s" "$THRASHLINE" | grep -o 'thrash=[0-9]*' | cut -d= -f2)
    THRASH=${THRASH:-0}

    printf "%-22s %5d %5ss %5d %5d %5d %5d\n" "$LABEL" "$DMG" "$FIRST_HIT" "$SCENARIO_MIN_FPS" "$BALL_PK" "$IK_PK" "$THRASH"
}

printf "%-22s %5s %6s %5s %5s %5s %5s\n" "SCENARIO" "DMG" "1stHIT" "mnFPS" "BALL" "IK" "THRSH"
printf "%-22s %5s %6s %5s %5s %5s %5s\n" "--------" "---" "------" "-----" "----" "--" "-----"

printf "\n=== BASELINE (monster at 960,880) ===\n"
run_scenario "same_floor_near"    800  885  960 880  0
run_scenario "same_floor_far"     200  885  960 880  0
run_scenario "on_P1"              550  745  960 880  1
run_scenario "on_P2"              1400 745  960 880  1
run_scenario "on_P3"              670  525  960 880  1
run_scenario "on_P4"              1250 525  960 880  1
run_scenario "floor_to_P3"        670  525  960 880  1
run_scenario "cross_P1_to_P2"     1400 745  960 880  1
run_scenario "P1_to_P3"           670  525  960 880  1
run_scenario "P2_to_P4"           1250 525  960 880  1

printf "\n=== EDGE CASES ===\n"
run_scenario "corner_left"        220  870  500 870  0
run_scenario "corner_right"       1700 870  1400 870 0
run_scenario "near_corner_left"   250  870  260 870  0
run_scenario "near_corner_right"  1680 870  1670 870 0
run_scenario "near_cliff_left"    220  580  250 750  0
run_scenario "near_cliff_right"   1700 580  1680 750 0

printf "\n=== CLIFF LEDGES ===\n"
run_scenario "cliff_left"         60   500  960 880  1
run_scenario "cliff_right"        1860 500  960 880  1

printf "\n=== DONE ===\n"
