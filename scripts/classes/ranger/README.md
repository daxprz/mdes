# Ranger (Ranged Class)

Mobility-focused class built around a grapple hook, tether system, crossbow, and aimed archer shot. The Ranger trades raw damage for spatial control — swinging across platforms, pinning enemies with tethers, and sniping from distance.

## Controls

| Input | Action |
|-------|--------|
| Square | Fire crossbow bolt (consumes ammo) |
| Triangle | Grapple hook special (see Grapple below) |
| L1 (grapple) | Grapple: hold to windup, release to throw. While connected: starts tether second hook. When all tether slots full: releases grapple. |
| R1 (shoulder) | Pull toward anchor (reel in while connected) |
| L2 (trigger) | Enter archer aim mode (hold). Move reticle with right stick. |
| R2 (trigger) | Fire aimed arrow (while L2 held) |
| Circle | Reload crossbow bolts (hold) |
| Jump | While grappling: jump on the rope (stays attached, rope goes slack). On ground: normal jump. |
| D-pad up/down | While swinging: shorten/lengthen rope |
| Left stick | While swinging: boost/brake angular velocity |

## Systems

### Grapple Hook

The primary mobility tool. A physics hook launched from the player that attaches to walls and enemies, then creates a pendulum swing.

#### State Machine

```
IDLE
  | (L1 pressed)
  v
WINDUP -----> THROWN -----> CONNECTED -----> SWINGING
  hold L1       flies to      rope slack      pendulum
  hook orbits   target        normal gravity   taut rope
  aim with                    falls freely
  sticks
                                  |                |
                                  v                v
                              (exceeds rope)   (above anchor)
                              enters SWINGING   goes slack
                                                re-enters CONNECTED

SWINGING -----> TETHER_WINDUP -----> TETHER_THROWN
  L1 again       second hook          second hook
  (wall)         orbits player        in flight
                 aim with sticks
                 release to throw

Any state -----> RETRACTING -----> IDLE
  explicit         hook reels
  release          back
```

#### Pendulum Physics

When the rope is taut (SWINGING, not slack), the player moves on a pendulum arc:

```
     anchor (wall)
       o
      /|
     / |  rope_len
    /  |
   /   |
  o    | swing_angle (from vertical)
player
```

- **Gravity**: `GRAPPLE_PENDULUM_GRAVITY` (600) drives the pendulum
- **Damping**: `GRAPPLE_SWING_DAMPING` (0.02) prevents perpetual motion
- **Input boost**: left stick in swing direction accelerates (`GRAPPLE_INPUT_BOOST` 1.5x)
- **Input brake**: left stick against swing direction decelerates (`GRAPPLE_INPUT_BRAKE` 1.0x)
- **Rope adjustment**: D-pad up/down shortens/lengthens rope at `GRAPPLE_ROPE_ADJUST_SPEED` (80 px/s)

The pendulum computes the target position, then sets **velocity** so `move_and_slide()` handles wall/platform collisions. After `move_and_slide()`, `_grapple_post_slide_correct()` re-syncs the pendulum angle and angular velocity to match the actual post-collision position. If the player was pushed away from the arc by a wall, the rope goes slack temporarily.

#### Slack vs Taut

- **Taut**: distance to anchor >= rope length. Pendulum physics drive movement.
- **Slack**: distance < rope length * 0.95. Normal gravity and movement apply. The rope hangs loose.
- **Snap**: when slack rope reaches full length again, velocity reflects with damping and pendulum re-engages.

#### Jump on Rope

Pressing jump while grappling adds an upward impulse (80% of normal jump velocity) and sets the rope to slack. The player rises toward or above the anchor under normal gravity, then falls back. When they reach rope length again, the pendulum snaps taut. This allows:
- Vaulting over obstacles in the swing path
- Changing swing direction
- Gaining height on the line
- Hopping over platforms while staying connected

