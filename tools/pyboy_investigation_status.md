# PyBoy headless testing of morseboy1 — investigation status

_Last updated: after confirming mode-3 VRAM write drop; PPU tile-layout mystery still open. Investigation paused on user request._

## Goal

Make `tools/pyboy_test.py` a reliable headless test for the DMG ROM
(`build/morseboy1.gb`) covering: boot behavior, register state, VRAM/BG-map
contents, rendered pixels, hooks, and save/load. Find and fix why the
rendered-pixel and memory assertions fail after PyBoy's DMG boot ROM runs.

## Environment / how to run

```sh
cd /home/dev/.t3/projects/morseboy1
.venv/bin/python tools/pyboy_test.py
```

PyBoy 2.9.0 (compiled Cython extension; `pb.mb` NOT exposed at runtime).
Installed source files usable for reference:
`.venv/lib/python3.13/site-packages/pyboy/core/{mb,lcd}.py`, plus generated C.

## CONFIRMED root cause #1 — ROM bug: VRAM writes dropped in LCD mode 3 (SMOKING GUN)

PyBoy's compiled `mb.setitem` drops ALL VRAM writes (`0x8000..0x9FFF`, tile
data AND BG map) when `in_tick and not fast_mode and LCDC.lcd_enable and
STAT.mode == 3`. This is faithful DMG hardware behavior (VRAM unwritable while
the PPU scans out).

The ROM's `Init` (src/main.asm, at 0x0157) copies tiles + BG map immediately
after reset WITHOUT waiting for VBlank, so some writes land in mode-3 windows
and are silently lost — on real hardware too.

Empirical proof (clean run, no hooks, `pb.tick(100)`):

```
fast_mode=False: map row4 x5..14: [1, 0, 0, 0, 4, 0, 5, 6, 7, 0]   <- writes lost
                 tile 8 raw:        [32, 32,124,124,102, 0, 32, 0]
fast_mode=True : map row4 x5..14: [1, 2, 3, 3, 4, 0, 5, 6, 7, 8]   <- == ROM text_row exactly
                 tile 8 raw:        [32, 32, 32, 32, 32, 0, 32, 0] <- == ROM data exactly
```

ROM fix (to do): in `Init`, wait for VBlank before the two `copy_dir` calls
(e.g. poll STAT mode == 1 / LY >= 144), or turn LCD off first. Note:
`FrameLoop`'s "wait for VBlank" actually polls STAT bit 3 ($08, LYC flag) —
that's not a VBlank wait; it just idles.

## CONFIRMED test bugs in tools/pyboy_test.py (to fix)

