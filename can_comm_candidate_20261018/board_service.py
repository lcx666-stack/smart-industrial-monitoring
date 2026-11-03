#!/usr/bin/env python3
"""Board-side CAN alarm publisher for an STM32 buzzer node.

The CAN controller must first be routed to J11 in the candidate PL image.
CAN carries fault notifications and their application acknowledgements only;
control commands stay on the authenticated Ethernet/SSH path.
"""

import argparse
import calendar
import datetime
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import threading
import time
import socket

import protocol as p
from transport import SocketCan

ROOT = Path('/data/ethernet_control_20261014')
ACTIVE_HELPER = ROOT / 'board_control_duty.py'
HELPER = ACTIVE_HELPER
EVENT_SOCKET = ROOT / 'can-events.sock'
EVENT_ROOT = ROOT


def fault_code(reason):
    text = str(reason or '').lower()
    for marker, name in (
            ('vibration threshold', 'VIBRATION_LIMIT'),
            ('current threshold', 'CURRENT_LIMIT'),
            ('pl motor fault', 'PL_MOTOR_FAULT'),
            ('adc error', 'ADC_ERROR'),
            ('pl dma frame loss', 'DMA_DROP'),
            ('dma dropped', 'DMA_DROP'),
            ('timestamp mismatch', 'TIMESTAMP_MISMATCH'),
            ('sequence gap', 'SEQ_GAP'),
            ('manual', 'MANUAL')):
        if marker in text:
            return p.FAULT_CODES[name]
    return p.FAULT_CODES['OTHER_EVENT']


def utc_parts(iso_text):
    try:
        stamp = str(iso_text).replace('Z', '+00:00')
        if not stamp.endswith('+00:00'):
            raise ValueError('not UTC')
        part = stamp[:-6]
        parsed = datetime.datetime.strptime(part, '%Y-%m-%dT%H:%M:%S.%f') if '.' in part \
            else datetime.datetime.strptime(part, '%Y-%m-%dT%H:%M:%S')
        if parsed.year < 2025:
            raise ValueError('RTC time invalid')
        return calendar.timegm(parsed.timetuple()), parsed.microsecond // 1000, 4
    except (TypeError, ValueError):
        return 0, 0xffff, 0


def trigger_key(folder, sequence):
    if sequence is None:
        return None
    return str(Path(folder).name) + ':' + str(sequence)


class QueueFullError(RuntimeError):
    pass


