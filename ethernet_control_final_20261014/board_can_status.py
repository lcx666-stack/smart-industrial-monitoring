#!/usr/bin/env python3
"""Read-only live state for the CS500 CAN alarm service."""

import datetime
import json
import re
import subprocess
import sys
import time

SERVICE = 'can-control-alarm'
INTERFACE = 'can0'


def run(argv):
    return subprocess.run(
        argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        universal_newlines=True, encoding='utf-8', errors='replace', timeout=5,
        check=False)


def service_state():
    result = run([
        'systemctl', 'show', SERVICE,
        '-p', 'ActiveState', '-p', 'SubState', '-p', 'MainPID',
        '-p', 'ActiveEnterTimestamp'
    ])
    fields = {}
    for line in result.stdout.splitlines():
        key, separator, value = line.partition('=')
        if separator:
            fields[key] = value
    try:
        main_pid = int(fields.get('MainPID', '0'))
    except ValueError:
        main_pid = 0
    return {
        'active_state': fields.get('ActiveState', 'unknown'),
        'sub_state': fields.get('SubState', 'unknown'),
        'main_pid': main_pid,
        'active_enter': fields.get('ActiveEnterTimestamp', ''),
    }


def pairing_state(main_pid, active_state):
    result = {
        'paired': False,
        'nonce': None,
        'known': active_state == 'active' and main_pid > 0,
    }
    if main_pid <= 0:
        return result
    journal = run([
        'journalctl', '-u', SERVICE, '_PID={}'.format(main_pid),
        '-b', '-o', 'cat', '--no-pager', '-n', '200'
    ])
    if journal.returncode:
        result['known'] = False
        return result
    for line in reversed(journal.stdout.splitlines()):
        match = re.search(r'STM32 paired:\s*nonce=([0-9A-Fa-f]{1,4})',
                          line.strip())
        if match:
            result['paired'] = True
            result['nonce'] = match.group(1).upper().zfill(4)
            break
    return result


def _two_rows(text, heading):
    match = re.search(
        r'^\s*{}:\s+bytes\s+packets[\s\S]*?\n\s*(\d+)\s+(\d+)\s+'
        r'(\d+)\s+(\d+)\s+(\d+)\s+(\d+)'.format(re.escape(heading)),
        text, re.MULTILINE)
    if not match:
        return None
    return [int(value) for value in match.groups()]


def can_state():
    result = run([
        'ip', '-details', '-statistics', 'link', 'show', INTERFACE
    ])
    if result.returncode:
        return {
            'available': False,
            'error': (result.stderr or result.stdout).strip()[-300:],
        }
    text = result.stdout
    state = re.search(r'\bcan\s+<[^>]+>\s+state\s+([A-Z-]+)', text)
    bitrate = re.search(r'(?:^|\s)bitrate\s+(\d+)', text)
    rx = _two_rows(text, 'RX')
    tx = _two_rows(text, 'TX')
    counters = re.search(
        r're-started\s+bus-errors\s+arbit-lost\s+error-warn\s+'
        r'error-pass\s+bus-off\s*\n\s*'
        r'(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)',
        text)
    counter_values = ([int(value) for value in counters.groups()]
                      if counters else [0, 0, 0, 0, 0, 0])
    return {
        'available': True,
        'state': state.group(1) if state else 'UNKNOWN',
        'bitrate': int(bitrate.group(1)) if bitrate else 0,
        'rx_packets': rx[1] if rx else 0,
        'tx_packets': tx[1] if tx else 0,
        'rx_errors': rx[2] if rx else 0,
        'tx_errors': tx[2] if tx else 0,
        'restarted': counter_values[0],
        'bus_errors': counter_values[1],
        'arbitration_lost': counter_values[2],
        'error_warning': counter_values[3],
        'error_passive': counter_values[4],
        'bus_off': counter_values[5],
    }


def snapshot():
    service = service_state()
    return {
        'ok': True,
        'checked_at': datetime.datetime.now(
            datetime.timezone.utc).isoformat(),
        'service': service,
        'pairing': pairing_state(service['main_pid'],
                                 service['active_state']),
        'can': can_state(),
    }


def emit(reply):
    print(json.dumps(reply, ensure_ascii=False, separators=(',', ':')),
          flush=True)


def main():
    if '--watch' not in sys.argv:
        emit(snapshot())
        return 0
    interval_ms = 500
    try:
        position = sys.argv.index('--interval-ms')
        interval_ms = max(100, min(5000, int(sys.argv[position + 1])))
    except (ValueError, IndexError):
        pass
    interval_seconds = interval_ms / 1000.0
    deadline = time.monotonic()
    while True:
        try:
            emit(snapshot())
            deadline += interval_seconds
            delay = deadline - time.monotonic()
            if delay > 0:
                time.sleep(delay)
            else:
                deadline = time.monotonic()
        except (BrokenPipeError, KeyboardInterrupt):
            return 0
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
