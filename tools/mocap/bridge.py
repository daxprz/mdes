#!/usr/bin/env python3
"""
Motion Capture Bridge for DAX
==============================
Runs the camera + pose detection and serves skeleton data over TCP.
Godot connects and receives real-time pose updates to drive the monster.

Protocol (TCP port 7777):
  - Server sends one JSON line per frame, terminated by newline
  - Each line: {"t": float, "landmarks": {...}}
  - Landmarks are normalized 0-1 coordinates
  - Client can disconnect/reconnect at any time

Usage:
    ./run.sh --bridge              # Start bridge on port 7777
    ./run.sh --bridge --port 7778  # Custom port
"""

import json
import socket
import threading
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
    ("right_hip", "right_knee"),
    ("right_knee", "right_ankle"),
    ("nose", "left_eye"),
    ("nose", "right_eye"),
]

COL_BONE = (0, 255, 200)
COL_JOINT = (0, 180, 255)
COL_SPINE = (255, 200, 0)
COL_TEXT = (255, 255, 255)
COL_CONNECTED = (0, 255, 0)
COL_WAITING = (0, 100, 200)


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


def extract_bridge_data(landmark_list, t):
    """Extract landmark data for the bridge protocol."""
    lm = build_lm_map(landmark_list)
    data = {"t": round(t, 4), "landmarks": {}}
    for name in EXPORT_LANDMARKS:
        if name in lm:
            data["landmarks"][name] = lm_to_list(lm[name])

    # Synthetic midpoints
    keys = ["left_shoulder", "right_shoulder", "left_hip", "right_hip"]
    if all(k in lm for k in keys):
        ls, rs, lh, rh = [lm[k] for k in keys]
        data["landmarks"]["mid_shoulder"] = [
            round((ls.x + rs.x) / 2, 4), round((ls.y + rs.y) / 2, 4),
            round((ls.z + rs.z) / 2, 4), round(min(lm_vis(ls), lm_vis(rs)), 3)
        ]
        data["landmarks"]["mid_hip"] = [
            round((lh.x + rh.x) / 2, 4), round((lh.y + rh.y) / 2, 4),
            round((lh.z + rh.z) / 2, 4), round(min(lm_vis(lh), lm_vis(rh)), 3)
        ]
    return data


def draw_skeleton(frame, landmark_list, w, h):
    lm = build_lm_map(landmark_list)
    for a_name, b_name in SKELETON_CONNECTIONS:
        if a_name not in lm or b_name not in lm:
            continue
        a, b = lm[a_name], lm[b_name]
        if lm_vis(a) < 0.3 or lm_vis(b) < 0.3:
            continue
        cv2.line(frame, lm_pixel(a, w, h), lm_pixel(b, w, h), COL_BONE, 2)

    # Spine
    keys = ["left_shoulder", "right_shoulder", "left_hip", "right_hip"]
    if all(k in lm and lm_vis(lm[k]) > 0.3 for k in keys):
        ls, rs, lh, rh = [lm[k] for k in keys]
        mid_sh = (int((ls.x + rs.x) / 2 * w), int((ls.y + rs.y) / 2 * h))
        mid_hp = (int((lh.x + rh.x) / 2 * w), int((lh.y + rh.y) / 2 * h))
        if "nose" in lm and lm_vis(lm["nose"]) > 0.3:
            cv2.line(frame, mid_sh, lm_pixel(lm["nose"], w, h), COL_SPINE, 2)
        cv2.line(frame, mid_sh, mid_hp, COL_SPINE, 2)

    for name in EXPORT_LANDMARKS:
        if name in lm and lm_vis(lm[name]) > 0.3:
            cv2.circle(frame, lm_pixel(lm[name], w, h), 4, COL_JOINT, -1)


def rotate_frame(frame, rotation):
    if rotation == 90:
        return cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)
    elif rotation == 270:
        return cv2.rotate(frame, cv2.ROTATE_90_COUNTERCLOCKWISE)
    elif rotation == 180:
        return cv2.rotate(frame, cv2.ROTATE_180)
    return frame


