---
xid: STO-PROG-001
parent: ./epic.md
kind: story
effort: prog
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-jvzu
shipped: 2026-06-07
tasks: 10
complete: 7
---

# XP & Level Framework

## Summary

Core XP curve, per-player level/xp fields in PlayerManager, and XP gain on hit, kill, and boss defeat with level-up VFX and a cap.

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

- [x] Define XP curve per level (level 1=100xp, level 2=250xp, scaling formula)
- [x] Add level and xp fields to player data in PlayerManager
- [x] XP earned on successful hit (attack lands on enemy = xp for that skill)
- [x] XP earned on kill (bonus xp for finishing blow)
- [x] XP earned on boss defeat (large bonus, scales with boss difficulty)
- [x] Level-up VFX + sound when threshold reached (gold flash, fanfare)
- [x] Max level cap (20 per skill, 50 overall)


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

- **Source:** BACKLOG.md Story 12.1
- **Shipped in:** v0.9.0
- **History:** Core XP curve, per-player level/xp fields in PlayerManager, and XP gain on hit, kill, and boss defeat with level-up VFX and a cap.

## Status notes

- 2026-06-07: Closed with --force; 3/10 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.0
