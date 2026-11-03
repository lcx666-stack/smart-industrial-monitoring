"""Receive only board-generated RGB frames and detection boxes."""

import struct


WIDTH, HEIGHT = 960, 540
IMAGE_BYTES = WIDTH * HEIGHT * 3
HEADER = struct.Struct("<4sIHHIIH")
BOX = struct.Struct("<HHHHH")


def receive_exact(connection, count):
    data = bytearray(count)
    view = memoryview(data)
    position = 0
    while position < count:
        received = connection.recv_into(view[position:])
        if received == 0:
            raise ConnectionError("board video connection closed")
        position += received
    return data


def read_packet(connection):
    magic, sequence, width, height, image_size, infer_sequence, count = HEADER.unpack(
        receive_exact(connection, HEADER.size))
    if (magic, width, height, image_size) != (b"CSNB", WIDTH, HEIGHT, IMAGE_BYTES):
        raise ValueError("unexpected board video packet")
    if not (1 <= infer_sequence <= sequence and 0 <= count <= 64):
        raise ValueError("invalid board inference metadata")
    rgb = receive_exact(connection, image_size)
    records = receive_exact(connection, count * BOX.size)
    boxes = []
    for offset in range(0, len(records), BOX.size):
        x1, y1, x2, y2, score = BOX.unpack_from(records, offset)
        if not (0 <= x1 < x2 <= WIDTH and 0 <= y1 < y2 <= HEIGHT and score <= 1000):
            raise ValueError("invalid board bounding box")
        boxes.append((x1, y1, x2, y2, score))
    return sequence, infer_sequence, rgb, boxes
