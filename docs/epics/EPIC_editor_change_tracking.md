# EPIC: Editor Change Tracking & Save Workflow

## Overview

Track unsaved changes per-component in the level editor. Show visual indicators on changed items, a summary bar of pending changes, and support Original/Custom save workflow for levels (same as splay pose editor).

## Stories

### STORY 1: Change Tracking Infrastructure

- [x] **1.1** Add `_changed: Dictionary` to level editor — tracks which components have changed since last save. Keys: "splays", "migrations", "spawn_areas", "spawn_positions", "seeds", "platforms", "portal", "cave_walls"
- [x] **1.2** Each edit operation sets `_changed[component] = true`
- [x] **1.3** On save (Original or Custom), clear all `_changed` flags
- [x] **1.4** Track per-item change state: `_changed_items: Dictionary` — e.g., `{ "splays": [0, 2], "platforms": [1] }` (indices of changed items)

### STORY 2: Visual Indicators on Changed Items

- [x] **2.1** In each editor mode's overlay, items with changes drawn with a small yellow dot or asterisk
- [x] **2.2** Applies to all modes: splays, platforms, spawn zones, etc.

### STORY 3: Change Summary Bar

- [x] **3.1** Render a summary line on screen: "2 Splays changed, 1 Migration changed" (only non-zero)
- [x] **3.2** Position: bottom-right or top-right of editor panel
- [x] **3.3** Color: yellow for pending changes, green when clean

### STORY 4: Custom vs Original Indicator

- [x] **4.1** Detect if current level has a custom override (user:// file exists for this level)
- [x] **4.2** If custom exists and has unsaved changes: show "(CUSTOM - N unsaved changes)" — SOURCE only
- [x] **4.3** If clean: show "(CUSTOM - saved)" or "(ORIGINAL)"

### STORY 5: Level Save Original/Custom

- [x] **5.1** Same O/C dialog mechanism as splay pose editor
- [x] **5.2** Ctrl+S in non-SPLAY_EDIT modes shows O/C dialog (SOURCE only shows O)
- [x] **5.3** Original: saves to `res://levels/{name}.json`
- [x] **5.4** Custom: saves to `user://levels/{name}.json` (existing behavior)
- [x] **5.5** When Custom is saved to Original: delete the custom file (they're now identical)
