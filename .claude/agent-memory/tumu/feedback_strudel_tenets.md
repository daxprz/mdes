---
name: feedback_strudel_tenets
description: User tenets for Strudel work — no inventions, only Strudel-compatible features
type: feedback
---

Do NOT create new features. Only implement what Strudel v1.2.0 actually has. The goal is COMPATIBILITY, not extension.

**Why:** User explicitly corrected when we added .bar(), .dots(), .meter() visualizers that don't exist in Strudel. Also corrected syntax (our `.pianoroll()` appended to bare text vs Strudel's `"mini".pianoroll()` with quotes).

**How to apply:**
- Before adding any feature, check if it exists in Strudel v1.2.0 source at `/var/tumu/repos/strudel-v1.2.0/`
- If it doesn't exist in Strudel, don't add it
- When implementing, match the exact Strudel syntax and behavior
- Game-specific hooks (intensity, monster events) are OK — they're integration points, not Strudel features
- The `docs/design/strudel_compatibility.md` tracks what we support vs what Strudel has
