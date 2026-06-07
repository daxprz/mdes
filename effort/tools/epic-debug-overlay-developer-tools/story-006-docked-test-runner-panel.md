---
xid: STO-TOOLS-006
parent: ./epic.md
kind: story
effort: tools
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-yb1j
shipped: 2026-06-07
tasks: 7
complete: 4
---

# Docked Test Runner Panel

## Summary

Five collapsible resizable sub-sections (Suites, Tests, Controls, Status, Editor) docked in the debug panel with layout persistence.

## Context

_(Why is this story needed? What does it depend on? Link to the parent
epic. If this is a discovered-from another story, surface the link.)_

## Problem

_(What specific problem does this story solve? Concrete; the reader
should be able to verify completion without re-reading the epic.)_

## Design

### Approach

_(How will this be implemented? Reference HUGs that constrain the
implementation choice; cite alternatives only when they shaped the
final pick.)_

### Changes

| File | Change |
|------|--------|
| `path/to/file` | _(add / modify / extract)_ |
| `path/to/test` | _(add tests for the new behavior)_ |

## Definition of Done

- [x] Sub-section framework with 5 resizable panels
- [x] Layout persisted to user://debug_panel_layout.json
- [x] Test editor docked; floating window suppressed
- [x] RCON run/suite auto-dock when drawer open


## Testing

### Unit / fixture tests

- [ ] _(Specific case.)_
- [ ] _(Edge case.)_

### Integration

- [ ] _(Scenario.)_

## Out of scope

- _(Things deliberately deferred to a later story. Be explicit — the
  reader should know what's *not* changing.)_

## Implementation Notes

_(Fill in during / after implementation. Capture what diverged from
the original design and why — useful for the retrospective + for
operators reading this story in a year.)_

### What Changed

_(Actual implementation. May differ from § Design above.)_

### Files Modified

- `path/to/file` — _(what changed)_

### Gotchas

_(Anything surprising or worth noting for future readers.)_


## TUMU Provenance

- **Source:** docs/epics/EPIC_debug_overlay.md Story 6; docs/design/debug_panel_spec.md
- **Shipped in:** 0.10.21
- **History:** Five collapsible resizable sub-sections (Suites, Tests, Controls, Status, Editor) docked in the debug panel with layout persistence.

## Status notes

- 2026-06-07: Closed with --force; 3/7 DoD boxes unchecked. Reason: historical: shipped in TUMU 0.10.21
