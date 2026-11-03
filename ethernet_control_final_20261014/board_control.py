#!/usr/bin/env python3
"""Ethernet board actions with the guarded raw-vibration motor profile."""

import argparse
import fcntl
import hashlib
import json
import mmap
import os
import secrets
import signal
import struct
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path('/data/ethernet_control_20261014')
ETHERNET_MOTOR_CONTROL = 1
BOOT_MOUNT = Path('/mnt/sdboot')
STATE = ROOT / 'state.json'
LOCK = ROOT / 'lock'
AI = Path('/data/board_ai_round2_bias_default_20261017/run_round2_bias_roi_fast_20261017.sh')
MOTOR = BOOT_MOUNT / 'motor_open_loop.py'
MOTOR10 = Path('/data/motor_anomaly_candidate_20261017/motor_open_loop_pwm10_anomaly.py')
MOTOR_PS = BOOT_MOUNT / 'motor_ps.py'
BLACKBOX = BOOT_MOUNT / 'motor_blackbox.py'
WAVE_DRIVER = BOOT_MOUNT / 'motor_wave_dma.ko'
WAVE_STATS = BOOT_MOUNT / 'motor_wave_stats.py'
WAVE_LIBRARY = BOOT_MOUNT / 'lib_motor_wave_stats.so'
WAVE_SERVICE = Path('/data/can_comm_candidate_20261018/board_wave_service_can.py')
WAVE_ENVELOPE_LIBRARY = ROOT / 'lib_board_wave_envelope.so'
HASHES = {
    AI: 'e259daab54c951f526749d0f1d6e4bcbc368b2f9fc60cbbf0c181e53db51dc26',
    MOTOR: '45496892e1b96c2a2354d1b9ecc6888cbfad82eb2c626c0b6d89916269fc8306',
    MOTOR10: 'affbb6e5de7ca3a69dd52a48e4ff73b6b4bcda15e94ea78604e07b73fe69532b',
    MOTOR_PS: '8285185d0964c7f8db8c911ff3f353e6c5b1047a071a1ffd722e21b2c0dbb220',
    BLACKBOX: '9755820e273b8b3e1c44a99e30506dd62f1632212f8e513ef842797cd3894759',
    WAVE_DRIVER: 'f33fda4876f44583c252b5f21dbf6711e2673a4001b6b5c52ecd9a14feecdae9',
    WAVE_STATS: '6eb9fd050b8712b57ddd502e407fb3324bc9f5a9ac69b02f55df4c8cb8c318e6',
    WAVE_LIBRARY: 'f14f01954b46bcb380ac041b5945eab83c9db1e2e2e5b199b5e3705d922c7a37',
    WAVE_SERVICE: '71660791daa9205b44ebddca0daa90710a7c5d80378f8650fae53277ba8a51eb',
    WAVE_ENVELOPE_LIBRARY: '67f124f188ef502914467d312fdff3ede406c2b7c359e830c4de45e3bf89d8f6',
}
FAULT_WORDS = ('FAIL:', 'CMA retained', 'AXI/FIFO fault', 'intr timeout',
               'EnqueueWorkload failed', 'STOP readback failed', 'WAVE_SERVICE_FAIL:')
HARDWARE_FAULT_WORDS = ('CMA retained', 'AXI/FIFO fault', 'intr timeout',
                        'EnqueueWorkload failed')


def mounted(target):
    """The Path.is_mount helper exists only from Python 3.7; the board runs
    3.6, so the mount table is read directly."""
    wanted = str(target)
    try:
        with open('/proc/mounts', 'r') as table:
            for line in table:
                fields = line.split()
                if len(fields) >= 2 and fields[1] == wanted:
                    return True
    except OSError:
        return False
    return False


def verified(path):
    if path.parent == BOOT_MOUNT and not mounted(BOOT_MOUNT):
        raise RuntimeError('SD BOOT partition is not mounted at /mnt/sdboot; '
                           'run: mkdir -p /mnt/sdboot && mount -o ro -t vfat '
                           '/dev/mmcblk0p1 /mnt/sdboot')
    with path.open('rb') as source:
        sha = hashlib.sha256()
        for block in iter(lambda: source.read(1024 * 1024), b''):
            sha.update(block)
        digest = sha.hexdigest()
    if digest != HASHES[path]:
        raise RuntimeError('approved file missing or hash mismatch: ' + str(path))


