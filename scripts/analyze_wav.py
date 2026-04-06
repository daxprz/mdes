#!/usr/bin/env python3
"""
WAV Audio Analyzer — spectral and temporal analysis for verifying Strudel output.

Usage:
  python3 scripts/analyze_wav.py <wav_file> [--onsets] [--spectral] [--temporal] [--summary] [--all]

Modes:
  (default)    Summary + amplitude onsets
  --onsets     Amplitude-based onset detection
  --spectral   Per-window FFT: dominant frequencies + MIDI notes
  --pitchtrack Per-window pitch tracking with note segmentation
  --temporal   Time-grid analysis: divide into slots, identify what's in each
  --summary    Quick overview: total duration, loudness, frequency bands
  --json       Machine-readable JSON output (for AB tests)

Options:
  --window_ms N     Analysis window size in ms (default: 50)
  --top N           Show top N frequencies per window (default: 3)
  --threshold F     Amplitude threshold for onset detection (default: 0.02)
  --expect SPEC     Expected pattern spec: "c2:0-500,~:500-1000,eb2:1000-1500"
  --cps F           Cycles per second (for temporal grid)
  --slots N         Notes per cycle (for temporal grid)
  --start_ms N      Trim: skip first N ms of recording
  --end_ms N        Trim: stop at N ms into recording
"""

import sys
import json
import argparse
import math
from pathlib import Path

import numpy as np
from scipy import signal as sig
from scipy.io import wavfile


# ── Constants ──────────────────────────────────────────────────────────

NOTE_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']

# Canonical note name aliases for matching
NOTE_ALIASES = {
    'db': 'c#', 'eb': 'd#', 'fb': 'e', 'gb': 'f#', 'ab': 'g#', 'bb': 'a#', 'cb': 'b',
}

# MIDI note frequencies (A4 = 440)
def midi_freq(midi_num):
    """MIDI note number to frequency."""
    return 440.0 * (2 ** ((midi_num - 69) / 12.0))


# ── Helpers ────────────────────────────────────────────────────────────

def freq_to_midi(freq):
    """Convert frequency to MIDI note number (float)."""
    if freq <= 0:
        return -1
    return 69 + 12 * math.log2(freq / 440.0)

