#!/usr/bin/env python3
"""Hardware encoder counter capture on 0x1B43; no drive unless explicit --arm.

RAW is after the existing two-stage CDC, before four-sample qualification.
Qualified counters are coherent CAPTURE snapshots. RAW counters are separate
live 32-bit reads, not a same-clock snapshot or an external voltage measurement.
Only bounded RAM storage is used; no SD log/firmware writes or fault clears.
"""
import math
import os
import signal
import statistics
import sys
import time

import motor_ps as ps
import motor_guarded_trial as trial

INTERVAL = .05
MAX_RECORDS = 256
MASK64 = (1 << 64) - 1


def disabled(device):
    if ps.u32(device.status, 0x120) & 1 or ps.u32(device.status, 0x48) & 0x1c0:
        raise RuntimeError("Drive active; counter capture does not stop or clear another controller")


def verify(device):
    device.verify_image(ps.FILTER4_OBSERVE_FEATURES)
    expected = ((0x100, ps.GUARD_ID), (0x104, ps.ABI),
                (0x160, trial.ENCODER_ID), (0x164, ps.ABI),
                (0x228, 4), (0x40c, 100000000))
    if any(ps.u32(device.status, address) != value for address, value in expected):
        raise RuntimeError("Wrong guard/encoder/qualifier/clock metadata; no writes made")
    disabled(device)
    if ps.u32(device.status, 0x408) & 15 != 12:
        raise RuntimeError("RAW logger not ready or already frozen; do not clear/retry automatically")


def measure_clock(device):
    def stamp():
        disabled(device)
        before = time.monotonic()
        sample = device.capture()
        after = time.monotonic()
        disabled(device)
        return sample.ticks, (before+after)/2, (after-before)/2
    first = stamp()
    results = []
    for _ in range(2):
        time.sleep(.5)
        last = stamp()
        wall = last[1]-first[1]
        uncertainty = last[2]+first[2]
        ticks = (last[0]-first[0]) & MASK64
        if wall <= 0 or uncertainty >= wall or ticks == 0:
            raise RuntimeError("PL clock counter stopped or reference interval unusable")
        results.append((ticks/wall, ticks/(wall+uncertainty), ticks/(wall-uncertainty)))
        first = last
    return results


class Recorder:
    def __init__(self, device):
        self.device = device
        self.started = time.monotonic()
        self.last_time = None
        self.rows = []

    def add(self, sample, force=False):
        now = time.monotonic()
        if not force and self.last_time is not None and now-self.last_time < INTERVAL:
            return
        if len(self.rows) >= MAX_RECORDS:
            raise RuntimeError("RAM record limit reached; no data silently discarded")
        encoder = trial.encoder_snapshot(self.device, sample)
        raw = tuple(ps.u32(self.device.status, address) for address in (0x500, 0x504, 0x600, 0x604))
        raw_levels = ps.u32(self.device.status, 0x454) & 3
        flags = ps.u32(self.device.status, 0x408)
        if self.rows and sample.ticks < self.rows[-1]['ticks']:
            raise RuntimeError("PL counter reset during capture")
        self.rows.append(dict(seconds=now-self.started, ticks=sample.ticks, raw=raw,
                              raw_levels=raw_levels, encoder=encoder, flags=flags,
                              ctrl=sample.ctrl, target=sample.target_q16,
                              guard=ps.u32(self.device.status, 0x124), core=ps.u32(self.device.status, 0x50)))
        self.last_time = now


class RecordingDevice:
    """Delegate all safety/control operations unchanged to the original device."""
    def __init__(self, device, recorder):
        self.device, self.recorder = device, recorder

    def __getattr__(self, name):
        return getattr(self.device, name)

    def check_fresh(self, *args):
        sample = self.device.check_fresh(*args)
        self.recorder.add(sample)
        return sample


def ab(levels):
    return '{}{}'.format(levels & 1, levels >> 1 & 1)


def print_records(recorder):
    print('RAW: live counters after CDC, before filter; qualified: coherent snapshot')
    print('t_s RAW_AB QUAL_AB dRAW_A_up/down dRAW_B_up/down dQUAL_A/B steps F R invalid frozen sat ctrl')
    previous = None
    for row in recorder.rows:
        if previous is None:
            raw = (0, 0, 0, 0)
            diff = dict.fromkeys(('a', 'b', 'steps', 'forward', 'reverse', 'invalid'), 0)
        else:
            # ELG1 RAW counters saturate. Never pretend they are wraparound counts.
            raw = tuple(last-first for first, last in zip(previous['raw'], row['raw']))
            if any(value < 0 for value in raw):
                raise RuntimeError('RAW counters decreased; possible reset')
            diff = trial.deltas(previous['encoder'], row['encoder'])
        print('{:.3f} {} {} {}/{} {}/{} {}/{} {} {} {} {} {} {} {}'.format(
            row['seconds'], ab(row['raw_levels']), ab(row['encoder'].levels),
            *raw, diff['a'], diff['b'], diff['steps'], diff['forward'], diff['reverse'],
            diff['invalid'], int(bool(row['flags'] & 2)), int(bool(row['flags'] & 32)), row['ctrl']))
        previous = row
    if len(recorder.rows) >= 2:
        first, last = recorder.rows[0], recorder.rows[-1]
        raw = tuple(b-a for a, b in zip(first['raw'], last['raw']))
        diff = trial.deltas(first['encoder'], last['encoder'])
        print('TOTAL RAW_A_up/down={}/{} RAW_B_up/down={}/{} QUAL_A={} QUAL_B={} steps={} F={} R={} invalid={}'.format(
            *raw, diff['a'], diff['b'], diff['steps'], diff['forward'], diff['reverse'], diff['invalid']))
    print('Counts alone do NOT certify the encoder, RPM or analog signal integrity.')


