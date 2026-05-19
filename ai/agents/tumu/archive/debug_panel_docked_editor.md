# Docked Test Editor & Collapsible Sub-Sections

**Priority:** High — UI infrastructure for all future test work
**Depends on:** v0.10.17 (multi-section panel framework)
**Full spec:** `docs/design/debug_panel_spec.md`
**Status:** IN PROGRESS — Phase 1 complete (sub-sections + docking)

## Summary
Replace the floating test editor/runner with a docked version inside the debug panel. Add a collapsible sub-section framework that all sections can use.

## Completed

### 1. Sub-section framework
- Collapsible panels with header bar (collapse icon, title, drag handle)
- Drag bottom edge to resize each section
- Save/load layout to `user://debug_panel_layout.json`
- Regenerate defaults if file missing/corrupt

### 2. Test Runner sub-sections
- **Suites**: List with play icons, click to run
- **Tests**: Scrollable list, click to load into editor, highlights loaded test
- **Controls**: Test name/mode header + context-sensitive button bar
- **Status**: Run status, result summary, per-check detail log
- **Editor**: Script lines with line numbers, status indicators, inline edit field

### 3. Docking integration
- test_editor.gd gains `_docked` flag — suppresses floating window when docked
- World-space overlay (handles, zones, breach markers) still renders
- Debug drawer auto-docks when switching to test runner section
- RCON `run`/`suite` commands dock to debug drawer when it's open
- Closing debug drawer undocks the editor back to floating mode

## Remaining

### 4. Dynamic line insertion
- Hover between lines shows green arrows with white "+"
- Arrows at fixed positions, fade with cursor distance
- White border on direct hover
- Click inserts blank line, shifts others down

### 5. Polish
- Test the full flow: load test -> edit -> run -> see results -> navigate suites
- Verify handle dragging works correctly in docked mode
- Verify picker (T key) works in docked mode
- Scrollbar rendering in editor sub-section
- Row drag-drop reordering in docked mode
