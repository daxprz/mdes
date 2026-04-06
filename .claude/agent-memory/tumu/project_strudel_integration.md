---
name: project_strudel_integration
description: Strudel v1.2.0 pattern engine integration status — what works, what's missing, architecture decisions
type: project
---

Strudel v1.2.0 pattern algebra ported to GDScript (v0.10.47–v0.10.67). Music Drawer (Ctrl+M) with multi-line editor, 6 visualizer types, 90+ SiON voice presets, 254+ unit tests. Audio effects (lpf, hpf, reverb, delay, distortion, crush, pan) via Godot AudioBus post-processing — 19 of 274 Strudel controls supported.

**Why:** User wants Strudel-compatible live-coding music in their Godot game. Tenets: no feature additions, retain Strudel compatibility, depth-first implementation.

**How to apply:**
- Mini-notation parser is solid (~95% coverage). The gap is everything OUTSIDE quotes: JS runtime, audio effects, sample system.
- 19 of 274 Strudel controls are mapped. Filter envelope, FM, modulation — still missing.
- Audio is GDSiON FM synthesis + SampleLibrary (13 synthesized drums, external .wav override). Samples route through AudioStreamPlayer pool (16-voice polyphony) before SiON.
- Per-note ADSR is implemented (.attack, .decay, .sustain, .release on SiON voices).
- Two scheduling modes: **batch** (MML sequence_on, sample-accurate) and **note** (per-note note_on, frame-accurate ±8ms). Use `strudel mode batch|note` to switch.
- Bus-level effects are a known limitation — .lpf(), .hpf() etc. apply to the ENTIRE Music bus, not per-voice. `music fx reset` RCON command exists to recover from bad filter settings.
- Source at `/var/tumu/repos/strudel-v1.2.0/` (frozen, do NOT update)
- Research at `/var/tumu/research/gamedev/strudel/viz_options.md`
- Compatibility doc: `docs/design/strudel_compatibility.md`
- Next priority: JS expression subset (stack(), setcps(), variable assignment from drawer text)
