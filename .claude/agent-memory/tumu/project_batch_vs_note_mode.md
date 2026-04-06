---
name: project_batch_vs_note_mode
description: Batch MML vs note_on scheduling — when to use each mode, known failure cases
type: project
---

Two audio scheduling modes exist for Strudel playback:

**Batch mode** (`strudel mode batch`): Compiles each cycle's notes into per-voice MML strings, feeds to SiON's sequencer via `sequence_on()`. Sample-accurate inter-note timing (~23μs). The default for simple patterns.

**Note mode** (`strudel mode note`): Per-note `note_on()` dispatch from Godot's `_process()` frame loop. ±8ms jitter (half-frame at 60fps). Used as fallback.

**Why this matters:** Batch mode's MML compiler uses `l<N>` (N equal-length notes per voice), which BREAKS on complex patterns with mixed note durations (like the 5-layer intro_dark/intro_light theme). The title music forces `batch_mode=false` before playing, then restores `batch_mode=true` after the cyclist starts.

**How to apply:**
- Title music (`_strudel_play_title()`) MUST use note mode — batch destroys its timing
- Simple drum/bass patterns work fine in batch mode
- If a pattern sounds wrong in batch mode, try `strudel mode note` to diagnose
- The mode switch is in `music_manager.gd:_strudel_play_title()` and `rcon.gd` (`strudel mode batch|note`)
- Both cyclist and trigger must have their `batch_mode` set together
