"""Display RGB and boxes produced on the board. No PC-side inference."""

import argparse
import socket

import cv2
import numpy as np

from view_board_ai import HEIGHT, WIDTH, read_packet


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="192.168.0.50")
    parser.add_argument("--port", type=int, default=5000)
    args = parser.parse_args()
    title = "CS500 board NPU preview - motor 12 V disconnected"
    cv2.namedWindow(title, cv2.WINDOW_AUTOSIZE)
    previous_sequence = 0
    try:
        with socket.create_connection((args.host, args.port), timeout=5) as connection:
            connection.settimeout(10)
            print("Connected; receiving board-computed boxes", flush=True)
            while True:
                sequence, infer_sequence, rgb, boxes = read_packet(connection)
                if sequence != previous_sequence + 1:
                    raise ValueError("Missing or out-of-order board frame")
                previous_sequence = sequence
                frame = cv2.cvtColor(
                    np.frombuffer(rgb, dtype=np.uint8).reshape(HEIGHT, WIDTH, 3),
                    cv2.COLOR_RGB2BGR,
                )
                for x1, y1, x2, y2, score in boxes:
                    cv2.rectangle(frame, (x1, y1), (x2, y2), (120, 255, 0), 2)
                    cv2.putText(
                        frame,
                        f"blade_defect {score / 10:.1f}%",
                        (x1, max(15, y1 - 5)),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.55,
                        (120, 255, 0),
                        2,
                    )
                cv2.putText(
                    frame,
                    f"frame {sequence}  NPU {infer_sequence}  age {sequence - infer_sequence}  boxes {len(boxes)}",
                    (12, HEIGHT - 12),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.55,
                    (255, 255, 255),
                    1,
                )
                cv2.imshow(title, frame)
                if cv2.waitKey(1) in (27, ord("q")):
                    break
                if cv2.getWindowProperty(title, cv2.WND_PROP_VISIBLE) < 1:
                    break
    finally:
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
