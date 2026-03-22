#!/bin/bash
# FULL TEST SUITE with title cards + score cards for recording
set -e

R() { printf "%s\n" "$1" | nc -w 2 localhost 9999; }

pkill -9 -f "Godot.*dax" 2>/dev/null || true
sleep 1
/Applications/Godot.app/Contents/MacOS/Godot --path "/Users/jeremy/dev/dax/test123" > /tmp/godot_all.log 2>&1 &
sleep 5

TOTAL_DMG=0
TOTAL_HIT=0
TOTAL_TESTS=0
ALL_RESULTS=""

run_scenario() {
    local TITLE=$1 LABEL=$2 DX=$3 DY=$4 MX=$5 MY=$6 FORCE_PRECOG=$7

    R "clear" > /dev/null 2>&1
R "portal off" > /dev/null 2>&1
    R "clearplayers" > /dev/null 2>&1
    sleep 1
    R "spawn dummy $DX $DY" > /dev/null 2>&1
    sleep 0.5
    R "spawn monster $MX $MY" > /dev/null 2>&1
    sleep 1
    R "tab 1" > /dev/null 2>&1
    R "title $TITLE" > /dev/null 2>&1
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
    local BALLLINE=$(R "ball")
    local BALL_PK=$(printf "%s" "$BALLLINE" | grep -o 'ball_peak=[0-9]*' | cut -d= -f2)
    BALL_PK=${BALL_PK:-0}
    local IKLINE=$(R "ik")
    local IK_PK=$(printf "%s" "$IKLINE" | grep -o 'ik_peak=[0-9]*' | cut -d= -f2)
    IK_PK=${IK_PK:-0}
    local THRASHLINE=$(R "thrash")
    local THRASH=$(printf "%s" "$THRASHLINE" | grep -o 'thrash=[0-9]*' | cut -d= -f2)
    THRASH=${THRASH:-0}

    # Show score card on screen
    R "score ${TITLE}|${DMG}|${FIRST_HIT}s|${SCENARIO_MIN_FPS}|${IK_PK}|${THRASH}" > /dev/null 2>&1
    sleep 3

    # Track totals
    TOTAL_DMG=$((TOTAL_DMG + DMG))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [ "$DMG" -gt 0 ]; then
        TOTAL_HIT=$((TOTAL_HIT + 1))
    fi

    # Accumulate for final grid
    ALL_RESULTS="${ALL_RESULTS}  ${LABEL}: ${DMG} dmg, ${FIRST_HIT}s, fps=${SCENARIO_MIN_FPS}, ik=${IK_PK}, thrash=${THRASH}|"

    printf "%-30s %5d %5ss %5d %5d %5d %5d\n" "$LABEL" "$DMG" "$FIRST_HIT" "$SCENARIO_MIN_FPS" "$BALL_PK" "$IK_PK" "$THRASH"
}

printf "%-30s %5s %6s %5s %5s %5s %5s\n" "SCENARIO" "DMG" "1stHIT" "mnFPS" "BALL" "IK" "THRSH"
printf "%-30s %5s %6s %5s %5s %5s %5s\n" "------------------------------" "---" "------" "-----" "----" "--" "-----"

R "title === SAME FLOOR COMBAT ===" > /dev/null 2>&1
sleep 2
run_scenario "Close Range - Same Floor"     "close_same_floor"      800  885  960 880  0
run_scenario "Long Range - Same Floor"      "far_same_floor"        200  885  960 880  0

R "title === PLATFORM HUNTING ===" > /dev/null 2>&1
sleep 2
run_scenario "Hunt to Lower-Left Platform"  "hunt_P1"               550  745  960 880  1
run_scenario "Hunt to Lower-Right Platform" "hunt_P2"               1400 745  960 880  1
run_scenario "Hunt to Upper-Left Platform"  "hunt_P3"               670  525  960 880  1
run_scenario "Hunt to Upper-Right Platform" "hunt_P4"               1250 525  960 880  1

R "title === CROSS-PLATFORM PURSUIT ===" > /dev/null 2>&1
sleep 2
run_scenario "Floor to Upper Platform"      "floor_to_upper"        670  525  960 880  1
run_scenario "Cross Lower Platforms"        "cross_lower"           1400 745  960 880  1
run_scenario "Lower-Left to Upper-Left"     "P1_to_P3"             670  525  960 880  1
run_scenario "Lower-Right to Upper-Right"   "P2_to_P4"             1250 525  960 880  1

R "title === CORNER TRAPPING ===" > /dev/null 2>&1
sleep 2
run_scenario "Corner Trap - Left Wall"      "corner_left"           220  870  500 870  0
run_scenario "Corner Trap - Right Wall"     "corner_right"          1700 870  1400 870 0
run_scenario "Overlap - Left Corner"        "overlap_left"          250  870  260 870  0
run_scenario "Overlap - Right Corner"       "overlap_right"         1680 870  1670 870 0

R "title === CLIFF EDGE ASSAULT ===" > /dev/null 2>&1
sleep 2
run_scenario "Near Left Cliff Edge"         "near_cliff_left"       220  580  250 750  0
run_scenario "Near Right Cliff Edge"        "near_cliff_right"      1700 580  1680 750 0
run_scenario "Left Cliff Ledge Assault"     "cliff_ledge_left"      60   500  960 880  1
run_scenario "Right Cliff Ledge Assault"    "cliff_ledge_right"     1860 500  960 880  1

# Show final results grid on screen
R "grid === FINAL RESULTS ===|${ALL_RESULTS}TOTAL: ${TOTAL_HIT}/${TOTAL_TESTS} hit, ${TOTAL_DMG} damage" > /dev/null 2>&1

printf "\n=== FINAL: %d/%d hit, %d total damage ===\n" "$TOTAL_HIT" "$TOTAL_TESTS" "$TOTAL_DMG"
