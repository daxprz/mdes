# EPIC: Monster Damage and Weak Spots

## Overview

Expand the quadruped monster's body-part system with targetable attachment points, vulnerable weak spots with tiered damage states, and attachable items (balloons, grapple) that interact with per-segment weight physics. Includes a new Attack Dummy test entity and a monster stand-down mode for automated testing.

## Dependencies

- `scripts/enemies/quadruped_monster.gd` — monster implementation (~3700 lines)
- `scripts/characters/balloon_dart.gd` — balloon dart projectile (attaches to enemies, causes floating)
- `scripts/autoload/rcon.gd` — RCON server for test automation
- Existing hitbox system: 7 `Area2D` zones (body, head, tail, leg0-3), `take_part_damage()`, `_sever_part()`
- Existing skeleton: `_spine[0]` = shoulders, `_spine[1]` = torso, `_spine[2]` = waist, `_skull`, `_tail[0..4]`, `_legs[0..3]` (0-1 = front/arms, 2-3 = rear/legs)

---

## STORY 1: Targetable Attachment Points

Invisible hitbox zones where items (balloons, grapple hooks) can attach to the monster. These are for item attachment only — not damage. Sized to match the visual body part they represent.

**Context:** The existing hitboxes are small circles (r=8-12) positioned at skeleton joints. Attachment points need to be larger, matching the visual silhouette so players can reliably target them.

### Tasks

- [ ] **1.1** Add attachment point `Area2D` nodes (separate from damage hitboxes) on collision layer for item attachment:
  - `attach_head` — centered on `_skull`, radius matches skull polygon bounding circle
  - `attach_tail_tip` — centered on `_tail[4]` (last segment), large invisible circle (r=30+, generous target)
  - `attach_shoulders` — centered on `_spine[0]` (front leg hip), radius matches shoulder width
  - `attach_waist` — centered on `_spine[2]` (rear leg hip), radius matches waist width
- [ ] **1.2** Update positions every frame in `_update_hitbox_positions()` — attachment points track their skeleton anchor
- [ ] **1.3** Each attachment point stores an array of attached items (`_attachments: Dictionary` keyed by point name)
- [ ] **1.4** Public API: `attach_item(point_name: String, item: Node2D)` and `detach_item(point_name: String, item: Node2D)`
- [ ] **1.5** Attached items have their `global_position` updated to the attachment point's world position each frame
- [ ] **1.6** Debug draw: when TAB-selected, show attachment points as dashed circles with labels

---

## STORY 2: Vulnerable Weak Spots with Tiered Damage

Each body region tracks its own HP and has three visible damage states (none, medium, high) with escalating blood effects and gameplay penalties.

**Context:** The existing system has per-part HP and severing, but no visual damage states or gameplay effects short of full severing. This story adds a gradient: parts degrade before they sever.

### Damage State Thresholds

Each part has configurable max HP. Damage states are determined by percentage of HP remaining:
- **None**: > 66% HP remaining
- **Medium**: 34-66% HP remaining
- **High**: < 34% HP remaining

### Tasks

- [ ] **2.1** Replace the flat `_part_health` dictionary with a struct per part: `{ max_hp, current_hp, damage_state }` where `damage_state` is an enum `{ NONE, MEDIUM, HIGH }`
- [ ] **2.2** On every `take_part_damage()` call, recalculate `damage_state` from `current_hp / max_hp` percentage (>0.66 = NONE, >0.33 = MEDIUM, else HIGH)
- [ ] **2.3** **Head** weak spot — existing `_skull` hitbox
  - Blood particles spawn at `_skull` position, scaled to damage state (none=0, medium=3 particles, high=6 particles)
  - No gameplay penalty beyond damage to main health pool
- [ ] **2.4** **Eye** weak spot — new tiny hitbox (r=3-4px) positioned at the eye render location on the skull
  - Hit = CRITICAL HIT: damage is applied to head part at 2x multiplier
  - On hit: play audible PING sound effect
  - On hit: blood squirts in 5 directions (72 degrees apart) from eye position, each a short-lived particle/line
  - Eye hitbox rotates with head (uses head-local coordinate transform)
- [ ] **2.5** **Mid-tail** weak spot — hitbox at `_tail[2]` (existing tail hitbox position)
  - Blood particles at `_tail[2]`, scaled to damage state
  - **High damage effect**: disables ATTACK_GRAB (roll/ball attack). Monster can no longer curl up. Set flag `_grab_disabled = true`, check in grab initiation.
