# Ranger Swing-Slide-Jump

## Overview

When a Ranger is swinging on a grappling rope and approaches terrain, they can **press JUMP to convert swing momentum into a ground slide**, then release JUMP to **launch off the surface**. This creates a fluid swing → slide → jump traversal loop that rewards timing and surface reading.

This extends Phase 5 of `grappling_hook_physics.md` — it's what happens when the player contacts terrain during a pendulum swing.

## Reference Diagram

See whiteboard `ranger_swing` — illustrates the physics for floor, wall, and hill collisions with 5 rope lengths. The diagram shows velocity decomposition (yellow), surface-parallel slide (blue), surface normal (green), and resultant launch (red) at each collision surface.

## Mechanic Phases

### Phase A: Impact Window

```
                🪝 anchor
               /
              / rope
             /
            P ← swinging
           ↓
      ░░░░░░░░░░░░  surface
      │← detection │
      │   radius   │
```

While swinging, when the player's center is within **IMPACT_RADIUS** of any surface (floor, wall, slope):

- A visual indicator appears: subtle glow on the surface near the player
- The player can press **JUMP** to initiate a slide
- The window is generous — approximately 1 player height (~48px)
- If the player does NOT press JUMP, they collide normally (bounce/stop per existing physics)

| Parameter | Value |
|-----------|-------|
| IMPACT_RADIUS | 48px (1 player height) |
| Visual cue | Surface glow pulse, 0.3s anticipation |

### Phase B: Slide Initiation

```
Velocity at impact:
         ↗ yellow (full velocity)
        /
       / θ (impact angle)
      ●──────→ blue (surface-parallel = slide speed)
  ░░░░░░░░░░░░░░░
```

When JUMP is pressed within the impact window:

1. **Decompose velocity** at the contact point:
   - **Surface-parallel component** (BLUE) = `dot(velocity, surface_tangent) * surface_tangent`
   - **Surface-normal component** = absorbed (converted to contact force)
2. **Add jump boost to parallel speed**: `slide_speed = blue_speed + SLIDE_BOOST`
3. **Player snaps to surface** and begins sliding in the BLUE direction
4. **Rope stays attached** — player is now sliding while still connected to the anchor

The slide direction follows the surface tangent at the contact point. On a floor, this is horizontal. On a wall, this is vertical. On a slope, it follows the slope.

| Parameter | Value |
|-----------|-------|
| SLIDE_BOOST | 50 px/s added to parallel speed |
| SLIDE_FRICTION | 0.985 per frame (very low — slides are fast) |
| MIN_SLIDE_SPEED | 20 px/s (below this, slide ends) |
| Snap distance | Player placed ON surface, velocity locked to tangent |

### Phase C: Taut Point Continuation

```
                🪝 anchor
                 \
                  \ rope (taut)
                   \
        ═══════════● P sliding →→→
  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
```

As the player slides along the surface, the rope may go **taut** (player reaches max rope distance from anchor). When this happens:

- If **JUMP is still held**: the rope **detaches silently** and the player continues sliding at current speed. The slide is now free — no rope constraint.
- If **JUMP was already released**: handled by Phase D below.
- Rope detach is invisible to the player — no visual snap or jerk. The momentum carries.

### Phase D: Jump Release

```
        RED ↗ (launch direction)
           /
          / = GREEN + BLUE
         /
        ● P
  ░░░░░░░░░░░░░░░
        ↑ GREEN (normal boost)
        ──→ BLUE (slide speed, decaying)
```

When the player **releases JUMP** while sliding:

1. **Compute launch vector** = GREEN (surface normal × JUMP_BOOST) + BLUE (current slide velocity)
2. **Apply as impulse**: player leaves the surface with this velocity
3. **Rope detaches** if still attached
4. The RED vector determines the launch arc — angle depends on:
   - **Surface angle**: floor = mostly UP, wall = mostly AWAY, slope = perpendicular to slope
   - **Remaining slide speed**: faster slide = more tangential momentum retained
   - **Jump boost**: constant normal component (same as standard jump)

| Parameter | Value |
|-----------|-------|
| JUMP_BOOST | Standard class jump velocity (from character config) |
| Launch = | surface_normal × JUMP_BOOST + slide_velocity |

### Phase E: Terrain Following

```
        P sliding →→→
  ░░░░░░░░░░░░░░░░░        ← floor
                    ╲
                     ╲      ← slope (45°)
                      ╲
                       ╲░░░░░░░
```

