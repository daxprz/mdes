# Agent Workflow Protocol

Each agent has four workflow folders that manage task lifecycle.

## Folder Structure

```
AI/agents/{agent-name}/
  inbox/        New tasks assigned to this agent — check here first
  active/       Tasks currently being worked on
  pending/      Tasks blocked or waiting on input
  archive/      Completed tasks (moved here when done)
```

## Task File Format

Each task is a markdown file named descriptively (e.g., `fix-boss-ai.md`, `test-grapple-physics.md`).

```markdown
---
assigned: 2026-04-01
source: user | agent:{name} | command:{name}
priority: high | normal | low
---

# Task Title

## Description

What needs to be done and why.

## Status Notes

Updates appended as work progresses.

- YYYY-MM-DD: Moved to active, beginning work
- YYYY-MM-DD: Blocked on X, moved to pending
- YYYY-MM-DD: Complete, moved to archive
```

## Lifecycle

1. **Assign** -- A task file is created in `inbox/` by the user, orchestrator, another agent, or a command.
2. **Start** -- The agent reads `inbox/`, picks up work, moves the file to `active/`, and appends a status note.
3. **Block** -- If the agent is blocked (needs input, waiting on another agent), move the file to `pending/` with a note explaining what is needed.
4. **Complete** -- When done, move the file to `archive/` with a final status note summarizing the outcome.

## On Startup

When an agent is invoked, it should:

1. Check `inbox/` for new work
2. Check `pending/` for unblocked items
3. Check `active/` for in-progress work that may need continuation

## Cross-Agent Handoff

Agents can assign tasks to other agents by writing a file to that agent's `inbox/`. Include a `source: agent:{your-name}` field so the receiving agent knows who assigned it.

## Commands Writing to Inbox

Slash commands and automated processes can drop task files into an agent's inbox. Include `source: command:{command-name}` to indicate the origin.

## The Liaison Agent (Required)

Every project using this workflow **must** have a `liaison` agent. The liaison is the project's external interface — the single point of contact for cross-project interaction.

- External projects write requests to `AI/agents/liaison/inbox/` using `source: project:{project-name}`
- The liaison triages: handles directly or delegates to the appropriate internal agent
- The liaison is the **only** agent that external projects should interact with directly
- Internal agents should not receive tasks directly from external projects
