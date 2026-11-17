#!/usr/bin/env python3
"""
fix_header.py — complete the DMG header of a GBDK-built ROM (in place).

GBDK-2020 links the correct 48-byte Nintendo logo and its own checksums,
but leaves the title empty and stores the global checksum big-endian,
which is not what standard tooling (rgbfix) expects. This patches:

  * Nintendo logo at 0x104..0x133 (48 bytes, idempotent)
  * title (11 chars, null-padded) at 0x134..0x142
  * CGB flag 0x00 at 0x143 (DMG-only)
  * header checksum at 0x14D   (rgbfix formula: -sum(0x134..0x14C) - 25)
  * global checksum at 0x14E..0x14F (little-endian, whole image except
    those two bytes)

The file size is never changed.

Usage:
  .venv/bin/python tools/fix_header.py [rom.gb] [title]
"""

import sys
from pathlib import Path

ROM = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("build/morseboy1.gb")
TITLE = (sys.argv[2] if len(sys.argv) > 2 else "morseboy1").encode("ascii")[:11]

# 48-byte Nintendo logo, byte-identical to the one rgbfix writes
# (rgbds src/fix/main.cpp nintendoLogo[]).
LOGO = bytes([
    0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B, 0x03, 0x73, 0x00, 0x83,
    0x00, 0x0C, 0x00, 0x0D, 0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E,
    0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99, 0xBB, 0xBB, 0x67, 0x63,
    0x6E, 0x0E, 0xEC, 0xCC, 0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E,
])

data = bytearray(ROM.read_bytes())
assert len(data) >= 0x150, f"ROM too small: {len(data)} bytes"

data[0x104:0x134] = LOGO
data[0x134:0x143] = TITLE.ljust(15, b"\x00")  # 15-byte region, exact width
data[0x143] = 0x00  # DMG-only

# Header checksum (rgbfix formula): sum starts at 0, sum -= byte + 1 for
# each of 0x134..0x14C.
hc = 0
for i in range(0x134, 0x14D):
    hc = (hc - data[i] - 1) & 0xFF
data[0x14D] = hc

# Global checksum: whole image except 0x14E-0x14F, stored little-endian.
gc = (sum(data[0x000:0x14E]) + sum(data[0x150:])) & 0xFFFF
data[0x14E] = gc & 0xFF
data[0x14F] = (gc >> 8) & 0xFF

ROM.write_bytes(bytes(data))
print(f"fix_header: logo OK, title {TITLE!r}, flag 0x00, "
      f"header sum 0x{hc:02x}, global 0x{gc:04x} (LE) -> {ROM}")
