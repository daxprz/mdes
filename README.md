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
Press SELECT to toggle. Shows velocity arrows, button states, grapple tracers, archer arc trails. Press G near a procedural tree to regenerate it with a new seed.

## Downloads

See [Releases](https://github.com/jeremyprz/muffin/releases) for Mac, Windows, and Linux builds.

### macOS Users
Right-click the app, click **Open**, then **Open** again to bypass Gatekeeper. Or run:
```
xattr -cr "/Applications/The Ultimate Muffin.app"
```

---

## Release Notes

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
