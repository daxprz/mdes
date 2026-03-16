# Technical Architecture

## Project Structure

```
test123/
├── project.godot              # Godot project config, input maps, autoloads
├── assets/
│   ├── sounds/                # 39 WAV sound effects (incl. guitar via Karplus-Strong synthesis)
│   └── sprites/
│       ├── bosses/            # 4 boss spritesheets (256×64 each)
│       ├── characters/        # 12 classes × 2 views + donut buddy
│       ├── enemies/           # Skeleton spritesheet
│       ├── environment/       # Overworld + tower tilesets
│       ├── items/             # Muffins, artifacts
│       └── ui/                # Hearts, portal, title logo
├── scenes/                    # .tscn scene files
│   ├── bosses/                # Boss arena + 4 individual boss scenes
│   ├── characters/            # Player (topdown + side), projectile, donut buddy
│   ├── enemies/               # Skeleton + all enemy types
│   ├── items/                 # Mini muffin
│   ├── overworld/             # Valley map, tower entrance
│   ├── towers/                # Tower base (procedural)
│   ├── traps/                 # Trap scenes (spikes, pendulums, etc.)
│   ├── dungeon_tower.tscn     # Dungeon maze tower variant
│   ├── tower_base.tscn        # Standard tower
│   └── ui/                    # Title screen, HUD, health bar
├── scripts/                   # .gd script files (mirrors scenes/)
│   ├── autoload/              # Global singletons
│   │   ├── game_manager.gd    # Game state, tower tracking, transitions
│   │   ├── player_manager.gd  # Player join/leave, 12 class stats, health/mana, leveling
│   │   ├── audio_manager.gd   # Sound playback with pooling
│   │   └── profile_manager.gd # Persistent player profiles (JSON save/load)
│   ├── bosses/                # Boss base class + 4 boss scripts
│   ├── characters/            # Player scripts + companions
│   ├── enemies/               # 13 enemy types + 4 mini-bosses + overworld patrol
│   ├── items/                 # Collectible logic
│   ├── overworld/             # Valley + tower entrance
│   ├── towers/                # Tower generation + dungeon tower
│   ├── traps/                 # Trap scripts (18 trap types)
│   └── ui/                    # UI scripts + multi-camera + pause menu + profile overlays
├── docs/                      # Project management
│   ├── BACKLOG.md             # Epics, stories, tasks
│   ├── PROJECT_AREAS.md       # 10 project areas
│   └── design/                # Design documents
│       ├── weapon_crafting.md  # Crafting system design
│       └── art_style_guide.md  # Art direction guide
└── documentation/             # Game documentation (this folder)
```

## Autoload Singletons (always loaded)

| Name | Script | Purpose |
|------|--------|---------|
| `GameManager` | game_manager.gd | Game state machine, tower tracking, scene transitions |
| `PlayerManager` | player_manager.gd | Player join/leave, 12 class stats, health/mana, leveling/XP |
| `PauseMenu` | pause_menu.gd | Global pause overlay with resume/quit + profile stats |
| `AudioManager` | audio_manager.gd | Pooled sound effect playback (39 sounds) |
| `ProfileManager` | profile_manager.gd | Persistent player profiles, save/load JSON, device-profile mapping |

## Scene Hierarchy

### Title Screen (`Node2D`)
- Background, Floor, Walls, Ceiling (physics)
- 5 platforms at calculated heights for lobby play
- PlaygroundSpawn (Marker2D)
- Players container (Node2D - lobby characters spawned here)
- UI (CanvasLayer) - title, join text, 4 player slots (12 classes), start text
- Profile selection overlay (triggered on first START press)
- Dynamic multi-camera

### Valley/Overworld (`Node2D`)
- Background (ColorRect grass)
- Paths (ColorRect dirt)
- 4 Tower visuals (ColorRect + Label)
- 4 Tower entrances (Area2D + tower_entrance.gd)
- Chasm visual + blocker (StaticBody2D)
- 3 Zipline visuals (hidden by default)
- Boundary walls (StaticBody2D)
- PlayerSpawnPoint (Marker2D)
- Dynamic multi-camera

### Tower Base (`Node2D`)
- Tower background, walls (visual + StaticBody2D)
- Platforms container (procedurally filled)
- Enemies container (procedurally filled)
- Muffins container (procedurally filled)
- ExitDoor (Area2D at top)
- UI (CanvasLayer) - muffin counter, tower title
- Dynamic multi-camera

### Boss Arena (`Node2D`)
- Built entirely in code: floor, walls, background
- Boss spawned from scene file based on tower_id
- Players spawned as player_side characters
- UI (CanvasLayer) - boss name, health bar
- Dynamic multi-camera