While sliding, if the terrain angle changes:

1. **Re-project velocity** onto the new surface tangent: `new_vel = dot(vel, new_tangent) * new_tangent`
2. Player stays locked to the surface — no separation unless they release JUMP
3. **Speed is preserved** through terrain transitions (minus friction)
4. Concave transitions (floor → slope going down) are smooth
5. Convex transitions (slope → flat) may cause brief separation if the angle change is sharp (> 90°), at which point the slide ends and the player is launched

| Transition | Behavior |
|------------|----------|
| Floor → downslope | Smooth, speed preserved |
| Floor → upslope | Smooth, speed preserved (may slow on steep slopes due to gravity) |
| Slope → floor | Smooth, speed preserved |
| Slope → opposite slope (convex) | Launch — slide ends, player keeps momentum |
| Floor → wall | Smooth if angle ≤ 90°, launch if sharp corner |

### Terrain Gravity During Slide

While sliding on a slope, gravity affects slide speed:
- **Downhill**: `slide_speed += GRAVITY * sin(slope_angle) * delta` (accelerates)
- **Uphill**: `slide_speed -= GRAVITY * sin(slope_angle) * delta` (decelerates)
- **Flat**: no gravity effect (only friction)

## Visual Effects

### Slide Particles

While sliding, emit particles from the player's feet:

```
        P →→→
  ░░ · ·  · ·  ░░░
      ↑ smoke/dust puffs
```

| Parameter | Value |
|-----------|-------|
| Particle type | Small dust puffs (2-4px circles, grey-brown) |
| Emit rate | Proportional to slide speed (faster = more particles) |
| Emit position | Player's feet, slightly behind direction of travel |
| Lifetime | 0.3 - 0.5s |
| Behavior | Rise slightly, fade out, drift opposite to travel direction |
| Color | Surface-dependent: grey on stone, brown on dirt, white on ice |

### Impact Flash

On initial surface contact (Phase B):
- Brief white flash at contact point (0.1s)
- Small radial particle burst (8-12 particles)
- Screen shake: 0 (slide is smooth, not a crash)

### Slide Trail

Optional: faint trail line behind the player during slide (like speed lines):
- 2px wide, player color at 30% alpha
- Fades over 0.5s
- Length proportional to speed

## State Machine

```
SWINGING ──[within IMPACT_RADIUS]──→ IMPACT_WINDOW
    │                                      │
    │ (no JUMP pressed)            [JUMP pressed]
    │                                      │
    ▼                                      ▼
NORMAL_COLLISION                      SLIDING
                                       │     │
                              [JUMP held,  [JUMP released]
                               rope taut]       │
                                  │              ▼
                                  ▼          LAUNCHED
                              SLIDING_FREE      │
                                  │              ▼
                          [JUMP released]    AIRBORNE
                                  │         (normal physics)
                                  ▼
                              LAUNCHED
                                  │
                                  ▼
                              AIRBORNE
```

## Integration Points

### With Existing Systems

- **Grappling hook** (`grappling_hook_physics.md`): This is Phase 5.5 — between swing and release
- **Character physics** (`character.gd`): Slide uses `move_and_slide()` with custom velocity
- **Jump system**: JUMP_BOOST uses the standard class jump velocity from config
- **Particle system** (`object_pool.gd`): Dust particles from the pool
- **Surface detection**: Uses existing collision normals from `CharacterBody2D`

### Config Keys (monster_defaults.json pattern)

```json
{
  "ranger_slide_boost": 50,
  "ranger_slide_friction": 0.985,
  "ranger_min_slide_speed": 20,
  "ranger_impact_radius": 48,
  "ranger_slide_particles_per_second": 30
}
```

## Edge Cases

| Case | Resolution |
|------|------------|
| Hit ceiling while swinging down | No slide — ceilings are not slideable |
| Hit a moving platform | Slide relative to platform velocity |
| Slide into another player | Pass through (no player-player collision during slide) |
| Slide off edge of platform | Launch with current slide velocity (like running off an edge) |
| Rope breaks during slide | Continue sliding — rope state doesn't affect slide |
| Multiple surfaces in IMPACT_RADIUS | Choose the one closest to velocity vector direction |
| Slide speed reaches zero | Slide ends, player stands on surface normally |
| Player takes damage during slide | Slide interrupted, knockback applied normally |
