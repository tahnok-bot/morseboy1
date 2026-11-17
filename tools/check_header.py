#!/usr/bin/env python3
"""
check_header.py — validate the DMG ROM header of build/morseboy1.gb.

Checks (matching rgbfix / rgbds semantics):
  * 48-byte Nintendo logo at 0x104..0x133
  * CGB flag at 0x143 (0x00 = DMG-only)
  * header checksum at 0x14D  (rgbfix formula: -sum(0x134..0x14C) - 25)
  * 16-bit global checksum at 0x14E..0x14F (little-endian)

Usage:
  .venv/bin/python tools/check_header.py [rom.gb]
"""

import sys
from pathlib import Path

ROM = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("build/morseboy1.gb")

# 48-byte Nintendo logo, byte-identical to rgbfix's nintendoLogo[].
LOGO = bytes([
    0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B, 0x03, 0x73, 0x00, 0x83,
    0x00, 0x0C, 0x00, 0x0D, 0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E,
    0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99, 0xBB, 0xBB, 0x67, 0x63,
    0x6E, 0x0E, 0xEC, 0xCC, 0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E,
])

def fail(msg: str) -> None:
    print(f"check-header: {msg}", file=sys.stderr)
    sys.exit(1)

def main() -> None:
    if not ROM.exists():
        fail(f"ROM not found: {ROM} (run 'make')")

    data = ROM.read_bytes()
    if len(data) < 0x150:
        fail(f"ROM too small: {len(data)} bytes (need at least 0x150)")

    # --- Nintendo logo (48 bytes at 0x104..0x133) ---
    logo = data[0x104:0x134]
    if len(logo) < 48:
        fail("logo region truncated")
    if logo != LOGO:
        for i in range(48):
            if logo[i] != LOGO[i]:
                fail(f"Nintendo logo mismatch at 0x{0x104 + i:03x} "
                     f"(got 0x{logo[i]:02x}, want 0x{LOGO[i]:02x})")
                break
        fail("Nintendo logo mismatch")
    print("check-header: Nintendo logo OK (48 bytes)")

    # --- CGB flag (0x143): 0x00 = DMG-only ---
    if data[0x143] != 0x00:
        fail(f"CGB flag is 0x{data[0x143]:02x}, want 0x00 (DMG-only)")
    print("check-header: CGB flag 0x00 (DMG-only)")

    # --- Header checksum (0x14D) ---
    # rgbfix formula: sum = 0; for i in 0x134..0x14C: sum -= byte + 1
    hc = 0
    for i in range(0x134, 0x14D):
        hc = (hc - data[i] - 1) & 0xFF
    if data[0x14D] != hc:
        fail(f"header checksum 0x{data[0x14D]:02x} != 0x{hc:02x}")
    print(f"check-header: header checksum 0x{data[0x14D]:02x}")

    # --- Global checksum (0x14E..0x14F, little-endian) ---
    gc = (sum(data[0x000:0x14E]) + sum(data[0x150:])) & 0xFFFF
    stored = int.from_bytes(data[0x14E:0x150], "little")
    if stored != gc:
        fail(f"global checksum {stored:04x} != {gc:04x}")
    print(f"check-header: global checksum {gc:04x} (LE)")

    # --- Title (informational) ---
    title = data[0x134:0x143].split(b"\x00", 1)[0].decode("ascii", "replace")
    print(f"check-header: title = {title!r}")

    print("ROM header: OK")

if __name__ == "__main__":
    main()
