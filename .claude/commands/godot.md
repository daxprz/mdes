---
description: Control the running Godot instance — restart, launch, kill, status
argument-hint: <restart|launch|kill|status>
---

# Godot

Control the running Godot instance.

## Sub-commands

### restart

Kill and relaunch Godot, wait for RCON to respond.

Options:
- `--level <name>` — after launch, load this level and clear enemies

```bash
pkill -f "Godot.*test123" 2>/dev/null
sleep 1
LOG_DIR="/var/tumu/logs"
if [ ! -d "$LOG_DIR" ]; then
  mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp"
fi
nohup /Applications/Godot.app/Contents/MacOS/Godot --path /Users/jeremy/dev/dax/test123 > "$LOG_DIR/godot_debug.log" 2>&1 &
sleep 3
echo "status" | nc -w2 localhost 9999
```

If `--level <name>` was provided, also run:
```bash
echo "level <name>" | nc -w1 localhost 9999
echo "clear" | nc -w1 localhost 9999
```

Report the status response when ready.
