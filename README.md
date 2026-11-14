# morseboy1

A tiny **Game Boy / Game Boy Color** starter project: single-bank 32 KB ROM,
written in SM83 assembly with [RGBDS](https://github.com/gbdev/rgbds), smoke-tested
with [mGBA headless](https://mgba.io/) natively and in the browser via
[mGBA WASM](https://github.com/thenick775/mgba/tree/feature/wasm).

The demo renders `HELLO GBC!` from BG tiles and, on CGB, cycles the background
color through a palette every 8 frames (on DMG it uses the classic `$E0` green).

## Quick start

Prereqs (all installed on this machine):

- `make`, and RGBDS 0.9.x (`rgbasm` / `rgblink` / `rgbfix`)
- `node` (v18+), for the web emulator
- `tools/mgba-headless` (prebuilt mGBA headless binary, already in `tools/`)

```sh
make            # build -> build/morseboy1.gbc
make test       # run the ROM 2 s in mGBA headless (exit 124 = ran fine)
make web        # build + serve the mGBA WASM web emulator on :8080
make clean      # remove build/
```

Open **http://localhost:8080** after `make web`.
Keys: `Z`/`X` = B/A, `Enter` = Start, `Shift` = Select, arrows = d-pad, `P` = pause.

## Layout

```
src/main.asm          the whole ROM (boot, header, reset, code, data, bss)
include/hardware.inc  GB devkit hardware registers (v6.0.0)
linker/script.ld      RGBDS 0.9.x linker script (ROM0/WRAM0 placement)
web/server.mjs        zero-dep dev server (COOP/COEP for mGBA-wasm threads)
web/index.html        browser UI wrapping the mGBA WASM core
build/                build/morseboy1.gbc  (final 32 KB ROM)
tools/mgba-headless   prebuilt mGBA headless smoke-test binary
```

## Build pipeline

1. `rgbasm -i include` — assemble `src/main.asm` -> `build/main.o`
2. `rgblink -t -l linker/script.ld` — link + place sections -> `build/morseboy1.raw`
3. `rgbfix -v -p 0` — pad to 32 KB, write the Nintendo logo (0x0104), compute the
   header checksum (0x014D) and ROM checksum (0x014E-F) -> `build/morseboy1.gbc`

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
0x0143         CGB flag: $80 = DMG+CGB, $C0 = CGB only
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

mGBA auto-detects the model from `cart->cgb & 0x80` (0x0143): with `$80` it
emulates a CGB, so the ROM runs in color. To force DMG mode (to test the
monochrome path):

```sh
tools/mgba-headless -C model=DMG build/morseboy1.gbc
```

## CGB palette notes

- CGB detection at runtime: write `0` to `KEY1` ($FF4D), read back — `$FE` on
  CGB, `$7E` on DMG.
- Palettes are set through the indirect `BCP`/`OCP` registers:
  `BCPS` $FF68, `BCPD` $FF69, `OCPS` $FF6A, `OCPD` $FF6B
  (palette number * 2 in `BCPS`/`OCPS`, 16-bit color as two `BCPD`/`OCPD`
  writes, low byte first). 16-bit color: 5 bits each, blue/green/red.
- DMG: the background palette is just `BGP` ($FF47), e.g. `$E0`.
- VBlank wait: poll `STAT` and mask **bit 3 ($08)** — the V-Blank flag.
  (`hardware.inc`'s `STAT_*` symbols are *bit-field encodings*, not register
  masks, so they can't be used directly as masks.)

## Web emulator

`web/server.mjs` is a dependency-free Node server. It serves:

- `/` — `web/index.html`
- `/mgba.js`, `/mgba.wasm` — the `@thenick775/mgba-wasm` core (v2.6.0)
- `/morseboy1.gbc` — the freshly built ROM

Every response carries `Cross-Origin-Opener-Policy: same-origin` and
`Cross-Origin-Embedder-Policy: require-corp` — required because the WASM core
uses Web Threads. The page fetches the ROM, writes it to the emulator's
virtual FS at `/data/games/`, and calls `loadGame()`.

## Extending

- Add a bank: bump `0x0148`, add `ROMX` placement in `linker/script.ld`, and
  switch banks via `$FF00` (requires an MBC cartridge type at `0x0147`).
- Sprites: OAM starts at $FE00; OBJ palettes 8-15 via `OCP` on CGB.
- Audio: NR channels at $FF10-$FF13 (DMG+), or the GBA-style APU is not
  available — keep it classic.
