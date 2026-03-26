# Gait Tuning & Foot Planting

**Priority:** High — foundation is built but needs refinement
**Depends on:** v0.10.17 (gait oscillation, config sliders)

## Summary
The gait system has clavicle/hip oscillation and knee swing, but the foot planting doesn't follow the full gait cycle described by the user. The defaults also need tuning with the config slider UI.

## Tasks

### 1. Gait-driven foot planting
The 3rd segment (lower leg + foot) should:
- Stay PLANTED when the foot is moving backward (body moving forward over it)
- LIFT and stay angled slightly backward during the forward swing phase
- POP forward and PLANT at the apex of the forward oscillation cycle
- Currently: feet step based on distance-from-ideal, not gait phase

### 2. Tune defaults with sliders
- Run `gait_tuning_loop` test with config panel open
- Adjust `gait_knee_swing`, `gait_stride_rate`, `step_threshold`, `step_duration`, `step_height`, `stiffness`, `accel_rate`, `decel_rate` until the walk looks natural
- Bake good values into `data/config/monster_defaults.json`

### 3. Verify at multiple speeds
- Test at slow (patrol), medium (chase), and fast (sprint)
- Ensure gait scales naturally — short choppy steps at low speed, long fluid strides at high