def tail(path, limit=1600):
    if not path:
        return ''
    try:
        with open(path, 'rb') as source:
            source.seek(0, os.SEEK_END)
            source.seek(max(0, source.tell() - limit))
            return source.read().decode('utf-8', 'replace')[-limit:]
    except FileNotFoundError:
        return ''


def birth(pid):
    try:
        record = Path('/proc/{}/stat'.format(pid)).read_text()
        remaining = record[record.rfind(')') + 2:].split()
        return None if remaining[0] == 'Z' else remaining[19]
    except (FileNotFoundError, IndexError, PermissionError):
        return None


def active(entry):
    return bool(entry and birth(entry.get('pid', -1)) == entry.get('birth'))


def before_capture_abort(output):
    """Only the approved shell launcher can emit this before execing the AI app."""
    return ('BOARD_AI_PRE_CAPTURE_ABORT exit=' in output and
            'BOARD_AI waiting' not in output and
            'BOARD_AI client connected' not in output and
            not any(word in output for word in HARDWARE_FAULT_WORDS))


def stopped_without_capture(output):
    return (before_capture_abort(output) or
            ('BOARD_AI waiting' in output and
             'BOARD_AI client connected' not in output and
             not any(word in output for word in HARDWARE_FAULT_WORDS)))


def cleanly_stopped(output):
    """A run that reached its own end prints the guarding PASS line; a run
    stopped by SIGTERM prints only the STOP line because the script exits
    straight after its finally block. Both count as a confirmed stop as long as
    no fault word is present, so the operator can start again immediately."""
    return ('STOP verified' in output and
            not any(word in output for word in FAULT_WORDS))


def read_pl():
    fd = os.open('/dev/mem', os.O_RDONLY | os.O_SYNC)
    try:
        with mmap.mmap(fd, 4096, offset=0x80000000, access=mmap.ACCESS_READ) as page:
            read = lambda offset: struct.unpack_from('<I', page, offset)[0]
            return dict(pl_id=read(0), features=read(0x54), motor_status=read(0x48),
                        motor_fault=read(0x50), guard_state=read(0x120),
                        guard_fault=read(0x124), applied_duty=read(0x168),
                        open_loop_abi=read(0x164),
                        duty_min=read(0x16c), duty_max=read(0x170),
                        camera_status=read(0xc14))
    finally:
        os.close(fd)


def neutral(pl):
    return (pl['pl_id'] == 0x4d535431 and pl['features'] == 0x4143 and
            pl['motor_fault'] == 0 and pl['guard_fault'] == 0 and
            not (pl['guard_state'] & 3) and pl['applied_duty'] == 0 and
            not (pl['motor_status'] & 0x1d0))


def motor_script(pl):
    """Select only a matching, separately hashed PL/PS duty profile."""
    duty_min = pl.get('duty_min', 15)
    abi = pl.get('open_loop_abi', 0x00010000)
    if duty_min == 15 and abi == 0x00010000:
        raise RuntimeError('vibration-latch candidate requires the verified 10% PL profile')
    if duty_min == 10 and abi == 0x00010001:
        return MOTOR10
    raise RuntimeError('unapproved PL motor duty metadata; no motor action')


def save(state):
    temp = ROOT / ('state-{}.tmp'.format(secrets.token_hex(8)))
    fd = os.open(str(temp), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, 'w') as output:
            json.dump(state, output)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temp, STATE)
    finally:
        if temp.exists():
            temp.unlink()


def launch(name, argv):
    log = ROOT / ('{}-{}-{}.log'.format(name, int(time.time()), secrets.token_hex(4)))
    fd = os.open(str(log), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, 'wb', buffering=0) as output:
            process = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=output,
                                       stderr=subprocess.STDOUT, start_new_session=True,
                                       close_fds=True)
        token = birth(process.pid)
        if token is None:
            raise RuntimeError('{} exited before start confirmation'.format(name))
        return dict(pid=process.pid, birth=token, log=str(log))
    except BaseException:
        raise


