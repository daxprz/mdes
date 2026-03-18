# Level Editor System

## Overview

A built-in level editor that allows configuring level aspects through
JSON files. Each level has a configuration file that defines spawn areas,
seeds, platforms, and other configurable elements.

## File Structure

### Default Configuration
- Stored in the application bundle: `res://levels/{level_name}.json`
- Read-only, ships with the game
- Used as fallback when override is missing or corrupt

### Override Configuration
- Stored in user data: `user://levels/{level_name}.json`
- Same directory as player profiles
- Created/modified by the level editor
- Takes priority over bundled version when valid

### Fallback Behavior
At load time:
1. Try to load `user://levels/{level_name}.json`
2. Validate JSON structure and required fields
3. If corrupt, incorrect, or missing → use `res://levels/{level_name}.json`
4. Log a warning if override was invalid

## JSON Schema

```json
{
  "version": 1,
  "level_name": "title_screen",

  "spawn_zones": {
    "fireflies": [
      {"rect": [50, 50, 1820, 490], "weight": 8.0},
      {"rect": [752, 760, 143, 140], "weight": 1.5}
    ],
    "bats": [
      {"rect": [100, 350, 1720, 500], "max_count": 5}
    ],
    "enemies": [
      {"rect": [200, 400, 1520, 400], "types": ["skeleton", "candy_corn"], "max_count": 8}
    ]
  },

  "platforms": [
    {"pos": [540, 760], "width": 422, "type": "static"},
    {"pos": [1380, 760], "width": 422, "type": "static"},
    {"pos": [670, 540], "width": 288, "type": "static"}
  ],

  "scenery": {
    "trees": [
      {"pos": [250, 900], "seed": 3105534387, "trunk_weight": 22, "trunk_length": 250},
      {"pos": [1670, 900], "seed": 4178534353, "trunk_weight": 20, "trunk_length": 230}
    ],
    "rocks": [
      {"pos": [400, 885], "size": 45, "seed": 1001, "hue": "grey"},
      {"pos": [1520, 882], "size": 55, "seed": 1004, "hue": "red"}
    ]
  },

  "portal": {
    "pos": [960, 880],
    "activation_range": 100,
    "all_present_time": 5.0
  },

  "camera": {
    "fixed": true,
    "position": [960, 495]
  }
}
```

## Editor Modes

### Mode 1: Edit Spawn Areas
- Spawn zone rectangles displayed as colored translucent overlays
- Vertices (corners) shown as draggable handles
- Click and drag corners to resize zones
- Right-click to add new zone, delete key to remove
- Zone type and weight editable via side panel

### Mode 2: Edit Seeds
- Procedural items (trees, rocks) shown with their seed number
- Click on an item to select it
- Press G to regenerate with random seed (existing feature)
- Seed number displayed above each item
- Position draggable

### Mode 3: Edit Platforms
- Platform positions and widths shown
- Drag platform center to move
- Drag edges to resize width
- Click empty space to add new platform

### Mode 4: Edit Portal
- Portal position draggable
- Activation range shown as circle overlay
- Timer value editable

## Editor UI

- **Toggle:** Press a key combo (e.g., Ctrl+E) to enter editor mode
- **Mode selector:** Tab bar at the top showing current mode
- **Properties panel:** Right side panel showing selected item's properties
- **Save button:** Saves current state to `user://levels/{level_name}.json`
- **Reset button:** Reverts to bundled default
- **Grid snap:** Optional snap-to-grid for alignment

## Mouse Interaction

All modes share common mouse controls:
- **Left click:** Select item / start drag
- **Left drag:** Move selected item or vertex
- **Right click:** Context menu (add, delete, duplicate)
- **Scroll wheel:** Zoom (if applicable)
- **Escape:** Deselect / exit editor

## Integration

- Level scripts call `LevelConfig.load_level(level_name)` at `_ready()`
- Returns a Dictionary with the parsed JSON data
- Level scripts use the data to configure spawn zones, platforms, etc.
- Editor modifies the same data structure and saves back to JSON
