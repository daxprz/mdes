#!/bin/bash
# Baseline: measure time from forced precog to EXECUTING for each scenario
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

# Valid platform positions: floor=890, P1=750, P2=750, P3=530, P4=530
SCENARIOS="
same_floor:700:885
floor_far:200:885
on_P1:550:745
on_P2:1400:745
on_P3:670:525
on_P4:1250:525
floor_to_P3:670:525
floor_center:960:885
P1_edge:380:745
cross_P1_to_P4:1250:525
"

printf "%-20s %6s %8s %s\n" "SCENARIO" "TIME" "RESULT" "NOTES"
printf "%-20s %6s %8s %s\n" "--------" "----" "------" "-----"

for SCENE in $SCENARIOS; do
    LABEL=${SCENE%%:*}
    REST=${SCENE#*:}
    X=${REST%%:*}
    Y=${REST#*:}

    R "tp $X $Y" > /dev/null 2>&1
    : > /tmp/godot_baseline.log
    sleep 0.5
    START=$(python3 -c "import time; print(time.time())")
    R "precog" > /dev/null 2>&1
    RESULT="TIMEOUT"
    for I in $(seq 1 20); do
        sleep 0.5
        if grep -qa "EXECUTING" /tmp/godot_baseline.log 2>/dev/null; then
            RESULT="LEAP"
            break
        fi
        if grep -qa "instant path=\[" /tmp/godot_baseline.log 2>/dev/null; then
            if grep -qa "hop 1" /tmp/godot_baseline.log 2>/dev/null; then
                RESULT="WALKING"
            fi
        fi
    done
    END=$(python3 -c "import time; print(time.time())")
    ELAPSED=$(python3 -c "print('%.1f' % ($END - $START))")
    MPOS=$(R "enemies" | tail -1 | grep -o '([0-9]*,[0-9]*)' | head -1)
    printf "%-20s %5ss %-8s %s\n" "$LABEL" "$ELAPSED" "$RESULT" "monster=$MPOS"
done

printf "\nDone.\n"
