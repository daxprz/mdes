---
description: Show recent Godot output, optionally filtered
argument-hint: "[filter_pattern] [line_count]" (e.g., "PRECOG 30" or "FAIL")
---

# Show Godot Log

Display recent Godot output from the debug log.

## Steps

The log path is resolved per-OS by `godot-env.sh` (`$GODOT_LOG`), so source it
first in each block.

1. If arguments contain a filter pattern, grep for it:
```bash
source "$(git rev-parse --show-toplevel)/.claude/scripts/godot-env.sh"
grep -E "<pattern>" "$GODOT_LOG" | tail -<count>
```

2. If no arguments, show last 40 lines:
```bash
source "$(git rev-parse --show-toplevel)/.claude/scripts/godot-env.sh"
tail -40 "$GODOT_LOG"
```

3. Common filter patterns:
   - `PRECOG|PATHFIND` — precognition pathfinding decisions
   - `LEAP|PLAN_FAIL` — leap planning and failures
   - `PASS|FAIL|Result` — test results
   - `DMG|BLOCKED` — damage dealt/blocked
   - `WALK|ARRIVED|HOP` — pathing execution
   - `debug:` — debug profile apply/clear events
