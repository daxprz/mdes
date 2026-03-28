#!/usr/bin/env python3
"""
Motion Capture Tool for DAX
===========================
Interactive recording: capture one movement at a time.
SPACE to start recording, SPACE again to stop and save.
Each recording is saved as a numbered JSON file.

Controls:
    SPACE   — Start/stop recording (auto-saves on stop)
    S       — Save a single-pose snapshot
    M       — Toggle mirror
    B       — Toggle bone labels
    Q/ESC   — Quit
"""

import argparse
import json
import time
import sys
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks.python import BaseOptions
from mediapipe.tasks.python.vision import (
    PoseLandmarker,
    PoseLandmarkerOptions,
    RunningMode,
)

MODEL_PATH = str(Path(__file__).parent / "pose_landmarker_full.task")

LANDMARK_NAMES = [
    "nose",
    "left_eye_inner", "left_eye", "left_eye_outer",
    "right_eye_inner", "right_eye", "right_eye_outer",
    "left_ear", "right_ear",
    "mouth_left", "mouth_right",
    "left_shoulder", "right_shoulder",
    "left_elbow", "right_elbow",
    "left_wrist", "right_wrist",
    "left_pinky", "right_pinky",
    "left_index", "right_index",
    "left_thumb", "right_thumb",
    "left_hip", "right_hip",
    "left_knee", "right_knee",
    "left_ankle", "right_ankle",
    "left_heel", "right_heel",
    "left_foot_index", "right_foot_index",
]

SKELETON_CONNECTIONS = [
    ("left_shoulder", "right_shoulder"),
    ("left_hip", "right_hip"),
    ("left_shoulder", "left_hip"),
    ("right_shoulder", "right_hip"),
    ("left_shoulder", "left_elbow"),
    ("left_elbow", "left_wrist"),
    ("right_shoulder", "right_elbow"),
    ("right_elbow", "right_wrist"),
    ("left_hip", "left_knee"),
    ("left_knee", "left_ankle"),
    ("left_ankle", "left_heel"),
    ("left_ankle", "left_foot_index"),
    ("right_hip", "right_knee"),
    ("right_knee", "right_ankle"),
    ("right_ankle", "right_heel"),
    ("right_ankle", "right_foot_index"),
    ("nose", "left_eye"),
    ("nose", "right_eye"),
    ("left_ear", "left_eye"),
    ("right_ear", "right_eye"),
]

EXPORT_LANDMARKS = [
    "nose",
    "left_shoulder", "right_shoulder",
    "left_elbow", "right_elbow",
    "left_wrist", "right_wrist",
    "left_hip", "right_hip",
    "left_knee", "right_knee",
    "left_ankle", "right_ankle",
    "left_heel", "right_heel",
    "left_foot_index", "right_foot_index",
    "left_ear", "right_ear",
    "left_index", "right_index",
]

COL_BONE = (0, 255, 200)
COL_JOINT = (0, 180, 255)
COL_JOINT_LOW = (80, 80, 80)
COL_RECORDING = (0, 0, 255)
COL_TEXT = (255, 255, 255)
COL_LABEL = (200, 200, 100)
COL_SPINE = (255, 200, 0)
COL_READY = (0, 200, 0)


def lm_pixel(lm, w, h):
    return int(lm.x * w), int(lm.y * h)

def lm_vis(lm):
    return lm.visibility if lm.visibility is not None else 0.5

def lm_to_list(lm):
    return [round(lm.x, 4), round(lm.y, 4), round(lm.z, 4), round(lm_vis(lm), 3)]

def build_lm_map(landmark_list):
    m = {}
    for i, name in enumerate(LANDMARK_NAMES):
        if i < len(landmark_list):
            m[name] = landmark_list[i]
    return m


