---
xid: STO-UI-003
parent: ./epic.md
kind: story
effort: ui
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-uhaf
shipped: 2026-06-07
tasks: 8
complete: 5
---

# Persistent Player HUD

## Summary

New player_hud.gd autoload on CanvasLayer 100 renders 1-4 bottom-center panels (name, class, color icon, HP/mana) visible across all game states, replacing the old GameManager HUD.

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

- [x] Create new player_hud.gd autoload with CanvasLayer (layer 100)
- [x] Show 1-4 HUD panels at bottom-center, evenly spaced, based on connected controllers
- [x] Each HUD shows: profile name (default P1-P4), class name, class color icon, HP/mana bars
- [x] HUD visible in ALL game states (title, overworld, tower, boss)
- [x] Remove old HUD from GameManager (_create_hud, _muffin_label, _player_stat_labels)


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

- **Source:** BACKLOG Story 27.1; inline_hud_selection.md
- **Shipped in:** v0.9.8
- **History:** New player_hud.gd autoload on CanvasLayer 100 renders 1-4 bottom-center panels (name, class, color icon, HP/mana) visible across all game states, replacing the old GameManager HUD.

## Status notes

- 2026-06-07: Closed with --force; 3/8 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.8
