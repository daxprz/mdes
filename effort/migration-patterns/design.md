---
xid: DES-DSGN-002
kind: design
effort: dsgn
status: shipped
date: 2026-06-07
guidance: ./guidance.md
hugs: []
tenets: []
bd-id: mdes-jfe
shipped: 2026-06-07
---

# Wildlife Migration Patterns

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

- **Source:** docs/design/migration_patterns.md; git: 'Implement migration patterns: cyclic multi-phase species movement' (2026-03-18), 'Migration: per-species patterns, stagger, bat repulsion, editor polish'
- **Shipped in:** v0.9.7
- **History:** Cyclic multi-phase migration system that compels species (fireflies, bats) toward the nearest active destination zone, then returns them to normal behavior on arrival. Includes a per-species pattern model, a level-config JSON schema, and a MIGRATION level-editor mode.
