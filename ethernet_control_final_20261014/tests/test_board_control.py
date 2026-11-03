"""Regression tests for AI startup failures before camera/CMA ownership."""

import importlib.util
import signal
import sys
import unittest
from pathlib import Path
from unittest import mock


with mock.patch.dict(sys.modules, {'fcntl': mock.Mock()}):
    spec = importlib.util.spec_from_file_location(
        'board_control_under_test', Path(__file__).with_name('board_control.py'))
    board = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(board)


PREFLIGHT_LOG = ('RTNETLINK answers: File exists\n'
                 'BOARD_AI_PRE_CAPTURE_ABORT exit=2\n')
ENTRY = {'pid': 123, 'birth': 'test', 'log': 'ai.log'}


class AiPreflightTests(unittest.TestCase):
    def test_marker_is_only_safe_before_capture(self):
        self.assertTrue(board.before_capture_abort(PREFLIGHT_LOG))
        self.assertFalse(board.before_capture_abort(
            PREFLIGHT_LOG + 'BOARD_AI client connected\n'))
        self.assertFalse(board.before_capture_abort(
            PREFLIGHT_LOG + '[HARDNPU] intr timeout\n'))

    def test_preflight_abort_does_not_latch_hardware_fault(self):
        state = {'ai': ENTRY}
        with mock.patch.object(board, 'read_pl', return_value={}), \
             mock.patch.object(board, 'active', return_value=False), \
             mock.patch.object(board, 'tail', side_effect=lambda p: PREFLIGHT_LOG if p else ''):
            report = board.status(state)
        self.assertFalse(report['fault_latched'])
        self.assertFalse(state.get('fault_latched', False))

    def test_ai_start_reports_preflight_error_without_stale_entry(self):
        state = {}
        with mock.patch.object(board, 'verified'), \
             mock.patch.object(board, 'launch', return_value=ENTRY), \
             mock.patch.object(board, 'tail', return_value=PREFLIGHT_LOG), \
             mock.patch.object(board, 'active', return_value=False):
            with self.assertRaisesRegex(RuntimeError, 'before camera startup'):
                board.action('ai_start', state, False)
        self.assertIsNone(state['ai'])
        self.assertFalse(state.get('fault_latched', False))

    def test_ai_stop_accepts_verified_pre_capture_abort(self):
        state = {'ai': ENTRY}
        with mock.patch.object(board, 'tail', return_value=PREFLIGHT_LOG), \
             mock.patch.object(board, 'active', return_value=False):
            result = board.action('ai_stop', state, False)
        self.assertIn('before camera/CMA startup', result['message'])
        self.assertFalse(state.get('fault_latched', False))

    def test_ai_stop_latches_unverified_exit(self):
        state = {'ai': ENTRY}
        with mock.patch.object(board, 'tail', return_value='unknown exit\n'), \
             mock.patch.object(board, 'active', return_value=False):
            with self.assertRaisesRegex(RuntimeError, 'cleanup unconfirmed'):
                board.action('ai_stop', state, False)
        self.assertTrue(state['fault_latched'])


