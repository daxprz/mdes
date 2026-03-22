---
description: Quick sanity check — verify Godot is running and basic systems work
---

# Sanity Check

Verify the game is running and core systems are functional.

## Steps

1. Check Godot is listening on RCON:
```bash
echo "status" | nc -w1 localhost 9999
```
If this fails, tell the user Godot is not running.

2. Check debug system:
```bash
echo "debug list" | nc -w1 localhost 9999
```
Verify aspects are registered (should show 40+ aspects).

3. Check enemies and players:
```bash
echo "enemies" | nc -w1 localhost 9999
echo "players" | nc -w1 localhost 9999
```

4. Check FPS:
```bash
echo "fps" | nc -w1 localhost 9999
```

5. List available tests:
```bash
echo "tests" | nc -w1 localhost 9999
```

6. Report summary: running/not running, FPS, entity counts, registered aspects count, available tests.
