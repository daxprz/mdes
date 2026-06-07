---
xid: STO-MECH-037
parent: ./epic.md
kind: story
effort: mech
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-8av
shipped: 2026-06-07
tasks: 10
complete: 7
---

# Attack Dummy Tether Support

## Summary

Adds a tether weapon to the attack dummy that aims at attachment points and creates tethers, with RCON controls for length and target B.

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

- [x] New attack dummy weapon: tether
- [x] Tether weapon flow: aim at attachment point, create to floor or target
- [x] set_tether_length(px) configurable
- [x] set_tether_target_b(floor / enemy node part)
- [x] RCON: attacker weapon tether
- [x] RCON: attacker tether_length <px>
- [x] RCON: attacker tether_b floor / enemy <idx> <part>


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

- **Source:** EPIC_dual_grapple_tether.md Story 8
- **Shipped in:** v0.9.18
- **History:** Adds a tether weapon to the attack dummy that aims at attachment points and creates tethers, with RCON controls for length and target B.

## Status notes

- 2026-06-07: Closed with --force; 3/10 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.18
