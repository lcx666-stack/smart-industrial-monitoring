import json
import struct
import unittest
from unittest import mock
from unittest import mock

from control_client import ControlClient
from video_protocol import BOX, HEADER, IMAGE_BYTES, read_packet


class ChunkSocket:
    def __init__(self, data):
        self.data = memoryview(data)
        self.offset = 0

    def recv_into(self, target):
        amount = min(len(target), 997, len(self.data) - self.offset)
        if amount:
            target[:amount] = self.data[self.offset:self.offset + amount]
            self.offset += amount
        return amount


class ProtocolTests(unittest.TestCase):
    def packet(self, boxes=b'', magic=b'CSNB', count=0):
        return (HEADER.pack(magic, 5, 960, 540, IMAGE_BYTES, 1, count) +
                bytes(IMAGE_BYTES) + boxes)

    def test_valid_packet(self):
        box = BOX.pack(10, 20, 30, 40, 875)
        sequence, infer_sequence, rgb, boxes = read_packet(ChunkSocket(self.packet(box, count=1)))
        self.assertEqual((sequence, infer_sequence, len(rgb), boxes),
                         (5, 1, IMAGE_BYTES, [(10, 20, 30, 40, 875)]))

    def test_bad_packet_rejected(self):
        with self.assertRaises(ValueError):
            read_packet(ChunkSocket(self.packet(magic=b'NOPE')))
        with self.assertRaises(ValueError):
            read_packet(ChunkSocket(self.packet(BOX.pack(30, 20, 10, 40, 10), count=1)))
        with self.assertRaises(ConnectionError):
            read_packet(ChunkSocket(self.packet()[:-1]))

    def test_ssh_fixed_commands_only(self):
        def fake_run(argv, **kwargs):
            self.assertIn('StrictHostKeyChecking=yes', argv)
            self.assertIn('BatchMode=yes', argv)
            self.assertNotIn('StrictHostKeyChecking=no', argv)
            return mock.Mock(returncode=0, stdout=json.dumps({'ok': True, 'data': {}}), stderr='')
        with mock.patch('subprocess.run', side_effect=fake_run):
            client = ControlClient('192.168.0.50', 'dummy-key')
            self.assertTrue(client.request('motor_start', operator_confirmed=True)['ok'])
            self.assertTrue(client.run_shell('id -u')['ok'])
            with self.assertRaises(ValueError):
                client.request('arbitrary-command')
            with self.assertRaises(ValueError):
                client.request('motor_start', seconds=10)


class DashboardFeedbackTests(unittest.TestCase):
    """The status poll runs every second, so its timing must not fill the log."""

    def finish(self, label, elapsed):
        from desktop_dashboard import Dashboard
        stub = mock.MagicMock()
        stub.pending_ops = 1
        Dashboard.finish_pending(stub, label, elapsed)
        return stub

    def test_status_timing_is_shown_quietly(self):
        stub = self.finish("status", 0.03)
        stub.write_log.assert_not_called()
        stub.timing_text.set.assert_called_once()
        self.assertIn("0.03", stub.timing_text.set.call_args[0][0])

    def test_operator_commands_are_still_logged_with_their_latency(self):
        stub = self.finish("motor_start", 1.4)
        stub.write_log.assert_called_once()
        self.assertIn("1.4", stub.write_log.call_args[0][0])

    def test_missing_timing_does_not_log_or_crash(self):
        stub = self.finish("motor_stop", None)
        stub.write_log.assert_not_called()
        stub.timing_text.set.assert_not_called()

    def test_live_can_paired_status_replaces_static_deployment_text(self):
        from desktop_dashboard import GREEN, format_can_alarm_status
        text, color = format_can_alarm_status({
            'service': {'active_state': 'active', 'sub_state': 'running'},
            'pairing': {'paired': True, 'nonce': 'F32D', 'known': True},
            'can': {'available': True, 'state': 'ERROR-ACTIVE',
                    'bitrate': 500000, 'rx_packets': 1, 'tx_packets': 78,
                    'bus_errors': 0},
        })
        self.assertIn('已配对', text)
        self.assertIn('F32D', text)
        self.assertIn('ERROR-ACTIVE', text)
        self.assertIn('收 1 / 发 78', text)
        self.assertNotIn('待部署', text)
        self.assertEqual(color, GREEN)

    def test_live_can_waiting_status_is_explicit(self):
        from desktop_dashboard import ACCENT, format_can_alarm_status
        text, color = format_can_alarm_status({
            'service': {'active_state': 'active', 'sub_state': 'running'},
            'pairing': {'paired': False, 'known': True},
            'can': {'available': True, 'state': 'ERROR-ACTIVE',
                    'bitrate': 500000, 'rx_packets': 0, 'tx_packets': 0,
                    'bus_errors': 0},
        })
        self.assertIn('等待 STM32 复位配对', text)
        self.assertEqual(color, ACCENT)


