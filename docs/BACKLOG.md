# The Ultimate Muffin - Backlog

> Status: `[ ]` = todo, `[~]` = in progress, `[x]` = done

---

## EPIC 1: Art Style Overhaul (`art`)
Improve all pixel art from placeholder quality to polished retro style.

### Story 1.1: Character Sprites
- [x] Task: Melee knight - topdown spritesheet (128x128) with shading, outline, detail
- [x] Task: Melee knight - side spritesheet (192x32) with shading, outline, detail
- [x] Task: Ranged ranger - topdown spritesheet
- [x] Task: Ranged ranger - side spritesheet
- [x] Task: Mage wizard - topdown spritesheet
- [x] Task: Mage wizard - side spritesheet
- [x] Task: Summoner - topdown spritesheet
- [x] Task: Summoner - side spritesheet
- [x] Task: Rogue - topdown spritesheet
- [x] Task: Rogue - side spritesheet
- [x] Task: Donut buddy sprite (144x24)

### Story 1.2: Boss Sprites
- [x] Task: Gingerbread Skeleton (256x64) - cookie bones, icing detail, gumdrop eyes
- [x] Task: Icing Goblin (256x64) - dripping frosting, cherry eyes, sprinkle decor
- [x] Task: Sprinkle Dragon (256x64) - rainbow sprinkle scales, candy fire breath
- [x] Task: Giant Muffin (256x64) - angry face, paper wrapper lines, chocolate chips

### Story 1.3: Enemy Sprites
- [x] Task: Skeleton enemy (128x32) - visible ribcage, glowing eyes, bone club
- [x] Task: Design & create 2-3 additional enemy types

### Story 1.4: Item Sprites
- [x] Task: Mini muffin (64x16) with sparkle animation
- [x] Task: Ultimate muffin (16x16) with halo glow
- [x] Task: 5 class artifacts (16x16 each)
- [x] Task: Mana potion / health potion pickups

### Story 1.5: Environment Tiles
- [x] Task: Overworld tileset (160x160) - grass, paths, water, trees, rocks
- [x] Task: Tower tileset (160x160) - stone, platforms, ladders, spikes, torches
- [x] Task: Boss arena backgrounds (per boss theme)

### Story 1.6: UI Art
- [x] Task: Heart icon, mana icon, muffin counter icon
- [x] Task: Portal animation (128x32)
- [x] Task: Title logo "THE ULTIMATE MUFFIN" (256x64)
- [x] Task: Menu panel art / button styles

---

## EPIC 2: Bug Fixes (`bugs`)

### Story 2.1: Boss Arena Escape
- [x] Task: Add walls/ceiling to boss arena so players can't jump out
- [x] Task: Add kill zone below arena floor (respawn player if they fall)

### Story 2.2: Crash Fixes
- [x] Task: Audit all scripts for Variant type inference errors (`sign()`, etc.)
- [x] Task: Test all scene transitions (title→overworld→tower→boss→overworld)
- [x] Task: Fix any remaining `call_deferred` issues during physics callbacks

### Story 2.3: Pause Menu
- [x] Task: Only the player who pressed START controls the menu
- [x] Task: Add navigation cooldown to prevent too-fast scrolling
- [x] Task: Quit goes to title screen first, separate "Quit Game" exits entirely

### Story 2.5: Attack Button Not Working
- [x] Task: BUG: Square button (attack) does nothing for any class
  - ROOT CAUSE: Charge system intercepted EVERY button press on the first frame,
    setting _is_charging=true before _handle_attack could fire. Normal attacks
    were permanently blocked.
  - FIX: Charge only activates after holding attack for 0.3s. Quick taps fire
    normal attacks. Hold for charge attacks.

### Story 2.4: Boss Damage Bug
- [x] Task: BUG: Players cannot damage the final boss (Giant Muffin) - attacks don't register
- [x] Task: Investigate boss collision layers vs player attack area masks
  - ROOT CAUSE: Boss scenes had no collision_layer set (defaulted to 1/world).
    Player attack areas use collision_mask=8 (enemies). Bosses were invisible to attacks.
- [x] Task: Verify boss is in "enemies" or "bosses" group and take_damage is callable
  - FIX: boss_base.gd _ready() now sets collision_layer=8 and adds to both
    "enemies" and "bosses" groups. All 4 bosses fixed.

### Story 2.8: Soft-Lock When All Players Die
- [x] Task: BUG: Game soft-locks when all players die (no revive possible)
  - FIX: PlayerManager emits all_players_dead signal. GameManager shows
    "ALL PLAYERS DOWN!" overlay for 2s, then restarts current scene with
    all players revived at full health/mana.

### Story 2.7: Melee Ground Attack Not Hitting
- [x] Task: BUG: Melee attack on ground doesn't hit enemies
  - ROOT CAUSE: attack_area.monitoring enabled and get_overlapping_bodies()
    called on same frame — Godot needs one physics frame to detect overlaps.
  - FIX: Wait one physics_frame after enabling monitoring before checking hits.
- [x] Task: Replace melee swing VFX with large arcing slash + silver/grey/yellow/white particles
- [x] Task: Blood particles on enemy hit (3 squirts, arc upward, land on surfaces, drip down)

### Story 2.6: Boss Falls Through Floor
- [x] Task: BUG: Giant Muffin falls through arena floor during fight
  - ROOT CAUSE: Summoned mini-muffin enemies had default collision_layer=1 (world).
    Boss is on layer 8 with mask=1, so boss collided with its own minions and got
    pushed through the floor.
  - FIX: All boss-spawned minions now use collision_layer=8 (same as enemies),
    so they don't push the boss. Added safety teleport in boss_base if boss
    position.y > 600 (below arena).

### Story 2.9: Title Screen START Button Ignored
- [x] Task: BUG: On the title screen when no players are connected, pressing START does nothing
  - ROOT CAUSE: `_setup_name_entry()` and `_setup_camera()` were only called from
    `_apply_saved_classes()`, which only runs on return-from-game. On fresh launch,
    the profile/name overlays were never created, so `_on_device_needs_profile()`
    silently did nothing — no profile was bound and `_try_join()` kept bailing out.
  - FIX: Call `_setup_camera()` and `_setup_name_entry()` unconditionally in `_ready()`.

