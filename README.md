# The Ultimate Muffin

A 4-player local co-op PVE action game built in Godot 4.6.

Players battle through tower dungeons, fight bosses, and collect muffins across three game modes: top-down overworld exploration, side-scrolling tower platforming, and boss arena fights.

## Controls

### Controller (PS5 / Xbox)

| Button | Gameplay | Ranger Grapple | Menus |
|--------|----------|----------------|-------|
| **Left Stick / D-pad** | Move | Swing boost/brake (horizontal), adjust rope length (vertical) | Navigate |
| **Cross (A)** | Jump | Disconnect + jump impulse | Select |
| **Square (X)** | Attack / Fire crossbow | — | Select |
| **Triangle (Y)** | Special ability | — | Delete character |
| **Circle (O)** | Interact / Reload | — | — |
| **L1 (bumper)** | Grapple: hold to spin, release to throw | While connected: second hook for tether | — |
| **R1 (bumper)** | — | Pull to anchor | — |
| **L2 (trigger)** | Archer aim mode (analog power) | — | — |
| **R2 (trigger)** | Fire aimed arrow | — | — |
| **L3 (left stick click)** | Block | — | — |
| **Start / Options** | Join game / Pause | — | Confirm |
| **Select / Share** | Debug toggle | — | — |
| **Right Stick** | Archer reticle position | Aim direction for throw | — |

### Keyboard

