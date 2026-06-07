---
xid: STO-MECH-009
parent: ./epic.md
kind: story
effort: mech
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-ehm
shipped: 2026-06-07
tasks: 9
complete: 6
---

# Block/Parry System (ALL classes)

## Summary

Hold-to-block damage reduction with a guard VFX, plus a perfect-parry window that stuns the attacker with a bright flash and clang.

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

- [x] Map block to a button (R2 / Left Shift)
- [x] Holding block: reduce incoming damage by 50%, movement speed halved
- [x] Visual: shield/guard VFX in front of character
- [x] Perfect parry: block within 0.2s of being hit -> attacker stunned for 1.5s
- [x] Perfect parry VFX: bright flash + metallic clang sound
- [x] Perfect parry window indicator (brief white flash on character when block starts)


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

- **Source:** BACKLOG Story 11.5
- **Shipped in:** v0.9.6
- **History:** Hold-to-block damage reduction with a guard VFX, plus a perfect-parry window that stuns the attacker with a bright flash and clang.

## Status notes

- 2026-06-07: Closed with --force; 3/9 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.6
