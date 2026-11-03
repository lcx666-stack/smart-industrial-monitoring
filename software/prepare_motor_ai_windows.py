#!/usr/bin/env python3
"""Index verified FRM1 black-box recordings into unlabeled AI windows.

This is an offline, read-only data-preparation step. It never starts the motor,
changes the PL image, or infers a fault label from a software trigger.
"""
import argparse
import json
import math
import os
import sys

from check_blackbox_event import verify_event
from motor_blackbox import FRAME, FRAME_SIZE


CHANNELS = ("current_raw", "vibration_1", "vibration_2", "vibration_3")
SCHEMA = "motor-ai-window-v1"


def summarize(raw):
    """Return features and quality flags for one complete FRM1 window."""
    if len(raw) == 0 or len(raw) % FRAME_SIZE:
        raise ValueError("Window is empty or contains a partial frame")
    values = [[] for _ in CHANNELS]
    first_seq = last_seq = first_ticks = last_ticks = None
    motor_fault = adc_error = False
    for current, v1, v2, v3, seq, flags, ticks, _ma, _magic in FRAME.iter_unpack(raw):
        for series, value in zip(values, (current, v1, v2, v3)):
            series.append(value)
        if first_seq is None:
            first_seq, first_ticks = seq, ticks
        last_seq, last_ticks = seq, ticks
        motor_fault |= bool(flags & 2)
        adc_error |= bool(flags & 4)
    features = {}
    for name, series in zip(CHANNELS, values):
        mean = sum(series) / len(series)
        variance = sum((item - mean) ** 2 for item in series) / len(series)
        features[name] = {"mean": mean, "std": math.sqrt(variance),
                          "min": min(series), "max": max(series)}
    return features, first_seq, last_seq, first_ticks, last_ticks, motor_fault, adc_error


def event_windows(metadata_path, window_frames):
    """Verify the whole event before yielding fixed, non-overlapping windows."""
    if not 1 <= window_frames <= 16384:
        raise ValueError("window_frames must be between 1 and 16384")
    verification = verify_event(metadata_path, parser="python")
    with open(metadata_path, "r", encoding="utf-8") as source:
        metadata = json.load(source)
    binary_path = os.path.join(os.path.dirname(os.path.abspath(metadata_path)),
                               metadata["binary_file"])
    trigger_index = metadata["pre_count"] if metadata["trigger_frame_included"] else metadata["pre_count"] - 1
    total = verification["frames"]
    with open(binary_path, "rb") as source:
        for start in range(0, total - window_frames + 1, window_frames):
            raw = source.read(window_frames * FRAME_SIZE)
            if len(raw) != window_frames * FRAME_SIZE:
                raise ValueError("Event changed while preparing windows")
            features, first_seq, last_seq, first_ticks, last_ticks, motor_fault, adc_error = summarize(raw)
            end = start + window_frames
            phase = "pre" if end <= trigger_index else "post" if start > trigger_index else "crosses_trigger"
            yield {"schema": SCHEMA, "event_metadata": os.path.abspath(metadata_path),
                   "binary_file": os.path.abspath(binary_path),
                   "source_sha256": verification["sha256"],
                   "byte_offset": start * FRAME_SIZE, "frame_count": window_frames,
                   "sample_rate_hz": metadata["sample_rate_hz_nominal"],
                   "first_seq": first_seq, "last_seq": last_seq,
                   "first_ticks": first_ticks, "last_ticks": last_ticks,
                   "trigger_phase": phase,
                   "software_trigger": bool(metadata.get("software_trigger", False)),
                   "motor_fault_flag": motor_fault, "adc_error_flag": adc_error,
                   "channels": list(CHANNELS), "features": features,
                   "label": None}


def prepare(events, output, window_frames):
    if not events:
        raise ValueError("At least one event metadata file is required")
    records = []
    for event in events:
        records.extend(event_windows(event, window_frames))
    if not records:
        raise ValueError("No complete windows; choose a smaller window size")
    with open(output, "x", encoding="utf-8", newline="\n") as target:
        for record in records:
            target.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
    return len(records)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("events", nargs="+", help="Complete FRM1 event JSON files with adjacent .bin files")
    parser.add_argument("--output", required=True, help="New JSONL index; existing files are never overwritten")
    parser.add_argument("--window-frames", type=int, default=2048,
                        help="Non-overlapping frames per window (default: 2048 at nominal 50 kHz)")
    args = parser.parse_args(argv)
    try:
        count = prepare(args.events, args.output, args.window_frames)
    except (OSError, ValueError, KeyError, TypeError, RuntimeError) as error:
        print("FAIL: {}".format(error), file=sys.stderr)
        return 1
    print("PASS: {} verified, unlabeled windows; no motor control or source modification".format(count))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
