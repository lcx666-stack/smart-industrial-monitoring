import hashlib
import io
import json
import struct
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import board_alarm_events as board
from control_client import ControlClient
from desktop_dashboard import Dashboard
from fault_history import FRAME, MAGIC, event_envelope


EVENT_ID = 'wave-events-123-abcdef12/event-20261018T100000Z-00000001-001'


class AlarmHistoryTests(unittest.TestCase):
    def make_event(self, root, corrupt=False):
        folder, name = EVENT_ID.split('/')
        directory = Path(root) / folder
        directory.mkdir()
        binary = b''.join(FRAME.pack(0, 100 if i == 2 else 1, 2, 3,
                                     i, 1, i * 100, 800 if i == 2 else 10,
                                     MAGIC) for i in range(5))
        digest = hashlib.sha256(binary).hexdigest()
        (directory / (name + '.bin')).write_bytes(binary if not corrupt else binary[:-1])
        metadata = {'format': 'FRM1', 'frame_bytes': 32, 'frame_count': 5,
                    'binary_bytes': len(binary), 'binary_sha256': digest,
                    'binary_file': name + '.bin', 'reason': 'PL motor fault',
                    'created_utc': '2026-10-18T10:00:00+00:00',
                    'pre_count': 2, 'trigger_seq': 2, 'incomplete': False}
        (directory / (name + '.json')).write_text(json.dumps(metadata), encoding='utf-8')
        return binary

    def test_completed_event_is_reported_and_verified_for_display(self):
        with tempfile.TemporaryDirectory() as root:
            binary = self.make_event(root)
            events = board.list_events(Path(root))
            self.assertEqual(len(events), 1)
            self.assertEqual(events[0]['code'], 'PL_MOTOR_FAULT')
            stream = io.BytesIO()
            board.fetch(EVENT_ID, Path(root), stream)
            with mock.patch.object(ControlClient, '_run', return_value=mock.Mock(returncode=0)):
                client = ControlClient('192.168.0.50', 'dummy-key')
            with mock.patch('control_client.subprocess.run', return_value=mock.Mock(
                    returncode=0, stdout=stream.getvalue(), stderr=b'')):
                received, raw = client.fetch_alarm_event(EVENT_ID)
            self.assertEqual(received['frame_count'], 5)
            self.assertEqual(raw, binary)
            bins = event_envelope(raw, width=2)
            self.assertEqual(bins[0][1], 800)
            self.assertEqual(bins[0][3], 100)

    def test_partial_write_is_not_reported_saved(self):
        with tempfile.TemporaryDirectory() as root:
            self.make_event(root, corrupt=True)
            self.assertEqual(board.list_events(Path(root)), [])

    def test_tampered_transport_and_path_are_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            self.make_event(root)
            stream = io.BytesIO()
            board.fetch(EVENT_ID, Path(root), stream)
            data = bytearray(stream.getvalue())
            data[-1] ^= 1
            with mock.patch.object(ControlClient, '_run', return_value=mock.Mock(returncode=0)):
                client = ControlClient('192.168.0.50', 'dummy-key')
            with mock.patch('control_client.subprocess.run', return_value=mock.Mock(
                    returncode=0, stdout=bytes(data), stderr=b'')):
                with self.assertRaisesRegex(ValueError, 'SHA-256'):
                    client.fetch_alarm_event(EVENT_ID)
            with self.assertRaises(ValueError):
                client.fetch_alarm_event('../state.json')
            with self.assertRaises(ValueError):
                board.paths('wave-events-123-abcdef12/../state')

    def test_bad_frame_refused_before_plotting(self):
        with tempfile.TemporaryDirectory() as root:
            binary = bytearray(self.make_event(root))
            struct.pack_into('<I', binary, 28, 0)
            with self.assertRaisesRegex(ValueError, 'invalid saved waveform frame'):
                event_envelope(binary)

    def test_existing_board_fault_reasons_have_codes(self):
        self.assertEqual(board.alarm_code('PL DMA frame loss'), 'DMA_DROP')
        self.assertEqual(board.alarm_code('waveform timestamp mismatch'),
                         'TIMESTAMP_MISMATCH')

    def test_new_saved_fault_notifies_without_realerting_old_history(self):
        dashboard = mock.MagicMock()
        dashboard.alarm_seen = set()
        dashboard.alarm_initialized = False
        dashboard.alarm_window = None
        old = {'id': 'old', 'code': 'MANUAL', 'created_utc': '2025-10-16',
               'frame_count': 200001, 'reason': 'manual software trigger'}
        new = {'id': 'new', 'code': 'PL_MOTOR_FAULT', 'created_utc': '2026-10-18',
               'frame_count': 200001, 'reason': 'PL motor fault'}
        Dashboard.show_alarm_catalog(dashboard, [old])
        dashboard.root.bell.assert_not_called()
        Dashboard.show_alarm_catalog(dashboard, [new, old])
        dashboard.root.bell.assert_called_once()
        self.assertIn('PL_MOTOR_FAULT', dashboard.write_log.call_args[0][0])
        dashboard.root.bell.reset_mock()
        Dashboard.show_alarm_catalog(dashboard, [new, old])
        dashboard.root.bell.assert_not_called()


if __name__ == '__main__':
    unittest.main()
