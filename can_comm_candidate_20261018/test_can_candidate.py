"""Offline protocol and control-safety checks; no CAN adapter or motor."""

import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import threading
import time
import types
import unittest
from unittest import mock

import board_service as board
import protocol as p


class FakeBus:
    def __init__(self):
        self.frames = []
        self.lock = threading.Lock()

    def send(self, can_id, payload):
        with self.lock:
            self.frames.append((can_id, payload))


class FakeController:
    def __init__(self):
        self.calls = []
        self.block_start = threading.Event()
        self.release_start = threading.Event()

    def action(self, operation, duty=None):
        self.calls.append((operation, duty))
        if operation == 'can_motor_start' and self.block_start.is_set():
            self.release_start.wait(2)
        if operation == 'status':
            return True, {'pl': {'applied_duty': 0, 'guard_fault': 0},
                          'fault_latched': False, 'motor_running': False}, 0
        return True, {}, 0

    def emergency_stop(self):
        self.calls.append(('emergency_stop', None))
        return True, {'pl': {'guard_fault': 128}}, 0


class ProtocolChecks(unittest.TestCase):
    def test_pairing_round_trip_and_alarm_gate(self):
        request = p.pair_request(0x4A21)
        self.assertEqual(p.parse_pair_request(*request), 0x4A21)
        confirm = p.pair_confirm(0x4A21)
        self.assertEqual(p.parse_pair_confirm(*confirm), 0x4A21)
        with self.assertRaises(ValueError):
            p.pair_request(0)
        with self.assertRaises(ValueError):
            p.parse_pair_confirm(p.PAIR_REQUEST_ID, confirm[1])

        with tempfile.TemporaryDirectory() as folder:
            bus = FakeBus()
            journal = board.Journal(Path(folder) / 'db')
            service = board.CanService(bus, journal, FakeController(), folder)
            notice = {'output_dir': 'wave-events-1-abcdef12',
                      'trigger_seq': 7,
                      'created_utc': '2026-10-18T03:22:40.000000+00:00',
                      'reason': 'vibration threshold'}
            journal.add_trigger(notice)
            service.publish()
            self.assertEqual(bus.frames, [])

            service.process_frame(*request)
            self.assertEqual(service.paired_nonce, 0x4A21)
            self.assertEqual(bus.frames[-1], confirm)
            service.publish()
            self.assertEqual(bus.frames[-1][0], p.ALARM_ID)
            journal.close()

    def test_can_stop_hold_blocks_ethernet_restart_and_survives_failed_start(self):
        helper = Path(__file__).with_name('board_control_can.py')
        spec = importlib.util.spec_from_file_location('can_control_test', str(helper))
        with mock.patch.dict(sys.modules, {'fcntl': types.ModuleType('fcntl')}):
            control = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(control)
        state = {}
        with mock.patch.object(control, 'stop_motor', return_value={'message': 'stopped'}):
            self.assertEqual(control.action('can_motor_stop', state, False),
                             {'message': 'stopped'})
        self.assertTrue(state['can_stop_hold'])
        with self.assertRaisesRegex(RuntimeError, 'CAN stop hold'):
            control.action('motor_start', state, True, 15)
        with self.assertRaisesRegex(RuntimeError, 'physical confirmation'):
            control.action('can_motor_start', state, False, 15)
        self.assertTrue(state['can_stop_hold'])

    def test_shared_helper_gate_rejects_old_ethernet_logic(self):
        with tempfile.TemporaryDirectory() as folder:
            candidate = Path(folder) / 'candidate.py'
            active = Path(folder) / 'active.py'
            candidate.write_bytes(b'CAN_SHARED_STOP_HOLD = 1\n')
            active.write_bytes(b'old Ethernet helper\n')
            self.assertFalse(board.shared_helper_ready(candidate, active))
            active.write_bytes(candidate.read_bytes())
            self.assertTrue(board.shared_helper_ready(candidate, active))
            active.write_bytes(candidate.read_bytes() + b'# changed\n')
            self.assertFalse(board.shared_helper_ready(candidate, active))

    def test_heartbeat_exposes_can_stop_hold(self):
        with tempfile.TemporaryDirectory() as folder:
            service = board.CanService(FakeBus(), board.Journal(Path(folder) / 'db'),
                                       FakeController(), folder)
            service.last_status = {'can_stop_hold': True, 'motor_running': False,
                                   'wave_running': True, 'fault_latched': False}
            self.assertEqual(service.state(), 12)
            service.journal.close()

    def test_event_queue_is_bounded_and_counts_overflow(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            event_dir = root / 'wave-events-1'
            event_dir.mkdir()
            (event_dir / 'event-1.json').write_text(
                json.dumps({'format': 'FRM1', 'trigger_seq': 1}), encoding='utf-8')
            journal = board.Journal(root / 'journal.sqlite3', event_root=root)
            journal.MAX_EVENTS = 2
            notice = {'output_dir': 'wave-events-1', 'trigger_seq': 1,
                      'created_utc': '2026-10-18T03:22:40.000000+00:00',
                      'reason': 'vibration threshold'}
            first = journal.add_trigger(notice)
            journal.add_saved('wave-events-1/event-1', dict(notice, binary_bytes=32))
            notice['trigger_seq'] = 2
            journal.add_trigger(notice)
            notice['trigger_seq'] = 3
            with self.assertRaises(board.QueueFullError):
                journal.add_trigger(notice)
            self.assertEqual(journal.overflow_attempts(), 1)
            journal.ack(first, 15)
            self.assertGreater(journal.add_trigger(notice), first)
            self.assertEqual(journal.db.execute('SELECT COUNT(*) FROM events').fetchone()[0], 2)
            self.assertTrue((event_dir / 'event-1.can-acked').exists())
            self.assertEqual(list(board.read_saved_events(root)), [])
            journal.close()

    def test_command_whitelist_and_wire_values(self):
        frame = p.command(0x12345678, p.MOTOR_START, 15)
        self.assertEqual(frame[0], p.COMMAND_ID)
        self.assertEqual(p.parse_command(*frame), (0x12345678, p.MOTOR_START, 15, 1))
        frame = p.command(1, p.MOTOR_SET_DUTY, 20)
        self.assertEqual(p.parse_command(*frame),
                         (1, p.MOTOR_SET_DUTY, 20, 1))
        with self.assertRaises(ValueError):
            p.command(1, p.MOTOR_SET_DUTY, 61)
        with self.assertRaises(ValueError):
            p.command(1, p.MOTOR_START, 9)
        with self.assertRaises(ValueError):
            p.parse_command(p.ESTOP_ID, frame[1])
        self.assertEqual(p.command(1, p.ESTOP)[0], p.ESTOP_ID)

    def test_journal_deduplicates_commands_and_preserves_event_sequence(self):
        with tempfile.TemporaryDirectory() as folder:
            journal = board.Journal(Path(folder) / 'journal.sqlite3')
            trigger = {'output_dir': 'wave-events-1-abcdef12', 'trigger_seq': 42,
                       'created_utc': '2026-10-18T03:22:40.033024+00:00',
                       'reason': 'vibration threshold'}
            seq = journal.add_trigger(trigger)
            self.assertEqual(seq, journal.add_trigger(trigger))
            self.assertEqual(journal.command(1, 100, p.MOTOR_START, 15), None)
            self.assertEqual(journal.command(1, 100, p.MOTOR_START, 15)[:2],
                             (p.MOTOR_START, 15))
            event_id = trigger['output_dir'] + '/event-a'
            meta = {'trigger_seq': 42, 'created_utc': trigger['created_utc'],
                    'reason': trigger['reason'], 'binary_bytes': 6400032,
                    'incomplete': False}
            self.assertEqual(journal.add_saved(event_id, meta), seq)
            journal.ack(seq, 15)
            self.assertEqual(journal.add_saved(event_id, meta), seq)
            self.assertEqual(journal.pending(time.time() + 3), [])
            second = board.Journal(Path(folder) / 'journal.sqlite3')
            self.assertEqual(second.add_saved(event_id, meta), seq)
            second.close()
            journal.close()

    def test_duplicate_start_is_not_executed_twice(self):
        with tempfile.TemporaryDirectory() as folder:
            controller, bus = FakeController(), FakeBus()
            service = board.CanService(bus, board.Journal(Path(folder) / 'db'),
                                       controller, folder)
            frame = p.command(5, p.MOTOR_START, 15)
            service.process_frame(*frame)
            deadline = time.time() + 2
            while ('can_motor_start', 15) not in controller.calls and time.time() < deadline:
                time.sleep(.01)
            service.process_frame(*frame)
            while time.time() < deadline:
                replies = [p.decode(*f) for f in bus.frames if f[0] == p.REPLY_ID]
                if any(r['outcome'] == p.DONE for r in replies):
                    break
                time.sleep(.01)
            self.assertEqual(controller.calls.count(('can_motor_start', 15)), 1)
            self.assertIn(p.DONE, [r['outcome'] for r in replies])
            service.journal.close()

    def test_estop_does_not_wait_for_start_worker(self):
        with tempfile.TemporaryDirectory() as folder:
            controller, bus = FakeController(), FakeBus()
            controller.block_start.set()
            service = board.CanService(bus, board.Journal(Path(folder) / 'db'),
                                       controller, folder)
            service.process_frame(*p.command(10, p.MOTOR_START, 15))
            deadline = time.time() + 2
            while ('can_motor_start', 15) not in controller.calls and time.time() < deadline:
                time.sleep(.01)
            service.process_frame(*p.command(11, p.ESTOP))
            deadline = time.time() + .5
            while ('emergency_stop', None) not in controller.calls and time.time() < deadline:
                time.sleep(.01)
            self.assertIn(('emergency_stop', None), controller.calls)
            controller.release_start.set()
            deadline = time.time() + 2
            while time.time() < deadline:
                replies = [p.decode(*f) for f in bus.frames if f[0] == p.REPLY_ID]
                if len([r for r in replies if r['outcome'] != p.ACCEPTED]) >= 2:
                    break
                time.sleep(.01)
            service.journal.close()

    def test_save_report_requires_matching_binary_hash(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            events = root / 'wave-events-1-abcdef12'
            events.mkdir()
            service = board.CanService(FakeBus(), board.Journal(root / 'db'),
                                       FakeController(), root)
            for name, wrong_hash in (('event-good', False), ('event-bad', True)):
                binary = b'X' * 32
                (events / (name + '.bin')).write_bytes(binary)
                metadata = {'format': 'FRM1', 'frame_bytes': 32,
                            'frame_count': 1, 'binary_bytes': 32,
                            'binary_file': name + '.bin',
                            'binary_sha256': '0' * 64 if wrong_hash else
                                hashlib.sha256(binary).hexdigest(),
                            'trigger_seq': 1 if not wrong_hash else 2,
                            'created_utc': '2026-10-18T03:22:40.000000+00:00',
                            'reason': 'vibration threshold'}
                (events / (name + '.json')).write_text(json.dumps(metadata),
                                                       encoding='utf-8')
            service.scan_events()
            outcomes = {row[1]: row[6] for row in service.journal.pending(
                time.time() + 3)}
            self.assertEqual(outcomes['wave-events-1-abcdef12/event-good'],
                             p.SAVE_COMPLETE)
            self.assertEqual(outcomes['wave-events-1-abcdef12/event-bad'],
                             p.SAVE_FAILED)
            service.journal.close()


if __name__ == '__main__':
    unittest.main()
