---
xid: STO-CLS-007
parent: ./epic.md
kind: story
effort: cls
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-625
shipped: 2026-06-07
tasks: 8
complete: 5
---

# Base Tank Class

## Summary

Adds TANK with high-HP stats, sprites, a heavy mace slam, ground-pound AoE stun, and a charged shockwave.

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

- [x] Add TANK to CharacterClass enum + stats (250 HP, 30 mana, 70 speed, 0.5 mana regen)
- [x] Create tank topdown + side spritesheets
- [x] Basic attack: heavy mace slam (45 damage, 1.2s cooldown, wide area)
- [x] Special: ground pound AoE stun around the tank
- [x] Charge attack: massive ground shockwave (60-160px radius, 20-70 damage scaled by charge)


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

- **Source:** BACKLOG.md Story 14.1
- **Shipped in:** v0.9.5
- **History:** Adds TANK with high-HP stats, sprites, a heavy mace slam, ground-pound AoE stun, and a charged shockwave.

## Status notes

- 2026-06-07: Closed with --force; 3/8 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.5
