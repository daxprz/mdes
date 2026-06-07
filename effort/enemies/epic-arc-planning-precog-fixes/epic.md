---
xid: EPI-ENMY-ARC-PLANNING-PRECOG-FIXES
parent: ../design.md
kind: epic
effort: enmy
status: shipped
date: 2026-06-07
hugs: []
tenets: []
bd-id: mdes-5mt
shipped: 2026-06-07
---

# Arc Planning & Precog Pathfinding Fixes

## Problem Statement

_(What problem are we solving? Why now? What's the impact of not
solving it? One paragraph — this drives the rest of the epic.)_

## Goals

- _(Specific, measurable outcome.)_
- _(Specific, measurable outcome.)_

## Non-Goals (Out of Scope)

- _(Explicitly excluded.)_
- _(Future work — deferred to a later epic, ideally linked.)_

## Context

**Source:** _(Where did this come from? Prior epic, user request, bug
report, AID directive — name it explicitly.)_

**Dependencies:**

- _(What must be true before we can start?)_
- _(External systems or features we need.)_

## Stories

| # | XID | Story | Status | Size |
|---|-----|-------|--------|------|
| 1 | `STO-enmy-001` | _(name)_ | open | S/M/L |

## Design

### Approach

_(High-level technical approach. How will we solve the problem? Keep
to one or two paragraphs — details belong in story files.)_

### Architecture

_(Component sketch or short description of the key components touched.
For complex shapes, link to a diagram in the DESIGN.)_

### Alternatives Considered

| Alternative | Pros | Cons | Decision |
|-------------|------|------|----------|
| _(Option A)_ | _(benefit)_ | _(drawback)_ | Rejected: _(reason)_ |
| _(Option B)_ | _(benefit)_ | _(drawback)_ | Selected |

## Decisions

| XID | Decision | Status | Rationale |
|-----|----------|--------|-----------|
| `HUG-enmy-NNN` | _(major architectural decision)_ | Adopted | _(why)_ |

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| _(risk)_ | Medium | High | _(how to reduce)_ |

## Success Criteria

- [ ] _(How do we know we're done?)_
- [ ] _(Measurable outcome.)_
- [ ] All stories shipped.
- [ ] Tests passing.
- [ ] `docs/work-platform.md` (or other consumer-facing doc) updated.

## Milestones

| Milestone | Target Date | Actual | Status |
|-----------|-------------|--------|--------|
| Stories defined | | | open |
| Implementation complete | | | open |
| Tests passing | | | open |

## Retrospective

_(Fill in after epic completion.)_

### What Went Well

-

### What Could Be Improved

-

### Lessons Learned

-


## TUMU Provenance

- **Source:** docs/epics/EPIC_arc_planning_fixes.md
- **Shipped in:** v0.10.0
- **History:** Incrementally re-apply seven interacting leap/precog fixes (arrival velocity, peak index, floor snap, chained-suspend skip, precog facing, waypoint protection, launch-under-platform filter) one at a time, plus fix the entity-platform matching that left the monster unable to locate itself (monster=P-1). Landed in Release v0.10.0 (Test Editor, Arc Planning, Bounded Leaps) with cross-platform gap detection following in subsequent fixes.
