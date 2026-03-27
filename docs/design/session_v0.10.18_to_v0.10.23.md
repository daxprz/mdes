# Session Documentation: v0.10.18 through v0.10.23

## Overview

This session built 6 releases (v0.10.18 - v0.10.23) covering a major overhaul of the debug panel's test runner, new gameplay mechanics, player system improvements, and extensive UI polish. Total: +3287/-965 lines across 39 files.

---

## 1. Docked Test Editor (v0.10.18)

### What was built
Replaced the floating test editor window with a docked version inside the debug panel.

### Architecture
The test editor (`test_editor.gd`) remains as the **data/logic layer** — it manages scripts, handles, world-space overlay, run/save/load, and result collection. The debug drawer (`debug_drawer.gd`) renders the docked UI by querying the test editor's state and forwarding interactions.

### Sub-section Framework
Five collapsible, resizable sub-sections within the Test Runner panel:

| Section | Purpose | Content |
|---------|---------|---------|
| **Suites** | Suite list | Selectable list with pass/fail dots, play buttons, score |
| **Tests** | Test list | Filtered by selected suite, numbered, pass/fail dots, play/pause buttons |
| **Controls** | Buttons | Play, Stop, Restart, Save, +dis, +fence, suite nav |
| **Status** | Results | Run status, summary, per-check detail log |
| **Editor** | Script | Line numbers, status indicators, soft-wrap, inline edit field |

### Sub-section Resizing
- **Split-pane**: Grip dots resize the section above; Editor absorbs the change
- **Min heights**: Each section has a minimum that can't be violated
- **Snap points**: Content-based preferred heights. Dashed cyan line visible during drag. Snaps on release within 12px. Double-click grip to snap.
- **Auto-snap on load**: All sections snap to preferred heights after layout loads
- **Editor fills remaining space**: Always extends to the bottom of the panel

### Header Bars
Each sub-section header shows contextual information:
- **Tests**: Selected suite name
- **Controls**: Test name + EDIT/EXEC/INSPECT mode label
- **Status**: Test name
- **Editor**: Test name + modified indicator (●) + save button (💾) + approve-all-deletes (✕)

### Files Changed
- `scripts/ui/debug_drawer.gd` — +1916 lines (the bulk of the docked UI)
- `scripts/ui/test_editor.gd` — Floating window code removed (-559 lines), `_docked` flag always true
- `scripts/autoload/rcon.gd` — `_ensure_test_editor` always docks, `_get_debug_drawer` simplified

---

## 2. Three Editor Modes (v0.10.21)