class Journal:
    """Durable event/command deduplication; accessed under one Python lock."""

    MAX_EVENTS = 10000

    def __init__(self, path, event_root=EVENT_ROOT):
        self.lock = threading.RLock()
        self.event_root = Path(event_root)
        self.db = sqlite3.connect(str(path), check_same_thread=False)
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.execute('PRAGMA synchronous=FULL')
        self.db.execute('''CREATE TABLE IF NOT EXISTS events (
            seq INTEGER PRIMARY KEY AUTOINCREMENT, event_id TEXT UNIQUE,
            trigger_key TEXT UNIQUE, fault INTEGER NOT NULL,
            utc INTEGER NOT NULL, ms INTEGER NOT NULL, flags INTEGER NOT NULL,
            result INTEGER NOT NULL, size_kib INTEGER NOT NULL,
            ack_mask INTEGER NOT NULL DEFAULT 0, last_sent REAL NOT NULL DEFAULT 0,
            first_seen REAL NOT NULL)''')
        self.db.execute('''CREATE TABLE IF NOT EXISTS counters (
            name TEXT PRIMARY KEY, value INTEGER NOT NULL)''')
        self.db.execute("INSERT OR IGNORE INTO counters VALUES ('overflow_attempts',0)")
        self.db.commit()

    def _reserve_event_slot(self):
        count = self.db.execute('SELECT COUNT(*) FROM events').fetchone()[0]
        if count < self.MAX_EVENTS:
            return
        # Keep a durable sidecar before dropping an alarm acknowledged by STM32.
        rows = self.db.execute('''SELECT seq,event_id FROM events WHERE result!=0
            AND (ack_mask & ?) = ?
            ORDER BY seq LIMIT 128''',
            (p.ACK_ALARM, p.ACK_ALARM)).fetchall()
        for seq, event_id in rows:
            if event_id:
                parts = event_id.split('/')
                if len(parts) != 2 or any(not part or part in ('.', '..') for part in parts):
                    continue
                directory = self.event_root / parts[0]
                if (directory / (parts[1] + '.json')).exists():
                    marker = directory / (parts[1] + '.stm32-acked')
                    try:
                        with marker.open('x', encoding='ascii') as output:
                            output.write(str(seq) + '\n')
                            output.flush()
                            os.fsync(output.fileno())
                    except FileExistsError:
                        pass
                    except OSError:
                        continue
            self.db.execute('DELETE FROM events WHERE seq=?', (seq,))
        count = self.db.execute('SELECT COUNT(*) FROM events').fetchone()[0]
        if count >= self.MAX_EVENTS:
            self.db.execute('''UPDATE counters SET value=value+1
                WHERE name='overflow_attempts' ''')
            self.db.commit()
            raise QueueFullError('CAN event journal full; original event files retained')

    def overflow_attempts(self):
        with self.lock:
            return self.db.execute("SELECT value FROM counters WHERE name='overflow_attempts'").fetchone()[0]

    def add_trigger(self, message):
        key = trigger_key(message.get('output_dir'), message.get('trigger_seq'))
        if not key:
            raise ValueError('trigger lacks output directory or sequence')
        utc, ms, valid = utc_parts(message.get('created_utc'))
        with self.lock:
            existing = self.db.execute('SELECT seq FROM events WHERE trigger_key=?',
                                       (key,)).fetchone()
            if existing:
                return existing[0]
            self._reserve_event_slot()
            self.db.execute('''INSERT OR IGNORE INTO events
                (trigger_key,fault,utc,ms,flags,result,size_kib,first_seen)
                VALUES (?,?,?,?,?,?,?,?)''',
                (key, fault_code(message.get('reason')), utc, ms, valid,
                 p.SAVE_PENDING, 0, time.time()))
            self.db.commit()
            return self.db.execute('SELECT seq FROM events WHERE trigger_key=?',
                                   (key,)).fetchone()[0]

    def add_saved(self, event_id, metadata):
        key = trigger_key(event_id.split('/')[0], metadata.get('trigger_seq'))
        utc, ms, valid = utc_parts(metadata.get('created_utc'))
        count = metadata.get('binary_bytes', 0)
        if type(count) is not int or count < 0:
            raise ValueError('invalid event binary length')
        size = min(65535, (count + 1023) // 1024)
        flags = valid | (0x80 if size == 65535 and count > 65535 * 1024 else 0)
        result = p.SAVE_PARTIAL if metadata.get('incomplete') else p.SAVE_COMPLETE
        with self.lock:
            existing = self.db.execute('SELECT seq,event_id FROM events WHERE trigger_key=?',
                                       (key,)).fetchone() if key else None
            if existing:
                seq, prior = existing
                if prior and prior != event_id:
                    raise ValueError('trigger key collision')
                if prior == event_id:
                    return seq
                self.db.execute('''UPDATE events SET event_id=?,fault=?,utc=?,ms=?,
                    flags=?,result=?,size_kib=?,ack_mask=ack_mask&3,last_sent=0
                    WHERE seq=?''',
                    (event_id, fault_code(metadata.get('reason')), utc, ms,
                     flags, result, size, seq))
            else:
                duplicate = self.db.execute('SELECT seq FROM events WHERE event_id=?',
                                            (event_id,)).fetchone()
                if duplicate:
                    return duplicate[0]
                self._reserve_event_slot()
                self.db.execute('''INSERT OR IGNORE INTO events
                    (event_id,trigger_key,fault,utc,ms,flags,result,size_kib,first_seen)
                    VALUES (?,?,?,?,?,?,?,?,?)''',
                    (event_id, key, fault_code(metadata.get('reason')), utc, ms,
                     flags, result, size, time.time()))
                row = self.db.execute('SELECT seq FROM events WHERE event_id=?',
                                      (event_id,)).fetchone()
                seq = row[0]
            self.db.commit()
            return seq

    def fail_pending(self):
        with self.lock:
            self.db.execute('''UPDATE events SET result=?, last_sent=0
                WHERE result=? AND event_id IS NULL''',
                (p.SAVE_FAILED, p.SAVE_PENDING))
            self.db.commit()

    def fail_saved(self, event_id, metadata):
        key = trigger_key(event_id.split('/')[0], metadata.get('trigger_seq'))
        if key:
            self.add_trigger({'output_dir': event_id.split('/')[0],
                              'trigger_seq': metadata.get('trigger_seq'),
                              'created_utc': metadata.get('created_utc'),
                              'reason': metadata.get('reason')})
        with self.lock:
            self.db.execute('''UPDATE events SET event_id=?,result=?,last_sent=0
                WHERE trigger_key=? AND event_id IS NULL''',
                (event_id, p.SAVE_FAILED, key))
            if not key:
                duplicate = self.db.execute('SELECT seq FROM events WHERE event_id=?',
                                            (event_id,)).fetchone()
                if duplicate:
                    self.db.commit()
                    return
                self._reserve_event_slot()
                utc, ms, valid = utc_parts(metadata.get('created_utc'))
                self.db.execute('''INSERT OR IGNORE INTO events
                    (event_id,fault,utc,ms,flags,result,size_kib,first_seen)
                    VALUES (?,?,?,?,?,?,?,?)''',
                    (event_id, fault_code(metadata.get('reason')), utc, ms,
                     valid, p.SAVE_FAILED, 0, time.time()))
            self.db.commit()

    def has_event(self, event_id):
        with self.lock:
            return self.db.execute('SELECT 1 FROM events WHERE event_id=?',
                                   (event_id,)).fetchone() is not None

    def ack(self, seq, mask):
        with self.lock:
            self.db.execute('UPDATE events SET ack_mask=ack_mask|? WHERE seq=?',
                            (mask, seq))
            self.db.commit()

    def pending(self, now):
        with self.lock:
            rows = self.db.execute('''SELECT seq,event_id,fault,utc,ms,flags,
                result,size_kib,ack_mask FROM events WHERE last_sent<=?
                AND (ack_mask & ?) != ?
                ORDER BY last_sent, seq LIMIT 16''',
                (now - 2.0, p.ACK_ALARM, p.ACK_ALARM)).fetchall()
            return rows

    def sent(self, seq, now):
        with self.lock:
            self.db.execute('UPDATE events SET last_sent=? WHERE seq=?', (now, seq))
            self.db.commit()

    def close(self):
        with self.lock:
            self.db.close()


class Controller:
    def __init__(self, helper=HELPER):
        self.helper = Path(helper)

    def action(self, operation, duty=None):
        if operation != 'status':
            return False, {'error': 'this CAN alarm service only reads board status'}, p.BOARD_REJECTED
        args = [sys.executable, '-B', str(self.helper), operation]
        try:
            result = subprocess.run(args, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, stdin=subprocess.DEVNULL,
                                    timeout=20, check=False)
            response = json.loads(result.stdout.decode('utf-8', 'replace').strip().splitlines()[-1])
            if result.returncode or not response.get('ok'):
                return False, response, p.BOARD_REJECTED
            return True, response.get('data', {}), 0
        except (OSError, ValueError, IndexError, subprocess.TimeoutExpired):
            return False, {}, p.BOARD_ERROR

def read_saved_events(root):
    """Yield published event JSON candidates; never opens the DMA device."""
    for folder in list(root.glob('wave-events-*')) + list(root.glob('blackbox-*')):
        if not folder.is_dir() or folder.is_symlink():
            continue
        for path in folder.glob('event-*.json'):
            if path.is_symlink():
                continue
            if any((folder / (path.stem + suffix)).exists()
                   for suffix in ('.can-acked', '.stm32-acked')):
                continue
            try:
                metadata = json.loads(path.read_text(encoding='utf-8'))
                if metadata.get('format') != 'FRM1':
                    continue
                yield folder.name + '/' + path.stem, metadata
            except (OSError, ValueError, TypeError):
                continue


class CanService:
    def __init__(self, bus, journal, controller, event_root=EVENT_ROOT):
        self.bus, self.journal, self.controller = bus, journal, controller
        self.event_root = Path(event_root)
        self.send_lock = threading.Lock()
        self.last_status = {}
        self.started = time.monotonic()
        self.retry_after = 0
        self.last_overflow_log = 0
        self.paired_nonce = None

    def report_overflow(self):
        now = time.monotonic()
        if now - self.last_overflow_log >= 60:
            print('CAN event journal full; overflow attempts={}; black-box files retained'.format(
                  self.journal.overflow_attempts()), file=sys.stderr, flush=True)
            self.last_overflow_log = now

    def send(self, frame):
        with self.send_lock:
            self.bus.send(*frame)

    def process_frame(self, can_id, payload):
        if can_id == p.PAIR_REQUEST_ID:
            try:
                nonce = p.parse_pair_request(can_id, payload)
                self.paired_nonce = nonce
                self.send(p.pair_confirm(nonce))
                print('STM32 paired: nonce={:04X}'.format(nonce),
                      flush=True)
            except (OSError, ValueError):
                pass
            return

        if can_id == p.ALARM_ACK_ID:
            try:
                seq, mask = p.parse_alarm_ack(payload)
                if mask & p.ACK_ALARM:
                    self.journal.ack(seq, p.ACK_ALARM)
            except ValueError:
                pass
            return  # Never accept motor/control commands from the CAN bus.

    def scan_events(self):
        for event_id, metadata in read_saved_events(self.event_root):
            if self.journal.has_event(event_id):
                continue
            folder, name = event_id.split('/')
            binary = self.event_root / folder / (name + '.bin')
            try:
                count = metadata['binary_bytes']
                expected = metadata['binary_sha256']
                if (type(count) is not int or count < 0 or count > 16 * 1024 * 1024 or
                        not isinstance(expected, str) or len(expected) != 64 or
                        metadata.get('binary_file') != binary.name or
                        binary.is_symlink() or binary.stat().st_size != count):
                    raise ValueError('invalid black-box pair')
                digest = hashlib.sha256()
                with binary.open('rb') as source:
                    for block in iter(lambda: source.read(65536), b''):
                        digest.update(block)
                if digest.hexdigest() != expected:
                    raise ValueError('black-box SHA-256 mismatch')
                self.journal.add_saved(event_id, metadata)
            except QueueFullError:
                self.report_overflow()
            except (OSError, ValueError, KeyError, TypeError):
                try:
                    self.journal.fail_saved(event_id, metadata)
                except QueueFullError:
                    self.report_overflow()

    def publish(self):
        if self.paired_nonce is None:
            return
        now = time.time()
        for seq, event_id, fault, utc, ms, flags, result, size, ack in \
                self.journal.pending(now):
            if not ack & p.ACK_ALARM:
                self.send(p.alarm(seq, fault, flags, ms))
            self.journal.sent(seq, now)

    def update_status(self):
        ok, data, _ = self.controller.action('status')
        if not ok:
            return
        self.last_status = data
        if 'WAVE_SERVICE_FAIL:' in data.get('wave_tail', ''):
            self.journal.fail_pending()

    def run(self, event_socket=EVENT_SOCKET):
        event_socket = Path(event_socket)
        if event_socket.exists():
            event_socket.unlink()
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        listener.bind(str(event_socket))
        os.chmod(str(event_socket), 0o600)
        listener.setblocking(False)
        last_scan = last_status = 0
        try:
            while True:
                now = time.monotonic()
                try:
                    message = listener.recv(2048)
                    notice = json.loads(message.decode('utf-8'))
                    if notice.get('kind') == 'trigger':
                        self.journal.add_trigger(notice)
                    elif notice.get('kind') == 'writer_failed':
                        self.journal.fail_pending()
                except BlockingIOError:
                    pass
                except QueueFullError:
                    self.report_overflow()
                except (ValueError, KeyError):
                    pass
                try:
                    frame = self.bus.recv(0.1)
                except OSError:
                    frame = None
                    time.sleep(.2)
                if frame:
                    self.process_frame(*frame)
                if now - last_scan >= 1:
                    self.scan_events()
                    last_scan = now
                if now - last_status >= 2:
                    self.update_status()
                    last_status = now
                if now >= self.retry_after:
                    try:
                        self.publish()
                    except OSError:
                        self.retry_after = time.monotonic() + 10
        finally:
            listener.close()
            event_socket.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--interface', default='can0')
    parser.add_argument('--helper', default=str(HELPER))
    parser.add_argument('--journal', default=str(ROOT / 'can-journal.sqlite3'))
    parser.add_argument('--check-only', action='store_true',
                        help='verify the Ethernet board helper without opening CAN')
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error('board service requires root for existing control helper')
    if not Path(args.helper).is_file():
        parser.error('active Ethernet helper is missing; required for board status reads')
    if args.check_only:
        return 0
    import fcntl
    ROOT.mkdir(mode=0o700, exist_ok=True)
    with (ROOT / 'can-service.lock').open('a+b') as lock:
        try:
            fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            parser.error('CAN service already running')
        bus = SocketCan(args.interface)
        journal = Journal(args.journal)
        try:
            CanService(bus, journal, Controller(args.helper)).run()
        finally:
            journal.close()
            bus.close()


if __name__ == '__main__':
    main()
