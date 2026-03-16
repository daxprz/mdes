# Inline Player HUD & Selection System

## Overview

Replace the overlay-menu-based profile/class selection with an always-visible
inline HUD at the bottom of the screen. Players use D-pad to select profiles
and classes directly while playing in the lobby arena. The HUD persists across
all game modes.

## HUD Layout

```
+----------------------------------------------------------------------+
|                                                                      |
|                        GAME PLAY AREA                                |
|                                                                      |
|                                                                      |
|                    (camera leaves buffer at bottom)                   |
+----------------------------------------------------------------------+
|  [P1 HUD]      [P2 HUD]      [P3 HUD]      [P4 HUD]               |
+----------------------------------------------------------------------+
```

Each HUD panel (roughly 200x60px) contains:
- Profile name (default "P1"-"P4", becomes player name when profile selected)
- Class name + class color icon
- HP bar + Mana bar (when in-game)
- On title screen: arrows hint for D-pad selection

HUDs are evenly spaced along the bottom center. Only show HUDs for connected
controllers (1-4 panels).

## Title Screen Selection

### Profile (D-pad Up/Down)
- Cycles through available profiles not currently selected by another player
- Default state: no profile bound, shows "P1"-"P4"
- Once a profile is selected, name updates immediately
- START button opens name entry overlay to create a new profile (title screen only)
- Newly created profile auto-selects for that player

### Class (D-pad Left/Right)
- Cycles through available classes not currently selected by another player
- Class change triggers a visual sequence:
  1. Red portal (similar to summoner portal) appears at player position
  2. Player becomes a ghost (semi-transparent, no collision)
  3. Character model swaps with a smoke poof VFX
  4. Player remains a ghost until pressing any non-movement button
  5. Second red portal appears, player becomes fully interactive

### Simultaneous Selection
All players can select profiles and classes simultaneously. No blocking overlays.

## Persistence Across Game Modes

The HUD stays visible in all states: title, overworld, tower, boss.
- Title screen: shows profile/class selection hints
- In-game: shows HP, mana, status effects

## Play Area Buffer

The camera system adds a bottom margin (~80px) so the HUD panel doesn't
overlap the gameplay area. The HUD sits on a CanvasLayer above everything.
A subtle dark backing ensures readability over any background.

## Auto-Join Flow

1. Controller connects -> HUD panel appears showing "P1" (no profile yet)
2. Player presses D-pad up/down -> cycles profiles
3. Player presses D-pad left/right -> cycles classes
4. Player presses START -> create new profile (if needed)
5. Any player presses START (when at least 1 player has a profile) -> start game

## What Gets Removed

- `profile_select_overlay.gd` - replaced by inline D-pad selection
- Old `PlayerSlots` HBoxContainer from `title_screen.tscn`
- Old HUD in `GameManager` (`_create_hud`, `_muffin_label`, etc.)
- Profile/class selection logic in `title_screen.gd` `_input`
