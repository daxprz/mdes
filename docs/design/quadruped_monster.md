# Quadruped Monster (Procedural Animation)

## Overview

A physics-based procedurally animated quadruped enemy. No sprites — entirely vector-rendered via `_draw()`. All movement is driven by verlet physics with constraint solving, producing organic locomotion. Multiple independently damageable/severable body parts, each eligible for rift tentacle attachment.

## Skeleton Layout

23 tracked points in local space, organized by limb chain:

```
              skull--jaw
                 |
                neck
                 |
    leg0 -- spine[0] -- spine[1] -- spine[2] -- tail[0]..tail[4]
    leg1 --                          -- leg2
                                     -- leg3
```

| Chain       | Segments | Anchor Point | Notes                          |
|-------------|----------|--------------|--------------------------------|
| Spine       | 3        | Body center  | Near-rigid, drives everything  |
| Neck        | 1        | spine[0]     | Connects head to body          |
| Head        | 2 points | neck tip     | Skull + jaw (jaw hinges open)  |
| Tail        | 5        | spine[2]     | Tapers, high drag              |
| Front legs  | 3 each   | spine[0]     | Upper leg, lower leg, foot     |
| Rear legs   | 3 each   | spine[2]     | Upper leg, lower leg, foot     |

## Physics

### Verlet Integration

Same pattern as `rift_tentacle.gd`: each point stores current and previous position. Per-frame update:

```
velocity = (current - previous) * DRAG
previous = current
current += velocity + gravity * delta
```

Drag constants per chain:
- Spine: 0.98 (very stiff)
- Legs: 0.94 (moderate)
- Tail: 0.88 (heavy, sluggish)
- Neck/Head: 0.92

### Constraints

Distance constraints enforce segment lengths. Forward + reverse passes (5 iterations) propagate forces bidirectionally — same solver as the rift tentacle.

Spine segments are near-rigid: very short max length, high iteration count.

### Foot Targeting (Procedural Walk)

Each foot has a world-space target position. A spring force pulls the foot toward its target before constraints run. When the foot drifts too far from its ideal ground position, a new step is initiated (the foot lifts and moves to the new target over ~0.15s).

Diagonal gait: front-left and rear-right step together, then front-right and rear-left. Gait phase is a continuous 0..1 cycle. Speed tiers control phase advancement rate and body velocity.

## Hitboxes

7 independently damageable zones, each an Area2D repositioned per-frame to match its segment positions:

| Part   | Health | Severable | Rift Attachable |
|--------|--------|-----------|-----------------|
| Body   | 200    | No (main) | Yes             |
| Head   | 60     | Yes       | Yes             |
| Tail   | 50     | Yes       | Yes             |
| Leg x4 | 40 ea  | Yes       | Yes             |

### Severing

When a part reaches 0 health, it detaches:
- Constraint to parent is removed
- Segments fall under gravity with high drag (crumple)
- Hitbox disabled, visual becomes a fading stump
- Missing legs degrade movement (slower, wobble, limp)
- Missing tail removes tail whip attack
- Missing head triggers death

## Postures

```
enum Posture { QUADRUPED, BIPEDAL }
```

- **QUADRUPED**: all 4 feet on ground, spine horizontal. Can bite, tail whip, lunge.
- **BIPEDAL**: front legs off ground, spine tilted up. Can swipe. Tail immobilized.

Transition takes ~0.4s. Spine[0] raises/lowers, rear legs widen stance.

## Attacks

| Attack     | Posture   | Range | Damage | Description                           |
|------------|-----------|-------|--------|---------------------------------------|
| Bite       | Quadruped | Close | 25     | Head lunges, jaw snaps                |
| Tail Whip  | Quadruped | Rear  | 18     | Tail swings through arc, knockback    |
| Lunge      | Quadruped | Mid   | 20     | Two-leg push, body launches forward   |
| Claw Swipe | Bipedal   | Close | 20     | Front leg arcs downward, knockback    |

## AI / Behavior

- Picks nearest player as target on spawn
- Chases target relentlessly (no detection range — always knows where target is)
- If a different player hits the monster 3+ times, switches target to that player
- Hit counter resets on target switch
- Attack selection based on distance, target position (in front vs behind), and posture

## Movement

| Speed  | Body Velocity | Gait Rate | When           |
|--------|---------------|-----------|----------------|
| Slow   | 30 px/s       | 0.5x      | Patrol/idle    |
| Medium | 80 px/s       | 1.0x      | Chase          |
| Fast   | 160 px/s      | 2.0x      | Charge/closing |

### Degraded Movement (Missing Legs)

- 3 legs: 75% speed, slight limp
- 2 legs: 40% speed, heavy wobble
- 1 leg: 15% speed, drags body
- 0 legs: 5% speed, crawl

## Rendering

All custom `_draw()`, no sprites. Dark organic color palette:
- Body/spine: thick lines (8-10px), Color(0.3, 0.25, 0.2)
- Legs: medium lines (5-6px), triangular claw at foot
- Tail: tapering 6px→2px
- Head: polygon skull, hinged polygon jaw
- Eyes: bright red dots on skull
- Severed stumps: ragged zigzag edge, red tint

## Integration

- `add_to_group("enemies")` — standard enemy group
- Standard interface: `take_damage()`, `apply_knockback()`, `died` signal
- Rift tentacle absorption via meta (per-part, multiple tentacles possible)
- `mass = 200.0` (very heavy — knockback barely moves it)
- Self-contained: no changes to any existing file
