---
xid: STO-ENMY-015
parent: ./epic.md
kind: story
effort: enmy
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-all
shipped: 2026-06-07
tasks: 12
complete: 9
---

# Attack Dummy (Test Entity)

## Summary

A test entity that actively fires bow or balloon weapons at the monster, configurable to target specific body parts, driven entirely via RCON.

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

- [x] New script attack_dummy.gd — CharacterBody2D rendered as orange circle
- [x] Configurable target via set_target()
- [x] Configurable body part targeting via set_target_part()
- [x] Weapon: Ranger bow firing arc projectiles
- [x] Weapon: Balloonist balloon darts
- [x] Weapon switching via set_weapon()
- [x] RCON commands: spawn attacker, target, part, weapon, rate, stop, start, stats
- [x] Debug draw: aim line, weapon name, shot/hit stats
- [x] Dummy takes no damage and is untargetable by monster


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

- **Source:** docs/epics/EPIC_monster_damage_and_weak_spots.md Story 5
- **Shipped in:** v0.9.18
- **History:** A test entity that actively fires bow or balloon weapons at the monster, configurable to target specific body parts, driven entirely via RCON.

## Status notes

- 2026-06-07: Closed with --force; 3/12 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.18
