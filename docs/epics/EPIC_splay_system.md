# EPIC: Splay Pose System

## Overview

A system for positioning creatures in pre-defined poses, tethered to the world. Splay poses define connection points with cast directions; splay instances place posed creatures in levels. Tethers auto-create on spawn, pulling the creature's skeleton into the target pose via IK override. Creatures can be active, standing down, or asleep after tethering.

## Concepts

### Splay Pose (Definition)
A reusable template describing how a creature should be spread/positioned. Stored as JSON in `res://data/splay_poses/`.

```json
{
  "name": "t-pose",
  "creature": "quadruped",
  "connections": [
    {
      "point": "head",
      "relative_pos": [0, -60],
      "cast_dir": [0, -1]
    },
    {
      "point": "tail_tip",
      "relative_pos": [0, 80],
      "cast_dir": [0, 1]
    },
    {
      "point": "shoulders",
      "relative_pos": [-50, 0],
      "cast_dir": [-1, 0]
    },
    {
      "point": "waist",
      "relative_pos": [50, 0],
      "cast_dir": [1, 0]
    }
  ]
}
```

- **name**: kebab-case identifier (e.g., `t-pose`, `l-to-r`, `spread-eagle`, `hanging`)
- **creature**: which creature type this pose applies to (currently only `quadruped`)
- **connections[].point**: attachment point ID on the creature (`head`, `tail_tip`, `shoulders`, `waist`)
- **connections[].relative_pos**: target position of this point relative to the creature's origin — the skeleton IK-overrides toward this position
- **connections[].cast_dir**: normalized direction to raycast outward from the connection point until hitting a surface. That surface becomes the tether's wall anchor.

### Splay Instance (In-Level Placement)
A specific placed creature in a level. Stored inside the level's JSON config under a `"splays"` key.

```json
{
  "splays": [
    {
      "pose": "t-pose",
      "creature": "quadruped",
      "pos": [960, 500],
      "rotation": 0,
      "behavior": "asleep"
    }
  ]
}
```

- **pose**: references a splay pose by name
- **creature**: creature type to spawn
- **pos**: world position [x, y]
- **rotation**: 0-360 degrees, rotates the entire pose around the origin
- **behavior**: what the creature does after tethering completes
  - `"active"` — wake the creature (it will fight against tethers)
  - `"stand_down"` — keep in stand-down mode (passive, receives damage)
  - `"asleep"` — new mode: dormant until damaged, then becomes active

---

## STORY 1: Splay Pose Data Format

Define the JSON schema and loading system for splay poses.

### Tasks

- [ ] **1.1** Create directory `res://data/splay_poses/` for pose JSON files
- [ ] **1.2** New autoload or utility: `scripts/systems/splay_manager.gd` — loads all pose JSONs from `res://data/splay_poses/`, provides lookup by name
- [ ] **1.3** `load_pose(name: String) -> Dictionary` — returns parsed pose data
- [ ] **1.4** `get_all_pose_names() -> Array[String]` — list available poses
- [ ] **1.5** `save_pose(pose: Dictionary)` — write pose JSON to `user://data/splay_poses/` (user override, same pattern as level configs)
- [ ] **1.6** Create 3 starter poses: `t-pose` (spread wide), `hanging` (suspended from above), `pinned-flat` (pressed against wall)

---

## STORY 2: Splay Instance Spawning

Runtime system that spawns a creature, creates tethers from each connection point to the nearest surface, and IK-overrides the skeleton.

### Tasks

