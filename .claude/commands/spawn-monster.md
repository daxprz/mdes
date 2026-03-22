---
description: Spawn a monster at a position (defaults to center floor)
argument-hint: "[x y]" (e.g., "960 885" or "540 730")
---

# Spawn Monster

Clear the scene and spawn a fresh monster for testing.

## Steps

1. Clear existing entities:
```bash
echo "clear" | nc -w1 localhost 9999
echo "portal off" | nc -w1 localhost 9999
echo "clearplayers" | nc -w1 localhost 9999
```

2. Parse position from arguments (default: 960 885 for center floor):

3. Spawn the monster:
```bash
echo "spawn monster $ARGUMENTS" | nc -w1 localhost 9999
```
If no arguments provided, use `spawn monster 960 885`.

4. Confirm spawn:
```bash
echo "enemies" | nc -w1 localhost 9999
```

5. Report the entity ID and position.
