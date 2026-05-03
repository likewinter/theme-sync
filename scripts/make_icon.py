#!/usr/bin/env python3
import os
import struct
import zlib

BUILD_DIR = "build"
ICONSET_DIR = os.path.join(BUILD_DIR, "AppIcon.iconset")
ICON_BASE = os.path.join(BUILD_DIR, "AppIconBase.png")
ICON_ICNS = os.path.join(BUILD_DIR, "ThemeSync.icns")

BG = (245, 245, 245, 0)
DARK = (47, 47, 47, 255)
LIGHT = (220, 220, 220, 255)

ICONSET_FILES = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

ICNS_ENTRIES = [
    (b"icp4", 16),
    (b"icp5", 32),
    (b"icp6", 64),
    (b"ic07", 128),
    (b"ic08", 256),
    (b"ic09", 512),
    (b"ic10", 1024),
]


def make_pixels(width, height):
    rows = []
    cx = width / 2
    cy = height / 2
    radius = width * 0.41015625
    radius_squared = radius * radius

    for y in range(height):
        row = bytearray()
        for x in range(width):
            dx = x + 0.5 - cx
            dy = y + 0.5 - cy
            if dx * dx + dy * dy <= radius_squared:
                color = DARK if x < cx else LIGHT
            else:
                color = BG
            row.extend(color)
        rows.append(row)
    return rows


def png_bytes(width, height):
    raw = bytearray()
    for row in make_pixels(width, height):
        raw.append(0)  # no filter
        raw.extend(row)

    compressed = zlib.compress(bytes(raw), level=9)

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", compressed)
        + chunk(b"IEND", b"")
    )


def write_png(path, width, height):
    with open(path, "wb") as f:
        f.write(png_bytes(width, height))


def write_icns(path):
    elements = []
    for icon_type, size in ICNS_ENTRIES:
        png = png_bytes(size, size)
        elements.append(icon_type + struct.pack(">I", len(png) + 8) + png)

    body = b"".join(elements)
    with open(path, "wb") as f:
        f.write(b"icns" + struct.pack(">I", len(body) + 8) + body)


if __name__ == "__main__":
    os.makedirs(BUILD_DIR, exist_ok=True)
    os.makedirs(ICONSET_DIR, exist_ok=True)

    write_png(ICON_BASE, 1024, 1024)
    for filename, size in ICONSET_FILES:
        write_png(os.path.join(ICONSET_DIR, filename), size, size)
    write_icns(ICON_ICNS)
