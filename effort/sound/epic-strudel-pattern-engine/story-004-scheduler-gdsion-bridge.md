---
xid: STO-SND-004
parent: ./epic.md
kind: story
effort: snd
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-6uub
shipped: 2026-06-07
tasks: 7
complete: 4
---

# Scheduler + GDSiON Bridge

## Summary

Connect the pattern engine to real-time audio via a cycle-based Cyclist scheduler and a Hap-to-SiON note_on bridge. Maps note/n/s/freq value types and per-note controls to GDSiON, integrated with the existing MusicManager.

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

- [x] Clock: port zyklus.mjs to Godot frame timing with latency/overlap
- [x] Cyclist scheduler: cps tracking, query window, setPattern/start/stop/now
- [x] SiON trigger bridge: hap value to note_on params, voice mapping (87 presets)
- [x] Controls: note/s/n/gain/speed/velocity/pan/cutoff, cps/cpm tempo


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

- **Source:** EPIC_strudel_integration.md EPIC 3 (Stories 3.1-3.4); commit 'Procedural adaptive music system (GDSiON)'
- **Shipped in:** v0.10.47
- **History:** Connect the pattern engine to real-time audio via a cycle-based Cyclist scheduler and a Hap-to-SiON note_on bridge. Maps note/n/s/freq value types and per-note controls to GDSiON, integrated with the existing MusicManager.

## Status notes

- 2026-06-07: Closed with --force; 3/7 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.10.47