class MotorDutyTests(unittest.TestCase):
    """The operator sets duty and duration is left open, so one arm uses the
    longest run the PL guard accepts (3600 s) instead of a fixed 1-second test."""

    SFATORY = 'STOP verified\nPASS: guarded open-loop run ended normally\n'

    def start(self, duty):
        state = {}
        launched = {}

        def fake_launch(name, argv):
            launched['argv'] = list(argv)
            return {'pid': 1, 'birth': 'test', 'log': 'motor.log'}

        with mock.patch.object(board, 'active', return_value=False), \
             mock.patch.object(board, 'tail', return_value=self.SFATORY), \
             mock.patch.object(board, 'neutral', return_value=True), \
             mock.patch.object(board, 'read_pl',
                               return_value={'duty_min': 10,
                                             'open_loop_abi': 0x10001}), \
             mock.patch.object(board, 'verified'), \
             mock.patch.object(board.subprocess, 'run') as preflight, \
             mock.patch.object(board, 'wait_motor_active',
                               return_value={}), \
             mock.patch.object(board, 'launch', side_effect=fake_launch):
            result = board.action('motor_start', state, True, duty)
        preflight.assert_not_called()
        return result, launched['argv'], state

    def test_selected_duty_is_forwarded_with_open_duration(self):
        for duty in (15, 30, 45, 60):
            result, argv, state = self.start(duty)
            self.assertEqual(argv[argv.index('--duty-percent') + 1], str(duty))
            self.assertEqual(argv[argv.index('--seconds') + 1], '3600')
            self.assertNotIn('--continuous', argv)
            self.assertIn('--sensor-in-motor-lead', argv)
            self.assertEqual(state['motor_duty'], duty)
            self.assertIn('{}%'.format(duty), result['message'])

    def test_missing_duty_defaults_to_the_validated_baseline(self):
        result, argv, state = self.start(None)
        self.assertEqual(argv[argv.index('--duty-percent') + 1], '15')
        self.assertEqual(state['motor_duty'], 15)
        self.assertIn('15%', result['message'])

    def test_out_of_range_duty_is_rejected_before_any_launch(self):
        for duty in (0, 14, 61, 100, -15, '30', 30.5, True, False):
            state = {}
            with mock.patch.object(board, 'active', return_value=False), \
                 mock.patch.object(board, 'read_pl', return_value={'duty_min': 15}), \
                 mock.patch.object(board, 'launch') as launch:
                with self.assertRaisesRegex(RuntimeError, 'duty must be an integer'):
                    board.action('motor_start', state, True, duty)
            launch.assert_not_called()
            self.assertNotIn('motor', state)

    def test_confirmation_is_still_required(self):
        with mock.patch.object(board, 'launch') as launch:
            with self.assertRaisesRegex(RuntimeError, 'confirmation required'):
                board.action('motor_start', {}, False, 30)
        launch.assert_not_called()


