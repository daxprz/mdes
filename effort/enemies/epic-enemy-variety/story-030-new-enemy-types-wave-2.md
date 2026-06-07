---
xid: STO-ENMY-030
parent: ./epic.md
kind: story
effort: enmy
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-fco
shipped: 2026-06-07
tasks: 11
complete: 8
---

# New Enemy Types — Wave 2

## Summary

Eight additional enemies, each with a distinct mechanic from bombing to splitting to shielding.

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

- [x] Cupcake Bomber — drops frosting bombs that splat and slow
- [x] Licorice Whip — tentacle grab-and-pull
- [x] Gummy Bear Brute — line charge, wall bounce, dizzy
- [x] Wafer Shield Bearer — hit from behind or with charge
- [x] Candy Corn Spinner — AoE spin, vulnerable when dizzy
- [x] Marshmallow Blob — splits into smaller blobs on death
- [x] Peppermint Roller — rolls and bounces, speeds up over time
- [x] Jellybean Sniper — background sniper, flushed by AoE


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

- **Source:** docs/BACKLOG.md Story 4.4
- **Shipped in:** v0.9.13
- **History:** Eight additional enemies, each with a distinct mechanic from bombing to splitting to shielding.

## Status notes

- 2026-06-07: Closed with --force; 3/11 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.13
