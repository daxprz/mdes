---
xid: STO-SND-006
parent: ./epic.md
kind: story
effort: snd
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-6s21
shipped: 2026-06-07
tasks: 5
complete: 2
---

# RCON Integration + Debug Aspects

## Summary

Wire the Strudel system into the existing RCON/console infrastructure with strudel play/stop/cps/hush commands, console autocomplete, and debug aspects exposing scheduler, hap, pattern, and parse state.

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

- [x] RCON commands: strudel <mini>, stop, cps, hush, console autocomplete
- [x] Debug aspects: strudel/scheduler, /haps, /pattern, /parse with logging + overlay


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

- **Source:** EPIC_strudel_integration.md EPIC 5 (Stories 5.1-5.2); commits 'strudel edit command', 'strudel start/stop'
- **Shipped in:** v0.10.50
- **History:** Wire the Strudel system into the existing RCON/console infrastructure with strudel play/stop/cps/hush commands, console autocomplete, and debug aspects exposing scheduler, hap, pattern, and parse state.

## Status notes

- 2026-06-07: Closed with --force; 3/5 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.10.50
