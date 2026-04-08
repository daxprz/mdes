# Whiteboard Implementation Notes

Technical details for maintaining and extending the whiteboard system. Read `docs/epics/EPIC_whiteboard.md` first for the high-level architecture.

## Critical Gotchas

### 1. Autoload Naming: `Rcon` not `RCON`

The RCON autoload in `project.godot` is named `Rcon` (capital R, lowercase con):
```
Rcon="*res://scripts/autoload/rcon.gd"
```

All `get_node_or_null()` calls MUST use `/root/Rcon`. Using `/root/RCON` will silently return null, causing all whiteboard features to fail with no error message.

### 2. Dynamic Dispatch Loses Array Types

`_get_whiteboard()` in debug_drawer.gd returns `Node2D` (not the typed script class). When calling methods on this dynamically-dispatched reference, return types lose their generics:

```gdscript
# WRONG — runtime error: can't assign Array to Array[int]
var sel_ids: Array[int] = wb.get_selected_ids()

# CORRECT — use untyped Array
var sel_ids: Array = wb.get_selected_ids()
```

This applies to ALL method calls through `_get_whiteboard()`:
- `get_selected_ids()` returns `Array` (not `Array[int]`)
- `get_all_components()` returns `Array` (not `Array[Dictionary]`)
- `get_wb_groups()` returns `Array` (not `Array[Dictionary]`)

### 3. Screen Coordinate Mapping (Retina)

On the development machine (macOS Retina, 3840x2160 display):
- **Godot viewport**: 1920x1080
- **Screen points**: 3840x2160
- **Mapping**: `screen_point = godot_pixel * 2` (NO title bar offset — fullscreen borderless)
- `event.position` in Godot is in viewport pixels (1920x1080)

The whiteboard level has camera fixed at (960, 540) with zoom (1, 1), so **world coordinates = viewport coordinates**.

### 4. Panel is LEFT-Side

The debug drawer panel slides out from the LEFT edge of the screen:
- Open: `_panel_x = 0`, extends to `_panel_width` (default 396)
- Closed: `_panel_x = -_panel_width`
- Icon bar: x = 0..36 (`ICON_BAR_WIDTH = 36`)
- Content area: x = 40..`_panel_width`

"Click outside panel" means `event.position.x > _panel_width` (when open).

### 5. Tools Instance Lifecycle

`_wb_tools_instance` (RefCounted, `whiteboard_tools.gd`) is lazily created by `_wb_get_or_create_tools()`. Creation requires:
1. `_get_whiteboard()` returns non-null (whiteboard exists in scene)
2. The whiteboard node must be created by RCON's `_get_or_create_whiteboard()`

The tools instance is NOT created until:
- A tool button is clicked in the drawer panel, OR
- A world-space click is routed while on the WHITEBOARD tab

If the whiteboard hasn't been created yet (no `wb` command issued), `_wb_get_or_create_tools()` returns null and world clicks are silently ignored.

### 6. Subsection Layout Framework

The WHITEBOARD tab uses the same subsection framework as other tabs:
- `_wb_subsections: Array[Dictionary]` — `{id, title, collapsed, height}`
- Unified header rendering via `_draw_sub_header()` (teal-green accent)
- Grip dots for resize, double-click to snap to preferred height
- Layout persisted to `user://whiteboard_layout.json`
- Last subsection (Inspector) fills remaining space

## File-by-File Guide

### whiteboard.gd (~900 lines)

**Extends**: `Node2D` (renders in world space via `_draw()`)

**Sections**:
1. Constants (grid, colors, annotation, selection, control points)
2. State (`_components`, `_groups`, `_next_id`, `_grid_visible`, `_preview_component`)
3. Named color lookup (16 colors for RCON-friendly names)
4. Public API — Component Creation (`add_point`, `add_line`, etc.)
5. Public API — Component Access & Modification (`get_component`, `set_component_property`, `move_component`, `delete_component`, selection)
6. Public API — Annotations (`annotate`, `get_annotations`, `clear_annotations`)
7. Public API — Control Points (`get_control_points(c)` — returns `[{pos, key}, ...]`)
8. Public API — Groups
9. Public API — Management (`clear_all`, name, grid)
10. Serialization (`to_dict`, `from_dict`, `save_to_file`, `load_from_file`)
11. Drawing (`_draw`, `_draw_grid`, `_draw_component`, `_draw_control_points`, `_draw_group`, `_draw_annotations`)
12. Helpers (`_make_base`, `_resolve_color`, `_parse_color`, `_get_centroid`, `_get_normal_endpoints`, `_sample_polyline`)

**Key method**: `_get_normal_endpoints(c)` — computes `[base_pos, tip_pos]` for a normal component. Used by `get_control_points()`, `_draw_normal()`, and control point dragging. Extracted from the old inline `_draw_normal` to avoid code duplication.

### whiteboard_tools.gd (~530 lines)

**Extends**: `RefCounted` (owned by debug_drawer, not in scene tree)

