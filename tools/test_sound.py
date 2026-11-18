#!/usr/bin/env python3
"""
test_sound.py — verify the Morse keyer tone headlessly with PyBoy.

Usage:
  .venv/bin/python tools/test_sound.py [rom.gb]

Boots the ROM, then:
  1. asserts the audio buffer is silent with no key held,
  2. holds button A for ~1.5 s and asserts a tone is present and its
     frequency is near 500 Hz,
  3. releases A and asserts the audio buffer is silent again,
  4. re-presses A and asserts the tone comes back (re-trigger works),
  5. navigates Start (SOS -> menu), A (menu -> reference, letter "A"),
  6. presses Start on the reference screen and asserts the Morse code
     of "A" (".-", 36 frames) is heard: tone bursts with silent gaps
     between the elements, then silence after the string finishes.

Exits 0 on success, 1 on failure.
"""

import sys
from pathlib import Path

import numpy as np
import pyboy

ROM_PATH = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("build/morseboy1.gb")

PALETTE = (0x000000, 0x333333, 0x999999, 0xFFFFFF)

EXPECTED_HZ = 500.0
HZ_TOLERANCE = 0.05  # allow +/-5%

pb = pyboy.PyBoy(
    str(ROM_PATH),
    window="null",
    cgb=False,
    color_palette=PALETTE,
    sound_emulated=True,
)


def collect(frames):
    """Tick `frames` frames and return the mono (left) samples as int8."""
    return np.concatenate(collect_frames(frames))


def collect_frames(frames):
    """Tick `frames` frames; return one mono (left) int8 array per frame."""
    buf = pb.sound.raw_buffer  # stereo-interleaved int8
    out = []
    for _ in range(frames):
        pb.tick(1)
        head = pb.sound.raw_buffer_head
        s = np.frombuffer(bytes(buf[:head]), dtype=np.int8)
        out.append(s[0::2])  # drop the right channel
    return out


def peak(samples):
    return int(np.max(np.abs(samples))) if samples.size else 0


def frequency_hz(samples, rate):
    """Zero-crossing estimate of the dominant tone frequency."""
    s = samples - np.mean(samples)
    sign = np.sign(s)
    # ignore runs of zeros at the edges
    crossings = int(np.count_nonzero(sign[:-1] * sign[1:] < 0))
    seconds = samples.size / rate
    return crossings / 2 / seconds if seconds > 0 else 0.0


def check(name, ok, detail=""):
    print(f"  {'ok ' if ok else 'FAIL'} {name}" + (f" — {detail}" if detail else ""))
    if not ok:
        sys.exit(1)


rate = pb.sound.sample_rate
print(f"PyBoy sound: {rate} Hz, buffer format {pb.sound.raw_buffer_format}")

# Let boot + logo settle.
pb.tick(60)

# 1. Silent while A is not held.
s_idle = collect(40)
check("silent with no key", peak(s_idle) == 0, f"peak={peak(s_idle)}")

# 2. Holding A plays a ~500 Hz tone.
pb.button_press("A")
s_held = collect(90)  # ~1.5 s
p = peak(s_held)
check("tone while A held", p > 0, f"peak={p}")
hz = frequency_hz(s_held, rate)
check(
    "tone ~500 Hz",
    abs(hz - EXPECTED_HZ) / EXPECTED_HZ < HZ_TOLERANCE,
    f"measured {hz:.1f} Hz",
)

# 3. Releasing A stops the tone. Allow a few frames for the release event
# to reach the ROM and for the ROM to power the APU off.
pb.button_release("A")
pb.tick(3)  # flush event propagation + ROM polling latency
s_off = collect(40)
check("silent after A released", peak(s_off) == 0, f"peak={peak(s_off)}")

# 4. Pressing A again sounds the tone again (re-trigger works).
pb.button_press("A")
pb.tick(3)  # same latency allowance, the other way around
s_held2 = collect(30)
p2 = peak(s_held2)
check("tone again on re-press", p2 > 0, f"peak={p2}")

# 5. Navigate to the reference screen (letter "A" at boot): Start goes
# SOS -> menu, A goes menu -> reference. A is released right after
# each press so the keyer tone doesn't mask the checks.
pb.button_release("A")
pb.tick(3)
pb.button_press("START")
pb.tick(6)
pb.button_release("START")
pb.tick(6)
pb.button_press("A")
pb.tick(6)
pb.button_release("A")
pb.tick(18)  # release latency + A debounce window (12 frames) elapses
s_ref = collect(10)
check("silent on reference screen", peak(s_ref) == 0, f"peak={peak(s_ref)}")

# 6. Start plays the Morse of the current letter ("A" -> ".-": 6f dot,
# 6f gap, 18f dash, 6f gap = 36 frames). Expect tone bursts, silent gap
# frames, and silence at the end of the window (playback done, APU off).
pb.button_press("START")
pb.tick(3)  # press propagation + ROM polling latency
pb.button_release("START")
play_frames = collect_frames(45)
p3 = peak(np.concatenate(play_frames))
check("tone while Start plays the letter", p3 > 0, f"peak={p3}")
silent = sum(1 for f in play_frames if f.size and peak(f) == 0)
check(
    "gaps between elements (intermittent tone)",
    silent >= 4,
    f"{silent} silent frames in 45",
)
tail = np.concatenate(play_frames[-3:])
check("silent after the letter finished", peak(tail) == 0, f"peak={peak(tail)}")

pb.stop()
print("sound test passed")
