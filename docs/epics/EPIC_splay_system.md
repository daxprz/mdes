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
  "breakaway_sound": "res://assets/sounds/quadruped_roar.wav",
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

- [x] **1.1** Create directory `res://data/splay_poses/` for pose JSON files
- [x] **1.2** New autoload or utility: `scripts/systems/splay_manager.gd` — loads all pose JSONs from `res://data/splay_poses/`, provides lookup by name
- [x] **1.3** `load_pose(name: String) -> Dictionary` — returns parsed pose data
- [x] **1.4** `get_all_pose_names() -> Array[String]` — list available poses
- [x] **1.5** `save_pose(pose: Dictionary)` — write pose JSON to `user://data/splay_poses/` (user override, same pattern as level configs)
- [x] **1.6** Create 3 starter poses: `t-pose` (spread wide), `hanging` (suspended from above), `pinned-flat` (pressed against wall)

---

## STORY 2: Splay Instance Spawning

Runtime system that spawns a creature, creates tethers from each connection point to the nearest surface, and IK-overrides the skeleton.

### Tasks

- [x] **2.1** `spawn_splay(pose_name: String, pos: Vector2, rotation: float, behavior: String)` function in `splay_manager.gd`
- [x] **2.2** Spawn the creature at `pos`, apply rotation to all connection relative positions and cast directions
- [x] **2.3** For each connection: raycast from `pos + rotated_relative_pos` in `rotated_cast_dir` until hitting a surface (collision layer 1). Create a tether from the attachment point to that surface hit point.
- [x] **2.4** Tether length = distance from connection point to surface hit (tight — no slack)
- [x] **2.5** If raycast misses (no surface in range), skip that connection and log a warning
- [x] **2.6** After all tethers created, set creature behavior:
  - `"active"`: set `_standdown = false` — creature wakes and fights against tethers
  - `"stand_down"`: set `_standdown = true`
  - `"asleep"`: set new `_asleep = true` flag — creature is dormant, skeleton runs but no AI. On any damage → set `_asleep = false`, `_standdown = false` (becomes active)
- [x] **2.7** IK override: set skeleton rest pose targets to the connection relative positions so the skeleton naturally settles into the splay shape (tethers reinforce this)

---

## STORY 3: Asleep Mode

New creature behavior: dormant until damaged.

### Tasks

- [x] **3.1** Add `_asleep: bool = false` flag to quadruped monster
- [x] **3.2** In `_physics_process`: if `_asleep`, skip AI (same as standdown) but also reduce breathing amplitude (barely alive look)
- [x] **3.3** In `take_damage` / `take_part_damage`: if `_asleep`, set `_asleep = false`, `_standdown = false` — creature wakes up and becomes fully active
- [x] **3.4** Visual indicator when asleep: closed eye (draw eye as a line instead of circles), "ZZZ" text fading in/out above head
- [x] **3.5** Audio: growl/roar sound on wake-up

---

## STORY 4: Skeleton IK Override for Poses

When splayed, the skeleton's rest pose targets shift to match the splay connection positions, pulling the creature into the desired shape.

### Tasks

- [x] **4.1** Add `_pose_overrides: Dictionary` to quadruped monster — maps attachment point names to target local positions
- [x] **4.2** When `_pose_overrides` is non-empty, `_solve_pose()` blends toward override positions instead of default rest poses
- [x] **4.3** Override strength: configurable blend factor (0.0 = natural, 1.0 = fully overridden). Default 0.8 so skeleton has slight organic movement.
- [x] **4.4** `set_pose_overrides(overrides: Dictionary)` public method — called by splay spawner
- [x] **4.5** `clear_pose_overrides()` — return to natural rest pose (e.g., when tethers break)
- [x] **4.6** When all tethers on a splayed creature are severed, auto-clear pose overrides so creature returns to natural pose

---

## STORY 5: Level Integration