class RoiOverlayTests(unittest.TestCase):
    def test_roi_comes_from_board_log(self):
        from desktop_dashboard import roi_from_board_log
        self.assertEqual(roi_from_board_log(
            "BOARD_AI waiting\nBOARD_AI roi=160,90,640,360 scale=1 pad=0,140\n"),
            (160, 90, 640, 360))
        self.assertIsNone(roi_from_board_log("BOARD_AI frames=30 boxes=1"))
        self.assertIsNone(roi_from_board_log("BOARD_AI roi=160,90,900,360 scale=1"))

    def test_roi_overlay_is_hidden_after_stop(self):
        from desktop_dashboard import Dashboard
        stub = mock.MagicMock()
        stub.active_roi = None
        stub.roi_item = 2
        stub.roi_label = 3
        Dashboard.set_roi(stub, (160, 90, 640, 360))
        stub.canvas.coords.assert_any_call(2, 160, 90, 800, 450)
        stub.canvas.itemconfigure.assert_any_call(2, state="normal")
        stub.active_roi = (160, 90, 640, 360)
        Dashboard.set_roi(stub, None)
        stub.canvas.itemconfigure.assert_any_call(2, state="hidden")
        stub.canvas.itemconfigure.assert_any_call(3, state="hidden")


class CanStatusHelperTests(unittest.TestCase):
    def test_can_state_uses_error_active_not_interface_up(self):
        from board_can_status import can_state
        output = (
            '2: can0: <NOARP,UP,LOWER_UP> mtu 72 state UP mode DEFAULT\n'
            '    can <FD> state ERROR-ACTIVE\n'
            '          bitrate 500000 sample-point 0.800\n'
            '    RX: bytes  packets  errors  dropped overrun mcast\n'
            '    8          1        0       0       0       0\n'
            '    TX: bytes  packets  errors  dropped carrier collsns\n'
            '    624        78       0       0       0       0\n'
            '          re-started bus-errors arbit-lost error-warn '
            'error-pass bus-off\n'
            '          0          0          0          0          0       0\n')
        result = mock.Mock(returncode=0, stdout=output, stderr='')
        with mock.patch('board_can_status.run', return_value=result):
            state = can_state()
        self.assertEqual(state['state'], 'ERROR-ACTIVE')
        self.assertEqual((state['rx_packets'], state['tx_packets']), (1, 78))
        self.assertEqual(state['bus_errors'], 0)

    def test_pairing_is_read_from_current_service_pid_only(self):
        from board_can_status import pairing_state
        result = mock.Mock(
            returncode=0, stdout='STM32 paired: nonce=f32d\n', stderr='')
        with mock.patch('board_can_status.run', return_value=result) as run:
            state = pairing_state(926, 'active')
        self.assertTrue(state['paired'])
        self.assertEqual(state['nonce'], 'F32D')
        self.assertIn('_PID=926', run.call_args[0][0])


if __name__ == '__main__':
    unittest.main()
