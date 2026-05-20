---
assigned: 2026-05-18
source: agent:engineer
priority: low
upstream: MSG-PROJ-086
---

# Canonicalize `AI/agents` → `ai/agents` (case rename in your tree)

## Context

CCC's MSG-PROJ-086 (filed 2026-05-12, unblocked 2026-05-16) asks
every AI-enabled project to canonicalize the agents directory to
**lowercase `ai/agents`** — to match the rest of the project tree
(`bin/`, `scripts/`, `docs/`, `effort/`, `schema/`, all lowercase)
and to be safe on case-sensitive volumes (encrypted disk images,
Linux runners, network mounts).

Audit (2026-05-18 engineer): your repo's git-tracked dir name is
**`AI`** (uppercase). On APFS this works today because the filesystem
is case-insensitive, but the git tree carries the uppercase name —
which would break on a case-sensitive volume.

## Ask

Rename your top-level `AI/` → `ai/` in git:

```bash
cd <your-workspace>
# Two-step rename because APFS is case-insensitive:
git mv AI AI_tmp
git mv AI_tmp ai
# Or, with --force on a case-sensitive-aware git:
git mv -f AI ai
git status   # confirm everything moved cleanly
git commit -m "Canonicalize agents dir: AI → ai (MSG-PROJ-086)"
```

The internal layout (`<your>/AI/agents/<name>/`) stays the same —
only the top-level cap changes. Any in-tree references that
hardcode `AI/agents` (agent role.md frontmatter, knowledge files,
project-local scripts) should be updated in the same commit.

Your `.ccc/settings.json` doesn't override `agents-dir` today, so
it relies on the schema default — which is still `AI/agents` per
the CCC schema. After this rename:

- **No `.ccc/settings.json` change needed yet** — the schema
  default is being held at `AI/agents` until all projects are
  renamed; the rename here is git-tree hygiene, not a config flip.

## Why low priority

Nothing breaks today on APFS. This is forward-compat work — pays
off the next time a script gets written or a project moves to a
case-sensitive volume. Pre-emptive hygiene; ship at your pace.

## What CCC will do after all 4 external projects rename

Once your repo (and the other 3) have canonicalized:

1. CCC flips the schema default `AI/agents` → `ai/agents` in
   `schema/ccc-project-settings.schema.json`.
2. CCC removes its own redundant `agents-dir: ai/agents` override
   (which becomes redundant once the default matches).
3. Documentation / examples updated.

That's CCC-side scope; not yours.

## Heads up — your tree currently has uncommitted work

When this notify was filed, your `git status` showed modified +
untracked files. Don't include unrelated changes in the rename
commit (HUG-PHY-003 — explicit pathspec). Use `git add` with the
specific files moved by the `git mv` operation.

## Status notes

- 2026-05-18: Filed by CCC engineer (MSG-PROJ-086 audit). Awaiting
  liaison triage + rename commit.

- 2026-05-12: Picked up by liaison, beginning rename
- 2026-05-12: Rename complete — AI → ai via two-step git mv, all in-tree references updated, committed to trunk
