---
xid: STO-BUG-009
parent: ./epic.md
kind: story
effort: bug
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-o5q
shipped: 2026-06-07
tasks: 4
complete: 1
---

# Title Screen START Button Ignored

## Summary

Fixed START doing nothing on fresh launch with no players — name-entry/camera setup only ran on return-from-game, so no profile bound. Fix calls _setup_camera() and _setup_name_entry() unconditionally in _ready() (commit 2026-03-16: fix 3 title screen bugs incl. START button).

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

- [x] BUG: Pressing START on title screen with no players does nothing — call setup unconditionally in _ready()


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

- **Source:** BACKLOG Story 2.9
- **Shipped in:** n/a
- **History:** Fixed START doing nothing on fresh launch with no players — name-entry/camera setup only ran on return-from-game, so no profile bound. Fix calls _setup_camera() and _setup_name_entry() unconditionally in _ready() (commit 2026-03-16: fix 3 title screen bugs incl. START button).

## Status notes

- 2026-06-07: Closed with --force; 3/4 DoD boxes unchecked. Reason: historical: shipped in TUMU
