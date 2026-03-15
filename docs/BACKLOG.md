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
- [ ] Task: Add enemy spawn points that trigger when players reach certain heights
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
  - Shows all 7 classes in a list
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

## Future Ideas (Unscheduled)
- Multiplayer lobby over network (not just local)
- Additional tower sets (post-game content)
- Character skins/cosmetics
- Leaderboards for muffin collection
- Story/dialogue system
- Achievement system
