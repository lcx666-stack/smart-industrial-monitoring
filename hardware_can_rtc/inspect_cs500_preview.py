#!/usr/bin/env python3
"""Summarize an acquired CS500 preview without altering the image."""

import argparse
from PIL import Image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("png")
    args = parser.parse_args()
    image = Image.open(args.png).convert("RGB")
    width, height = image.size
    print(f"size={width}x{height}")
    for y in (0, 100, 300, 500, 700, 900, height - 1):
        values = [image.getpixel((x, y)) for x in range(width)]
        means = tuple(round(sum(rgb[c] for rgb in values) / width, 1) for c in range(3))
        print(f"row {y}: mean RGB={means}")
    for x in (0, 100, 1000, 1715, 1716, 1717, 1718, 1719, 1720, 1721, 1800, width - 1):
        values = [image.getpixel((x, y)) for y in range(height)]
        means = tuple(round(sum(rgb[c] for rgb in values) / height, 1) for c in range(3))
        print(f"col {x}: mean RGB={means}")


if __name__ == "__main__":
    main()
