# EPIC: Physics-Based Chain System

## Overview

Replace the current single-Node2D chain with a proper multi-body physics chain using RigidBody2D segments linked by PinJoint2D connections. Links are rigid (no flex), can rotate at joints, and interact with specific objects. Ropes should work similarly but with more segments and spring behavior.

## Design Decisions (from discussion)

- **Joint type**: PinJoint2D at each connection — links rotate freely but can't stretch
- **Link size**: Fixed configurable size per link (e.g., 8px). Chain gets as many links as needed to cover the distance. Configurable constant for tuning performance.
- **Performance**: May need optimization — multiple chains × 20+ bodies each. Link count and physics settings tunable.
- **Interaction**: Chains interact with SOME objects:
  - Players can walk through (no collision with player layer)
  - Hammer hits deal damage to nearby chain sections (proximity-based)
  - Chain links collide with world geometry (drape over platforms)
- **Endpoints**: FIXED in world coordinates (PinJoint2D or StaticBody2D anchor). Once calculated from raycast, endpoints don't move.
- **Rope parity**: Ropes should work the same architecture but with more segments and DampedSpringJoint2D for elasticity.

## STORY 1: RigidBody2D Chain Links

Replace chain rendering with actual physics bodies.

### Tasks

- [x] **1.1** Define `CHAIN_LINK_LENGTH` constant (configurable, default 8px)
- [x] **1.2** On chain creation: calculate number of links from `target_length / CHAIN_LINK_LENGTH`
- [x] **1.3** Spawn each link as a `RigidBody2D` with a small `RectangleShape2D` collision shape
- [x] **1.4** Each link has `collision_layer` that excludes players but includes world
- [x] **1.5** Connect links with `PinJoint2D` — allows rotation, prevents stretch
- [x] **1.6** Endpoint A: `PinJoint2D` connecting first link to a `StaticBody2D` at the wall/creature attachment point
- [x] **1.7** Endpoint B: same as A for the other end
- [x] **1.8** Rendering: alternating thin/thick segments from each link's position (existing visual style)

## STORY 2: Chain Physics Behavior

Configure the physics properties for realistic chain behavior.

### Tasks

- [x] **2.1** Each link: mass proportional to link size, gravity enabled
- [x] **2.2** Links naturally drape under gravity when slack
- [x] **2.3** Chain hangs in catenary when suspended between two points
- [x] **2.4** When creature moves, chain follows through joint physics
- [x] **2.5** Angular damping on links to prevent wild spinning
- [x] **2.6** Linear damping to reduce oscillation

## STORY 3: Chain Damage System

Damage individual chain sections based on proximity to impacts.

### Tasks

- [x] **3.1** Each link has its own HP (derived from chain's total HP / link count)
- [x] **3.2** Projectile/hammer hits deal damage to the nearest link(s) within proximity
- [x] **3.3** When a link's HP reaches 0, the chain breaks at that point
- [x] **3.4** Breaking: links on each side become separate chains (or fall freely)
- [x] **3.5** Shake/flash feedback on the damaged link (existing visual)
- [x] **3.6** Sound effect on break (metallic snap)

## STORY 4: Rope Parity

Ropes use the same architecture with different physics properties.

### Tasks

- [x] **4.1** Rope links: smaller, more numerous (e.g., 4px segments vs 8px)
- [x] **4.2** Rope joints: `DampedSpringJoint2D` instead of `PinJoint2D` — allows slight stretch
- [x] **4.3** Lower mass per segment, more linear damping
- [x] **4.4** Rope rendering: thinner, brown color (existing)
- [x] **4.5** Same endpoint pinning system as chains

## STORY 5: Creature Attachment

Chains connected to creatures follow the creature's movement.

### Tasks

- [x] **5.1** Creature endpoint: PinJoint2D attached to a kinematic point that tracks the attachment point position
- [x] **5.2** As creature moves, the kinematic anchor moves, and chain physics responds
- [x] **5.3** When creature is `_physics_frozen`, anchor stays fixed
- [x] **5.4** Breakaway: when all chains on a creature break, trigger breakaway sequence

## Implementation Priority

1. **Story 1** — Core: RigidBody2D links with PinJoint2D
2. **Story 2** — Physics tuning
3. **Story 5** — Creature attachment
4. **Story 3** — Damage system
5. **Story 4** — Rope parity

## Key Constants (Tunable)

| Constant | Default | Description |
|----------|---------|-------------|
| `CHAIN_LINK_LENGTH` | 8.0 | Length of each chain link in pixels |
| `CHAIN_LINK_MASS` | 0.5 | Mass per link |
| `CHAIN_LINK_DAMPING` | 0.3 | Angular damping to reduce spin |
| `CHAIN_LINEAR_DAMPING` | 0.1 | Linear damping to reduce oscillation |
| `CHAIN_MAX_LINKS` | 50 | Performance cap on links per chain |
| `ROPE_LINK_LENGTH` | 4.0 | Rope segment size |
| `ROPE_SPRING_STIFFNESS` | 100.0 | Spring force for rope joints |
| `ROPE_SPRING_DAMPING` | 5.0 | Damping for rope springs |