def draw_skeleton(frame, landmark_list, w, h, show_labels=False):
    lm = build_lm_map(landmark_list)

    for a_name, b_name in SKELETON_CONNECTIONS:
        if a_name not in lm or b_name not in lm:
            continue
        a, b = lm[a_name], lm[b_name]
        if lm_vis(a) < 0.3 or lm_vis(b) < 0.3:
            continue
        ax, ay = lm_pixel(a, w, h)
        bx, by = lm_pixel(b, w, h)
        thickness = max(1, int(min(lm_vis(a), lm_vis(b)) * 3))
        cv2.line(frame, (ax, ay), (bx, by), COL_BONE, thickness)

    # Synthetic spine
    keys = ["left_shoulder", "right_shoulder", "left_hip", "right_hip"]
    if all(k in lm for k in keys) and all(lm_vis(lm[k]) > 0.3 for k in keys):
        ls, rs, lh, rh = [lm[k] for k in keys]
        mid_sh = (int((ls.x + rs.x) / 2 * w), int((ls.y + rs.y) / 2 * h))
        mid_hp = (int((lh.x + rh.x) / 2 * w), int((lh.y + rh.y) / 2 * h))
        mid_sp = ((mid_sh[0] + mid_hp[0]) // 2, (mid_sh[1] + mid_hp[1]) // 2)
        if "nose" in lm and lm_vis(lm["nose"]) > 0.3:
            cv2.line(frame, mid_sh, lm_pixel(lm["nose"], w, h), COL_SPINE, 2)
        cv2.line(frame, mid_sh, mid_sp, COL_SPINE, 2)
        cv2.line(frame, mid_sp, mid_hp, COL_SPINE, 2)
        for pt in [mid_sh, mid_sp, mid_hp]:
            cv2.circle(frame, pt, 4, COL_SPINE, -1)

    for name in EXPORT_LANDMARKS:
        if name not in lm:
            continue
        l = lm[name]
        px, py = lm_pixel(l, w, h)
        vis = lm_vis(l)
        col = COL_JOINT if vis > 0.5 else COL_JOINT_LOW
        radius = 5 if vis > 0.5 else 3
        cv2.circle(frame, (px, py), radius, col, -1)
        if show_labels:
            short = name.replace("left_", "L.").replace("right_", "R.")
            cv2.putText(frame, short, (px + 6, py - 4),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.3, COL_LABEL, 1)


def extract_frame_data(landmark_list, t):
    lm = build_lm_map(landmark_list)
    fd = {"t": round(t, 4), "landmarks": {}}
    for name in EXPORT_LANDMARKS:
        if name in lm:
            fd["landmarks"][name] = lm_to_list(lm[name])

    keys = ["left_shoulder", "right_shoulder", "left_hip", "right_hip"]
    if all(k in lm for k in keys):
        ls, rs, lh, rh = [lm[k] for k in keys]
        fd["landmarks"]["mid_shoulder"] = [
            round((ls.x + rs.x) / 2, 4), round((ls.y + rs.y) / 2, 4),
            round((ls.z + rs.z) / 2, 4), round(min(lm_vis(ls), lm_vis(rs)), 3)
        ]
        fd["landmarks"]["mid_hip"] = [
            round((lh.x + rh.x) / 2, 4), round((lh.y + rh.y) / 2, 4),
            round((lh.z + rh.z) / 2, 4), round(min(lm_vis(lh), lm_vis(rh)), 3)
        ]
        fd["landmarks"]["mid_spine"] = [
            round((ls.x + rs.x + lh.x + rh.x) / 4, 4),
            round((ls.y + rs.y + lh.y + rh.y) / 4, 4),
            round((ls.z + rs.z + lh.z + rh.z) / 4, 4),
            round(min(lm_vis(ls), lm_vis(rs), lm_vis(lh), lm_vis(rh)), 3)
        ]
    return fd


def save_recording(frames, filepath, fps):
    data = {
        "fps": round(fps, 1),
        "frame_count": len(frames),
        "duration": round(frames[-1]["t"] - frames[0]["t"], 2) if len(frames) > 1 else 0,
        "landmarks_per_frame": list(EXPORT_LANDMARKS) + ["mid_shoulder", "mid_hip", "mid_spine"],
        "coordinate_space": "normalized_0_1 (x=left-right, y=top-bottom, z=depth_toward_camera)",
        "frames": frames
    }
    with open(filepath, "w") as f:
        json.dump(data, f, indent=2)
    dur = data["duration"]
    print(f"  SAVED: {filepath} ({len(frames)} frames, {dur:.1f}s)")
    return filepath


def save_single_pose(landmark_list, filepath):
    fd = extract_frame_data(landmark_list, 0.0)
    data = {
        "type": "single_pose",
        "landmarks_exported": list(EXPORT_LANDMARKS) + ["mid_shoulder", "mid_hip", "mid_spine"],
        "coordinate_space": "normalized_0_1",
        "pose": fd["landmarks"]
    }
    with open(filepath, "w") as f:
        json.dump(data, f, indent=2)
    print(f"  SAVED: {filepath} (single pose)")


def run_playback(filepath):
    with open(filepath) as f:
        data = json.load(f)
    frames = data["frames"]
    fps = data.get("fps", 30)
    frame_time = 1.0 / fps
    print(f"Playing {len(frames)} frames at {fps} fps ({data.get('duration', '?')}s)")

    W, H = 960, 720
    frame_idx = 0
    paused = False

    while True:
        if frame_idx >= len(frames):
            frame_idx = 0
        canvas = np.zeros((H, W, 3), dtype=np.uint8)
        fd = frames[frame_idx]
        landmarks = fd["landmarks"]

        for a_name, b_name in SKELETON_CONNECTIONS:
            if a_name in landmarks and b_name in landmarks:
                a, b = landmarks[a_name], landmarks[b_name]
                if a[3] < 0.3 or b[3] < 0.3:
                    continue
                cv2.line(canvas, (int(a[0]*W), int(a[1]*H)),
                         (int(b[0]*W), int(b[1]*H)), COL_BONE, 2)

        for vals in landmarks.values():
            if vals[3] < 0.3:
                continue
            cv2.circle(canvas, (int(vals[0]*W), int(vals[1]*H)), 5, COL_JOINT, -1)

        for sp in ["mid_shoulder", "mid_spine", "mid_hip"]:
            if sp in landmarks and landmarks[sp][3] > 0.3:
                cv2.circle(canvas, (int(landmarks[sp][0]*W), int(landmarks[sp][1]*H)), 4, COL_SPINE, -1)

        cv2.putText(canvas, f"Frame {frame_idx+1}/{len(frames)}  t={fd['t']:.2f}s",
                     (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, COL_TEXT, 1)
        cv2.putText(canvas, "SPACE=pause  LEFT/RIGHT=step  Q=quit",
                     (10, H-20), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (150,150,150), 1)
        cv2.imshow("DAX Mocap Playback", canvas)

        key = cv2.waitKey(int(frame_time * 1000)) & 0xFF
        if key in (ord('q'), 27): break
        elif key == ord(' '): paused = not paused
        elif key in (81, 2): frame_idx = max(0, frame_idx-1); continue
        elif key in (83, 3): frame_idx = min(len(frames)-1, frame_idx+1); continue
        if not paused: frame_idx += 1

    cv2.destroyAllWindows()


def rotate_frame(frame, rotation):
    """Rotate a frame by 0, 90, 180, or 270 degrees clockwise."""
    if rotation == 90:
        return cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)
    elif rotation == 270:
        return cv2.rotate(frame, cv2.ROTATE_90_COUNTERCLOCKWISE)
    elif rotation == 180:
        return cv2.rotate(frame, cv2.ROTATE_180)
    return frame


def auto_detect_rotation(landmarker, cap, mirror=True):
    """Read a few frames, try all 4 rotations, and pick the one where
    the nose is above the hips (smallest nose.y, since y=0 is top).
    This is robust regardless of how the camera is oriented."""
    print("  Auto-detecting camera orientation...")
    timestamp_ms = 0

    # Collect a few raw frames
    raw_frames = []
    for _ in range(30):
        ret, frame = cap.read()
        if not ret:
            break
        if mirror:
            frame = cv2.flip(frame, 1)
        raw_frames.append(frame)

    if not raw_frames:
        print("  No frames captured — assuming upright (0)")
        return 0, 0

    # Test each rotation: run pose detection and check if nose is above hips
    best_rotation = 0
    best_score = -999.0  # Higher = nose further above hips = more correct

    for test_rot in [0, 90, 180, 270]:
        scores = []
        ts = timestamp_ms
        for frame in raw_frames[::3]:  # Sample every 3rd frame for speed
            rotated = rotate_frame(frame, test_rot)
            rgb = cv2.cvtColor(rotated, cv2.COLOR_BGR2RGB)
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            ts += 33
            result = landmarker.detect_for_video(mp_image, ts)
            if result.pose_landmarks and len(result.pose_landmarks) > 0:
                lm = build_lm_map(result.pose_landmarks[0])
                has_nose = "nose" in lm and lm_vis(lm["nose"]) > 0.3
                has_hips = all(k in lm and lm_vis(lm[k]) > 0.3
                               for k in ["left_hip", "right_hip"])
                if has_nose and has_hips:
                    nose_y = lm["nose"].y
                    hip_y = (lm["left_hip"].y + lm["right_hip"].y) / 2
                    # Score = how far nose is above hips (positive = correct orientation)
                    scores.append(hip_y - nose_y)
        timestamp_ms = ts

        if scores:
            avg = np.mean(scores)
            det_count = len(scores)
            print(f"    rot={test_rot:3d}: {det_count} detections, nose-above-hips={avg:.3f}")
            if avg > best_score:
                best_score = avg
                best_rotation = test_rot
        else:
            print(f"    rot={test_rot:3d}: no detections")

    print(f"  Best rotation: {best_rotation} degrees (score={best_score:.3f})")
    return best_rotation, timestamp_ms


def run_capture(camera_index=0, forced_rotation=None):
    if not Path(MODEL_PATH).exists():
        print(f"ERROR: Pose model not found at {MODEL_PATH}")
        sys.exit(1)

    options = PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=MODEL_PATH),
        running_mode=RunningMode.VIDEO,
        num_poses=1,
        min_pose_detection_confidence=0.5,
        min_pose_presence_confidence=0.5,
        min_tracking_confidence=0.5,
    )
    landmarker = PoseLandmarker.create_from_options(options)

    cap = cv2.VideoCapture(camera_index)
    if not cap.isOpened():
        print(f"ERROR: Cannot open camera {camera_index}")
        sys.exit(1)

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
    actual_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    actual_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    print(f"Camera: {actual_w}x{actual_h}")

    # Determine rotation
    timestamp_base = 0
    if forced_rotation is not None:
        rotation = forced_rotation
        print(f"  Forced rotation: {rotation} degrees")
    else:
        rotation, timestamp_base = auto_detect_rotation(landmarker, cap, mirror=True)

    if rotation != 0:
        # After rotation, effective dimensions swap for 90/270
        if rotation in (90, 270):
            print(f"  Effective resolution after rotation: {actual_h}x{actual_w}")

    mirror = True
    show_labels = False
    recording = False
    recorded_frames = []
    start_time = 0.0
    frame_count = 0
    fps_timer = time.time()
    fps_display = 0.0
    last_landmarks = None
    timestamp_ms = timestamp_base

    # Recording numbering
    output_dir = Path(__file__).parent / "output"
    output_dir.mkdir(exist_ok=True)
    take_number = _next_take_number(output_dir)
    pose_number = _next_pose_number(output_dir)
    saved_files = []

    print("\n=== DAX Motion Capture ===")
    print("  SPACE  = start/stop recording (auto-saves on stop)")
    print("  S      = snapshot current pose")
    print("  R      = cycle rotation (0/90/180/270)")
    print("  M      = toggle mirror")
    print("  B      = toggle bone labels")
    print("  Q/ESC  = quit")
    print(f"  Output: {output_dir}/")
    print(f"  Next take: take_{take_number:03d}.json")
    print()

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        if mirror:
            frame = cv2.flip(frame, 1)
        if rotation != 0:
            frame = rotate_frame(frame, rotation)

        h, w = frame.shape[:2]

        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        timestamp_ms += 33
        result = landmarker.detect_for_video(mp_image, timestamp_ms)

        has_pose = result.pose_landmarks and len(result.pose_landmarks) > 0
        if has_pose:
            landmark_list = result.pose_landmarks[0]
            last_landmarks = landmark_list
            draw_skeleton(frame, landmark_list, w, h, show_labels)

            if recording:
                t = time.time() - start_time
                fd = extract_frame_data(landmark_list, t)
                recorded_frames.append(fd)

        # FPS
        frame_count += 1
        elapsed = time.time() - fps_timer
        if elapsed >= 1.0:
            fps_display = frame_count / elapsed
            frame_count = 0
            fps_timer = time.time()

        # -- HUD --
        hud_y = 30

        if recording:
            # Recording: red border + red dot + frame count + duration
            dur = time.time() - start_time
            cv2.rectangle(frame, (0, 0), (w-1, h-1), COL_RECORDING, 3)
            cv2.circle(frame, (25, hud_y - 3), 10, COL_RECORDING, -1)
            cv2.putText(frame, f"RECORDING  take_{take_number:03d}   {len(recorded_frames)} frames  {dur:.1f}s",
                        (42, hud_y + 3), cv2.FONT_HERSHEY_SIMPLEX, 0.65, COL_RECORDING, 2)
            cv2.putText(frame, "SPACE to stop & save",
                        (w // 2 - 110, h - 20), cv2.FONT_HERSHEY_SIMPLEX, 0.6, COL_RECORDING, 1)
        else:
            # Idle: green ready indicator
            cv2.putText(frame, f"FPS: {fps_display:.0f}", (10, hud_y),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.55, COL_TEXT, 1)
            cv2.putText(frame, f"READY  (next: take_{take_number:03d})",
                        (w // 2 - 120, hud_y), cv2.FONT_HERSHEY_SIMPLEX, 0.6, COL_READY, 1)
            status_parts = []
            if mirror: status_parts.append("MIRROR")
            if rotation != 0: status_parts.append(f"ROT:{rotation}")
            if status_parts:
                cv2.putText(frame, "  ".join(status_parts), (10, hud_y + 22),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.4, (150, 150, 150), 1)
            if not has_pose:
                cv2.putText(frame, "No person detected", (w // 2 - 100, h // 2),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 200), 2)
            # Show saved takes
            if saved_files:
                y_saves = h - 50
                for sf in saved_files[-3:]:  # Show last 3
                    cv2.putText(frame, sf, (10, y_saves),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.4, (100, 200, 100), 1)
                    y_saves -= 18
            cv2.putText(frame, "SPACE=record  S=pose  R=rotate  M=mirror  B=labels  Q=quit",
                        (10, h - 12), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (120, 120, 120), 1)

        cv2.imshow("DAX Motion Capture", frame)

        key = cv2.waitKey(1) & 0xFF
        if key in (ord('q'), 27):
            # If recording, save before quitting
            if recording and recorded_frames:
                path = output_dir / f"take_{take_number:03d}.json"
                save_recording(recorded_frames, str(path), fps=fps_display or 30)
                saved_files.append(f"take_{take_number:03d}.json ({len(recorded_frames)}f)")
            break
        elif key == ord(' '):
            if not recording:
                # START recording
                recording = True
                recorded_frames = []
                start_time = time.time()
                print(f"  REC START: take_{take_number:03d}")
            else:
                # STOP recording — auto-save immediately
                recording = False
                if recorded_frames:
                    path = output_dir / f"take_{take_number:03d}.json"
                    fpath = save_recording(recorded_frames, str(path), fps=fps_display or 30)
                    saved_files.append(f"take_{take_number:03d}.json ({len(recorded_frames)}f)")
                    take_number += 1
                    recorded_frames = []
                else:
                    print("  (no frames captured)")
        elif key == ord('s'):
            if last_landmarks is not None:
                path = output_dir / f"pose_{pose_number:03d}.json"
                save_single_pose(last_landmarks, str(path))
                saved_files.append(f"pose_{pose_number:03d}.json")
                pose_number += 1
        elif key == ord('m'):
            mirror = not mirror
        elif key == ord('b'):
            show_labels = not show_labels
        elif key == ord('r') and not recording:
            rotation = (rotation + 90) % 360
            print(f"  Rotation: {rotation} degrees")

    cap.release()
    cv2.destroyAllWindows()
    landmarker.close()

    print(f"\nDone. {len(saved_files)} files saved to {output_dir}/")
    for sf in saved_files:
        print(f"  {sf}")


def _next_take_number(output_dir):
    """Find the next available take number."""
    n = 1
    while (output_dir / f"take_{n:03d}.json").exists():
        n += 1
    return n


def _next_pose_number(output_dir):
    """Find the next available pose number."""
    n = 1
    while (output_dir / f"pose_{n:03d}.json").exists():
        n += 1
    return n


def main():
    parser = argparse.ArgumentParser(description="DAX Motion Capture Tool")
    parser.add_argument("--play", type=str, default=None,
                        help="Play back a recorded JSON file")
    parser.add_argument("--camera", type=int, default=0,
                        help="Camera index (default: 0)")
    parser.add_argument("--rotate", type=int, default=None, choices=[0, 90, 180, 270],
                        help="Force camera rotation (default: auto-detect)")
    args = parser.parse_args()

    if args.play:
        run_playback(args.play)
    else:
        run_capture(camera_index=args.camera, forced_rotation=args.rotate)


if __name__ == "__main__":
    main()