---

## EPIC 3: Overworld Progression (`design`, `mechanics`)
The overworld needs structure - players shouldn't access everything immediately.

### Story 3.1: Area Gating
- [x] Task: Block paths to Tower 2 and Tower 3 until Tower 1 is complete
- [x] Task: Each tower completion unlocks a zipline to the NEXT area
- [x] Task: Zipline is an interactive object players ride across chasms
- [x] Task: Final tower area only accessible after all 3 ziplines unlocked

### Story 3.2: Overworld Boundaries
- [x] Task: Add proper walls/fences around the playable overworld area
- [x] Task: Add visual boundaries (cliffs, water, dense forest)
- [x] Task: Camera limits so players can't see outside the map

### Story 3.3: Overworld Polish
- [x] Task: Make ziplines animated/functional (not just visual blocks)
- [x] Task: Add NPC or signpost near each tower with lore/hints
- [x] Task: Add ambient overworld enemies (optional combat)

---

## EPIC 4: Enemy Variety (`enemies`)

### Story 4.1: New Enemy Types
- [x] Task: Design flying enemy (bat/fairy cake) - moves in sine wave pattern
- [x] Task: Design ranged enemy (cookie archer) - shoots at players from distance
- [x] Task: Design tank enemy (candy golem) - slow, high HP, big hits
- [x] Task: Design swarm enemy (sprinkle bugs) - small, fast, come in groups

### Story 4.2: Enemy Density & Placement
- [x] Task: Increase enemy count per tower floor (scale with tower difficulty)
- [x] Task: Add enemy spawn points that trigger when players reach certain heights
- [x] Task: Mix enemy types per floor for tactical variety

