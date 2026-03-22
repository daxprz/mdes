---
description: Spawn a chained monster attached to a wall
argument-hint: "[x y chain_length]" (e.g., "1300 885 800")
---

# Spawn Chained Monster

Clear the scene and spawn a monster chained to the nearest wall.

## Steps

1. Clear existing entities:
```bash
echo "clear" | nc -w1 localhost 9999
echo "portal off" | nc -w1 localhost 9999
echo "clearplayers" | nc -w1 localhost 9999
```

2. Parse arguments: x (default 1300), y (default 885), chain_length (default 800).

3. Spawn monster:
```bash
echo "spawn monster <x> <y>" | nc -w1 localhost 9999
```

4. Wait for physics to settle:
```bash
echo "standdown on" | nc -w1 localhost 9999
sleep 1
```

5. Attach chain to right wall (default anchor at 1920, 820):
```bash
echo "chain 0 head wall 1920 820 <chain_length>" | nc -w1 localhost 9999
sleep 1
```

6. Confirm:
```bash
echo "enemies" | nc -w1 localhost 9999
echo "chain status" | nc -w1 localhost 9999
```

7. Report entity ID, position, and chain status. Note: monster is in standdown — use `standdown off` to activate.
