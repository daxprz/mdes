---
xid: DES-SND-003
kind: design
effort: snd
status: shipped
date: 2026-06-07
guidance: ./guidance.md
hugs: []
tenets: []
bd-id: mdes-t94r
shipped: 2026-06-07
---

# Strudel v1.2.0 Compatibility Audit

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
| `EPI-snd-SLUG` | _(epic name)_ | open | _(HUG references)_ |

## Key Concepts

_(Optional: domain-specific terminology defined for the reader. Skip
if the system uses only standard CCC concepts — link to
`docs/work-platform.md` instead.)_

## Related

- **Guidance:** [guidance.md](guidance.md)
- **Depends on:** _(other DESIGNs / external systems)_
- **Used by:** _(downstream consumers)_


## TUMU Provenance

- **Source:** docs/design/strudel_compatibility.md
- **Shipped in:** v0.10.52
- **History:** Cross-cutting feature-by-feature audit of what the GDScript port supports versus Strudel v1.2.0 across mini-notation, pattern algebra, signals, and visualizers, plus the major missing systems (JS expression language, sample playback, full control set, chord/scale). Doubles as the priority roadmap for closing compatibility gaps.
