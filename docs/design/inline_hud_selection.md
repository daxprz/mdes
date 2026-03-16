# Inline Player HUD & Selection System

## Overview

Always-visible inline HUD at the bottom of the screen. Players use D-pad to
select profiles and classes directly. Profile selection is title-screen only;
class selection works in ALL game modes. The HUD persists across all states.

## HUD Layout

```
+----------------------------------------------------------------------+
|                                                                      |
|                        GAME PLAY AREA                                |
|                 (camera reserves 90px at bottom)                     |
|                                                                      |
+----------------------------------------------------------------------+
| [dark backing strip - full width, 80px + 10px margin]                |
| [P1 sprite|name|class|HP|MP]  [P2]  [P3]  [P4]                      |
+----------------------------------------------------------------------+
```

Each HUD panel (220×70px) contains:
- Class sprite (first frame of side spritesheet, 32×32 via AtlasTexture)
- Profile name (default "P1"-"P4", updates on profile selection)
- Class name
- HP bar (red) + Mana bar (blue)
- Status line (tentacle state or selection hints)

HUDs are evenly spaced along the bottom center. Only show HUDs for connected
controllers (1-4 panels). CanvasLayer 100.

## Selection Controls

### Profile (D-pad Up/Down) — Title Screen Only
- Cycles through available profiles (skips those bound to other controllers)
- Default state: guest profile auto-created, shows "P1"-"P4"
- Overhead player label updates immediately via ProfileManager.profile_loaded signal
- START opens name entry overlay to create a new profile
- Keyboard: R/F keys

### Class (D-pad Left/Right) — ANY Game State
- Cycles through available classes (skips those taken by other players)
- Blocked during rift lockout (15s) or if tentacle permanently lost
- Blocked when max tentacles (4) are active
- Keyboard: Q/E keys

### Class Change VFX
1. Red portal + smoke poof at player position
2. Character sprite swaps in-place (gameplay) or full respawn (title screen)
3. Player briefly becomes ghost (40% opacity)
4. On title screen: ghost until pressing any non-movement button, then materializes
5. Rift tentacle spawns (see SYSTEMS.md §27)
6. 15-second class-change lockout

## Auto-Join Flow

1. Controller connects → auto-join with guest profile (no START needed)
2. D-pad up/down → cycle profiles (title screen)
3. D-pad left/right → cycle classes (any time)
4. START → create new profile (title screen) or start game
5. Controller disconnects → player removed, HUD panel removed

## Camera Integration

The multi-camera (`multi_camera.gd`) reserves 90px at the bottom for the HUD:
- `HUD_RESERVED_HEIGHT = 90` (80px panel + 10px margin)
- Zoom uses reduced usable viewport height
- Camera target shifts upward by half the HUD height (in world units)
- Title screen uses fixed camera at (960, 495) — no pan/zoom

## Architecture

| Component | Type | Role |
|-----------|------|------|
| `PlayerHUD` | Autoload | HUD rendering, D-pad input, class/profile cycling |
| `player_side.gd` | Per-player | In-game class change handler (non-title) |
| `title_screen.gd` | Scene | Title-screen class change (respawn + ghost flow) |
| `multi_camera.gd` | Per-scene | Camera with HUD-aware framing |

## What Was Removed

- `profile_select_overlay.gd` menu UI (orphaned, no longer loaded)
- `PlayerSlots` HBoxContainer from `title_screen.tscn`
- Old HUD from `GameManager` (`_create_hud`, `_muffin_label`, `_player_stat_labels`)
- Profile-required join flow from `PlayerManager._try_join` (now auto-creates guests)
