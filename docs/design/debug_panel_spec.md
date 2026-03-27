# Debug Panel — Multi-Section Dockable UI Spec

**Status: IMPLEMENTED (v0.10.18-v0.10.23)**

## Architecture

The debug drawer is a multi-section dockable panel with an icon bar. It is always the primary interface for test editing — there is no floating editor.

### Icon Bar (left strip, ~36px)
- **Magnifying Glass** — Debug aspect tree
- **Play/Bug** — Test Runner (docked)
- **Gear** — Entity config panel

### Three Panels

#### Debug Panel (Magnifying Glass)
- Aspect filter search box
- Entity filter (type checkboxes, ID wildcard)
- Global on/off toggle
- Scale slider for selected monster
- 2-level collapsible aspect tree with V/T columns

#### Test Runner Panel (Play/Bug)
Five collapsible, resizable sub-sections:

| Section | Content | Header Context |
|---------|---------|----------------|
| **Suites** | Selectable list with pass/fail dots, scores, play buttons | — |
| **Tests** | Filtered by suite, numbered, pass/fail, play/pause buttons | Selected suite name |
| **Controls** | Button bar (Play, Stop, Restart, +dis, +fence, etc.) | Test name + EDIT/EXEC/INSPECT |
| **Status** | Run status, summary, per-check detail (all or selected row) | Test name |
| **Editor** | Script with line numbers, soft-wrap, inline edit, insertion/deletion | Test name + save (💾) + approve-all (✕) |

#### Config Panel (Gear)
- Search filter for config keys
- Entity list (all types, click to select)
- Type-adaptive config: monsters get `cfg()` sliders, others show properties

## Sub-Section Framework

### Layout
```
+---------------------------------------------------+
| [v] Title     [context]        [mode]  [grip :::] |  ← Header bar (always visible)
+---------------------------------------------------+
| Body (variable height, scrollable)                 |
+---------------------------------------------------+
```

### Resizing
- **Grip dots**: Resize the section ABOVE; Editor absorbs the change
- **Min heights**: Each section has a minimum
- **Snap points**: Content-based preferred height. Cyan dashed line visible during drag. Snaps on release within 12px.
- **Double-click grip**: Jumps to preferred height
- **Auto-snap on load**: All sections snap to content-based heights after layout loads
- **Editor fills remaining space**: Always extends to panel bottom

### Persistence
Layout saved to `user://debug_panel_layout.json` (collapsed states + heights).

## Editor Modes

### EDIT (green)
- Click rows to select, inline edit field with cursor
- Line insertion: green triangle + "+" on left between rows
- Pending deletion: ✕ → red strikeout → ↶ undo / bold ✕ confirm
- Comment toggle: # button on hover
- Save: 💾 in header when modified from disk

### EXECUTE (orange)
- Read-only during test execution
- Running line highlighted
- No edit field, no insertion, no deletion

### INSPECT (blue)
- Click rows to view check detail in Status pane
- Comment and delete buttons still available
- Auto-entered after results arrive or cached results load

## Script Editor Features

### Soft-Wrap
Long lines wrap at natural sub-command boundaries. Priority order:
1. Boundary commands (`unless`, `check`) — earliest match per line
2. Label/extract (`label:`, `extract:`) — latest match
3. Comparisons (`>`, `<`, `=`) — latest match
4. Any space — fallback
5. Hard character wrap — last resort

Continuation lines indented 8px with ↵ indicator.

### Inline Edit Field
Auto-sizes to fit soft-wrapped content. Same wrap algorithm as script rows.

### Save/Diff Detection
- Disk hash stored on load
- Yellow ● + 💾 when content differs from on-disk source file
- Save writes to `res://data/tests/<name>.json` (git-tracked)

## Test Result Caching

### Script Hash
- `_compute_script_hash(script)` — deterministic content hash
- Stored in `results.json` when a test runs
- On load, compared against current script content
- If match, results auto-load (pass/fail, detail, summary)

### Cross-Version Persistence
- `/ship-it` copies latest results forward to new version directory
- Hash validation ensures copied results are still valid

### Startup Scan
- On first open, ALL tests scanned for cached results
- Pass/fail dots pre-populated
- Suite scores aggregated from constituent tests
- Individual test results auto-recompute suite scores

## Entity Selection

### Generic Overlay
- World-space `Node2D` draws for ANY entity type
- Pulsing cyan circle + 1-indexed number
- Floating info box with line pointing to entity
- Shows: type, ID, position, HP, state, velocity, scale, chain status

### Config Panel Entity List
- All entities (enemies + players + dummies)
- Click to select, auto-enables state_info aspects
- Entity type detected from script path

## Viewport Behavior
- Panel background fully opaque (game viewport scales to the right via canvas_transform)
- Game renders at full resolution underneath but is shifted/scaled to fit remaining area
