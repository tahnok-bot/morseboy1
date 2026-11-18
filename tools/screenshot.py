#!/usr/bin/env python3
"""
screenshot.py — render the ROM headlessly with PyBoy and save one PNG per
screen, driving the real UI with joypad input.

Usage:
  .venv/bin/python tools/screenshot.py [rom.gb] [out_dir]

Defaults: build/morseboy1.gb -> screenshots/
Outputs (names prefixed with the ROM stem, e.g. morseboy1):
  _welcome.png  SOS launch screen, as drawn by the ROM at start
  _menu.png     main menu (Start from welcome)
  _quiz.png     quiz screen (menu -> quiz, A)
  _ref_a.png    reference screen, letter A (menu -> ref, A; letter A only
                for now — left/right cycling exists but is not exercised)

Timing notes:
  - PyBoy 2.x runs its built-in boot ROM first (~80 frames, a "PyBoy"
    logo); the cartridge starts when it ends and draws the SOS screen.
    The welcome screen is therefore detected via the tile map (the SOS
    text at rows 5-6) rather than a fixed frame count.
  - A/Start/B action presses are debounced in the ROM (KEY_DEBOUNCE in
    src/main.c: the button must read as released for 12 frames before a
    press edge is accepted), so every tap below waits that window out
    after releasing.
"""

import sys
from pathlib import Path

import pyboy

ROM_PATH = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("build/morseboy1.gb")
OUT_DIR = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("screenshots")
STEM = ROM_PATH.stem

# Must stay in sync with KEY_DEBOUNCE in src/main.c.
KEY_DEBOUNCE = 12

# SOS welcome screen text: "s   o   s" (row 5) and "... --- ..." (row 6)
# in the 20x18 tile map — see draw_sos() in src/main.c.
SOS_TILEMAP_START = 0x9800 + 5 * 32
SOS_TILEMAP_END = 0x9800 + 7 * 32

# Upper bound for boot-rom wait, so a ROM change cannot hang the script.
BOOT_WAIT_LIMIT = 300

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
mem = pb.memory


def tick(frames):
    if not pb.tick(frames):
        print(f"emulation stopped after {frames} frames", file=sys.stderr)
        sys.exit(1)


def tap(name, hold=2):
    """Tap a button: hold it `hold` frames, release, then wait out the ROM's
    debounce window (plus the release frame) so the next action press
    registers. pyboy.button() keeps the button down for `hold` ticks and
    releases it on the following tick."""
    pb.button(name, delay=hold)
    tick(hold + 1 + KEY_DEBOUNCE)


def save(name):
    # PyBoy 2.x headless: the internal Screen object still renders the
    # framebuffer; grab the PIL image from it.
    img = pb.screen.image
    path = OUT_DIR / f"{STEM}_{name}.png"
    img.save(path)
    print(f"saved {img.size[0]}x{img.size[1]} {name} -> {path}")


def welcome_drawn():
    """The SOS text occupies tile-map rows 5-6 once the ROM has started."""
    return any(mem[SOS_TILEMAP_START:SOS_TILEMAP_END])


OUT_DIR.mkdir(parents=True, exist_ok=True)

# 1. Welcome (SOS) — wait out PyBoy's built-in boot ROM (logo frames),
# then tick one more frame so the ROM's own drawing is what gets rendered.
# Tick single frames so the rendered screen stays current.
for _ in range(BOOT_WAIT_LIMIT):
    tick(1)
    if welcome_drawn():
        break
else:
    print(f"SOS screen not drawn within {BOOT_WAIT_LIMIT} frames", file=sys.stderr)
    sys.exit(1)
tick(1)
save("welcome")

# 2. Menu — Start opens it from the welcome screen.
tap("start")
save("menu")

# 3. Quiz — menu selection is "ref" at first; move down to "quiz", press A.
tap("down")
tap("a")
save("quiz")

# 4. Reference, letter A — B back to the menu (selection stays on "quiz"),
# move up to "ref", press A. The letter index is 0 (A) at this point and
# left/right are never pressed, so the screen stays on A.
tap("b")
tap("up")
tap("a")
save("ref_a")
