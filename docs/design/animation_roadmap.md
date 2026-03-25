# Procedural Animation Roadmap

Captured from the v0.10.4–v0.10.9 session. The 2.5D projection system and movement blending are in place. These are the next areas to develop.

## Soon: Momentum & Speed Curves

The current speed blend is a linear ramp (`move_toward` at constant rate). Real creatures accelerate and decelerate with momentum — fast start is hard, stopping takes time, top speed has a ramp.

**What to build:**
- Replace linear speed blend with a configurable acceleration/deceleration curve
- Acceleration should be slower than deceleration (heavy creature builds speed gradually but can brake hard)
- Foot push force should scale with the speed curve — more force at high speed, less when starting
- Gait should visibly change: short choppy steps during acceleration, long fluid strides at top speed
- The `exag_floor_sprint` and `exag_speed_transitions` tests exercise this

**Configurable params (via `cfg()`):** `accel_rate`, `decel_rate`, `max_speed_ramp_time`, `stride_speed_curve`

## Soon: Attack Wind-up & Follow-through

Attacks currently snap into position. They should have visible anticipation and recovery.

**What to build:**
- Slash wind-up: shoulder coils back, weight shifts, brief pause before strike
- Slash follow-through: claw continues arc past impact, body weight carries forward, recovery pause
- Bite telegraph: head rears back, jaw opens wide, pause, then snap forward (some of this exists but needs more weight)
- Tail whip: bigger wind-up curl before the release

## Later: Wall Climbing & Wall Jumping

The monster currently only interacts with horizontal surfaces (floor raycasts). Wall interaction would add a new movement mode.

**What to build:**
- Horizontal raycasts to detect walls (direction + distance)
- Wall climbing: feet plant on vertical surfaces, body rotates 90deg, locomotion works sideways. The 2.5D projection system handles the visual rotation naturally
- Wall jumping: push off wall with rear legs, launch arc, rotate body mid-air back to horizontal
- Careful hop-up: slower, more deliberate platform climb. Front legs reach up and feel for the edge, rear legs push one at a time, body pulls up with visible effort (existing hop-up is purely functional)

## Later: More Exaggerated Animation Tests

Tests to add to `exaggerated_animations` suite as features are built:
- Attack wind-up showcase (bite, swipe, tail whip in sequence)
- Wall climb demo (if/when wall climbing is added)
- Multi-platform chase (monster follows dummy across P0→P1→P3→P4→P2→P0)
- Severed limb locomotion (monster with missing legs adapts gait)

## Foundation Already Built

These systems support all of the above:
- `_change_state()` with enter/exit hooks (v0.10.4–6)
- `_facing_target` / `_facing` blend with turn commitment (v0.10.7)
- 2.5D projection via `_projected_len()` and `_enforce_shoulder_3d()` (v0.10.9)
- `cfg()` runtime config system for per-spawn parameter tuning (v0.10.8)
- `exaggerated_animations` test suite for visual verification
