---
xid: STO-PROG-008
parent: ./epic.md
kind: story
effort: prog
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-0whw
shipped: 2026-06-07
tasks: 10
complete: 7
---

# Pause Menu - Profile Stats Display

## Summary

The pause menu surfaces the paused player's profile name, avatar, level and XP bar, per-skill levels, session stats, acquired items, and lifetime stats.

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

- [x] Pause menu shows paused player's profile name + avatar
- [x] Show class avatar/icon (character sprite preview)
- [x] Show current level + XP bar (progress to next level)
- [x] Show per-skill levels (attack, special, charge, block Lv.X)
- [x] Show session stats: muffins collected, enemies killed, damage dealt
- [x] Show acquired items/artifacts this session
- [x] Show lifetime stats from profile (total kills, total muffins, bosses defeated)


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

- **Source:** BACKLOG.md Story 13.4
- **Shipped in:** v0.9.0
- **History:** The pause menu surfaces the paused player's profile name, avatar, level and XP bar, per-skill levels, session stats, acquired items, and lifetime stats.

## Status notes

- 2026-06-07: Closed with --force; 3/10 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.0
