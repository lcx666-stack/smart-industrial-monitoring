import json
import collections
import importlib.util
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from waveform_display import (VIBRATION_COLORS, WaveformPanel, current_readout,
                              display_current_interval, parse_wave_packet,
                              vibration_view)

with mock.patch.dict(sys.modules, {'fcntl': mock.Mock()}):
    spec = importlib.util.spec_from_file_location(
        'board_control_wave_under_test', Path(__file__).with_name('board_control.py'))
    board = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(board)


class PacketTests(unittest.TestCase):
    def test_current_display_reverses_polarity_without_mutating_raw_data(self):
        raw = [-156, -81, 1, 2, 3, 4, 5, 6]
        self.assertEqual(display_current_interval(raw), (81, 156))
        self.assertEqual(raw[:2], [-156, -81])
        self.assertEqual(display_current_interval([-30, 40]), (-40, 30))

    def test_current_readout_uses_latest_two_ms_range(self):
        self.assertEqual(current_readout(None), '最新 2 ms：等待数据')
        self.assertEqual(current_readout([-156, -81, 1, 2, 3, 4, 5, 6]),
                         '最新 2 ms：81～156 mA')
        self.assertEqual(current_readout([-156, -81, 1, 2, 3, 4, 5, 6], False),
                         '末次 2 ms（已停止）：81～156 mA')

    def test_current_value_is_drawn_and_marked_stale_after_stop(self):
        panel = WaveformPanel.__new__(WaveformPanel)
        panel.canvas = mock.Mock()
        panel.width, panel.height = 960, 540
        panel.history = []
        panel.current_range, panel.vibration_range = 1600, 2048
        panel.live = False
        packet = {'bins': [[-156, -81, 1, 2, 3, 4, 5, 6]]}
        panel.add(packet)
        texts = [call.kwargs.get('text') for call in panel.canvas.create_text.call_args_list]
        self.assertIn('最新 2 ms：81～156 mA', texts)
        self.assertIn('电机电流 (mA)', texts)
        self.assertIn('PL 已设固定零点，未扣本次空载基线', texts)
        panel.canvas.reset_mock()
        panel.mark_stopped()
        texts = [call.kwargs.get('text') for call in panel.canvas.create_text.call_args_list]
        self.assertIn('末次 2 ms（已停止）：81～156 mA', texts)

    def test_current_threshold_lines_are_drawn_at_positive_and_negative_limits(self):
        panel = WaveformPanel.__new__(WaveformPanel)
        panel.canvas = mock.Mock()
        panel.width, panel.height = 960, 540
        panel.history = []
        panel.current_range, panel.vibration_range = 1600, 2048
        panel.live = False
        panel.draw()

        threshold_calls = [
            call for call in panel.canvas.create_line.call_args_list
            if call.kwargs.get('fill') == '#ff4d4f'
        ]
        self.assertGreaterEqual(len(threshold_calls), 2)
        self.assertEqual(threshold_calls[0].args, (0, 37.125, 960, 37.125))
        self.assertEqual(threshold_calls[1].args, (0, 97.875, 960, 97.875))
        texts = [call.kwargs.get('text') for call in panel.canvas.create_text.call_args_list]
        self.assertIn('+800 mA', texts)
        self.assertIn('-800 mA', texts)
        positive_label = next(
            call for call in panel.canvas.create_text.call_args_list
            if call.kwargs.get('text') == '+800 mA'
        )
        self.assertEqual(positive_label.args, (8, 41.125))
        self.assertEqual(positive_label.kwargs.get('anchor'), 'nw')

    def test_each_vibration_channel_has_one_absolute_raw_threshold_line(self):
        panel = WaveformPanel.__new__(WaveformPanel)
        panel.canvas = mock.Mock()
        panel.width, panel.height = 960, 540
        panel.history = collections.deque([
            [5300, 5310, 5380, 5390, 5360, 5370, 5350, 5360]
        ])
        panel.current_range, panel.vibration_range = 1600, 2048
        panel.live = False
        panel.draw()

        threshold_calls = [
            call for call in panel.canvas.create_line.call_args_list
            if call.kwargs.get('fill') == '#ff4d4f'
        ]
        self.assertEqual(len(threshold_calls), 5)
        row_h = panel.height / 4
        for channel in range(1, 4):
            top = channel * row_h
            expected_y = top + 3
            self.assertEqual(threshold_calls[channel + 1].args,
                             (0, expected_y, 960, expected_y))
        texts = [call.kwargs.get('text') for call in panel.canvas.create_text.call_args_list]
        self.assertIn('X >= 7000 ADC', texts)
        self.assertIn('Y >= 7000 ADC', texts)
        self.assertIn('Z >= 7000 ADC', texts)

    def test_vibration_auto_zoom_and_bold_envelope_are_visible(self):
        history = collections.deque([
            [0, 0, 5300, 5320, 5400, 5420, 5500, 5520],
            [0, 0, 5320, 5340, 5420, 5440, 5520, 5540],
        ])
        centre, view, peak = vibration_view(history, 1)
        self.assertEqual((centre, view, peak), (5320, 256, 20))

        panel = WaveformPanel.__new__(WaveformPanel)
        panel.canvas = mock.Mock()
        panel.width, panel.height = 960, 540
        panel.history = history
        panel.current_range, panel.vibration_range = 1600, 2048
        panel.live = True
        panel.draw()
        vibration_strokes = [
            call for call in panel.canvas.create_line.call_args_list
            if call.kwargs.get('fill') == VIBRATION_COLORS[0] and
            call.kwargs.get('width') == 3
        ]
        self.assertEqual(len(vibration_strokes), 2)
        texts = [call.kwargs.get('text')
                 for call in panel.canvas.create_text.call_args_list]
        self.assertIn('Δ峰值 20 · 自动纵轴 ±256 ADC', texts)

    def run_native(self, script):
        compiler = shutil.which('gcc')
        if compiler is None:
            self.skipTest('C compiler unavailable')
        with tempfile.TemporaryDirectory() as temporary:
            library = Path(temporary) / ('wave.dll' if os.name == 'nt' else 'wave.so')
            source = Path(__file__).with_name('board_wave_envelope.c')
            subprocess.run([compiler, '-O3', '-Wall', '-Wextra', '-Werror', '-shared',
                            '-fPIC', '-o', str(library), str(source)], check=True)
            result = subprocess.run([sys.executable, '-c', script, str(library)],
                                    cwd=str(source.parent), text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    check=True)
            return result.stdout.strip()

    def test_min_max_envelope_keeps_spike(self):
        packet = parse_wave_packet(self.run_native('''
import struct,sys
from board_wave_service import Envelope,NativeEnvelope
class Viewer:
 def publish(self,data):print(data.decode().strip())
class Recorder:sequence_gaps=0
frame=struct.Struct('<hhhhIIQiI')
data=b''.join(frame.pack(0,5300+i%3,5400,5500,i,1,i*2000,
                         700 if i==13 else -120,0x314d5246) for i in range(5000))
Envelope(Viewer(),Recorder(),NativeEnvelope(sys.argv[1])).ingest(data,{'dropped':0})
'''))
        self.assertEqual(len(packet['bins']), 50)
        self.assertEqual(packet['bins'][0][:2], [-120, 700])
        self.assertEqual(packet['bins'][0][2:4], [5300, 5302])

    def test_split_batches_keep_exact_100_frame_boundaries(self):
        rows = json.loads(self.run_native('''
import json,struct,sys
from board_wave_service import NativeEnvelope
native=NativeEnvelope(sys.argv[1]); frame=struct.Struct('<hhhhIIQiI')
data=b''.join(frame.pack(0,1,2,3,i,1,i*2000,
                         900 if i==117 else -100,0x314d5246) for i in range(200))
first=native.ingest(data[:117*32]); second=native.ingest(data[117*32:])
print(json.dumps([first,second]))
'''))
        self.assertEqual(rows[0][0][:2], [-100, -100])
        self.assertEqual(rows[1][0][:2], [-100, 900])

    def test_bad_packet_is_refused(self):
        with self.assertRaises(ValueError):
            parse_wave_packet(json.dumps({'kind': 'wave', 'bin_ms': 2,
                                          'bins': [[1, 0] * 4],
                                          'seq_gaps': 0, 'dropped': 0}))


