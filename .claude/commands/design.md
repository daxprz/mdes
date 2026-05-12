---
description: Design a game component using knowledge from the research repository and codebase patterns
argument-hint: <component> [--quick]
---

# Design Command

## Purpose

Design a game component, system, or subsystem using knowledge from the research repository and the existing codebase.

**Invocation:** `/design <thing to design>`

## Process

### Step 1: Read the Knowledge Index

Read `/var/tumu/research/gamedev/godot/index.md` to understand established patterns and best practices relevant to the design task.

### Step 2: Identify Relevant Patterns

From the index, identify which patterns, techniques, or architectural approaches apply to the thing being designed. Look for:
- **Multi-source patterns** — concepts reinforced by multiple videos (highest confidence)
- **Specific techniques** — e.g., state machines for behavior, components for modularity, resources for data
- **Anti-patterns** — things the knowledge base warns against

If the index references a topic you need more detail on, follow the appendix cross-links to read the full video `content.md` for that source.

### Step 3: Read the Existing Codebase

Understand how the current project is structured:
- Read `CLAUDE.md` for project architecture
- Read relevant existing scripts in `scripts/` that the new design will interact with
- Read any existing epic or design docs in `docs/epics/` or `docs/design/`

### Step 4: Produce the Design

Write a design document at `docs/design/<component-name>.md` with:

```markdown
# <Component Name> Design

## Overview
Brief description of what this component does and why it's needed.

## Knowledge Base References
Which patterns from the knowledge repository informed this design:
- Pattern X from [V3], [V7] — why it applies here
- Anti-pattern Y from [V1] — what we're avoiding and why

## Architecture
How the component is structured. Use Godot-specific terminology:
- Node hierarchy
- Signal connections
- State machine states (if applicable)
- Resource definitions (if applicable)

## Implementation Plan
Ordered steps to build this component:
1. Create the scene structure
2. Implement core logic
3. Add debug aspects
4. Write test scenarios

## Debug Aspects
What debug aspects should be registered for this component:
- `<group>/<sub>` — what it shows

## Test Scenarios
What test JSON files should be created to verify this component works.
```

### Step 5: Review Against Knowledge

Before finalizing, cross-check the design against the knowledge index:
- Does it follow component-based design principles?
- Does it use signals for decoupling?
- Does it avoid the anti-patterns listed in the knowledge base?
- Would a state machine simplify the logic?
- Is data separated from logic using Resources?

Report any deviations and justify them.

## Variations

- `/design <thing>` — full design with knowledge cross-referencing
- `/design <thing> --quick` — skip knowledge lookup, just produce a skeleton design doc
