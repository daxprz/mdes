# Physics-Based Grappling Hook (Ranger)

## Overview

Replace the current raycast-based grappling hook with a full physics simulation.
The hook is swung, thrown, and creates momentum-based traversal. Grappled entities
react based on Newtonian mass physics — both the player and the target accelerate
toward each other proportionally to their mass.

## Phase 1: Windup

```
Player holds grapple button:

  t=0.0s    t=0.5s    t=1.0s    t=1.5s
    .         .          .          .
    |        /          ─          \
    P       P           P           P
            (slow)    (medium)    (fast)
```

- Holding the grapple button starts swinging the hook in a circle around the player
- Swing radius: ~40px, centered at player's hand position
- Angular velocity increases over time: `ω = BASE_SPEED + hold_time * ACCELERATION`
- Base speed: 4 rad/s, acceleration: 3 rad/s², max: 12 rad/s
- Visual: hook sprite orbiting the player, rope/chain trailing behind
- Sound: whooshing sound that increases pitch with speed

### Windup Constants

| Parameter | Value |
|-----------|-------|
| Swing radius | 40px |
| Base angular velocity | 4 rad/s |
| Angular acceleration | 3 rad/s² |
| Max angular velocity | 12 rad/s |
| Min hold time to throw | 0.3s |

## Phase 2: Throw

```
Release button while aiming right:

    .___________→ ·  ·  ·  ·  ·  🪝
    P
```

- On button release, hook is thrown in the thumbstick aim direction
- If no thumbstick input, throws in the direction the hook was moving at release
- Throw velocity: `speed = BASE_THROW + hold_time * THROW_SCALE` (capped)
- Hook follows a physics arc: initial velocity + gravity
- Rope trails behind the hook as it flies (verlet chain, 20 segments)
- Max range determined by throw speed and arc (not a hard limit)

### Throw Constants

| Parameter | Value |
|-----------|-------|
| Base throw speed | 200 px/s |
| Speed per second held | 150 px/s |
| Max throw speed | 500 px/s |
| Hook gravity | 400 px/s² |
| Hook drag | 0.98 per frame |
| Rope segment count | 20 |
| Rope segment length | 12px |

### Arc Physics

```
v₀ = throw_speed * aim_direction
Each frame:
  velocity.y += HOOK_GRAVITY * delta
  velocity *= HOOK_DRAG
  position += velocity * delta
```

Hook checks for collision each frame via raycasting along velocity vector.

## Phase 3: Connection

The hook connects when it contacts:
- **Wall/Platform** (StaticBody2D): anchors at the contact point
- **Enemy** (CharacterBody2D in "enemies" group): anchors to the enemy's center
- **Boss**: anchors to the boss

On connection:
1. Hook locks to the anchor point
2. Player receives a launch impulse toward the anchor at **50% of jump velocity**
3. Rope goes taut rendered as verlet chain from player to anchor
4. Sound: grapple_hit.wav

```
Connection:
                        🪝 (anchored to wall)
                       /
                      /
                     /
                    P → (launched toward hook)
```

### Launch Constants

| Parameter | Value |
|-----------|-------|
| Launch speed | 50% of JUMP_VELOCITY (variable per class) |
| Launch direction | normalized(anchor - player) |

## Phase 4: Pendulum Swing

At the apex of the launch (when player velocity.y changes from negative to positive,
or when rope reaches full taut length), the player transitions to pendulum mode.

```
                    🪝 anchor
                   /|
                  / |
                 /  | (rope length L)
                /   |
               P    |
              ←→    |
         swing motion
```

### Pendulum Physics

The player swings as a pendulum from the anchor point:

```
θ = angle from vertical (anchor to player)
L = rope length (adjustable)
g = gravity

Angular acceleration: α = -(g / L) * sin(θ)
Apply damping: α -= angular_velocity * SWING_DAMPING
Angular velocity: ω += α * delta
θ += ω * delta

Player position:
  x = anchor.x + L * sin(θ)
  y = anchor.y + L * cos(θ)
```

### Thumbstick Control During Swing

| Input | Effect |
|-------|--------|
| Left/Right (with swing) | Adds angular velocity in swing direction (+1.5 rad/s²) |
| Left/Right (against swing) | Brakes angular velocity (-1.0 rad/s²) |
| Up | Shortens rope by 80 px/s (player climbs toward anchor) |
| Down | Lengthens rope by 80 px/s (player drops away from anchor) |

### Swing Constants

| Parameter | Value |
|-----------|-------|
| Gravity (pendulum) | 600 px/s² |
| Swing damping | 0.02 |
| Input boost | 1.5 rad/s² |
| Input brake | 1.0 rad/s² |
| Rope adjust speed | 80 px/s |
| Min rope length | 30px |
| Max rope length | 300px |

## Phase 5: Release

### Release from Wall
- Press grapple button again to release
- Rope retracts visually back to player (tween, 0.2s)
- Player retains full momentum from the swing
- This is the core traversal mechanic: swing + release = fling

