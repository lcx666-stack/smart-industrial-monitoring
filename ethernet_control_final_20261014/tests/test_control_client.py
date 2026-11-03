"""The client must forward only validated motor parameters, prefer the warm
board agent, and still work through the one-shot CLI when the agent fails."""

import importlib.util
import unittest
from pathlib import Path
from unittest import mock


spec = importlib.util.spec_from_file_location(
    'control_client_under_test', Path(__file__).with_name('control_client.py'))
cc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cc)

OK_REPLY = mock.Mock(returncode=0, stdout='{"ok": true, "data": {}}', stderr='')
AGENT_REPLY = {'ok': True, 'data': {'message': 'ok'}}


class ClientHarness(unittest.TestCase):
    def client(self, use_agent=False):
        with mock.patch.object(cc.ControlClient, '_run', return_value=OK_REPLY):
            return cc.ControlClient('192.168.0.50', 'key', use_agent=use_agent)


class MotorRequestTests(ClientHarness):
    def remote_for(self, **fields):
        client = self.client()
        with mock.patch.object(client, '_run', return_value=OK_REPLY) as run:
            client.request('motor_start', **fields)
        return run.call_args[0][0]

    def test_duty_is_forwarded_only_with_confirmation(self):
        remote = self.remote_for(operator_confirmed=True, duty_percent=30)
        self.assertTrue(remote.endswith('motor_start --confirm --duty-percent 30'),
                        remote)

    def test_start_without_duty_stays_valid(self):
        remote = self.remote_for(operator_confirmed=True)
        self.assertTrue(remote.endswith('motor_start --confirm'), remote)

    def test_invalid_or_extra_parameters_are_refused(self):
        for fields in ({'operator_confirmed': True, 'duty_percent': 9},
                       {'operator_confirmed': True, 'duty_percent': 61},
                       {'operator_confirmed': True, 'duty_percent': '30'},
                       {'operator_confirmed': True, 'duty_percent': True},
                       {'operator_confirmed': False, 'duty_percent': 30},
                       {'operator_confirmed': True, 'seconds': 3600},
                       {'duty_percent': 30}):
            client = self.client()
            with mock.patch.object(client, '_run', return_value=OK_REPLY) as run:
                with self.assertRaises(ValueError):
                    client.request('motor_start', **fields)
            run.assert_not_called()

    def test_stop_estop_and_clear_are_accepted_without_parameters(self):
        for op in ('motor_stop', 'motor_estop', 'motor_clear', 'motor_preflight',
                   'ai_start', 'ai_stop', 'blackbox_start', 'status'):
            client = self.client()
            with mock.patch.object(client, '_run', return_value=OK_REPLY) as run:
                client.request(op, **({'operator_confirmed': True}
                                       if op in ('motor_estop', 'motor_clear')
                                       else {}))
            suffix = ' ' + op + (' --confirm'
                                 if op in ('motor_estop', 'motor_clear')
                                 else '')
            self.assertTrue(run.call_args[0][0].endswith(suffix),
                            run.call_args[0][0])

    def test_non_duty_operations_reject_parameters(self):
        client = self.client()
        with self.assertRaises(ValueError):
            client.request('motor_stop', duty_percent=30)
        with self.assertRaises(ValueError):
            client.request('unknown_operation')


class AgentTransportTests(ClientHarness):
    def agent_client(self):
        return self.client(use_agent=True)

    def test_agent_payload_carries_op_confirm_and_duty(self):
        client = self.agent_client()
        with mock.patch.object(client, '_agent_reply',
                               return_value=dict(AGENT_REPLY)) as agent, \
             mock.patch.object(client, '_run') as run:
            reply = client.request('motor_start', operator_confirmed=True,
                                   duty_percent=30)
        self.assertEqual(agent.call_args[0][0],
                         {'op': 'motor_start', 'confirm': True, 'duty_percent': 30})
        run.assert_not_called()
        self.assertTrue(reply['ok'])

    def test_status_payload_has_no_motor_fields(self):
        client = self.agent_client()
        with mock.patch.object(client, '_agent_reply',
                               return_value=dict(AGENT_REPLY)) as agent:
            client.request('status')
        self.assertEqual(agent.call_args[0][0], {'op': 'status'})

    def test_agent_failure_falls_back_to_the_one_shot_cli(self):
        client = self.agent_client()
        with mock.patch.object(client, '_agent_reply', return_value=None), \
             mock.patch.object(client, '_run', return_value=OK_REPLY) as run:
            reply = client.request('status')
        self.assertIn('board_control_duty.py status', run.call_args[0][0])
        self.assertTrue(reply['ok'])

    def test_agent_is_not_retried_immediately_after_failure(self):
        client = self.agent_client()
        client._stop_agent()
        with mock.patch.object(client, '_start_agent') as start, \
             mock.patch.object(client, '_run', return_value=OK_REPLY):
            client.request('status')
        start.assert_not_called()

    def test_agent_can_be_disabled_entirely(self):
        client = self.client(use_agent=False)
        with mock.patch.object(client, '_agent_reply') as agent, \
             mock.patch.object(client, '_run', return_value=OK_REPLY):
            client.request('status')
        agent.assert_not_called()


class CanStatusTests(ClientHarness):
    def test_live_can_status_uses_fixed_read_only_helper(self):
        client = self.client()
        reply = {
            'ok': True,
            'service': {'active_state': 'active', 'sub_state': 'running'},
            'pairing': {'paired': True, 'nonce': 'F32D'},
            'can': {'available': True, 'state': 'ERROR-ACTIVE'},
        }
        result = mock.Mock(returncode=0, stdout=cc.json.dumps(reply), stderr='')
        with mock.patch.object(cc.subprocess, 'run', return_value=result) as run:
            self.assertEqual(client.can_alarm_status(), reply)
        argv = run.call_args[0][0]
        self.assertIn(cc.CAN_STATUS_HELPER, argv)
        self.assertIn('root@192.168.0.50', argv)

    def test_live_can_status_rejects_invalid_output(self):
        client = self.client()
        bad = mock.Mock(returncode=0, stdout='not-json', stderr='')
        with mock.patch.object(cc.subprocess, 'run', return_value=bad):
            with self.assertRaises(ConnectionError):
                client.can_alarm_status()

    def test_live_can_stream_uses_one_persistent_ssh_process(self):
        client = self.client()
        process = object()
        with mock.patch.object(cc.subprocess, 'Popen',
                               return_value=process) as popen:
            self.assertIs(client.open_can_alarm_stream(500), process)
        argv = popen.call_args[0][0]
        self.assertIn(cc.CAN_STATUS_HELPER, argv)
        self.assertIn('--watch', argv)
        self.assertEqual(argv[-1], '500')


if __name__ == '__main__':
    unittest.main()
