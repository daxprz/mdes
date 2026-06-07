---
xid: STO-SND-002
parent: ./epic.md
kind: story
effort: snd
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-jn89
shipped: 2026-06-07
tasks: 12
complete: 9
---

# Pattern Core — The Algebra

## Summary

Port the five core types (Fraction, TimeSpan, Hap, State, Pattern) and the full pattern algebra to GDScript, mathematically identical to Strudel v1.2.0. Includes combinators, composers, euclidean rhythms, and continuous signals.

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

- [x] Fraction type: exact rational arithmetic, comparison, cycle ops, conversion
- [x] TimeSpan: spanCycles, intersection, duration, cycleArc
- [x] Hap and State types with source-location context
- [x] Pattern foundation: queryArc, pure/silence/gap, reify, fmap, filters
- [x] Applicative + monadic ops: appBoth/Left/Right, bind/join, squeezeJoin
- [x] Combinators: stack/sequence/slowcat, fast/slow, every, rev, layer, ply
- [x] Composers: set/keep/add/sub/mul/div with hows, struct, mask
- [x] Euclidean rhythms: Bjorklund, euclid, euclidRot, euclidLegato
- [x] Continuous signals: saw, sine, tri, square, rand, range, segment


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

- **Source:** EPIC_strudel_integration.md EPIC 1 (Stories 1.1-1.9); commit 'Strudel pattern engine (live-coding music)'
- **Shipped in:** v0.10.48
- **History:** Port the five core types (Fraction, TimeSpan, Hap, State, Pattern) and the full pattern algebra to GDScript, mathematically identical to Strudel v1.2.0. Includes combinators, composers, euclidean rhythms, and continuous signals.

## Status notes

- 2026-06-07: Closed with --force; 3/12 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.10.48
