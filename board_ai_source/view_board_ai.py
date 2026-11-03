"""Display board-originated CS500 RGB frames and NPU boxes; never infer on PC."""

from __future__ import annotations

import argparse
import queue
import socket
import struct
import threading
import tkinter as tk

from PIL import Image, ImageDraw, ImageTk


HEADER = struct.Struct("<4sIHHIIH")
BOX = struct.Struct("<HHHHH")
WIDTH, HEIGHT = 960, 540
IMAGE_BYTES = WIDTH * HEIGHT * 3
MAX_BOXES = 64


def receive_exact(connection: socket.socket, count: int) -> bytearray:
    data = bytearray(count)
    view = memoryview(data)
    position = 0
    while position < count:
        received = connection.recv_into(view[position:])
        if received == 0:
            raise ConnectionError("Board disconnected")
        position += received
    return data


def read_packet(connection: socket.socket):
    magic, sequence, width, height, image_size, infer_sequence, count = HEADER.unpack(
        receive_exact(connection, HEADER.size)
    )
    if (magic, width, height, image_size) != (b"CSNB", WIDTH, HEIGHT, IMAGE_BYTES):
        raise ValueError("Not a board-NPU preview packet")
    if not (1 <= infer_sequence <= sequence and 0 <= count <= MAX_BOXES):
        raise ValueError("Invalid inference metadata")
    image = receive_exact(connection, image_size)
    records = receive_exact(connection, count * BOX.size)
    boxes = []
    for offset in range(0, len(records), BOX.size):
        x1, y1, x2, y2, score = BOX.unpack_from(records, offset)
        if not (0 <= x1 < x2 <= WIDTH and 0 <= y1 < y2 <= HEIGHT and score <= 1000):
            raise ValueError("Invalid board bounding box")
        boxes.append((x1, y1, x2, y2, score))
    return sequence, infer_sequence, image, boxes


def replace_latest(items: queue.Queue, item) -> None:
    try:
        items.put_nowait(item)
    except queue.Full:
        try:
            items.get_nowait()
        except queue.Empty:
            pass
        items.put_nowait(item)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="192.168.0.50")
    parser.add_argument("--port", type=int, default=5000)
    args = parser.parse_args()

    frames: queue.Queue = queue.Queue(maxsize=1)
    events: queue.Queue = queue.Queue()
    stop = threading.Event()
    root = tk.Tk()
    root.title("CS500 board NPU preview — motor 12 V disconnected")
    canvas = tk.Canvas(root, width=WIDTH, height=HEIGHT, bg="black", highlightthickness=0)
    canvas.pack()
    image_item = canvas.create_image(0, 0, anchor=tk.NW)
    status = tk.StringVar(value=f"Connecting to {args.host}:{args.port}")
    tk.Label(root, textvariable=status).pack()
    tk.Label(root, text="Boxes are experimental; PC only displays board results. No motor control.").pack()

    def receive() -> None:
        try:
            with socket.create_connection((args.host, args.port), timeout=5) as connection:
                connection.settimeout(10)
                events.put("Connected; waiting for board inference")
                previous_sequence = 0
                while not stop.is_set():
                    packet = read_packet(connection)
                    if packet[0] != previous_sequence + 1:
                        raise ValueError("Missing or out-of-order board frame")
                    previous_sequence = packet[0]
                    replace_latest(frames, packet)
        except (OSError, ConnectionError, ValueError) as error:
            events.put(str(error))

    threading.Thread(target=receive, daemon=True).start()

    def refresh() -> None:
        try:
            while True:
                status.set(events.get_nowait())
        except queue.Empty:
            pass
        try:
            sequence, infer_sequence, payload, boxes = frames.get_nowait()
        except queue.Empty:
            pass
        else:
            frame = Image.frombytes("RGB", (WIDTH, HEIGHT), payload)
            draw = ImageDraw.Draw(frame)
            for x1, y1, x2, y2, score in boxes:
                draw.rectangle((x1, y1, x2, y2), outline="#00ff78", width=3)
                draw.text((x1, max(0, y1 - 16)), f"blade_defect {score / 10:.1f}%", fill="#00ff78")
            photo = ImageTk.PhotoImage(frame)
            canvas.itemconfigure(image_item, image=photo)
            canvas.image = photo
            status.set(f"Frame {sequence} | NPU result {infer_sequence} | "
                       f"box age {sequence - infer_sequence} frames | {len(boxes)} boxes")
        if not stop.is_set():
            root.after(30, refresh)

    def close() -> None:
        stop.set()
        root.destroy()

    root.protocol("WM_DELETE_WINDOW", close)
    root.after(30, refresh)
    root.mainloop()


if __name__ == "__main__":
    main()
