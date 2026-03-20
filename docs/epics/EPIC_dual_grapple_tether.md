# EPIC: Dual-Grapple Tether System

## Overview

Extend the Ranged class grapple to support a two-point tether: grapple onto one thing, then grapple onto a second thing, connecting them with a physics rope. The rope pulls strongly to a player-chosen length. The tether interacts with the weight system and can be severed by damage.

## Dependencies

- `scripts/characters/player_side.gd` — grapple implementation (GrappleState enum, ~600 lines starting at line 2869)
- `scripts/enemies/quadruped_monster.gd` — attachment points, weight system, per-segment weights
- `scripts/characters/balloon_dart.gd` — balloon float forces (tether can anchor floating enemies)
- `scripts/testing/attack_dummy.gd` — test entity that will simulate tether actions
- Existing grapple: position/velocity/raycast simulated in player script (not a projectile)
- Existing grapple states: IDLE → WINDUP → THROWN → CONNECTED → SWINGING → TUG → RETRACTING
- Existing controls: L1 = grapple, D-pad UP/DOWN = adjust rope length

## Control Scheme (Confirmed)

### Player Flow

```
1. L1 (hold)      → Hook swings in circles (WINDUP)
2. L1 (release)   → Hook shoots out, connects to target A (THROWN → CONNECTED)
3. D-pad UP/DOWN  → Adjust rope length (optional — sets tether length)
4. L2 (hold)      → Second hook swings in circles at the OTHER end of the rope
5. L2 (release)   → Second hook shoots out, connects to target B
6. Rope PULLS STRONGLY to the length chosen in step 3
```

### Button Mapping

| Button | Current Use | New Use |
|--------|-------------|---------|
| L1 (hold/release) | Grapple windup + throw | Same — first grapple point |
| D-pad UP/DOWN | Adjust rope length while swinging | Same + sets tether target length |
| L2 (hold/release) | Boost/shrink (moved) | Second grapple point: windup + throw from far end |

**Key insight:** The second hook swings from the far end of the rope (anchor A), not from the player. The player may still be swinging on the first rope while the second hook is spinning/thrown.

---

## STORY 1: Tether State Machine

Extend the grapple state machine to support tether mode with L2 as the second-point trigger.

### Tasks

- [ ] **1.1** Add new grapple states: `TETHER_WINDUP` (second hook spinning at anchor A), `TETHER_THROWN` (second hook in flight from anchor A), `TETHER_ACTIVE` (both points connected, rope live, player detached)
- [ ] **1.2** When in CONNECTED/SWINGING state, L2 (hold) transitions to `TETHER_WINDUP` — second hook begins spinning at the current anchor point (anchor A)
- [ ] **1.3** L2 (release) in `TETHER_WINDUP` → `TETHER_THROWN` — second hook launches from anchor A position toward player's aim direction
- [ ] **1.4** Second hook uses same physics as primary hook: gravity, drag, raycast collision detection
- [ ] **1.5** On second hook connect → `TETHER_ACTIVE`: player detaches from rope, rope stays between anchor A and anchor B
- [ ] **1.6** Store tether data: anchor A (position, body, offset, part), anchor B (same), target length (from D-pad adjustment in step 3)
- [ ] **1.7** Move existing L2 boost/shrink functionality to a different binding (or disable during grapple connected state)

---

## STORY 2: Tether Rope Entity

The tether is a standalone entity that persists after the player detaches. It applies physics forces between its two anchors.

### Tasks

- [ ] **2.1** New script: `scripts/systems/tether.gd` — `Node2D` entity with: anchor A data, anchor B data, target length, current HP, rope segments for rendering
- [ ] **2.2** Each frame: compute distance between anchors. If distance > target length, apply pull force toward each other
- [ ] **2.3** Pull force: strong spring — `TETHER_PULL_FORCE` constant, scaled by (distance - target_length). Should pull hard enough to yank enemies.
- [ ] **2.4** Force divided by each anchor's mass — wall = infinite mass (only other end moves), light enemies move more
- [ ] **2.5** Enemy mass lookup: use `mass` property if present, otherwise default (50.0)
- [ ] **2.6** If anchor is an enemy attachment point: apply force via `_apply_attach_forces` / directly offset skeleton segments, using `get_segment_weight()`
- [ ] **2.7** Tether interacts with balloon float: a tethered-to-floor enemy can't float away even with balloons
- [ ] **2.8** Tether entity added to `"tethers"` group for RCON/test access
- [ ] **2.9** Tether cleans up if either anchor is freed (enemy dies, etc.)

---

## STORY 3: Tether Length Control

Player sets the tether length before launching the second hook. The tether then enforces that length with strong pull.

### Tasks

- [ ] **3.1** When in CONNECTED/SWINGING state, D-pad UP/DOWN adjusts `_tether_target_length` (same as existing rope adjust, but also stored for tether)
- [ ] **3.2** Default tether length = current rope length at the moment L2 is pressed
- [ ] **3.3** On `TETHER_ACTIVE`: rope immediately begins pulling anchors to target length
- [ ] **3.4** Visual indicator during step 3: show target length numerically or as a marker on the rope while player adjusts
- [ ] **3.5** Length adjustment speed: `GRAPPLE_ROPE_ADJUST_SPEED` (80 px/s)
- [ ] **3.6** Min tether length: 30px. Max tether length: 900px (matching existing grapple constraints)

---

## STORY 4: Body Part Targeting

Tether hooks snap to attachment points on enemies for precise, weight-aware anchoring.

### Tasks

