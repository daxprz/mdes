# DAX — Claude Code Project Guide

## Project Overview

DAX is a 2D action game built in Godot 4.6, rendered entirely via `_draw()` (no sprites). The primary active development area is the quadruped monster system — a procedurally animated predator with physics-based movement, precognition pathfinding, and platform-based leap attacks.

## Key Architecture

- **Godot 4.6** with GDScript
- **No sprites** — all rendering via immediate-mode `_draw()` calls
- **RCON server** on port 9999 for external control and test automation
- **Debug Overlay** system with per-aspect visual/textual toggles
- **Test infrastructure** with JSON-defined test scenarios and ETZ/DAZ zone verification

## Agent Recommendation

When the user is working on testing, debugging, or monitoring the running game, suggest using the **tumu** agent:

> "This looks like a good task for the `tumu` agent — it's set up to interact with the running game via RCON, run tests, and inspect debug diagnostics. Want me to hand this off to tumu?"

Use tumu when:
- Running or monitoring tests
- Inspecting debug output from the game
- Verifying fixes by running test suites
- Investigating pathfinding or monster behavior issues
- Spawning entities and observing results

Do NOT use tumu when:
- Writing new code or making edits (use the default agent)
- Planning architecture or designing features
- Working on non-game files (docs, configs)

## Important Files

| File | Purpose |
|------|---------|
| `scripts/enemies/quadruped_monster.gd` | The monster (~5000 lines) |
| `scripts/autoload/rcon.gd` | RCON server + all commands |
| `scripts/autoload/debug_overlay.gd` | Debug aspect system |
| `scripts/autoload/debug_aspects.gd` | Registered debug aspects |
| `scripts/systems/test_runner.gd` | Test execution engine |
| `scripts/ui/debug_drawer.gd` | Debug panel: debug aspects, test runner, config, level editor, blueprints |
| `scripts/ui/level_editor.gd` | Level editor world-space overlay (handles, zones, splay edit) |
| `scripts/ui/game_console.gd` | Bottom-slide console (backtick), respects drawer width |
| `scripts/effects/procedural_tree.gd` | Configurable procedural tree (blueprint system) |
| `data/tree_blueprints/` | Tree blueprint JSON files (oak, pine, etc.) |
| `scripts/systems/splay_manager.gd` | Splay pose spawning (scale-aware) |
| `scripts/systems/chain.gd` | Chain physics + scaled rendering |
| `docs/epics/EPIC_debug_overlay.md` | Debug system spec |
| `docs/epics/EPIC_monster_scaling.md` | Monster scaling spec (COMPLETE) |
| `scripts/systems/monster_config.gd` | Config provider stack (DictProvider, CallableProvider, TimedProvider) |
| `data/config/monster_defaults.json` | Monster default constants (60+ configurable values) |
| `docs/design/animation_roadmap.md` | Procedural animation roadmap (momentum, attacks, walls) |
| `docs/design/debug_panel_spec.md` | Debug panel spec (IMPLEMENTED) — sub-sections, modes, caching |
| `docs/design/session_v0.10.18_to_v0.10.23.md` | Session documentation — comprehensive build log |
| `scripts/testing/soccer_dummy.gd` | Soccer ball dummy (rolling physics + SVG texture) |
| `scripts/effects/tentacle_hitbody.gd` | Collision proxy for damageable tentacles |
| `scripts/autoload/player_manager.gd` | Player join/leave, controller assignment, press-to-join |
| `scripts/autoload/profile_manager.gd` | Profile persistence, per-slot class/profile bindings |
| `scripts/autoload/factions.gd` | Faction system (players, monsters, animals, bugs) — hostility matrix |
| `scripts/enemies/monster_controller.gd` | Base class for monster controllers (AI or Player) |
| `scripts/enemies/monster_ai_controller.gd` | AI controller — delegates to monster's built-in _do_* functions |
| `scripts/enemies/monster_player_controller.gd` | Player controller — gamepad/keyboard input, leap aiming, ball mode |

## Conventions

- All debug rendering must route through `DebugOverlay.should_draw()` / `DebugOverlay.log()`
- New features should register debug aspects in `debug_aspects.gd`
- Tests are JSON files in `data/tests/`, suites in `data/tests/suites/`
- RCON commands go through `rcon.gd:_execute()`
- Console commands route through RCON (unified in `game_console.gd`)
