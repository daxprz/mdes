---
xid: STO-SND-003
parent: ./epic.md
kind: story
effort: snd
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-89f5
shipped: 2026-06-07
tasks: 7
complete: 4
---

# Mini-Notation Parser

## Summary

Port the krill PEG grammar to a hand-written recursive-descent GDScript parser producing an AST that converts to Pattern trees. Tracks source locations on every leaf for editor highlighting.

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

- [x] Lexer/tokenizer: atoms, rests, brackets, operators, source offsets
- [x] Recursive-descent parser: sequences, stacks, groups, slowcat, polymeter, operators
- [x] AST-to-Pattern: patternifyAST, applyOptions, alignment dispatch, leaf locations
- [x] Compatibility test: mini() output matches Strudel firstCycleValues


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

- **Source:** EPIC_strudel_integration.md EPIC 2 (Stories 2.1-2.3); commit 'Strudel v1.2.0 compat'
- **Shipped in:** v0.10.51
- **History:** Port the krill PEG grammar to a hand-written recursive-descent GDScript parser producing an AST that converts to Pattern trees. Tracks source locations on every leaf for editor highlighting.

## Status notes

- 2026-06-07: Closed with --force; 3/7 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.10.51
