# morseboy1

A tiny **Game Boy (DMG)** starter project: single-bank 32 KB ROM, written in
**C** with [GBDK-2020](https://github.com/gbdk-2020/gbdk-2020) (v4.5.0),
smoke-tested with [mGBA headless](https://mgba.io/) natively and in the
browser via [mGBA WASM](https://github.com/thenick775/mgba/tree/feature/wasm).

The ROM targets DMG only (CGB flag `$00` in the header, no CGB/palette code).
The start screen shows `s o s` with the Morse code `... --- ...` beneath it,
drawn with GBDK's built-in 8x8 console font (the stdio `printf` family).
Holding the A button sounds a ~500 Hz square-wave Morse keyer tone; the
tone lasts exactly as long as A is held (see [Sound](#sound)).

## Quick start

Prereqs (all installed on this machine):

- **GBDK-2020 4.5.0** at `~/gbdk-2020` (override with `GBDK_ROOT=/path`)
- `make`
- `node` (v18+), for the web emulator
- `tools/mgba-headless` (prebuilt mGBA headless binary, already in `tools/`)
- Python 3 venv for pixel checks: `make venv` (installs PyBoy + Pillow)

```sh
make            # build -> build/morseboy1.gb
make test       # run the ROM 2 s in mGBA headless (exit 124 = ran fine)
make check      # header assertion + smoke test + shell/js checks
make screenshot # PyBoy headless pixel capture -> build/morseboy1_frame.png
make web        # build + serve the mGBA WASM web emulator on :8080
make clean      # remove build/
```

Open **http://localhost:8080** after `make web`.
Keys: `Z`/`X` = B/A, `Enter` = Start, `Shift` = Select, arrows = d-pad, `P` = pause.

## Layout

```
src/main.c            the whole ROM (palette, font init, text, vsync loop)
tools/mgba-headless   prebuilt mGBA headless smoke-test binary
tools/fix_header.py   post-link DMG header completion (logo/title/checksums)
tools/check_header.py strict DMG header validation (make check)
tools/screenshot.py   headless PyBoy pixel capture -> build/morseboy1_frame.png
tools/test_sound.py   headless PyBoy audio check (silence/tone/frequency)
web/server.mjs        zero-dep dev server (COOP/COEP for mGBA-wasm threads)
web/index.html        browser UI wrapping the mGBA WASM core
build/                build/morseboy1.gb   (final 32 KB ROM)
```

## Build pipeline

1. `$(GBDK_ROOT)/bin/lcc -msm83:gb -o build/morseboy1.gb src/main.c`
   — compile and link the full ROM in one step: GBDK's CRT startup code,
   the stdio/console runtime, and the built-in IBM font are linked in
   automatically. (The platform flag selects sm83/GB; verified that the
   older `-Wa-l -Wl-m -Wl-j` extra only emitted a `.noi` symbol file and
   did not change the ROM bytes.)
2. `.venv/bin/python tools/fix_header.py build/morseboy1.gb morseboy1`
   — post-link header completion (this machine has no rgbfix; GBDK leaves
   part of the header to the user). Patches in place, size-preserving:
     - verifies/patches the 48-byte Nintendo logo at `0x104..0x133`
       (GBDK already links the correct one — byte-identical to rgbfix's)
     - writes the 11-char title `morseboy1` (null-padded) at `0x134`
     - sets the CGB flag at `0x143` to `0x00` (DMG-only)
     - recomputes the header checksum at `0x14D` using rgbfix's formula
       (`sum = 0; for i in 0x134..0x14C: sum -= byte + 1`)
     - recomputes the 16-bit global checksum at `0x14E..0x14F`,
       stored **little-endian** (GBDK stores it big-endian, which
       standard tooling does not expect)

The Game Boy BIOS only verifies the 48-byte logo at boot; the two checksums
are for host-side tooling, which is why step 2 mirrors rgbfix's exact
semantics.

## ROM map

```
0x0000-0x00FF  unused
0x0100-0x0102  jp 0x0150          (entry; GBDK crt0 starts here)
0x0104-0x0133  Nintendo logo (48 B)
0x0134-0x014F  cartridge header
0x0150-        GBDK crt0 / reset / init, then the linked main code
```

### Cartridge header (0x0134-0x014F)

The layout mGBA and rgbfix use — note the CGB flag is at 0x0143:

```
0x0134-0x0142  title (15 B region; 11-char DMG title, null-padded)
0x0143         CGB flag: $00 = DMG only (this ROM)
0x0144-0x0145  new licensee code
0x0146         SGB flag
0x0147         cartridge type ($00 = ROM only)
0x0148         ROM size ($00 = 32 KB)
0x0149         RAM size ($00 = none)
0x014A         destination code
0x014B         mask ROM version
0x014C         (unused)
0x014D         header checksum   (rgbfix formula, see pipeline)
0x014E-0x014F  ROM checksum      (16-bit, little-endian)
```

`make check-header` (via `tools/check_header.py`) asserts all of the above.

## Pixel verification

`tools/screenshot.py` runs the ROM headlessly in [PyBoy](https://pyboy.dev/)
(windowless, `cgb=False`) and saves `build/morseboy1_frame.png` after
100 frames:

```sh
.venv/bin/python tools/screenshot.py        # build/morseboy1.gb -> build/morseboy1_frame.png
```

The expected frame is a bright field with `s   o   s` at character row 5
(letters at columns 5, 9, 13) and the Morse code `... --- ...` at row 6
(centered under the letters).

The palette maps DMG shades in hardware order — index 0 (the lightest,
`DMG_WHITE`) to `0xFFFFFF` and index 3 (the darkest, `DMG_BLACK`) to
`0x000000` — so the PNG matches what real hardware shows: dark glyphs on a
bright background.

### Tile format (verified: DMG is 16 bytes per tile)

Game Boy background tiles are **16 bytes per 8x8 tile — two bytes per row,
low bitplane then high bitplane** — on both DMG and CGB hardware. Pixel
color id for column x of a row = `((hi >> (7-x)) & 1) << 1 | ((lo >> (7-x)) & 1)`,
looked up in `BGP`. This was confirmed across all three authorities this
project is validated against:

- **PyBoy v2.9.0** (`core/lcd.py`): `_dot_tiledat_addr` uses a `0x10`
  (16-byte) tile stride and `row * 2` row offset, both bitplane bytes.
- **mGBA** (software renderer, all models including DMG):
  `tileDataLower = data[(tile*8 + y)*2]`, `tileDataUpper = data[... + 1]`.
- Pan Docs / GB hardware documentation.

There is **no** DMG "8 bytes per tile" fetch mode; the old note about a
PyBoy DMG tile-fetch discrepancy came from confusing the 1bpp *export*
convention (8 bytes of glyph source) with the on-VRAM tile layout.
GBDK's built-in font ships glyphs as 8-byte 1bpp source, and its font
runtime expands them into the 16-byte VRAM format at load time — so
`printf("hi hi")` needs no manual tile conversion.

## DMG notes

- The ROM is DMG-only: CGB flag `$00` at 0x0143 and no CGB registers in the
  code (no `KEY1` detection, no `BCP`/`OCP` palette writes, no VRAM bank 1).
- Background palette: `BGP_REG = DMG_PALETTE(WHITE, WHITE, DARK_GRAY, BLACK)`
  via `gb/gb.h` helpers. The IBM font's ink pixels use color id 3, so text
  is the darkest shade on a white field.
- Text output: GBDK-2020 stdio (`printf`/`putchar`) with `<gbdk/console.h>`
  (`cls`, `gotoxy`). The font is loaded lazily on the first console call —
  the source `putchar(' ')` does that before `cls()`. The IBM font uses an
  identity char-to-tile mapping (char `c` -> tile `c`), and tile 0 is blank,
  which is what `cls()` fills the map with.
- VBlank: `vsync()` (GBDK) handles the STAT bit-3 poll; no manual loop.

## Sound

`src/main.c` drives sound channel 1 (square wave) directly via the APU
registers — a ~500 Hz Morse keyer tone, sounded only while A is held:

- **Period** `d = 0x6FA` (NR13 = `$FA`, NR14 high bits `0b110`):
  `131072 / (2048 - d)` Hz, per the Pan docs. (The higher the period value,
  the higher the frequency.)
- **Powering the APU**: the sound registers are read-only until NR52 bit 7
  is set. `tone_on()` writes `NR52 = $80` first, then configures the
  channel; `tone_off()` writes `NR52 = $00`, which stops the channel
  immediately and clears its state for the next press.
- **Trigger**: the channel is enabled by writing NR14 with bit 7 set
  (`NR14 = $86`); NR52's per-channel "on" bits are read-only. With the
  length counter disabled (NR14 bit 6 = 0) the tone simply continues until
  the APU is powered off, so one trigger per key press is enough.
- **Volume/pan**: NR12 = `$F0` (constant full volume, no envelope),
  NR51 = `$11` (channel 1 to both speakers), NR50 = `$77` (master volume).

Headless verification with PyBoy (`tools/test_sound.py`):

```sh
.venv/bin/python tools/test_sound.py   # exits 0 only if all checks pass
```

Checks: silent with no key held; tone present and ~500 Hz (±5%) while A is
held; silent again after A is released; tone returns on re-press.

## Web emulator

The whole preview is static content — one HTML page, the
`@thenick775/mgba-wasm` core (v2.6.0), and the ROM. There is no server logic.
There is one hard requirement though: the page must be served with

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

because mGBA-wasm calls `new WebAssembly.Memory({ shared: true })` (Web
Threads), which only exists on *cross-origin isolated* pages. Without those
two headers the emulator throws on startup — `file://`, `python -m
http.server`, and any header-less static host all fail this way. The page
itself fetches `/morseboy1.gb`, writes it to the emulator's virtual FS at
`/data/games/`, and calls `loadGame()`.

### Local development

`make web` runs `web/server.mjs`, a dependency-free Node server that serves
the built ROM plus the WASM core with the required COOP/COEP headers.
This is the fastest way to iterate.

The page works without a keyboard: an on-screen d-pad, A/B, Start/Select
and Pause are mapped to the same mGBA button events as the keys, so it is
usable from a phone (multi-touch holds work — e.g. key A with one finger
while nudging the d-pad with another).

## Extending

- **More source files**: just add `.c` files to `CSOURCES` in the Makefile —
  lcc compiles and links them in one invocation.
- **Banks (MBC)**: pass makebin flags through lcc, e.g.
  `lcc -msm83:gb -Wl-yt0x1A -Wl-yo4 ...` (MBC5, 4 ROM banks), or use
  GBDK's `-autobank` with `#pragma bank` / `BANKREF` for automatic placement.
  (Single-bank 32 KB needs nothing.)
- **Sprites**: OAM starts at $FE00; GBDK provides `set_sprite_data`,
  `set_sprite_pos`, OBJ palette via `OBP0`/`OBP1`.
- **Tiles/images**: `set_bg_tile_data` + `fill_bg_char` (see the `images`
  GBDK example); exported 1bpp 8-byte-per-tile art is fine as *source*,
  GBDK's helpers place it into 16-byte VRAM tiles.
- **Audio**: the keyer in `src/main.c` is the reference for the DMG APU
  power-on/trigger sequence; NR10-NR14 (channel 1) at $FF10-$FF14, master
  volume/pan at $FF20-$FF21, power at $FF22. The GBDK sound API
  (`gbdk/sound.h`) is an alternative for simple effects.
