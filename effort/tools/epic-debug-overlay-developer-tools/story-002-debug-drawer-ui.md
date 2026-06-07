---
xid: STO-TOOLS-002
parent: ./epic.md
kind: story
effort: tools
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-s6fa
shipped: 2026-06-07
tasks: 10
complete: 7
---

# Debug Drawer UI

## Summary

Slide-out left-edge panel with aspect search, entity filter, global toggle, and a collapsible V/T aspect tree. Persisted to user:// on Ctrl+S.

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

- [x] Slide-out panel from left edge (Ctrl+D toggle)
- [x] Aspect filter search box
- [x] Entity filter section (type checkboxes, ID wildcard)
- [x] Global on/off checkbox
- [x] 2-level collapsible tree with V/T columns
- [x] Group header toggles
- [x] Ctrl+S save, auto-load on startup


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

- **Source:** docs/epics/EPIC_debug_overlay.md Story 2; docs/design/debug_panel_spec.md
- **Shipped in:** 0.10.26
- **History:** Slide-out left-edge panel with aspect search, entity filter, global toggle, and a collapsible V/T aspect tree. Persisted to user:// on Ctrl+S.

## Status notes

- 2026-06-07: Closed with --force; 3/10 DoD boxes unchecked. Reason: historical: shipped in TUMU 0.10.26