### EDIT Mode (green)
- Full editing: click to select rows, inline edit field with cursor
- Line insertion (green triangle + "+" on left between rows)
- Pending deletion (✕ → red strikeout → ↶ undo / bold ✕ confirm)
- Comment toggle (# button on hover)
- Save button in header bar when modified

### EXECUTE Mode (orange)
- Read-only during test execution
- Running line highlighted with ● indicator
- No edit field, no insertion, no deletion

### INSPECT Mode (blue)
- Click rows to view their check detail in the Status pane
- Blue selection highlight
- Comment and delete buttons still available
- No edit field
- Auto-entered after test results arrive or cached results load

### Mode Flow
```
EDIT → (run test) → EXECUTE → (results arrive) → INSPECT
INSPECT → (load new test) → EDIT or INSPECT (if cached results exist)
```

---

## 3. Script Editor Features

### Soft-Wrap
Long lines wrap at natural sub-command boundaries with ↵ indicators.

**Priority order** (highest first):
1. **Boundary commands** (`unless`, `check`) — earliest match (one clause per line)
2. **Label/extract** (`label:`, `extract:`) — latest match
3. **Comparisons** (`>`, `<`, `=`) — latest match
4. **Any space** — fallback
5. **Hard character wrap** — absolute last resort

Continuation lines are indented 8px. First line uses full width, continuation lines use narrower width.

### Variable Row Heights
Each script row calculates its pixel height from soft-wrap line count. All click/hover detection uses cumulative variable heights.

### Inline Edit Field
- Auto-sizes to fit soft-wrapped content (minimum 32px)
- Same wrap algorithm as script rows
- Click anywhere in the edit area to focus (takes priority over row selection behind it)

### Line Insertion
- Green right-pointing triangle with "+" appears on the left between rows when hovering near boundaries (±4px)
- Click to insert a blank line, auto-selects and focuses edit field
- Only in EDIT mode

### Pending Deletion
- Clicking ✕ marks line as pending delete (red strikeout background + dimmed text)
- Two buttons appear: ↶ (undo, blue) and bold ✕ (confirm, bright red)
- Approve-all button in Editor header bar when any deletes are pending
- Index adjustment when lines are inserted/deleted with pending deletes

### Comment Toggle
- `#` button appears on hover (left of ✕)
- Toggles `# ` prefix on the line
- Green when line is commented, grey when not
- Works in both EDIT and INSPECT modes

### Save/Diff Detection
- `_disk_hash` stores the hash of the on-disk version when a test loads
- `is_modified_from_disk()` compares current editor content against disk hash
- Yellow ● indicator + 💾 save button in Editor header when modified
- Save writes to `res://data/tests/<name>.json` (git-tracked source file)

---

## 4. Test Result Caching (v0.10.21-22)

### Script Hash System
- `_compute_script_hash(script)` — deterministic hash of the test script content
- Stored in `results.json` as `"script_hash"` when a test runs
- On load, the current script hash is compared against saved results
- If hashes match, results auto-load (pass/fail indicators, detail log, summary)
- Edit-aware: changing the script invalidates cached results; changing it back revalidates

### Cross-Version Persistence
- `/ship-it` copies latest test results from old version to new version directory
- `find_latest_results()` searches only the current version (fast, single directory)
- Hash validation ensures copied results are still valid after code changes

### Startup Scan
- On first open of the test runner, ALL tests are scanned for cached results
- Each test's on-disk script hash is computed and compared against saved results
- Pass/fail dots pre-populated immediately
- Suite scores aggregated from constituent test results

### Suite Auto-Recompute
- When any individual test result changes, all suites containing that test recompute their passed/total
- Suite indicators update in real time without running the suite

---

## 5. Entity Selection System (v0.10.19)

### Generic Selection
- Config panel lists ALL entities (enemies + players + dummies), deduplicated
- Click any entity to select — works for monsters, bats, players, dummies
- 1-indexed numbers in the entity list correlate with in-world indicators

### World-Space Selection Overlay
- `_draw_selection_overlay()` in a world-space `Node2D` child of the scene
- Pulsing cyan circle + 1-indexed number for the selected entity
- Floating info box with line pointing to entity showing: type, ID, position, HP, state, velocity, scale, chain status
- Renders for ANY entity type — not monster-specific

### Config Panel Redesign
- **Search filter** at top — type to filter config keys
- **Entity list** — all entities with ID, type, 1-indexed number
- **Type-adaptive config**: monsters get `cfg()` sliders, other entities show script properties

### Debug Aspect Tree Fix
- Click/hover detection was using hardcoded `HEADER_HEIGHT` (160px)
- Changed to dynamically calculated `_tree_y_start` set each frame during drawing
- V/T checkbox clicks now always hit the correct row

---

## 6. Gameplay Features (v0.10.18)

### Chain Daze (`CHAIN_DAZE` state)
When a chained monster leaps beyond its chain's reach:
1. **Yank**: Position clamped to chain boundary, velocity reversed. Monster takes 30 damage, chain takes 25 damage + violent shake
2. **Falling** (phase 0): Ragdoll — limbs dangle, tail droops, skull drops
3. **Dazed** (phase 1, 5s): Lying flat on ground. 5 sparkly 4-pointed stars circle the head in elliptical, undulating pattern
4. **Standing up** (phase 2, 2s): Spine and limbs lerp from collapsed to upright
5. **Recovery**: Returns to CHASE with 2x leap cooldown

### Soccer Ball Dummy
- `spawn dummy` creates a rolling soccer ball (Wikipedia Telstar SVG → PNG texture)
- `Sprite2D` rotates based on rolling physics: `angular_vel = linear_vel / radius`
- Bounce (50% energy), ground friction (0.97), air friction (0.998)
- Takes damage, applies knockback, has 1000 HP

### Balloon Chain Explosions
- Popping a balloon triggers nearby balloons within 80px with 0.12s staggered delay
- Every pop spawns a 3-layer expanding fireball (white flash → orange ring → red outer ring + sparks)
- 20 damage to enemies + 10 friendly fire per pop
- `_popping` guard prevents infinite chain loops

### Melee Ground Slam Pops Balloons
- During downward slam, checks for nearby balloons each frame
- Pops them on contact without stopping the slam

### Damageable Tentacles
- `CharacterBody2D` hitbody on collision layer 8 follows tentacle tip
- `tentacle_hitbody.gd` forwards `take_damage()` to parent tentacle
- 30 HP when free (phases 0-2), damage flash on hit, death smoke on kill
- When attached (phase 3), routes through existing sub-health system

### Chains Damageable by All Weapons
- `_check_melee_hits()` in `chain.gd` detects player `attack_area` overlapping chain segments
- 8 damage per hit with shake + sound feedback

### `kill` RCON Command
- Deals 99999 damage to all enemies (triggers death sequence, unlike `clear`)

### `check no_leaps` Test Check
- Verifies monster has zero planned leap edges (used in chain constraint tests)

---

## 7. Player System Improvements (v0.10.18)

### Press-to-Join Controllers
- No auto-join on startup — players press a button to claim the next slot
- Per-slot persistence: class and profile saved per player slot (not per controller)
- Mid-game disconnect reserves the slot; reconnect auto-reattaches

### Controller Identification
- `_get_controller_name()` uses `Input.get_joy_guid()` (hardware UUID)
- For identical controllers (same GUID), appends stable sub-index
- Bindings saved to `user://controller_bindings.json`

### Player Debug Migration
Old `_debug_mode` flag replaced by `DebugOverlay` aspects:
- `player/velocity_arrows` — current velocity + predicted jump arrows
- `player/jump_tracers` — lingering jump impulse snapshots
- `player/archer_arcs` — archer aim arc + arrow trail rendering
- `player/reticle_info` — reticle position text
- `player/button_state` — HUD button state labels

### Hitbox Debug Aspects
- `hitboxes/monster_parts` — colored circles for head, body, tail, legs, eye
- `hitboxes/player_attack` — attack area rectangle when swinging

### Debug Auto-Disabled on Level Start
- `_disable_debug_on_level_start()` called in `go_to_overworld()` and `go_to_tower()`
- Turns off `DebugOverlay.global_enabled`, closes debug drawer

---

## 8. UI Cleanup (v0.10.23)

### Static Entity Info Removed
- Eliminated ~45 lines of the left/right positioned state text panel from `quadruped_monster.gd`
- Only the generic following overlay in the debug drawer remains

### Test Menu Streamlined (Ctrl+T)
Removed 8 obsolete test suite entries. Reorganized into:
- **Spawn**: Monster (standdown/active), Dummy, Monster Fight
- **Actions**: Kill All, Clear, Territorial, Revive, Enable Joins
- **Level**: Clear Level, Restart Level

### RCON Help Updated
- All commands listed with descriptions in the `help` output

---

## 9. Commands Created

### `/godot restart`
Kill and relaunch the Godot instance, wait for RCON.

### `/rca-test-failures`
Iterative failure triage: populate TODO suite → run → RCA each failure → fix → evict → repeat → re-run gates.

### `/ship-it` Updated
Added step 4: copy test results forward from old version to new version directory after version bump.

---

## 10. Files Summary

| Category | Files | Lines Changed |
|----------|-------|---------------|
| Debug Drawer | `debug_drawer.gd` | +1916 |
| Test Editor | `test_editor.gd` | -559 (removed floating window) |
| Test Runner | `test_runner.gd` | +110 (hash, caching, no_leaps) |
| Monster | `quadruped_monster.gd` | +276/-95 (chain daze, hitbox debug, remove static info) |
| RCON | `rcon.gd` | +203 (kill, help, deferred runs, drawer lookup) |
| Player | `player_side.gd` | +178/-153 (debug migration, balloon pop, hitbox) |
| Balloon | `balloon_dart.gd` | +131 (chain explosions, fireball blast) |
| Profile | `profile_manager.gd` | +81 (slot persistence, GUID) |
| Player Manager | `player_manager.gd` | +72 (press-to-join, reconnect) |
| New Files | `soccer_dummy.gd`, `tentacle_hitbody.gd`, `godot.md`, `rca-test-failures.md` | +198 |
| Tests | `chained_leap_bounds.json`, suite updates | +40 |
| Docs | README, EPIC, design docs | +124 |
