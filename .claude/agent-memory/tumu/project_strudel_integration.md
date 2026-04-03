---
name: project_strudel_integration
description: Strudel v1.2.0 pattern engine integration status — what works, what's missing, architecture decisions
type: project
---

Strudel v1.2.0 pattern algebra ported to GDScript (v0.10.47-v0.10.52). Music Drawer (Ctrl+M) with multi-line editor, 6 visualizer types, 90+ SiON voice presets, 148 unit tests.

**Why:** User wants Strudel-compatible live-coding music in their Godot game. Tenets: no feature additions, retain Strudel compatibility, depth-first implementation.

**How to apply:**
- Mini-notation parser is solid (~95% coverage). The gap is everything OUTSIDE quotes: JS runtime, audio effects, sample system.
- Only 6 of 274 Strudel controls are mapped. Filter, envelope, effects, FM, modulation — all missing.
- Audio is GDSiON FM synthesis, NOT Web Audio. Different sound character. Can't reproduce samples.
- Source at `/var/tumu/repos/strudel-v1.2.0/` (frozen, do NOT update)
- Research at `/var/tumu/research/gamedev/strudel/viz_options.md`
- Active work file: `AI/agents/tumu/active/strudel_integration.md`
- Compatibility doc: `docs/design/strudel_compatibility.md`