- [ ] **2.1** `spawn_splay(pose_name: String, pos: Vector2, rotation: float, behavior: String)` function in `splay_manager.gd`
- [ ] **2.2** Spawn the creature at `pos`, apply rotation to all connection relative positions and cast directions
- [ ] **2.3** For each connection: raycast from `pos + rotated_relative_pos` in `rotated_cast_dir` until hitting a surface (collision layer 1). Create a tether from the attachment point to that surface hit point.
- [ ] **2.4** Tether length = distance from connection point to surface hit (tight — no slack)
- [ ] **2.5** If raycast misses (no surface in range), skip that connection and log a warning
- [ ] **2.6** After all tethers created, set creature behavior:
  - `"active"`: set `_standdown = false` — creature wakes and fights against tethers
  - `"stand_down"`: set `_standdown = true`
  - `"asleep"`: set new `_asleep = true` flag — creature is dormant, skeleton runs but no AI. On any damage → set `_asleep = false`, `_standdown = false` (becomes active)
- [ ] **2.7** IK override: set skeleton rest pose targets to the connection relative positions so the skeleton naturally settles into the splay shape (tethers reinforce this)

---

## STORY 3: Asleep Mode

New creature behavior: dormant until damaged.

### Tasks

- [ ] **3.1** Add `_asleep: bool = false` flag to quadruped monster
- [ ] **3.2** In `_physics_process`: if `_asleep`, skip AI (same as standdown) but also reduce breathing amplitude (barely alive look)
- [ ] **3.3** In `take_damage` / `take_part_damage`: if `_asleep`, set `_asleep = false`, `_standdown = false` — creature wakes up and becomes fully active
- [ ] **3.4** Visual indicator when asleep: closed eye (draw eye as a line instead of circles), "ZZZ" text fading in/out above head
- [ ] **3.5** Audio: growl/roar sound on wake-up

---

## STORY 4: Skeleton IK Override for Poses

When splayed, the skeleton's rest pose targets shift to match the splay connection positions, pulling the creature into the desired shape.

### Tasks

- [ ] **4.1** Add `_pose_overrides: Dictionary` to quadruped monster — maps attachment point names to target local positions
- [ ] **4.2** When `_pose_overrides` is non-empty, `_solve_pose()` blends toward override positions instead of default rest poses
- [ ] **4.3** Override strength: configurable blend factor (0.0 = natural, 1.0 = fully overridden). Default 0.8 so skeleton has slight organic movement.
- [ ] **4.4** `set_pose_overrides(overrides: Dictionary)` public method — called by splay spawner
- [ ] **4.5** `clear_pose_overrides()` — return to natural rest pose (e.g., when tethers break)
- [ ] **4.6** When all tethers on a splayed creature are severed, auto-clear pose overrides so creature returns to natural pose

---

## STORY 5: Level Integration

Splay instances saved in level configs, auto-spawned when level loads.

### Tasks

