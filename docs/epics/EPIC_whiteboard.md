# EPIC: Debug Digital Whiteboard

## Overview

A collaborative workspace where humans and AIs can diagram, annotate, and communicate visually about game systems. Both parties draw primitives, add annotations, and build up diagrams through either the debug drawer GUI (human) or RCON commands (AI). The whiteboard renders as a world-space overlay via `_draw()`, so it overlays a live game level or a blank canvas.

## Status

| Phase | Status | Description |
|-------|--------|-------------|
| Phase 1 | COMPLETE | Data model, grid, component rendering |
| Phase 2 | COMPLETE | RCON commands — full CRUD for AI interaction |
| Phase 3 | COMPLETE | Debug drawer tab — panel UI with Board/Tools/Settings/Actions/Inspector |
| Phase 4 | COMPLETE | World-space tools — mouse interaction for drawing, selection, editing |
| Phase 5 | IN PROGRESS | Polish — annotations, selection glow, group visuals |

## Architecture

### File Layout

| File | Purpose | Lines |
|------|---------|-------|
| `scripts/ui/whiteboard.gd` | Data model + renderer (Node2D). Grid, components, groups, annotations, serialization, selection, control points | ~900 |
| `scripts/ui/whiteboard_tools.gd` | Tool state machine (RefCounted). Click/drag/release for Select, Line, Poly, etc. Control point dragging | ~530 |
| `scripts/ui/debug_drawer.gd` | WHITEBOARD section (6th tab). Subsections: Board, Tools, Settings, Actions, Inspector | +700 lines added |
| `scripts/autoload/rcon.gd` | `wb` command family — full CRUD for AI interaction, drawer/tool control | +300 lines added |
| `levels/whiteboard.json` | Blank dark level config for pure whiteboard use | ~20 |
| `data/whiteboards/` | Saved whiteboard JSON files | directory |

### Key Decisions