```
Release at bottom of swing (max horizontal velocity):

                    🪝
                     |  (rope retracting)
                     |
                    P ─────→  (flung with momentum)
```

### Release from Enemy (Tug)

When connected to an enemy and the player presses grapple again, instead of
simply releasing, a **tug** occurs based on Newtonian physics:

```
F = TUG_FORCE (constant, e.g. 8000)

Player acceleration: a_player = F / mass_player    (toward enemy)
Enemy acceleration:  a_enemy  = F / mass_enemy      (toward player)

Applied as impulse velocity:
  player.velocity += direction_to_enemy * a_player * TUG_DURATION
  enemy.velocity  += direction_to_player * a_enemy * TUG_DURATION
```

Both entities move. The lighter one moves more.

### Tug Behavior by Mass Ratio

| Mass Ratio (enemy/player) | Result |
|---------------------------|--------|
| < 0.5 (very light) | Enemy flung hard toward player, player barely moves |
| 0.5 - 0.8 (light) | Enemy pulled significantly, player pulled slightly |
| 0.8 - 1.2 (equal) | Both pulled toward each other equally |
| 1.2 - 2.0 (heavy) | Player pulled significantly, enemy barely moves |
| > 2.0 (very heavy) | Player flung toward enemy (reverse tug) |

### Release/Tug Constants

| Parameter | Value |
|-----------|-------|
| Tug force | 8000 |
| Tug duration | 0.15s |
| Rope retract time | 0.2s |
| Tug damage | 10 (to enemy only) |

## Entity Mass System

Every entity has a `mass` property. This is a refinement of the existing weight
system (SYSTEMS.md §21) — mass is used for all physics interactions including
grapple tug, knockback, balloon lift, and blast wave push.

### Mass Table

| Entity | Mass | Category | Grapple Behavior |
|--------|------|----------|------------------|
| Sprinkle Swarm | 5 | Tiny | Flung violently |
| Fairy Cake Bat | 8 | Tiny | Flung violently |
| Peppermint Roller | 25 | Small | Flung |
| Candy Corn | 25 | Small | Flung |
| Skeleton | 30 | Small | Flung |
| Cookie Archer | 30 | Small | Flung |
| Jellybean Sniper | 30 | Small | Flung |
| Cupcake Bomber | 35 | Medium | Tugged |
| Licorice Whip | 40 | Medium | Tugged |
| Marshmallow Blob | 50 | Medium | Tugged |
| Wafer Shield | 55 | Medium | Tugged |
| Gummy Bear | 60 | Medium | Tugged |
| **Player** | **70** | **Reference** | **—** |
| Mini-bosses | 120 | Heavy | Reverse tug (slight) |
| Candy Golem | 150 | Heavy | Reverse tug |
| Bosses | 300 | Very Heavy | Reverse tug (strong) |

### Mass Rules

- Mass should roughly correlate with visual size
- New enemies/bosses should be assigned mass at creation time
- The existing weight system (§21) is superseded by mass
- All systems that reference weight should migrate to mass

## Rope Rendering

The grapple rope uses the same verlet chain physics as the balloon string
and rift tentacle, adapted for the grapple:

- **Windup:** short chain (5 segments) orbiting with the hook
- **In-flight:** chain trails behind hook (20 segments, slight sag from gravity)
- **Connected/Swing:** chain from player to anchor (segment count = rope_length / 12)
- **Retracting:** chain shrinks as hook returns to player

Visual: thin brown/grey line (2px width), slightly darker than the balloon string.

## State Machine

```
IDLE → (hold grapple) → WINDUP → (release) → THROWN → (hit) → CONNECTED
  ↑                                  ↓ (miss)          ↓
  └──────────────── RETRACTING ←─────┘          SWINGING
                       ↑                           ↓
                       └───── (press grapple) ─────┘
                       └───── (press grapple + enemy) → TUG → RETRACTING
```

| State | Player Control | Gravity | Collision |
|-------|---------------|---------|-----------|
| IDLE | Full | Normal | Normal |
| WINDUP | Full (movement) | Normal | Normal |
| THROWN | Full (movement) | Normal | Normal |
| CONNECTED | Limited | Reduced | Normal |
| SWINGING | Pendulum input | Pendulum | Rope constraint |
| TUG | None (impulse) | Normal | Normal |
| RETRACTING | Full | Normal | Normal |

## Integration with Existing Systems

- **Ammo:** Grapple does NOT consume arrows
- **Reload:** Can reload while swinging (one-handed crossbow reload)
- **Charge attack:** Cannot charge while swinging
- **Block/Parry:** Cannot block while swinging
- **Damage:** Hook deals 10 damage on initial hit, tug deals 10 damage
- **Sound:** grapple_launch.wav (throw), grapple_hit.wav (connect),
  new whoosh sound (windup), new creak sound (swing)
