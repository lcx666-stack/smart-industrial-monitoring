"""Run only fixed board actions over trusted, key-authenticated OpenSSH.

Two transports, one whitelist:

* a warm stdio agent on the board (`board_control_agent.py`). Importing the
  standard library on the board costs about 0.8 s per process (measured:
  `python3 -c pass` 0.16 s versus the import line 0.80 s), so the agent is
  started once inside a single authenticated SSH channel and answers JSON lines
  over stdin/stdout. No socket is opened.
* the original one-shot CLI (`board_control_duty.py`) as a fallback, so the
  console keeps working even when the agent cannot start.

Windows ships OpenSSH without connection multiplexing, so the remaining cost
per request is that handshake; the board-side import cost is what the agent
removes.
"""

import ipaddress
import hashlib
import json
import os
import queue
import re
import struct
import subprocess
import threading
import time


BOARD_HELPER = '/data/ethernet_control_20261014/board_control_duty.py'
BOARD_AGENT = '/data/ethernet_control_20261014/board_control_agent.py'
ALARM_HELPER = '/data/ethernet_control_20261014/board_alarm_events.py'
CAN_STATUS_HELPER = '/data/ethernet_control_20261014/board_can_status.py'
EVENT_ID = re.compile(r'^(wave-events|blackbox)-[0-9]+-[0-9a-f]{8}/event-[A-Za-z0-9_-]+$')
MAX_EVENT_BYTES = 16 * 1024 * 1024
OPERATIONS = frozenset(('status', 'ai_start', 'ai_stop', 'blackbox_start',
                        'wave_start', 'wave_stop', 'motor_preflight',
                        'motor_start', 'motor_set_duty', 'motor_stop',
                        'motor_estop', 'motor_clear'))
DUTY_OPERATIONS = frozenset(('motor_start', 'motor_set_duty'))
CONFIRM_OPERATIONS = frozenset(('motor_start', 'motor_set_duty',
                                'motor_estop', 'motor_clear'))


