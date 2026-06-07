---
xid: STO-SND-007
parent: ./epic.md
kind: story
effort: snd
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-2b22
shipped: 2026-06-07
tasks: 7
complete: 4
---

# Extract Strudel Line Compiler

## Summary

Move the ~800-line line parser out of music_drawer.gd into a standalone StrudelLineCompiler, plus the merge/expand helpers from rcon.gd. Pure refactor gated by the 47-test A/B suite for zero behavior change.

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

- [x] Create strudel_line_compiler.gd from drawer parse methods
- [x] Drawer delegates to StrudelLineCompiler.parse_line
- [x] Move merge_continuation_lines and expand_stacks from rcon.gd
- [x] Gate: 47 A/B tests pass identically


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

- **Source:** composition_architecture.md Phase 1; commit 'Composition refactor phases 3-5'
- **Shipped in:** v0.10.41
- **History:** Move the ~800-line line parser out of music_drawer.gd into a standalone StrudelLineCompiler, plus the merge/expand helpers from rcon.gd. Pure refactor gated by the 47-test A/B suite for zero behavior change.

## Status notes

- 2026-06-07: Closed with --force; 3/7 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.10.41
