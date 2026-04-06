---
name: project_bus_level_effects
description: Bus-level audio effects limitation — lpf/hpf/reverb apply to ALL voices, not per-voice
type: project
---

All Strudel audio effects (.lpf(), .hpf(), .room(), .delay(), .distort(), .pan()) are applied to the Godot "Music" AudioBus, not per-voice. This means `.lpf(300)` on a bass line will also filter out hi-hats, cymbals, and everything else on the bus.

**Why:** Godot's AudioBus system doesn't support per-AudioStreamPlayer effect chains easily. SiON's internal `@f` MML commands could provide per-voice filtering but aren't wired up yet. This was discovered the hard way when `.lpf(300)` on a bass pattern killed all hi-hat frequencies — user said "I can only hear bass."

**How to apply:**
- When using `.lpf()` with drums+bass, keep cutoff above 400Hz to avoid killing highs
- `music fx reset` RCON command exists to recover from bad filter settings
- `music fx` / `music fx status` shows current state of all 6 bus effect slots
- Future fix: move filters into MML `@f` commands for per-voice, audio-thread-accurate filtering (Phase 2 of batch mode plan)
- The 6 effect slots: LPF (idx 0), HPF (1), Distort (2), Reverb (3), Delay (4), Pan (5)
- `MusicManager.reset_music_effects()` disables all slots and clears `_active_controls`
