# Game Systems

## 1. Player Join System

- Up to 4 players — connected controllers auto-join on the title screen
- Keyboard is NOT auto-joined (controller-only game)
- Each player is assigned the next available player index (0-3)
- A guest profile is auto-created if no saved profile exists for the controller
- Controller hot-plug: connecting mid-title-screen auto-joins, disconnecting removes the player
- Players can also join mid-game via START in any scene

## 2. Death & Revive System

**Dying:**
- When health reaches 0, the player becomes a "ghost"
- Ghost appearance: semi-transparent blue (0.5, 0.5, 0.8, 0.4 alpha)
- Ghost cannot move, attack, or be damaged
- Collision layer set to 0 (no physics interactions)
- "STAND NEAR TO REVIVE" label appears above head
- Yellow progress bar appears above head

**Reviving:**
- Any alive teammate within 60px automatically starts reviving
- No button press needed - just stand near
- Revive takes 3.0 seconds of continuous proximity
- Progress bar fills yellow as revive progresses
- If teammate leaves range, progress slowly drains (0.5x rate)
- On revive: health restored to 50%, gold flash VFX, "player_revive" sound

## 3. Tower Generation

Towers are procedurally generated based on `tower_id`:

| Parameter | Formula |
|-----------|---------|
| Platform count | 8 + (tower_id × 2) |
| Vertical spacing | 2400 / (platform_count + 1) |
| Platform width | Random 80-160px |
| X position | Alternates left/right with sine variation |

**Content placement:**
- Muffins on every other platform (even index)
- Enemies on every 3rd platform starting from index 1
- Enemy patrol distance = 40% of platform width
- Floor platform spans full tower width at bottom
- Exit door at top (y=40)

## 4. Camera System (Multi-Player)

Dynamic camera that keeps all players on screen:
- Calculates bounding box of all players + donut buddies
- Centers on the midpoint of all players, shifted up to account for bottom HUD
- Reserves 90px at viewport bottom for the PlayerHUD strip
- Zoom uses reduced usable height so players aren't framed behind HUD
- Zooms out when players spread apart, in when close
- Smooth lerp at speed 4.0
- Configurable min/max zoom and margin per scene
- Title screen uses a fixed camera (no pan/zoom) centered at (960, 495)

| Scene | Min Zoom | Max Zoom | Margin |
|-------|----------|----------|--------|
| Title Screen | Fixed | Fixed | N/A |
| Overworld | 0.6 | 1.2 | 200×150 |
| Tower | 0.5 | 1.8 | 100×80 |
| Boss Arena | 0.6 | 1.2 | 150×100 |

## 5. Audio System

Global `AudioManager` autoload with pooled playback:
- Max 4 simultaneous instances per sound name
- Pool reuses silent AudioStreamPlayers
- Configurable volume (dB) and pitch per call
- Steals oldest player if pool is full
- Process mode: ALWAYS (plays even when paused)

### Sound List (39 sounds)
| Sound | Used For |
|-------|----------|
| sword_slash | Melee attack (pitch varies by combo hit) |
| crossbow_shoot | Ranged attack |
| magic_bolt | Mage attack |
| staff_bonk | Summoner attack |
| dagger_stab | Rogue attack |
| shield_charge | Melee special, Tank fortify/slam |
| explosion | Bomb explosions, ground slam landing |
| freeze | Mage freeze effect |
| summon | Summoner special, delegate mode, healer potion |
| shadow_dash | Rogue special, delegate dash |
| jump | All classes jumping |
| muffin_collect | Picking up mini-muffins |
| player_hurt | Taking damage |
| player_die | Player death |
| player_revive | Revive complete, healing zone |
| enemy_hit | Hitting an enemy |
| enemy_die | Enemy killed |
| boss_roar | Boss spawns |
| boss_defeat | Boss killed |
| menu_select | Menu navigation |
| menu_confirm | Menu selection |
| pause | Pause toggle |
| airwalk_activate | Mage air-walk activation |
| backstab_hit | Rogue backstab from stealth |
| beam_fire | Mage beam of light charge attack |
| enrage_roar | Melee enrage activation |
| grapple_launch | Ranger grappling hook fire |
| grapple_hit | Ranger grappling hook impact |
| mana_drink | Mage mana potion consumption |
| mark_target | Summoner homing mark hit |
| refuel_gurgle | Demolitionist refueling jetpack |
| reload_click | Ranger ammo reload |
| rocket_ignite | Demolitionist jetpack ignition |
| rocket_thrust | Demolitionist jetpack thrust loop |
| rocket_crash | Demolitionist crash landing explosion |
| stealth_activate | Rogue stealth activation |
| wind_gust | Healer wind gust knockback |
| guitar_note | Guitarist musical note attack (Karplus-Strong synthesis) |
| guitar_blast | Guitarist blast wave special |

