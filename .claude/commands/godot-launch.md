---
description: Launch Godot graphically for the current project
---

# Launch Godot

Kill any existing Godot instances and launch fresh.

## Steps

1. Kill existing instances:
```bash
pkill -f "Godot.*test123" 2>/dev/null
sleep 1
lsof -ti:9999 | xargs kill 2>/dev/null
sleep 1
```

2. Launch Godot graphically with log capture:
```bash
nohup /Applications/Godot.app/Contents/MacOS/Godot --path /Users/jeremy/dev/dax/test123 > /tmp/godot_debug.log 2>&1 &
echo "Godot launched (PID $!)"
```

3. Wait for startup and verify:
```bash
sleep 5
echo "status" | nc -w1 localhost 9999
```

4. Report status.
