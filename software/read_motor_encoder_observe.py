#!/usr/bin/env python3
"""Read frozen ELG1 events and pulse statistics. Never writes MMIO or starts a motor."""
import argparse
import json
import os
import sys

import motor_ps as ps

ID = 0x454C4731
MASK64 = (1 << 64)-1
WIDTH_BINS_NS = (0, 40, 160, 1000, 10000, 100000, 1000000, 10000000)
PROXIMITY_BINS = ('0..100ns', '100ns..1us', '1..10us', '>=10us', 'no_previous_PWM_edge')


def u64(page, offset):
    return ps.u32(page, offset) | ps.u32(page, offset+4) << 32


def relative(tick, origin):
    value = (tick-origin) & MASK64
    return value-(1 << 64) if value & (1 << 63) else value


def header(device):
    return tuple(ps.u32(device.status, address) for address in range(0x408, 0x458, 4))


def decode(word):
    if word >> 25 or (word >> 16 & 127) > 100:
        raise RuntimeError('Invalid observation event state')
    return dict(raw_ab=[word & 1, word >> 1 & 1],
                qualified_ab=[word >> 2 & 1, word >> 3 & 1],
                raw_ready=bool(word & 16), qualified_ready=bool(word & 32),
                raw_activity=bool(word & 64), encoder_step=bool(word & 128),
                encoder_invalid=bool(word & 256), core_fault=bool(word & 512),
                guard_fault=bool(word & 1024), drive_permit=bool(word & 2048),
                pwm=bool(word & 4096), stby=bool(word & 8192),
                an1=bool(word & 16384), an2=bool(word & 32768),
                duty_percent=word >> 16 & 127, ctrl=word >> 23 & 3)


def read_observation(device, filter4=False):
    features = ps.FILTER4_OBSERVE_FEATURES if filter4 else ps.OBSERVE_GUARDED_FEATURES
    device.verify_image(features)
    page = device.status
    if (ps.u32(page, 0x400), ps.u32(page, 0x404), ps.u32(page, 0x100),
            ps.u32(page, 0x104), ps.u32(page, 0x228)) != (ID, ps.ABI, ps.GUARD_ID, ps.ABI, 4 if filter4 else 1):
        raise RuntimeError('Observation/guard identity or encoder profile mismatch')
    before = header(device)
    flags = ps.u32(page, 0x408)
    if flags & 3 != 3:
        raise RuntimeError('Observation has not frozen; this reader never starts or triggers the drive')
    layout = tuple(ps.u32(page, address) for address in (0x40c, 0x410, 0x414, 0x438, 0x448, 0x44c, 0x450))
    if layout != (100000000, 64, 64, 200000, 4, 128, 0x800) or flags & ~63 or flags & 12 != 12:
        raise RuntimeError('Unsupported observation layout/clock/readiness')
    pre, next_index, post = (ps.u32(page, address) for address in (0x418, 0x41c, 0x420))
    reason, dropped = ps.u32(page, 0x424), ps.u32(page, 0x43c)
    trigger, freeze, start = (u64(page, address) for address in (0x428, 0x430, 0x440))
    if (not 0 <= pre <= 64 or not 0 <= next_index < 64 or not 1 <= post <= 64 or
            (pre < 64 and next_index != pre) or not 1 <= reason <= 7 or
            (dropped and post != 64) or
            (freeze-trigger) & MASK64 != 200000 or bool(flags & 16) != bool(dropped) or
            not ps.u32(page, 0x454) & 4 or relative(freeze, start) < 0):
        raise RuntimeError('Malformed observation header')
    saturated = bool(flags & 32)
    indices = ([(next_index+i) & 63 for i in range(pre)] if pre == 64 else list(range(pre)))
    indices += list(range(64, 64+post))
    events = []
    previous = None
    for physical in indices:
        offset = 0x800+16*physical
        tick, word, delta = u64(page, offset), ps.u32(page, offset+8), ps.u32(page, offset+12)
        age = relative(tick, trigger)
        state = decode(word)
        if ((physical < 64 and age >= 0) or (physical == 64 and age != 0) or
                (physical > 64 and not 0 < age <= 200000) or
                (previous is not None and (relative(tick, previous['tick']) <= 0 or
                                           delta != word ^ previous['state_word']))):
            raise RuntimeError('Observation event order/delta is inconsistent')
        event = dict(tick=tick, relative_ns=age*10, state_word=word, change_mask=delta,
                     trigger_event=physical == 64, **state)
        events.append(event)
        previous = event
    trigger_event = events[pre]
    if any(reason & (1 << bit) and not trigger_event[name] for bit, name in enumerate(
            ('encoder_invalid', 'core_fault', 'guard_fault'))):
        raise RuntimeError('First-fault reason does not match its event')
    channels = {}
    for channel, base in (('A', 0x500), ('B', 0x600)):
        rises, falls, highs, lows = (ps.u32(page, base+offset) for offset in (0, 4, 8, 12))
        seen, level = ps.u32(page, base+0x38), ps.u32(page, base+0x3c)
        edge_tick = u64(page, base+0x30)
        if seen not in (0, 1) or level not in (0, 1) or (seen and relative(freeze, edge_tick) < 0):
            raise RuntimeError('Malformed pulse statistics')
        item = dict(rises=rises, falls=falls, open_level=level,
                    open_tail_ns=relative(freeze, edge_tick)*10 if seen else None,
                    initial_partial_segment_excluded=True)
        for label, count, min_offset, max_offset, hist_offset in (
                ('high', highs, 0x10, 0x18, 0x40), ('low', lows, 0x20, 0x28, 0x60)):
            minimum, maximum = u64(page, base+min_offset), u64(page, base+max_offset)
            histogram = [ps.u32(page, base+hist_offset+4*i) for i in range(8)]
            if (not saturated and (sum(histogram) != count or count > (falls if label == 'high' else rises)) or
                    (count and (not 0 < minimum <= maximum <= (freeze-start) & MASK64)) or
                    (not count and (minimum != MASK64 or maximum != 0))):
                raise RuntimeError('Pulse histogram/minimum/maximum disagree')
            item[label] = dict(completed=count, minimum_ns=minimum*10 if count else None,
                               maximum_ns=maximum*10 if count else None, histogram=histogram)
        proximity = [ps.u32(page, base+0x80+4*i) for i in range(5)]
        if not saturated and sum(proximity) != rises+falls:
            raise RuntimeError('PWM proximity counts disagree with input edges')
        item['since_previous_pwm_edge'] = dict(zip(PROXIMITY_BINS, proximity))
        channels[channel] = item
    if header(device) != before:
        raise RuntimeError('Observation changed during read; possible reset')
    return dict(features=features, trace_id='ELG1', clock_hz=100000000,
                trigger_tick=trigger, freeze_tick=freeze, statistics_start_tick=start,
                post_fault_ns=2000000, retained_pre_events=pre, retained_post_events=post,
                dropped_post_events=dropped, counters_saturated=saturated,
                trigger_reason=[name for bit, name in enumerate(
                    ('encoder invalid', 'core fault rising', 'guard fault rising')) if reason & (1 << bit)],
                retained_pre_span_ns=-events[0]['relative_ns'] if pre else 0,
                width_bins_lower_ns=WIDTH_BINS_NS,
                pwm_rises=ps.u32(page, 0x460), pwm_falls=ps.u32(page, 0x464),
                channels=channels, events=events,
                limitations='Digital levels after CDC, not analog voltage. PRE span depends on edge rate. '
                            'Only completed segments enter histograms; open tail is separate. '
                            'Statistics continue through the 2 ms deadline even if POST storage fills. '
                            'Proximity to PWM does not prove causation.')


