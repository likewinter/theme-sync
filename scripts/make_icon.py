#!/usr/bin/env python3
import struct
import zlib

WIDTH = 1024
HEIGHT = 1024

BG = (245, 245, 245)
DARK = (47, 47, 47)
LIGHT = (220, 220, 220)

CX = WIDTH // 2
CY = HEIGHT // 2
R = 420
R2 = R * R


def make_pixels():
    rows = []
    for y in range(HEIGHT):
        row = bytearray()
        for x in range(WIDTH):
            dx = x - CX
            dy = y - CY
            if dx * dx + dy * dy <= R2:
                color = DARK if x < CX else LIGHT
            else:
                color = BG
            row.extend(color)
        rows.append(row)
    return rows


def write_png(path):
    rows = make_pixels()

    raw = bytearray()
    for row in rows:
        raw.append(0)  # no filter
        raw.extend(row)

    compressed = zlib.compress(bytes(raw), level=9)

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data)) +
            tag +
            data +
            struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 2, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n" +
        chunk(b"IHDR", ihdr) +
        chunk(b"IDAT", compressed) +
        chunk(b"IEND", b"")
    )

    with open(path, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    write_png("build/AppIconBase.png")
