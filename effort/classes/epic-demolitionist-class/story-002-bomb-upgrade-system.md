---
xid: STO-CLS-002
parent: ./epic.md
kind: story
effort: cls
status: shipped
date: 2026-06-07
depends-on: []
bd-id: mdes-vii
shipped: 2026-06-07
tasks: 7
complete: 4
---

# Bomb Upgrade System

## Summary

Tiered bomb upgrades for damage and radius plus fragment and napalm bomb variants.

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

- [x] Explosive Power upgrades (damage multiplier tiers)
- [x] Blast Size upgrades (radius multiplier tiers)
- [x] Fragment Bombs (split into 3-5 mini-bombs after first bounce) - via charge attack
- [x] Napalm Bombs (leave burning ground for 3s, DoT damage)


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

- **Source:** BACKLOG.md Story 9.2; docs/design/new_classes.md
- **Shipped in:** v0.9.5
- **History:** Tiered bomb upgrades for damage and radius plus fragment and napalm bomb variants.

## Status notes

- 2026-06-07: Closed with --force; 3/7 DoD boxes unchecked. Reason: historical: shipped in TUMU v0.9.5
