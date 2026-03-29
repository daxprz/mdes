# Motion Capture Bridge — Design Document

## Overview

A real-time motion capture system that captures human skeleton data from a webcam via MediaPipe and streams it to the running Godot game, driving a quadruped monster's skeleton in real-time. Used for designing and tuning procedural animations by acting them out physically.

## Architecture

```
┌─────────────────┐     TCP:7777     ┌──────────────────┐
│  bridge.py      │ ──────────────→  │  mocap_client.gd │
│  (Python)       │   JSON lines     │  (Godot)         │
│                 │                  │                  │
│  Camera → MP    │                  │  3D FABRIK →     │
│  Pose → TCP     │                  │  2.5D project →  │
│                 │                  │  Monster skeleton│
└─────────────────┘                  └──────────────────┘
```

### Python Side (`tools/mocap/`)

| File | Purpose |
|------|---------|
| `bridge.py` | Camera capture + MediaPipe PoseLandmarker + TCP server. Streams JSON lines at ~30fps. |
| `capture.py` | Standalone recording tool. SPACE=record takes, S=snapshot, R=rotate. Saves to `output/`. |
| `run.sh` | Launcher. `--bridge` routes to bridge.py, otherwise capture.py. Uses local `.venv`. |
| `pose_landmarker_full.task` | MediaPipe model file (9MB, gitignored). Auto-downloaded on first run. |
| `output/` | Recorded takes (`take_NNN.json`) and poses (`pose_NNN.json`). Gitignored. |

### Godot Side

| File | Purpose |
|------|---------|
| `scripts/systems/mocap_client.gd` | TCP client, calibration HUD, 2.5D mapping pipeline, config panel |
| RCON commands | `mocap connect/disconnect/calibrate/panel/reset/set/get/raw/status` |
| `data/tests/mocap_stage.json` | Test definition for mocap sessions |
| `levels/mocap_stage.json` | Level config (not currently auto-loading) |

## Coordinate Mapping (Mocap → Game)

This is the most critical and subtle part of the system.

