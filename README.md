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