class MotorStopSemanticsTests(unittest.TestCase):
    """Routine stop must not latch: the operator asked to be able to start and
    stop rotation repeatedly without a power cycle."""

    STOP_LINE = 'STOP verified: guard disabled, duty target=0, ctrl=FREE, bridge inactive\n'
    ESTOP_LINE = 'PASS: open-loop outputs disabled; operator stop latched\n'
    CLEAR_LINE = 'ACK: run-guard fault cleared; motor remains disarmed\n'
    ENTRY = {'pid': 4242, 'birth': 'tok', 'log': 'motor.log'}

    def test_graceful_stop_uses_sigterm_and_leaves_no_latch(self):
        state = {'motor': dict(self.ENTRY)}
        alive = {'value': True}

        def fake_kill(pid, sig):
            self.assertEqual(pid, 4242)
            self.assertEqual(sig, signal.SIGTERM)
            alive['value'] = False

        with mock.patch.object(board, 'active', side_effect=lambda e: alive['value']), \
             mock.patch.object(board, 'read_pl', return_value={}), \
             mock.patch.object(board, 'verified'), \
             mock.patch.object(board, 'tail', return_value=self.STOP_LINE), \
             mock.patch.object(board.os, 'kill', side_effect=fake_kill), \
             mock.patch.object(board.subprocess, 'run') as run:
            result = board.action('motor_stop', state, False)
        run.assert_not_called()
        self.assertIn('no latch', result['message'])
        self.assertFalse(state.get('fault_latched', False))

    def test_unconfirmed_graceful_stop_falls_back_to_latched_estop(self):
        state = {'motor': dict(self.ENTRY)}
        stop_result = mock.Mock(returncode=0, stdout=self.ESTOP_LINE.encode())
        with mock.patch.object(board, 'active', return_value=True), \
             mock.patch.object(board, 'read_pl', return_value={}), \
             mock.patch.object(board, 'verified'), \
             mock.patch.object(board, 'tail', return_value='nothing useful\n'), \
             mock.patch.object(board.os, 'kill'), \
             mock.patch.object(board.time, 'monotonic', side_effect=[0.0, 0.0, 100.0]), \
             mock.patch.object(board.time, 'sleep'), \
             mock.patch.object(board.subprocess, 'run', return_value=stop_result):
            result = board.action('motor_stop', state, False)
        self.assertIn('operator stop latched', result['message'])
        self.assertIn('graceful stop unconfirmed', result['message'])
        self.assertTrue(state['fault_latched'])

    def test_stop_without_a_run_is_a_no_op(self):
        with mock.patch.object(board, 'active', return_value=False), \
             mock.patch.object(board.subprocess, 'run') as run:
            result = board.action('motor_stop', {}, False)
        run.assert_not_called()
        self.assertIn('nothing to stop', result['message'])

    def test_estop_latches_and_clear_acknowledges(self):
        state = {}
        with mock.patch.object(board, 'verified'), \
             mock.patch.object(board, 'read_pl', return_value={}), \
             mock.patch.object(board.subprocess, 'run',
                               return_value=mock.Mock(returncode=0,
                                                      stdout=self.ESTOP_LINE.encode())):
            board.action('motor_estop', state, False)
        self.assertTrue(state['fault_latched'])
        self.assertTrue(state['stop_latched'])
        with mock.patch.object(board, 'verified'), \
             mock.patch.object(board.subprocess, 'run',
                               return_value=mock.Mock(returncode=0,
                                                      stdout=self.CLEAR_LINE.encode())):
            result = board.action('motor_clear', state, False)
        self.assertFalse(state['fault_latched'])
        self.assertNotIn('stop_latched', state)
        self.assertIn('fault cleared', result['message'])

    def test_clear_is_refused_when_the_board_refuses(self):
        state = {'fault_latched': True}
        refused = mock.Mock(returncode=1,
                            stdout=b'FAIL: Cannot acknowledge an active/core-faulted motor\n')
        with mock.patch.object(board, 'verified'), \
             mock.patch.object(board.subprocess, 'run', return_value=refused):
            with self.assertRaisesRegex(RuntimeError, 'latch not cleared'):
                board.action('motor_clear', state, False)
        self.assertTrue(state['fault_latched'])

    def test_clear_removes_legacy_can_stop_hold(self):
        state = {'fault_latched': True, 'can_stop_hold': True}
        cleared = mock.Mock(returncode=0, stdout=self.CLEAR_LINE.encode())
        with mock.patch.object(board, 'verified'), \
             mock.patch.object(board, 'active', return_value=False), \
             mock.patch.object(board.subprocess, 'run', return_value=cleared):
            board.clear_motor(state)
        self.assertFalse(state['fault_latched'])
        self.assertNotIn('can_stop_hold', state)

    CLEAN_PL = {'pl_id': 0x4d535431, 'features': 0x4143, 'motor_status': 0,
                'motor_fault': 0, 'guard_state': 0, 'guard_fault': 0,
                'applied_duty': 0, 'open_loop_abi': 0x10001,
                'duty_min': 10, 'duty_max': 60, 'camera_status': 0}

    def only_existing_logs(self, text):
        def fake_tail(path, limit=1600):
            return text if path else ''
        return fake_tail

    INTERRUPTED_LOG = (
        'Preflight: 0x4143, ADC fresh, outputs disabled\n'
        'Forward open-loop: requested duty=15%, PS limit=3600.0s, PL limit=PS+100ms\n'
        'STOP verified: guard disabled, duty target=0, ctrl FREE, bridge inactive\n'
        'snapshots=120 applied_duty_peak=15 current_delta=[-12.0,+1.0]mA\n'
        'Interrupted; no automatic clear or retry\n')
    FAULTY_LOG = INTERRUPTED_LOG + 'FAIL: Motor/guard fault latched; stop\n'

    def test_stale_unconfirmed_run_latches_until_acknowledged(self):
        state = {'motor': dict(self.ENTRY)}
        with mock.patch.object(board, 'active', return_value=False), \
             mock.patch.object(board, 'read_pl', return_value=dict(self.CLEAN_PL)), \
             mock.patch.object(board, 'tail',
                               side_effect=self.only_existing_logs('FAIL: Motor/guard fault latched\n')):
            report = board.status(state)
        self.assertTrue(report['fault_latched'])

    def test_clear_drops_the_record_so_status_stops_relatching(self):
        state = {'motor': dict(self.ENTRY), 'fault_latched': True, 'stop_latched': True}
        with mock.patch.object(board, 'active', return_value=False), \
             mock.patch.object(board, 'verified'), \
             mock.patch.object(board.subprocess, 'run',
                               return_value=mock.Mock(returncode=0,
                                                      stdout=self.CLEAR_LINE.encode())):
            board.action('motor_clear', state, False)
        self.assertIsNone(state['motor'])
        self.assertFalse(state['fault_latched'])
        self.assertNotIn('stop_latched', state)
        with mock.patch.object(board, 'active', return_value=False), \
             mock.patch.object(board, 'read_pl', return_value=dict(self.CLEAN_PL)), \
             mock.patch.object(board, 'tail',
                               side_effect=self.only_existing_logs('FAIL: Motor/guard fault latched\n')):
            report = board.status(state)
        self.assertFalse(report['fault_latched'])

    def test_sigterm_stop_counts_as_a_confirmed_stop(self):
        state = {'motor': dict(self.ENTRY)}
        with mock.patch.object(board, 'active', return_value=False), \
             mock.patch.object(board, 'read_pl', return_value=dict(self.CLEAN_PL)), \
             mock.patch.object(board, 'tail',
                               side_effect=self.only_existing_logs(self.INTERRUPTED_LOG)):
            report = board.status(state)
        self.assertFalse(report['fault_latched'])

    def test_restart_right_after_a_sigterm_stop_is_allowed(self):
        state = {'motor': dict(self.ENTRY)}
        with mock.patch.object(board, 'active', return_value=False), \
             mock.patch.object(board, 'tail',
                               side_effect=self.only_existing_logs(self.INTERRUPTED_LOG)), \
             mock.patch.object(board, 'neutral', return_value=True), \
             mock.patch.object(board, 'read_pl', return_value=dict(self.CLEAN_PL)), \
             mock.patch.object(board, 'verified'), \
             mock.patch.object(board, 'wait_motor_active',
                               return_value={}), \
             mock.patch.object(board, 'launch',
                               return_value={'pid': 9, 'birth': 'b', 'log': 'm.log'}):
            result = board.action('motor_start', state, True, 15)
        self.assertIn('15%', result['message'])
        self.assertFalse(state.get('fault_latched', False))

    def test_fault_word_in_the_same_log_still_blocks(self):
        state = {'motor': dict(self.ENTRY)}
        with mock.patch.object(board, 'active', return_value=False), \
             mock.patch.object(board, 'read_pl', return_value=dict(self.CLEAN_PL)), \
             mock.patch.object(board, 'tail',
                               side_effect=self.only_existing_logs(self.FAULTY_LOG)):
            report = board.status(state)
        self.assertTrue(report['fault_latched'])
        with mock.patch.object(board, 'launch') as launch:
            with self.assertRaisesRegex(RuntimeError, 'fault latched'):
                board.action('motor_start', state, True, 15)
        launch.assert_not_called()

    def test_run_that_never_reached_the_stop_line_still_latches(self):
        state = {'motor': dict(self.ENTRY)}
        with mock.patch.object(board, 'active', return_value=False), \
             mock.patch.object(board, 'read_pl', return_value=dict(self.CLEAN_PL)), \
             mock.patch.object(board, 'tail',
                               side_effect=self.only_existing_logs('Preflight: ok\n')):
            report = board.status(state)
        self.assertTrue(report['fault_latched'])