- [ ] **2.6** **Torso** weak spot — hitbox at `_spine[1]` (existing body hitbox position)
  - Blood particles at `_spine[1]`, scaled to damage state
  - **High damage effect**: continuous blood drip — 1 blood particle per second from `_spine[1]`, persists until death or heal
- [ ] **2.7** **Rear legs** (leg2, leg3) — each tracked individually, existing hitbox positions
  - Blood particles at knee joint, scaled to damage state
  - **High damage on 1 rear leg**: reduce leap launch velocity by 25% (`LEAP_LAUNCH_SPEED *= 0.75`)
  - **High damage on 2 rear legs**: reduce leap launch velocity by 50% (`LEAP_LAUNCH_SPEED *= 0.50`)
- [ ] **2.8** **Front legs / arms** (leg0, leg1) — each tracked individually, existing hitbox positions
  - Blood particles at knee joint, scaled to damage state
  - **High damage on 1 arm**: reduce slash damage by 50% (SWIPE_DAMAGE, SPRINT_SLASH_DAMAGE, LEAP_SLASH_DAMAGE)
  - **High damage on 2 arms**: reduce slash damage by 75%
- [ ] **2.9** Blood particle system: reusable function `_spawn_blood(pos: Vector2, count: int, spread_mode: String)` where `spread_mode` is `"splash"` (random directions) or `"squirt"` (5 fixed directions for eye hit). Particles are short-lived lines/circles that fade and fall under gravity.
- [ ] **2.10** RCON command: `partstatus` — print all parts with current HP, max HP, and damage state
- [ ] **2.11** RCON command: `partdmg <part> <amount>` — deal damage to a specific part for testing

---

## STORY 3: Attachable Items — Balloons and Grapple

Items that attach to the monster's attachment points and exert physics forces, interacting with per-segment weight.

**Context:** Balloon darts already exist (`balloon_dart.gd`) and attach to enemies causing floating. This story formalizes attachment to specific body points and adds weight-aware physics.

### Tasks

