# The Ultimate Muffin

A 4-player local co-op PVE action game built in Godot 4.6.

Players battle through tower dungeons, fight bosses, and collect muffins across three game modes: top-down overworld exploration, side-scrolling tower platforming, and boss arena fights.

## Features

- **12 playable classes** with unique mechanics: Melee, Ranged, Mage, Summoner, Rogue, Demolitionist, Healer, Tank, Ninja, Balloonist, Guitarist, Werewolf
- **Physics-based grappling hook** (Ranger) with pendulum swing, rope slack, and Newtonian enemy tug
- **Parabolic arrow aiming** (Ranger) with arc solver, analog trigger power control, and power lock
- **Rift tentacle system** — class changes spawn physics-based tentacles that hunt players and buff enemies
- **4 bosses** with unique attack patterns and phases
- **18 enemy types** including 4 mini-bosses, each with a mass property for physics interactions
- **Persistent player profiles** with per-class skill leveling and XP
- **Controller haptics** — rumble feedback for grapple events, LED color matching class
- **Procedural background trees** with debug regeneration tools
- **Portal doorway** — atmospheric game start with stone archway, wooden doors, vortex, and fog
- **Level editor** (Ctrl+E) with JSON config system — spawn zones, positions, seeds, platforms, portal all editable
- **Title screen ecosystem** — fireflies with spawn-gravity zones and bats with perlin noise hunting
- **Migration patterns** — cyclic multi-phase movement sequences that drive wildlife across the level
- **Quadruped monster** — procedurally animated beast with foot-driven locomotion, 2-bone IK, head tracking, and pre-cognition pathfinding
- **Cave walls** — curved floor-to-wall transitions with collision, undulation, and standing ledges
- **RCON server** (port 9999) — remote console for automated testing, spawning, teleporting, debug control

## How to Play

- Connect 1-4 controllers (PS5, Xbox, or similar)
- D-pad up/down selects profile, left/right selects class
- Walk all players into the portal doorway to begin

### Ranger Controls
| Input | Action |
|-------|--------|
| Square | Fire crossbow (uses ammo) |
| L1 (hold/release) | Grappling hook windup and throw |
| L1 (while connected) | Phase 1: pull to anchor. Phase 2: disconnect |
| Jump (while connected) | Disconnect + jump impulse in stick direction |
| L2 (hold) | Aim mode — reticle + pull strength builds |
| R2 | Fire aimed arrow along solved parabolic arc |
| RB (during L2) | Reverse power, release to lock power level |

### Debug Mode
Ctrl+D toggles debug mode anywhere. Shows velocity arrows, button states, grapple tracers, archer arc trails. Press G near a procedural tree to regenerate it with a new seed.

## Downloads

