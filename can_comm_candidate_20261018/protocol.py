"""Classic CAN alarm frame formats for the CS500-to-STM32 link.

Pair request ID 0x190, pair confirmation ID 0x191, alarm ID 0x180 and its
acknowledgement ID 0x280 are used on the live link.
The board service ignores CAN control commands; control is over Ethernet/SSH.
Only eight-byte standard frames are accepted. Integer fields are little-endian.
"""

import struct
import zlib

ESTOP_ID = 0x080
STOP_ID = 0x081
ALARM_ID = 0x180
TIME_ID = 0x181
SAVE_ID = 0x182
HEARTBEAT_ID = 0x183
EVENT_KEY_ID = 0x184
PAIR_REQUEST_ID = 0x190
PAIR_CONFIRM_ID = 0x191
ALARM_ACK_ID = 0x280
COMMAND_ID = 0x300
REPLY_ID = 0x380

GET_STATUS = 1
MOTOR_START = 2
MOTOR_SET_DUTY = 3
CLEAR_FAULT = 4
MARK_EVENT = 5
STOP = 6
ESTOP = 7
COMMANDS = {GET_STATUS, MOTOR_START, MOTOR_SET_DUTY, CLEAR_FAULT, MARK_EVENT, STOP, ESTOP}
CONTROL_IDS = {STOP: STOP_ID, ESTOP: ESTOP_ID}

ACCEPTED = 1
DONE = 2
REJECTED = 3
FAILED = 4

BAD_FRAME = 1
BAD_COMMAND = 2
NOT_ARMED = 3
BOARD_REJECTED = 4
BOARD_ERROR = 5
REPLAY_CONFLICT = 6

FAULT_CODES = {
    'PL_MOTOR_FAULT': 1, 'ADC_ERROR': 2, 'DMA_DROP': 3,
    'TIMESTAMP_MISMATCH': 4, 'SEQ_GAP': 5, 'CURRENT_LIMIT': 6,
    'VIBRATION_LIMIT': 7, 'MANUAL': 8, 'OTHER_EVENT': 255,
}
FAULT_NAMES = {v: k for k, v in FAULT_CODES.items()}
SAVE_PENDING = 0
SAVE_COMPLETE = 1
SAVE_PARTIAL = 2
SAVE_FAILED = 3
ACK_ALARM = 1
ACK_TIME = 2
ACK_SAVE = 4
ACK_KEY = 8
VERSION_FLAGS = 0x10
FRAME_SIZE = 8
PAIR_MAGIC = 0x31505343  # "CSP1" little-endian
PAIR_VERSION = 1


def _frame(can_id, payload):
    if len(payload) != FRAME_SIZE or not 0 <= can_id <= 0x7ff:
        raise ValueError('standard CAN frame must contain eight bytes')
    return can_id, payload


def command(request_id, opcode, value=0, sender=1):
    if type(request_id) is not int or not 0 <= request_id <= 0xffffffff:
        raise ValueError('bad request id')
    if opcode not in COMMANDS or type(value) is not int or not 0 <= value <= 255:
        raise ValueError('bad command')
    if type(sender) is not int or not 1 <= sender <= 255:
        raise ValueError('bad sender')
    if opcode in (MOTOR_START, MOTOR_SET_DUTY):
        if not 10 <= value <= 60:
            raise ValueError('motor duty must be 10..60')
    elif value:
        raise ValueError('only motor start/set-duty takes a value')
    return _frame(CONTROL_IDS.get(opcode, COMMAND_ID),
                  struct.pack('<IBBBB', request_id, opcode, value,
                              VERSION_FLAGS, sender))


def parse_command(can_id, payload, sender=1):
    if can_id not in (COMMAND_ID, STOP_ID, ESTOP_ID) or len(payload) != 8:
        raise ValueError('not a v1 command frame')
    request_id, opcode, value, flags, source = struct.unpack('<IBBBB', payload)
    if source != sender or flags != VERSION_FLAGS:
        raise ValueError('source or version mismatch')
    if CONTROL_IDS.get(opcode, COMMAND_ID) != can_id:
        raise ValueError('opcode/identifier mismatch')
    command(request_id, opcode, value, source)
    return request_id, opcode, value, source


