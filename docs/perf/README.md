# Performance Documentation

Lessons learned, tools built, and reference data for tracking down and fixing performance issues in DAX.

## Contents

| Document | Purpose |
|----------|---------|
| [perf_monitor.md](perf_monitor.md) | How to use the Performance Monitor (FPS overlay, RCON commands, snapshots) |
| [monster_profiler.md](monster_profiler.md) | Section profiler in `quadruped_monster.gd` — what each probe measures, how to read results |
| [spike_investigation.md](spike_investigation.md) | Case study: tracking down the 450ms precog spike — methodology, data, fix |
| [godot_perf_reference.md](godot_perf_reference.md) | Godot Performance singleton monitors, threading constraints, renderer differences |
| [known_costs.md](known_costs.md) | Measured baseline costs and budgets for the major systems |
