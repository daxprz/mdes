---
xid: STO-SND-001
parent: ./epic.md
kind: story
effort: snd
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-le44
shipped: 2026-06-07
tasks: 18
complete: 15
---

# New Sound Effects

## Summary

Fifteen new ability sound effects synthesized and bound to their gameplay triggers across the class roster. All landed in a single batch (commit 441bc6a, 2026-03-15).

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

- [x] airwalk_activate.wav - Mage air-walk activation
- [x] backstab_hit.wav - Rogue backstab strike
- [x] beam_fire.wav - Mage beam of light
- [x] enrage_roar.wav - Melee enrage activation
- [x] grapple_hit.wav - Grappling hook impact
- [x] grapple_launch.wav - Grappling hook fire
- [x] mana_drink.wav - Mage mana potion
- [x] mark_target.wav - Summoner homing mark hit
- [x] refuel_gurgle.wav - Demolitionist refueling
- [x] reload_click.wav - Ranger reload
- [x] rocket_crash.wav - Demolitionist crash landing
- [x] rocket_ignite.wav - Demolitionist jetpack ignition
- [x] rocket_thrust.wav - Demolitionist jetpack loop
- [x] stealth_activate.wav - Rogue stealth activation
- [x] wind_gust.wav - Healer wind gust


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

- **Source:** BACKLOG.md Story 18.1; commit 441bc6a (Add 15 new sound effects for all new abilities)
- **Shipped in:** v0.9.5
- **History:** Fifteen new ability sound effects synthesized and bound to their gameplay triggers across the class roster. All landed in a single batch (commit 441bc6a, 2026-03-15).

## Status notes

- 2026-06-07: Closed with --force; 3/18 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.5
