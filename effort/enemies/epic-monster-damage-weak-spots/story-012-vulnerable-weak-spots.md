---
xid: STO-ENMY-012
parent: ./epic.md
kind: story
effort: enmy
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-9f2
shipped: 2026-06-07
tasks: 14
complete: 11
---

# Vulnerable Weak Spots with Tiered Damage

## Summary

Per-region HP with three damage states (none/medium/high), escalating blood effects, and gameplay penalties including an eye critical hit and leg/arm/tail/torso degradation.

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

- [x] Replace flat _part_health with per-part struct {max_hp, current_hp, damage_state}
- [x] Recalculate damage_state from HP percentage on each take_part_damage()
- [x] Head weak spot — scaled blood particles at skull
- [x] Eye weak spot — 2x critical hit, PING sound, 5-direction blood squirt, head-local transform
- [x] Mid-tail weak spot — high damage disables grab/ball attack
- [x] Torso weak spot — high damage continuous blood drip until death
- [x] Rear legs — high damage reduces leap launch velocity 25%/50%
- [x] Front legs/arms — high damage reduces slash damage 50%/75%
- [x] Blood particle system _spawn_blood with splash/squirt modes
- [x] RCON partstatus command
- [x] RCON partdmg command


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

- **Source:** docs/epics/EPIC_monster_damage_and_weak_spots.md Story 2
- **Shipped in:** v0.9.18
- **History:** Per-region HP with three damage states (none/medium/high), escalating blood effects, and gameplay penalties including an eye critical hit and leg/arm/tail/torso degradation.

## Status notes

- 2026-06-07: Closed with --force; 3/14 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.18