def print_compact(result):
    print('ELG1 features=0x{:X} reason={} pre={} post={} dropped_post={} saturated={}'.format(
        result['features'], ','.join(result['trigger_reason']), result['retained_pre_events'],
        result['retained_post_events'], result['dropped_post_events'], result['counters_saturated']))
    print('pre_span={}ns post_window={}ns PWM rises={} falls={}'.format(
        result['retained_pre_span_ns'], result['post_fault_ns'], result['pwm_rises'], result['pwm_falls']))
    print('Width bins lower bounds (ns): {}'.format(list(WIDTH_BINS_NS)))
    for channel, values in result['channels'].items():
        print('{} rises={} falls={} open_level={} open_tail={}ns (not completed)'.format(
            channel, values['rises'], values['falls'], values['open_level'], values['open_tail_ns']))
        for level in ('high', 'low'):
            pulse = values[level]
            print('  {} completed={} min={}ns max={}ns bins={}'.format(
                level, pulse['completed'], pulse['minimum_ns'], pulse['maximum_ns'], pulse['histogram']))
        print('  since_previous_PWM_edge={}'.format(values['since_previous_pwm_edge']))
    print('relative_ns  rawAB qualifiedAB invalid core guard permit PWM STBY duty ctrl')
    for row in result['events']:
        print('{:+11d}  {}{} {}{} {} {} {} {} {} {} {:3d} {}{}'.format(
            row['relative_ns'], *row['raw_ab'], *row['qualified_ab'], int(row['encoder_invalid']),
            int(row['core_fault']), int(row['guard_fault']), int(row['drive_permit']),
            int(row['pwm']), int(row['stby']), row['duty_percent'], row['ctrl'],
            ' TRIGGER' if row['trigger_event'] else ''))
    print('Observation only; motor NOT armed; no MMIO writes. ' + result['limitations'])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--json', action='store_true', help='Print full machine-readable observation')
    parser.add_argument('--encoder-filter4', action='store_true', help='Read the explicitly selected 0x1B43 four-sample image')
    args = parser.parse_args(argv)
    if os.geteuid() != 0:
        parser.error('Run as root for MMIO diagnostics')
    try:
        with ps.MotorDevice() as device:
            result = read_observation(device, args.encoder_filter4)
        if args.json:
            print(json.dumps(result, ensure_ascii=True, indent=2))
        else:
            print_compact(result)
        return 0
    except (OSError, RuntimeError) as error:
        print('FAIL: {}'.format(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
