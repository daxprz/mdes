---
xid: STO-ENMY-011
parent: ./epic.md
kind: story
effort: enmy
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-nj1
shipped: 2026-06-07
tasks: 9
complete: 6
---

# Targetable Attachment Points

## Summary

Invisible larger hitbox zones (head, tail tip, shoulders, waist) where items can attach, tracked to skeleton anchors each frame with a public attach/detach API.

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

- [x] Add attachment point Area2D nodes (head r16, tail_tip r30, shoulders r14, waist r12)
- [x] Update positions every frame in _update_hitbox_positions()
- [x] _attachments Dictionary keyed by point name
- [x] Public API: attach_item, detach_item, get_attach_world_position
- [x] Attached items' global_position tracked each frame with freed-item cleanup
- [x] Debug draw: dashed cyan circles with labels and item count when selected


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

- **Source:** docs/epics/EPIC_monster_damage_and_weak_spots.md Story 1
- **Shipped in:** v0.9.18
- **History:** Invisible larger hitbox zones (head, tail tip, shoulders, waist) where items can attach, tracked to skeleton anchors each frame with a public attach/detach API.

## Status notes

- 2026-06-07: Closed with --force; 3/9 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.18
