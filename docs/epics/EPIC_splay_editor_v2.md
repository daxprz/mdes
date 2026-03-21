# EPIC: Splay Editor V2 — Source Detection, Pose Management, Level References

## Overview

Enhance the splay system with source/development detection, proper save workflows (original vs custom), a full-featured pose library with usage tracking and CRUD, and graceful handling of missing pose references in levels.

## Dependencies

- `scripts/systems/splay_manager.gd` — pose loading/saving
- `scripts/ui/level_editor.gd` — SPLAY/SPLAY_EDIT modes
- `scripts/ui/pose_library.gd` — pose browser
- `scripts/autoload/level_config.gd` — level save/load
- `data/splay_poses/*.json` — bundled poses (source authority)

---

## STORY 1: Source Mode Detection

Detect whether the game is running from a development environment (source code) vs an exported build.

### Tasks

- [x] **1.1** Add `is_source_mode() -> bool` to a utility/autoload — returns `true` when running from the editor or from an unpackaged project directory
- [x] **1.2** Detection method: check `OS.has_feature("editor")` or if `res://` paths resolve to the filesystem (not packed)
- [x] **1.3** Visual indicator: small "DEV" badge in corner when in source mode

---

## STORY 2: Rename Current Splay to I-Pose

The current saved splay on the title screen level should be named "i-pose" (straight vertical, arms at sides).

### Tasks

- [x] **2.1** Rename the splay instance in the title_screen level config from "t-pose" to "i-pose"
- [x] **2.2** Create/rename the bundled pose file to `data/splay_poses/i-pose.json`
- [x] **2.3** Update the level config reference to use "i-pose"

---

## STORY 3: Splay Edit — Origin Tracking & Save Modes

The editor tracks which pose it was opened from and offers Save Original (source only) vs Save Custom.

### Tasks

- [x] **3.1** Track `_splay_edit_origin_pose_name: String` — the pose name the edit session started from
- [x] **3.2** On Ctrl+S: show save dialog with options:
  - **Save Original** (overwrites `res://data/splay_poses/{name}.json`) — only available in source mode
  - **Save Custom** (saves to `user://data/splay_poses/{name}.json` or prompts for new name)
- [x] **3.3** Save Original writes to the project's bundled `data/splay_poses/` directory (the source authority)
- [x] **3.4** Save Custom writes to `user://data/splay_poses/` (user override, already working)
- [x] **3.5** If not in source mode, only Save Custom is available — Save Original is greyed out
- [x] **3.6** Visual: save dialog shows which mode, pose name, and a text input for custom name

---

## STORY 4: Pose Library — Usage Tracking

The pose library shows which levels use each pose and how many times.

### Tasks

- [x] **4.1** On library open: scan all level configs (both bundled `res://levels/` and user `user://levels/`) for `"splays"` arrays
- [x] **4.2** Build a usage map: `{ pose_name: [{ level: "title_screen", count: 2 }, ...] }`
- [x] **4.3** Display usage in the library list: each pose entry shows "Used in: title_screen (1)" or "Unused"
- [x] **4.4** Unused poses shown dimmed

---

## STORY 5: Pose Library — CRUD Operations

Full create, read, update, delete operations on poses.

### Tasks

- [x] **5.1** **Add New Pose**: button/key creates a new empty pose with a prompted name, opens SPLAY_EDIT
- [x] **5.2** **Delete Pose**:
  - Custom poses (`user://`) — always deletable
  - Bundled poses (`res://`) — only deletable in source mode
  - Confirmation prompt before delete
  - If pose is in use: show warning with level list, require double-confirm
- [x] **5.3** **Edit Pose**: select and press Enter or E to open in SPLAY_EDIT
  - Source mode: edits the original
  - Non-source: creates a custom copy for editing
- [x] **5.4** **Rename Pose**: key to rename (creates new, copies data, deletes old) — source only for bundled

---

## STORY 6: Level Editor — Missing Pose References

Gracefully handle splay instances that reference poses which no longer exist.

### Tasks

- [x] **6.1** In SPLAY mode overlay: splay instances with missing poses drawn with RED outline instead of orange
- [x] **6.2** Label shows "MISSING: {pose_name}" in red
- [x] **6.3** On click/select a missing splay: open pose library in "replacement" mode
- [x] **6.4** Replacement mode: selecting a pose reassigns the splay instance to the new pose
- [x] **6.5** Delete option: key to remove the splay instance from the level entirely
- [x] **6.6** On level load: missing pose splays are skipped with a warning (no crash)

---

## Implementation Priority

1. **Story 1 (Source Detection)** — Foundation for save permissions
2. **Story 2 (I-Pose Rename)** — Quick fix
3. **Story 3 (Save Modes)** — Core editor workflow
4. **Story 4 (Usage Tracking)** — Library enhancement
5. **Story 5 (CRUD)** — Library management
6. **Story 6 (Missing References)** — Robustness

---

## Answered Questions

- **Save dialog UX**: Popup overlay with _O_riginal and _C_ustom buttons (underlined hotkeys, clickable). O only available in source mode.
- **Pose name validation**: Kebab-case alphanumeric (enforced by filter input).
- **I-pose**: Named for the body shape — vertical body (I stem) with arms/legs making the top/bottom serifs of the I. T-pose will be suspended by arms/neck.
