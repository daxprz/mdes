# Performance Monitor

The FPS overlay (`scripts/ui/fps_overlay.gd`, autoload `FPSOverlay`) is the primary tool for diagnosing performance issues at runtime.

## Enabling

```
debug on perf/fps           # Show the overlay
debug log perf/snapshot_log # Enable auto-spike logging to stdout
```

Or via RCON:
```
perf                        # Show current status text
perf compact                # Switch to compact mode (FPS number + mini graph)
perf expanded               # Switch to expanded mode (all metrics)
perf snapshot               # Dump full snapshot to stdout NOW
perf reset                  # Clear spike counter and peak data
```

## Modes

### Compact
Bottom-right corner: FPS number, mini graph (200 frames), spike counter. Click to expand.

### Expanded
Full metrics panel with groups:

| Group | Metrics |
|-------|---------|
| **Timing** | Process time, Physics time, Navigation time |
| **Objects** | Total objects, nodes, orphan nodes, resources |
| **Rendering** | Draw calls, render objects, primitives |
| **Memory** | Static memory, peak memory, message buffer |
| **Entities** | Enemies, players, loose items, dummies, chains, tethers |
| **Pool** | Acquires, misses, idle count |

Each metric shows current value and delta-from-60-frames-ago. Color coding:
- **White** — normal
- **Yellow** — warning threshold exceeded
- **Red** — alert threshold exceeded

## Auto-Spike Detection

When FPS drops below **40** (configurable `LAG_SPIKE_THRESHOLD`), the monitor automatically captures a snapshot. A **5-second cooldown** (`LAG_SPIKE_COOLDOWN`) prevents the snapshot itself from inducing a spike cascade.

Auto-snapshots are logged to stdout with the header:
```
PERF SNAPSHOT -- AUTO-SPIKE #N (X FPS) -- timestamp
```

## Manual Snapshots

Press **Spacebar** when the perf panel is visible, or use RCON `perf snapshot`.

## Snapshot Contents

A full snapshot includes:

1. **FPS stats** — current, average, min, sample count, spike count
2. **All Performance monitors** — grouped by category with delta and alert flags
3. **Entity census** — every enemy, player, loose item, chain, tether with:
   - Name, node path, position, HP, state
   - Process flags (`[FROZEN]` if both process and physics disabled, `[NO_PHYSICS]` if physics disabled, `[HIDDEN]` if not visible)
   - **Section profiler data** for monsters (see [monster_profiler.md](monster_profiler.md))
4. **Object Pool stats** — if ObjectPool autoload is registered
5. **Music system status** — composition, section, transition state, active notes

## Reading Snapshots

Key patterns to look for:

| Symptom | Look at |
|---------|---------|
| FPS drops during monster action | Monster section profiler — which section has a high peak? |
| FPS drops with no monster | Process time + Draw Calls — rendering overhead |
| Memory climbing | Static Mem delta, Object count delta — leak? |
| Stutter on level load | Objects delta, Nodes delta — scene tree churn |
| Physics spike | Physics time + monster `move_slide` / `chain_clamp` probes |

## Tips

- The snapshot captures the **instant** the spike is detected, not the frame that caused it. The spike frame already happened — the snapshot shows the aftermath plus **peak** values accumulated since last reset.
- Reset peaks with `perf reset` before a specific test to isolate that test's peaks.
- Auto-spike snapshots include peaks from ALL prior frames since last reset. Manual snapshots do too. Always reset before investigating a specific scenario.