1. **Decoupled from game** — No dependency on monsters, players, chain physics. Works on any level.
2. **Dictionary-based data model** — Matches codebase convention. Components are plain Dictionaries. Clean JSON round-trip.
3. **Overlay, not a scene** — The whiteboard Node2D is added as a child of the current scene (like level_editor's overlay).
4. **Lazy initialization** — Created on first use (first RCON `wb` command or first drawer interaction).
5. **Integer component IDs** — Auto-incremented per whiteboard. RCON uses bare integers.
6. **Autoload name** — RCON autoload is `Rcon` (capital R, lowercase con) — accessed as `/root/Rcon`.
7. **Panel is LEFT-side** — The debug drawer slides out from the LEFT edge. `_panel_x = 0` when open.

## Data Model

### Component (Dictionary)

All components share a common base:

```gdscript
{
  "id": int,              # Auto-incremented
  "type": String,         # point|rect|circle|ellipse|line|polyline|poly|arrow|vector|normal
  "color": String,        # "#rrggbb" or "#rrggbbaa"
  "label": String,        # Optional display label
  "visible": bool,        # true by default
  "selected": bool,       # false by default
  "line_width": float,    # 2.0 default
  "annotations": Array,   # [{"producer": "H"|"A", "text": "..."}]
  "show_annotations": bool, # true by default
}
```

Type-specific fields:

| Type | Extra Fields |
|------|-------------|
| `point` | `x`, `y`, `radius` (display dot size, default 4) |
| `rect` | `x`, `y`, `w`, `h` |
| `circle` | `cx`, `cy`, `r` |
| `ellipse` | `cx`, `cy`, `rx`, `ry` |
| `line` | `x1`, `y1`, `x2`, `y2` |
| `polyline` | `points: [[x,y], ...]` |
| `poly` | `points: [[x,y], ...]` (renders closed) |
| `arrow` | `x1`, `y1`, `x2`, `y2`, `head_size` (12 default) |
| `vector` | `ox`, `oy`, `dx`, `dy` (origin + direction) |
| `normal` | `ref_id`, `t` (0..1 along ref), `length` (30 default), `flipped` (bool) |

### Group (Dictionary)

```gdscript
{"label": String, "ids": Array[int], "color": String}
```

### Whiteboard (Dictionary — serialized to JSON)

```gdscript
{
  "name": String,
  "version": 1,
  "next_id": int,
  "components": Array[Dictionary],
  "groups": Array[Dictionary]
}
```

## Control Points

Every selected component shows draggable control point handles (small squares). Control points per type:

| Type | Control Points |
|------|---------------|
| `point` | `pos` — the point position |
| `line`, `arrow` | `p1`, `p2` — both endpoints |
| `rect` | `tl`, `tr`, `br`, `bl` — four corners (opposite corner stays fixed during drag) |
| `circle` | `center` (blue), `radius` (white, on right edge) |
| `ellipse` | `center` (blue), `rx` (horizontal), `ry` (vertical) |
| `polyline`, `poly` | `p0`, `p1`, `p2`... — each vertex |
| `vector` | `origin` (blue), `tip` — dragging tip changes dx/dy |
| `normal` | `base` (moves t parameter along ref), `tip` (changes length) |

Center/origin handles render in blue (`CP_CENTER_FILL`). Edge/endpoint handles render in white (`CP_FILL`).

CP hit radius: 8px. CP rendering size: 5px squares with black outline + colored fill.

## Tool State Machine

```
enum Tool { SELECT, ANNOTATE, POINT, LINE, POLYLINE, POLY, RECT, CIRCLE, ELLIPSE, ARROW, VECTOR, NORMAL }
```

### Tool Behaviors

| Tool | Click | Drag | Release | Double-Click |
|------|-------|------|---------|-------------|
| SELECT | Hit-test CPs first, then components. Click empty = deselect | CP drag or whole-component move | End drag | — |
| ANNOTATE | Select component, auto-focus annotation field | — | — | — |
| POINT | Create point immediately, auto-select | — | — | — |
| LINE, ARROW | Start two-step draw | Preview ghost | Finalize if dragged > 3px, else keep drawing for 2nd click | — |
| RECT | Start two-step draw | Preview ghost | Finalize if dragged > 3px | — |
| CIRCLE | Start two-step (center→edge) | Preview ghost | Finalize if dragged > 3px | — |
| ELLIPSE | Start two-step (center→corner) | Preview ghost | Finalize if dragged > 3px | — |
| VECTOR | Start two-step (origin→tip) | Preview ghost | Finalize if dragged > 3px | — |
| POLYLINE, POLY | Each click adds a point | Preview from last point to cursor | — | Finalize |

**Dual creation modes**: Two-step tools support BOTH:
- **Drag-release**: click-hold-drag-release creates the shape in one gesture
- **Two-click**: click start, click end (for precision placement)

The `_did_drag` flag distinguishes the two modes. If mouse moves > `MIN_DRAG_DISTANCE` (3px) during the operation, release finalizes. If not, the operation stays open for a second click.

**Auto-selection**: All newly created components are automatically selected, immediately showing their control points.

## RCON Commands

```
# Whiteboard management
wb new [name]                              — Create new whiteboard
wb save [name]                             — Save to data/whiteboards/<name>.json
wb load <name>                             — Load from file
wb files                                   — List saved files
wb clear                                   — Clear all components
wb level                                   — Load blank whiteboard level
wb open                                    — Open drawer on WHITEBOARD tab
wb close                                   — Close drawer
wb tool [name|index]                       — Get/set active tool
wb grid [on|off]                           — Toggle grid
wb dump                                    — Dump entire whiteboard as JSON

# Component creation (returns "OK: id=N")
wb point <x> <y> [color=red] [label=text]
wb line <x1> <y1> <x2> <y2> [color=...] [label=...]
wb rect <x> <y> <w> <h> [color=...] [label=...]
wb circle <cx> <cy> <r> [color=...] [label=...]
wb ellipse <cx> <cy> <rx> <ry> [color=...] [label=...]
wb polyline <x1> <y1> <x2> <y2> ... [color=...] [label=...]
wb poly <x1> <y1> <x2> <y2> ... [color=...] [label=...]
wb arrow <x1> <y1> <x2> <y2> [color=...] [label=...]
wb vector <ox> <oy> <dx> <dy> [color=...] [label=...]
wb normal <ref_id> [t=0.5] [length=30] [flipped=false] [color=...]

# Component modification
wb set <id> <key>=<value> ...              — Set properties
wb move <id> <dx> <dy>                     — Translate
wb delete <id>                             — Remove
wb show <id> / wb hide <id>                — Toggle visibility

# Selection
wb select <id> [id ...]                    — Select component(s)
wb deselect                                — Clear selection
wb selected                                — List selected IDs

# Annotations
wb annotate <id> <H|A> <text...>           — Add annotation line
wb annotations <id>                        — List annotations
wb annotations clear <id>                  — Clear annotations
wb annotations show|hide <id>              — Toggle callout visibility

# Groups
wb group <label> <id> [id ...]             — Create/update group
wb ungroup <label>                         — Remove group
wb groups                                  — List all groups

# Inspection
wb list                                    — List all components (id, type, label)
wb inspect <id>                            — Show full component details as JSON
```

## Debug Drawer Integration

### Section: WHITEBOARD (index 5)

The 6th tab in the debug drawer icon bar. Uses teal-green accent color `Color(0.4, 0.75, 0.6)`.

### Subsections

| ID | Title | Content |
|----|-------|---------|
| `wb_board` | Board | Name text field, **New** / **Save** / **Load** / **Clear** buttons, file picker |
| `wb_tools` | Tools | 2-column grid of 12 tool buttons. Active tool highlighted blue with left accent bar |
| `wb_settings` | Settings | Color swatches (12 colors, 2 rows). Annotation input field (shown when ANNOTATE tool active or SELECT with selection) |
| `wb_actions` | Actions | Context buttons: Delete Selected, Deselect All, Hide Selected, Show All, Grid Toggle |
| `wb_inspector` | Inspector | Selected component properties (id, type, coords, etc). Annotation list with `[H]`/`[A]` tags |

### Settings Pane Behavior

- **Color swatches**: Always shown. When SELECT tool is active with a selection, clicking a swatch changes the selected component's color (in addition to setting the tool color).
- **Annotation input**: Shown when ANNOTATE tool active, or SELECT with a selection. `[H]` producer prefix. Click to focus, type text, Enter to submit, Escape to cancel.

### World-Space Click Routing

When `_current_section == Section.WHITEBOARD` and click is outside the drawer panel:
1. `debug_drawer._input()` detects the world-space click
2. Calls `_wb_get_or_create_tools()` to get/create the tools instance
3. Converts screen pos to world pos via `_wb_get_world_pos()`
4. Routes to `tools.handle_click()`, `handle_drag()`, or `handle_release()`
5. Syncs preview component to whiteboard for ghost rendering
6. Double-click detection for finalizing polyline/poly

### Screen-to-World Conversion

```gdscript
func _wb_get_world_pos(screen_pos: Vector2) -> Vector2:
    var cam := get_viewport().get_camera_2d()
    var vp_size: Vector2 = get_viewport().get_visible_rect().size
    var zoom: Vector2 = cam.zoom if cam.zoom.x > 0 else Vector2.ONE
    return (screen_pos - vp_size / 2.0) / zoom + cam.global_position
```

In the whiteboard level (camera at 960,540, zoom 1.0), world coords = viewport coords.

## Rendering

### Grid

- Minor lines: every 20px, `Color(0.15, 0.15, 0.2, 0.15)`
- Major lines: every 100px, `Color(0.2, 0.25, 0.35, 0.3)`
- Axis lines (x=0, y=0): brighter `Color(0.3, 0.4, 0.55, 0.4)`
- Coordinate labels on major lines, font size 8

### Selection

Selected components get:
- Thicker outline (+2px via `SELECTION_EXTRA_WIDTH`)
- Pulsing glow (sin-based lerp toward white at `SELECTION_PULSE_SPEED = 4.0`)

### Preview/Ghost

In-progress two-step draws show a semi-transparent preview (alpha=0.45) of the component being created.

### Annotations

When `show_annotations` is true and annotations are non-empty:
- Speech-bubble positioned offset from component centroid (`ANNOTATION_OFFSET = Vector2(20, -30)`)
- Each line prefixed with `[H]` (cyan) or `[A]` (orange)
- Dark semi-transparent background, leader line to component

### Control Points

Small squares drawn on top of everything for selected components:
- Black outline (5px), white or blue fill (4px inner)
- Blue for center/origin/pos handles, white for edges/endpoints

## Whiteboard Level

`levels/whiteboard.json` — dark background, camera fixed at (960, 540), floor transparent and off-screen, distant walls.

## Known Issues / TODO

- [ ] GUI automated testing is unreliable with CGEvents on macOS fullscreen — use RCON commands (`wb open`, `wb tool`) for programmatic testing
- [ ] Dynamic dispatch from `_get_whiteboard()` returns `Node2D`, so methods return untyped Arrays — use `var sel: Array = wb.get_selected_ids()` (no type annotation) to avoid runtime errors
- [ ] Subsection resize persistence works via `user://whiteboard_layout.json`
- [ ] Group bounding box rendering is basic (min/max centroid + padding) — could be improved with actual shape bounds
