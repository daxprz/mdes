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
source "$(git rev-parse --show-toplevel)/.claude/scripts/godot-env.sh"
godot_kill   # terminates ALL instances for this project (handles the -- pattern)
nohup "$GODOT_BIN" --path "$GODOT_PROJECT" > "$GODOT_LOG" 2>&1 &
sleep 3
echo "status" | nc -w2 localhost 9999
```

The resolver (`.claude/scripts/godot-env.sh`) deduces the Godot binary and
project path per-OS (macOS app bundle vs. Linux `godot` on PATH), so no paths
are hardcoded. Override with `GODOT_BIN` / `GODOT_PROJECT` env vars if needed.

If `--level <name>` was provided, also run:
```bash
echo "level <name>" | nc -w1 localhost 9999
echo "clear" | nc -w1 localhost 9999
```

Report the status response when ready.