## 6. Scene Transition System

All transitions go through `GameManager.transition_to_scene()`:
- Uses `call_deferred` to avoid physics callback issues
- `_transitioning` flag prevents double-transitions
- Flag resets after 2 process frames

### Transition Map
| From | Trigger | To |
|------|---------|-----|
| Title Screen | START pressed (≥1 player) | Overworld |
| Overworld | Walk into tower entrance | Tower |
| Tower | Reach exit door at top | Boss Arena |
| Boss Arena | Defeat boss (3s delay) | Overworld |
| Any scene | Pause → Quit | Title Screen |

## 7. Collectibles

### Mini-Muffins
- Found on tower platforms and dropped by enemies (3 on death)
- Area2D collision detection with players
- Sparkle animation (if sprite frames available)
- On collect: scale up 1→1.5 + fade out over 0.25s
- Increments player's muffin_count in both GameManager and PlayerManager
- "muffin_collect" sound at -5dB

### Artifacts
- Awarded when a boss is defeated
- Each tower has 2 possible artifacts
- Distributed round-robin to players: `artifact[player_index % count]`
- Stored in GameManager per player

## 8. Pause Menu

- Global autoload (`PauseMenu`) - available in all scenes
- Triggered by START/Options or Escape (not on title screen)
- Pauses the entire game tree (`get_tree().paused = true`)
- Process mode: ALWAYS (menu still responds while game paused)
- Two options: RESUME / QUIT
- Navigate with D-pad up/down
- Confirm with X (Cross) or Space
- QUIT resets all game state and returns to title screen

## 9. Health Bar System

Reusable `HealthBar` scene (Node2D with custom `_draw()`):
- Draws border → background → damage trail → current health
- Color shifts: green (>80%) → yellow (50-80%) → red (<50%)
- Smooth drain animation (damage trail lags behind actual health)
- Configurable: width, height, offset, colors, hide-when-full flag

| Entity | Bar Width | Bar Height | Offset | Color |
|--------|-----------|------------|--------|-------|
| Player | 28px | 3px | y=-22 | Green→Red |
| Player Mana | 28px | 2px | y=-18 | Blue |
| Skeleton | 20px | 2px | y=-18 | Red |
| Boss | 48px | 4px | y=-44 | Red |
| Donut Buddy | 16px | 2px | y=-16 | Orange |
| Revive Progress | 28px | 3px | y=-30 | Yellow |

## 10. Overworld Structure

**Layout (1280×720 single screen):**
```
         [Tower 1] (top center, y=75)
            |
[Tower 2]---[Valley Spawn]---[Tower 3]
 (left)      (center)         (right)
            |
       [== CHASM ==]
            |
       [Final Tower] (bottom center)
```

- Valley spawn at (640, 400)
- 3 zipline visuals (hidden until tower complete)
- Chasm blocker (StaticBody2D) prevents access to final tower
- Blocker removed when all 3 towers completed
- Tower entrances: Area2D with 80×80 collision shapes
- Any single player entering triggers transition (no need for all players)

## 11. Character Leveling System

Skill-based leveling: abilities improve through effective use.

**XP Sources:**
- Successful hit on enemy: 1-3 XP (scales with enemy difficulty)
- Special ability use: 5-10 XP
- Charge attack damage: 1 XP per 5 damage dealt
- Block: 3 XP per blocked hit, 15 XP for perfect parry
- Healing (Healer): 0.5 XP per HP healed on allies
- Summoning (Summoner): donut buddy damage contributes XP

