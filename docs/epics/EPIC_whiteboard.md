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
| Phase 5 | COMPLETE | Polish — annotations, selection glow, group visuals |
| Phase 6 | COMPLETE | Arc, Bezier tools, grid/component snapping, component locking |

## Architecture

### File Layout

| File | Purpose | Lines |
|------|---------|-------|
| `scripts/ui/whiteboard.gd` | Data model + renderer (Node2D). Grid, 12 component types, groups, annotations, serialization, selection, control points, snapping helpers | ~1100 |
| `scripts/ui/whiteboard_tools.gd` | Tool state machine (RefCounted). 14 tools including arc (3-step) and bezier (multi-click). Click/drag/release, CP dragging, snapping, lock guards | ~750 |
| `scripts/ui/debug_drawer.gd` | WHITEBOARD section (6th tab). Subsections: Board, Tools, Settings, Actions, Inspector. Snap/lock UI | +800 lines added |
| `scripts/autoload/rcon.gd` | `wb` command family — full CRUD, arc/bezier creation, snap/lock commands, drawer/tool control | +400 lines added |
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
  "type": String,         # point|rect|circle|ellipse|line|polyline|poly|arrow|vector|normal|arc|bezier
  "color": String,        # "#rrggbb" or "#rrggbbaa"
  "label": String,        # Optional display label
  "visible": bool,        # true by default
  "selected": bool,       # false by default
  "locked": bool,         # false by default — blocks modification/CP rendering when true
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
| `arc` | `cx`, `cy`, `r`, `start_angle` (radians), `sweep_angle` (radians) |
| `bezier` | `points: [[x,y], ...]` (N anchors), `controls: [[x,y], ...]` (2*(N-1) control handles) |

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
| `arc` | `center` (blue, rehomes entire arc), `start` (changes r and start_angle), `end` (changes sweep_angle) |
| `bezier` | `a0`, `a1`... (blue, anchor points — move with handles), `c0`, `c1`... (white, control handles) |

Center/origin handles render in blue (`CP_CENTER_FILL`). Edge/endpoint handles render in white (`CP_FILL`).

CP hit radius: 8px. CP rendering size: 5px squares with black outline + colored fill.

## Tool State Machine

