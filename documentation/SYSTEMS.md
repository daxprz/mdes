# Game Systems

## 1. Player Join System

- Up to 4 players can join at any time by pressing START (Options) / Enter
- Each player is assigned the next available player index (0-3)
- A random untaken class is assigned on join (can be changed on title screen)
- Players can join mid-game in any scene - they spawn at the scene's spawn point
- Controller disconnect removes the player

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
- Centers on the midpoint of all players
- Zooms out when players spread apart, in when close
- Smooth lerp at speed 4.0
- Configurable min/max zoom and margin per scene

| Scene | Min Zoom | Max Zoom | Margin |
|-------|----------|----------|--------|
| Title Screen | 0.8 | 1.3 | 200×150 |
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

### Sound List
| Sound | Used For |
|-------|----------|
| sword_slash | Melee attack (pitch varies by combo hit) |
| crossbow_shoot | Ranged attack |
| magic_bolt | Mage attack |
| staff_bonk | Summoner attack |
| dagger_stab | Rogue attack |
| shield_charge | Melee special |
| explosion | Ranged special, ground slam landing |
| freeze | Mage special |
| summon | Summoner special |
| shadow_dash | Rogue special |
| jump | All classes jumping |
| muffin_collect | Picking up mini-muffins |
| player_hurt | Taking damage |
| player_die | Player death |
| player_revive | Revive complete |
| enemy_hit | Hitting an enemy |
| enemy_die | Enemy killed |
| boss_roar | Boss spawns |
| boss_defeat | Boss killed |
| menu_select | Menu navigation |
| menu_confirm | Menu selection |
| pause | Pause toggle |

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

## 11. Display Settings

| Setting | Value |
|---------|-------|
| Viewport | 1920×1080 |
| Window Mode | Fullscreen (mode 3) |
| Stretch Mode | canvas_items |
| Stretch Aspect | expand |
| Texture Filter | Nearest (pixel-perfect) |
| Renderer | GL Compatibility |
