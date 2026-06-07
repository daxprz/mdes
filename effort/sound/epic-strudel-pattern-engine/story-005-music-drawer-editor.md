---
xid: STO-SND-005
parent: ./epic.md
kind: story
effort: snd
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-6a6e
shipped: 2026-06-07
tasks: 8
complete: 5
---

# Music Drawer — Editor UI

## Summary

Build the in-game live-coding panel (Ctrl+M) modeled on Strudel's REPL using Godot _draw(): multi-line editor with full keybindings, source highlighting, pianoroll, and hot-reload on edit. Closes the type-see-hear feedback loop.

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

- [x] Music Drawer panel: slide-out with play/stop/BPM controls, Ctrl+M shortcut
- [x] Music line text editing: cursor, selection, multi-line, syntax coloring, live eval
- [x] Source highlighting: active hap locations glow behind leaf text with fade
- [x] Pianoroll visualization: scrolling window, value axis, playhead, labels, options
- [x] Live editing / hot reload: re-parse, atomic pattern swap, flash + error display


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

- **Source:** EPIC_strudel_integration.md EPIC 4 (Stories 4.1-4.5); commits 'Multi-line editor', 'source text highlighting', 'Pianoroll options'
- **Shipped in:** v0.10.51
- **History:** Build the in-game live-coding panel (Ctrl+M) modeled on Strudel's REPL using Godot _draw(): multi-line editor with full keybindings, source highlighting, pianoroll, and hot-reload on edit. Closes the type-see-hear feedback loop.

## Status notes

- 2026-06-07: Closed with --force; 3/8 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.10.51