See [Releases](https://github.com/jeremyprz/muffin/releases) for Mac, Windows, and Linux builds.

### macOS Users
Right-click the app, click **Open**, then **Open** again to bypass Gatekeeper. Or run:
```
xattr -cr "/Applications/The Ultimate Muffin.app"
```

---

## Release Notes

### v0.9.15
**Death Ball Grab, Down-Jump Loosening, Edge Case 8/8**
- Death ball grab attack: monster curls around player, clasps with front legs, kicks with rear, bites repeatedly, ejects after 2s
- Body collision enlarges during grab to trap the player (30px radius centered on target)
- Down-jump constraints loosened: 40% body radius, skip lateral clearance, gentle drops allowed
- Edge cases: 8/8 scenarios hit (was 5/8), time-to-first-hit 1.1-3.2s
- Baseline: 7-10/10 hit, 1055 total damage
- I key toggles debug draw on all enemies (no prerequisites)
- Debug text: compact layout, positioned opposite side of screen, no overlap
- Skeleton-to-world constraints prevent skull/tail clipping through geometry

### v0.9.14
**10/10 Hit Rate, Belly Sphere Collider, Skeleton World Constraints**
- Achieved 10/10 baseline hit rate (all scenarios deal damage)
- Body collider: circle sphere (r=14) rigidly attached to torso as hanging belly
- Skeleton-to-world constraints: skull, tail, spine pushed out of geometry via raycasts
- Airspace validation: arrival points under overhangs rejected via upward raycast
- Underside attack rejection: arrival points below target's platform filtered
- State lock timer (3s precog, 1.5s attack) eliminates same-floor strategy thrashing
- Strategy thrash scoring: tracks state changes since target moved
- IK quality scoring: spread + hover + stretch, queryable via RCON
- EPIC documentation with 6 prioritized stories and specific tasks
- Baseline: 9-10/10 hit, 590-780 dmg, IK/thrash/FPS tracked per scenario

### v0.9.13
**Realistic Trajectory Clearance, IK Scoring, 1395 Total Damage**
- LEAP_BODY_RADIUS increased from 22px to 55px — trajectories now account for the creature's actual size
- Creature no longer clips platforms mid-flight or squeezes through gaps it can't fit
- IK quality scoring system: spread (2pts/px over 30), stretch (5pts/px over max), hover (3pts/px above floor)
- IK score displayed in debug (green/yellow/red) and queryable via RCON (`ik`, `ikreset`)
- Automated baseline: 9/10 scenarios deal damage, 1395 total, same-floor-near deals 905
- FPS stable at 54-99 without debug draw (debug draw toggleable via RCON `debugdraw`)
- Async graph building (5 pairs/frame), precog cooldown (2s), leap cooldown (2s)
- Sprint slash, connected hop-up, direct leap all tuned for appropriate scenarios
- Foot landing re-raycasts floor to prevent floating feet after steps
- Out-of-bounds teleport recovery

### v0.9.12
**9/10 Baseline, IK Fixes, FPS Stability**
- Automated baseline: 9/10 scenarios deal damage, min FPS 60 (never dips)
- IK leg clamping: feet stay under the body, only corrected at 2x max reach
- Async graph building: 5 pairs per frame, no single-frame stutter
- Precog cooldown: 5s between triggers, prevents infinite loop FPS crash
- Wonky leg detection: feet that reach to lower platforms are auto-corrected
- Knee snap at 2x stiffness prevents oscillation/sticking
- Step threshold 35px for responsive foot placement
- Dummy player tracks HP/damage, displays on-screen, routes take_damage correctly
- RCON: fps, hp, resethp commands for automated measurement

### v0.9.11
**Speed Overhaul, Sprint Slash, Connected Hop-Up**
- Ruthless panther: instant precog when target is on a different platform (no timer wait)
- Pre-cached platform graph at spawn — Dijkstra pathfinding is instant
- Sprint slash: same-plane charge at 250 speed + 3 rapid alternating claw swipes
- Connected hop-up: short platform climb with feet connected to both surfaces
- Movement doubled: slow 60, medium 140, fast 240 px/s
- Attack cooldown 0.8s, leap cooldown 4s, leap windup 0.6s
- Out-of-bounds recovery: teleport back to spawn if monster falls off screen
- Debug draw toggle (`debugdraw` via RCON) — disable heavy visual rendering for performance
- Automated baseline: 7/10 scenarios succeed in 0.7-5.5s average

### v0.9.10
**Pre-cognition Pathfinding, RCON Server, Automated Testing**
- Pre-cognition system: when the monster can't hit a player for 5s, it curls up and plans a multi-hop route across platforms
- Ball-drop platform detection: grid of virtual balls covers the entire map, landings are Y-snapped and grouped into surfaces
- Dijkstra pathfinding across the platform connectivity graph to find shortest route from monster to target
- Destination-aware arc clearance: ignores hits on the landing platform so upward leaps aren't falsely rejected
- IK skeleton reset after landing: spine returns to horizontal, feet raycast to floor
- RCON server (TCP port 9999): debug, spawn monster/dummy, teleport, tab, key simulation, clear enemies, force precog, status
- Dummy player: controllerless target with gravity and collision for automated testing
- Automated test script (`scripts/test_precog.sh`): 6/6 positions with successful pathfind + leap execution
- Debug visualization: platform bars, graph edges, Dijkstra path, waypoint markers, precog phase status

### v0.9.9
**Quadruped Leap Planning, Head Pivot, Cave Walls, Keystone Platform**
- Vertical leap attack with reverse trajectory planning: finds open-air strike zones around the target, then reverse-solves parabolic launch velocities to reach them
- Two-phase planning: broad search (12 arrivals × 5 flight times) then refinement around near-misses (5 positions × 7 times)
- 5-stage leap sequence: plan → windup (coil/compress) → airborne (missile alignment) → 6-slash barrage → bite+thrash+fling
- Body-width clearance: 3 parallel arc raycasts (left, center, right edge) ensure the creature fits through gaps
- Head pivot: skull/jaw/eye/teeth rotate in head-local space to face the target; stays upright on direction flip
- Paired stepping: one front + one rear foot at a time, rear legs trail behind the body
- Foot-driven locomotion: feet grip ground in world space and push the body via force
- 2-bone IK with mammal anatomy (front elbows backward, rear knees forward)
- Cave walls with CollisionPolygon2D: curved floor-to-wall transitions, flat ledge shelf at 1/3 height
- Portal keystone is a standable platform (48px wide StaticBody2D)
- Debug entity inspector: TAB cycles enemies, shows skeleton, strike zone, trajectory planning, target crosshair with distance
- Comprehensive design doc at docs/design/quadruped_monster.md

### v0.9.8
**Quadruped Monster, Cave Walls, Debug Inspector**
- Quadruped monster: procedurally animated 23-point skeleton with foot-driven locomotion
- Feet grip the ground in world space and push the body forward — body moves as a result of foot forces
- 2-bone IK solves knee positions; mammal anatomy (front elbows backward, rear knees forward)
- Head pivots to track target: skull, jaw, eye, teeth all rotate in head-local space
- Paired stepping: one front foot + one rear foot move at a time, rear legs trail behind
- Bite, claw swipe, tail whip, and lunge attacks; aggro switches after 3 hits from another player
- 7 independently damageable/severable body parts (body, head, tail, 4 legs)
- Cave walls: curved CollisionPolygon2D floor-to-wall transitions on both sides of the room
- Flat ledge shelf at 1/3 height for standing; undulation, rock texture, depth shading
- Debug entity inspector: TAB cycles enemies, shows skeleton, foot targets, state, target crosshair
- Debug M key spawns a quadruped on the title screen

### v0.9.7
**Rift Tentacle Physics**
- Rift tentacle segments now resist movement with verlet drag (0.92 velocity retention per frame)
- When attached to an enemy, only the anchor segment tracks it — the rest trail behind under physics
- Bidirectional constraint solver (5 iterations, forward+reverse passes) propagates forces both ways along the chain
- Pulling either end tugs the entire tentacle with visible lag and resistance
- Rift orb draws at anchor segment, staying attached to the enemy as it moves

### v0.9.6
**Migration Patterns**
- Migration patterns: cyclic multi-phase species movement — wildlife migrates between configurable zones on a timer
- Per-species patterns with independent zones (fireflies and bats each have their own pattern)
- Stagger mode: random phase offset per individual so not all entities migrate in lockstep
- Bat repulsion: bats strongly repel each other within 120px
- Level editor MIGRATION mode: drag zone centers/radii, X to delete zones, N/Del for phases, +/- for zones, S to switch species, G to toggle stagger, left/right arrows for cadence (1s steps)
- Species and cadence shown in editor top bar, species label on each zone circle

### v0.9.5
**Level Editor, Fireflies & Bats, Archer Reticle Fix, Menu Overhaul**
- Level editor (Ctrl+E): JSON-based config system for all level layout — spawn zones, P1-P4 positions, seeds, platforms, portal position
- 5 editor modes: SPAWN_AREAS, SPAWN_POSITIONS, SEEDS, PLATFORMS, PORTAL with mouse drag on vertices/handles
- Ctrl+S saves level edits, Ctrl+R resets to bundled defaults, live rebuild on every change
- Fireflies: spawn-gravity zones with per-fly home points, 20% glow time, deficit-scaled spawn rate (1x-5x)
- Bats: perlin noise movement via FastNoiseLite, firefly hunting within 100px, 5s hunger cooldown, max belly of 5
- Archer auto-target: gold portal-style sense effect (glow, rays, particles) that dissipates over 0.5s
- Fix: archer manual reticle was orphaned inside auto-target draw function — now renders reliably when L2 held
- Fix: trigger detection uses analog axis with hysteresis (0.1 start, 0.05 stop) instead of nonexistent button constants
- All menus support thumbstick, D-pad, and mouse input (3 input methods everywhere)
- Fix: pause mapped to Options button (was D-pad UP), D-pad navigation works in pause menu
- Profile select sub-mode in pause menu with HUD popups
- Auto-select profile's preferred class when cycling profiles on title screen
- Grapple hook connection no longer inflicts damage
- HUD aura fades out over 1 second when popup dismissed
- Portal stone pillars: per-stone X-only jitter, dark wood frame strips behind pillars
- Ctrl+D toggles debug mode anywhere (title screen, gameplay, pause menu)

### v0.9.4
**Critical Fix & Procedural Rocks**
- Fix: `Input.set_joy_light()` caused a parse error in export builds, preventing the entire player script from loading. Controllers could select classes but not move characters. Fixed via runtime `call()` dispatch.
- Procedural vector rocks with faceted plane shading (Kats Pixels technique)
- Configurable light direction, highlight intensity, and highlight width on rocks
- Grey and red-brown rock palettes with directional shadow/base/lit/highlight shading
- Debug: press G to regenerate nearest procedural scenery item (trees and rocks)
- README.md with full release notes

### v0.9.3
**Portal Doorway & Procedural Trees**
- Stone archway with wooden double doors, keystone, and decorative transom with muffin symbol replaces "Press START to begin"
- Doors creak open when a player approaches, fog creeps along the floor
- Slow-spinning blue vortex with layered glow, speeds up during pull-in
- All players must stand in the doorway for 5 seconds to transition
- Deep bass drone sound while doors are open
- Procedural background trees with multi-layered leaf canopy (3 green shades)
- Debug: press G to regenerate nearest tree with a random seed
- Archer can now aim and shoot while swinging on grapple
- Fix: health sparkle particles no longer leak after pickup
- Fix: grapple hook follows moving platforms via anchor body tracking
- Fix: title screen raised 40px so players render above HUD bar

### v0.9.2
**Portal Doorway (initial), Keystone & Vortex Polish**
- Initial portal doorway implementation
- Trapezoidal capstone centered on arch peak
- Vortex rotation reduced to barely-noticeable drift
- Pull-in gradually speeds up the vortex
- Arch-following wooden slats behind stone arch
- Bass drone sound (beam_fire at 0.12 pitch)

### v0.9.1
**Archer Aimed Shot, Grapple Polish, Debug System, Controller Features**
- Physics-based archer aimed shot with quadratic arc solver (L2/R2)
- Analog trigger pull = proportional max power. RB locks power level.
- Grapple moved to L1 with full movement during windup
- Two-phase disconnect: pull toward anchor, then release
- Jump-release adds impulse in thumbstick direction (additive to swing momentum)
- Rope slack physics: free movement above anchor, bounce at rope end
- Launch immunity preserves momentum through freefall until landing
- Either thumbstick aims grapple (right priority)
- Controller rumble at all grapple events (scales with velocity)
- Controller LED matches class color via Godot 4.6 Input.set_joy_light
- Debug mode (SELECT): velocity arrows, jump prediction, tracer snapshots, HUD button state
- Debug tracer arrows linger 10s on grapple jump-release
- Archer debug: solver arc (orange) and arrow trail (cyan) linger 10s
- Velocity audit system documented (not yet implemented)
- Profile saves last class choice, auto-selects on rejoin
- In-game class change requires button press before rift spawns
- Out-of-bounds players teleported back via purple aether rift
- Entity mass system: all 18 enemies + bosses + player have mass values
- Grapple tug uses Newtonian F=ma on both ends based on mass

### v0.9.0
**Inline HUD, Rift Tentacles, Health Drops, CI Pipeline**
- Inline player HUD replaces overlay menus — D-pad selects profile/class directly
- HUD shows class sprite, name, HP/mana bars, tentacle status
- Camera reserves 90px for bottom HUD strip
- Rift tentacle spawns on class change with verlet physics (14 segments)
- Tentacle hunts players (4 smashes) and enemies (permanent attach + buff)
- Tentacle sub-health (50 HP) absorbs damage, rift shrinks as health drops
- 25% health drop on enemy death — green + shaped pickup, heals 15 HP
- Fix: boss pseudo-enemy squares (wrong skeleton scene path, pants leak)
- 3-tier version system (MAJOR.MINOR.PATCH)
- GitHub Actions CI: builds Mac/Windows/Linux on tag push
- macOS build on native runner with proper codesign

### Pre-v0.9.0
**Core Game Development (EPICs 1-26)**
- 12 character classes with full ability sets
- 4 bosses: Gingerbread Skeleton, Icing Goblin, Sprinkle Dragon, Giant Muffin
- 13 regular enemies + 4 mini-bosses
- 18 trap/obstacle types
- Overworld with 3 towers + final tower gating
- Procedural tower generation with platforms, enemies, and collectibles
- Character leveling (4 skills per class, max level 20)
- Persistent profiles saved to JSON
- Pause menu, death/revive system, scene transitions
- Demolitionist rocket jetpack with chaos mechanics
- Balloonist physics with H2 gas explosions
- Guitarist with Karplus-Strong string synthesis audio
- Werewolf frenzy mode
- Ninja triple-slash and air jumps
- 39 sound effects
- Complete pixel art overhaul (all 12 classes, 4 bosses, enemies, environment)