```
enum Tool { SELECT, ANNOTATE, POINT, LINE, POLYLINE, POLY, RECT, CIRCLE, ELLIPSE, ARROW, VECTOR, NORMAL, ARC, BEZIER }
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
| ARC | **Three-step**: 1) Click sets center, 2) Drag-release sets radius + start angle, 3) Click finalizes sweep angle | Step 1→2: preview circle from center. Step 2→3: preview arc sweeping from start to cursor | Step 1→2: if dragged > 3px, set radius and start from drag vector | — |
| BEZIER | Each click adds an anchor point (like POLYLINE) | — | — | Finalize — auto-generates smooth control handles via Catmull-Rom tangents |

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
wb arc <cx> <cy> <r> <start_deg> <sweep_deg> [color=...] [label=...]
wb bezier <x1> <y1> <x2> <y2> ... [color=...] [label=...]

# Locking
wb lock <id> [id ...]                     — Lock components (blocks modification/CPs)
wb unlock <id> [id ...]                   — Unlock components

# Snapping
wb snap [grid|comp] [on|off]              — Toggle grid/component snapping

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
| `wb_tools` | Tools | 2-column grid of 14 tool buttons (Select, Annotate, Point, Line, PolyLine, Poly, Rect, Circle, Ellipse, Arrow, Vector, Normal, Arc, Bezier). Active tool highlighted blue with left accent bar |
| `wb_settings` | Settings | Color swatches (12 colors, 2 rows). Annotation input field (shown when ANNOTATE tool active or SELECT with selection) |
| `wb_actions` | Actions | Context buttons: Delete Selected, Deselect All, Hide Selected, Show All, Grid Toggle, **Lock / Unlock** (when selected), **Snap Grid** toggle, **Snap Components** toggle |
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

## Snapping

Two independent snap modes, togglable via Actions subsection buttons or RCON (`wb snap`):

| Mode | Behavior |
|------|----------|
| **Snap Grid** | Rounds coordinates to nearest minor grid point (20px) |
| **Snap Components** | Snaps to the nearest control point of any visible component within 12px |

Snapping is applied in `whiteboard_tools._snap()` before any tool processing. Both modes can be active simultaneously — grid snap applies first, then component snap overrides if a CP is within range.

The **SELECT tool bypasses snapping** for hit testing — click positions are used raw so you can select components at any position. Snapping only applies when creating or drawing components.

State is stored in `whiteboard_tools.snap_grid` and `whiteboard_tools.snap_components`, synced from the debug drawer toggles.

## Component Locking

Any component can be locked (`locked: true`) to prevent accidental modification. Locked components:

- **Cannot be modified** — `set_component_property()` rejects edits (except `locked`, `selected`, `visible`)
- **Cannot be moved** — `move_component()` returns false
- **Do not render control points** — even when selected
- **Can be selected** — for inspection purposes (view properties in Inspector)
- **Cannot be dragged** — SELECT tool allows click-to-select but blocks drag-to-move

Lock/unlock via:
- **Actions subsection**: Lock / Unlock buttons appear when a component is selected
- **RCON**: `wb lock <id> [id ...]` / `wb unlock <id> [id ...]`
- **Property**: `wb set <id> locked=true`

## Arc Tool (Three-Step)

The Arc tool uses a three-step creation workflow:

1. **Click** → set center (P1). `_arc_step = 1`
2. **Hold/Drag** → preview circle from center. **Release** → set P2, compute R (radius) and start_angle from drag vector. `_arc_step = 2`
   - Alternative: click again to set P2 by click (no drag)
3. **Move** → preview arc sweeping from P2 to cursor angle. **Click** → finalize sweep_angle

The sweep angle uses `_shortest_angle_dist()` (`fmod(to - from + PI, TAU) - PI`) to always take the minimum arc-distance path. This limits single arcs to ≤180° on creation. For larger arcs, create the arc and then drag the end control point past 180°.

**Post-creation control points:**
- **center** (blue) — rehomes entire arc
- **start** — changes R and start_angle simultaneously
- **end** — changes sweep_angle

**RCON creation:** `wb arc <cx> <cy> <r> <start_deg> <sweep_deg>` — angles in degrees, converted to radians internally.

## Bezier Tool (Multi-Click)

Uses the same multi-click pattern as Polyline:
1. Each click adds an anchor point
2. Double-click finalizes
3. Control handles are auto-generated using Catmull-Rom-style smooth tangents (`_auto_bezier_controls()`)

**Data model:** N anchor `points` + 2×(N-1) `controls`. For each segment between anchors[i] and anchors[i+1]:
- `controls[2*i]` = handle out from anchor i
- `controls[2*i+1]` = handle in to anchor i+1

**Rendering:** Each segment is sampled as a cubic bezier at 32 points. When selected, thin dimmed lines show anchor-to-handle connections.

**Control point dragging:**
- Dragging an **anchor** also moves its associated control handles (preserving relative offset)
- Dragging a **control handle** moves only that handle

**RCON creation:** `wb bezier <x1> <y1> <x2> <y2> ...` — provide anchor coordinates (minimum 2 points), controls are auto-generated.

## Known Issues / TODO

- [ ] GUI automated testing is unreliable with CGEvents on macOS fullscreen — use RCON commands (`wb open`, `wb tool`) for programmatic testing
- [ ] Dynamic dispatch from `_get_whiteboard()` returns `Node2D`, so methods return untyped Arrays — use `var sel: Array = wb.get_selected_ids()` (no type annotation) to avoid runtime errors
- [ ] Subsection resize persistence works via `user://whiteboard_layout.json`
- [ ] Group bounding box rendering is basic (min/max centroid + padding) — could be improved with actual shape bounds

## See Also

- **`docs/design/whiteboard_implementation.md`** — Technical implementation notes: file-by-file guide, critical gotchas (autoload naming, Retina coordinates, dynamic dispatch), arc/bezier/snap/lock detailed internals, testing strategy, extension guide