def reply(request_id, opcode, outcome, state=0, detail=0):
    return _frame(REPLY_ID, struct.pack('<IBBBB', request_id, opcode,
                                        outcome, state, detail))


def alarm(seq, fault, flags, milliseconds):
    return _frame(ALARM_ID, struct.pack('<IBBH', seq, fault, flags, milliseconds))


def pair_request(nonce):
    if type(nonce) is not int or not 1 <= nonce <= 0xffff:
        raise ValueError('bad pairing nonce')
    return _frame(PAIR_REQUEST_ID,
                  struct.pack('<IBHB', PAIR_MAGIC, PAIR_VERSION, nonce, 0))


def pair_confirm(nonce):
    if type(nonce) is not int or not 1 <= nonce <= 0xffff:
        raise ValueError('bad pairing nonce')
    return _frame(PAIR_CONFIRM_ID,
                  struct.pack('<IBHB', PAIR_MAGIC, PAIR_VERSION, nonce, 0))


def _parse_pair(can_id, payload, expected_id):
    if can_id != expected_id or len(payload) != 8:
        raise ValueError('not a pairing frame')
    magic, version, nonce, reserved = struct.unpack('<IBHB', payload)
    if magic != PAIR_MAGIC or version != PAIR_VERSION or not nonce or reserved:
        raise ValueError('bad pairing frame')
    return nonce


def parse_pair_request(can_id, payload):
    return _parse_pair(can_id, payload, PAIR_REQUEST_ID)


def parse_pair_confirm(can_id, payload):
    return _parse_pair(can_id, payload, PAIR_CONFIRM_ID)


def event_time(seq, utc_seconds):
    return _frame(TIME_ID, struct.pack('<II', seq, utc_seconds))


def save(seq, result, flags=0, size_kib=0):
    return _frame(SAVE_ID, struct.pack('<IBBH', seq, result, flags, size_kib))


def event_key(seq, event_id):
    return _frame(EVENT_KEY_ID, struct.pack('<II', seq,
                  zlib.crc32(event_id.encode('utf-8')) & 0xffffffff))


def heartbeat(uptime, guard_fault, state, node=1):
    return _frame(HEARTBEAT_ID, struct.pack('<IBBBB', uptime, guard_fault,
                                            state, 1, node))


def alarm_ack(seq, mask, receiver=1):
    if not 0 <= mask <= 15:
        raise ValueError('bad acknowledgment mask')
    return _frame(ALARM_ACK_ID, struct.pack('<IBBH', seq, mask, receiver, 0))


def parse_alarm_ack(payload, receiver=1):
    if len(payload) != 8:
        raise ValueError('bad acknowledgment length')
    seq, mask, source, reserved = struct.unpack('<IBBH', payload)
    if source != receiver or reserved or not 0 <= mask <= 15:
        raise ValueError('bad acknowledgment')
    return seq, mask


def decode(can_id, payload):
    if len(payload) != 8:
        raise ValueError('bad payload length')
    specs = {
        PAIR_REQUEST_ID: ('<IBHB', ('magic', 'version', 'nonce', 'reserved')),
        PAIR_CONFIRM_ID: ('<IBHB', ('magic', 'version', 'nonce', 'reserved')),
        ALARM_ID: ('<IBBH', ('seq', 'fault', 'flags', 'ms')),
        TIME_ID: ('<II', ('seq', 'utc_seconds')),
        SAVE_ID: ('<IBBH', ('seq', 'result', 'flags', 'size_kib')),
        EVENT_KEY_ID: ('<II', ('seq', 'event_key')),
        HEARTBEAT_ID: ('<IBBBB', ('uptime_s', 'guard_fault', 'state',
                                  'version', 'node')),
        REPLY_ID: ('<IBBBB', ('request_id', 'opcode', 'outcome', 'state', 'detail')),
    }
    if can_id not in specs:
        raise ValueError('unknown CAN id')
    fmt, names = specs[can_id]
    return dict(zip(names, struct.unpack(fmt, payload)))
