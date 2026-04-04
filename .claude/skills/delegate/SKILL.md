---
name: delegate
description: Delegate a task to another agent within this project. Writes a task file to the target agent's inbox. Use when the current agent needs another agent's expertise.
disable-model-invocation: false
argument-hint: <agent> <task description>
---

# Delegate Task to Another Agent

Hand off a task to another agent in this project by writing to their inbox.

## Arguments

$ARGUMENTS

- **`$0`** — Target agent name (`tumu` or `liaison`).
- **Remaining args** — Task description. Becomes the basis for the task title and body.

## Agent Registry

Read `AI/agents/ROSTER.md` for the full agent roster.

Available agents:
- `tumu` 🧁 — Game testing, RCON, debug diagnostics
- `liaison` 🔗 — Cross-project interface

## Behavior

### Phase 1: Resolve Target Agent

1. Match `$0` against agent directory names in `AI/agents/`
2. If no exact match, check aliases above
3. If still no match, list available agents and ask
4. Verify `AI/agents/{agent}/inbox/` exists

### Phase 2: Check for Duplicates

1. Scan the target agent's `inbox/` for existing `.md` files (ignore `.gitkeep`)
2. Read each file's title and description
3. If a strong overlap exists with the new task, ask: "There's already a similar task in {agent}'s inbox: '{title}'. Update it instead?"
4. If yes, append a status note to the existing file

### Phase 3: Create Task File

1. Generate a kebab-case filename from the task description (e.g., `review-auth-flow.md`)
2. Determine the calling agent:
   - If you're running as a named agent (check your system prompt), use `source: agent:{your-name}`
   - If running as the main session, use `source: user`
3. Write to `AI/agents/{target}/inbox/{filename}`:

```markdown
---
assigned: YYYY-MM-DD
source: agent:{calling-agent} | user
priority: normal
---

# {Task Title}

## Description

{Expanded task description with enough context for the target agent to act independently. Include relevant file paths, decisions made so far, and what outcome is expected.}

## Status Notes

- YYYY-MM-DD: Created via /delegate
```

### Phase 4: Update Caller State (if applicable)

If the calling agent has an active task related to this delegation:
1. Note the delegation in the active task's status notes
2. Optionally move the active task to `pending/` if blocked on the delegated work

### Phase 5: Confirm

```
Delegated to: {agent} ({emoji})
  File:   AI/agents/{agent}/inbox/{filename}
  Title:  {task title}
  Source:  agent:{calling-agent}
```

## Examples

```
/delegate engineer implement the new PDF split logic from the design doc
/delegate qa review test coverage for the resource management module
/delegate knowledge update the architecture docs after the auth refactor
/delegate pe review the proposed ORN schema changes for backward compatibility
/delegate sre check if the MCP container health checks are working correctly
```

## Key Rules

1. **Never bypass the target agent's inbox** — always write to `inbox/`, even if you could do the work yourself
2. **Include enough context** — the target agent starts with no conversation history; the task file is all they get
3. **Default priority is `normal`** — only use `high` if the user explicitly says urgent
4. **Track delegations** — note in your own active task that you delegated, so the chain is traceable
5. **One task per file** — if delegating multiple things, create multiple files
