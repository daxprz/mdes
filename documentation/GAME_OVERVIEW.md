# The Ultimate Muffin - Complete Game Documentation

## What Is This Game?

The Ultimate Muffin is a **4-player local co-op PVE action game** built in Godot 4. Players work together to conquer bakery-themed towers, defeat sweet-themed bosses, and claim the Ultimate Muffin.

Players choose from **12 unique classes** (Melee, Ranged, Mage, Summoner, Rogue, Demolitionist, Healer, Tank, Ninja, Balloonist, Guitarist, Werewolf), each with distinct attacks, specials, charge attacks, and Circle-button abilities. Persistent player profiles track levels, XP, and stats across sessions.

The game has three modes of play:
1. **Top-down overworld** (Zelda-style) - explore a valley, choose which tower to enter
2. **Side-scrolling tower platforming** - ascend towers, fight enemies, collect muffins (includes standard towers and dungeon maze towers)
3. **Boss arena fights** - defeat a unique boss at the top of each tower

---

## Game Flow

```
TITLE SCREEN (playable lobby arena)
  - Press START (Options) to select/create a profile
  - Profile chosen → join with your preferred class
  - Use D-pad left/right to pick your class (12 classes, no duplicates)
  - Press Triangle to switch profile
  - Jump around and test your moves
  - Auto-join on return from quit-to-menu
  - Profile selection on fresh launch
  - Press START again to begin
        |
        v
OVERWORLD (top-down valley)
  - Walk to a tower entrance to enter
  - 3 towers + 1 final tower (locked until 3 complete)
  - Ziplines unlock after each tower, opening new paths
        |
        v
TOWER (side-scrolling platformer)
  - Ascend the tower by jumping between platforms
  - Collect mini-muffins along the way
  - Fight skeleton enemies
  - Reach the EXIT door at the top
        |
        v
BOSS FIGHT (side-scrolling arena)
  - Defeat the tower's boss
  - Earn class artifacts
  - Tower marked complete, zipline unlocked
  - Return to overworld
        |
        v
REPEAT for all 3 towers, then...
        |
        v
FINAL TOWER + GIANT MUFFIN BOSS
  - The hardest tower and the ultimate boss
  - Victory!
```

---

## Controls

### PS5 Controller
| Button | Action |
|--------|--------|
| Left Stick | Move / Aim |
| X (Cross) | Jump (Demolitionist: 2nd press = rocket jetpack) |
| Square | Attack (hold to charge) |
| Triangle | Special ability (also: switch profile on title screen) |
| Circle | Class ability (Enrage / Reload / Air-Walk / Delegate / Stealth / Refuel / Wind Gust / Fortify / Air Dash / Self-Float / Amp Up / Frenzy) |
| D-pad Left/Right | Cycle class (title screen) |
| R2 / L Shift | Block (perfect parry within 0.2s) |
| Options (Start) | Profile select / Join game / Pause |

### Keyboard
| Key | Action |
|-----|--------|
| WASD | Move / Aim |
| Space | Jump |
| J | Attack (hold to charge) |
| K | Special |
| F | Class ability (Circle equivalent) |
| Left Shift | Block |
| Enter | Join game |
| Escape | Pause |
| Q / E | Cycle class (title screen) |