class MotorProfileTests(unittest.TestCase):
    def test_only_matching_pl_abi_selects_pwm10_script(self):
        self.assertEqual(board.motor_script({'duty_min': 10, 'open_loop_abi': 0x10001}),
                         board.MOTOR10)
        self.assertEqual(board.motor_script({'duty_min': 15, 'open_loop_abi': 0x10000}),
                         board.MOTOR)
        with self.assertRaises(RuntimeError):
            board.motor_script({'duty_min': 10, 'open_loop_abi': 0x10000})

    def test_manual_blackbox_trigger_uses_persistent_recorder(self):
        state = {'wave': {'pid': 42, 'birth': 'x', 'log': 'wave.log'}}
        with mock.patch.object(board.signal, 'SIGUSR1', 10, create=True), \
             mock.patch.object(board, 'active', return_value=True), \
             mock.patch.object(board.os, 'kill') as kill:
            result = board.action('blackbox_start', state, False)
        kill.assert_called_once_with(42, 10)
        self.assertIn('manual event', result['message'])

    def test_wave_fault_ack_requires_inspection_and_dma_release(self):
        state = {'wave': {'pid': 42, 'birth': 'x', 'log': 'wave.log'},
                 'fault_latched': True}
        pl = {'pl_id': 0x4d535431, 'features': 0x4143, 'motor_fault': 0,
              'guard_fault': 0, 'guard_state': 4, 'applied_duty': 0,
              'motor_status': 0x2b}
        with mock.patch.object(board, 'active', return_value=False), \
             mock.patch.object(board, 'tail', return_value='WAVE_SERVICE_FAIL: ADC DMA integrity fault'), \
             mock.patch.object(board, 'dma_device_open', return_value=False), \
             mock.patch.object(board, 'read_pl', return_value=pl), \
             mock.patch.object(board.Path, 'exists', return_value=False):
            with self.assertRaisesRegex(RuntimeError, 'inspection confirmation'):
                board.action('wave_ack', state, False)
            result = board.action('wave_ack', state, True)
        self.assertIsNone(state['wave'])
        self.assertFalse(state['fault_latched'])
        self.assertIn('acknowledged', result['message'])


if __name__ == '__main__':
    unittest.main()
