#!/usr/bin/env python3
"""Warm SSH agent candidate matching board_control.py, including wave ops."""

import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    'board_control_duty', os.path.join(HERE, 'board_control_duty.py'))
if spec is None or spec.loader is None:
    raise SystemExit('FAIL: board_control_duty.py not found')
board_control = importlib.util.module_from_spec(spec)
spec.loader.exec_module(board_control)

OPERATIONS = frozenset(('status', 'ai_start', 'ai_stop', 'blackbox_start',
                        'wave_start', 'wave_stop', 'motor_preflight',
                        'motor_start', 'motor_set_duty', 'motor_stop',
                        'motor_estop', 'motor_clear'))


def handle(request):
    op = request.get('op')
    if op not in OPERATIONS:
        return {'ok': False, 'error': 'unsupported operation'}
    duty = request.get('duty_percent')
    if duty is not None and (not isinstance(duty, int) or isinstance(duty, bool)):
        return {'ok': False, 'error': 'duty must be an integer'}
    with board_control.LOCK.open('a+b') as lock:
        board_control.fcntl.flock(lock.fileno(), board_control.fcntl.LOCK_EX)
        state = (json.loads(board_control.STATE.read_text())
                 if board_control.STATE.exists() else {})
        before = json.dumps(state, sort_keys=True)
        try:
            data = board_control.action(op, state, request.get('confirm') is True, duty)
            reply = {'ok': True, 'data': data}
        except Exception as error:
            reply = {'ok': False, 'error': str(error)}
        if json.dumps(state, sort_keys=True) != before:
            board_control.save(state)
    return reply


def main():
    if os.geteuid() != 0:
        raise SystemExit('root required')
    board_control.ROOT.mkdir(mode=0o700, exist_ok=True)
    for line in sys.stdin:
        try:
            request = json.loads(line)
            reply = handle(request) if isinstance(request, dict) else \
                {'ok': False, 'error': 'bad request json'}
        except Exception as error:
            reply = {'ok': False, 'error': str(error)}
        sys.stdout.write(json.dumps(reply, ensure_ascii=False) + '\n')
        sys.stdout.flush()


if __name__ == '__main__':
    raise SystemExit(main())