The player does NOT detach on jump. Detach is explicit (grapple button when tether slots full, or grapple release via the tether flow).

#### Connected Pulling

R1 while connected sets `_grapple_pulling = true` — the player is reeled toward the anchor at `LAUNCH_SPEED_RATIO * JUMP_VELOCITY`. Collision is handled by `move_and_slide()`. When within 20px of anchor, pulling stops and swing begins.

### Tether System

The Ranger can place up to 3 standalone tethers (physics ropes) between two anchor points. Tethers persist after placement — they're independent entities that constrain whatever they connect.

#### Placement Flow

1. While SWINGING/CONNECTED to a wall: press L1 to begin second hook windup
2. Second hook orbits the player (aim with sticks)
3. Release L1 to throw the second hook
4. On hit: a `Tether` entity is created between anchor A (original grapple point) and anchor B (second hook hit)
5. Player detaches from the grapple — tether is now standalone
6. Tethers can connect wall-to-wall, wall-to-enemy, or enemy-to-enemy
7. Enemy anchors snap to the nearest attachment point on the enemy skeleton

#### Tether Properties

- Target length set to current rope length at time of L1 press
- Pulls anchors toward each other when over-length (mass-weighted: lighter moves more)
- Can be severed by projectile damage (HP-based: `TETHER_MAX_HP` 1000)
- Visual: catenary rope with color based on tension (brown → red → critical)
- Max 3 active tethers per Ranger

### Crossbow

Simple ranged attack on Square:
- 10 bolt capacity (`RANGER_MAX_ARROWS`)
- 60 base damage (scaled by attack skill)
- 0.6s cooldown between shots
- Reload by holding Circle (1.5s per bolt, displays count)
- Bolts are standard projectiles (straight-line, 400 speed)

### Archer Aimed Shot

Precision sniping system on L2/R2:

#### Aim Mode (L2 held)

- Reticle appears, controlled by right stick (`ARCHER_AIM_RETICLE_SPEED` 400 px/s)
- Power charges over time (`ARCHER_ARROW_SPEED_RATE` 1200 per second)
- Speed range: 300 (min) to 1800 (max)
- L2 partial pull caps maximum power proportionally
- R1 while aiming: power decreases. Release R1: locks power at current level.
- Auto-target: after 5s of reticle inactivity, snaps to nearest enemy within 600px

#### Arc Solving

The archer solves a ballistic arc equation to hit the reticle position:

```
Given: speed v, gravity g, target offset (dx, dy)
Solve: launch angle theta via quadratic in tan(theta)

a*u^2 + b*u + c = 0   where u = tan(theta)
a = g * dx^2
b = 2 * v^2 * dx
c = g * dx^2 - 2 * v^2 * dy
```

Two solutions (high arc / low arc) — the solver picks the one that most closely passes through the reticle. Green arc = solution found. Red arc = no solution (need more power or closer target).

#### Firing (R2)

- Requires L2 held (aim mode active)
- Fresh R2 press fires (not held from previous shot)
- Arrow follows the solved arc with gravity (`ARCHER_ARROW_GRAVITY` 500)
- After firing, auto-re-strings after 0.5s if L2 still held
- Attack cooldown applied

### Tug (Enemy Grapple)

When grappled to an enemy, pressing L1 performs a Newtonian tug:
- Applies `GRAPPLE_TUG_FORCE` (8000) as impulse to both player and enemy
- Force distributed by mass: player accelerates toward enemy, enemy pulled toward player
- Enemies with `apply_knockback()` receive the impulse
- Deals `GRAPPLE_TUG_DAMAGE` (currently 0)
- Duration: `GRAPPLE_TUG_DURATION` (0.15s)

## Constants Reference

