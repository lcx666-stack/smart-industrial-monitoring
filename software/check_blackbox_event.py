#!/usr/bin/env python3
"""Read-only verification of black-box binary and event metadata."""
import argparse
import hashlib
import json
import os
import sys

from check_waveform_dma import FrameStats
from motor_blackbox import FRAME_SIZE, decode_frame


def verify_event(metadata_path, parser="native"):
    with open(metadata_path, "r", encoding="utf-8") as source:
        metadata = json.load(source)
    name = metadata["binary_file"]
    if not isinstance(name, str) or name != os.path.basename(name) or \
            "/" in name or "\\" in name or name in ("", ".", ".."):
        raise ValueError("binary_file must be a local filename")
    path = os.path.join(os.path.dirname(os.path.abspath(metadata_path)), name)
    if metadata.get("format") != "FRM1" or metadata.get("frame_bytes") != FRAME_SIZE:
        raise ValueError("Unsupported black-box format")
    if metadata.get("incomplete") is not False or metadata.get("pre_window_complete") is not True or \
            metadata.get("post_window_complete") is not True:
        raise ValueError("Event window is incomplete")
    counts = [metadata[key] for key in ("pre_count", "post_count", "frame_count",
                                       "pre_count_requested", "post_count_requested")]
    if any(type(value) is not int or value < 0 for value in counts):
        raise ValueError("Invalid window frame counts")
    pre, post, total, pre_requested, post_requested = counts
    included = metadata.get("trigger_frame_included")
    if type(included) is not bool or pre != pre_requested or post != post_requested or \
            total != pre + post + int(included):
        raise ValueError("Event frame-count/window mismatch")
    if total == 0 or os.path.getsize(path) != total * FRAME_SIZE or \
            metadata.get("binary_bytes") != total * FRAME_SIZE:
        raise ValueError("Event binary size mismatch")
    expected = metadata["expected_ticks_per_frame"]
    if type(expected) is not int or expected <= 0:
        raise ValueError("Invalid expected timestamp period")
    nominal = metadata.get("sample_rate_hz_nominal")
    if type(nominal) is not int or nominal <= 0 or \
            metadata.get("clock_hz_configured") != nominal * expected:
        raise ValueError("Inconsistent sample-rate/clock metadata")
    stats = FrameStats(expected, parser)
    digest = hashlib.sha256()
    with open(path, "rb") as source:
        while True:
            data = source.read(65536)
            if not data:
                break
            digest.update(data)
            stats.ingest(data)
        if included:
            source.seek(pre * FRAME_SIZE)
            trigger = decode_frame(source.read(FRAME_SIZE))
            if trigger["seq"] != metadata["trigger_seq"] or \
                    trigger["ticks"] != metadata["trigger_ticks"]:
                raise ValueError("Trigger frame/metadata mismatch")
        elif metadata.get("trigger_seq") is not None:
            # A status-trigger snapshot has no extra trigger sample: the last
            # pre-frame is the most recently observed frame at trigger time.
            if not pre:
                raise ValueError("Status trigger has no observed pre-frame")
            source.seek((pre - 1) * FRAME_SIZE)
            trigger = decode_frame(source.read(FRAME_SIZE))
            if trigger["seq"] != metadata["trigger_seq"] or \
                    trigger["ticks"] != metadata["trigger_ticks"]:
                raise ValueError("Status trigger/metadata mismatch")
    if digest.hexdigest() != metadata.get("binary_sha256"):
        raise ValueError("Event SHA-256 mismatch")
    if stats.frames != total or stats.sequence_gaps or stats.tick_mismatches:
        raise ValueError("Event waveform sequence/timestamp integrity failure")
    return {"metadata": metadata_path, "frames": total, "pre_frames": pre,
            "post_frames": post, "software_trigger": metadata.get("software_trigger", False),
            "sha256": digest.hexdigest(), "parser": stats.parser_name}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("events", nargs="+", help="Event JSON files")
    parser.add_argument("--parser", choices=("native", "python"), default="native")
    args = parser.parse_args(argv)
    for path in args.events:
        result = verify_event(path, args.parser)
        print("PASS: {metadata} frames={frames} pre={pre_frames} post={post_frames} ".format(**result) +
              "software_trigger={software_trigger} parser={parser} sha256={sha256}".format(**result))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, ValueError, KeyError, TypeError) as error:
        print("FAIL: {}".format(error), file=sys.stderr)
        sys.exit(1)