- BGP register is `$FF47` (test used `0xFF27`). ROM does `ld [rBGP],a` -> 0xFF47 = 0xE0 after Init.
- Cartridge title starts at `0x0134` ("MORSEBOY1"), not 0x013D (that's the tail + game ID "MB01").
- Foreground color: with BGP=0xE0, palette mapping is p0->0(black), p1->0(black),
  p2->2(0x999999), p3->3(white). The test's `FG_COLOR = PALETTE[1]` expectation is
  wrong; observed rendered colors are only black/0x999999/white.
- LCDC=0x93 is valid (bit7 LCD on, bit4 block01, bit1 OBJ on, bit0 BG on). Keep.
- Boot ROM runs ~64 frames before game starts; wait >= 100 frames before asserting.
- save_state/load_state needs `state.seek(0)` (already fixed in test).

## OPEN mystery #2 — rendered pixels don't match any consistent tile model

Facts (all from clean no-hook runs, post-game frame 100 unless noted):

1. ROM tiles are standard DMG 8x8 1bpp packed, 8 bytes/tile:
   `tiles` at 0x018f, 9 tiles x 8 bytes = 72 bytes -> $8000..$8047.
   text_row `[1,2,3,3,4,0,5,6,7,8]` ("HELLO GBC!") -> $9885..$988E (row 4).
2. `pb.get_tile(t).data_address` = `$8000 + t*0x10` — PyBoy's tile API uses a
   16-byte stride (16x8 / 2-bit model), not the DMG 8-byte 1bpp layout.
3. Post-game screen: most of every 8-row tile row renders
   `.... / .... / .... / .... / W...W / WgggW / W...W / ....` (repeated per 8px)
   = exactly the 2-bit pair model on bytes ($8008,$8009)=($88,$F8):
   p=(b1bit<<1)|b0bit, bit7 first, BGP=0xE0 (p0,p1->black; p2->gray; p3->white).
   So the PPU appears to read 16x8-style (b0,b1) byte pairs from the packed region.
4. Controlled marker experiment (frame 100, LCD off during writes, readback
   verified `0x8000..0x800F = [0..15]`, row-0 map cleared to entry 0):
   rendered tile 0 at (0,0) is ALL p=3 (all white), matching NEITHER the pair
   model NOR the 1bpp model. A fresh-boot probe ($8000=0x80 only, BGP=0xFC)
   gave row0 = ".WWWWWWW" which also matches no consistent mapping.
5. `pb.get_tile(0).ndarray()` agrees with the screen (also shows the stale/odd
   contents), so both use the same internal view.
6. Python source says: `mb.setitem` VRAM writes call
   `lcd.renderer.invalidate_tile(((i & 0xFFF0) - 0x8000)//16, 0)` for tile data;
   `invalidate_tile` zeroes `_tilecache_state[tile]`; `update_tilecache` refills
   from `VRAM0[t*16 .. t*16+15]` (2 bytes/row); frame render happens in
   `lcd.tick` -> `renderer.render_frame()` (FastRenderer: update_background_view
   + copy_tilemap_scanline per row). GPU/CUDA path is inactive headless.
   Yet the rendered result after a Python-side write does not reflect the new
   VRAM0 contents. Possibilities: compiled .so differs from these .py sources,
   tilecache refill/invalidation race, or another internal buffer feeds the
   scanline path (dot-accurate fetcher around lcd.py lines 1750-2100, with
   `_dot_tiledat_addr` using `tile_index * 0x10`).

### Decisions made so far

- Prioritize ROM fixes + high-level API assertions over brute-force pixel
  reconstruction. Use `pb.tilemap_background()` and `pb.get_tile(t)` for
  map/tile validation; keep raw-pixel assertions minimal or derive expectations
  from post-fix behavior (golden-image style), cross-checked with mGBA.
- Do NOT trust hook-based tracing of the Init copy loops: hooks replace bytes
  with OPCODE_BRK (0xDB) and corrupt multi-byte instructions/operands; loop-body
  hooks at 0x0167/0x0168/0x0179/0x017a never fired; broad hooking aborted.
- `fast_mode=True` is a valid diagnostic (bypasses mode-3 drop) but not the ROM
  fix.

## Remaining work (ordered)

1. Fix ROM: wait for VBlank (or LCD off) before VRAM copies in `Init`;
   optionally clear full BG map ($9800..$98BF) to remove boot-logo residue
   (rows 8-10 currently show boot logo fragments). Rebuild, re-link with map/sym.
2. Fix tools/pyboy_test.py: BGP at 0xFF47; title at 0x0134; correct foreground
   color (or assert on the actual palette indices); use 16-byte PyBoy tile
   stride or `pb.get_tile` for tile assertions; keep 100-frame wait; keep
   seek(0) on load_state.
3. After ROM fix, re-verify in accurate mode: VRAM tiles + BG map row 4 must
   match ROM data exactly (no drops). Then decide pixel assertions:
   - either derive from `pb.get_tile`/screen self-consistently after the fix,
   - or keep pixel assertions structural (e.g. text-row region differs from
     blank rows) and use mGBA (`make test`) as visual ground truth.
4. Optional: open a PyBoy issue / inspect compiled .so if the stale-render
   behavior (open mystery #2) matters; it does not block steps 1-3.
5. Wire `tools/pyboy_test.py` into Makefile (`make check` or similar).

## Key addresses / symbols

```
0x0157 Init        0x0185 FrameLoop   0x018f tiles (72 bytes)   0x01d7 text_row (10 bytes)
BGP $FF47 (=0xE0 post-Init)   LCDC $FF40 (=0x93)   LY $FF44   STAT $FF41
BG map row 4: $9885..$988E    tile data: $8000..$8047 (game), boot logo at $8010..$806F
```

## Repro snippets that produced the key evidence

```python
# mode-3 drop proof
for fm in (False, True):
    pb = pyboy.PyBoy("build/morseboy1.gb", window="null", cgb=False, sound_emulated=False, fast_mode=fm)
    pb.tick(100, render=False)
    print(fm, list(pb.memory[0x9885:0x988f]), list(pb.memory[0x8040:0x8048]))

# marker experiment (stale render)
pb = pyboy.PyBoy("build/morseboy1.gb", window="null", cgb=False, sound_emulated=False)
pb.tick(100, render=False)
pb.memory[0xff40] &= 0x7F
for i in range(16): pb.memory[0x8000+i] = i
for x in range(32): pb.memory[0x9800+x] = 0
pb.memory[0xff40] |= 0x80
pb.tick(2, render=True)
# -> rendered tile 0 all-white (p=3), readback [0..15]
```