### Grapple
| Constant | Value | Purpose |
|----------|-------|---------|
| `GRAPPLE_SWING_RADIUS` | 40 | Hook orbit radius during windup |
| `GRAPPLE_BASE_ANGULAR_VEL` | 14 | Starting spin speed |
| `GRAPPLE_ANGULAR_ACCEL` | 12 | Spin acceleration per second |
| `GRAPPLE_MAX_ANGULAR_VEL` | 35 | Maximum spin speed |
| `GRAPPLE_MIN_HOLD` | 0.3s | Minimum hold before throw |
| `GRAPPLE_BASE_THROW_SPEED` | 4000 | Minimum throw speed |
| `GRAPPLE_THROW_SPEED_PER_SEC` | 3000 | Speed gain per second held |
| `GRAPPLE_MAX_THROW_SPEED` | 10000 | Maximum throw speed |
| `GRAPPLE_HOOK_GRAVITY` | 400 | Hook gravity during flight |
| `GRAPPLE_HOOK_DRAG` | 0.98 | Hook drag during flight |
| `GRAPPLE_PENDULUM_GRAVITY` | 600 | Pendulum gravity (stronger than normal) |
| `GRAPPLE_SWING_DAMPING` | 0.02 | Angular velocity damping |
| `GRAPPLE_INPUT_BOOST` | 1.5 | Swing acceleration from input |
| `GRAPPLE_INPUT_BRAKE` | 1.0 | Swing deceleration from input |
| `GRAPPLE_ROPE_ADJUST_SPEED` | 80 | Rope length change speed (px/s) |
| `GRAPPLE_MIN_ROPE_LEN` | 30 | Shortest rope allowed |
| `GRAPPLE_MAX_ROPE_LEN` | 900 | Longest rope allowed |
| `GRAPPLE_LAUNCH_SPEED_RATIO` | 0.75 | Pull speed as ratio of jump velocity |
| `GRAPPLE_TUG_FORCE` | 8000 | Tug impulse force |
| `GRAPPLE_TUG_DURATION` | 0.15s | Tug impulse duration |

### Archer
| Constant | Value | Purpose |
|----------|-------|---------|
| `ARCHER_AIM_RETICLE_SPEED` | 400 | Reticle movement speed (px/s) |
| `ARCHER_ARROW_MIN_SPEED` | 300 | Minimum arrow launch speed |
| `ARCHER_ARROW_MAX_SPEED` | 1800 | Maximum arrow launch speed |
| `ARCHER_ARROW_SPEED_RATE` | 1200 | Arrow speed charge rate (per second) |
| `ARCHER_ARROW_GRAVITY` | 500 | Arrow gravity during flight |
| `ARCHER_AIM_LOCK_COOLDOWN` | 0.25s | Arc re-solve interval |
| `ARCHER_AIM_MAX_RANGE` | 600 | Auto-target range |
| `RANGER_MAX_ARROWS` | 10 | Crossbow bolt capacity |
| `RANGER_RELOAD_TIME` | 1.5s | Time per bolt reload |

## Known Issues / TODO

- **Grapple line clips through walls**: The hook flight phase (`THROWN`) uses raycasting for collision, but the visual rope between player and hook doesn't wrap around geometry. The hook itself hits walls correctly — but the rope renders as a straight line through obstacles. (Item 1 from the physics cleanup list — systemic rope/chain collision system planned.)
- **No rope wrapping**: When swinging around a corner, the rope passes through the platform edge. A proper rope-wrapping system would shorten the effective rope and create a pivot at the contact point.
- **Tether slot limit**: Currently 3 tethers max. The HUD shows 3 dots but the constant says 5 (`TETHER_MAX_COUNT`). These are out of sync.
- **Duplicate code**: `_ranger_fire_crossbow()` and `_attack_ranged()` are identical. One should call the other.

## File Structure

```
scripts/classes/ranger/
  ranger_class.gd     — All Ranger logic (grapple, tether, crossbow, archer)
  README.md           — This file

scripts/characters/
  player_side.gd      — Physics loop, grapple state variables, post-slide correction

scripts/systems/
  tether.gd           — Standalone tether entity (created by Ranger, lives independently)
```