class BootMountGuardTests(unittest.TestCase):
    def test_unmounted_boot_partition_is_reported_clearly(self):
        with mock.patch.object(board, 'mounted', return_value=False):
            with self.assertRaisesRegex(RuntimeError, '/mnt/sdboot'):
                board.verified(board.MOTOR)

    def test_rootfs_files_are_not_gated_on_the_boot_mount(self):
        with mock.patch.object(board, 'mounted', return_value=False), \
             mock.patch.object(board.Path, 'open',
                               side_effect=FileNotFoundError):
            with self.assertRaises(FileNotFoundError):
                board.verified(board.AI)

    def test_mount_helper_parses_the_mount_table(self):
        with mock.patch('builtins.open',
                        mock.mock_open(read_data='/dev/mmcblk0p1 /mnt/sdboot vfat ro 0 0\n')):
            self.assertTrue(board.mounted('/mnt/sdboot'))
        with mock.patch('builtins.open',
                        mock.mock_open(read_data='/dev/mmcblk0p2 / ext4 rw 0 0\n')):
            self.assertFalse(board.mounted('/mnt/sdboot'))


class BoardPython36CompatibilityTests(unittest.TestCase):
    """The board runs Ubuntu 18.04 (Python 3.6). A 3.7-only call such as
    Path.is_mount() shipped once and every motor_clear failed with an
    AttributeError, so the source is checked directly."""

    BANNED = ('is_mount(', 'capture_output=', 'importlib.resources',
              'os.path.isrelative', 'text=True, errors=')

    def test_source_avoids_python37_only_apis(self):
        source = Path(__file__).with_name('board_control.py').read_text(encoding='utf-8')
        for token in self.BANNED:
            self.assertNotIn(token, source, 'board_control.py uses ' + token)


if __name__ == '__main__':
    unittest.main()