def midi_to_name(midi_num):
    """Convert MIDI note number to name (e.g., 60 -> C4)."""
    if midi_num < 0:
        return "?"
    note = int(round(midi_num))
    octave = (note // 12) - 1
    name = NOTE_NAMES[note % 12]
    cents = round((midi_num - note) * 100)
    cents_str = f"{cents:+d}c" if abs(cents) > 5 else ""
    return f"{name}{octave}{cents_str}"

def freq_to_name(freq):
    """Convert frequency to note name."""
    return midi_to_name(freq_to_midi(freq))

def name_to_midi(name):
    """Convert note name like 'c2', 'eb4', 'f#3', 'D2+45c' to MIDI number.
    Strips cents annotations like '+45c', '-12c' before parsing.
    """
    import re
    name = name.strip().lower()
    # Strip cents annotation (e.g., "+45c", "-12c")
    name = re.sub(r'[+-]\d+c$', '', name)
    # Handle flats via alias
    for alias, canonical in NOTE_ALIASES.items():
        if name.startswith(alias) and len(name) > len(alias):
            rest = name[len(alias):]
            if rest.lstrip('-').isdigit():
                name = canonical + rest
                break
    # Parse: note + optional sharp + octave
    i = 1
    if len(name) > 1 and name[1] == '#':
        i = 2
    note_part = name[:i].upper()
    octave_part = name[i:]
    if not octave_part.lstrip('-').isdigit():
        return -1
    octave = int(octave_part)
    try:
        note_idx = NOTE_NAMES.index(note_part)
    except ValueError:
        return -1
    return (octave + 1) * 12 + note_idx

def notes_match(expected_name, detected_name):
    """Check if two note names refer to the same pitch (enharmonic matching).
    Tolerates ±1 semitone for pitch tracker imprecision.
    """
    m1 = name_to_midi(expected_name)
    m2 = name_to_midi(detected_name)
    if m1 < 0 or m2 < 0:
        # Fall back to substring match (strip accidentals and cents)
        e = expected_name.lower().rstrip('0123456789+-c ')
        d = detected_name.lower().rstrip('0123456789+-c ')
        return e == d or e in d or d in e
    return abs(m1 - m2) <= 1  # Allow ±1 semitone tolerance


# ── WAV I/O ────────────────────────────────────────────────────────────

def read_wav(path):
    """Read WAV file, return (sample_rate, mono_float_array)."""
    sr, data = wavfile.read(path)
    if data.dtype == np.int16:
        data = data.astype(np.float64) / 32768.0
    elif data.dtype == np.int32:
        data = data.astype(np.float64) / 2147483648.0
    elif data.dtype == np.float32:
        data = data.astype(np.float64)
    if len(data.shape) > 1:
        data = data.mean(axis=1)
    return sr, data


# ── Harmonic Series Detection ──────────────────────────────────────────

def deduce_harmonics(peaks, max_harmonics=8, tolerance_cents=50):
    """Given a list of spectral peaks [{freq, mag, ...}], identify which form
    a harmonic series and deduce the fundamental.

    Returns: {
        'fundamental': float (Hz),
        'fundamental_note': str,
        'harmonics': [{n: int, freq: float, mag: float, note: str, deviation_cents: float}],
        'inharmonic': [{freq, mag, note}]  — peaks not part of the series
    } or None if no series found.

    The algorithm tries each peak as a candidate fundamental (or sub-harmonic
    of the lowest peak) and scores how many other peaks align as integer multiples.
    """
    if not peaks or len(peaks) < 2:
        return None

    freqs = [p['freq'] for p in peaks if p['freq'] > 20]
    if len(freqs) < 2:
        return None

    best_score = 0
    best_result = None

    # Generate candidate fundamentals:
    # - Each peak's frequency
    # - Each peak divided by 2, 3, 4 (in case fundamental is missing)
    candidates = set()
    for f in freqs:
        candidates.add(f)
        for d in [2, 3, 4]:
            if f / d > 20:
                candidates.add(f / d)

    for f0 in sorted(candidates):
        harmonics = []
        matched_peaks = set()

        for i, p in enumerate(peaks):
            if p['freq'] <= 20:
                continue
            # Which harmonic number is this closest to?
            ratio = p['freq'] / f0
            n = round(ratio)
            if n < 1 or n > max_harmonics:
                continue
            expected_freq = f0 * n
            deviation_cents = 1200 * math.log2(p['freq'] / expected_freq) if expected_freq > 0 else 9999

            if abs(deviation_cents) <= tolerance_cents:
                harmonics.append({
                    'n': n,
                    'freq': p['freq'],
                    'mag': p['mag'],
                    'note': p.get('note', freq_to_name(p['freq'])),
                    'deviation_cents': round(deviation_cents, 1),
                })
                matched_peaks.add(i)

        # Score: number of harmonics, weighted by having the fundamental present
        score = len(harmonics)
        has_fundamental = any(h['n'] == 1 for h in harmonics)
        if has_fundamental:
            score += 2  # Bonus for having the actual fundamental

        if score > best_score and len(harmonics) >= 2:
            best_score = score
            inharmonic = [peaks[i] for i in range(len(peaks)) if i not in matched_peaks and peaks[i]['freq'] > 20]
            best_result = {
                'fundamental': round(f0, 2),
                'fundamental_note': freq_to_name(f0),
                'fundamental_present': has_fundamental,
                'harmonics': sorted(harmonics, key=lambda h: h['n']),
                'inharmonic': inharmonic,
            }

    return best_result


# ── Spectral Analysis ─────────────────────────────────────────────────

def spectral_analysis(data, sr, window_ms=50, top_n=3):
    """Per-window FFT analysis. Returns list of window results."""
    window_samples = int(sr * window_ms / 1000)
    hop = window_samples
    results = []

    for start in range(0, len(data) - window_samples, hop):
        chunk = data[start:start + window_samples]
        t_start = start / sr
        t_end = (start + window_samples) / sr
        rms = float(np.sqrt(np.mean(chunk ** 2)))

        if rms < 0.001:
            results.append({
                'time_ms': (t_start * 1000, t_end * 1000),
                'rms': rms,
                'peaks': [],
                'bands': {},
                'silent': True,
            })
            continue

        windowed = chunk * np.hanning(len(chunk))
        fft = np.fft.rfft(windowed)
        magnitudes = np.abs(fft) / len(chunk)
        freqs = np.fft.rfftfreq(len(chunk), 1.0 / sr)

        peak_indices = sig.find_peaks(magnitudes, height=rms * 0.1, distance=5)[0]
        if len(peak_indices) == 0:
            peak_indices = np.argsort(magnitudes[1:])[-top_n:] + 1
        peak_indices = sorted(peak_indices, key=lambda i: magnitudes[i], reverse=True)[:top_n]

        peaks = []
        for idx in peak_indices:
            freq = float(freqs[idx])
            mag = float(magnitudes[idx])
            if freq > 20:
                peaks.append({
                    'freq': freq,
                    'mag': mag,
                    'note': freq_to_name(freq),
                    'midi': float(freq_to_midi(freq)),
                })

        band_energy = {}
        for band_name, (lo, hi) in [('sub', (20, 80)), ('low', (80, 300)),
                                      ('mid', (300, 2000)), ('high', (2000, 8000)),
                                      ('air', (8000, 20000))]:
            mask = (freqs >= lo) & (freqs < hi)
            band_energy[band_name] = float(np.sqrt(np.mean(magnitudes[mask] ** 2))) if mask.any() else 0.0

        # Deduce harmonic series from the peaks
        harm = deduce_harmonics(peaks)

        results.append({
            'time_ms': (t_start * 1000, t_end * 1000),
            'rms': rms,
            'peaks': peaks,
            'bands': band_energy,
            'harmonics': harm,
            'silent': False,
        })

    return results


# ── Pitch Tracking ────────────────────────────────────────────────────

def track_pitch(data, sr, window_ms=50, hop_ms=10, min_freq=30, max_freq=2000):
    """Track dominant pitch over time using harmonic product spectrum (HPS).
    HPS multiplies downsampled copies of the magnitude spectrum to find the
    fundamental, even when harmonics are stronger (common in FM synthesis).
    Returns list of {time_ms, freq, note, confidence, rms} per frame.
    """
    # For bass notes (30Hz), we need at least 2 full periods → ~67ms.
    # Use 50ms minimum, which handles down to ~40Hz reliably.
    window_samples = int(sr * window_ms / 1000)
    hop_samples = int(sr * hop_ms / 1000)
    frames = []

    for start in range(0, len(data) - window_samples, hop_samples):
        chunk = data[start:start + window_samples]
        t_ms = (start + window_samples // 2) / sr * 1000
        rms = float(np.sqrt(np.mean(chunk ** 2)))

        if rms < 0.005:
            frames.append({'time_ms': t_ms, 'freq': 0, 'note': '~', 'midi': -1,
                           'confidence': 0.0, 'rms': rms})
            continue

        # --- Harmonic Product Spectrum (HPS) ---
        # Zero-pad to next power of 2 for FFT efficiency
        n_fft = 1 << (len(chunk) - 1).bit_length()
        windowed = chunk * np.hanning(len(chunk))
        fft = np.fft.rfft(windowed, n=n_fft)
        magnitudes = np.abs(fft)
        freqs = np.fft.rfftfreq(n_fft, 1.0 / sr)

        # HPS: multiply spectrum with downsampled copies (harmonics 2..5)
        hps = magnitudes.copy()
        n_harmonics = 5
        for h in range(2, n_harmonics + 1):
            decimated = magnitudes[::h]
            hps[:len(decimated)] *= decimated

        # Restrict search to min_freq..max_freq
        freq_res = sr / n_fft
        min_bin = max(1, int(min_freq / freq_res))
        max_bin = min(len(hps) - 1, int(max_freq / freq_res))

        if min_bin >= max_bin:
            frames.append({'time_ms': t_ms, 'freq': 0, 'note': '?', 'midi': -1,
                           'confidence': 0.0, 'rms': rms})
            continue

        region = hps[min_bin:max_bin]
        peak_idx = np.argmax(region)
        peak_bin = min_bin + peak_idx
        freq = float(freqs[peak_bin])

        # Confidence: ratio of HPS peak to median (higher = more harmonic)
        median_val = float(np.median(region[region > 0])) if np.any(region > 0) else 1e-10
        confidence = min(1.0, float(region[peak_idx]) / (median_val * 100 + 1e-10))

        # Parabolic interpolation for sub-bin accuracy
        if 0 < peak_idx < len(region) - 1:
            a = float(region[peak_idx - 1])
            b = float(region[peak_idx])
            c = float(region[peak_idx + 1])
            denom = 2 * b - a - c
            if denom > 0:
                delta = 0.5 * (a - c) / denom
                freq = float(freqs[peak_bin]) + delta * freq_res

        if freq > min_freq and confidence > 0.01:
            midi_val = freq_to_midi(freq)
            frames.append({
                'time_ms': t_ms,
                'freq': freq,
                'note': midi_to_name(midi_val),
                'midi': float(midi_val),
                'confidence': round(confidence, 4),
                'rms': rms,
            })
        else:
            frames.append({'time_ms': t_ms, 'freq': 0, 'note': '?', 'midi': -1,
                           'confidence': 0.0, 'rms': rms})

    return frames


def segment_pitch_track(frames, min_dur_ms=30, pitch_tolerance=1.0):
    """Segment a pitch track into note events.
    Groups consecutive frames with similar pitch into note segments.
    pitch_tolerance: max MIDI semitone difference to consider "same note".
    Returns list of {start_ms, end_ms, duration_ms, midi, note, confidence, rms}.
    """
    if not frames:
        return []

    segments = []
    seg_midi = frames[0]['midi']
    seg_frames = [frames[0]]

    for i in range(1, len(frames)):
        f = frames[i]
        curr_midi = f['midi']

        # Same note if both pitched and close enough, or both silent
        same = False
        if seg_midi < 0 and curr_midi < 0:
            same = True
        elif seg_midi >= 0 and curr_midi >= 0:
            same = abs(curr_midi - seg_midi) <= pitch_tolerance

        if same:
            seg_frames.append(f)
        else:
            # Emit segment
            _emit_segment(segments, seg_frames, min_dur_ms)
            seg_midi = curr_midi
            seg_frames = [f]

    # Final segment
    _emit_segment(segments, seg_frames, min_dur_ms)

    # Merge pass: rejoin note segments of similar pitch separated by short gaps
    # (pitch tracker may fragment a sustained note due to brief detection errors)
    merged = _merge_nearby_segments(segments, max_gap_ms=150, pitch_tolerance=pitch_tolerance)
    return merged


def _merge_nearby_segments(segments, max_gap_ms=200, pitch_tolerance=1.0,
                           max_bridge_ms=150):
    """Merge note segments that are the same pitch, separated by short gaps or
    short different-pitch bridge segments (pitch tracker artifacts).

    Two-pass approach:
    1. Absorb short bridges: if segment B is shorter than max_bridge_ms and
       segments A and C (flanking it) have the same pitch, merge A+B+C.
    2. Merge adjacent same-pitch segments separated by a gap < max_gap_ms.
    """
    if len(segments) < 2:
        return segments

    # Pass 1: Absorb short bridge segments
    absorbed = list(segments)
    changed = True
    while changed:
        changed = False
        new_list = []
        i = 0
        while i < len(absorbed):
            if (i + 2 < len(absorbed)
                and absorbed[i]['type'] == 'note'
                and absorbed[i + 2]['type'] == 'note'
                and abs(absorbed[i]['midi'] - absorbed[i + 2]['midi']) <= pitch_tolerance
                and absorbed[i + 1]['duration_ms'] <= max_bridge_ms):
                # Merge i, i+1, i+2 into one segment
                merged_seg = {
                    'start_ms': absorbed[i]['start_ms'],
                    'end_ms': absorbed[i + 2]['end_ms'],
                    'duration_ms': absorbed[i + 2]['end_ms'] - absorbed[i]['start_ms'],
                    'midi': absorbed[i]['midi'],  # Keep first segment's pitch
                    'note': absorbed[i]['note'],
                    'confidence': max(absorbed[i]['confidence'], absorbed[i + 2]['confidence']),
                    'rms': round((absorbed[i]['rms'] + absorbed[i + 2]['rms']) / 2, 4),
                    'type': 'note',
                }
                new_list.append(merged_seg)
                i += 3
                changed = True
            else:
                new_list.append(absorbed[i])
                i += 1
        absorbed = new_list

    # Pass 2: Merge adjacent same-pitch segments with small gaps
    merged = [absorbed[0]]
    for s in absorbed[1:]:
        prev = merged[-1]
        gap = s['start_ms'] - prev['end_ms']
        same_type = prev['type'] == 'note' and s['type'] == 'note'
        same_pitch = same_type and abs(prev['midi'] - s['midi']) <= pitch_tolerance

        if same_pitch and gap < max_gap_ms:
            prev['end_ms'] = s['end_ms']
            prev['duration_ms'] = prev['end_ms'] - prev['start_ms']
            w1 = max(prev['duration_ms'] - s['duration_ms'], 1)
            w2 = max(s['duration_ms'], 1)
            total_w = w1 + w2
            prev['midi'] = round((prev['midi'] * w1 + s['midi'] * w2) / total_w, 1)
            prev['note'] = midi_to_name(prev['midi'])
            prev['confidence'] = round(max(prev['confidence'], s['confidence']), 3)
            prev['rms'] = round((prev['rms'] + s['rms']) / 2, 4)
        else:
            merged.append(s)

    return merged


def _emit_segment(segments, frames, min_dur_ms):
    """Helper to emit a note segment from accumulated frames."""
    if not frames:
        return
    start_ms = frames[0]['time_ms']
    end_ms = frames[-1]['time_ms']
    duration_ms = end_ms - start_ms
    if duration_ms < min_dur_ms:
        return

    # Average MIDI and RMS
    pitched = [f for f in frames if f['midi'] >= 0]
    if pitched:
        avg_midi = sum(f['midi'] for f in pitched) / len(pitched)
        avg_conf = sum(f['confidence'] for f in pitched) / len(pitched)
        avg_rms = sum(f['rms'] for f in frames) / len(frames)
        segments.append({
            'start_ms': start_ms,
            'end_ms': end_ms,
            'duration_ms': duration_ms,
            'midi': round(avg_midi, 1),
            'note': midi_to_name(avg_midi),
            'confidence': round(avg_conf, 3),
            'rms': round(avg_rms, 4),
            'type': 'note',
        })
    else:
        avg_rms = sum(f['rms'] for f in frames) / len(frames)
        segments.append({
            'start_ms': start_ms,
            'end_ms': end_ms,
            'duration_ms': duration_ms,
            'midi': -1,
            'note': '~',
            'confidence': 0.0,
            'rms': round(avg_rms, 4),
            'type': 'rest',
        })


# ── Amplitude Onset Detection ─────────────────────────────────────────

def detect_onsets(data, sr, threshold=0.02, min_gap_ms=30):
    """Detect note onsets using energy envelope."""
    window = int(sr * 0.01)  # 10ms windows
    hop = window // 2
    envelope = []
    times = []
    for start in range(0, len(data) - window, hop):
        env = np.sqrt(np.mean(data[start:start + window] ** 2))
        envelope.append(env)
        times.append(start / sr)
    envelope = np.array(envelope)
    times = np.array(times)

    onsets = []
    in_note = False
    note_start = 0
    note_peak = 0

    for i in range(1, len(envelope)):
        if not in_note and envelope[i] > threshold and envelope[i] > envelope[i-1]:
            in_note = True
            note_start = i
            note_peak = envelope[i]
        elif in_note:
            note_peak = max(note_peak, envelope[i])
            if envelope[i] < threshold * 0.5 or envelope[i] < note_peak * 0.1:
                s = int(times[note_start] * sr)
                e = int(times[i] * sr)
                note_data = data[s:e]
                duration_ms = (times[i] - times[note_start]) * 1000

                dom_freq, band_e = _analyze_chunk_spectrum(note_data, sr)

                onsets.append({
                    'start_ms': round(times[note_start] * 1000, 1),
                    'end_ms': round(times[i] * 1000, 1),
                    'duration_ms': round(duration_ms, 1),
                    'peak_amp': round(float(note_peak), 4),
                    'dom_freq': round(dom_freq, 1),
                    'note': freq_to_name(dom_freq) if dom_freq > 20 else '?',
                    'midi': round(freq_to_midi(dom_freq), 1) if dom_freq > 20 else -1,
                    'bands': {k: round(v, 5) for k, v in band_e.items()},
                    'type': classify_sound(dom_freq, band_e),
                })
                in_note = False

    return onsets


def _analyze_chunk_spectrum(note_data, sr):
    """FFT a chunk and return (dominant_freq, band_energy_dict)."""
    if len(note_data) < 64:
        return 0, {}
    windowed = note_data * np.hanning(len(note_data))
    fft = np.fft.rfft(windowed)
    magnitudes = np.abs(fft) / len(note_data)
    freqs = np.fft.rfftfreq(len(note_data), 1.0 / sr)
    peak_idx = np.argmax(magnitudes[1:]) + 1
    dom_freq = float(freqs[peak_idx])

    band_e = {}
    for bn, (lo, hi) in [('sub', (20, 80)), ('low', (80, 300)),
                          ('mid', (300, 2000)), ('high', (2000, 8000)),
                          ('air', (8000, 20000))]:
        mask = (freqs >= lo) & (freqs < hi)
        band_e[bn] = float(np.sqrt(np.mean(magnitudes[mask] ** 2))) if mask.any() else 0.0
    return dom_freq, band_e


def classify_sound(dom_freq, bands):
    """Classify a sound as drum type or pitched note."""
    if not bands:
        return 'unknown'
    total = sum(bands.values()) or 1e-10
    high_ratio = (bands.get('high', 0) + bands.get('air', 0)) / total
    low_ratio = (bands.get('sub', 0) + bands.get('low', 0)) / total
    mid_ratio = bands.get('mid', 0) / total

    if high_ratio > 0.6:
        return 'hihat/cymbal'
    elif low_ratio > 0.6 and dom_freq < 120:
        return 'kick'
    elif mid_ratio > 0.4 and high_ratio > 0.2:
        return 'snare/clap'
    elif dom_freq > 0 and dom_freq < 300:
        return f'bass ({freq_to_name(dom_freq)})'
    elif dom_freq >= 300:
        return f'pitched ({freq_to_name(dom_freq)})'
    else:
        return 'unknown'


# ── Temporal Grid Analysis ────────────────────────────────────────────

def temporal_grid(data, sr, cps, slots, cycles=None):
    """Divide recording into a time grid and identify what's in each slot.
    cps: cycles per second
    slots: number of equal slots per cycle
    cycles: number of cycles to analyze (default: all that fit)
    Returns list of slot results.
    """
    cycle_dur = 1.0 / cps
    slot_dur = cycle_dur / slots
    total_dur = len(data) / sr

    if cycles is None:
        cycles = int(total_dur / cycle_dur)
    cycles = max(1, min(cycles, int(total_dur / cycle_dur) + 1))

    results = []
    for c in range(cycles):
        for s in range(slots):
            t_start = c * cycle_dur + s * slot_dur
            t_end = t_start + slot_dur
            if t_end * sr > len(data):
                break

            s_start = int(t_start * sr)
            s_end = min(int(t_end * sr), len(data))
            chunk = data[s_start:s_end]

            rms = float(np.sqrt(np.mean(chunk ** 2)))

            if rms < 0.003:
                results.append({
                    'cycle': c,
                    'slot': s,
                    'time_ms': (round(t_start * 1000, 1), round(t_end * 1000, 1)),
                    'rms': round(rms, 5),
                    'note': '~',
                    'type': 'rest',
                    'freq': 0,
                })
                continue

            dom_freq, bands = _analyze_chunk_spectrum(chunk, sr)
            stype = classify_sound(dom_freq, bands)

            # Also run pitch tracking on this chunk for better accuracy on bass
            pt_frames = track_pitch(chunk, sr, window_ms=min(20, int(slot_dur * 500)),
                                     hop_ms=min(10, int(slot_dur * 250)))
            pitched = [f for f in pt_frames if f['midi'] >= 0 and f['confidence'] > 0.4]
            if pitched:
                avg_midi = sum(f['midi'] for f in pitched) / len(pitched)
                note_name = midi_to_name(avg_midi)
                freq_est = midi_freq(int(round(avg_midi)))
            else:
                note_name = freq_to_name(dom_freq) if dom_freq > 20 else '?'
                freq_est = dom_freq

            results.append({
                'cycle': c,
                'slot': s,
                'time_ms': (round(t_start * 1000, 1), round(t_end * 1000, 1)),
                'rms': round(rms, 5),
                'note': note_name,
                'type': stype,
                'freq': round(freq_est, 1),
                'bands': {k: round(v, 5) for k, v in bands.items()},
            })

    return results


# ── Pattern Validation ────────────────────────────────────────────────

def validate_pattern(segments, expect_spec, tolerance_ms=80):
    """Validate pitch-tracked segments against an expected pattern spec.
    Format: "c2:0-500,~:500-1000,eb2:1000-1500,f2:1500-2000"
    Uses pitch-tracked segments (from segment_pitch_track) for better accuracy.
    """
    expectations = []
    for part in expect_spec.split(','):
        part = part.strip()
        if ':' not in part:
            continue
        note, timerange = part.split(':', 1)
        t_start, t_end = timerange.split('-')
        expectations.append({
            'note': note.strip(),
            'start_ms': float(t_start),
            'end_ms': float(t_end),
        })

    results = []
    for exp in expectations:
        exp_start = exp['start_ms']
        exp_end = exp['end_ms']
        exp_dur = exp_end - exp_start
        is_rest = exp['note'] in ('~', 'rest', 'silence')

        # Find segments overlapping this time window
        overlapping = [s for s in segments
                      if s['end_ms'] > exp_start - tolerance_ms
                      and s['start_ms'] < exp_end + tolerance_ms]

        if is_rest:
            # Check that no note segments START in this window.
            # Decay tails from the previous note bleeding in are OK — they're
            # just envelope sustain, not new onsets.
            note_starts_in_window = [s for s in overlapping
                                    if s['type'] == 'note'
                                    and s['start_ms'] >= exp_start - tolerance_ms
                                    and s['start_ms'] < exp_end]
            ok = len(note_starts_in_window) == 0
            results.append({
                'expected': exp,
                'pass': ok,
                'detail': f"{'PASS' if ok else 'FAIL'}: expected rest at {exp_start:.0f}-{exp_end:.0f}ms, "
                         f"found {len(note_starts_in_window)} new onsets"
                         + (f" ({', '.join(s['note'] for s in note_starts_in_window)})" if note_starts_in_window else ""),
            })
        else:
            # Check for a note segment with matching pitch in this window
            note_segs = [s for s in overlapping if s['type'] == 'note']
            if not note_segs:
                results.append({
                    'expected': exp,
                    'pass': False,
                    'detail': f"FAIL: expected {exp['note']} at {exp_start:.0f}-{exp_end:.0f}ms, "
                             f"found no notes (only {len(overlapping)} rest segments)",
                })
                continue

            # Find the best matching segment
            best = None
            for s in note_segs:
                if notes_match(exp['note'], s['note']):
                    if best is None or abs(s['start_ms'] - exp_start) < abs(best['start_ms'] - exp_start):
                        best = s

            if best is None:
                # No pitch match — report what was found
                found_notes = ', '.join(f"{s['note']}@{s['start_ms']:.0f}ms" for s in note_segs)
                results.append({
                    'expected': exp,
                    'pass': False,
                    'detail': f"FAIL: expected {exp['note']} at {exp_start:.0f}-{exp_end:.0f}ms, "
                             f"found wrong pitch(es): {found_notes}",
                })
                continue

            # Check timing
            onset_ok = abs(best['start_ms'] - exp_start) < tolerance_ms
            dur_ok = best['duration_ms'] >= exp_dur * 0.4  # At least 40% of expected
            ok = onset_ok  # Pitch already matched

            detail_parts = []
            if ok:
                detail_parts.append("PASS")
            else:
                detail_parts.append("FAIL")
            detail_parts.append(f"{exp['note']} at {best['start_ms']:.0f}ms "
                              f"(expected {exp_start:.0f}ms, Δ={best['start_ms']-exp_start:+.0f}ms)")
            detail_parts.append(f"dur={best['duration_ms']:.0f}ms (expected ~{exp_dur:.0f}ms)")
            detail_parts.append(f"detected={best['note']} conf={best['confidence']:.2f}")

            results.append({
                'expected': exp,
                'pass': ok,
                'detail': ': '.join(detail_parts[:2]) + ', ' + ', '.join(detail_parts[2:]),
            })

    return results


# ── Printing ──────────────────────────────────────────────────────────

def print_spectral(results, top_n=3):
    print(f"\n{'Time (ms)':>16}  {'RMS':>6}  Dominant Frequencies")
    print("-" * 80)
    for r in results:
        t0, t1 = r['time_ms']
        if r['silent']:
            print(f"  {t0:7.0f}-{t1:5.0f}  {r['rms']:.4f}  (silent)")
            continue
        peaks_str = "  ".join(
            f"{p['freq']:.0f}Hz({p['note']})" for p in r['peaks'][:top_n]
        )
        print(f"  {t0:7.0f}-{t1:5.0f}  {r['rms']:.4f}  {peaks_str}")

        # Show harmonic series if detected
        harm = r.get('harmonics')
        if harm:
            h_str = " ".join(f"H{h['n']}={h['freq']:.0f}Hz" for h in harm['harmonics'])
            f0_str = f"f0={harm['fundamental']:.0f}Hz({harm['fundamental_note']})"
            present = "✓" if harm.get('fundamental_present') else "↓"
            print(f"{'':>24}  harmonics: {f0_str} {present}  {h_str}")

        bands = r.get('bands', {})
        if bands:
            band_str = " ".join(f"{k}={v:.4f}" for k, v in bands.items() if v > 0.001)
            if band_str:
                print(f"{'':>24}  bands: {band_str}")


def print_onsets(onsets):
    print(f"\n{'#':>3}  {'Start':>8}  {'End':>8}  {'Dur':>6}  {'Amp':>5}  {'Freq':>7}  {'Note':>6}  Type")
    print("-" * 75)
    for i, o in enumerate(onsets):
        print(f"  {i+1:2d}  {o['start_ms']:7.1f}  {o['end_ms']:7.1f}  {o['duration_ms']:5.0f}ms  "
              f"{o['peak_amp']:.3f}  {o['dom_freq']:6.0f}Hz  {o['note']:>5s}  {o['type']}")


def print_pitch_segments(segments):
    print(f"\n{'#':>3}  {'Start':>8}  {'End':>8}  {'Dur':>6}  {'MIDI':>5}  {'Note':>6}  {'Conf':>5}  {'RMS':>6}  Type")
    print("-" * 80)
    for i, s in enumerate(segments):
        midi_str = f"{s['midi']:.0f}" if s['midi'] >= 0 else " -"
        print(f"  {i+1:2d}  {s['start_ms']:7.1f}  {s['end_ms']:7.1f}  {s['duration_ms']:5.0f}ms  "
              f"{midi_str:>5s}  {s['note']:>5s}  {s['confidence']:.3f}  {s['rms']:.4f}  {s['type']}")


def print_temporal_grid(grid_results):
    print(f"\n{'Cyc':>3} {'Slot':>4}  {'Time (ms)':>16}  {'RMS':>7}  {'Note':>6}  {'Freq':>7}  Type")
    print("-" * 72)
    prev_cycle = -1
    for r in grid_results:
        if r['cycle'] != prev_cycle and prev_cycle >= 0:
            print("  " + "-" * 68)
        prev_cycle = r['cycle']
        t0, t1 = r['time_ms']
        print(f"  {r['cycle']:2d}   {r['slot']:2d}   {t0:7.0f}-{t1:5.0f}  {r['rms']:.5f}  "
              f"{r['note']:>5s}  {r['freq']:6.0f}Hz  {r['type']}")


def print_summary(data, sr, onsets=None, segments=None):
    duration = len(data) / sr
    rms = float(np.sqrt(np.mean(data ** 2)))
    peak = float(np.max(np.abs(data)))
    print(f"\nSummary:")
    print(f"  Duration:    {duration:.3f}s ({duration*1000:.0f}ms)")
    print(f"  Sample rate: {sr}Hz")
    print(f"  RMS level:   {rms:.4f} ({20*math.log10(max(rms, 1e-10)):.1f} dBFS)")
    print(f"  Peak level:  {peak:.4f} ({20*math.log10(max(peak, 1e-10)):.1f} dBFS)")

    if segments:
        note_segs = [s for s in segments if s['type'] == 'note']
        rest_segs = [s for s in segments if s['type'] == 'rest']
        print(f"  Pitch segments: {len(note_segs)} notes, {len(rest_segs)} rests")
        if note_segs:
            durations = [s['duration_ms'] for s in note_segs]
            notes = [s['note'] for s in note_segs]
            print(f"  Note sequence: {' '.join(notes)}")
            print(f"  Note durations: min={min(durations):.0f}ms  max={max(durations):.0f}ms  avg={sum(durations)/len(durations):.0f}ms")

    if onsets:
        print(f"  Amplitude onsets: {len(onsets)}")
        if onsets:
            types = {}
            for o in onsets:
                t = o['type']
                types[t] = types.get(t, 0) + 1
            print(f"  Sound types: {', '.join(f'{k}={v}' for k, v in sorted(types.items()))}")


# ── Main ──────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description='WAV Audio Analyzer for Strudel output')
    parser.add_argument('wav_file', help='Path to WAV file')
    parser.add_argument('--window_ms', type=int, default=50, help='Window size in ms (default: 50)')
    parser.add_argument('--top', type=int, default=3, help='Top N frequencies per window')
    parser.add_argument('--onsets', action='store_true', help='Amplitude onset detection')
    parser.add_argument('--harmonics', action='store_true', help='Harmonic series analysis per note segment')
    parser.add_argument('--spectral', action='store_true', help='Full spectral analysis (per-window FFT)')
    parser.add_argument('--pitchtrack', action='store_true', help='Pitch tracking + note segmentation')
    parser.add_argument('--temporal', action='store_true', help='Temporal grid analysis')
    parser.add_argument('--summary', action='store_true', help='Quick summary')
    parser.add_argument('--all', action='store_true', help='Run all analyses')
    parser.add_argument('--json', action='store_true', help='JSON output (for AB tests)')
    parser.add_argument('--threshold', type=float, default=0.02, help='Onset threshold')
    parser.add_argument('--expect', type=str, help='Expected pattern spec')
    parser.add_argument('--cps', type=float, help='Cycles per second (for temporal grid)')
    parser.add_argument('--slots', type=int, help='Slots per cycle (for temporal grid)')
    parser.add_argument('--cycles', type=int, help='Number of cycles to analyze')
    parser.add_argument('--start_ms', type=float, default=0, help='Trim: skip first N ms')
    parser.add_argument('--end_ms', type=float, default=0, help='Trim: stop at N ms')
    args = parser.parse_args()

    path = Path(args.wav_file)
    if not path.exists():
        print(f"ERROR: {path} not found", file=sys.stderr)
        sys.exit(1)

    sr, data = read_wav(str(path))

    # Apply trimming
    if args.start_ms > 0:
        start_sample = int(args.start_ms / 1000.0 * sr)
        data = data[start_sample:]
    if args.end_ms > 0:
        end_sample = int(args.end_ms / 1000.0 * sr)
        data = data[:end_sample]

    if not args.json:
        print(f"Loaded: {path.name} ({len(data)/sr:.3f}s, {sr}Hz, {len(data)} samples)")

    # Default mode
    if not any([args.onsets, args.summary, args.spectral, args.pitchtrack,
                args.harmonics, args.temporal, args.all]):
        args.summary = True
        args.pitchtrack = True

    # Always compute pitch tracking (it's fast and useful)
    pitch_frames = track_pitch(data, sr)
    segments = segment_pitch_track(pitch_frames)
    onsets = detect_onsets(data, sr, threshold=args.threshold) if (args.onsets or args.all) else None

    if args.json:
        # Machine-readable output
        output = {
            'file': str(path),
            'duration_ms': round(len(data) / sr * 1000, 1),
            'sample_rate': sr,
            'rms': round(float(np.sqrt(np.mean(data ** 2))), 5),
            'peak': round(float(np.max(np.abs(data))), 5),
            'segments': segments,
        }
        if onsets is not None:
            output['onsets'] = onsets
        if args.expect:
            output['validation'] = validate_pattern(segments, args.expect)
        if args.cps and args.slots:
            output['grid'] = temporal_grid(data, sr, args.cps, args.slots, args.cycles)
        print(json.dumps(output, indent=2))
        sys.exit(0)

    # Human-readable output
    if args.summary or args.all:
        print_summary(data, sr, onsets, segments)

    if args.pitchtrack or args.all:
        print("\n── Pitch-Tracked Note Segments ──")
        print_pitch_segments(segments)

    if args.onsets or args.all:
        print("\n── Amplitude Onsets ──")
        print_onsets(onsets)

    if args.harmonics or args.all:
        print("\n── Harmonic Series Analysis (per note segment) ──")
        print("-" * 80)
        for i, seg in enumerate(segments):
            if seg['type'] != 'note':
                continue
            # Extract the chunk for this segment
            s_start = int(seg['start_ms'] / 1000.0 * sr)
            s_end = int(seg['end_ms'] / 1000.0 * sr)
            chunk = data[s_start:s_end]
            if len(chunk) < 256:
                continue
            # Use a larger window (or the whole segment) for better freq resolution
            analysis_len = min(len(chunk), int(sr * 0.2))  # Up to 200ms
            # Take from the middle of the note (avoid attack/release transients)
            mid = len(chunk) // 2
            half = analysis_len // 2
            analysis_chunk = chunk[max(0, mid - half):mid + half]

            windowed = analysis_chunk * np.hanning(len(analysis_chunk))
            n_fft = 1 << (len(analysis_chunk) - 1).bit_length()
            fft = np.fft.rfft(windowed, n=n_fft)
            magnitudes = np.abs(fft) / len(analysis_chunk)
            freqs = np.fft.rfftfreq(n_fft, 1.0 / sr)

            # Find all peaks above noise floor
            rms = float(np.sqrt(np.mean(analysis_chunk ** 2)))
            peak_indices = sig.find_peaks(magnitudes, height=rms * 0.05, distance=3)[0]
            peak_indices = sorted(peak_indices, key=lambda j: magnitudes[j], reverse=True)[:12]

            peaks = [{'freq': float(freqs[j]), 'mag': float(magnitudes[j]),
                       'note': freq_to_name(float(freqs[j]))}
                     for j in peak_indices if freqs[j] > 20]

            harm = deduce_harmonics(peaks)
            print(f"\n  Segment {i+1}: {seg['note']} ({seg['start_ms']:.0f}-{seg['end_ms']:.0f}ms, {seg['duration_ms']:.0f}ms)")
            if harm:
                f0 = harm['fundamental']
                present = "present" if harm.get('fundamental_present') else "missing (inferred)"
                print(f"    Fundamental: {harm['fundamental_note']} = {f0:.1f}Hz ({present})")
                for h in harm['harmonics']:
                    ratio_str = f"x{h['n']}"
                    expected_hz = f0 * h['n']
                    print(f"      H{h['n']:2d} {ratio_str:>3s}  {h['freq']:7.1f}Hz  {h['note']:>8s}  "
                          f"(expected {expected_hz:.1f}Hz, Δ{h['deviation_cents']:+.0f}¢)  mag={h['mag']:.5f}")
                if harm['inharmonic']:
                    for p in harm['inharmonic']:
                        print(f"      ???      {p['freq']:7.1f}Hz  {p['note']:>8s}  (inharmonic)  mag={p['mag']:.5f}")
            else:
                peak_list = ', '.join(f"{p['freq']:.0f}Hz" for p in peaks[:5])
                print(f"    No harmonic series detected (peaks: {peak_list})")

    if args.spectral or args.all:
        results = spectral_analysis(data, sr, window_ms=args.window_ms, top_n=args.top)
        print("\n── Spectral Analysis ──")
        print_spectral(results, top_n=args.top)

    if args.temporal and args.cps and args.slots:
        grid = temporal_grid(data, sr, args.cps, args.slots, args.cycles)
        print("\n── Temporal Grid ──")
        print_temporal_grid(grid)
    elif args.temporal:
        print("\nERROR: --temporal requires --cps and --slots", file=sys.stderr)

    if args.expect:
        print("\n── Pattern Validation ──")
        print("-" * 70)
        validation = validate_pattern(segments, args.expect)
        passed = sum(1 for v in validation if v['pass'])
        for v in validation:
            print(f"  {v['detail']}")
        print(f"\n  Result: {passed}/{len(validation)} checks passed")


if __name__ == '__main__':
    main()
