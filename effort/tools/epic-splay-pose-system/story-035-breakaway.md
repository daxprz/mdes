---
xid: STO-TOOLS-035
parent: ./epic.md
kind: story
effort: tools
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-t5kl
shipped: 2026-06-07
tasks: 8
complete: 5
---

# Breakaway — Dramatic Freedom

## Summary

When a splayed creature's tethers exceed 50% aggregate damage, all snap with sound, screen shake, slow-mo, and the creature wakes angry.

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

- [x] Aggregate tether durability trigger at 50% damage
- [x] Per-pose breakaway sound with fallback
- [x] Screen shake + snap particles + flash/slow-mo
- [x] Clear overrides, become active, brief invincibility
- [x] splay breakaway <idx> RCON


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

- **Source:** docs/epics/EPIC_splay_system.md Story 10
- **Shipped in:** 0.9.21
- **History:** When a splayed creature's tethers exceed 50% aggregate damage, all snap with sound, screen shake, slow-mo, and the creature wakes angry.

## Status notes

- 2026-06-07: Closed with --force; 3/8 DoD boxes unchecked. Reason: historical: shipped in TUMU 0.9.21
