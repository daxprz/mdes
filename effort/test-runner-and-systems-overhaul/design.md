---
xid: DES-DSGN-004
kind: design
effort: dsgn
status: shipped
date: 2026-06-07
guidance: ./guidance.md
hugs: []
tenets: []
bd-id: mdes-jvl
shipped: 2026-06-07
---

# Test Runner, Player & Gameplay Systems Overhaul (v0.10.18-23)

## Overview

_(One paragraph: what problem this design addresses; who benefits; what
is in scope. Definitional, not aspirational — the reader should walk
away knowing whether to read further.)_

## Background

_(Context: why this is needed now. What drove the decision to author
this design? Surface upstream prompts, prior failed attempts, or
strategic shifts that make this design's existence reasonable.)_

## Current State

_(Living section — what already exists in the codebase / system that
this design will extend or replace. Update as work lands.)_

## Goals

- _(Specific, testable outcome. Avoid "make X better" — say "X handles
  N concurrent operators without dropping events.")_
- _(Another goal. Each goal should map to at least one epic.)_

## Non-Goals (Out of Scope)

- _(Explicitly excluded; what we are NOT solving here.)_
- _(Deferred to a future design — link if it exists.)_

## Epics

| XID | Epic | Status | Implements |
|-----|------|--------|------------|
| `EPI-dsgn-SLUG` | _(epic name)_ | open | _(HUG references)_ |

## Key Concepts

_(Optional: domain-specific terminology defined for the reader. Skip
if the system uses only standard CCC concepts — link to
`docs/work-platform.md` instead.)_

## Related

- **Guidance:** [guidance.md](guidance.md)
- **Depends on:** _(other DESIGNs / external systems)_
- **Used by:** _(downstream consumers)_


## TUMU Provenance

- **Source:** docs/design/session_v0.10.18_to_v0.10.23.md; git: 'Release v0.10.18 — Docked test editor, chain daze, soccer ball, balloon explosions, press-to-join' through 'Release v0.10.23 — Remove static entity info, clean test menu, save/diff detection'
- **Shipped in:** v0.10.23
- **History:** Six-release build log covering the docked test editor with three editor modes, script-hash result caching, generic entity selection, and gameplay/player additions (chain daze, soccer dummy, balloon chain explosions, press-to-join controllers, debug-aspect migration). All six releases shipped.
