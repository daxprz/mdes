# The Ultimate Muffin - Backlog

> Status: `[ ]` = todo, `[~]` = in progress, `[x]` = done

---

## EPIC 1: Art Style Overhaul (`art`)
Improve all pixel art from placeholder quality to polished retro style.

### Story 1.1: Character Sprites
- [ ] Task: Melee knight - topdown spritesheet (128x128) with shading, outline, detail
- [ ] Task: Melee knight - side spritesheet (192x32) with shading, outline, detail
- [ ] Task: Ranged ranger - topdown spritesheet
- [ ] Task: Ranged ranger - side spritesheet
- [ ] Task: Mage wizard - topdown spritesheet
- [ ] Task: Mage wizard - side spritesheet
- [ ] Task: Summoner - topdown spritesheet
- [ ] Task: Summoner - side spritesheet
- [ ] Task: Rogue - topdown spritesheet
- [ ] Task: Rogue - side spritesheet
- [ ] Task: Donut buddy sprite (144x24)

### Story 1.2: Boss Sprites
- [ ] Task: Gingerbread Skeleton (256x64) - cookie bones, icing detail, gumdrop eyes
- [ ] Task: Icing Goblin (256x64) - dripping frosting, cherry eyes, sprinkle decor
- [ ] Task: Sprinkle Dragon (256x64) - rainbow sprinkle scales, candy fire breath
- [ ] Task: Giant Muffin (256x64) - angry face, paper wrapper lines, chocolate chips

### Story 1.3: Enemy Sprites
- [ ] Task: Skeleton enemy (128x32) - visible ribcage, glowing eyes, bone club
- [ ] Task: Design & create 2-3 additional enemy types

### Story 1.4: Item Sprites
- [ ] Task: Mini muffin (64x16) with sparkle animation
- [ ] Task: Ultimate muffin (16x16) with halo glow
- [ ] Task: 5 class artifacts (16x16 each)
- [ ] Task: Mana potion / health potion pickups

### Story 1.5: Environment Tiles
- [ ] Task: Overworld tileset (160x160) - grass, paths, water, trees, rocks
- [ ] Task: Tower tileset (160x160) - stone, platforms, ladders, spikes, torches
- [ ] Task: Boss arena backgrounds (per boss theme)

### Story 1.6: UI Art
- [ ] Task: Heart icon, mana icon, muffin counter icon
- [ ] Task: Portal animation (128x32)
- [ ] Task: Title logo "THE ULTIMATE MUFFIN" (256x64)
- [ ] Task: Menu panel art / button styles

---

## EPIC 2: Bug Fixes (`bugs`)

### Story 2.1: Boss Arena Escape
- [ ] Task: Add walls/ceiling to boss arena so players can't jump out
- [ ] Task: Add kill zone below arena floor (respawn player if they fall)

### Story 2.2: Crash Fixes
- [ ] Task: Audit all scripts for Variant type inference errors (`sign()`, etc.)
- [ ] Task: Test all scene transitions (title→overworld→tower→boss→overworld)
- [ ] Task: Fix any remaining `call_deferred` issues during physics callbacks

---

## EPIC 3: Overworld Progression (`design`, `mechanics`)
The overworld needs structure - players shouldn't access everything immediately.

### Story 3.1: Area Gating
- [ ] Task: Block paths to Tower 2 and Tower 3 until Tower 1 is complete
- [ ] Task: Each tower completion unlocks a zipline to the NEXT area
- [ ] Task: Zipline is an interactive object players ride across chasms
- [ ] Task: Final tower area only accessible after all 3 ziplines unlocked

### Story 3.2: Overworld Boundaries
- [ ] Task: Add proper walls/fences around the playable overworld area
- [ ] Task: Add visual boundaries (cliffs, water, dense forest)
- [ ] Task: Camera limits so players can't see outside the map

### Story 3.3: Overworld Polish
- [ ] Task: Make ziplines animated/functional (not just visual blocks)
- [ ] Task: Add NPC or signpost near each tower with lore/hints
- [ ] Task: Add ambient overworld enemies (optional combat)

---

## EPIC 4: Enemy Variety (`enemies`)

### Story 4.1: New Enemy Types
- [ ] Task: Design flying enemy (bat/fairy cake) - moves in sine wave pattern
- [ ] Task: Design ranged enemy (cookie archer) - shoots at players from distance
- [ ] Task: Design tank enemy (candy golem) - slow, high HP, big hits
- [ ] Task: Design swarm enemy (sprinkle bugs) - small, fast, come in groups

### Story 4.2: Enemy Density & Placement
- [ ] Task: Increase enemy count per tower floor (scale with tower difficulty)
- [ ] Task: Add enemy spawn points that trigger when players reach certain heights
- [ ] Task: Mix enemy types per floor for tactical variety

### Story 4.3: Enemy Behaviors
- [ ] Task: Enemies should work together (ranged stays back while melee charges)
- [ ] Task: Enemies should react to player class (focus summoner's donut buddies, etc.)

---

## EPIC 5: Level Design Variety (`design`, `mechanics`)

### Story 5.1: Tower Layout Improvements
- [ ] Task: Reduce platform spacing to match jump height with comfortable margin
- [ ] Task: Add multiple paths up (left route vs right route)
- [ ] Task: Add secret areas with bonus muffins
- [ ] Task: Each tower has a unique visual theme (gingerbread, icing, sprinkle)

### Story 5.2: Platforming Challenge
- [ ] Task: Add moving platforms
- [ ] Task: Add crumbling platforms (break after standing on them)
- [ ] Task: Add conveyor belt platforms
- [ ] Task: Add vertical sections (climbing challenges)

---

## EPIC 6: Wall Jump Limits (`mechanics`)

### Story 6.1: Wall Cling Stamina
- [ ] Task: Add wall-cling stamina (deplete while wall sliding, regen on ground)
- [ ] Task: Visual indicator showing remaining wall-cling time
- [ ] Task: Max 2-3 wall jumps before must touch ground

---

## EPIC 7: Traps & Obstacles (`mechanics`, `design`)

### Story 7.1: Trap Types
- [ ] Task: Spike floors (deal damage on contact)
- [ ] Task: Swinging pendulum blades (timed obstacle)
- [ ] Task: Arrow traps (shoot from walls on a timer)
- [ ] Task: Lava/acid pools (instant kill or heavy damage)
- [ ] Task: Pressure plates that trigger traps

### Story 7.2: Environmental Hazards
- [ ] Task: Falling rocks/debris in certain sections
- [ ] Task: Wind gusts that push players sideways
- [ ] Task: Dark rooms where only nearby area is visible

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

## Future Ideas (Unscheduled)
- Multiplayer lobby over network (not just local)
- Additional tower sets (post-game content)
- Character skins/cosmetics
- Leaderboards for muffin collection
- Story/dialogue system
- Achievement system