def status(state):
    pl = read_pl()
    trip_config = ({'current_delta_abs_ma': 800, 'vibration_raw_any_axis_ge': 7000}
                   if pl.get('duty_min') == 10 and
                   pl.get('open_loop_abi') == 0x00010001 else None)
    data = {'pl': pl, 'fault_latched': state.get('fault_latched', False),
            'motor_target_duty': state.get('motor_duty', 0),
            'combined_enabled': True, 'motor_trip_config': trip_config}
    for name in ('ai', 'motor', 'blackbox', 'wave'):
        entry = state.get(name)
        data[name + '_running'] = active(entry)
        data[name + '_tail'] = tail(entry.get('log') if entry else None)
    if state.get('motor') and not data['motor_running']:
        previous = data['motor_tail']
        if not cleanly_stopped(previous):
            state['fault_latched'] = True
            data['fault_latched'] = True
    ai_fault_text = '' if (not data['ai_running'] and
                           before_capture_abort(data['ai_tail'])) else data['ai_tail']
    if any(word in ai_fault_text + data['motor_tail'] + data['blackbox_tail']
           + data['wave_tail'] for word in FAULT_WORDS):
        state['fault_latched'] = True
        data['fault_latched'] = True
    # A PS vibration trip latches the PL operator STOP. Its direct test script
    # may not be the motor run tracked in state.json, so inspect PL readback.
    if pl['motor_fault'] or pl['guard_fault']:
        state['fault_latched'] = True
        data['fault_latched'] = True
    return data


def stop_motor(state):
    """Routine stop: SIGTERM the run so the board script neutralises the
    outputs through its own STOP path. That path does not latch the PL
    operator stop, so rotation can be started again immediately. The latching
    PL stop stays reserved for the red button, because it needs a PL reset."""
    entry = state.get('motor')
    if not active(entry):
        return {'message': 'motor is not running; nothing to stop'}
    # A routine stop must remain reachable even if SD/metadata verification
    # fails after a run starts. The running, already-verified script handles
    # SIGTERM and neutralises the bridge in its finally block.
    os.kill(entry['pid'], signal.SIGTERM)
    deadline = time.monotonic() + 6.0
    while active(entry) and time.monotonic() < deadline:
        time.sleep(0.05)
    output = tail(entry['log'], 4000)
    if not active(entry) and 'STOP verified' in output:
        return {'message': 'motor stopped; guard disabled, duty 0, ctrl FREE, '
                           'bridge inactive; no latch left behind'}
    return estop_motor(state, reason='graceful stop unconfirmed: ' + output[-400:])


def estop_motor(state, reason=None):
    """Latch the PL operator stop. Rotation is refused until it is acknowledged
    with motor_clear, which the guard only accepts while disarmed and neutral."""
    script = motor_script(read_pl())
    verified(MOTOR_PS)
    verified(script)
    result = subprocess.run([sys.executable, '-B', str(script), '--stop'],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            stdin=subprocess.DEVNULL, timeout=6, check=False)
    output = result.stdout.decode('utf-8', 'replace')
    if result.returncode or 'operator stop latched' not in output:
        state['fault_latched'] = True
        raise RuntimeError('STOP not confirmed; physically cut motor supply: ' + output[-700:])
    state['fault_latched'] = True
    state['stop_latched'] = True
    message = output.strip()
    if reason:
        message = '{} ({})'.format(message, reason)
    return {'message': message}


def clear_motor(state):
    """Acknowledge a latched stop/fault. motor_ps.py refuses while the core is
    active or faulted, so this cannot re-arm a spinning motor. The acknowledged
    run entry is dropped as well: status() re-latches whenever the last motor
    log lacks its normal end lines, which would otherwise undo this clear."""
    verified(MOTOR_PS)
    result = subprocess.run([sys.executable, '-B', str(MOTOR_PS), 'clear-fault'],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            stdin=subprocess.DEVNULL, timeout=8, check=False)
    output = result.stdout.decode('utf-8', 'replace')
    if result.returncode or 'fault cleared' not in output:
        raise RuntimeError('latch not cleared: ' + output[-700:])
    state['fault_latched'] = False
    state.pop('stop_latched', None)
    state.pop('can_stop_hold', None)
    entry = state.get('motor')
    if entry and not active(entry):
        state['motor'] = None
    return {'message': output.strip() + '; acknowledged run record cleared'}