- [ ] **4.1** When grapple hook (either first or second) hits an enemy with `_attach_points`, snap to the nearest attachment point within range
- [ ] **4.2** Store attachment point name in tether anchor data — forces applied at that skeleton position
- [ ] **4.3** Tether force at attachment point uses `get_segment_weight()` — pulling the tail tip moves the tail more than pulling the torso
- [ ] **4.4** Support tethering two parts on the SAME enemy (e.g., head↔waist folds the monster over)
- [ ] **4.5** Support tethering parts across different enemies (e.g., monster A head ↔ monster B tail)
- [ ] **4.6** Visual: rope end-points track the attachment point world position each frame

---

## STORY 5: Tether Severing

Tethers have HP and can be cut by projectile damage.

### Tasks

- [ ] **5.1** Tether HP: configurable constant (default 20 HP)
- [ ] **5.2** Hit detection: each frame, check all projectiles in `"loose_items"` group for proximity to tether rope segments (distance < 8px from rope line)
- [ ] **5.3** On hit: deal projectile damage to tether, projectile continues (passes through)
- [ ] **5.4** At 0 HP: rope snaps — both anchors released, snap visual + sound
- [ ] **5.5** Visual: damaged rope changes color (brown → orange → red) as HP decreases
- [ ] **5.6** Enemies attacking through the rope also damage it (proximity check against enemy attack hitboxes)

---

## STORY 6: Tether Rendering

Visual rendering of the spinning second hook, thrown rope, and active tether.

### Tasks

- [ ] **6.1** `TETHER_WINDUP`: draw second hook spinning in circles at anchor A position (same visual as normal windup but at a remote point)
- [ ] **6.2** `TETHER_THROWN`: draw rope from anchor A to flying second hook
- [ ] **6.3** `TETHER_ACTIVE`: draw multi-segment rope between anchor A and anchor B with catenary sag when slack
- [ ] **6.4** Tension visual: slack = droopy grey rope, taut = straight brown rope, pulling = bright/vibrating
- [ ] **6.5** Anchor indicators: small hook/circle drawn at each end
- [ ] **6.6** Snap animation on sever: rope recoils to both ends, particle burst at break point

---

## STORY 7: Attack Dummy Tether Support

The attack dummy can simulate tether actions for automated testing — aim at attachment points, fire grapple hooks, create tethers.

### Tasks

- [ ] **7.1** New weapon for attack dummy: `"tether"` — fires a grapple-like hook at the target
- [ ] **7.2** Tether weapon flow: dummy aims at target enemy attachment point → fires hook → on connect, fires second hook straight down (to floor) or to a specified second target
- [ ] **7.3** Configurable tether length on dummy: `set_tether_length(px: float)`
- [ ] **7.4** Configurable second target: `set_tether_target_b(target: Node2D, part: String)` or `"floor"` for ground anchor
- [ ] **7.5** RCON: `attacker weapon tether` — switch to tether weapon
- [ ] **7.6** RCON: `attacker tether_length <px>` — set tether length
- [ ] **7.7** RCON: `attacker tether_b floor` or `attacker tether_b enemy <idx> <part>` — set second anchor target

---

## STORY 8: RCON & Automated Tests

RCON commands and test scripts for tether verification.

### Tasks

- [ ] **8.1** RCON: `tether <enemy_idx> <point> floor` — create tether from enemy body part to floor directly below
- [ ] **8.2** RCON: `tether <enemy_idx1> <point1> <enemy_idx2> <point2>` — tether two enemy body parts
- [ ] **8.3** RCON: `tether wall <x1> <y1> <x2> <y2>` — tether between two wall positions
- [ ] **8.4** RCON: `tether length <px>` — set length on most recent tether
- [ ] **8.5** RCON: `tether cut` — sever all active tethers
- [ ] **8.6** RCON: `tether status` — show all active tethers: anchors, length, tension, HP
- [ ] **8.7** `scripts/test_tether.sh` — automated tests:
  - Create tether enemy↔floor, verify enemy can't move past length
  - Create tether enemy↔enemy, verify pull forces
  - Attach balloons to tethered enemy, verify tether holds it down
  - Sever tether via `tether cut`, verify release
  - Attack dummy fires tether at monster in standdown

---

## Implementation Priority

1. **Story 1 (State Machine)** — Foundation. L1 first hook, L2 second hook.
2. **Story 2 (Tether Entity)** — Core. Rope physics between two anchors.
3. **Story 6 (Rendering)** — Need to see what's happening.
4. **Story 3 (Length Control)** — Player agency via D-pad.
5. **Story 4 (Body Part Targeting)** — Leverages existing attachment system.
6. **Story 7 (Attack Dummy)** — Automated testing capability.
7. **Story 5 (Severing)** — Gameplay interaction.
8. **Story 8 (RCON/Tests)** — Automation.

---

## Key Files (New + Modified)

| File | Status | Purpose |
|------|--------|---------|
| `scripts/characters/player_side.gd` | Modified | L2 tether states, second hook throw, tether creation |
| `scripts/systems/tether.gd` | **New** | Tether rope entity: physics, rendering, HP, severing |
| `scripts/testing/attack_dummy.gd` | Modified | Tether weapon: fires hooks, creates tethers |
| `scripts/enemies/quadruped_monster.gd` | Modified | Tether force at attachment points |
| `scripts/autoload/rcon.gd` | Modified | Tether RCON commands |
| `scripts/test_tether.sh` | **New** | Automated tether test |
| `docs/epics/EPIC_dual_grapple_tether.md` | **New** | This document |

---

## Open Questions

- **Multiple tethers**: Can the player have more than one active tether at a time? (fire-and-forget, then start another?)
- **Self-tether**: Can the player tether themselves to something? (Would that be different from normal grapple swing?)
- **Player swing + second hook**: While the player is swinging on the first rope, the second hook spins at anchor A. Can the player still swing/move during this, or are they locked?
