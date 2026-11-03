#!/usr/bin/env python3
"""Preview a candidate 1920x1080 CS500 ISP frame, without modifying the raw.

The vendor ISP emits four little-endian 32-bit pixels per 128-bit word. Its
32-bit pixel is {zero, R, G, B}, so memory byte order is B,G,R,zero. The first
board frame still needs visual inspection before the layout is certified.
"""
import argparse
from pathlib import Path

from PIL import Image


WIDTH = 1920
HEIGHT = 1080
FRAME_BYTES = WIDTH * HEIGHT * 4


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("raw", type=Path)
    parser.add_argument("png", type=Path)
    args = parser.parse_args()
    if args.png.exists():
        parser.error(f"refusing to overwrite {args.png}")
    pixels = args.raw.read_bytes()
    if len(pixels) != FRAME_BYTES:
        parser.error(f"expected {FRAME_BYTES} bytes, got {len(pixels)}")
    image = Image.frombytes("RGB", (WIDTH, HEIGHT), pixels, "raw", "BGRX")
    image.save(args.png)
    print(f"Saved candidate preview {args.png}; inspect for channel order and frame alignment")


if __name__ == "__main__":
    main()
