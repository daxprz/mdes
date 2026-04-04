---
name: spawn
description: Spawn entities in the running Godot game via RCON. Supports regular monsters, chained monsters, and dummies. Use for setting up test scenarios.
disable-model-invocation: true
argument-hint: <monster|chained|dummy> [x y] [options]
allowed-tools: Bash Read
---

# Spawn — Entity Spawner

Clear the scene and spawn entities for testing.

## Usage

- `/spawn monster [x y]` — Spawn monster (default: 960 885, center floor)
- `/spawn chained [x y] [chain_length]` — Spawn chained monster (default: 1300 885, length 800)
- `/spawn dummy [x y]` — Spawn attack dummy

## Arguments

Type: `$0`
Position/options: remaining args

## Common Preamble

```bash
echo "status" | nc -w1 localhost 9999
```
If no response → Godot not running.

Clear the scene:
```bash
echo "clear" | nc -w1 localhost 9999
echo "portal off" | nc -w1 localhost 9999
echo "clearplayers" | nc -w1 localhost 9999
```

---

## `monster` — Regular Monster

1. Spawn: `echo "spawn monster <x> <y>" | nc -w1 localhost 9999`
   - Default position: 960 885 (center floor)
2. Confirm: `echo "enemies" | nc -w1 localhost 9999`
3. Report entity ID and position.

---

## `chained` — Chained Monster

1. Spawn: `echo "spawn monster <x> <y>" | nc -w1 localhost 9999`
   - Default: 1300 885
2. Standdown: `echo "standdown on" | nc -w1 localhost 9999`
3. Wait 1 second for physics to settle
4. Attach chain to wall: `echo "chain 0 head wall 1920 820 <chain_length>" | nc -w1 localhost 9999`
   - Default chain length: 800
5. Confirm:
```bash
echo "enemies" | nc -w1 localhost 9999
echo "chain status" | nc -w1 localhost 9999
```
6. Report. Note: monster in standdown — `standdown off` to activate.

---

## `dummy` — Attack Dummy

1. Spawn: `echo "spawn dummy <x> <y>" | nc -w1 localhost 9999`
   - Default: 1500 860
2. Confirm: `echo "enemies" | nc -w1 localhost 9999`
