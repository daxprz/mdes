#!/bin/bash
# Launch the DAX Motion Capture tool using the local venv
DIR="$(cd "$(dirname "$0")" && pwd)"
VENV="$DIR/.venv"

if [ ! -d "$VENV" ]; then
    echo "Setting up venv..."
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install mediapipe opencv-python numpy
fi

# Route --bridge to bridge.py, everything else to capture.py
if [[ " $* " == *" --bridge "* ]]; then
    exec "$VENV/bin/python3" "$DIR/bridge.py" "$@"
else
    exec "$VENV/bin/python3" "$DIR/capture.py" "$@"
fi