def pulse_statistics(device):
    disabled(device)
    def snapshot():
        return (ps.u32(device.status, 0x408),
                tuple(tuple(ps.u32(device.status, base+offset) for offset in range(0, 0x94, 4))
                      for base in (0x500, 0x600)))
    first, second = snapshot(), snapshot()
    disabled(device)
    if first != second:
        print('NOTE: RAW pulse statistics still changing; no coherent width summary claimed')
        return
    print('RAW width statistics since boot; completed segments only; widths are PL clock cycles')
    print('width-bin lower bounds in cycles: 0,4,16,100,1000,10000,100000,1000000')
    for name, words in zip(('A', 'B'), first[1]):
        def wide(index):
            return words[index] | words[index+1] << 32
        print('RAW_{} up={} down={} level={}'.format(name, words[0], words[1], words[15]))
        for level, count, minimum, maximum, bins in (
                ('high', words[2], 4, 6, words[16:24]), ('low', words[3], 8, 10, words[24:32])):
            print(' {} count={} min_cycles={} max_cycles={} bins={}'.format(
                level, count, wide(minimum) if count else None, wide(maximum) if count else None, list(bins)))
    if first[0] & 32:
        print('WARNING: RAW counters saturated; interval counts are not complete')


def parser_definition():
    parser = trial.parser_definition()
    parser.description = __doc__
    parser.add_argument('--observe-seconds', type=float, default=3., help='Passive observation only, .5..10 s')
    return parser


def main(argv=None):
    parser = parser_definition()
    args = parser.parse_args(argv)
    if args.encoder_filtered or args.encoder_bypass or args.encoder_observe:
        parser.error('This counter tool selects only the current 0x1B43 filter4 image')
    args.encoder_filter4 = True
    trial.validate_args(parser, args)  # Complete ARM acceptance checked before MMIO.
    if not math.isfinite(args.observe_seconds) or not .5 <= args.observe_seconds <= 10:
        parser.error('Passive observe-seconds must be .5..10')
    if args.arm and args.observe_seconds != 3:
        parser.error('observe-seconds does not change the fixed 1.5 s motor deadline')
    if os.geteuid() != 0:
        parser.error('Run as root for MMIO counter access')
    def interrupted(_number, _frame):
        raise KeyboardInterrupt()
    old_handler = signal.signal(signal.SIGTERM, interrupted)
    try:
        with ps.MotorDevice() as device:
            verify(device)
            clock = measure_clock(device)
            for index, (hz, lower, upper) in enumerate(clock):
                print('CLOCK {} PL_MHz={:.6f} bounds=[{:.6f},{:.6f}]'.format(index, hz/1e6, lower/1e6, upper/1e6))
            if args.arm and (not 98e6 <= statistics.median(item[0] for item in clock) <= 102e6 or
                             any(lower < 98e6 or upper > 102e6 for _hz, lower, upper in clock)):
                raise RuntimeError('Measured PL clock not near 100 MHz; ARM refused')
            recorder = Recorder(device)
            if args.arm:
                offset, sample, encoder = trial.preflight(device, filter4=True)
                recorder.started = time.monotonic()
                recorder.add(sample, force=True)
                error = None
                try:
                    trial.run_trial(RecordingDevice(device, recorder), args, offset, sample, encoder)
                except (OSError, RuntimeError, KeyboardInterrupt) as caught:
                    error = caught
                # Never print deferred records or continue diagnostics while armed.
                disabled(device)
                recorder.add(device.capture(), force=True)
                print_records(recorder)
                pulse_statistics(device)
                if error is not None:
                    raise error
            else:
                recorder.add(device.capture(), force=True)
                while time.monotonic()-recorder.started < args.observe_seconds:
                    time.sleep(INTERVAL)
                    disabled(device)
                    recorder.add(device.capture())
                recorder.add(device.capture(), force=True)
                disabled(device)
                print_records(recorder)
                pulse_statistics(device)
                print('DONE: passive capture only; motor NOT armed; snapshot requests only')
        return 0
    except KeyboardInterrupt:
        print('Interrupted; no automatic clear or retry', file=sys.stderr)
        return 130
    except (OSError, RuntimeError) as error:
        print('FAIL: {}'.format(error), file=sys.stderr)
        return 1
    finally:
        signal.signal(signal.SIGTERM, old_handler)


if __name__ == '__main__':
    raise SystemExit(main())
