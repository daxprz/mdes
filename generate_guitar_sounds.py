#!/usr/bin/env python3
"""Generate guitar sound effects as WAV files."""

import wave
import struct
import math
import random
import os

SAMPLE_RATE = 22050
MAX_AMP = 32767
OUTPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets", "sounds")


def write_wav(filename, samples):
    path = os.path.join(OUTPUT_DIR, filename)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        data = b""
        for s in samples:
            s = max(-1.0, min(1.0, s))
            data += struct.pack("<h", int(s * MAX_AMP))
        w.writeframes(data)
    print(f"  Created: {filename} ({len(samples)} samples, {len(samples)/SAMPLE_RATE:.3f}s)")


def noise():
    return random.uniform(-1, 1)

def sine(t, freq):
    return math.sin(2 * math.pi * freq * t)

def envelope_decay(i, total, power=2.0):
    return (1.0 - i / total) ** power

def envelope_linear(i, total, attack_frac=0.05, decay_frac=0.3):
    frac = i / total
    if frac < attack_frac:
        return frac / attack_frac
    decay_start = 1.0 - decay_frac
    if frac > decay_start:
        return (1.0 - frac) / decay_frac
    return 1.0

def freq_sweep(t, f_start, f_end, duration):
    f = f_start + (f_end - f_start) * (t / duration)
    phase = 2 * math.pi * (f_start * t + (f_end - f_start) * t * t / (2 * duration))
    return math.sin(phase)


def gen_guitar_note():
    """Short funky pluck/twang."""
    dur = 0.15
    n = int(SAMPLE_RATE * dur)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = envelope_decay(i, n, 2.5)
        # Plucky guitar: fundamental + harmonics with fast decay
        s = sine(t, 330) * 0.5 * env
        s += sine(t, 660) * 0.3 * (env ** 1.5)
        s += sine(t, 990) * 0.15 * (env ** 2.0)
        s += sine(t, 1320) * 0.1 * (env ** 2.5)
        # Twang: slight pitch bend down at start
        if t < 0.02:
            bend = 1.0 + (0.02 - t) * 25
            s += sine(t, 330 * bend) * 0.3 * env
        # String vibration
        s += sine(t, 330 * (1 + 0.005 * sine(t, 6))) * 0.1 * env
        # Pick noise
        if t < 0.01:
            s += noise() * 0.6 * (0.01 - t) / 0.01
        samples.append(max(-1, min(1, s * 0.85)))
    return samples


def gen_guitar_blast():
    """Deep distorted power chord blast."""
    dur = 0.4
    n = int(SAMPLE_RATE * dur)
    samples = []
    for i in range(n):
        t = i / SAMPLE_RATE
        env = envelope_linear(i, n, 0.05, 0.5)
        # Power chord: low E + fifth
        s = sine(t, 82) * 0.4 * env   # Low E
        s += sine(t, 123) * 0.35 * env  # Fifth (B)
        s += sine(t, 164) * 0.25 * env  # Octave
        s += sine(t, 246) * 0.15 * env  # Higher harmonic
        # Distortion
        s = max(-0.7, min(0.7, s * 2.5))
        # Add grit/noise
        s += noise() * 0.15 * env
        # Sub bass rumble
        s += sine(t, 41) * 0.3 * env
        # Feedback overtone
        s += sine(t, 500 + 200 * sine(t, 3)) * 0.08 * env
        samples.append(max(-1, min(1, s * 0.9)))
    return samples


def main():
    random.seed(42)
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    sounds = [
        ("guitar_note.wav", gen_guitar_note),
        ("guitar_blast.wav", gen_guitar_blast),
    ]

    print(f"Generating {len(sounds)} guitar sound effects...")
    for filename, generator in sounds:
        samples = generator()
        write_wav(filename, samples)

    print("Done!")


if __name__ == "__main__":
    main()