**Per-Skill Tracking:**
- Basic attack, special ability, charge attack, block/parry each level independently
- Max skill level: 20, max overall level: 50

**Level Benefits:**
| Skill | Bonus Per Level |
|-------|----------------|
| Attack | +2% damage |
| Special | +2% effect |
| Charge | +3% charge speed, +2% max charge damage |
| Block | +1% damage reduction |

**Overall Level:**
- Average of all skill levels (rounded down)
- +5 max HP per level, +3 max mana per level
- Displayed next to player name (e.g. "Dax - Melee Lv.7")

---

## 12. Persistent Profile System

ProfileManager autoload manages player profiles saved as JSON in `user://`.

**Profile Data:** name, class preferences (stack-ranked), per-class stats (level, skill_xp, total_kills, total_muffins, boss_kills), created date, lifetime stats.

**Profile Flow:**
1. Controller connects -> "Choose Profile" or "Create New" screen
2. Create: enter name (3-16 chars) -> stack-rank class preferences -> optionally name sub-characters -> confirm
3. Existing profiles shown with level + preferred class icon
4. Up to 8 saved profiles, guest mode available (no progress saved)

**Auto-Save Triggers:** tower completion, boss defeat, quit to menu.

**Profile-Linked Gameplay:**
- Join auto-assigns profile's top available class
- If preferred class taken, uses next in stack-rank
- Player label shows profile name (e.g. "Dax - Melee Lv.7")
- XP and levels persist across sessions

---

## 13. Ammo & Reload System (Ranged)

- Ranged class has limited arrows
- Reload by holding Circle (1.5s reload time)
- Cannot attack while reloading
- Ammo count displayed on HUD

---

## 14. Stealth System (Rogue)

- Activate on Circle: 5s duration, 20s cooldown
- While stealthed: semi-transparent, enemies do not target rogue
- 50% damage reduction while stealthed
- Attacks from stealth deal 3.75x damage (backstab multiplier)
- Stealth breaks on attack

---

## 15. Enrage System (Melee)

- Activate on Circle: 10s duration, 45s cooldown
- 1.5x speed multiplier, 1.8x damage multiplier
- Red tint visual effect
- enrage_roar.wav on activation

---

## 16. Rocket Jetpack System (Demolitionist)

- First jump: normal. Second jump press: activates rocket (4s fuel)
- 800 thrust acceleration, 550 max speed
- Aim direction controls thrust vector
- Chaos mechanic: drift angle increases over time with random spin direction
- Out of fuel: crash explosion deals damage to self and nearby
- Refuel: hold Circle while grounded (no auto-refuel)
- Landing safely deactivates rocket

---

## 17. Air-Walk System (Mage)

- Activate on Circle: 5s duration, 10s cooldown
- Disables gravity: mage can walk on air
- Full movement in all directions while airborne
- Useful for positioning beam attacks and avoiding ground hazards

---

## 18. Fortify System (Tank)

- Activate on Circle: 8s duration, 25s cooldown
- 60% incoming damage reduction
- 50% attack damage reduction (tradeoff)
- Bronze glow VFX with pulsing animation
- Warning flash in final 2 seconds

---

## 19. Delegate Mode (Summoner)

- Activate on Circle: 10s duration, 30s cooldown
- Summoner freezes in trance, ghost delegate spawned
- Player controls the ghost (1.5x speed, 1.5x jump, can dash)
- All donut buddies follow the ghost
- Summoner takes 1.5x damage; hit >= 15 cancels delegate
- On exit: aether rift teleport to ghost's position

---

## 20. Balloon Physics System

Balloons are core to the Balloonist class and interact with multiple game systems.

**Balloon Properties:**
- Teardrop-shaped visual with physics string (12 chain segments)
- Balloons repulse each other (spread out naturally)
- Affected by wind gusts and environmental forces
- Weight system: balloons add lift force to attached entities

**H2 Gas System:**
- When a balloon is popped, it releases H2 (hydrogen) gas
- H2 gas lingers in the air for 25 seconds
- H2 gas ignites on contact with fire-type attacks or lava
- Ignition causes a hydrogen explosion with area damage
- Chain reactions: one explosion can ignite nearby H2 clouds
- Mage fireballs (fire type) are the primary ignition source
- Rising chocolate lava also ignites H2 gas on contact

