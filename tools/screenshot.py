#!/usr/bin/env python3
"""
screenshot.py — render the ROM headlessly with PyBoy and save a PNG frame.

Usage:
  .venv/bin/python tools/screenshot.py [rom.gb] [out.png] [frames]

Defaults: build/morseboy1.gb -> build/morseboy1_frame.png, ~100 frames
(long enough to get past the ~64-frame DMG boot logo).
"""

import sys
from pathlib import Path

import pyboy

ROM_PATH = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("build/morseboy1.gb")
OUT_PATH = Path(sys.argv[2]) if len(sys.argv) > 2 else ROM_PATH.with_name(ROM_PATH.stem + "_frame.png")
FRAMES = int(sys.argv[3]) if len(sys.argv) > 3 else 100

# DMG shade order, matching the ROM's BGP mapping: palette index 0 is the
# brightest shade (DMG_WHITE = 0) and index 3 the darkest (DMG_BLACK = 3),
# so frames show a bright background with dark glyphs, as on real hardware.
PALETTE = (0xFFFFFF, 0x999999, 0x333333, 0x000000)

pb = pyboy.PyBoy(
    str(ROM_PATH),
    window="null",
    cgb=False,
    color_palette=PALETTE,
    sound_emulated=False,
)

ok = pb.tick(FRAMES)
if not ok:
    print(f"emulation stopped after {FRAMES} frames")
    sys.exit(1)

# PyBoy 2.9 headless: the internal Screen object still renders the
# framebuffer; grab the PIL image from it.
img = pb.screen.image
img.save(OUT_PATH)
print(f"saved {img.size[0]}x{img.size[1]} screenshot -> {OUT_PATH}")
