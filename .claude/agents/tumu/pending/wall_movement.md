# Wall Climbing, Wall Jumping, Careful Hop-Up

**Priority:** Medium — new movement modes, significant feature
**Depends on:** Gait tuning (ground locomotion should be solid first)

## Summary
The monster currently only interacts with horizontal surfaces. Wall interaction adds a new movement mode that leverages the 2.5D projection system.

## Tasks

### 1. Wall detection
- Add horizontal raycasts (left/right from body center)
- Detect wall proximity, direction, and surface normal
- Register as a new pathfinding option in precog system

### 2. Wall climbing
- Feet plant on vertical surfaces using rotated rest poses
- Body rotates 90° — the 2.5D projection handles the visual naturally
- Locomotion works sideways (foot push along wall instead of floor)
- Gait oscillation adapts to vertical movement
- Transition animation: approach wall → front feet reach up → rear feet push → body tilts → climbing

### 3. Wall jumping
- Push off wall with rear legs (visible compression + release)
- Launch arc away from wall
- Body rotates mid-air from wall-aligned back to horizontal
- Can chain: wall jump → land on opposite wall → climb

### 4. Careful hop-up (improved)
- Current hop-up is purely functional (instant compress → rise)
- New version: slower, more deliberate platform climb
- Front legs reach up and feel for the edge (raycasts from claw tips)
- Rear legs push one at a time (alternating, visible effort)
- Body pulls up with visible strain (spine compression)
- Head peeks over edge before committing
