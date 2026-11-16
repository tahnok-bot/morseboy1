# morseboy1

A tiny **Game Boy (DMG)** starter project: single-bank 32 KB ROM, written in
SM83 assembly with [RGBDS](https://github.com/gbdev/rgbds), smoke-tested with
[mGBA headless](https://mgba.io/) natively and in the browser via
[mGBA WASM](https://github.com/thenick775/mgba/tree/feature/wasm).

The ROM targets DMG only (CGB flag `$00` in the header, no CGB/palette code)
and renders `HELLO GBC!` from BG tiles in the classic `$E0` green palette.

## Quick start

Prereqs (all installed on this machine):

- `make`, and RGBDS ≥ 0.9.4 (`rgbasm` / `rgblink` / `rgbfix`; this machine has 1.0.4)
- `node` (v18+), for the web emulator
- `tools/mgba-headless` (prebuilt mGBA headless binary, already in `tools/`)

```sh
make            # build -> build/morseboy1.gb
make test       # run the ROM 2 s in mGBA headless (exit 124 = ran fine)
make check      # strict diagnostics + header assertion + smoke test
make web        # build + serve the mGBA WASM web emulator on :8080
make clean      # remove build/
```

Open **http://localhost:8080** after `make web`.
Keys: `Z`/`X` = B/A, `Enter` = Start, `Shift` = Select, arrows = d-pad, `P` = pause.

## Layout

```
src/main.asm          the whole ROM (boot, header, reset, code, data)
include/hardware.inc  GB devkit hardware registers (v6.0.0)
linker/script.ld      RGBDS 0.9.x linker script (ROM0/WRAM0 placement)
web/server.mjs        zero-dep dev server (COOP/COEP for mGBA-wasm threads)
web/index.html        browser UI wrapping the mGBA WASM core
build/                build/morseboy1.gb   (final 32 KB ROM)
tools/mgba-headless   prebuilt mGBA headless smoke-test binary
```

## Build pipeline

1. `rgbasm -i include` — assemble `src/main.asm` -> `build/main.o`
   (with `-Weverything -Wtruncation=1`; the build fails on any warning)
2. `rgblink -Weverything -Wtruncation=1 -d -t -l linker/script.ld` — link +
   place sections in **DMG mode** (strict: fails on any warning,
   guarantees no CGB-only memory is used) -> `build/morseboy1.raw`
3. `rgbfix -Weverything -v -m ROM -p 0` — pad to 32 KB, write the Nintendo logo (0x0104),
   compute the header checksum (0x014D) and ROM checksum (0x014E-F), and pin the
   cartridge type to ROM-only -> `build/morseboy1.gb`

## ROM map

```
0x0000-0x00FF  unused
0x0100-0x0102  jp 0x0150          (entry; the boot code starts here)
0x0104-0x0133  Nintendo logo (48 B)
0x0134-0x014F  cartridge header
0x0150-        reset / init / main loop
```

### Cartridge header (0x0134-0x014F)

This is the layout mGBA and rgbfix actually use — note the CGB flag shares the
title's 16th byte at 0x0143, and the type byte is at 0x0147:

```
0x0134-0x0143  title (16 B; last byte = CGB flag)
0x013F-0x0142  game ID ("MB01")
0x0143         CGB flag: $00 = DMG only (this ROM)
0x0144-0x0145  new licensee code ($33 $80)
0x0146         SGB flag
0x0147         cartridge type ($00 = ROM only)
0x0148         ROM size ($00 = 32 KB)
0x0149         RAM size ($00 = none)
0x014A         destination code ($01 = not Japan)
0x014B         old licensee code ($33 = Nintendo)
0x014C         version
0x014D         header checksum   (rgbfix)
0x014E-0x014F  ROM checksum      (rgbfix)
```

## DMG notes

- The ROM is DMG-only: CGB flag `$00` at 0x0143, and the code uses no CGB
  registers (no `KEY1` detection, no `BCP`/`OCP` palette writes, no VRAM
  bank 1). `rgblink -d` in the build enforces this.
- The background palette is just `BGP` ($FF47); the ROM writes the classic
  `$E0` green.
- VBlank wait: poll `STAT` and mask **bit 3 ($08)** — the V-Blank flag.
  (`hardware.inc`'s `STAT_*` symbols are *bit-field encodings*, not register
  masks, so they can't be used directly as masks.)

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

## Extending

- Add a bank: bump `0x0148`, add `ROMX` placement in `linker/script.ld`, and
  switch banks via `$FF00` (requires an MBC cartridge type at `0x0147`).
- Sprites: OAM starts at $FE00; OBJ colors come from `OBP0`/`OBP1` ($FF48/$FF49).
- Audio: NR channels at $FF10-$FF13 (DMG+), or the GBA-style APU is not
  available — keep it classic.