## Collision Layer Map

| Layer | Used For |
|-------|----------|
| 1 | World geometry (floors, walls, platforms) |
| 2 | Players (CharacterBody2D) |
| 4 | Interactables (tower entrances, muffins, exit doors) |
| 8 | Enemies |

| Entity | Layer | Mask |
|--------|-------|------|
| Player | 2 | 1 (world) |
| Player Attack Area | 0 | 8 (enemies) |
| Player Interact Area | 0 | 4 (interactables) |
| Skeleton / All Enemies | 8 | 1 (world) |
| Enemy Hitbox | 8 | 2 (players) |
| Boss (set in boss_base.gd _ready) | 8 | 1 (world) |
| Tower Entrance | 4 | 2 (players) |
| Mini Muffin | 4 | 2 (players) |
| Exit Door | 4 | 2 (players) |
| Boss Projectile | 4 | 2 (players) |
| Delegate Ghost | 0 | 1 (world) |

## Key Class Inheritance

```
CharacterBody2D
├── Player (overworld, top-down) - all 12 classes
├── PlayerSide (tower/boss, side-scrolling) - all 12 classes
│   Abilities by class:
│   ├── Melee: combo, ground slam, shield charge, enrage, ground pound charge
│   ├── Ranged: crossbow (10 ammo), grappling hook, reload, piercing shot charge
│   ├── Mage: fireball (fire type, explodes balloons), mana potion, air-walk (drains mana), beam of light charge
│   ├── Summoner: homing mark, summon buddy, delegate mode, empowered buddy charge
│   ├── Rogue: 3 knife fan, shadow dash, stealth/backstab, charged backstab
│   ├── Demolitionist: bombs, big bomb, rocket jetpack, refuel, mega bomb charge
│   ├── Healer: healing potion throw, healing burst, wind gust, channel heal charge
│   ├── Tank: mace slam, ground pound stun, fortify, shockwave charge
│   ├── Ninja: 3 fast slices, dive kick, air dash/item pickup, triple jump, meteor charge
│   ├── Balloonist: balloon darts (physics string + teardrop), pop all, self-float, 3x fire rate, max 10
│   ├── Guitarist: sine wave notes, blast wave (60° arc, weight-based), amp up, power chord charge
│   └── Werewolf: triple claw slash (8 blood drops), roar push (30° arc, 250px), frenzy, pounce charge
├── Skeleton (enemy)
├── FairyCakeBat, CookieArcher, CandyGolem, SprinkleSwarm (wave 1 enemies)
├── CupcakeBomber, LicoriceWhip, GummyBear, WaferShield (wave 2 enemies)
├── CandyCorn, MarshmallowBlob, PeppermintRoller, JellybeanSniper (wave 2 enemies)
├── CookieCutterMiniboss, FrostingFountainMiniboss (mini-bosses)
├── SprinkleTornadoMiniboss, BatterElementalMiniboss (mini-bosses)
├── DonutBuddy (summoner companion)
└── BossBase (class_name: BossBase)
    ├── GingerbreadSkeleton
    ├── IcingGoblin
    ├── SprinkleDragon
    └── GiantMuffin

Area2D
├── Projectile (player projectiles)
├── BossProjectile (class_name: BossProjectile)
├── MiniMuffin (collectible)
└── TowerEntrance (overworld triggers)

Node2D
├── Valley (overworld scene script)
├── TowerBase (tower scene script)
├── DungeonTower (dungeon maze tower variant)
├── BossArena (boss scene script)
└── HealthBar (custom _draw() health display)

Node
├── GameManager (autoload)
├── PlayerManager (autoload) - 12 classes, leveling/XP system
├── AudioManager (autoload)
└── ProfileManager (autoload) - persistent profiles, JSON save/load

CanvasLayer
├── PauseMenu (autoload)
├── ProfileSelectOverlay (profile selection UI)
└── NameEntryOverlay (on-screen keyboard for profile names)

Camera2D
└── MultiCamera (dynamic zoom/pan script)
```

## Physics Constants

| Constant | Value | Used In |
|----------|-------|---------|
| Gravity | 800 px/s² | Skeleton |
| Gravity | 900 px/s² | Player (side) |
| Gravity | 980 px/s² | Bosses |
| Jump Velocity | -550 px/s | Player (side) |
| Wall Jump | (250, -480) px/s | Player (side) |
| Terminal Velocity | 600 px/s | Player (side) |
| Ground Slam Speed | 600 px/s | Melee (side) |