- [ ] **5.1** Add `"splays"` key to level config schema — array of splay instance objects
- [ ] **5.2** On level load (title_screen.gd `_rebuild_from_config`), iterate `config["splays"]` and call `spawn_splay()` for each
- [ ] **5.3** On level clear/rebuild, remove all splayed creatures and their tethers
- [ ] **5.4** Splay instances survive `clear` RCON command (they're level fixtures, not spawned enemies) — or add a `clear_splays` command

---

## STORY 6: Splay Instance Editor Mode

New level editor mode for placing and configuring splay instances in a level.

### Tasks

- [ ] **6.1** Add `SPLAY` to the editor `Mode` enum and `MODE_NAMES`/`MODE_COLORS`
- [ ] **6.2** In SPLAY mode: click to place a new splay instance at mouse position
- [ ] **6.3** Drag to reposition existing splay instances
- [ ] **6.4** Rotate: mouse wheel or left/right arrows while selected to adjust rotation
- [ ] **6.5** Cycle pose: up/down arrows or key to switch between available pose names
- [ ] **6.6** Cycle behavior: key to toggle active/stand_down/asleep
- [ ] **6.7** Delete: Delete/Backspace removes selected splay instance
- [ ] **6.8** Draw overlay: show splay instance position (colored circle), rotation arrow, pose name label, behavior label, connection point markers with cast direction lines
- [ ] **6.9** Preview: show ghost outline of the creature in the splay pose at the instance position
- [ ] **6.10** Save: splay instances written to level config `"splays"` array on Ctrl+S

---

## STORY 7: Splay Pose Editor Mode

Editor mode for modifying the splay pose definition itself (connection points, relative positions, cast directions).

### Tasks

- [ ] **7.1** Add `SPLAY_EDIT` to the editor `Mode` enum
- [ ] **7.2** In SPLAY_EDIT mode: select a splay instance to edit its underlying pose
- [ ] **7.3** Show the creature at the splay position with connection points drawn as draggable handles
- [ ] **7.4** Drag a connection point handle to change its `relative_pos`
- [ ] **7.5** Right-click drag on a connection point to change its `cast_dir` (draw an arrow showing the direction)
- [ ] **7.6** Add connection: key to add a new connection point (cycles through available attachment points not yet used)
- [ ] **7.7** Remove connection: Delete on selected connection point
- [ ] **7.8** Cast direction preview: draw dotted line from connection point in cast direction, show where it would hit a surface
- [ ] **7.9** Live preview: creature skeleton updates in real-time as you drag connection points
- [ ] **7.10** Save: Ctrl+S in SPLAY_EDIT saves the pose to `user://data/splay_poses/{pose_name}.json`

---

## STORY 8: RCON Commands

Commands for testing splays without the editor.

### Tasks

- [ ] **8.1** RCON: `splay list` — list all available pose names
- [ ] **8.2** RCON: `splay spawn <pose> [x y] [rotation] [behavior]` — spawn a splay instance
- [ ] **8.3** RCON: `splay clear` — remove all splay instances and their tethers
- [ ] **8.4** RCON: `splay status` — show all active splay instances with positions, poses, behavior, tether count

---

## Implementation Priority

1. **Story 1 (Data Format)** — Foundation: pose JSON schema + loader
2. **Story 3 (Asleep Mode)** — Simple monster flag, needed for behavior options
3. **Story 2 (Spawning)** — Core: spawn + tether + behavior
4. **Story 4 (IK Override)** — Visual: creature actually holds the pose shape
5. **Story 8 (RCON)** — Test everything without editor
6. **Story 5 (Level Integration)** — Persistence in level configs
7. **Story 6 (Instance Editor)** — Place splays in the editor
8. **Story 7 (Pose Editor)** — Edit poses visually

---

## Key Files (New + Modified)

| File | Status | Purpose |
|------|--------|---------|
| `scripts/systems/splay_manager.gd` | **New** | Pose loading, splay spawning, instance management |
| `data/splay_poses/*.json` | **New** | Splay pose definitions |
| `scripts/enemies/quadruped_monster.gd` | Modified | Asleep mode, pose overrides, IK blend |
| `scripts/ui/level_editor.gd` | Modified | SPLAY and SPLAY_EDIT editor modes |
| `scripts/ui/title_screen.gd` | Modified | Spawn splays from level config on load |
| `scripts/autoload/rcon.gd` | Modified | Splay RCON commands |
| `levels/*.json` | Modified | Add `"splays"` array to level configs |

---

## On Godot's Built-In Pose/Animation Systems

The project's procedural skeleton (23 Vector2 points with spring physics) is incompatible with Godot's `Skeleton2D`/`Bone2D`/`AnimationPlayer` pipeline, which expects node-based bone hierarchies. Godot's `Animation` resource stores keyframed transforms for specific node paths — not applicable to arrays of Vector2.

The correct Godot-idiomatic approach for this custom skeleton is:
- **Poses as JSON** (consistent with the project's existing config system)
- **Runtime IK override** via blend targets (consistent with the existing spring-based pose solver)
- If a full `Skeleton2D` migration happens in the future, poses could be converted to `Animation` resources at that time

---

## Open Questions

- **Pose library UI**: Should there be an in-game browser for selecting poses, or is the editor sufficient?
- **Breakaway**: When a splayed creature breaks free (all tethers severed), should there be a dramatic animation/sound?
- **Multiple creatures per splay**: Could a splay instance reference multiple creatures (e.g., two monsters tethered to each other in a pose)?
