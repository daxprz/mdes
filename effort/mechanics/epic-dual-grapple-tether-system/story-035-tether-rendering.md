---
xid: STO-MECH-035
parent: ./epic.md
kind: story
effort: mech
status: in-progress
date: 2026-06-07
depends-on: []
bd-id: mdes-rtd
---

# Tether Rendering

## Summary

Renders the spinning second hook, the thrown rope, and the active tether with tension-based visuals, anchor indicators, and a sever snap animation. Subtle transition animations remain open.

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

- [x] TETHER_WINDUP: draw second hook spinning at anchor A
- [x] TETHER_THROWN: draw rope from anchor A to flying hook
- [x] TETHER_ACTIVE: multi-segment rope with catenary sag when slack
- [x] Tension visual: slack grey, taut brown, pulling bright/vibrating
- [x] Anchor indicators at each end
- [x] Snap animation on sever: recoil + particle burst


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

- **Source:** EPIC_dual_grapple_tether.md Story 6
- **Shipped in:** v0.9.16
- **History:** Renders the spinning second hook, the thrown rope, and the active tether with tension-based visuals, anchor indicators, and a sever snap animation. Subtle transition animations remain open.
