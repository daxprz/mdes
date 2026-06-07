---
xid: STO-PROG-002
parent: ./epic.md
kind: story
effort: prog
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-05hm
shipped: 2026-06-07
tasks: 11
complete: 8
---

# Per-Skill Leveling

## Summary

Independent XP tracking for attack, special, charge, and block, each leveling from its own successful use, including class-specific healing and summoning XP.

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

- [x] Track XP separately for: basic attack, special ability, charge attack, block/parry
- [x] Each skill levels independently based on successful use
- [x] Basic attack: each landed hit grants 1-3 xp (scales with enemy difficulty)
- [x] Special ability: each successful use grants 5-10 xp
- [x] Charge attack: damage dealt during charge converts to xp (1 xp per 5 damage)
- [x] Block: each blocked hit grants 3 xp. Perfect parry grants 15 xp
- [x] Healing (Healer): each HP healed on allies grants 0.5 xp
- [x] Summoning (Summoner): donut buddy damage contributes xp to summoner


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

- **Source:** BACKLOG.md Story 12.2
- **Shipped in:** v0.9.0
- **History:** Independent XP tracking for attack, special, charge, and block, each leveling from its own successful use, including class-specific healing and summoning XP.

## Status notes

- 2026-06-07: Closed with --force; 3/11 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.0