- [ ] **3.1** When a balloon dart hits an attachment point `Area2D`, call `attach_item()` with the attachment point name. The balloon attaches to that specific point (not just the monster's origin).
- [ ] **3.2** Each balloon exerts an upward force. The force is applied at the attachment point's position, creating torque on the skeleton (head balloons tilt the front up, tail balloons tilt the rear up).
- [ ] **3.3** Grapple hook attachment — when a grapple projectile hits an attachment point, it attaches and creates a pull force toward the grapple source. Force applied at the attachment point position.
- [ ] **3.4** Multiple items can attach to the same point. Forces stack additively.

---

## STORY 4: Per-Segment Weight System

Each body segment has a weight proportional to its visual size. Attached item forces interact with this weight to create realistic cumulative physics.

**Context:** The monster currently has a flat `MASS = 200.0` used only for knockback resistance. This story distributes weight across the skeleton so localized forces (balloons on head vs tail) produce different effects.

### Tasks

- [ ] **4.1** Define weight constants per segment, proportional to visual size:
  - Head (skull + jaw): ~15 (small, bony)
  - Neck (2 segments): ~10
  - Shoulders / spine[0]: ~30 (front of torso, arms attached)
  - Torso / spine[1]: ~40 (largest body section)
  - Waist / spine[2]: ~30 (rear of torso, legs attached)
  - Tail (5 segments): ~20 total (~4 each)
  - Each leg (3 segments): ~12 each (~48 total)
  - **Total: ~205** (close to existing MASS=200)
- [ ] **4.2** Attachment forces are divided by the local segment weight before being applied to the skeleton. Light parts (head, tail tip) are more affected than heavy parts (torso).
- [ ] **4.3** Forces propagate through the skeleton chain: a force on the tail tip pulls tail[4], which pulls tail[3], etc., each attenuated by the next segment's weight. Cumulative force reaches the body.
- [ ] **4.4** Total upward force across all attachments is summed and compared against total body weight. If upward force exceeds weight, the monster begins to float (reduced gravity or negative gravity on the CharacterBody2D).
- [ ] **4.5** Enough balloons on the head should visibly tilt the front of the monster upward (spine[0] rises relative to spine[2]).
- [ ] **4.6** RCON command: `weight` — print all segment weights and total upward/pull forces from attached items
- [ ] **4.7** RCON command: `attach balloon <point>` — attach a test balloon to an attachment point
- [ ] **4.8** RCON command: `detach <point>` — remove all items from an attachment point

---

## STORY 5: Attack Dummy (Test Entity)

A new test entity that actively attacks the monster. Placeable via RCON, configurable to use different weapons and target specific body parts.

**Context:** The existing dummy player is a passive green circle used as a monster target. The attack dummy is the inverse — it targets the monster and fires weapons at it for testing damage/weak spots.

### Tasks

- [ ] **5.1** New script: `scripts/testing/attack_dummy.gd` — `CharacterBody2D` with gravity, collision, rendered as an orange circle with a weapon indicator
- [ ] **5.2** Configurable target: `set_target(enemy: Node2D)` — the dummy faces and aims at this enemy
- [ ] **5.3** Configurable body part targeting: `set_target_part(part_name: String)` — aims at a specific hitbox/attachment point on the target. Default `""` = aim at body center.
- [ ] **5.4** Weapon: Ranger bow — fires projectile at target part on a cooldown. Projectile uses existing `projectile.gd` or a simplified version. Deals configurable damage on hit.
- [ ] **5.5** Weapon: Balloonist balloons — fires balloon darts (`balloon_dart.gd`) at the target part on a cooldown. Darts attach on hit and cause floating.
- [ ] **5.6** Weapon switching: `set_weapon(weapon_name: String)` — `"bow"` or `"balloon"`
- [ ] **5.7** RCON commands:
  - `spawn attacker [x y]` — spawn an attack dummy at position (default: 400, 850)
  - `attacker target <enemy_index>` — set target to an enemy by index
  - `attacker part <part_name>` — aim at a specific body part (`head`, `eye`, `tail`, `torso`, `leg0`, etc.)
  - `attacker weapon <name>` — switch weapon (`bow`, `balloon`)
  - `attacker rate <seconds>` — set attack cooldown
  - `attacker stop` — stop attacking (idle)
  - `attacker start` — resume attacking
- [ ] **5.8** Debug draw: when in debug mode, draw aim line from dummy to target part, show weapon name and attack rate
- [ ] **5.9** Attack dummy does not take damage and cannot be targeted by the monster (not in `players` group)

---

## STORY 6: Monster Stand-Down Mode

A test mode where the monster becomes passive — stops attacking, stops moving, and simply receives damage. Used for testing weapons, weak spots, and attachment physics.

### Tasks

- [ ] **6.1** New state: `State.STANDDOWN` — monster enters idle pose, all attack/chase/precog logic skipped
- [ ] **6.2** In stand-down: monster still runs skeleton physics (breathing, IK, foot planting) so it looks alive and hitboxes are positioned correctly
- [ ] **6.3** In stand-down: `take_damage` and `take_part_damage` still function — damage states update, blood effects trigger, gameplay penalties apply
- [ ] **6.4** In stand-down: attachment points active — items can attach and physics forces apply
- [ ] **6.5** RCON command: `standdown` — toggle stand-down mode on all quadruped monsters
- [ ] **6.6** RCON command: `standdown on` / `standdown off` — explicit set
- [ ] **6.7** Visual indicator: when in stand-down, draw a white flag icon or "STANDDOWN" text above the monster

---

## STORY 7: Automated Test Suite — Damage and Attachments

Scripted test scenarios using RCON to verify weak spots, damage states, and attachment physics.

### Tasks

- [ ] **7.1** `scripts/test_damage.sh` — test script:
  - Spawn monster + attack dummy
  - Monster enters stand-down
  - Attack dummy fires at each body part in sequence, verify damage states via `partstatus`
  - Verify eye critical hit (PING + 5-way blood squirt)
  - Verify high-damage penalties: grab disabled (mid-tail), blood drip (torso), leap reduction (legs), slash reduction (arms)
- [ ] **7.2** `scripts/test_attachments.sh` — test script:
  - Spawn monster in stand-down
  - Attach balloons to head, verify front tilt
  - Attach balloons to tail tip, verify rear tilt
  - Attach enough balloons to float the monster
  - Attach grapple to waist, verify pull force
  - Verify cumulative weight interaction via `weight` command
- [ ] **7.3** Each test outputs pass/fail per scenario with metrics

---

## STORY 8: Regression Testing After Each Change

After every significant implementation change in this EPIC, run the existing test suites to catch regressions. No feature lands without a green baseline.

### Tasks

- [ ] **8.1** After each story is implemented, run `scripts/test_all.sh` (full 18-scenario suite) and record results
- [ ] **8.2** After each story, run `scripts/test_baseline.sh` (10-scenario baseline) and compare against documented baseline
- [ ] **8.3** After each story, run `scripts/test_edge_cases.sh` (8 edge cases) and confirm no regressions
- [ ] **8.4** If any test regresses: stop, diagnose, fix before proceeding to next story
- [ ] **8.5** Record per-story test results in the Baseline History table below

---

## STORY 9: Capture Official Baseline

Record the current baseline metrics before any work in this EPIC begins. All future changes are measured against this snapshot.

### Tasks

- [ ] **9.1** Run `scripts/test_all.sh` and capture: hit rate, total damage, min FPS, worst IK, worst thrash, ball quality
- [ ] **9.2** Run `scripts/test_baseline.sh` and capture all 10 scenario results
- [ ] **9.3** Run `scripts/test_edge_cases.sh` and capture all 8 edge case results
- [ ] **9.4** Record results in the Baseline History table below as the "Pre-EPIC" row
- [ ] **9.5** After each story completes, add a new row with updated metrics

---

## Baseline History

| Checkpoint | Hit Rate | Damage | Min FPS | Worst IK | Worst Thrash | Ball | Notes |
|------------|----------|--------|---------|----------|--------------|------|-------|
| v0.9.17 (from prior EPIC) | 17/18 | 3812 | 50 | 1996 | 24 | 46 | Last recorded baseline |
| Pre-EPIC (run Story 9) | — | — | — | — | — | — | Capture before any changes |
| After Story 2 (Weak Spots) | — | — | — | — | — | — | |
| After Story 6 (Stand-Down) | — | — | — | — | — | — | |
| After Story 5 (Attack Dummy) | — | — | — | — | — | — | |
| After Story 1 (Attach Points) | — | — | — | — | — | — | |
| After Story 4 (Weight) | — | — | — | — | — | — | |
| After Story 3 (Items) | — | — | — | — | — | — | |

---

## Implementation Priority

1. **Story 9 (Capture Baseline)** — First. Establish the "before" snapshot.
2. **Story 2 (Weak Spots)** — Core gameplay. Players need to see and feel damage on the monster.
3. **Story 6 (Stand-Down)** — Needed to test everything else.
4. **Story 5 (Attack Dummy)** — Needed to automate testing.
5. **Story 1 (Attachment Points)** — Foundation for items.
6. **Story 4 (Weight System)** — Foundation for attachment physics.
7. **Story 3 (Attachable Items)** — Depends on 1 + 4.
8. **Story 7 (Test Suite)** — Depends on all above.
- **Story 8 (Regression Testing)** — Runs after every story above. Not a sequential step — it gates each transition.

---

## Key Files (New + Modified)

| File | Status | Purpose |
|------|--------|---------|
| `scripts/enemies/quadruped_monster.gd` | Modified | Attachment points, weak spots, damage states, weight system, stand-down |
| `scripts/testing/attack_dummy.gd` | **New** | Attack dummy entity |
| `scripts/autoload/rcon.gd` | Modified | New commands: partstatus, partdmg, standdown, spawn attacker, attacker *, weight, attach, detach |
| `scripts/test_damage.sh` | **New** | Automated damage/weak spot test |
| `scripts/test_attachments.sh` | **New** | Automated attachment physics test |
| `docs/epics/EPIC_monster_damage_and_weak_spots.md` | **New** | This document |

---

## Key Metrics

| Metric | RCON Command | Measures |
|--------|-------------|----------|
| Part HP / damage state | `partstatus` | Per-part HP, max HP, damage state (NONE/MEDIUM/HIGH) |
| Segment weights | `weight` | Per-segment weight, total attached forces |
| Eye critical hits | test script | Hit count, PING trigger, blood squirt |
| Leap reduction | test script | Launch velocity with 0/1/2 damaged rear legs |
| Slash reduction | test script | Slash damage with 0/1/2 damaged arms |
| Float threshold | test script | Number of balloons needed to lift monster |
