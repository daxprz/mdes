# The Ultimate Muffin - Complete Game Documentation

## What Is This Game?

The Ultimate Muffin is a **4-player local co-op PVE action game** built in Godot 4. Players work together to conquer bakery-themed towers, defeat sweet-themed bosses, and claim the Ultimate Muffin.

The game has three modes of play:
1. **Top-down overworld** (Zelda-style) - explore a valley, choose which tower to enter
2. **Side-scrolling tower platforming** - ascend towers, fight enemies, collect muffins
3. **Boss arena fights** - defeat a unique boss at the top of each tower

---

## Game Flow

```
TITLE SCREEN (playable lobby arena)
  - Press START (Options) to join with a random class
  - Use L1/R1 to pick your class (no duplicates)
  - Jump around and test your moves
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
| Left Stick | Move |
| X (Cross) | Jump |
| Square | Attack |
| Triangle | Special ability |
| Circle | Interact |
| Options (Start) | Join game / Pause |
| L1 | Previous class (title screen) |
| R1 | Next class (title screen) |

### Keyboard
| Key | Action |
|-----|--------|
| WASD | Move |
| Space | Jump |
| J | Attack |
| K | Special |
| F | Interact |
| Enter | Join game |
| Escape | Pause |
| Q / E | Cycle class (title screen) |
