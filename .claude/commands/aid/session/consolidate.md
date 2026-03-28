# Command: /aid-session-consolidate

Ensure all recent Claude Code sessions have up-to-date summaries persisted to disk.

This is a maintenance command that scans sessions from the last 2 weeks, generates or
refreshes summaries, and archives anything older than 2 weeks.

## Usage

```
/aid-session-consolidate
```

No arguments. Operates on all sessions for the current project.

## Directory Structure

```
/var/tumu/aid/sessions/
  byid/<session-uuid>/summary.md       # Canonical summary keyed by session ID
  recent/<MM-DD-kebab-topic>.md         # Human-browsable symlink/copy for recent sessions (last 14 days)
  archive/<YYYY>/<MM-DD-kebab-topic>.md # Older sessions moved here automatically
```

- **`byid/`** — one directory per session UUID, always the authoritative location
- **`recent/`** — flat listing of sessions from the last 14 days, named for quick scanning
- **`archive/<YYYY>/`** — sessions older than 14 days, grouped by year

## Behavior

### Phase 1: Discover Sessions

1. **Resolve the session directory:**
   ```
   ~/.claude/projects/<escaped-project-path>/
   ```
   Use the current project path, escaped with `-` replacing `/`.

2. **List all `.jsonl` files** (no age filter — we need to find old ones to archive too).

3. **Create output directories** if they don't exist:
   ```
   /var/tumu/aid/sessions/byid/
   /var/tumu/aid/sessions/recent/
   /var/tumu/aid/sessions/archive/
   ```

### Phase 2: For Each Session, Check Summary Status

For each session `.jsonl` file:

1. **Read the session ID** from the filename (UUID stem).

2. **Check if `/var/tumu/aid/sessions/byid/<session-id>/summary.md` exists.**

3. **If summary does NOT exist** → go to Phase 3 (generate).

4. **If summary EXISTS:**
   - Compare the `mtime` of `summary.md` to the `mtime` of the `.jsonl` file
   - If `summary.md` mtime >= `.jsonl` mtime → **SKIP** (summary is current)
   - If `summary.md` mtime < `.jsonl` mtime → go to Phase 3 (regenerate)

### Phase 3: Generate Summary

For each session that needs a summary:

1. **Parse the `.jsonl` file** and extract:
   - `custom-title` → session name
   - `agent-setting` → which agent role was active
   - First few `type: "user"` messages where `message.content` is a string → what the human asked
   - `type: "assistant"` messages with `text` content blocks → what the agent did
   - Any `Edit` or `Write` tool uses → files that were modified
   - Any `Bash` tool uses with `git commit` → commits created
   - Timestamp of first and last message → session duration
   - **Counts for value assessment**: total human messages, total assistant text responses, total tool uses (Edit/Write/Bash), total files modified, total commits

2. **Derive the kebab-topic** from the session:
   - Use `custom-title` if present (kebab-case it: lowercase, spaces/special chars → hyphens, 2-5 words)
   - Otherwise derive from the first user message (extract the core subject, kebab-case it)
   - Fallback: `<agent>-session` (e.g., `engineer-session`, `default-session`)
   - If the name collides with an existing file in `recent/` or `archive/`, append `-2`, `-3`, etc.

3. **Determine the date prefix** from the session's **last-active timestamp** (the timestamp of the last message in the JSONL, NOT the time the summary is generated):
   - Format: `MM-DD` (e.g., `03-11`)
   - Full year `YYYY` is used for archive paths
   - If no timestamp is available, fall back to the `.jsonl` file's `mtime`

4. **Write `/var/tumu/aid/sessions/byid/<session-id>/summary.md`:**

   ```markdown
   # Session Summary

   | Field | Value |
   |-------|-------|
   | **Session ID** | `<full-uuid>` |
   | **Title** | <custom-title or first user message> |
   | **Agent** | <agent-setting or "(default)"> |
   | **Started** | <first message timestamp> |
   | **Last Active** | <last message timestamp> |
   | **Project** | <project path> |
   | **Topic** | `<MM-DD-kebab-topic>` |
   | **Value** | HIGH / MEDIUM / LOW |

   ## What Happened

   <2-5 sentence summary of the session's purpose and what was accomplished.
   Focus on: what was the goal, what was done, what was the outcome.>

   ## Key Actions

   - <Bullet list of significant actions taken>
   - <Files edited, commands run, commits created>
   - <Decisions made or knowledge discovered>

   ## Files Modified

   - `<path>` — <what changed>

   ## Resume Command

   ```bash
   claude --resume <session-id>
   ```
   ```

5. **Assess session value** — assign HIGH, MEDIUM, or LOW based on the extracted counts:

   **HIGH** — meaningful work was done:
   - Files were edited/written (any Edit or Write tool use), OR
   - Commits were created, OR
   - 5+ human messages AND 3+ substantive assistant text responses

   **MEDIUM** — useful exploration or research:
   - 3+ human messages with substantive assistant responses, OR
   - Multiple tool uses (reads, searches, MCP calls) showing real investigation, OR
   - A named session (`custom-title` exists) suggesting intentional work

   **LOW** — throwaway or trivial:
   - 0-2 human messages, OR
   - Only sanity checks, connectivity tests, or single tool calls, OR
   - Empty sessions, test sessions (`"test"`, `"call mcp__olai__sanity_check"`), OR
   - Session content is primarily command boilerplate (`<command-message>`, `<local-command-caveat>`)

6. **Keep summaries concise** — aim for under 50 lines. The goal is fast scanning, not full replay.

### Phase 4: Place in Recent or Archive

For each session with a summary:

1. **Determine age** from the session's last-active timestamp (or `.jsonl` mtime).

2. **If LOW value** — archive immediately regardless of age:
   - Create `/var/tumu/aid/sessions/archive/<YYYY>/` if it doesn't exist
   - Copy the summary to `/var/tumu/aid/sessions/archive/<YYYY>/<MM-DD-kebab-topic>.md`
   - If the session previously had a file in `recent/`, **remove it** from `recent/`

3. **If MEDIUM or HIGH value AND last active within the last 14 days:**
   - Copy (or symlink) the summary to `/var/tumu/aid/sessions/recent/<MM-DD-kebab-topic>.md`
   - If a file for this session already exists in `recent/`, overwrite it

4. **If MEDIUM or HIGH value AND last active more than 14 days ago:**
   - Create `/var/tumu/aid/sessions/archive/<YYYY>/` if it doesn't exist
   - Copy the summary to `/var/tumu/aid/sessions/archive/<YYYY>/<MM-DD-kebab-topic>.md`
   - If the session previously had a file in `recent/`, **remove it** from `recent/`

### Phase 5: Report

After processing all sessions, report:

```
Session consolidation complete
   Scanned:     <N> sessions
   Up-to-date:  <N> (skipped)
   Generated:   <N> (new summaries)
   Refreshed:   <N> (updated stale summaries)
   Recent:      <N> (HIGH/MEDIUM in recent/)
   Archived:    <N> (LOW value or older than 14 days)
```

## Key Rules

- **Do not modify `.jsonl` files** — they are read-only source data
- **`byid/` is the canonical location** — `recent/` and `archive/` are copies for browsability
- **Kebab-topic must be human-readable** — someone scanning `recent/` should understand what each session was about at a glance
- **Concise over complete** — summaries are for quick scanning, not transcript replay
- **Idempotent** — running twice with no session changes produces no new work
- **Archive is automatic** — anything older than 14 days moves to `archive/<YYYY>/` without user intervention
