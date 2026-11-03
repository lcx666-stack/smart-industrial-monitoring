#!/usr/bin/env python3
"""Measure 50 kHz timestamp spacing and DMA-to-PS sample age on CS500."""

import argparse
import datetime
import json
import math
import mmap
import os
import signal
import statistics
import struct
import sys
import time

sys.path.insert(0, '/mnt/sdboot')
from motor_blackbox import WaveDevice

FRAME = struct.Struct('<hhhhIIQiI')
FRAME_SIZE = FRAME.size
CLOCK_HZ = 100000000
MST_CAPTURE = 0x08
MST_SNAPSHOT_SEQ = 0x0c
MST_SAMPLE_AGE = 0x2c
MST_TICKS_LO = 0x40
MST_TICKS_HI = 0x44
STOP = False


def request_stop(_number, _frame):
    global STOP
    STOP = True


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
        'min_us': min(values) if values else None,
        'mean_us': statistics.mean(values) if values else None,
        'p50_us': percentile(values, 0.50),
        'p95_us': percentile(values, 0.95),
        'max_us': max(values) if values else None,
    }


class PlClock:
    def __init__(self):
        self.fd = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
        self.page = mmap.mmap(
            self.fd, 4096, offset=0x80000000, access=mmap.ACCESS_WRITE)

    def capture(self):
        previous = struct.unpack_from('<I', self.page, MST_SNAPSHOT_SEQ)[0]
        struct.pack_into('<I', self.page, MST_CAPTURE, 1)
        current = previous
        for _ in range(1000):
            current = struct.unpack_from(
                '<I', self.page, MST_SNAPSHOT_SEQ)[0]
            if current != previous:
                break
        else:
            raise RuntimeError('PL snapshot capture did not advance')
        low = struct.unpack_from('<I', self.page, MST_TICKS_LO)[0]
        high = struct.unpack_from('<I', self.page, MST_TICKS_HI)[0]
        sample_age = struct.unpack_from('<I', self.page, MST_SAMPLE_AGE)[0]
        return low | (high << 32), sample_age

    def close(self):
        self.page.close()
        os.close(self.fd)


def main():
    global STOP
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', default='/dev/motor_wave_dma')
    parser.add_argument('--duration', type=float, default=2.0)
    parser.add_argument('--output', default='/tmp/acquisition_latency.json')
    args = parser.parse_args()
    if not 0.2 <= args.duration <= 20.0:
        parser.error('duration must be 0.2..20 seconds')
    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)

    device = WaveDevice(args.device)
    clock = PlClock()
    tick_deltas = []
    transport_age_us = []
    sample_age_us = []
    read_batch_frames = []
    read_costs_us = []
    frames = 0
    initial = None
    final = None
    try:
        initial = device.status()
        device.start()
        time.sleep(.25)
        catch_up_deadline = time.monotonic() + 1.0
        while not STOP and time.monotonic() < catch_up_deadline:
            data = device.read()
            if not data:
                break
            frames += len(data) // FRAME_SIZE
            if not tick_deltas:
                previous_ticks = None
                for offset in range(0, len(data), FRAME_SIZE):
                    ticks = FRAME.unpack_from(data, offset)[6]
                    if previous_ticks is not None:
                        delta = ticks - previous_ticks
                        if 0 < delta < 100000:
                            tick_deltas.append(delta)
                    previous_ticks = ticks
        deadline = time.monotonic() + args.duration
        while not STOP and time.monotonic() < deadline:
            read_started = time.perf_counter()
            data = device.read()
            read_costs_us.append(
                (time.perf_counter() - read_started) * 1000000.0)
            if not data:
                time.sleep(.0001)
                continue
            batch_frames = len(data) // FRAME_SIZE
            frames += batch_frames
            read_batch_frames.append(batch_frames)
            latest_ticks = FRAME.unpack_from(
                data, len(data) - FRAME_SIZE)[6]
            capture_ticks, age_cycles = clock.capture()
            age_cycles_now = capture_ticks - latest_ticks
            if 0 < age_cycles_now < CLOCK_HZ:
                transport_age_us.append(
                    age_cycles_now * 1000000.0 / CLOCK_HZ)
            if age_cycles != 0xffffffff and age_cycles < CLOCK_HZ:
                sample_age_us.append(
                    age_cycles * 1000000.0 / CLOCK_HZ)
        time.sleep(.05)
        final = device.status()
    finally:
        try:
            device.stop()
            deadline = time.monotonic() + 5.0
            while time.monotonic() < deadline:
                data = device.read()
                if data:
                    continue
                state = device.status()
                if (state['produced'] == state['consumed'] and
                        not (state['flags'] & 3)):
                    break
                time.sleep(.005)
        finally:
            device.close()
            clock.close()

    tick_period_us = ([delta * 1000000.0 / CLOCK_HZ
                       for delta in tick_deltas])
    result = {
        'checked_at': datetime.datetime.now(
            datetime.timezone.utc).isoformat(),
        'clock_hz': CLOCK_HZ,
        'duration_s': args.duration,
        'frames_read': frames,
        'sample_tick_interval': summarize(tick_period_us),
        'sample_rate_from_ticks_hz': (
            CLOCK_HZ / statistics.mean(tick_deltas)
            if tick_deltas else None),
        'dma_to_ps_sample_age_us': summarize(transport_age_us),
        'pl_latest_sample_age_us': summarize(sample_age_us),
        'read_batch_frames': {
            'count': len(read_batch_frames),
            'mean': statistics.mean(read_batch_frames)
            if read_batch_frames else None,
            'max': max(read_batch_frames) if read_batch_frames else None,
        },
        'device_read_cost_us': summarize(read_costs_us),
        'initial_status': initial,
        'final_status': final,
    }
    with open(args.output, 'w') as output:
        json.dump(result, output, ensure_ascii=False, indent=2)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