**Sections**:
1. Tool enum and state variables
2. Input handlers (`handle_click`, `handle_drag`, `handle_release`, `handle_double_click`, `cancel`)
3. Tool-specific click handlers
4. Control point hit testing & dragging (`_cp_hit_test`, `_apply_cp_drag`, `_apply_rect_cp`)
5. Preview/ghost rendering (`_update_preview`)
6. Hit testing geometry (`_hit_test`, `_distance_to_component`, `_distance_to_segment`, etc.)
7. Nearest-point-on-component for normal placement

**Key state**:
- `_drawing: bool` — true during two-step/multi-step operations
- `_did_drag: bool` — true if mouse moved > 3px during a draw (enables drag-release finalization)
- `_cp_dragging: bool` + `_cp_comp_id` + `_cp_key` — active control point drag
- `_drag_selected: bool` + `_drag_id` — whole-component move via SELECT tool

### debug_drawer.gd (whiteboard additions, ~700 lines)

**State variables** (lines ~63-87):
- `_wb_subsections`, `_wb_subsections_initialized` — subsection layout
- `_wb_active_tool: int` — index into `WB_TOOLS`
- `_wb_tool_color: String` — active color name
- `_wb_name_focused/text` — board name editing
- `_wb_annotate_focused/text` — annotation input
- `_wb_tools_instance: RefCounted` — the WhiteboardTools instance
- `_wb_world_dragging: bool` — true during world-space drag
- `_wb_last_click_time/pos` — double-click detection

**Constants** (lines ~89-123):
- `WB_SUB_MIN` — minimum heights per subsection
- `WB_TOOLS: Array[Dictionary]` — 12 tools with name and icon
- `WB_COLOR_SWATCHES: Array[Dictionary]` — 12 color swatches

**Key functions**:
- `_wb_get_or_create_tools()` — lazy tool instance creation
- `_wb_get_world_pos(screen_pos)` — viewport-to-world conversion
- `_draw_whiteboard_section()` — main section drawing entry point
- `_handle_wb_click()` — panel click routing
- `_handle_wb_tool_settings_click()` — tool/swatch clicks (works WITHOUT whiteboard)
- `_handle_wb_text_input()` — name and annotation text entry
- `_handle_wb_hover()` — tool hover highlighting

**Input routing** (in `_input()`, ~lines 917-950):
1. Click outside panel + section is WHITEBOARD → route to tools
2. Mouse drag + `_wb_world_dragging` → route to tools.handle_drag
3. Mouse release + `_wb_world_dragging` → route to tools.handle_release
4. Escape key + tools.is_drawing() → cancel in-progress draw

### rcon.gd (whiteboard commands, `_cmd_wb`)

Entry point: `_cmd_wb(parts)` at ~line 5051.

Notable sub-commands:
- `wb open` / `wb close` — toggles drawer, sets section to WHITEBOARD
- `wb tool [name|index]` — gets/sets active drawing tool
- `wb level` — loads blank level, hides baked platforms, attaches whiteboard node

## Testing Strategy

### RCON-Driven Testing (Reliable)

All whiteboard features are testable via RCON without GUI interaction:

```bash
# Setup
echo "wb level" | nc -w2 localhost 9999
echo "wb open" | nc -w2 localhost 9999
echo "wb tool select" | nc -w2 localhost 9999

# Create components
echo "wb circle 960 540 100 color=red" | nc -w2 localhost 9999

# Verify
echo "wb list" | nc -w2 localhost 9999
echo "wb inspect 1" | nc -w2 localhost 9999
echo "wb selected" | nc -w2 localhost 9999

# Selection & annotations
echo "wb select 1" | nc -w2 localhost 9999
echo "wb annotate 1 H Note text" | nc -w2 localhost 9999
echo "wb annotations 1" | nc -w2 localhost 9999
```

### GUI Testing (Unreliable via automation)

CGEvents on macOS fullscreen are unreliable for automated clicking. Issues:
- Window focus can be lost between Python and Godot processes
- Keyboard events (Ctrl+D) don't reliably reach Godot
- Title bar offset varies by window mode

**Workaround**: Use `wb open` and `wb tool` RCON commands to set drawer state, then use CGEvents only for world-space clicks with the correct mapping:
```python
# Fullscreen, NO title bar offset
screen_x = godot_x * 2
screen_y = godot_y * 2
```

### Visual Verification

Take screenshots after RCON operations and inspect them:
```bash
screencapture -x /tmp/wb_test.png
```

## Extension Guide

### Adding a New Component Type

1. Add type-specific fields to the data model (in EPIC doc)
2. Add `add_<type>()` to `whiteboard.gd` (follow existing pattern with `_make_base`)
3. Add rendering in `_draw_component()` match statement
4. Add hit testing in `whiteboard_tools.gd:_distance_to_component()`
5. Add control points in `whiteboard.gd:get_control_points()`
6. Add CP drag handling in `whiteboard_tools.gd:_apply_cp_drag()`
7. Add RCON command in `rcon.gd:_cmd_wb()`
8. Add preview rendering in `whiteboard_tools.gd:_update_preview()`

### Adding a New Tool

1. Add to `Tool` enum in `whiteboard_tools.gd`
2. Add to `WB_TOOLS` const in `debug_drawer.gd`
3. Add click/drag/release handling in `whiteboard_tools.gd`
4. Add RCON `wb tool <name>` support (automatic if added to WB_TOOLS)
