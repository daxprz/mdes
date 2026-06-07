---
xid: STO-CLS-015
parent: ./epic.md
kind: story
effort: cls
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-x8m
shipped: 2026-06-07
tasks: 7
complete: 4
---

# Healer - Wind Gust + Healing Potion Throw

## Summary

Throwable healing-zone potion, a Wind Gust knockback ability, and a channelable healing aura.

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

- [x] Basic attack changed to Healing Potion Throw (arcing projectile, creates healing zone on land)
- [x] Wind Gust ability on Circle (8s cooldown, 100px radius, 400 force knockback)
- [x] Channel heal: hold attack to channel continuous healing aura (5 HP/s to nearby allies)
- [x] Interrupted channel fires proportional burst heal


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

- **Source:** BACKLOG.md Story 15.7
- **Shipped in:** v0.9.5
- **History:** Throwable healing-zone potion, a Wind Gust knockback ability, and a channelable healing aura.

## Status notes

- 2026-06-07: Closed with --force; 3/7 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.5