| Key | Action |
|-----|--------|
| **W/A/S/D** | Move |
| **Space** | Jump |
| **J** | Attack |
| **K** | Special ability |
| **F** | Interact |
| **G** | Grapple (hold/release) |
| **Shift** | Pull to anchor (R1) |
| **Tab** | Archer aim (L2) |
| **Enter** | Fire aimed arrow (R2) |
| **Left Arrow** | Block |
| **Escape** | Pause |
| **Backtick (`)** | Debug toggle |

### Title Screen

| Input | Action |
|-------|--------|
| **Press any button** | Join / materialize ghost player |
| **Move** | Ghost player movement before materializing |
| **Jump (when dead, solo)** | Self-revive |
| **Ctrl+D** | Toggle debug mode |
| **Ctrl+E** | Toggle level editor |
| **Ctrl+T** | Test menu |
| **?** | Help overlay (all commands) |
| **M** (debug) | Spawn quadruped monster |
| **G** (debug) | Regenerate nearest tree |

### Level Editor (Ctrl+E)

| Input | Action |
|-------|--------|
| **Tab** | Cycle mode: Spawn Areas → Positions → Seeds → Platforms → Portal → Migration → Splay → Splay Edit |
| **Ctrl+S** | Save level |
| **Ctrl+R** | Reset to defaults |
| **Mouse drag** | Edit positions and sizes |
| **1-9** (Migration) | Select phase |
| **N** (Migration) | Add phase |
| **Del / Backspace** (Migration) | Delete last phase |
| **+** (Migration) | Add zone |
| **S** (Migration) | Cycle species |
| **G** (Migration) | Toggle stagger |
| **Left/Right** (Migration) | Adjust cadence (1s steps) |
| **N** (Splay) | Add splay instance |
| **P** (Splay) | Pose library browser |
| **E** (Splay) | Enter pose editor |
| **B** (Splay) | Cycle behavior (asleep/stand_down/active) |
| **Left/Right** (Splay) | Rotate instance |
| **Up/Down** (Splay) | Cycle pose |
| **SPACE** (Splay Edit) | Toggle connection point on/off |
| **Shift+SPACE** (Splay Edit) | Dump skeleton JSON to logs |
| **C** (Splay Edit) | Toggle rope/chain |
| **P** (Splay Edit) | Toggle pin (joint doesn't move during IK) |
| **M** (Splay Edit) | Toggle mirror mode (L/R symmetric) |
| **L/R/U/D** (Splay Edit) | Preset poses |
| **Arrows** (Splay Edit) | Nudge cast endpoint |
| **Drag** (Splay Edit) | IK-drag connection point / cast endpoint / origin |

### RCON Commands (TCP port 9999)

```
help, debug, spawn <monster|dummy|attacker> [x y], tp <x> <y>, tab [n],
key <k>, enemies, players, precog, status, quit, clear, clearplayers,
enablejoins, revive, resethp, fps, hp, ik, ikreset, thrash, ball,
debugdraw, title, score, grid,
standdown [on|off], territorial [on|off], partstatus, partdmg <part> <amount>,
weight, attach balloon <point>, detach <point>,
tether <idx> <point> floor [len], tether <idx1> <pt1> <idx2> <pt2> [len],
tether wall <x1> <y1> <x2> <y2> [len], tether length <px>,
tether cut, tether status,
chain <idx> <point> floor [len], chain status, chain cut,
splay list, splay spawn <pose> [x y] [rot] [behavior], splay clear, splay status,
dump [enemy_idx] [trigger],
attacker <target|part|weapon|rate|stop|start|stats|tether_length|tether_b>
```

---

## Features

- **12 playable classes** with unique mechanics: Melee, Ranged, Mage, Summoner, Rogue, Demolitionist, Healer, Tank, Ninja, Balloonist, Guitarist, Werewolf
- **Physics-based grappling hook** (Ranger) with pendulum swing, rope slack, and Newtonian enemy tug
- **Dual-grapple tether system** (Ranger) — connect two points with a physics rope that pulls to a chosen length, max 5 active tethers
- **Parabolic arrow aiming** (Ranger) with arc solver, analog trigger power control, and power lock
- **Rift tentacle system** — class changes spawn physics-based tentacles that hunt players and buff enemies
- **4 bosses** with unique attack patterns and phases
- **18 enemy types** including 4 mini-bosses, each with a mass property for physics interactions
- **Persistent player profiles** with per-class skill leveling and XP
- **Controller haptics** — rumble feedback for grapple events, LED color matching class
- **Procedural background trees** with debug regeneration tools
- **Portal doorway** — atmospheric game start with stone archway, wooden doors, vortex, and fog
- **Splay pose system** — position creatures in custom poses with chains/tethers to walls, full skeleton snapshot save/restore, breakaway at 50% damage
- **Chain system** — zero-stretch rigid connections with shackles, peg+ring wall mounts, 2000 HP, shake/flash on damage
- **Level editor** (Ctrl+E) with JSON config system — spawn zones, positions, seeds, platforms, portal, splay instances all editable
- **Title screen ecosystem** — fireflies with spawn-gravity zones and bats with perlin noise hunting
- **Migration patterns** — cyclic multi-phase movement sequences that drive wildlife across the level
- **Quadruped monster** — procedurally animated beast with foot-driven locomotion, 2-bone IK, head tracking, pre-cognition pathfinding, vulnerable body parts with tiered damage, and attachment points for balloons/tethers
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
| L1 (while connected) | Tether: second hook windup + throw (connects two points with rope) |
| R1 (while connected) | Pull toward anchor |
| Jump (while connected) | Disconnect + jump impulse in stick direction |
| D-pad UP/DOWN (while swinging) | Adjust rope length (sets tether target length) |
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

### v0.10.2
**Test Gate System, Suite Partitioning, Release Workflow**

- Test suites now have `"gate": true/false` field — gate suites auto-run, non-gate suites are manual-only
- Gate suites (`chained`, `combat`, `leaping`, `scaling`) partition all 27 tests with no overlaps
- Non-gate suites (`all`, `todo`) excluded from automated gating
- New `scaling` gate suite for scaled monster tests
- `combat` suite expanded: added `quick` and `verify_leap_graph_P0_P1` to close coverage gaps
- `/test-gate` command: checks staleness via `ts/<suite>/pass` and `ts/<suite>/fail` git tags, runs stale suites, records results
- `/release` command: pushes trunk + version tag, enforces all gate suites passing at HEAD
- `/ship-it` command: bumps patch version, updates docs, writes release notes, commits

### v0.10.1
**Procedural Monster Scaling, Splay Scale Controls, Chain Scaling**

- Single `creature_scale` float controls all monster dimensions (skeleton, collision, drawing, combat, pathing)
- `sc()` helper scales 260+ spatial constants automatically; scale 1.0 is identical to pre-scaling behavior
- Speed auto-scales with size; `speed_override` decouples speed from size
- `pathing_radius` override lets large monsters path through standard-sized gaps
- `spawn monster X Y [state] [scale=N] [pathing_radius=N]` RCON syntax
- Splay manager spawns scaled creatures with scaled skeleton snapshots, connection offsets, and chain distances
- Chain link width, shackles, wall pegs/rings scale with creature size
- Tether rope width, hooks, and fray effect scale with creature size
- Debug drawer: live scale slider on TAB-selected monster (Ctrl+D)
- Level editor splay widget: draggable rotation handle (cyan circle) and scale handle (green diamond)
- `splay spawn` RCON and level config support `scale=N`
- All monsters auto-assign `entity_id` in `_ready()` via static counter
- Level editor save dialog click detection fixed (screen-to-world coordinate conversion)
- New test: `giant_floor_to_P3` (two scaled monsters, 0.5x and 2.0x, hunt one target)
- Debug aspects: `scaling/active_scale`, `scaling/effective_radii`, `scaling/speed_info`

### v0.10.0
**In-Game Test Editor, Arc Planning Fixes, Bounded Leap System — 25/26 tests pass (96%)**

**In-Game Test Editor:**
- Visual test editor (Ctrl+T → Tests...) with draggable control points for all command types
- Spawn, bleap, ETZ/DAZ, fence, exit_circle — all editable in the game world
- Floating window: numbered script list, click to select, inline text editing with Tab autocomplete
- Run mode: per-line execution state (pending/running/complete), auto-select failed row
- Suite runner with prev/next navigation, position in title bar [N/M]
- Notify system with variable substitution (`var owait default=0`)
- Double-click to execute single line, drag-drop row reordering
- Post-run review: violations render as body circles (r=55), breach markers shown
- `suite all owait=0` runs all 26 tests; `suite todo owait=600` for interactive review

**Arc Planning Fixes (P1):**
- Body circle clearance via `intersect_shape` with `CircleShape2D` at each arc point
- Dynamic radius reduction near destination: full radius mid-flight, fades when directly above landing zone
- Below-surface cap: radius limited so body can't reach UP and clip platform from underneath
- Higher arcs: LEAP_FLIGHT_TIME_MAX 1.2→1.6, LEAP_FLIGHT_TIMES 5→7
- Finer simulation: LEAP_ARC_STEPS 16→40, LEAP_ARC_DT 0.04→0.03
- Gap detection: same-level platforms trigger precog when floor probe finds no ground at midpoint
- Horizontal bounding arcs (arc_l/arc_r) replace diagonal launch-perpendicular offset

**Bounded Leap Monitor:**
- Continuous graph monitoring during wait (polls every 0.5s)
- Collects matches and violations over test lifetime
- MATCHED = START+END fit, no disallow breach; VIOLATION = START+END fit but arc clips disallow
- Unmatched arcs (fail START/END) silently ignored — not violations
- `bleap next` accumulates multiple leap defs; single `check bounded_leaps` evaluates all
- Monitor checks body circle (r=55) against disallow capsules

**Breach Fences & Exit Circles:**
- `wait N unless breach X1 Y1 X2 Y2 patterns...` — finite segment trip wire
- `wait N unless exit_circle X Y R patterns...` — abort if entity leaves circle
- Fences are TRUE segments: perpendicular distance limit (50px), strict [0,1] span
- Breach markers rendered in editor (orange circle with L<line>[idx] label)
- Breach just aborts wait — not a test failure

**Test Infrastructure:**
- All 26 tests in script format with parameterized `notify` and `var owait default=0`
- Comprehensive JSON output: `user://test-output/<version>/<test>/<timestamp>/results.json`
- Suite output: `user://test-output/<version>/<suite>/<timestamp>.json`
- Test state machine: INITIALIZING → RUNNING → COMPLETE → FINALIZED
- `suite all` runs all tests; `suite todo` runs failing tests only
- RCON key=value args: `suite all owait=600`, `run test owait=10`
- Auto-clear zones and debug state between suite tests

**Console Improvements:**
- Cursor position, text selection, Ctrl+A/C/X/V cut/copy/paste
- Test name autocomplete for `testload`, `run`, `testsave`, `suite`
- `run` and `suite` from console route through RCON (consistent arg parsing)

### v0.9.25
**Chain Surface Collision, Physical Chain Constraints, Console Autocomplete**

**Chain Surface Collision:**
- Verlet chain points raycast in 4 directions (down, up, left, right)
- Chains drape over platforms, rest on ledges, slide against walls
- Surface friction dampens horizontal sliding
- Only collides with world geometry (players pass through)

**Physical Chain Constraints:**
- Leaps/precog/lunges all allowed for chained creatures — chain physically limits reach
- On-floor: horizontal-only constraint (Pythagorean max-X at current Y)
- Airborne: full 2D constraint with floor clamp (no clipping through geometry)
- Chain constraint runs before move_and_slide (respects floor collision)
- Standdown off now forces CHASE state + picks target

**Console Autocomplete (Tab):**
- Tab cycles through matching commands
- Completes RCON commands, test names (`run <tab>`), suite names (`suite <tab>`)
- Current match highlighted in [brackets] above input line
- Up to 8 matches shown with overflow indicator

**Chained Monster Tests:**
- chained_floor: monster attacks nearby dummy within chain reach
- chained_reach: dummy beyond chain length (expects 0 damage)
- chained_above: dummy on platform above (expects 0 damage)
- Test setup: spawn standdown → chain → spawn dummy → wake

**Portal Safety:**
- Portal disabled state persists across level rebuilds (stored as scene meta)
- Re-applied every 60 frames to catch recreated portal nodes

### v0.9.24
**Chained Creature AI, In-Game Console, Portal Test Safety**

**Chained Creature AI:**
- Active chained creatures walk, chase, and attack within chain reach
- Horizontal chain constraint: uses Pythagorean max-X at current Y (no vertical yanking)
- No precog pathfinding for chained creatures (can't multi-hop)
- No leaping for chained creatures
- Stale precog waypoints cleared on spawn
- Chain constraint applied before move_and_slide (floor collision respected)
- Asleep chained: stays frozen, zero velocity
- Awake + on floor: full AI with chain limits
- Awake + suspended: dangles with gravity, limbs enforced

**In-Game Console (backtick `):**
- Quake-style pop-down console, accepts all RCON commands
- Test runner: `run <test>`, `suite <name>`, `tests`
- File-based tests (JSON): setup commands, wait, checks
- 13 combat test files + combat suite
- Frame-based task queue for sequential test execution
- Command history, scrollable output, color-coded results

**Editor Fixes:**
- Ctrl+E works on first press
- Splay drag: stored creature reference (no proximity guessing)
- Splay drag: Verlet chain points shift with creature
- Rotation ring in splay edit (drag to rotate all points around origin)
- FABRIK: 30 iterations, angle corrections propagate downstream

**Portal Test Safety:**
- `portal off` RCON command disables portal transitions
- All test scripts + JSON test files include portal off in setup
- Prevents test dummy from triggering level transition

### v0.9.21
**Verlet Chain Physics, Chained Creature Mode, Breakaway Fix, Pose Lock Fix**

**Chain Physics (Verlet):**
- Position-based Verlet integration with Jakobsen constraint solving
- Chains drape naturally under gravity with fixed-length segments
- Iterations scale with chain length for convergence
- Chain HP reduced to 200 for faster breakaway testing
- Alternating thin/thick dark grey rendering with shackles + peg/ring
- RCON: chaindump — detailed per-point position + distance report

**Chained Creature Mode:**
- `_chained` flag: creature has gravity but chains constrain position
- Chain constraints clamp CharacterBody2D position each frame
- Velocity along chain direction killed when taut
- Asleep + not on floor = go limp (limbs dangle)
- Awake + on floor = try to stand/walk within chain reach

**Breakaway Fix:**
- Tracks total ORIGINAL HP across ALL chains (including severed ones)
- Breakaway triggers when 50% of original aggregate HP is destroyed
- On breakaway: state forced to CHASE, _pick_target() called immediately
- Creature targets nearest player after breaking free

**Pose Lock Fix:**
- `_enforce_spine_rigid()` skips angle constraints when `_pose_locked`
- Only distance enforcement runs — preserves non-standard orientations
- Fixes body kinking sideways for vertically-posed splayed creatures
- Neck/skull angle constraints also skipped when pose_locked

**Test Menu:**
- "Clear Level" (was "Reset Level") — clears enemies/players
- "Restart Level" — full scene reload (game reboot)

### v0.9.20
**Editor Change Tracking, Source Mode Detection, Save Original/Custom Workflow**

**Source Mode Detection:**
- `Version.is_source_mode()` — detects running from source code (checks `res://project.godot`)
- "[DEV]" badge shown in editor when in source mode
- Source-only operations: save original, delete bundled poses

**Editor Save Workflow (Original / Custom):**
- Ctrl+S shows O/C dialog with clickable buttons and keyboard shortcuts
- _O_riginal: saves to `res://` (source authority), deletes custom override
- _C_ustom: saves to `user://` (user override)
- Works for both level configs AND splay poses (same UX)
- Non-source builds: only Custom save available

**Change Tracking:**
- Per-component tracking: which items have unsaved changes
- Yellow asterisk (*) on changed splay instances in editor overlay
- Summary bar: "2 splays changed, 1 migration changed" (only non-zero)
- Custom/Original status: "(CUSTOM - N unsaved changes)" or "(ORIGINAL)"

**Pose Library Enhancements:**
- Usage tracking: scans all level configs, shows "Used in: level(count)" per pose
- CRUD: N=new, Del=delete, E=edit
- Unused poses shown dimmed
- Missing pose references: RED outline, click to replace or delete

**Splay Editor Fixes:**
- Drag/rotate/cycle no longer trigger full level rebuilds
- Creature moves directly when dragging splay instance marker
- I-pose: renamed from t-pose (body=I stem, arms/legs=I serifs)
- Save dialog: O/C choice with underlined hotkeys, clickable buttons
- ESC from edit rebuilds level to restore all splay creatures

### v0.9.19
**Splay Pose System, Chain System, Skeleton Rigidity, Editor Overhaul**

**Splay Pose System:**
- Creatures positioned in custom poses with chains/tethers to walls
- Pose editor (Ctrl+E → SPLAY → E): preset poses (L/R/U/D), FABRIK IK drag, pinned joints, mirror mode
- Full skeleton snapshot saved in pose JSON — exact restoration on reload and spawn
- Poses auto-spawn from level config on level load
- 3 behaviors: active, stand_down, asleep (dormant until damaged)
- Breakaway at 50% aggregate tether damage — flash, screen shake, creature wakes
- Pose library browser (P key) with preview thumbnails
- Multi-creature splay support with inter-creature tethers

**Chain System:**
- Zero-stretch rigid connections (hard position correction every frame)
- 2000 HP, damage per hit capped at 5
- Shackles at creature end (sized to limb), peg+ring at wall end
- Alternating thin/thick dark grey segments, fixed-length rendering
- Shake + flash damage feedback on hit
- RCON: chain commands parallel tether commands

**Skeleton Rigidity:**
- 4 new bones: clavicle L/R (from shoulders), hip bone L/R (from waist)
- Clavicles/hip bones rotate with body orientation
- Upper limbs rigid (exact length), lower limbs ±10% flex
- Tail segments: rigid ±5% flex, max 20° bend per joint
- Spine joints: max 30° bend, neck joints: max 45° bend
- All rigid constraints enforced in ALL states (leap, grab, precog)
- Planted feet preserved at world position when reachable
- Skeleton dump system: Shift+SPACE in edit, RCON dump, auto-triggers

**Leap & Movement Fixes:**
- No backwards leaps: facing check at initiation, launch, and during flight
- Precog multi-hop: must face launch direction before each hop
- Floating legs fixed: force-replant when feet unreachable

**Editor & Testing:**
- Splay editor: click to select, SPACE toggle, C rope/chain, P pin, M mirror, drag IK
- Test menu (Ctrl+T): run test suites, spawn monsters, reset level
- Help overlay (?): all keyboard, controller, and RCON commands
- Territorial mode: monsters attack each other (RCON: territorial [on|off])
- Skeleton dump: JSON export of all bone positions + distances for debugging

### v0.9.18
**Monster Damage & Weak Spots, Dual-Grapple Tether System, Attack Dummy**

**Monster Damage & Weak Spots:**
- Tiered damage states per body part: NONE → MEDIUM → HIGH with blood effects
- 7 vulnerable zones: head, eye, mid-tail, torso, 2 rear legs, 2 arms (front legs)
- Eye critical hit: 2x damage to head + audible PING + 5-directional blood squirt
- Gameplay penalties at HIGH damage: tail disables grab attack, torso drips blood continuously, rear legs reduce leap distance (25%/50%), arms reduce slash damage (50%/75%)
- Blood particle system with splash and squirt modes, gravity, and fade
- Part-specific arrow damage: arrows hit nearest body part hitbox
- Monster HP increased: body 1500, head 400, tail 300, legs 250 each
- 4 attachment points: head, tail tip, shoulders, waist — for balloons, tethers, grapple
- Per-segment weight system (total ~193): head 15, torso 40, legs 12 each
- RCON: partstatus, partdmg, weight, attach, detach

**Dual-Grapple Tether System:**
- L1 first hook → adjust rope length → L1 second hook → creates persistent tether between two points
- Tether entity with strong pull physics (force 25000), mass-aware force distribution
- Connects anything: enemy↔enemy, enemy↔wall, body part↔body part, wall↔wall
- Max 5 active tethers per player, HUD dots show available slots
- Body part targeting: hooks snap to nearest attachment point on enemies
- Tether rendering: catenary sag when slack, straight when taut, red when over-stressed
- Tether HP (100): severable by projectiles passing through the rope, visual fraying before snap
- R1 pulls player to anchor (moved from L1 second press)
- RCON: tether commands for creation, length adjustment, status, and cutting

**Attack Dummy & Testing:**
- New test entity: configurable orange circle that fires at enemies
- 3 weapons: bow (arrows), balloon (darts), tether (creates tethers at targets)
- Targets specific body parts by name, tracks shots/hits
- Monster stand-down mode: passive, receives damage, skeleton still animates
- Solo self-revive: press jump when dead with no teammates
- RCON: spawn attacker, attacker target/part/weapon/rate/stop/start/stats
- clearplayers blocks controller re-joins, enablejoins re-allows them
- Balloons last forever (only removed by popping)

**Test Suites:**
- test_damage.sh: 6 tests for damage states, grab disable, bleeding, leap/slash reduction
- test_attachments.sh: 6 tests for balloon attachment, stacking, detach, weight
- test_tether.sh: 7 tests for tether creation, physics, balloon resistance, severing
- Regression: 18/18 hit rate, 4513 total damage (best ever)

### v0.9.17
**17/18 Test Suite, Score Cards, Cliff Aerial Strike, 3812 Damage**
- Full 18-scenario test suite with on-screen title cards and colored score tables
- 17/18 scenarios deal damage (3812 total), only cliff_ledge_right fails
- Raw ballistic aerial strike after precog hops reaches cave wall cliff ledges
- Score cards: green/yellow/red for damage, time, FPS, IK, thrash per test
- Final results grid rendered on screen after all tests (8s hold)
- Post-grab teleport to player position (no more popping back to pre-grab spot)
- Skeleton-to-world constraints prevent skull/tail clipping through floors
- Test categories: Same Floor, Platform Hunting, Cross-Platform Pursuit, Corner Trapping, Cliff Edge Assault
- RCON commands: title, score, grid for recording-friendly test visualization

### v0.9.16
**10/10 Baseline, Rigid Spinning Ball, Safe Landing, Thrash=8**
- 10/10 baseline hit rate, 1175 total damage, worst thrash 8 (was 29)
- 8/8 edge cases hit, time-to-first-hit 1.1-10.4s
- Rigid spinning ball grab: body parts SET (not lerped) on computed circle positions
- Ball radius 40px (player visible in center), collision expands to full tail spiral (~88px)
- Body frozen during grab (move_and_slide skipped, IK/gait/spine all skipped)
- Safe landing after grab: teleports to player's position, raycasts floor, resets skeleton
- 25% chance of grab-ball on leap contact (instead of normal slash barrage)
- Periodic slash visual effects spawn at ball center during bites/kicks
- Ball quality scoring: measures containment of body parts within ball radius
- Tail spiral starts from spine[2] angle, grows proportionally by TAIL_SEG_LEN
- I key toggles debug draw on all enemies

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
