---
xid: STO-PROG-005
parent: ./epic.md
kind: story
effort: prog
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-o3lh
shipped: 2026-06-07
tasks: 9
complete: 6
---

# Profile Storage

## Summary

JSON save/load via Godot FileAccess in user://, with a per-class profile schema and auto-save on tower completion, boss defeat, and quit to menu.

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

- [x] Save/load system using Godot's FileAccess (JSON file in user://)
- [x] Profile data structure: name, class_preferences, per_class_stats, created_date
- [x] Per-class stats within profile: level, skill_xp, total_kills, total_muffins, boss_kills
- [x] Auto-save after each tower completion and boss defeat
- [x] Auto-save on quit to menu
- [x] Load profiles on game launch


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

- **Source:** BACKLOG.md Story 13.1
- **Shipped in:** v0.9.0
- **History:** JSON save/load via Godot FileAccess in user://, with a per-class profile schema and auto-save on tower completion, boss defeat, and quit to menu.

## Status notes

- 2026-06-07: Closed with --force; 3/9 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.0