class ControlClient:
    AGENT_RETRY_S = 30.0
    AGENT_TIMEOUT_S = 20.0

    def __init__(self, host, key_path, ssh='ssh', use_agent=True):
        self.host = str(ipaddress.IPv4Address(host))
        if not key_path:
            raise ValueError('select an SSH private key')
        self.key_path = key_path
        self.ssh = ssh
        self.use_agent = bool(use_agent)
        self._flags = (0x08000000 if os.name == 'nt' else 0)
        self._agent = None
        self._agent_lines = queue.Queue()
        self._agent_reader = None
        self._agent_retry_after = 0.0
        result = self._run('true', timeout=7)
        if result.returncode:
            raise ConnectionError((result.stderr or 'SSH authentication failed').strip())

    # ---- transport ---------------------------------------------------------
    def _options(self, needs_stdin=False):
        argv = [self.ssh, '-T']
        if not needs_stdin:
            argv += ['-n']
        return argv + ['-i', self.key_path,
                       '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes',
                       '-o', 'StrictHostKeyChecking=yes', '-o', 'ConnectTimeout=5',
                       '-o', 'Compression=no']

    def _run(self, remote, timeout=12):
        argv = self._options() + ['root@' + self.host, remote]
        return subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              text=True, encoding='utf-8', errors='replace',
                              timeout=timeout, check=False, creationflags=self._flags)

    # ---- warm agent --------------------------------------------------------
    def _agent_alive(self):
        return self._agent is not None and self._agent.poll() is None

    def _start_agent(self):
        argv = self._options(needs_stdin=True) + [
            'root@' + self.host, 'python3', '-u', '-B', BOARD_AGENT]
        try:
            self._agent = subprocess.Popen(
                argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL, text=True, bufsize=1,
                creationflags=self._flags)
        except OSError:
            self._agent = None
            return False
        self._agent_reader = threading.Thread(target=self._drain_agent, daemon=True)
        self._agent_reader.start()
        return True

    def _drain_agent(self):
        process = self._agent
        try:
            for line in process.stdout:
                self._agent_lines.put(line)
        except (OSError, ValueError):
            pass
        finally:
            self._agent_lines.put(None)

    def _agent_reply(self, payload, timeout):
        if not self._agent_alive() and not self._start_agent():
            self._agent_retry_after = time.monotonic() + self.AGENT_RETRY_S
            return None
        try:
            self._agent.stdin.write(json.dumps(payload) + '\n')
            self._agent.stdin.flush()
            item = self._agent_lines.get(timeout=timeout)
        except (OSError, ValueError, queue.Empty):
            self._stop_agent()
            return None
        if item is None:
            self._stop_agent()
            return None
        try:
            reply = json.loads(item)
        except ValueError:
            self._stop_agent()
            return None
        if not isinstance(reply, dict) or not isinstance(reply.get('ok'), bool):
            self._stop_agent()
            return None
        return reply

    def _stop_agent(self, retry=True):
        process, self._agent = self._agent, None
        if retry:
            self._agent_retry_after = time.monotonic() + self.AGENT_RETRY_S
        if process is None:
            return
        try:
            process.terminate()
            process.wait(timeout=3)
        except (OSError, subprocess.SubprocessError):
            try:
                process.kill()
            except OSError:
                pass
        for stream in (process.stdin, process.stdout):
            try:
                if stream is not None:
                    stream.close()
            except OSError:
                pass

    # ---- public API --------------------------------------------------------
    def request(self, op, **fields):
        if op not in OPERATIONS:
            raise ValueError('unsupported operation')
        duty = None
        confirmed = fields.pop('operator_confirmed', False)
        if op in CONFIRM_OPERATIONS and confirmed is not True:
            raise ValueError('operator confirmation required')
        if op in DUTY_OPERATIONS:
            if set(fields) - {'duty_percent'}:
                raise ValueError('unexpected control parameters')
            duty = fields.get('duty_percent')
            if duty is not None and (not isinstance(duty, int) or
                                     isinstance(duty, bool) or not 10 <= duty <= 60):
                raise ValueError('duty must be an integer from 10 to 60 percent; board PL metadata must match')
        elif fields:
            raise ValueError('unexpected control parameters')

        if self.use_agent and time.monotonic() >= self._agent_retry_after:
            payload = {'op': op}
            if op in CONFIRM_OPERATIONS:
                payload['confirm'] = True
            if duty is not None:
                payload['duty_percent'] = duty
            reply = self._agent_reply(payload, timeout=self.AGENT_TIMEOUT_S)
            if reply is not None:
                return reply

        remote = 'python3 -B {} {}'.format(BOARD_HELPER, op)
        if op in CONFIRM_OPERATIONS:
            remote += ' --confirm'
        if duty is not None:
            remote += ' --duty-percent {}'.format(duty)
        result = self._run(remote, timeout=12)
        try:
            reply = json.loads(result.stdout.strip())
        except json.JSONDecodeError as error:
            raise ConnectionError('invalid board response: ' +
                                  (result.stderr or result.stdout)[-600:]) from error
        if not isinstance(reply, dict) or not isinstance(reply.get('ok'), bool):
            raise ConnectionError('invalid board response format')
        if result.returncode and reply['ok']:
            raise ConnectionError('SSH failed after board action: ' + result.stderr[-400:])
        return reply

    def run_shell(self, command):
        if not isinstance(command, str) or not command.strip():
            raise ValueError('empty root command')
        result = self._run(command, timeout=30)
        output = (result.stdout + result.stderr).strip()
        return {'ok': result.returncode == 0,
                'data': {'message': output[-2200:] or '命令完成，无输出'},
                'error': output[-2200:] or '命令退出码 {}'.format(result.returncode)}

    def can_alarm_status(self):
        """Read live service, STM32 pairing, and can0 state."""
        argv = self._options() + ['root@' + self.host, 'python3', '-B',
                                  CAN_STATUS_HELPER]
        result = subprocess.run(argv, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True,
                                encoding='utf-8', errors='replace',
                                timeout=12, creationflags=self._flags,
                                check=False)
        if result.returncode:
            raise ConnectionError((result.stderr or result.stdout).strip()[-600:])
        try:
            reply = json.loads(result.stdout.strip())
        except json.JSONDecodeError as error:
            raise ConnectionError('invalid CAN status response') from error
        if not isinstance(reply, dict) or reply.get('ok') is not True:
            raise ConnectionError('invalid CAN status format')
        return reply

    def open_can_alarm_stream(self, interval_ms=500):
        """Open one long-lived SSH stream that pushes CAN state updates."""
        if not isinstance(interval_ms, int) or not 100 <= interval_ms <= 5000:
            raise ValueError('invalid CAN status interval')
        argv = self._options() + [
            'root@' + self.host, 'python3', '-u', '-B', CAN_STATUS_HELPER,
            '--watch', '--interval-ms', str(interval_ms)
        ]
        return subprocess.Popen(
            argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, bufsize=1,
            creationflags=self._flags)

    def list_alarm_events(self):
        argv = self._options() + ['root@' + self.host, 'python3', '-B',
                                  ALARM_HELPER, 'list']
        result = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=15, creationflags=self._flags)
        if result.returncode:
            raise ConnectionError(result.stderr.decode('utf-8', 'replace')[-500:])
        reply = json.loads(result.stdout.decode('utf-8'))
        if not isinstance(reply, dict) or not isinstance(reply.get('events'), list):
            raise ValueError('invalid alarm catalog')
        return reply['events']

    def fetch_alarm_event(self, event_id):
        if not isinstance(event_id, str) or not EVENT_ID.fullmatch(event_id):
            raise ValueError('invalid event ID')
        argv = self._options() + ['root@' + self.host, 'python3', '-B',
                                  ALARM_HELPER, 'fetch', event_id]
        result = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=35, creationflags=self._flags)
        if result.returncode:
            raise ConnectionError(result.stderr.decode('utf-8', 'replace')[-500:])
        raw = result.stdout
        if len(raw) < 4:
            raise ValueError('truncated alarm response')
        header_length = struct.unpack_from('<I', raw)[0]
        if not 0 < header_length <= 8192 or len(raw) < 4 + header_length:
            raise ValueError('invalid alarm response header')
        event = json.loads(raw[4:4 + header_length].decode('utf-8'))
        binary = raw[4 + header_length:]
        expected = event.get('binary_bytes')
        digest = event.get('binary_sha256')
        if (event.get('id') != event_id or type(expected) is not int or
                expected > MAX_EVENT_BYTES or expected <= 0 or
                len(binary) != expected or expected != event.get('frame_count', 0) * 32 or
                not isinstance(digest, str) or len(digest) != 64 or
                hashlib.sha256(binary).hexdigest() != digest.lower()):
            raise ValueError('black-box waveform size or SHA-256 mismatch')
        return event, binary

    def close(self):
        """Terminate the agent so no privileged helper lingers after exit."""
        self._stop_agent(retry=False)
