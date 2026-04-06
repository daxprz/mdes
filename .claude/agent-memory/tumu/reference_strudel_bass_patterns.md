---
name: reference_strudel_bass_patterns
description: Strudel bass line recipes — acid, sub, synth, walking, euclidean patterns with voice/effect settings
type: reference
---

Bass voice recommendations: `sawtooth` (rich, versatile), `square` (punchy/retro), `sine` (pure sub), `triangle` (mellow).

**Acid bass:** `note("d2 d2 d2 a1 bb1 d1 f2").s("sawtooth").lpf(200).lpenv(4).lpq(7)` — high lpq (5-8) for resonant squelch, lpenv sweeps filter open per note. `ftype("ladder")` for analog 303 character (not yet implemented in our system).

**Sub bass:** `note("c1 ~ c1 ~ <eb1 f1>").s("sine").gain(0.8).decay(0.3)` — no effects, low octave, sits underneath.

**Synth bass:** `note("c2 ~ c2 ~ e2 ~ g1 ~").s("sawtooth").lpf(500).lpq(3)` — moderate filter, general purpose.

**Walking bass:** `note("c2 e2 g2 a2 f2 d2 g1 c2").s("sawtooth").lpf(800).decay(0.2)` — scale-wise motion with passing tones.

**Euclidean:** `note("c2 eb2 g2 bb2").euclid(3,8).s("sawtooth").lpf(400).lpq(5)` — tresillo feel. Also: euclid(5,8) = funk, euclid(3,16) = sparse dub.

**Bass + drums combo:**
```
stack(
  s("bd ~ bd ~, ~ cp ~ ~, hh*8"),
  note("c2 ~ <eb2 g2> ~").s("sawtooth").lpf(500).lpq(4)
)
```

**Effect sweet spots for bass:** lpf 200-800, lpq 1-3 subtle / 5-8 squelchy, decay 0.1-0.4, gain 0.5-0.9.

⚠️ In our system .lpf() is bus-level — affects ALL voices. Keep cutoff above 400 when mixing with drums. Use `music fx reset` to recover.

Sources: strudel.cc/learn/synths, strudel.cc/recipes, club.tidalcycles.org/t/acid-bass-line