def wait_motor_active(state, timeout=8.0):
    """Wait until the launched process has actually armed the PL outputs."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        entry = state.get('motor')
        if not active(entry):
            output = tail(entry.get('log') if entry else None, 1200)
            state['fault_latched'] = True
            raise RuntimeError('motor exited before activation: ' + output[-700:])
        pl = read_pl()
        if pl.get('motor_fault') or pl.get('guard_fault'):
            state['fault_latched'] = True
            raise RuntimeError(
                'motor failed during activation: guard=0x{:02X} core=0x{:02X}'
                .format(pl.get('guard_fault', 0), pl.get('motor_fault', 0)))
        if (int(pl.get('motor_status', 0)) & 0x1C0 and
                int(pl.get('applied_duty', 0)) > 0):
            return pl
        time.sleep(.025)
    state['fault_latched'] = True
    raise RuntimeError('motor activation timed out before PWM readback')


def ensure_wave_driver():
    device = Path('/dev/motor_wave_dma')
    if device.exists():
        return
    verified(WAVE_DRIVER)
    info = subprocess.run(['modinfo', '-F', 'vermagic', str(WAVE_DRIVER)],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=4, check=False)
    version = info.stdout.decode('ascii', 'replace').split()
    if info.returncode or not version or version[0] != os.uname().release:
        raise RuntimeError('waveform driver kernel version mismatch')
    result = subprocess.run(['insmod', str(WAVE_DRIVER)], stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=5, check=False)
    if result.returncode or not device.exists():
        raise RuntimeError('waveform DMA driver load failed: ' +
                           result.stdout.decode('utf-8', 'replace')[-400:])


def dma_device_open():
    """Read-only confirmation that no process still owns the exclusive DMA FD."""
    for pid in os.listdir('/proc'):
        if not pid.isdigit():
            continue
        directory = '/proc/{}/fd'.format(pid)
        try:
            descriptors = os.listdir(directory)
        except OSError:
            continue
        for descriptor in descriptors:
            try:
                if os.readlink(directory + '/' + descriptor) == '/dev/motor_wave_dma':
                    return True
            except OSError:
                pass
    return False


def action(op, state, confirmed, duty_percent=None):
    if op == 'status':
        return status(state)
    if op == 'motor_set_duty':
        if not confirmed:
            raise RuntimeError('operator confirmation required for live duty change')
        if (not isinstance(duty_percent, int) or isinstance(duty_percent, bool) or
                not 10 <= duty_percent <= 60):
            raise RuntimeError('duty must be an integer from 10 to 60 percent')
        entry = state.get('motor')
        if not active(entry):
            raise RuntimeError('motor is not running; live duty change rejected')
        control = state.get('motor_control') or {}
        if not control.get('token') or type(control.get('seq')) is not int:
            raise RuntimeError('active motor run has no live duty control channel')
        pl = read_pl()
        if (state.get('fault_latched') or not (pl['guard_state'] & 1) or
                pl['guard_fault'] or pl['motor_fault']):
            raise RuntimeError('PL guard/fault state rejects live duty change')
        if not pl['duty_min'] <= duty_percent <= min(60, pl['duty_max']):
            raise RuntimeError('duty must be within current PL range {}..{} percent'.format(
                pl['duty_min'], min(60, pl['duty_max'])))
        control['seq'] += 1
        control['duty'] = duty_percent
        state['motor_control'] = control
        state['motor_duty'] = duty_percent
        return {'message': 'live target accepted; PL ramps toward {}%'.format(duty_percent),
                'motor_target_duty': duty_percent, 'duty_seq': control['seq'],
                'applied_duty': pl['applied_duty']}
    if op == 'motor_stop':
        return stop_motor(state)
    if op == 'motor_estop':
        if not confirmed:
            raise RuntimeError('operator confirmation required for latched motor stop')
        return estop_motor(state)
    if op == 'motor_clear':
        if not confirmed:
            raise RuntimeError('operator confirmation required to clear motor fault')
        wave_result = None
        try:
            wave_result = action('wave_ack', state, True)
        except RuntimeError as error:
            if str(error) != 'no stopped waveform fault to acknowledge':
                raise
        motor_result = clear_motor(state)
        messages = []
        if wave_result:
            messages.append(wave_result.get('message', 'waveform fault acknowledged'))
        messages.append(motor_result.get('message', 'motor fault cleared'))
        return {'message': '; '.join(messages)}
    if op == 'wave_ack':
        if not confirmed:
            raise RuntimeError('explicit inspection confirmation required')
        entry = state.get('wave')
        output = tail(entry.get('log') if entry else None)
        if not entry or active(entry) or 'WAVE_SERVICE_FAIL:' not in output:
            raise RuntimeError('no stopped waveform fault to acknowledge')
        if dma_device_open() or Path('/data/ethernet_control_20261014/wave-service.sock').exists():
            raise RuntimeError('DMA release not confirmed; do not acknowledge')
        pl = read_pl()
        if not neutral(pl):
            raise RuntimeError('PL not neutral; do not acknowledge')
        for name in ('ai', 'motor', 'blackbox'):
            previous = state.get(name)
            if previous and any(word in tail(previous.get('log')) for word in FAULT_WORDS):
                raise RuntimeError('another subsystem fault remains latched')
        state['wave'] = None
        state['fault_latched'] = False
        return {'message': 'inspected waveform fault acknowledged; DMA remains stopped'}
    if op == 'wave_stop':
        entry = state.get('wave')
        if not active(entry):
            return {'message': 'wave service is not running'}
        os.kill(entry['pid'], signal.SIGTERM)
        deadline = time.monotonic() + 10
        while active(entry) and time.monotonic() < deadline:
            time.sleep(.05)
        output = tail(entry['log'], 2000)
        if active(entry) or 'WAVE_SERVICE_STOPPED' not in output:
            state['fault_latched'] = True
            raise RuntimeError('wave storage/cleanup unconfirmed: ' + output[-700:])
        return {'message': 'wave monitoring stopped; DMA released and events flushed'}
    if op == 'ai_stop':
        entry = state.get('ai')
        if not entry:
            return {'message': 'AI not started from this control interface'}
        if active(entry):
            os.kill(entry['pid'], signal.SIGTERM)
            deadline = time.monotonic() + 5
            while active(entry) and time.monotonic() < deadline:
                time.sleep(0.1)
        output = tail(entry['log'])
        released = 'BOARD_AI_STOPPED' in output and 'CMA released' in output
        never_captured = stopped_without_capture(output)
        if active(entry) or not (released or never_captured):
            state['fault_latched'] = True
            raise RuntimeError('AI cleanup unconfirmed; do not retry: ' + output[-500:])
        return {'message': ('AI stopped; CMA released' if released else
                            'AI stopped before camera/CMA startup')}
    # Keep waveform monitoring available after a motor fault.  Restarting the
    # recorder cannot energize the motor and helps preserve later evidence.
    # A waveform-service failure still requires the explicit wave_ack path.
    if state.get('fault_latched') and op == 'wave_start':
        prior_wave = state.get('wave')
        if prior_wave and 'WAVE_SERVICE_FAIL:' in tail(prior_wave.get('log')):
            raise RuntimeError('waveform fault requires inspection and wave_ack')
    elif state.get('fault_latched'):
        raise RuntimeError('fault latched; inspect board before further action')
    if op == 'ai_start':
        prior = state.get('ai')
        if active(prior):
            raise RuntimeError('AI already running')
        if prior and ('BOARD_AI_STOPPED' not in tail(prior['log']) and
                      not stopped_without_capture(tail(prior['log']))):
            raise RuntimeError('previous AI shutdown not verified')
        verified(AI)
        state['ai'] = launch('ai', ['bash', str(AI)])
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            output = tail(state['ai']['log'])
            if 'BOARD_AI waiting at ' in output and active(state['ai']):
                return {'message': 'board AI ready; connect video port 5000'}
            if not active(state['ai']):
                if before_capture_abort(output):
                    state['ai'] = None
                    raise RuntimeError('AI preflight failed before camera startup: ' +
                                       output[-500:])
                state['fault_latched'] = True
                raise RuntimeError('AI exited before video ready; inspect board: ' +
                                   output[-500:])
            time.sleep(0.1)
        return {'message': 'board AI still starting; connect video port 5000'}
    if op == 'wave_start':
        if active(state.get('wave')):
            return {'message': 'wave service already running'}
        if active(state.get('blackbox')):
            raise RuntimeError('8-second black-box owns the DMA device')
        ensure_wave_driver()
        verified(BLACKBOX)
        verified(WAVE_STATS)
        verified(WAVE_LIBRARY)
        verified(WAVE_SERVICE)
        verified(WAVE_ENVELOPE_LIBRARY)
        directory = ROOT / ('wave-events-{}-{}'.format(int(time.time()), secrets.token_hex(4)))
        directory.mkdir(mode=0o700)
        state['wave'] = launch('wave', [sys.executable, '-u', '-B', str(WAVE_SERVICE),
                                        '--output-dir', str(directory)])
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            output = tail(state['wave']['log'])
            if 'WAVE_SERVICE_READY' in output and active(state['wave']):
                return {'message': '50 kHz ADC wave + fault black-box monitoring',
                        'output_dir': str(directory)}
            if not active(state['wave']):
                state['fault_latched'] = True
                raise RuntimeError('wave service exited before ready: ' + output[-700:])
            time.sleep(.05)
        state['fault_latched'] = True
        raise RuntimeError('wave service startup unconfirmed')
    if op == 'motor_preflight':
        if active(state.get('motor')):
            raise RuntimeError('motor action already running')
        script = motor_script(read_pl())
        verified(MOTOR_PS)
        verified(script)
        result = subprocess.run([sys.executable, '-B', str(script)],
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                stdin=subprocess.DEVNULL, timeout=8, check=False)
        output = result.stdout.decode('utf-8', 'replace')
        if result.returncode or 'motor NOT armed' not in output:
            raise RuntimeError('motor preflight failed: ' + output[-700:])
        return {'message': output.strip()}
    if op == 'motor_start':
        if not confirmed:
            raise RuntimeError('per-run physical confirmation required')
        if duty_percent is None:
            duty_percent = 15
        if (not isinstance(duty_percent, int) or isinstance(duty_percent, bool) or
                not 10 <= duty_percent <= 60):
            raise RuntimeError('duty must be an integer from 10 to 60 percent')
        pl = read_pl()
        script = motor_script(pl)
        if duty_percent < pl.get('duty_min', 15):
            raise RuntimeError('duty must be an integer from {} to 60 percent'.format(
                pl.get('duty_min', 15)))
        prior = state.get('motor')
        if active(prior):
            raise RuntimeError('motor action already running')
        if prior and not cleanly_stopped(tail(prior['log'])):
            state['fault_latched'] = True
            raise RuntimeError('previous motor stop unconfirmed')
        if active(state.get('blackbox')):
            raise RuntimeError('motor and standalone 8-second black-box cannot share DMA')
        if active(state.get('wave')) and not (ROOT / 'wave_motor_concurrency_approved').exists():
            raise RuntimeError('powered motor + persistent DMA black-box has not passed board acceptance')
        if not neutral(pl):
            raise RuntimeError('PL not neutral or approved 0x4143 image absent')
        verified(script)
        state.pop('can_stop_hold', None)
        control = {'token': secrets.token_hex(16), 'seq': 0, 'duty': duty_percent}
        state['motor'] = launch('motor', [sys.executable, '-B', str(script),
            '--arm', '--seconds', '3600', '--duty-percent', str(duty_percent), '--motor-vm', '12',
            '--sensor-in-motor-lead', '--pl-current-limit-ma', '800',
            '--vibration-trip-raw-code', '7000',
            '--duty-control-state', str(STATE),
            '--duty-control-token', control['token']])
        state['motor_control'] = control
        state['motor_duty'] = duty_percent
        wait_motor_active(state)
        return {'message': 'forward run started at {}% ; current delta 800 mA or any '
                           'vibration raw code >=7000 latches STOP; the PL guard caps '
                           'one arm at 3600 s, the desktop controller re-arms while it stays on'
                           .format(duty_percent)}
    if op == 'blackbox_start':
        if active(state.get('wave')):
            os.kill(state['wave']['pid'], signal.SIGUSR1)
            return {'message': 'manual event marked in persistent waveform recorder'}
        if active(state.get('motor')) or active(state.get('blackbox')):
            raise RuntimeError('motor or blackbox already running')
        ensure_wave_driver()
        verified(BLACKBOX)
        directory = ROOT / ('blackbox-{}-{}'.format(int(time.time()), secrets.token_hex(4)))
        directory.mkdir(mode=0o700)
        state['blackbox'] = launch('blackbox', [sys.executable, '-B', str(BLACKBOX),
            '--output-dir', str(directory), '--parser', 'native', '--seconds', '8'])
        return {'message': '8-second waveform capture started', 'output_dir': str(directory)}
    raise RuntimeError('unsupported action')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('status', 'ai_start', 'ai_stop',
                        'motor_preflight', 'motor_start', 'motor_stop', 'motor_set_duty',
                        'motor_estop', 'motor_clear', 'blackbox_start',
                        'wave_start', 'wave_stop', 'wave_ack'))
    parser.add_argument('--confirm', action='store_true')
    parser.add_argument('--duty-percent', type=int)
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise RuntimeError('root required')
    ROOT.mkdir(mode=0o700, exist_ok=True)
    with LOCK.open('a+b') as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        state = json.loads(STATE.read_text()) if STATE.exists() else {}
        try:
            data = action(args.operation, state, args.confirm, args.duty_percent)
            reply = {'ok': True, 'data': data}
        except Exception as error:
            reply = {'ok': False, 'error': str(error)}
        save(state)
    print(json.dumps(reply, ensure_ascii=False))
    return 0 if reply['ok'] else 1


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except Exception as error:
        print(json.dumps({'ok': False, 'error': str(error)}, ensure_ascii=False))
        raise SystemExit(1)