### Story 4.3: Enemy Behaviors
- [x] Task: Enemies should work together (ranged stays back while melee charges)
- [x] Task: Enemies should react to player class (focus summoner's donut buddies, etc.)

### Story 4.4: New Enemy Types - Wave 2
- [x] Task: Cupcake Bomber - flies overhead, drops frosting bombs that splat and slow
- [x] Task: Licorice Whip - long range tentacle enemy, grabs and pulls players toward it
- [x] Task: Gummy Bear Brute - huge, charges in a line, bounces off walls, gets dizzy
- [x] Task: Wafer Shield Bearer - has a shield, must be hit from behind or with charge attacks
- [x] Task: Candy Corn Spinner - spins rapidly dealing AoE damage, vulnerable when dizzy after
- [x] Task: Marshmallow Blob - splits into 2 smaller blobs when killed, those split into 2 more
- [x] Task: Peppermint Roller - rolls left/right along platforms, bounces off walls, speeds up over time
- [x] Task: Jellybean Sniper - hides in background, fires precise shots, must be flushed out with AoE

### Story 4.5: Mini-Bosses (mid-tower encounters)
- [x] Task: Each tower gets a mini-boss halfway up
- [x] Task: Tower 1 mini-boss: Giant Cookie Cutter (slices platforms, must dodge pattern)
- [x] Task: Tower 2 mini-boss: Frosting Fountain (sprays icing in rotating pattern)
- [x] Task: Tower 3 mini-boss: Sprinkle Tornado (pulls players toward center, throws sprinkles outward)
- [x] Task: Tower 4 mini-boss: Batter Elemental (shapeshifting blob, mimics player attacks)

---

## EPIC 5: Level Design Variety (`design`, `mechanics`)

### Story 5.1: Tower Layout Improvements
- [x] Task: Reduce platform spacing to match jump height with comfortable margin
- [x] Task: Add multiple paths up (left route vs right route)
- [x] Task: Add secret areas with bonus muffins
- [x] Task: Each tower has a unique visual theme (gingerbread, icing, sprinkle)

### Story 5.2: Platforming Challenge
- [x] Task: Add moving platforms
- [x] Task: Add crumbling platforms (break after standing on them)
- [x] Task: Add conveyor belt platforms
- [x] Task: Add vertical sections (climbing challenges)

---

## EPIC 6: Wall Jump Limits (`mechanics`)

### Story 6.1: Wall Cling Stamina
- [x] Task: Add wall-cling stamina (deplete while wall sliding, regen on ground)
- [x] Task: Visual indicator showing remaining wall-cling time (red flash when exhausted)
- [x] Task: Max 2-3 wall jumps before must touch ground (max 3)

---

## EPIC 7: Traps & Obstacles (`mechanics`, `design`)

### Story 7.1: Trap Types
- [x] Task: Spike floors (deal damage on contact) - 15 dmg, 0.5s cooldown
- [x] Task: Swinging pendulum blades (timed obstacle) - 20 dmg, sin() swing
- [x] Task: Arrow traps (shoot from walls on a timer) - 10 dmg, 2.5s interval
- [x] Task: Lava/acid pools (instant kill or heavy damage) - 30 dmg/0.3s + knockback
- [x] Task: Pressure plates that trigger traps - signal-based, links to other traps

### Story 7.2: Environmental Hazards
- [x] Task: Falling rocks/debris in certain sections - 20 dmg, 3-5 rocks, proximity trigger
- [x] Task: Wind gusts that push players sideways - 200px/s push, intermittent on/off
- [x] Task: Dark rooms where only nearby area is visible - replaced with smoke bomb system

### Story 7.3: New Obstacles - Wave 2
- [x] Task: Rotating saw blades on chains (circle around an anchor point)
- [x] Task: Icing waterfall (slippery vertical stream, pushes players down if they enter)
- [x] Task: Candy cane poles (bounce pads - launch players upward when touched)
- [x] Task: Chocolate lava rising floor (slowly rises from bottom, forces players to climb faster)
- [x] Task: Sugar crystal barriers (breakable walls that block paths, require X hits)
- [x] Task: Frosting slides (angled platforms that are slippery, players slide down)
- [x] Task: Cookie crumble floors (entire sections that collapse after a timer once stepped on)
- [x] Task: Caramel sticky zones (slow player movement to 30%, must jump through)
- [x] Task: Popcorn geysers (periodic upward blast that launches players + enemies high)
- [x] Task: Sprinkle mines (hidden on platforms, explode when stepped on, 15 dmg + knockback)

---

## EPIC 8: Procedural Weapon Crafting (`items`, `classes`)
**LARGE EFFORT** - Needs design phase before implementation.

### Story 8.1: Design Phase
- [ ] Task: Define weapon component system per class (see design doc)
- [ ] Task: Define stat modifiers per component
- [ ] Task: Define name generation rules (funny, short, readable)
- [ ] Task: Define crafting material sources (drops, muffin currency, boss rewards)
- [ ] Task: Define crafting UI wireframes

### Story 8.2: Weapon Components Per Class
- [ ] Task: Melee - Blade + Hilt + Enchantment
- [ ] Task: Ranged - Limb + String + Bolt Type
- [ ] Task: Mage - Orb + Staff + Rune
- [ ] Task: Summoner - Core + Shell + Spirit
- [ ] Task: Rogue - Blade + Grip + Poison

### Story 8.3: Name Generation
- [ ] Task: Build name template system: `[Prefix] [Material] [Weapon] of [Suffix]`
- [ ] Task: Create word lists per component (funny/bakery themed)
- [ ] Task: Examples: "Crispy Gingerbread Sword of Sprinkles", "Soggy Muffin Dagger of Crumbs"

### Story 8.4: Crafting System Implementation
- [ ] Task: Crafting station in overworld (or between towers)
- [ ] Task: Crafting UI - drag components together
- [ ] Task: Material inventory system
- [ ] Task: Weapon equip/swap system
- [ ] Task: Weapon stats affect combat (damage, speed, effects)

### Story 8.5: Crafting Materials
- [ ] Task: Common drops from enemies (flour, sugar, sprinkles)
- [ ] Task: Rare drops from bosses (enchanted icing, golden crumbs)
- [ ] Task: Muffin currency can buy base materials
- [ ] Task: Material storage/inventory UI

---

## EPIC 9: New Class - Demolitionist (`classes`)
Bomb-throwing specialist with upgradeable explosives.

### Story 9.1: Base Demolitionist Class
- [x] Task: Add DEMOLITIONIST to CharacterClass enum + stats (100 HP, 100 mana, 105 speed, 1.5 mana regen)
- [x] Task: Create demolitionist topdown + side spritesheets
- [x] Task: Basic attack: throw bomb (arcs with gravity, bounces once, explodes after 1.5s or on enemy contact)
- [x] Task: Bomb explosion: 25 damage, 60px radius, knockback, VFX + screen shake
- [x] Task: Special: Big Bomb (costs 40 mana, 50 damage, 90px radius, bigger VFX)

### Story 9.2: Bomb Upgrade System
- [x] Task: Explosive Power upgrades (damage multiplier tiers)
- [x] Task: Blast Size upgrades (radius multiplier tiers)
- [x] Task: Fragment Bombs (split into 3-5 mini-bombs after first bounce) - via charge attack
- [x] Task: Napalm Bombs (leave burning ground for 3s, DoT damage)

### Story 9.3: Bomb Aspects (elemental types)
- [x] Task: Electric aspect (chains to nearby enemies, brief stun)
- [x] Task: Fire aspect (ignites enemies, DoT for 3s)
- [x] Task: Impact aspect (massive knockback, lower damage)
- [x] Task: Ice aspect (slows enemies in blast radius)

---

## EPIC 10: New Class - Healer (`classes`)
Support class with healing staff and buff abilities.

### Story 10.1: Base Healer Class
- [x] Task: Add HEALER to CharacterClass enum + stats (90 HP, 130 mana, 95 speed, 2.5 mana regen)
- [x] Task: Create healer topdown + side spritesheets
- [x] Task: Basic attack: staff swing (10 damage) that ALSO heals closest allied player for 8 HP
- [x] Task: Auto-target: healing beam visual arcs to nearest injured ally
- [x] Task: Special: Healing Burst (costs 50 mana, heals all allies in 80px for 30 HP)

### Story 10.2: Healer Charge Attack
- [x] Task: Charge attack sends healing blast wave (circular pulse outward)
- [x] Task: Wave distance + healing power scales with charge duration (1-3s)
- [x] Task: Visual: circular ring expands outward from healer
- [x] Task: Allies in wave radius get healed + temporary buff (10% speed + 10% damage for 5s)
- [x] Task: Enemies hit by wave get stunned for 1.5s

### Story 10.3: Healer Dash
- [x] Task: Dash creates perpendicular wave pulse (line expanding outward from dash direction)
- [x] Task: Wave heals allies and pushes enemies aside
- [x] Task: Visual: bright line expanding perpendicular to movement

---

## EPIC 11: Combat System Overhaul (`mechanics`, `classes`)
Universal combat mechanics that apply to ALL classes.

### Story 11.1: Melee Buff
- [x] Task: Increase melee swing range by 40% (20→28, 22→31, 28→39)
- [x] Task: Visible swing arc VFX (colored arc that follows the attack area)
- [x] Task: Arc color matches combo stage (white→yellow→orange)
- [x] Task: Add distinct sound per combo hit (light→medium→heavy slash)

### Story 11.2: Charge Attack System (ALL classes)
- [x] Task: Hold attack button to charge (0.5s minimum, 3s maximum)
- [x] Task: Visual: character glows brighter the longer they charge, particles emit
- [x] Task: Release to fire charged attack (damage/effect scales with charge time)
- [x] Task: Per-class charge behavior:
  - Melee: Ground pound (hover, wiggle, smoke, then blast. Radius + damage scales with charge)
  - Ranged: Charged shot (pierces enemies, bigger projectile)
  - Mage: Charged bolt (larger, explodes on impact, AoE scales with charge)
  - Summoner: Summon empowered donut buddy (bigger, stronger, lasts longer with charge)
  - Rogue: Charged backstab (teleport behind nearest enemy, massive damage)
  - Demolitionist: Mega bomb (huge radius + fragments, scales with charge)
  - Healer: Healing blast wave (radius + heal amount scales with charge)

### Story 11.3: Melee Ground Pound Improvements
- [x] Task: While charging in air: character hovers in place
- [x] Task: Hover wiggle animation (oscillate position ±2px)
- [x] Task: Smoke/particle VFX builds during hover
- [x] Task: On release: slam down with blast radius proportional to charge (40px min → 120px max)
- [x] Task: Damage scales: 30 min → 80 max based on charge
- [x] Task: Screen shake on impact (intensity scales with charge)

### Story 11.4: Stagger Mechanic
- [x] Task: Getting hit while charging → "staggered" state
- [x] Task: Staggered: character wiggles rapidly for 1s, cannot act
- [x] Task: Staggered players take 25% more damage
- [x] Task: Visual: rapid left-right shake + stars above head
- [x] Task: Sound: dazed/dizzy sound effect

### Story 11.5: Block/Parry System (ALL classes)
- [x] Task: Map block to a button (R2 / Left Shift)
- [x] Task: Holding block: reduce incoming damage by 50%, movement speed halved
- [x] Task: Visual: shield/guard VFX in front of character
- [x] Task: Perfect parry: block within 0.2s of being hit → attacker stunned for 1.5s
- [x] Task: Perfect parry VFX: bright flash + metallic clang sound
- [x] Task: Perfect parry window indicator (brief white flash on character when block starts)

### Story 11.6: Dash Wave
- [x] Task: All class dashes create a perpendicular wave pulse
- [x] Task: Wave pushes enemies sideways (away from dash line)
- [x] Task: Wave visual: line expanding outward perpendicular to dash direction
- [x] Task: Wave damage: 5 (minor, mainly for crowd control)
- [x] Task: Rogue shadow dash wave is larger and deals 10 damage

---

---

## EPIC 12: Character Leveling System (`progression`, `classes`)
Skill-based leveling: abilities improve through effective use.

### Story 12.1: XP & Level Framework
- [x] Task: Define XP curve per level (e.g. level 1=100xp, level 2=250xp, scaling formula)
- [x] Task: Add level and xp fields to player data in PlayerManager
- [x] Task: XP earned on successful hit (attack lands on enemy = xp for that skill)
- [x] Task: XP earned on kill (bonus xp for finishing blow)
- [x] Task: XP earned on boss defeat (large bonus, scales with boss difficulty)
- [x] Task: Level-up VFX + sound when threshold reached (gold flash, fanfare)
- [x] Task: Max level cap (e.g. 20 per skill, 50 overall)

### Story 12.2: Per-Skill Leveling
- [x] Task: Track XP separately for: basic attack, special ability, charge attack, block/parry
- [x] Task: Each skill levels independently based on successful use
- [x] Task: Basic attack: each landed hit grants 1-3 xp (scales with enemy difficulty)
- [x] Task: Special ability: each successful use grants 5-10 xp
- [x] Task: Charge attack: damage dealt during charge converts to xp (1 xp per 5 damage)
- [x] Task: Block: each blocked hit grants 3 xp. Perfect parry grants 15 xp
- [x] Task: Healing (Healer): each HP healed on allies grants 0.5 xp
- [x] Task: Summoning (Summoner): donut buddy damage contributes xp to summoner

### Story 12.3: Skill Level Benefits
- [x] Task: Each skill level grants a small bonus:
  - Attack levels: +2% damage per level
  - Special levels: -2% cooldown per level, +1% effect per level
  - Charge levels: +3% charge speed per level, +2% max charge damage
  - Block levels: +1% damage reduction per level, +0.02s parry window per 5 levels
- [x] Task: Milestone bonuses at levels 5, 10, 15, 20 (unlock new visual effects, sound changes)
- [x] Task: Display skill levels on pause menu stat screen

### Story 12.4: Overall Character Level
- [x] Task: Overall level = average of all skill levels (rounded down)
- [x] Task: Overall level grants: +5 max HP per level, +3 max mana per level
- [x] Task: Level displayed next to player name (e.g. "P1 - Melee Lv.7")
- [x] Task: Level shown on title screen class selection slots

---

## EPIC 13: Persistent Profiles & Save System (`progression`, `ui`)
Player profiles that survive game crashes and sessions.

### Story 13.1: Profile Storage
- [x] Task: Save/load system using Godot's FileAccess (JSON file in user://)
- [x] Task: Profile data structure: name, class_preferences, per_class_stats, created_date
- [x] Task: Per-class stats within profile: level, skill_xp, total_kills, total_muffins, boss_kills
- [x] Task: Auto-save after each tower completion and boss defeat
- [x] Task: Auto-save on quit to menu
- [x] Task: Load profiles on game launch

### Story 13.2: Profile Creation Flow
- [x] Task: When controller connects: show "Choose Profile" or "Create New" screen
- [x] Task: Create new profile step 1: Enter name (3-16 characters)
  - On-screen keyboard for controller input
  - Direct keyboard typing support
  - Name validation (no empty, no duplicates)
- [x] Task: Create new profile step 2: Stack-rank class preferences (drag/reorder list)
  - Shows all 12 classes in a list
  - D-pad up/down to select, X to grab, move up/down, X to drop
  - Top preference = default class when joining
- [x] Task: Create new profile step 3: Optionally name each sub-character per class
  - E.g. "BladeMaster" for their Melee, "BoomBoy" for their Demolitionist
  - Skip button to use defaults
- [x] Task: Create new profile step 4: Accept/confirm screen showing summary
- [x] Task: Profile select screen shows existing profiles with level + preferred class icon

### Story 13.3: Profile-Linked Gameplay
- [x] Task: When player joins (START press), auto-assign their profile's top available class
- [x] Task: If preferred class is taken, use next preference in stack-rank
- [x] Task: Player label shows profile name instead of "P1" (e.g. "Dax - Melee Lv.7")
- [x] Task: XP and level progress saved to profile after each session
- [x] Task: Track lifetime stats per profile: total playtime, total muffins, bosses defeated

### Story 13.4: Pause Menu - Profile Stats Display
- [x] Task: Pause menu shows paused player's profile name + avatar
- [x] Task: Show class avatar/icon (character sprite preview)
- [x] Task: Show current level + XP bar (progress to next level)
- [x] Task: Show per-skill levels (attack Lv.X, special Lv.X, charge Lv.X, block Lv.X)
- [x] Task: Show session stats: muffins collected, enemies killed, damage dealt
- [x] Task: Show acquired items/artifacts this session
- [x] Task: Show lifetime stats from profile (total kills, total muffins, bosses defeated)

### Story 13.5: Multiple Profiles Management
- [x] Task: Support up to 8 saved profiles
- [x] Task: Delete profile option (with confirmation)
- [x] Task: Profile selection remembers last-used profile per controller
- [x] Task: Guest mode: play without a profile (no progress saved, labeled "Guest")

---

## EPIC 14: New Class - Tank (`classes`)
Armored frontliner with crowd control and damage absorption.

### Story 14.1: Base Tank Class
- [x] Task: Add TANK to CharacterClass enum + stats (250 HP, 30 mana, 70 speed, 0.5 mana regen)
- [x] Task: Create tank topdown + side spritesheets
- [x] Task: Basic attack: heavy mace slam (45 damage, 1.2s cooldown, wide area)
- [x] Task: Special: ground pound AoE stun around the tank
- [x] Task: Charge attack: massive ground shockwave (60-160px radius, 20-70 damage scaled by charge)

### Story 14.2: Fortify Ability
- [x] Task: Fortify ability on Circle (interact) - 8s duration, 25s cooldown
- [x] Task: Fortified: ignore 60% of incoming damage
- [x] Task: Fortified: attack damage reduced by 50% (tradeoff)
- [x] Task: Bronze glow VFX with pulsing, warning flash at 2s remaining
- [x] Task: "FORTIFIED!" floating text on activation

---

## EPIC 15: Class Ability Expansion (`classes`, `mechanics`)
New abilities added to all existing classes.

### Story 15.1: Melee - Enrage
- [x] Task: Enrage ability on Circle (interact) - 10s duration, 45s cooldown
- [x] Task: Enraged: 1.5x speed multiplier, 1.8x damage multiplier
- [x] Task: Red tint VFX, "ENRAGE!" floating text

### Story 15.2: Ranged - Ammo/Reload + Grappling Hook
- [x] Task: Ammo system with limited arrows (reload on Circle, 1.5s reload time)
- [x] Task: Crossbow bolt damage increased to 60
- [x] Task: Special changed to Grappling Hook (fires aimed, pulls to walls or enemies, 20 damage on enemy hit)
- [x] Task: All ranged attacks use aim direction system

### Story 15.3: Mage - Beam of Light + Mana Potion + Air-Walk
- [x] Task: Rapid-fire magic bolts (6 damage each, 450px/s, costs mana)
- [x] Task: Special changed to Mana Potion (restores 60% max mana)
- [x] Task: Charge attack: Beam of Light (raycast, 40-120 damage, multi-hit, scales with charge)
- [x] Task: Air-Walk ability on Circle (5s duration, 10s cooldown, no gravity while active)

### Story 15.4: Summoner - Homing Mark + Delegate Mode
- [x] Task: Basic attack changed to Homing Mark (slow homing orb, marks target for +damage from buddies, 6s duration)
- [x] Task: Delegate Mode on Circle (30s cooldown, 10s duration) - summoner freezes, ghost moves freely
- [x] Task: Ghost: 1.5x speed, 1.5x jump, can dash. Buddies follow ghost
- [x] Task: Summoner takes 1.5x damage while delegating; hit >= 15 cancels it
- [x] Task: Aether rift teleport VFX on enter/exit delegate mode

### Story 15.5: Rogue - Stealth + Backstab
- [x] Task: Knife fan basic attack pattern
- [x] Task: Stealth ability on Circle (5s duration, 20s cooldown)
- [x] Task: Stealthed: semi-transparent, enemies ignore, take 50% less damage
- [x] Task: Backstab from stealth: 3.75x damage multiplier

### Story 15.6: Demolitionist - Rocket Jetpack + Crash + Refuel
- [x] Task: Rocket jetpack activated by second jump press (4s fuel)
- [x] Task: Thrust with aim direction, drift increases over time (chaos/spin)
- [x] Task: Fuel depletion = crash explosion (damage to self + nearby)
- [x] Task: Refuel on Circle while grounded (hold to refill, no auto-refuel on landing)

### Story 15.7: Healer - Wind Gust + Healing Potion Throw
- [x] Task: Basic attack changed to Healing Potion Throw (arcing projectile, creates healing zone on land)
- [x] Task: Wind Gust ability on Circle (8s cooldown, 100px radius, 400 force knockback)
- [x] Task: Channel heal: hold attack to channel continuous healing aura (5 HP/s to nearby allies)
- [x] Task: Interrupted channel fires proportional burst heal

### Story 15.8: All Classes Aim Weapons
- [x] Task: All projectiles and attacks use right-stick/movement aim direction
- [x] Task: Grappling hook, bolts, bombs, marks, potions all aim-able

---

## EPIC 16: Top-Down Ability Port (`mechanics`)
All side-scrolling abilities ported to work in top-down overworld.

### Story 16.1: Overworld Abilities
- [x] Task: All class abilities functional in top-down mode
- [x] Task: Aim direction works in 8-directional top-down movement

---

## EPIC 17: Tower 2 Dungeon Maze (`design`)

### Story 17.1: Dungeon Tower Scene
- [x] Task: Create dungeon_tower.tscn - maze-style tower variant
- [x] Task: Dungeon tower script (dungeon_tower.gd)

---

## EPIC 18: Audio Expansion (`audio`)

### Story 18.1: New Sound Effects
- [x] Task: airwalk_activate.wav - Mage air-walk activation
- [x] Task: backstab_hit.wav - Rogue backstab strike
- [x] Task: beam_fire.wav - Mage beam of light
- [x] Task: enrage_roar.wav - Melee enrage activation
- [x] Task: grapple_hit.wav - Grappling hook impact
- [x] Task: grapple_launch.wav - Grappling hook fire
- [x] Task: mana_drink.wav - Mage mana potion
- [x] Task: mark_target.wav - Summoner homing mark hit
- [x] Task: refuel_gurgle.wav - Demolitionist refueling
- [x] Task: reload_click.wav - Ranger reload
- [x] Task: rocket_crash.wav - Demolitionist crash landing
- [x] Task: rocket_ignite.wav - Demolitionist jetpack ignition
- [x] Task: rocket_thrust.wav - Demolitionist jetpack loop
- [x] Task: stealth_activate.wav - Rogue stealth activation
- [x] Task: wind_gust.wav - Healer wind gust

---

## EPIC 19: Bug Fixes - Wave 2 (`bugs`)

### Story 19.1: Profile & Join Fixes
- [x] Task: Profile selection required before joining game
- [x] Task: Profile persistence across sessions (JSON in user://)
- [x] Task: ProfileManager autoload handles device-profile mapping

---

## EPIC 20: New Class - Ninja (`classes`)
Fast aerial specialist with triple jump and dive attacks.

### Story 20.1: Base Ninja Class
- [x] Task: Add NINJA to CharacterClass enum + stats (85 HP, 70 mana, 140 speed, 1.5 mana regen)
- [x] Task: Create ninja topdown + side spritesheets
- [x] Task: Basic attack: 3 fast sequential slices
- [x] Task: Special: dive kick (fast downward kick, bounces on hit)
- [x] Task: Charge attack: meteor strike (charge in air, slam down with scaling damage/radius)
- [x] Task: Circle ability: air dash / item pickup (dash through air + pull nearby items)
- [x] Task: Passive: triple jump (3 jumps before needing ground)

---

## EPIC 21: New Class - Balloonist (`classes`)
Chaos controller with physics-based balloons and H2 gas explosions.

### Story 21.1: Base Balloonist Class
- [x] Task: Add BALLOONIST to CharacterClass enum + stats (80 HP, 90 mana, 100 speed, 1.0 mana regen)
- [x] Task: Create balloonist topdown + side spritesheets
- [x] Task: Basic attack: balloon darts (physics string with 12 segments, teardrop-shaped balloons)
- [x] Task: Balloon physics: repulsion between balloons, wind sensitivity, weight system
- [x] Task: 3x fire rate, max 10 active balloons
- [x] Task: Special: Pop All (Triangle) - pop all active balloons, release H2 gas
- [x] Task: Charge attack: giant balloon (larger, more lift, scales with charge)
- [x] Task: Circle ability: self-float (attach balloon to self for flight)

### Story 21.2: H2 Gas & Hydrogen Explosion System
- [x] Task: H2 gas lingers for 25 seconds after balloon pop
- [x] Task: H2 gas ignites on contact with fire-type attacks or lava
- [x] Task: Hydrogen explosion with area damage on ignition
- [x] Task: Chain reactions: explosions ignite nearby H2 clouds
- [x] Task: Mage fireballs (fire type) explode balloons and ignite H2 gas

---

## EPIC 22: New Class - Guitarist (`classes`)
Rhythm-based fighter with sine wave projectiles and weight-based push.

### Story 22.1: Base Guitarist Class
- [x] Task: Add GUITARIST to CharacterClass enum + stats (110 HP, 100 mana, 95 speed, 2.0 mana regen)
- [x] Task: Create guitarist topdown + side spritesheets
- [x] Task: Basic attack: musical notes (sine wave trajectory)
- [x] Task: Special: blast wave (60-degree arc, weight-based push using entity weight system)
- [x] Task: Charge attack: power chord (massive sound blast, scales with charge)
- [x] Task: Circle ability: amp up (15s duration, 30s cooldown, amplified damage + effect radius)
- [x] Task: Guitar sounds via Karplus-Strong string synthesis (guitar_note.wav, guitar_blast.wav)

---

## EPIC 23: New Class - Werewolf (`classes`)
Brutal melee brawler with blood effects and frenzy mode.

### Story 23.1: Base Werewolf Class
- [x] Task: Add WEREWOLF to CharacterClass enum + stats (200 HP, 40 mana, 120 speed, 0.5 mana regen)
- [x] Task: Create werewolf topdown + side spritesheets
- [x] Task: Basic attack: triple claw slash (3-hit combo, 8 blood drops per slash)
- [x] Task: Special: roar push (30-degree arc, 250px range, weight-based push)
- [x] Task: Charge attack: pounce (charge and leap, damage/distance scale with charge)
- [x] Task: Circle ability: frenzy (8s duration, 35s cooldown, boosted attack/move speed)

---

## EPIC 24: Entity Weight System (`mechanics`)
Physics weight system for knockback and push calculations.

### Story 24.1: Weight Implementation
- [x] Task: Assign weight values: Player 70, Skeleton 30, Bat 5, Golem 150, Boss 300
- [x] Task: Guitarist blast wave uses weight for push distance calculation
- [x] Task: Werewolf roar uses weight for push distance calculation
- [x] Task: Balloon lift affected by entity weight

---

## EPIC 25: Balloon Physics & Environmental Interactions (`mechanics`)
Advanced physics interactions between balloons, gas, fire, and lava.

### Story 25.1: Environmental Interactions
- [x] Task: Rising chocolate lava kills enemies instantly
- [x] Task: Rising chocolate lava ignites H2 gas on contact
- [x] Task: Mage fireballs are fire type - explode balloons on contact
- [x] Task: Dead players removed from "players" group (enemies stop targeting)
- [x] Task: Stealthed rogue removed from "players" group (invisible to enemy AI)

---

## EPIC 26: HUD & Profile Enhancements (`ui`)

### Story 26.1: Always-Visible HUD
- [x] Task: Total muffins display (top center)
- [x] Task: Per-player stats display (top right)

### Story 26.2: Profile Flow Improvements
- [x] Task: Auto-join on return from quit-to-menu
- [x] Task: Profile selection on fresh launch only
- [x] Task: Triangle to switch profile on title screen
- [x] Task: D-pad left/right for class cycling on title screen

---

## EPIC 27: Inline Player HUD & Selection Rework (`ui`, `mechanics`)
Replace the menu-based profile/class selection with an always-visible inline HUD.
Players select profile and class directly via D-pad on the title screen while
playing in the lobby arena. The HUD persists throughout all game modes.

### Story 27.1: Persistent Player HUD
- [x] Task: Create new `player_hud.gd` autoload with CanvasLayer (layer 100)
- [x] Task: Show 1-4 HUD panels at bottom-center, evenly spaced, based on connected controllers
- [x] Task: Each HUD shows: profile name (default "P1"-"P4"), class name, class color icon, HP/mana bars
- [x] Task: HUD visible in ALL game states (title, overworld, tower, boss)
- [x] Task: Remove old HUD from GameManager (`_create_hud`, `_muffin_label`, `_player_stat_labels`)

### Story 27.2: Inline Profile Selection (Title Screen Only)
- [x] Task: D-pad up/down cycles through available profiles on the title screen
- [x] Task: Profiles already selected by another player are skipped
- [x] Task: Default display is "P1"-"P4" when no profile is bound
- [x] Task: HUD updates immediately when profile changes
- [x] Task: START button shows "Create Profile" name entry overlay (title screen only)
- [x] Task: Newly created profile auto-selects for that player

### Story 27.3: Inline Class Selection (Title Screen Only)
- [x] Task: D-pad left/right cycles through available classes on the title screen
- [x] Task: Classes already selected by another player are skipped
- [x] Task: On class change: red portal appears at player position, player becomes ghost
- [x] Task: Character model swaps with smoke poof VFX at same position
- [x] Task: Pressing any non-movement button spawns 2nd red portal, player becomes interactive

### Story 27.4: Play Area Buffer
- [x] Task: Add bottom margin to camera/viewport so HUD doesn't cover gameplay
- [x] Task: Ensure HUD is readable over all backgrounds (slight dark backing)

### Story 27.5: Remove Old Selection System
- [x] Task: Remove profile/class selection logic from `title_screen.gd` (`_input` overlay triggers)
- [x] Task: Remove old player slot UI from `title_screen.tscn` (PlayerSlots HBoxContainer)
- [x] Task: Clean up `PlayerManager._input` join flow — auto-join on controller connect
- [ ] Task: Remove `profile_select_overlay.gd` file (no longer loaded, safe to delete)
- [ ] Task: Clean up unused signals and methods in ProfileManager

---

## EPIC 28: Rift Tentacle System (`mechanics`)
Tentacle emerges from a red rift portal when players change class.

### Story 28.1: Base Tentacle
- [x] Task: Verlet physics tentacle (14 segments, ~126px) with purple visual
- [x] Task: Phase 0 (0-5s): confused wiggling
- [x] Task: Phase 1 (5-15s): hunt nearest non-owner player, lunge at 1.5x reach
- [x] Task: Phase 2 (grab): 4 smashes (8 dmg each) + smoke VFX + fling
- [x] Task: Red portal + ghost + smoke poof on class change
- [x] Task: 15-second class-change lockout during rift

### Story 28.2: Enemy Attachment
- [x] Task: Tentacle also grabs enemies (permanent attach)
- [x] Task: Enemy buff: 2x health, 1.5x scale, red-purple tint
- [x] Task: Attached tentacle attacks players: single pound + random fling
- [x] Task: Owner permanently loses class-change ability on attachment

### Story 28.3: Tentacle Sub-Health
- [x] Task: 50 HP sub-health absorbs damage before enemy takes it
- [x] Task: Rift size scales with tentacle health
- [x] Task: At 0 HP: purple smoke puff, enemy restored, owner unlocked
- [x] Task: Patched boss_base.gd + all 18 enemy take_damage functions

### Story 28.4: Tentacle Limits & Reset
- [x] Task: Max 4 active tentacles in-game
- [x] Task: All tentacle state resets on level/scene transition
- [x] Task: HUD shows tentacle status (available/active/lost)

---

## EPIC 29: Item Drops (`mechanics`)

### Story 29.1: Health Pickup
- [x] Task: Green + shaped health pickup with sparkle particles
- [x] Task: 25% drop chance on enemy death (all 18 enemy types)
- [x] Task: Heals 15 HP on player contact
- [x] Task: 30-second despawn timer, bobble animation
- [x] Task: Collect VFX: green particle burst + scale-up fade

---

## EPIC 30: Ranger Grappling Hook Rework (`mechanics`, `physics`)
Replace the current grappling hook with a full physics-based system.
The hook swings, launches, and creates momentum-based traversal.
Grappled entities react based on true mass physics.

### Story 30.1: Grapple Windup & Throw
- [x] Task: L1/LB initiates grapple. Hook swings in a circle (14–35 rad/s)
- [x] Task: Either thumbstick aims (right priority). Dotted arrow shows direction.
- [x] Task: Release L1 throws at 4000–10000 px/s with gravity arc. Max range 900px.
- [x] Task: Full movement during windup (walk, jump, gravity all work)

### Story 30.2: Grapple Connection & Launch
- [x] Task: Hook connects on walls or entities (10 damage on hit)
- [x] Task: Player launched toward anchor at 75% jump velocity, blended with travel direction
- [x] Task: Rope slack physics: goes slack above anchor, bounces when taut

### Story 30.3: Pendulum Swing Physics
- [x] Task: Full pendulum physics with momentum/brake input and rope length adjustment
- [x] Task: Rope rendered with catenary sag proportional to slack
- [x] Task: Launch immunity preserves momentum through freefall until landing

### Story 30.4: Grapple Release & Enemy Tug
- [x] Task: Two-phase disconnect (wall): L1 = pull toward anchor, L1 again = release
- [x] Task: Jump disconnect: additive 25% jump velocity in thumbstick direction
- [x] Task: Enemy tug: Newtonian F=ma on both ends based on mass
- [x] Task: Controller rumble at all grapple events (windup, throw, connect, swing, tug, release)

### Story 30.5: Entity Mass System
- [x] Task: `mass` property on all 18 enemies, boss_base, and player (70)
- [x] Task: Mass values from 5 (Sprinkle Swarm) to 300 (Bosses)

| Entity | Mass | Tug Behavior |
|--------|------|-------------|
| Sprinkle Swarm | 5 | Flung hard |
| Fairy Cake Bat | 8 | Flung |
| Skeleton | 30 | Flung |
| Candy Corn | 25 | Flung |
| Cookie Archer | 30 | Flung |
| Cupcake Bomber | 35 | Tugged |
| Licorice Whip | 40 | Tugged |
| Peppermint Roller | 25 | Flung |
| Marshmallow Blob | 50 | Tugged |
| Gummy Bear | 60 | Tugged |
| Wafer Shield | 55 | Tugged |
| Jellybean Sniper | 30 | Flung |
| Candy Golem | 150 | Reverse tug |
| Player | 70 | Reference |
| Mini-bosses | 120 | Reverse tug (slight) |
| Bosses | 300 | Reverse tug (strong) |

---

## EPIC 31: Archer Aimed Shot (`mechanics`)
Physics-based arrow aiming with parabolic arc solver.

### Story 31.1: Aim System
- [x] Task: L2 hold enters aim mode with movable reticle (right stick)
- [x] Task: Quadratic arc solver finds launch angle for target position
- [x] Task: Reticle sparkles when solution found, 50% transparent when not
- [x] Task: Arrow follows parabolic arc with gravity (500 px/s²)
- [x] Task: Can fire without solution (best-attempt trajectory)

### Story 31.2: Power Control
- [x] Task: Pull strength scales with L2 hold time (300–1800 px/s)
- [x] Task: Partial trigger pull = proportional max power cap
- [x] Task: RB reverses power direction, release RB locks power level
- [x] Task: Locked power persists across shots, charges up to lock level
- [x] Task: Lock indicator (white tick + gold diamond) on charge bar

### Story 31.3: Fire Mechanics
- [x] Task: R2 fires with edge detection (fresh press required)
- [x] Task: 0.5s cooldown, auto re-string while L2 held
- [x] Task: Does not consume regular ammo pool
- [x] Task: Reticle position persists across L2 pulls

---

## EPIC 32: Debug & Developer Tools (`tools`)

### Story 32.1: Debug Mode
- [x] Task: SELECT button toggles debug mode
- [x] Task: Velocity arrows (green=current, red=predicted jump)
- [x] Task: Debug tracer arrows on grapple jump (green/yellow/cyan, 10s linger)
- [x] Task: HUD button state display above each player panel
- [x] Task: Archer debug: solver arc + arrow trail (orange/cyan, 10s linger)

### Story 32.2: Velocity Audit System (documented, not implemented)
- [ ] Task: See docs/design/velocity_audit_system.md

---

## EPIC 33: Controller Features (`ui`)

### Story 33.1: Haptic Feedback
- [x] Task: Grapple rumble at all key moments (windup through release)
- [x] Task: Swing rumble scales with velocity (5–20% weak motor)

### Story 33.2: LED Color
- [x] Task: Controller LED matches player class color (Godot 4.6 Input.set_joy_light)
- [x] Task: Updates on spawn and class change

---

## EPIC 34: Quality of Life (`mechanics`)

### Story 34.1: Out-of-Bounds Teleport
- [x] Task: Teleport OOB players to nearest player with purple aether rift VFX

### Story 34.2: Profile Class Memory
- [x] Task: Save last_class to profile, auto-select on rejoin if available

### Story 34.3: Class Change Ghost State
- [x] Task: In-game class change requires button press to materialize before rift spawns

---

## EPIC 35: Portal Doorway (Title Screen) (`ui`, `mechanics`)
Replace "Press START to begin" with a magical portal doorway in the lobby arena.
Players walk into the doorway to start the game.

### Story 35.1: Doorway Structure
- [ ] Task: Large stone doorway in center of title screen arena
- [ ] Task: Front layer: stacked stones with archway and keystone
- [ ] Task: Back layer: pure black (void behind the arch)
- [ ] Task: Players render between front and back layers when near

### Story 35.2: Portal Activation
- [ ] Task: Single player in front of doorway: blue sparkly spiral appears, spinning
- [ ] Task: Heavy particle effects around the spiral
- [ ] Task: ALL players in front of doorway: glow brightens
- [ ] Task: Translucent sparkly rays shoot outward from center

### Story 35.3: Transition Sequence
- [ ] Task: All players pulled toward door center
- [ ] Task: Players shrink and spin as they are sucked in
- [ ] Task: Transition to overworld after animation completes

### Story 35.4: UI Cleanup
- [ ] Task: Remove "Press START to begin" text
- [ ] Task: Remove "START: begin" from HUD hints

---

## EPIC 36: Level Editor (`tools`)
Built-in level editor for configuring levels via JSON files.
See `docs/design/level_editor.md` for full specification.

### Story 36.1: JSON Level Configuration
- [ ] Task: Define JSON schema for level configuration (spawn zones, platforms, scenery, portal, camera)
- [ ] Task: Default JSON files stored in `res://levels/` (bundled with game)
- [ ] Task: Override JSON files stored in `user://levels/` (user data directory)
- [ ] Task: LevelConfig autoload: loads level data with fallback to bundled defaults
- [ ] Task: Validation: corrupt/missing override falls back gracefully with warning

### Story 36.2: Level Loading Integration
- [ ] Task: Title screen loads configuration from JSON instead of hardcoded values
- [ ] Task: Tower levels load platform layout from JSON
- [ ] Task: Spawn zones for all creature types loaded from JSON
- [ ] Task: Scenery (trees, rocks) loaded from JSON with seeds

### Story 36.3: Editor UI Framework
- [ ] Task: Editor toggle via key combo (Ctrl+E)
- [ ] Task: Mode selector tab bar (spawn areas, seeds, platforms, portal)
- [ ] Task: Properties panel for selected item
- [ ] Task: Save/Reset buttons

### Story 36.4: Edit Spawn Areas Mode
- [ ] Task: Spawn zones shown as colored translucent overlays
- [ ] Task: Corner vertices draggable via mouse click-and-drag
- [ ] Task: Add/delete zones via right-click context menu
- [ ] Task: Zone weight and type editable

### Story 36.5: Edit Seeds Mode
- [ ] Task: Procedural items shown with seed numbers
- [ ] Task: Click to select, G to regenerate (existing feature)
- [ ] Task: Position draggable via mouse

### Story 36.6: Edit Platforms Mode
- [ ] Task: Platform positions and widths shown with drag handles
- [ ] Task: Drag center to move, drag edges to resize
- [ ] Task: Click empty space to add new platform

### Story 36.7: Edit Portal Mode
- [ ] Task: Portal position draggable
- [ ] Task: Activation range shown as circle overlay
- [ ] Task: Timer value editable

---

## Future Ideas (Unscheduled)
- Multiplayer lobby over network (not just local)
- Additional tower sets (post-game content)
- Character skins/cosmetics
- Leaderboards for muffin collection
- Story/dialogue system
- Achievement system
