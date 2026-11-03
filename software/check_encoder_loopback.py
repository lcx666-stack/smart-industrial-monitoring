#!/usr/bin/env python3
"""Read 0x3B43 known A/B loopback; physical motor outputs are hard-low."""
import argparse
import math
import os
import signal
import sys
import time

import motor_ps as ps

FEATURES = 0x00003B43
ENCODER_ID = 0x454E4331
TRACE_ID = 0x45545231
OBSERVE_ID = 0x454C4731
MASK64 = (1 << 64) - 1


def verify(device):
    device.verify_image(FEATURES)
    expected = ((0x100, ps.GUARD_ID), (0x104, ps.ABI),
                (0x160, ENCODER_ID), (0x164, ps.ABI),
                (0x200, TRACE_ID), (0x204, ps.ABI),
                (0x228, 4), (0x400, OBSERVE_ID), (0x404, ps.ABI),
                (0x40c, 100000000), (0x130, 40000))
    if any(ps.u32(device.status, address) != value for address, value in expected):
        raise RuntimeError('Loopback guard, encoder, clock, trace or ABI mismatch')
    if ps.u32(device.status, 0x120) & 1 or ps.u32(device.status, 0x48) & 0x1c0:
        raise RuntimeError('Drive not disabled; disconnect motor power')
    if ps.u32(device.status, 0x124) or ps.u32(device.status, 0x50):
        raise RuntimeError('Latched fault in loopback image; inspect jumpers')
    if ps.u32(device.status, 0x408) & 15 != 12:
        raise RuntimeError('Loopback observer not ready or faulted')


def snapshot(device):
    verify(device)
    before = time.monotonic()
    sample = device.capture()
    after = time.monotonic()
    encoder = tuple(ps.u32(device.status, offset) for offset in
                    (0x168, 0x16c, 0x170, 0x174, 0x178, 0x17c, 0x180))
    raw = tuple(ps.u32(device.status, offset) for offset in
                (0x500, 0x504, 0x600, 0x604))
    if sample.seq != ps.u32(device.status, 0x0c) or not encoder[0] & 4:
        raise RuntimeError('Encoder snapshot changed or not initialized')
    if encoder[4]:
        raise RuntimeError('Known loopback already registered invalid transitions')
    verify(device)
    return sample.ticks, (before+after)/2, (after-before)/2, encoder, raw


def delta(first, last):
    value = last-first
    if value < 0:
        raise RuntimeError('Counter decreased; possible reset during loopback')
    return value


def evaluate(first, last):
    ticks = (last[0]-first[0]) & MASK64
    seconds = last[1]-first[1]
    uncertainty = first[2]+last[2]
    if not ticks or seconds <= 0 or uncertainty >= seconds:
        raise RuntimeError('PL clock or Linux reference interval invalid')
    frequency = ticks/seconds
    lower = ticks/(seconds+uncertainty)
    upper = ticks/(seconds-uncertainty)
    q = tuple(delta(first[3][index], last[3][index]) for index in range(1, 7))
    raw = tuple(delta(a, b) for a, b in zip(first[4], last[4]))
    cycles_per_quad = 2000
    expected = ticks/cycles_per_quad
    return dict(clock_mhz=frequency/1e6, clock_lower_mhz=lower/1e6,
                clock_upper_mhz=upper/1e6, seconds=seconds, ticks=ticks,
                expected_phase_rises=expected, qualified=q, raw=raw)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=float, default=2.)
    args = parser.parse_args(argv)
    if not math.isfinite(args.seconds) or not 1 <= args.seconds <= 3:
        parser.error('Observation must be 1..3 seconds')
    if os.geteuid() != 0:
        parser.error('Run as root for loopback diagnostics')
    old_handler = signal.getsignal(signal.SIGTERM)
    def interrupted(_signum, _frame):
        raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM, interrupted)
    try:
        with ps.MotorDevice() as device:
            first = snapshot(device)
            time.sleep(args.seconds)
            last = snapshot(device)
            result = evaluate(first, last)
            q = result['qualified']
            raw = result['raw']
            print('PL_MHz={:.6f} bounds=[{:.6f},{:.6f}] duration={:.6f}s'.format(
                result['clock_mhz'], result['clock_lower_mhz'],
                result['clock_upper_mhz'], result['seconds']))
            print('Expected each phase rises={:.1f} at 50 kHz; expected legal steps={:.1f}'.format(
                result['expected_phase_rises'], 4*result['expected_phase_rises']))
            print('RAW A_up/down={}/{} B_up/down={}/{}'.format(*raw))
            print('QUAL A_up={} B_up={} legal={} invalid={} forward={} reverse={}'.format(
                q[0], q[1], q[2], q[3], q[4], q[5]))
            highs = []
            for base in (0x500, 0x600):
                low = ps.u32(device.status, base+0x10)
                high = ps.u32(device.status, base+0x14)
                highs.append(low | high << 32)
            print('RAW high width minimum: A={} B={} PL clocks'.format(*highs))
            # Require both phase counts, a Gray direction, clock and hard-off
            # package state. A failed image is diagnostic, never a drive test.
            target = result['expected_phase_rises']
            tolerance = max(8, .02*target)
            if (result['clock_lower_mhz'] < 98 or result['clock_upper_mhz'] > 102 or
                any(abs(count-target) > tolerance for count in (raw[0], raw[2], q[0], q[1])) or
                any(abs(count-target) > tolerance for count in (raw[1], raw[3])) or
                abs(q[2]-4*target) > 4*tolerance or q[4] != q[2] or q[5] or q[3] or
                any(not 995 <= width <= 1005 for width in highs)):
                raise RuntimeError('Known quadrature waveform failed dynamic input or decoder check')
            print('PASS: both physical encoder inputs captured the known waveform; motor outputs stayed disabled')
        return 0
    except KeyboardInterrupt:
        print('Interrupted; no motor-control writes', file=sys.stderr)
        return 130
    except (OSError, RuntimeError) as error:
        print('FAIL: {}'.format(error), file=sys.stderr)
        return 1
    finally:
        signal.signal(signal.SIGTERM, old_handler)


if __name__ == '__main__':
    raise SystemExit(main())