Splay instances saved in level configs, auto-spawned when level loads.

### Tasks

- [x] **5.1** Add `"splays"` key to level config schema — array of splay instance objects
- [x] **5.2** On level load (title_screen.gd `_rebuild_from_config`), iterate `config["splays"]` and call `spawn_splay()` for each
- [x] **5.3** On level clear/rebuild, remove all splayed creatures and their tethers
- [x] **5.4** Splay instances survive `clear` RCON command (they're level fixtures, not spawned enemies) — or add a `clear_splays` command

---

## STORY 6: Splay Instance Editor Mode

New level editor mode for placing and configuring splay instances in a level.

### Tasks

- [x] **6.1** Add `SPLAY` to the editor `Mode` enum and `MODE_NAMES`/`MODE_COLORS`
- [x] **6.2** In SPLAY mode: click to place a new splay instance at mouse position
- [x] **6.3** Drag to reposition existing splay instances
- [x] **6.4** Rotate: mouse wheel or left/right arrows while selected to adjust rotation
- [x] **6.5** Cycle pose: up/down arrows or key to switch between available pose names
- [x] **6.6** Cycle behavior: key to toggle active/stand_down/asleep
- [x] **6.7** Delete: Delete/Backspace removes selected splay instance
- [x] **6.8** Draw overlay: show splay instance position (colored circle), rotation arrow, pose name label, behavior label, connection point markers with cast direction lines
- [x] **6.9** Preview: show ghost outline of the creature in the splay pose at the instance position
- [x] **6.10** Save: splay instances written to level config `"splays"` array on Ctrl+S

---

## STORY 7: Splay Pose Editor Mode

Editor mode for modifying the splay pose definition itself (connection points, relative positions, cast directions).

### Tasks

- [x] **7.1** Add `SPLAY_EDIT` to the editor `Mode` enum
- [x] **7.2** In SPLAY_EDIT mode: select a splay instance to edit its underlying pose
- [x] **7.3** Show the creature at the splay position with connection points drawn as draggable handles
- [x] **7.4** Drag a connection point handle to change its `relative_pos`
- [x] **7.5** Right-click drag on a connection point to change its `cast_dir` (draw an arrow showing the direction)
- [x] **7.6** Add connection: key to add a new connection point (cycles through available attachment points not yet used)
- [x] **7.7** Remove connection: Delete on selected connection point
- [x] **7.8** Cast direction preview: draw dotted line from connection point in cast direction, show where it would hit a surface
- [x] **7.9** Live preview: creature skeleton updates in real-time as you drag connection points
- [x] **7.10** Save: Ctrl+S in SPLAY_EDIT saves the pose to `user://data/splay_poses/{pose_name}.json`

---

## STORY 8: RCON Commands

Commands for testing splays without the editor.

### Tasks

- [x] **8.1** RCON: `splay list` — list all available pose names
- [x] **8.2** RCON: `splay spawn <pose> [x y] [rotation] [behavior]` — spawn a splay instance
- [x] **8.3** RCON: `splay clear` — remove all splay instances and their tethers
- [x] **8.4** RCON: `splay status` — show all active splay instances with positions, poses, behavior, tether count

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

## Answered Questions

- **Pose library UI**: YES — in-game browser for selecting/previewing poses. See Story 9.
- **Breakaway**: YES — dramatic animation + sound when all tethers severed. See Story 10.
- **Multiple creatures per splay**: YES — a splay can reference multiple creatures tethered to each other. See Story 11.

---

## STORY 9: Pose Library UI

In-game browser for browsing, previewing, and selecting splay poses.

### Tasks

- [x] **9.1** Pose library panel: overlay UI showing all available poses as a scrollable list/grid
- [x] **9.2** Each entry shows: pose name, creature type, connection count, thumbnail preview (small skeleton outline in the pose shape)
- [x] **9.3** Select a pose to see a full-size preview: creature skeleton drawn in the pose with connection points and cast direction arrows
- [x] **9.4** "Place" button: transitions to SPLAY editor mode with the selected pose ready to place
- [x] **9.5** "Edit" button: transitions to SPLAY_EDIT editor mode for the selected pose
- [x] **9.6** "New" button: create a blank pose from a template, auto-opens SPLAY_EDIT
- [x] **9.7** "Delete" button: remove a user-created pose (bundled poses can't be deleted)
- [x] **9.8** Accessible from level editor via a key (e.g., P for Pose library) while in SPLAY mode
- [x] **9.9** Filter/search: type to filter poses by name

---

## STORY 10: Breakaway — Dramatic Freedom

When a splayed creature breaks free (all tethers severed), play a dramatic animation and sound.

### Tasks

- [x] **10.1** Track aggregate tether durability per splay instance: sum all tether max HP = total durability. Sum all damage taken across tethers = total damage. When total damage > 50% of total durability → trigger breakaway (all tethers snap simultaneously).
- [x] **10.2** Breakaway sound: configurable per pose via `"breakaway_sound"` resource reference in the pose JSON (e.g., `"res://assets/sounds/monster_roar.wav"`). Fallback to a default chain-snap if not specified. Each creature type should have a unique default roar.
- [x] **10.3** Screen shake on breakaway (scaled by creature mass)
- [x] **10.4** Visual: tether snap particles burst outward from each former anchor point
- [x] **10.5** Visual: creature flashes bright for 0.3s, brief slow-motion (Engine.time_scale = 0.3 for 0.5s, then restore)
- [x] **10.6** Creature pose overrides cleared — skeleton springs back to natural rest pose (visible uncoiling/stretching)
- [x] **10.7** Creature automatically becomes active (regardless of previous behavior) — it's angry now
- [x] **10.8** Brief invincibility (0.5s) after breakaway so creature isn't immediately killed while uncoiling
- [x] **10.9** RCON: `splay breakaway <idx>` — force-trigger breakaway on a splayed creature for testing

---

## STORY 11: Multi-Creature Splay

A splay pose can reference multiple creatures, with connections between them and to the world.

### Tasks

- [x] **11.1** Pose format: `"creatures"` array instead of single `"creature"` field. Each entry has: `creature_type`, `offset` (relative to splay origin), `connections` array.
- [x] **11.2** Connections can target: `"world"` (raycast to surface, current behavior) or `"creature:<index>:<point>"` (tether to another creature's attachment point)
- [x] **11.3** Spawn all creatures in the splay, then create tethers: world tethers raycast to surfaces, inter-creature tethers connect attachment points directly
- [x] **11.4** Inter-creature tether length = distance between the two attachment points at pose time (tight)
- [x] **11.5** Breakaway: if ALL tethers on ALL creatures in the splay are severed, trigger breakaway for all. Partial break (one creature free, others still tethered) = only the freed creature wakes.
- [x] **11.6** SPLAY editor: show multiple creature outlines, drag each independently. Connection lines drawn between creatures.
- [x] **11.7** Pose library: thumbnail shows all creatures in the multi-creature arrangement
- [x] **11.8** Behavior is per-creature within the splay (one could be asleep, another active)

---

## Updated Implementation Priority

1. **Story 1 (Data Format)** — Foundation
2. **Story 3 (Asleep Mode)** — Simple flag
3. **Story 2 (Spawning)** — Core mechanic
4. **Story 4 (IK Override)** — Visual pose
5. **Story 8 (RCON)** — Test without editor
6. **Story 10 (Breakaway)** — Dramatic payoff
7. **Story 5 (Level Integration)** — Persistence
8. **Story 6 (Instance Editor)** — Place splays
9. **Story 7 (Pose Editor)** — Edit poses
10. **Story 9 (Pose Library)** — Browse/preview
11. **Story 11 (Multi-Creature)** — Advanced feature
