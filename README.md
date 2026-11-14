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
itself fetches `/morseboy1.gbc`, writes it to the emulator's virtual FS at
`/data/games/`, and calls `loadGame()`.

### Local development

`make web` runs `web/server.mjs`, a dependency-free Node server that serves
the built ROM plus the WASM core with the required COOP/COEP headers.
This is the fastest way to iterate.

### Static deployment (git-pages / Codeberg Pages)

`make site` assembles a deployable static site in `web/_site/`:

```
web/_site/
  index.html      the page
  mgba.js         mGBA WASM glue (from node_modules)
  mgba.wasm       mGBA WASM core (~1.9 MB)
  morseboy1.gbc   the built ROM
  _headers        COOP/COEP for every response (Netlify-style, parsed by git-pages)
```

Deploy it to any [git-pages](https://git-pages.org) server — Codeberg's
`codeberg.page` or one you run yourself in front of this Gitea instance:

- **Gitea Actions** (this repo): `.gitea/workflows/pages.yaml` builds the
  ROM, runs the headless smoke test, and uploads the site with `git-pages-cli`
  to `https://opencode-bot.pages.zoltanlabs.ca/` (hardcoded in the workflow's
  `env:` block — the one place to change the URL). Set in the repo's Actions
  settings: secret `PAGES_TOKEN` (a token the git-pages server can verify
  against the forge, belonging to the account the subdomain maps to). Push
  to `main`. Without `PAGES_TOKEN` the workflow only builds and uploads the
  site as an artifact. If the subdomain has no TLS certificate yet, add
  `--server pages.zoltanlabs.ca` to the CLI invocation (the CLI can't request
  a first-time HTTPS publish on a bare site URL).
- **Codeberg Pages** instead: push the site to the `pages` branch and add a
  `git-pages` webhook, or use the [git-pages Forgejo/Gitea
  action](https://codeberg.org/git-pages/action).
- **Self-hosting git-pages**: add the two headers to the allowlist, since
  custom headers are denied by default (`config.toml`):

  ```toml
  [limits]
  allowed-custom-headers = ["Cross-Origin-Opener-Policy", "Cross-Origin-Embedder-Policy"]
  ```

## Extending

- Add a bank: bump `0x0148`, add `ROMX` placement in `linker/script.ld`, and
  switch banks via `$FF00` (requires an MBC cartridge type at `0x0147`).
- Sprites: OAM starts at $FE00; OBJ palettes 8-15 via `OCP` on CGB.
- Audio: NR channels at $FF10-$FF13 (DMG+), or the GBA-style APU is not
  available — keep it classic.
