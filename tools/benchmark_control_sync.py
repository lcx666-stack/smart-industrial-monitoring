#!/usr/bin/env python3
"""Measure Ethernet control acknowledgement and state-apply latency."""

import argparse
import datetime
import json
import math
from pathlib import Path
import statistics
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] /
                       'ethernet_control_final_20261014'))
from control_client import ControlClient


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
        'min_ms': min(values) if values else None,
        'mean_ms': statistics.mean(values) if values else None,
        'p50_ms': percentile(values, 0.50),
        'p95_ms': percentile(values, 0.95),
        'max_ms': max(values) if values else None,
    }


def status_data(client):
    reply = client.request('status')
    if not reply.get('ok'):
        raise RuntimeError('status rejected: {}'.format(reply.get('error')))
    return reply.get('data', {})


def wait_for(client, predicate, timeout=4.0, interval=.05):
    started = time.monotonic()
    last = None
    while time.monotonic() - started < timeout:
        last = status_data(client)
        if predicate(last):
            return last, (time.monotonic() - started) * 1000.0
        time.sleep(interval)
    raise RuntimeError('state wait timed out: {}'.format(last))


def request_timed(client, operation, **fields):
    started = time.monotonic()
    reply = client.request(operation, **fields)
    elapsed = (time.monotonic() - started) * 1000.0
    if not reply.get('ok'):
        raise RuntimeError('{} rejected: {}'.format(
            operation, reply.get('error')))
    return reply, elapsed


def stopped(data):
    pl = data.get('pl', {})
    return (not data.get('motor_running') and
            int(pl.get('applied_duty', 0)) == 0 and
            not int(pl.get('motor_fault', 0)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', default='192.168.0.50')
    parser.add_argument('--key', required=True)
    parser.add_argument('--trials', type=int, default=5)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    if not 1 <= args.trials <= 20:
        parser.error('trials must be 1..20')

    client = ControlClient(args.host, args.key, use_agent=True)
    samples = {
        'start_ack_ms': [], 'start_apply_ms': [],
        'duty_ack_ms': [], 'duty_apply_ms': [],
        'stop_ack_ms': [], 'stop_apply_ms': [],
    }
    trials = []
    initial = status_data(client)
    preparation = {}
    try:
        if initial.get('wave_running'):
            started = time.monotonic()
            reply = client.request('wave_stop')
            if not reply.get('ok'):
                raise RuntimeError('wave_stop rejected: {}'.format(
                    reply.get('error')))
            preparation['wave_stop_ms'] = (
                time.monotonic() - started) * 1000.0
        current = status_data(client)
        if (current.get('fault_latched') or
                int(current.get('pl', {}).get('guard_fault', 0))):
            started = time.monotonic()
            reply = client.request('motor_clear', operator_confirmed=True)
            if not reply.get('ok'):
                raise RuntimeError('motor_clear rejected: {}'.format(
                    reply.get('error')))
            preparation['fault_clear_ms'] = (
                time.monotonic() - started) * 1000.0
        current, preparation['neutral_ms'] = wait_for(
            client, lambda data: stopped(data) and
            not data.get('fault_latched') and
            int(data.get('pl', {}).get('guard_fault', 0)) == 0)

        for trial_index in range(args.trials):
            trial = {'index': trial_index + 1}
            started = time.monotonic()
            reply, trial['start_ack_ms'] = request_timed(
                client, 'motor_start', operator_confirmed=True,
                duty_percent=10)
            trial['start_message'] = reply.get('data', {}).get('message', '')
            applied, trial['start_apply_ms'] = wait_for(
                client,
                lambda data: data.get('motor_running') and
                int(data.get('pl', {}).get('applied_duty', 0)) >= 10,
                timeout=5.0)
            trial['start_apply_ms'] = (
                time.monotonic() - started) * 1000.0
            time.sleep(.25)

            started = time.monotonic()
            reply, trial['duty_ack_ms'] = request_timed(
                client, 'motor_set_duty', operator_confirmed=True,
                duty_percent=15)
            applied, trial['duty_apply_ms'] = wait_for(
                client,
                lambda data: int(
                    data.get('pl', {}).get('applied_duty', 0)) >= 15,
                timeout=3.0)
            trial['duty_apply_ms'] = (
                time.monotonic() - started) * 1000.0

            started = time.monotonic()
            reply, trial['stop_ack_ms'] = request_timed(
                client, 'motor_stop')
            stopped_state, trial['stop_apply_ms'] = wait_for(
                client, stopped, timeout=6.0)
            trial['stop_apply_ms'] = (
                time.monotonic() - started) * 1000.0
            for key in ('start_ack_ms', 'start_apply_ms', 'duty_ack_ms',
                        'duty_apply_ms', 'stop_ack_ms', 'stop_apply_ms'):
                samples[key].append(trial[key])
            trials.append(trial)
    finally:
        final = status_data(client)
        if not stopped(final):
            try:
                client.request('motor_stop')
                final, _ = wait_for(client, stopped, timeout=6.0)
            except Exception:
                try:
                    client.request('motor_estop', operator_confirmed=True)
                except Exception:
                    pass
        client.close()

    result = {
        'checked_at': datetime.datetime.now(
            datetime.timezone.utc).isoformat(),
        'host': args.host,
        'trials': args.trials,
        'start_duty_percent': 10,
        'changed_duty_percent': 15,
        'preparation': preparation,
        'summary': {name: summarize(values)
                    for name, values in samples.items()},
        'samples': trials,
        'final_state': final,
        'final_motor_stopped': stopped(final),
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2),
                      encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result['final_motor_stopped'] else 2


if __name__ == '__main__':
    raise SystemExit(main())
