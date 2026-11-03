#!/usr/bin/env python3
"""Measure CS500-to-STM32 alarm acknowledgement stability over SocketCAN."""

import argparse
import json
import math
import re
import socket
import struct
import subprocess
import time


AF_CAN = 29
CAN_RAW = 1
SOL_CAN_RAW = 101
CAN_RAW_FILTER = 1
CAN_FRAME = struct.Struct('=IB3x8s')
ALARM_ID = 0x180
ACK_ID = 0x280


def percentile(values, fraction):
    ordered = sorted(values)
    if not ordered:
        return None
    position = (len(ordered) - 1) * fraction
    low, high = math.floor(position), math.ceil(position)
    if low == high:
        return ordered[low]
    return ordered[low] * (high - position) + ordered[high] * (position - low)


def can_counters(interface):
    output = subprocess.check_output(
        ['ip', '-details', '-statistics', 'link', 'show', interface],
        universal_newlines=True, encoding='utf-8', errors='replace')
    result = {'raw': output}
    counter_match = re.search(
        r're-started\s+bus-errors\s+arbit-lost\s+error-warn\s+'
        r'error-pass\s+bus-off\s*\n\s*'
        r'(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)',
        output)
    counter_names = ('re-started', 'bus-errors', 'arbit-lost', 'error-warn',
                     'error-pass', 'bus-off')
    values = ([int(value) for value in counter_match.groups()]
              if counter_match else [None] * len(counter_names))
    result.update(dict(zip(counter_names, values)))
    for heading in ('RX', 'TX'):
        match = re.search(
            r'{}:\s+bytes\s+packets\s+errors\s+dropped[\s\S]*?\n'
            r'\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)'.format(heading),
            output)
        prefix = heading.lower()
        result[prefix + '_packets'] = int(match.group(2)) if match else None
        result[prefix + '_errors'] = int(match.group(3)) if match else None
        result[prefix + '_dropped'] = int(match.group(4)) if match else None
    return result


def receive_ack(bus, sequence, deadline):
    while time.monotonic() < deadline:
        try:
            raw = bus.recv(16)
        except socket.timeout:
            continue
        can_id, length, data = CAN_FRAME.unpack(raw)
        can_id &= 0x1FFFFFFF
        if can_id != ACK_ID or length != 8:
            continue
        ack_sequence, mask, receiver, reserved = struct.unpack('<IBBH', data)
        if (ack_sequence == sequence and mask == 1 and receiver == 1 and
                reserved == 0):
            return True
    return False


def drain(bus):
    bus.setblocking(False)
    try:
        while True:
            bus.recv(16)
    except BlockingIOError:
        pass
    finally:
        bus.setblocking(True)
        bus.settimeout(0.05)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--interface', default='can0')
    parser.add_argument('--count', type=int, default=500)
    parser.add_argument('--interval-ms', type=float, default=20.0)
    parser.add_argument('--timeout-ms', type=float, default=250.0)
    parser.add_argument('--sequence', type=lambda value: int(value, 0),
                        default=0xDEADBEEF)
    args = parser.parse_args()
    if not 1 <= args.count <= 100000:
        parser.error('count must be 1..100000')
    if not 1 <= args.interval_ms <= 5000:
        parser.error('interval must be 1..5000 ms')

    before = can_counters(args.interface)
    bus = socket.socket(AF_CAN, socket.SOCK_RAW, CAN_RAW)
    bus.bind((args.interface,))
    bus.setsockopt(SOL_CAN_RAW, CAN_RAW_FILTER,
                   struct.pack('=II', ACK_ID, 0x7FF))
    bus.settimeout(args.timeout_ms / 1000.0)
    payload = struct.pack('<IBBH', args.sequence & 0xffffffff, 7, 0, 0)
    frame = CAN_FRAME.pack(ALARM_ID, 8, payload)
    latencies = []
    lost = 0
    started = time.monotonic()
    try:
        for index in range(args.count):
            drain(bus)
            sent_at = time.monotonic()
            bus.send(frame)
            deadline = sent_at + args.timeout_ms / 1000.0
            if receive_ack(bus, args.sequence, deadline):
                latencies.append((time.monotonic() - sent_at) * 1000.0)
            else:
                lost += 1
            target = started + (index + 1) * args.interval_ms / 1000.0
            delay = target - time.monotonic()
            if delay > 0:
                time.sleep(delay)
    finally:
        bus.close()
    elapsed = time.monotonic() - started
    after = can_counters(args.interface)
    result = {
        'interface': args.interface,
        'alarm_id': ALARM_ID,
        'ack_id': ACK_ID,
        'sequence': args.sequence,
        'sent': args.count,
        'acked': len(latencies),
        'lost': lost,
        'success_rate_percent': 100.0 * len(latencies) / args.count,
        'duration_s': elapsed,
        'effective_rate_hz': args.count / elapsed,
        'rtt_ms': {
            'min': min(latencies) if latencies else None,
            'mean': sum(latencies) / len(latencies) if latencies else None,
            'p50': percentile(latencies, 0.50),
            'p95': percentile(latencies, 0.95),
            'max': max(latencies) if latencies else None,
        },
        'before': {key: value for key, value in before.items()
                   if key != 'raw'},
        'after': {key: value for key, value in after.items()
                  if key != 'raw'},
        'can_state': 'ERROR-ACTIVE' if 'ERROR-ACTIVE' in after['raw'] else
                     ('ERROR-PASSIVE' if 'ERROR-PASSIVE' in after['raw'] else
                      ('BUS-OFF' if 'BUS-OFF' in after['raw'] else 'UNKNOWN')),
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if lost == 0 else 2


if __name__ == '__main__':
    raise SystemExit(main())
