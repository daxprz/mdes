# Docked Test Editor & Collapsible Sub-Sections

**Priority:** High — UI infrastructure for all future test work
**Depends on:** v0.10.17 (multi-section panel framework)
**Full spec:** `docs/design/debug_panel_spec.md`

## Summary
Replace the floating test editor/runner with a docked version inside the debug panel. Add a collapsible sub-section framework that all sections can use.

## Tasks

### 1. Sub-section framework
- Collapsible panels with header bar (collapse icon, title, drag handle)
- Drag top edge to resize each section
- Save/load layout to `user://debug_panel_layout.json`
- Regenerate defaults if file missing/corrupt

### 2. Test Runner sub-sections
- **Suites**: List with play icons, click to run, shows last result
- **Tests**: Scrollable list, click to run
- **Test Controls**: Docked header + control buttons (Run/Stop)
- **Test Status**: Docked output/results area (scrollable)
- **Test Editor**: Docked script editor with line numbers

### 3. Dynamic line insertion
- Hover between lines shows green arrows with white "+"
- Arrows at fixed positions, fade with cursor distance
- White border on direct hover
- Click inserts blank line, shifts others down

### 4. Remove floating editor
- Remove the old floating test_editor.gd overlay
- All test editing/running goes through the docked panel