**Balloon Interactions:**
- Mage fireballs explode balloons on contact (fire type)
- Popping creates H2 gas clouds
- Balloonist "Pop All" detonates all active balloons at once
- Chain reaction potential: pop all near fire = massive explosion

---

## 21. Entity Mass System

Every entity has a `mass` property used for all physics interactions:
grapple tug, knockback, blast wave push, balloon lift.

| Entity | Mass | Category |
|--------|------|----------|
| Sprinkle Swarm | 5 | Tiny |
| Fairy Cake Bat | 8 | Tiny |
| Peppermint Roller | 25 | Small |
| Candy Corn | 25 | Small |
| Skeleton | 30 | Small |
| Cookie Archer | 30 | Small |
| Jellybean Sniper | 30 | Small |
| Cupcake Bomber | 35 | Medium |
| Licorice Whip | 40 | Medium |
| Marshmallow Blob | 50 | Medium |
| Wafer Shield | 55 | Medium |
| Gummy Bear | 60 | Medium |
| Player | 70 | Reference |
| Mini-bosses | 120 | Heavy |
| Candy Golem | 150 | Heavy |
| Bosses | 300 | Very Heavy |

Mass affects:
- Grapple tug: F=ma applied to both ends (see §29)
- Guitarist blast wave push distance (lighter = pushed further)
- Werewolf roar push distance
- Balloon lift (lighter entities float higher)
- General knockback calculations

---

## 22. Rising Chocolate Lava

- Chocolate lava rises from the bottom of certain tower sections
- Kills enemies instantly on contact
- Forces players to climb faster (acts as a timer mechanic)
- Ignites H2 gas on contact (interacts with balloon system)
- Visual: bubbling brown lava surface with particle effects

---

## 23. Enemy Targeting & Group System

**Dead Players:**
- Dead players are removed from the "players" group
- Enemies stop targeting dead players immediately
- Prevents enemies from attacking ghosts waiting for revive

**Stealthed Rogue:**
- Stealthed rogue is removed from the "players" group
- Enemies cannot detect or target the stealthed rogue
- Rogue becomes fully invisible to enemy AI (not just reduced detection)

---

## 24. Inline Player HUD

`PlayerHUD` autoload (CanvasLayer 100) — always visible across all game states.

**Layout:** 1-4 panels at bottom-center, evenly spaced based on connected controllers.
Dark backing strip spans full width, 80px tall with 10px bottom margin.

**Each panel shows:**
- Class sprite (first frame of side spritesheet via AtlasTexture, 32×32)
- Profile name (default "P1"-"P4", updates when profile selected)
- Class name (updates on class change)
- HP bar (red) and mana bar (blue)
- Status line: tentacle/class-change status or selection hints

**HUD Status Indicators:**
| State | Text | Color |
|-------|------|-------|
| Available | "L/R: change class" | Green |
| Rift active (15s) | "RIFT ACTIVE..." | Red |
| Tentacle lost | "TENTACLE LOST" | Dark red |
| Title screen | "D-Pad: profile/class \| START: new profile" | Grey |

**Top Center:** Total muffins collected (hidden on title screen)

---

## 25. Inline Profile & Class Selection

**Profile Selection (Title Screen Only):**
- D-pad up/down cycles through available profiles
- Profiles already bound to another controller are skipped
- START opens name entry overlay to create a new profile
- Newly created profile auto-selects for that player

**Class Selection (Any Game State):**
- D-pad left/right cycles through available classes
- Classes taken by other players are skipped
- Keyboard: Q/E for class, R/F for profile (title only)

**Class Change VFX Sequence:**
1. Red portal + smoke poof at player position
2. Character sprite swaps in-place
3. Player briefly becomes ghost (semi-transparent)
4. Rift tentacle spawns (see System 27)
5. 15-second class-change lockout while rift is active

---

## 26. Display Settings

| Setting | Value |
|---------|-------|
| Viewport | 1920×1080 |
| Window Mode | Fullscreen (mode 3) |
| Stretch Mode | canvas_items |
| Stretch Aspect | expand |
| Texture Filter | Nearest (pixel-perfect) |
| Renderer | GL Compatibility |

