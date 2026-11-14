#!/usr/bin/env python3
## 32x32 ranked-bars HUD icon for the scoreboard toggle.
import struct
import zlib
from pathlib import Path

W, H = 32, 32
rows = []
for y in range(H):
    row = bytearray([0])  # PNG filter byte per scanline
    for x in range(W):
        if 8 <= x < 24 and 11 <= y < 21:
            if y in (12, 15, 18) and 10 <= x < 22:
                row.extend((255, 230, 130, 255))
            else:
                row.extend((42, 34, 56, 255))
        else:
            row.extend((0, 0, 0, 0))
    rows.append(bytes(row))

raw = b"".join(rows)
compressed = zlib.compress(raw, 9)


def chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", compressed)
png += chunk(b"IEND", b"")

out = Path(__file__).resolve().parents[2] / "assets/ui/hud/icon_scores.png"
out.write_bytes(png)
print(out)