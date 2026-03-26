# Quick Wins & Polish

**Priority:** Low — small items that can be done anytime
**Depends on:** Nothing specific

## Tasks

### 1. Timescale RCON command
- `timescale <float>` sets `Engine.time_scale`
- ~10 lines of code
- Instantly useful for slow-motion debugging of leaps, grabs, attacks
- Add to console autocomplete

### 2. Fix flaky hunt_P2 ik_peak
- Threshold is 2000, occasionally spikes to 2034-2148
- Options: bump threshold to 2500, or investigate the specific platform geometry on P2 that causes awkward leg configurations

### 3. Tune default animation values
- Play-test the monster at normal speed (not exaggerated)
- Use the config sliders to find good defaults for:
  - Attack wind-up/follow-through timings
  - Bite/swipe/tail/lunge feel
  - Turn speed and momentum at different distances
- Bake into `monster_defaults.json`

### 4. Sprint slash and hop-up wind-up
- Sprint slash and hop-up attacks don't have the same wind-up/follow-through treatment as bite/swipe/tail/lunge
- Add coil → strike → recovery phases with configurable timings