### Mocap Coordinate Space (MediaPipe)
- **x** = left-right in camera image (human's right = +x)
- **y** = up-down (+y = downward)
- **z** = depth (-z = toward camera, +z = away)
- Origin = hip center
- All values normalized 0-1 for x/y, z is relative depth

### Game Coordinate Space
- Monster faces **RIGHT** (+X in game)
- **+X** = forward (right on screen)
- **+Y** = down
- **Z** = depth into/out of screen (NOT rendered in 2D)

### Mapping Rules
The HUMAN faces the CAMERA. The MONSTER faces RIGHT.

| Mocap Direction | Game Direction | Rendered? |
|----------------|----------------|-----------|
| Toward camera (-Z) | +X (forward/right) | **YES** |
| Away from camera (+Z) | -X (backward/left) | **YES** |
| Human's left (-X) | +Z (away from viewport) | **NO** — depth |
| Human's right (+X) | -Z (toward viewport) | **NO** — depth |
| Down (+Y) | +Y (down) | **YES** |
| Up (-Y) | -Y (up) | **YES** |

### Key Implication
- **T-pose** (arms in pure mocap X) → pure game Z → **invisible arms** (correct for side-view)
- **Arms reaching toward camera** → visible forward extension
- **Arms raised up/down** → visible vertical movement

## 2.5D Projection Pipeline

```
1. Extract all 3D mocap points relative to hip center
2. FABRIK constrain arm chains in 3D (preserve bone lengths in mocap space)
3. Compute arm joint positions RELATIVE to their shoulder
4. Project relative 3D → 2D:
   game_x = -mocap_z * facing * scale  (with dead zone for noise)
   game_y = mocap_y * scale
5. Offset from clavicle position in monster local space
6. 2.5D FABRIK: clamp MAX rendered bone length (allow shorter for foreshortening)
```

### Z Dead Zone
MediaPipe's monocular depth estimation is noisy. A dead zone of 0.05 normalized units filters small Z differences that would otherwise create false visible extension. Only Z differences > 0.05 produce visible game-X displacement.

## Pinning System

When mocap connects and the first frame arrives:
- **spine[2]** (rear/hips) is captured in world coords and NEVER moves
- **spine[1]** (mid-spine) is captured and used as the projection anchor
- **Facing direction** is locked (toward the target/dummy)
- **Scale** is computed from the first frame's torso length and locked
- **Monster physics** is frozen (`_physics_frozen = true`) so the monster's own `_physics_process` doesn't fight the mocap data

On disconnect, physics is unfrozen.

## Calibration System

### Poses (current)
1. **STAND ON MARKS** — relaxed, arms at sides, at 45° to camera
2. **T-POSE** — arms straight out
3. **ARMS FORWARD** — pointing at camera
4. **REACH UP** — arms above head

### Calibration Flow
1. Wait for ALL 9 required landmarks visible for 5 continuous seconds
2. Wait for stability (20 frames with < 0.008 movement per frame)
3. Countdown 3-2-1 with giant on-screen numbers
4. Capture 15 frames, average positions
5. Screen flash on capture
6. If excessive movement detected during countdown/capture → reset with warning
7. After all poses: compute torso length, shoulder width, arm bone lengths, depth sign

### T-Pose Auto-Detection
Continuously monitors arm positions. If both wrists are at shoulder height AND extended outward for 1.5 seconds, starts a 3-2-1 reset countdown. On completion, re-pins and recalibrates from current pose.

### Calibration Results Used
- `_cal_torso_len` — hip-to-shoulder distance (the "1.0" body size unit)
- `_cal_upper_arm` / `_cal_lower_arm` — 3D FABRIK bone lengths
- `_cal_shoulder_width` / `_cal_hip_width` — body proportions
- `_cal_depth_sign` — which Z direction is "toward camera"

## Config Panel

Pop-out slider panel (lower-right, CanvasLayer 95). Mouse input handled via polling in `_process` (Godot's gui_input doesn't work reliably on CanvasLayer Controls).

| Slider | Range | Default | Effect |
|--------|-------|---------|--------|
| Spine Angle | 0-90 | 0 | 0=vertical (standing), 90=horizontal (quadruped) |
| Smoothing | 0.01-0.5 | 0.15 | Temporal lerp blend per frame |
| X Scale | 0.1-3.0 | 1.0 | Horizontal extent multiplier |
| Y Scale | 0.1-3.0 | 1.0 | Vertical extent multiplier |
| Depth Blend | -1 to 1 | 0.25 | How much mocap X bleeds into game X |
| Arm Scale | 0.5-3.0 | 1.0 | Arm length multiplier |

**RESET SCENE** button above the panel — re-pins, clears smoothing, recalibrates.

## RCON Commands

```
mocap connect [port]      — Connect to bridge (default 7777)
mocap disconnect          — Stop receiving, unfreeze monster
mocap calibrate           — Start calibration sequence
mocap panel               — Toggle config slider panel
mocap reset               — Re-pin and recalibrate from current frame
mocap set <key> <value>   — Adjust config (angle, smooth, xscale, yscale, depth, armscale)
mocap get                 — Show all config values
mocap raw                 — Dump raw 3D mocap data for current frame
mocap status              — Connection state, target, calibration status
skeleton                  — Dump monster's current skeleton positions
```

## Test Setup Workflow

```bash
# Terminal 1: start bridge
tools/mocap/run.sh --bridge

# Terminal 2 (or RCON):
echo "level flat_floor" | nc -w2 localhost 9999
echo "spawn monster 400 850 standdown scale=4.0" | nc -w1 localhost 9999
echo "spawn dummy 1500 860" | nc -w1 localhost 9999
echo "tab" | nc -w1 localhost 9999
echo "debug on body_mechanics/spine_debug" | nc -w1 localhost 9999
echo "debug on body_mechanics/leg_debug" | nc -w1 localhost 9999
echo "mocap connect" | nc -w1 localhost 9999
echo "mocap panel" | nc -w1 localhost 9999
```

## Known Issues / Open Work

### Critical
- **T-pose arms not fully invisible** — MediaPipe's monocular Z estimation has ~0.10-0.15 normalized noise on wrist depth. The Z dead zone (0.05) helps but doesn't fully eliminate it. Need to either increase dead zone or subtract T-pose Z residual during calibration.
- **Body shape changes with distance** — Scale should be locked from calibration, not recomputed per frame. Partially fixed (pin_scale) but needs verification.

### Needed
- **Calibration T-pose Z offset subtraction** — Record the wrist Z residuals during T-pose calibration and subtract them from all subsequent frames. This would make T-pose truly invisible.
- **Rear leg FABRIK during mocap** — RL/RR should remain properly FABRIK-constrained (currently just pinned statically).
- **FL/FR angle extents** — Front legs should have configurable min/max angle limits so they don't swing into impossible positions.
- **45-degree actor expectation** — The calibration should expect the actor at ~45° to the camera (best coverage of all movement axes). The coordinate mapping should account for this known rotation.

### Nice to Have
- **Debug drawer MOCAP section** — Dedicated section in the debug drawer with the config sliders (instead of separate pop-out panel).
- **Recording from bridge** — Save the mapped monster skeleton data (not just raw mocap) for playback.
- **Multiple pose library** — Capture named poses (idle, swipe_coil, swipe_strike, etc.) and blend between them.
- **Auto-detect camera orientation** — The bridge's rotation auto-detect works but may need refinement for unusual setups.

## File Locations

```
tools/mocap/
  bridge.py               — TCP streaming server
  capture.py              — Standalone recording tool
  run.sh                  — Launcher script
  .venv/                  — Python virtual environment (gitignored)
  output/                 — Recorded takes (gitignored)
  pose_landmarker_full.task — MediaPipe model (gitignored)

scripts/systems/
  mocap_client.gd         — Godot-side client + mapping + UI

data/tests/
  mocap_stage.json        — Test definition

levels/
  mocap_stage.json        — Level config
```
