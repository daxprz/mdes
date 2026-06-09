---
description: Launch Godot graphically for the current project
---

# Launch Godot

Kill any existing Godot instances and launch fresh.

## Steps

1. Kill existing instances:
```bash
source "$(git rev-parse --show-toplevel)/.claude/scripts/godot-env.sh"
godot_kill   # terminates ALL instances for this project (handles the -- pattern)
lsof -ti:9999 | xargs kill 2>/dev/null
sleep 1
```

2. Launch Godot graphically with log capture (binary/project resolved per-OS by
   the sourced `godot-env.sh`):
```bash
source "$(git rev-parse --show-toplevel)/.claude/scripts/godot-env.sh"
nohup "$GODOT_BIN" --path "$GODOT_PROJECT" > "$GODOT_LOG" 2>&1 &
echo "Godot launched (PID $!) — log: $GODOT_LOG"
```

3. Wait for startup and verify:
```bash
sleep 5
echo "status" | nc -w1 localhost 9999
```

4. Report status.