---

## 27. Rift Tentacle System

When a player changes class, a red rift portal opens and a multi-segmented
tentacle emerges. The tentacle uses verlet physics (14 segments, ~126px).

**Phases:**
| Phase | Duration | Behavior |
|-------|----------|----------|
| Wiggle | 0-5s | Confused wiggling, sine-wave motion |
| Hunt | 5-15s | AI seeks nearest non-owner player OR enemy |
| Smash (player) | On grab | 4 smashes (8 dmg each) + smoke bursts, then fling |
| Attached (enemy) | Permanent | Buffs enemy, attacks nearby players |

**Player Grab:** 4 back-and-forth smashes at 8 damage each with smoke VFX,
then flings the player away. Returns to hunt phase.

**Enemy Grab:** Permanently attaches to enemy with buffs:
- 2× health, 1.5× scale, red-purple tint
- Tentacle follows enemy indefinitely with smaller red-purple rift
- Attacks nearby players: single pound + random high-speed fling (600px/s)
- 4-second cooldown between attacks

**Tentacle Sub-Health (50 HP):**
- When attached to an enemy, all damage to the enemy goes to tentacle first
- Rift size visually scales with remaining tentacle health
- At 0 HP: large purple smoke puff, tentacle vanishes, enemy restored to normal
- Owner player's class-change ability is restored

**Limits:**
- Max 4 active tentacles in-game at once
- If tentacle attaches to enemy, owner permanently loses class-change ability
  (until next level or tentacle is destroyed)
- All tentacle state resets on level/scene transitions

**Visual:**
- Purple outer / light-purple inner segments
- Circular suckers alternating sides at segment joints
- Menacing curled hook at the tip
- Red glow on player grab, purple glow when attached to enemy

---

## 28. Health Pickup System

Enemies have a 25% chance to drop a health pickup on death.

**Appearance:** Green + shaped item (drawn with `_draw()`), pulsing glow
**Sparkles:** Green particles spawn every 0.3s, float upward and fade
**Motion:** Pops up 30px on spawn, then bobbles gently up and down
**Heal:** 15 HP on player contact
**Despawn:** Fades out after 30 seconds if not collected
**Collect VFX:** Burst of 6 green sparkles + scale-up fade
**Sound:** "muffin_collect" at -3dB, pitch 1.3

---

## 29. Physics-Based Grappling Hook (Ranger)

Full physics simulation replacing the old raycast grapple. See
`docs/design/grappling_hook_physics.md` for detailed constants and formulas.

**State Machine:** IDLE → WINDUP → THROWN → CONNECTED → SWINGING → RETRACTING

**Windup:** Hold grapple button to swing the hook in a circle. Angular velocity
increases with hold time (4–12 rad/s). Visual: hook orbiting at 40px radius.

**Throw:** Release in thumbstick direction. Speed scales with hold time
(200–500 px/s). Hook follows a gravity arc. Rope trails as verlet chain.

**Connection:** Hook anchors to walls (StaticBody2D) or entities. Player
launches toward anchor at 50% of jump velocity.

**Pendulum Swing:** At apex, rope goes taut. Player swings as a pendulum
(`α = -(g/L)*sin(θ)`). Left/right adjusts momentum, up/down adjusts rope length.

**Release (Wall):** Player retains swing momentum. Rope retracts visually.

**Tug (Enemy):** Newtonian physics — constant force applied, both entities
accelerate proportionally to `F/mass`. Light enemies flung toward player,
equal mass = mutual pull, heavy enemies = player flung toward them.

| Tug Result | Mass Ratio (enemy/player) |
|------------|--------------------------|
| Enemy flung hard | < 0.5 |
| Enemy pulled | 0.5 – 0.8 |
| Both pulled equally | 0.8 – 1.2 |
| Player pulled | 1.2 – 2.0 |
| Player flung toward enemy | > 2.0 |

---

## 26. Display Settings

| Setting | Value |
|---------|-------|
| Viewport | 1920×1080 |
| Window Mode | Fullscreen (mode 3) |
| Stretch Mode | canvas_items |
| Stretch Aspect | expand |
| Texture Filter | Nearest (pixel-perfect) |
| Renderer | GL Compatibility |
