"""Linux SocketCAN and optional python-can USB adapter transports."""

import socket
import struct

CAN_FRAME = struct.Struct('=IB3x8s')
CAN_EFF_FLAG = 0x80000000
CAN_RTR_FLAG = 0x40000000
CAN_ERR_FLAG = 0x20000000
CAN_SFF_MASK = 0x7ff


class SocketCan:
    def __init__(self, channel='can0'):
        if not hasattr(socket, 'AF_CAN'):
            raise RuntimeError('SocketCAN is unavailable on this system')
        self.sock = socket.socket(socket.AF_CAN, socket.SOCK_RAW,
                                  socket.CAN_RAW)
        self.sock.bind((channel,))

    def send(self, can_id, payload):
        if len(payload) != 8 or not 0 <= can_id <= CAN_SFF_MASK:
            raise ValueError('only eight-byte standard CAN frames are supported')
        self.sock.send(CAN_FRAME.pack(can_id, 8, payload))

    def recv(self, timeout=0.2):
        self.sock.settimeout(timeout)
        try:
            raw = self.sock.recv(CAN_FRAME.size)
        except socket.timeout:
            return None
        if len(raw) != CAN_FRAME.size:
            return None  # CAN FD and malformed frames are outside v1.
        can_id, length, payload = CAN_FRAME.unpack(raw)
        if can_id & (CAN_EFF_FLAG | CAN_RTR_FLAG | CAN_ERR_FLAG) or length != 8:
            return None
        return can_id & CAN_SFF_MASK, payload

    def close(self):
        self.sock.close()


class PythonCan:
    """Adapter-independent host transport; install python-can and USB driver."""

    def __init__(self, interface, channel, bitrate=500000, **options):
        try:
            import can
        except ImportError:
            raise RuntimeError('install python-can for the USB-CAN adapter')
        self.can = can
        self.bus = can.ThreadSafeBus(interface=interface, channel=channel,
                                     bitrate=bitrate, ignore_config=True, **options)

    def send(self, can_id, payload):
        if len(payload) != 8 or not 0 <= can_id <= CAN_SFF_MASK:
            raise ValueError('only eight-byte standard CAN frames are supported')
        self.bus.send(self.can.Message(arbitration_id=can_id, data=payload,
                                       is_extended_id=False), timeout=0.2)

    def recv(self, timeout=0.2):
        msg = self.bus.recv(timeout=timeout)
        if msg is None or msg.is_extended_id or msg.is_remote_frame or \
                msg.is_error_frame or len(msg.data) != 8:
            return None
        return msg.arbitration_id, bytes(msg.data)

    def close(self):
        self.bus.shutdown()
