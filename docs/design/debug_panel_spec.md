# Debug Panel — Multi-Section Dockable UI Spec

## Architecture

The debug drawer becomes a multi-section dockable panel with an icon bar.

### Icon Bar (left strip, ~36px)
- **Magnifying Glass** — Debug aspect tree (existing)
- **Play/Bug** — Test Runner (NEW docked version)
- **Gear** — Config sliders (existing)

### Sub-Section Framework

Each section contains collapsible sub-sections. Sub-sections are:
- **Collapsible** — show/hide each section
- **Resizable** — drag the top edge of each section to allocate fixed height
- **Configurable** — layout saved/loaded from file, regenerate defaults on failure
- **Scrollable** — sub-body area scrolls independently

### Sub-Section Layout

```
+---------------------------------------------------+
| [v] Title                            [drag handle] |  ← Control header (always visible)
+---------------------------------------------------+
| Sub-header (fixed size)                            |
+---------------------------------------------------+
| Sub-body (flexible size, scrollable)               |
|                                                    |
|                                                    |
+---------------------------------------------------+
| Sub-footer (fixed size)                            |
+---------------------------------------------------+
```

**Control header** (left to right):
- LEFT: Collapse/expand icon (triangle)
- LEFT: Section title
- CENTER: (reserved for future)
- RIGHT: (reserved for future)
- RIGHT: Drag indicator (grip dots)

## Test Runner Section

### Sub-section 1: Suites
- List of all suite JSON files with play icons
- Click to run a suite
- Shows last result (pass/fail count) next to each

### Sub-section 2: Tests
- Scrollable list of all test JSON files
- Click to run a test
- Hover highlights

### Sub-section 3: Test Controls (DOCKED)
Replaces the floating test editor controls:
- **Header**: The existing test name / status header
- **Footer**: The existing control buttons (Run, Stop, etc.)

### Sub-section 4: Test Status (DOCKED)
Replaces the floating test output:
- **Body**: Test output / status / results area (scrollable)

### Sub-section 5: Test Editor (DOCKED)
Replaces the floating script editor:
- **Body**: Script lines with line numbers
- **Footer**: Editor input area (fixed size, top edge draggable to resize)
- **Dynamic insertion controls**:
  - Hovering over a line shows green arrows with white "+" BETWEEN lines (left and right sides)
  - Arrows are at fixed positions but fade with distance from cursor
  - Hovering directly over an arrow gives it a white border highlight
  - Clicking an arrow inserts a new blank line, existing lines shift down

### Removal
The existing floating test editor/runner overlay is removed in favor of the docked version.

## Viewport Scaling
When the drawer opens, the game viewport scales and shifts to fit the remaining visible area (already implemented via canvas_transform).

## Config Persistence
Sub-section heights and collapsed states are saved to `user://debug_panel_layout.json`.
Load on startup, regenerate defaults if file is missing or corrupt.
