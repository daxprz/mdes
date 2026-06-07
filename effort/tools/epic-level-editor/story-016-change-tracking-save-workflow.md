---
xid: STO-TOOLS-016
parent: ./epic.md
kind: story
effort: tools
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-mevk
shipped: 2026-06-07
tasks: 9
complete: 6
---

# Change Tracking & Save Workflow

## Summary

Per-component and per-item change tracking with yellow change indicators, an on-screen change summary bar, and an Original/Custom save dialog mirroring the splay pose editor.

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

- [x] _changed dictionary tracks changed components
- [x] Per-item change state (_changed_items)
- [x] Yellow dot/asterisk on changed items in every mode
- [x] On-screen change summary bar (yellow pending / green clean)
- [x] Custom vs Original indicator
- [x] Ctrl+S Original/Custom save dialog; delete custom when promoted


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

- **Source:** docs/epics/EPIC_editor_change_tracking.md
- **Shipped in:** 0.9.20
- **History:** Per-component and per-item change tracking with yellow change indicators, an on-screen change summary bar, and an Original/Custom save dialog mirroring the splay pose editor.

## Status notes

- 2026-06-07: Closed with --force; 3/9 DoD boxes unchecked. Reason: historical: shipped in TUMU 0.9.20
