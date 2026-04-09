# Ranger Slide: Modifier System Integration

## Problem

The slide-charge mechanic needs a **time-varying modifier** — the boost multiplier ramps from 1.0x to 1.5x over 2 seconds. The current modifier system is static: you push fixed values and they stay until popped. We need modifiers that evolve at runtime.

## Modifier System Extension: `RampModifierProvider`

A new provider type that **interpolates modifier values over time**.

```gdscript
## RampModifierProvider: modifier values lerp from start to end over duration.
## After duration, values stay at end_val. Useful for charge-up effects.
##
## Usage:
##   var charge = MCP.RampModifierProvider.new({
##       "slide_boost": ["multiply", 1.0, 1.5]  # [op, start_val, end_val]
##   }, 2.0, "slide_charge")
##   player.push_config(charge)
##   # At t=0.0s: slide_boost *= 1.0
##   # At t=1.0s: slide_boost *= 1.25
##   # At t=2.0s: slide_boost *= 1.5 (stays here)
```

The `[op, start_val, end_val]` triple replaces the `[op, value]` pair. The provider tracks its own creation time and lerps between start and end based on elapsed time.

This is composable with the existing stack — multiple RampModifiers can stack (e.g., a rage buff ramping simultaneously with a charge).

### API

| Method | Returns | Description |
|--------|---------|-------------|
| `get_modifier(key)` | `[op, current_lerped_val]` | Returns the interpolated modifier |
| `get_progress()` | `float (0..1)` | How far through the ramp |
| `is_expired()` | `bool` | Always false (ramp stays at end) |
| `reset()` | `void` | Restart the timer from zero |
| `freeze()` | `void` | Lock the current value (stop ramping) |

## Slide Mechanic via Modifiers

### Config Keys

| Key | Base Value | Description |
|-----|-----------|-------------|
| `ranger_slide_boost` | 50.0 | Speed added on slide initiation |
| `ranger_slide_friction` | 0.985 | Per-frame friction multiplier |
| `ranger_slide_charge_mult` | 1.0 | Charge multiplier (ramped by modifier) |
| `ranger_impact_radius` | 48.0 | Surface detection distance |

### Modifier Lifecycle

```
SWING → [Circle press] → SLIDE_INIT
  1. Push RampModifierProvider("slide_charge"):
     - "ranger_slide_charge_mult": ["multiply", 1.0, 1.5] over 2.0s
  2. Decompose velocity → start sliding

SLIDING → [each frame]
  - speed = cfg("ranger_slide_charge_mult") applied to slide velocity
  - Gravity: g * dot(surface_tangent, DOWN) affects speed
  - If player leaves surface → freeze the ramp modifier (charge stops growing)

SLIDING → [Circle release, ON surface]
  - boost_mult = cfg("ranger_slide_charge_mult")  ← reads the ramped value
  - launch = slide_velocity * boost_mult
  - Pop the modifier
  - Apply launch as impulse

SLIDING → [Circle release, OFF surface]
  - No boost (charge wasted)
  - Pop the modifier
  - Player keeps current velocity (gravity-only)
```

## Visual Indicators

### Phase: CHARGING (Circle held while sliding)

```
    ┌─ charge ring (fills clockwise) ─┐
    │                                  │
    P ═══════→  (sliding)
  ░░░░░░░░░░░░░░░░░
```

- **Charge ring**: Circular arc around the player, filling clockwise over 2 seconds
  - Color: Yellow (0%) → Orange (50%) → White-hot (100%)
  - Radius: 20px, line width: 2px → 4px as charge builds
  - Subtle pulsing glow at high charge
- **Player tint**: Slight brightening proportional to charge (lerp toward white, 0-15%)

### Phase: SLIDING (dust particles)

```
        P →→→
  ░░ · ·  · ·  ░░░
      ↑ dust puffs (gravity-affected)
```

- Particle emitter at player's feet, behind direction of travel
- **Size**: 2-5px circles
- **Color**: Brown-grey (`Color(0.6, 0.55, 0.45, 0.4)`)
- **Behavior**: Inherit slight opposite velocity, then fall with gravity
- **Rate**: Proportional to speed (30 particles/sec at 300 px/s)
- **Lifetime**: 0.3-0.5s, fade out alpha over life

### Phase: RELEASE-LEAP (starburst pop)

```
        ✦ P
       /|\
      / | \  (radial burst)
  ░░░░░░░░░░░
```

On Circle release (boosted launch):
- **Starburst**: 12-16 radial lines from player position, 20-40px long
  - Color: White core → charge-color (yellow/orange) tips
  - Duration: 0.15s, rapid fade
- **Dust cloud**: 8-12 larger particles (4-8px), heavier gravity, 0.5s life
- **Screen shake**: Tiny (1px, 0.05s) — feels punchy, not disruptive

### Phase: ROPE-SLACK

```
                🪝
               ~
              ~  (slack rope)
             ~
        P ═══→ sliding
  ░░░░░░░░░░░░░░░░░
```

- When player contacts surface and starts sliding, rope goes slack
- Rope rendered as a drooping catenary curve (same verlet chain, but gravity pulls it down)
- Rope length stays constant — it just droops because the player is now closer to the anchor than the rope is long

### Phase: ROPE-TAUT (sproing)

```
                🪝
               /  ← snap!
              /   (chain stress effect)
             /
        P ─→  (launched or detached)
  ░░░░░░░░░░░░░░░░░
```

When rope transitions from slack to taut:
- **Chain stress flash**: Each rope segment briefly flashes white (0.1s, staggered from anchor → player)
- **Sproing vibration**: Rope oscillates side-to-side for 0.3s (decreasing amplitude)
  - Same visual as chain damage in the Executioner system
- **Sound**: "sproing" (high-frequency elastic snap)
- **Rumble**: Short (0.1s), medium intensity

### Phase: OFF-SURFACE (charge lost)

```
                🪝
               /
              / (taut — player pulled off)
             /
        P ·    (floating, no surface contact)
           (charge ring fades to red, shatters)
  ░░░░░░░░░░░░░░░░░
```

- Charge ring turns red and "shatters" (breaks into 4-6 arc segments that fly outward and fade)
- Brief red flash on player (0.1s)
- This tells the player: "you lost your charge"

## Debug Visuals (`player/slide` aspect)

### During SWING (approaching surface)
- Dashed yellow circle: impact detection radius (48px)
- Yellow probe line: direction to nearest surface

### During SLIDE
- **Yellow arrow**: full velocity vector
- **Green arrow**: surface normal (constant 40px)
- **Blue arrow**: surface-parallel component (slide speed)
- **Red arrow**: predicted launch if released NOW (with current charge multiplier)
- **White line**: surface tangent
- **Text**: "slide: NNN px/s  charge: NN%  ROPE|FREE|SURFACE"

### On SLIDE INITIATE (lingering 8s)
- Jump tracer snapshot: incoming velocity (green), surface normal (yellow), slide result (cyan)

### On LAUNCH (lingering 8s)
- Jump tracer: slide velocity (green), boost impulse (yellow), final launch (cyan)
- Charge multiplier displayed as text: "×1.35"

### Min/Max Extents
- During slide, draw thin horizontal/vertical lines showing the maximum extent the slide has reached (like a high-water mark)
- Color: dim cyan dashed lines
- Helps visualize total slide distance for tuning