class BridgeServer:
    """TCP server that streams pose data to connected clients."""

    def __init__(self, port=7777):
        self.port = port
        self.clients = []  # List of connected sockets
        self.lock = threading.Lock()
        self.server_socket = None
        self.running = False

    def start(self):
        self.running = True
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket.bind(("127.0.0.1", self.port))
        self.server_socket.listen(4)
        self.server_socket.settimeout(1.0)
        t = threading.Thread(target=self._accept_loop, daemon=True)
        t.start()
        print(f"  Bridge server listening on 127.0.0.1:{self.port}")

    def _accept_loop(self):
        while self.running:
            try:
                client, addr = self.server_socket.accept()
                client.setblocking(False)
                with self.lock:
                    self.clients.append(client)
                print(f"  Client connected: {addr}")
            except socket.timeout:
                continue
            except OSError:
                break

    def broadcast(self, data_dict):
        """Send a JSON line to all connected clients."""
        line = json.dumps(data_dict, separators=(',', ':')) + "\n"
        raw = line.encode("utf-8")
        dead = []
        with self.lock:
            for client in self.clients:
                try:
                    client.sendall(raw)
                except (BrokenPipeError, ConnectionResetError, OSError):
                    dead.append(client)
            for d in dead:
                self.clients.remove(d)
                try:
                    d.close()
                except OSError:
                    pass
                print("  Client disconnected")

    @property
    def client_count(self):
        with self.lock:
            return len(self.clients)

    def stop(self):
        self.running = False
        with self.lock:
            for c in self.clients:
                try:
                    c.close()
                except OSError:
                    pass
            self.clients.clear()
        if self.server_socket:
            self.server_socket.close()


def run_bridge(port=7777, camera_index=0, rotation=None):
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
    print(f"  Camera: {int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))}x{int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))}")

    if rotation is None:
        rotation = 0

    server = BridgeServer(port)
    server.start()

    mirror = True
    timestamp_ms = 0
    start_time = time.time()
    frame_count = 0
    fps_timer = time.time()
    fps_display = 0.0

    print("\n=== DAX Mocap Bridge ===")
    print(f"  Streaming on 127.0.0.1:{port}")
    print(f"  In Godot: echo \"mocap connect\" | nc -w1 localhost 9999")
    print(f"  R=rotate  M=mirror  Q=quit")
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
            draw_skeleton(frame, landmark_list, w, h)

            t = time.time() - start_time
            data = extract_bridge_data(landmark_list, t)
            server.broadcast(data)

        # FPS
        frame_count += 1
        elapsed = time.time() - fps_timer
        if elapsed >= 1.0:
            fps_display = frame_count / elapsed
            frame_count = 0
            fps_timer = time.time()

        # HUD
        n_clients = server.client_count
        status_col = COL_CONNECTED if n_clients > 0 else COL_WAITING
        status_text = f"STREAMING to {n_clients} client(s)" if n_clients > 0 else "WAITING for connection..."
        cv2.circle(frame, (15, 22), 8, status_col, -1)
        cv2.putText(frame, status_text, (30, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.55, status_col, 1)
        cv2.putText(frame, f"FPS: {fps_display:.0f}  port:{port}", (w - 180, 28),
                     cv2.FONT_HERSHEY_SIMPLEX, 0.45, COL_TEXT, 1)
        if not has_pose:
            cv2.putText(frame, "No person detected", (w // 2 - 100, h // 2),
                         cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 200), 2)
        if rotation != 0:
            cv2.putText(frame, f"ROT:{rotation}", (10, h - 15),
                         cv2.FONT_HERSHEY_SIMPLEX, 0.4, (150, 150, 150), 1)

        cv2.imshow("DAX Mocap Bridge", frame)

        key = cv2.waitKey(1) & 0xFF
        if key in (ord('q'), 27):
            break
        elif key == ord('r'):
            rotation = (rotation + 90) % 360
            print(f"  Rotation: {rotation}")
        elif key == ord('m'):
            mirror = not mirror

    server.stop()
    cap.release()
    cv2.destroyAllWindows()
    landmarker.close()
    print("Bridge stopped.")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="DAX Mocap Bridge")
    parser.add_argument("--bridge", action="store_true", help="(flag consumed by run.sh)")
    parser.add_argument("--port", type=int, default=7777, help="TCP port (default: 7777)")
    parser.add_argument("--camera", type=int, default=0, help="Camera index")
    parser.add_argument("--rotate", type=int, default=None, choices=[0, 90, 180, 270])
    args = parser.parse_args()
    run_bridge(port=args.port, camera_index=args.camera, rotation=args.rotate)
