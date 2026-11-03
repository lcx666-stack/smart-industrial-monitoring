#!/usr/bin/env python3
"""Exercise the board AI preview and summarize its timing reports."""

import argparse
import datetime
import json
import math
from pathlib import Path
import re
import socket
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'ethernet_control_final_20261014'))

from control_client import ControlClient
from video_protocol import read_packet

REPORT = re.compile(
    r'BOARD_AI frames=(\d+) average_fps=(\S+) infer_ms=(\S+) '
    r'boxes=(\d+) guard_faults=(\S+)')


def percentile(values, fraction):
    ordered = sorted(values)
    if not ordered:
        return None
    position = (len(ordered) - 1) * fraction
    low, high = math.floor(position), math.ceil(position)
    if low == high:
        return ordered[low]
    return ordered[low] * (high - position) + ordered[high] * (position - low)


def summarize(values):
    return {
        'count': len(values),
        'min': min(values) if values else None,
        'mean': sum(values) / len(values) if values else None,
        'p50': percentile(values, .50),
        'p95': percentile(values, .95),
        'max': max(values) if values else None,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', default='192.168.0.50')
    parser.add_argument('--key', required=True)
    parser.add_argument('--frames', type=int, default=80)
    parser.add_argument('--timeout', type=float, default=30.0)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    if not 10 <= args.frames <= 500:
        parser.error('frames must be 10..500')

    client = ControlClient(args.host, args.key, use_agent=True)
    connection = None
    started_ai = False
    start_ack_ms = None
    stop_ack_ms = None
    packets = []
    failure = None
    try:
        initial = client.request('status')
        if not initial.get('ok'):
            raise RuntimeError('status rejected')
        initial_data = initial.get('data', {})
        if initial_data.get('ai_running'):
            reply = client.request('ai_stop')
            if not reply.get('ok'):
                raise RuntimeError('could not stop existing AI')
        if initial_data.get('wave_running'):
            raise RuntimeError('wave service is running; stop it before NPU timing')
        if initial_data.get('motor_running'):
            raise RuntimeError('motor is running; AI timing requires stop')
        if initial_data.get('fault_latched') or int(
                initial_data.get('pl', {}).get('guard_fault', 0)):
            reply = client.request('motor_clear', operator_confirmed=True)
            if not reply.get('ok'):
                raise RuntimeError('fault clear rejected')

        started = time.monotonic()
        reply = client.request('ai_start')
        start_ack_ms = (time.monotonic() - started) * 1000.0
        if not reply.get('ok'):
            raise RuntimeError('ai_start rejected: {}'.format(reply.get('error')))
        started_ai = True
        connection = socket.create_connection((args.host, 5000), timeout=5)
        connection.settimeout(5)
        deadline = time.monotonic() + args.timeout
        previous = None
        while len(packets) < args.frames and time.monotonic() < deadline:
            sequence, infer_sequence, rgb, boxes = read_packet(connection)
            if len(rgb) != 960 * 540 * 3:
                raise RuntimeError('unexpected video frame length')
            if previous is not None and sequence != previous + 1:
                raise RuntimeError('video sequence gap')
            previous = sequence
            packets.append({
                'sequence': sequence,
                'infer_sequence': infer_sequence,
                'frame_age': sequence - infer_sequence,
                'boxes': len(boxes),
                'received_at': time.monotonic(),
            })
        if not packets:
            raise RuntimeError('no AI video frames received')
    except Exception as error:
        failure = str(error)
    finally:
        if connection is not None:
            try:
                connection.close()
            except OSError:
                pass
        if started_ai:
            started = time.monotonic()
            try:
                client.request('ai_stop')
            finally:
                stop_ack_ms = (time.monotonic() - started) * 1000.0
        final = client.request('status')
        client.close()

    final_data = final.get('data', {}) if final.get('ok') else {}
    reports = []
    for match in REPORT.finditer(final_data.get('ai_tail', '')):
        reports.append({
            'frames': int(match.group(1)),
            'average_fps': float(match.group(2)),
            'infer_ms': float(match.group(3)),
            'boxes': int(match.group(4)),
            'guard_faults': match.group(5),
        })
    infer_ms = [row['infer_ms'] for row in reports]
    fps = [row['average_fps'] for row in reports]
    frame_ages = [row['frame_age'] for row in packets]
    wall_fps = None
    if len(packets) > 1:
        elapsed = packets[-1]['received_at'] - packets[0]['received_at']
        wall_fps = (len(packets) - 1) / elapsed if elapsed > 0 else None
    result = {
        'checked_at': datetime.datetime.now(
            datetime.timezone.utc).isoformat(),
        'requested_frames': args.frames,
        'received_frames': len(packets),
        'failure': failure,
        'start_ack_ms': start_ack_ms,
        'stop_ack_ms': stop_ack_ms,
        'wall_fps': wall_fps,
        'reported_infer_ms': summarize(infer_ms),
        'reported_fps': summarize(fps),
        'npu_frame_age': summarize(frame_ages),
        'reports': reports,
        'final_ai_running': final_data.get('ai_running'),
        'final_fault_latched': final_data.get('fault_latched'),
        'final_ai_tail': final_data.get('ai_tail', ''),
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2),
                      encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if not failure and len(packets) >= max(10, args.frames // 2) else 2


if __name__ == '__main__':
    raise SystemExit(main())
