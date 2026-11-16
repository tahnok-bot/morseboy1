#!/usr/bin/env python3
"""
pyboy_test.py — headless correctness test for morseboy1, driven by PyBoy.

Complements `make test` (mGBA headless "does it run at all?") with actual
*assertions* on what the ROM does:

  * boot behavior (PyBoy's built-in DMG boot ROM plays a ~64-frame "P" logo
    animation and beeps before jumping to 0x0100, and sets BGP=0xFC itself)
  * register state (BGP, LCDC)
  * VRAM (tile data) and the background tile map (the "HELLO GBC!" row)
  * rendered pixels (dark-pixel count derived from the ROM's own tile bytes)
  * the recommended tilemap API (PyBoy.tilemap_background)
  * CPU liveness (PC stays inside FrameLoop)
  * symbol support (RGBDS .sym file -> pyboy.symbol_lookup / hooks)
  * CPU hooks (hook_register on FrameLoop)
  * save_state / load_state round-trip
  * input API smoke test

Usage:
  .venv/bin/python tools/pyboy_test.py [rom.gb] [rom.sym]

Defaults: build/morseboy1.gb and build/morseboy1.sym (auto-found next to the
ROM by PyBoy itself; passed here explicitly for clear error messages).

Exit code: 0 = all checks passed, 1 = at least one failed.

Requirements: .venv with pyboy (pip install pyboy), numpy, pillow.
"""

import sys
from pathlib import Path

import numpy as np

import pyboy

# ---------------------------------------------------------------------------
# Test ROM facts (mirrors src/main.asm)
# ---------------------------------------------------------------------------
ROM_PATH = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("build/morseboy1.gb")
SYM_PATH = Path(sys.argv[2]) if len(sys.argv) > 2 else ROM_PATH.with_suffix(".sym")

R_BGP = 0xFF47
R_LCDC = 0xFF40

BGP_EXPECTED = 0xE0  # classic green palette, written in Init
LCDC_EXPECTED = 0x80 | 0x10 | 0x02 | 0x01  # ON|BLOCK01|BG_9800|OBJ_8|OBJ_ON|BG_ON

N_TILES = 9
VRAM_TILES = 0x8000
TEXT_ROW_ADDR = 0x9800 + 4 * 32 + 5  # BG map, row 4, x=5..14
TEXT_ROW_LEN = 10

# Fixed 4-color DMG palette so pixel assertions are deterministic.
PALETTE = (0x000000, 0x333333, 0x999999, 0xFFFFFF)
# BGP 0xE0 -> pattern bit 0 (background) => color index 3, bit 1 (foreground)
# => index 1. (BGP bit pairs: 7-6 -> index of value 0, 5-4 -> index of 1.)
BG_COLOR = PALETTE[3]
FG_COLOR = PALETTE[1]


def rgba(color: int) -> np.ndarray:
    """Expand a 24-bit RGB int to the (R, G, B, A=255) buffer representation."""
    return np.array([(color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF, 255], dtype=np.uint8)


def expected_fg_pixels(tiles: bytes, text_row: bytes) -> int:
    """Total foreground pixels PyBoy must render: the sum of set bits in the
    tile bytes of every glyph in the text row."""
    total = 0
    for gid in text_row:
        tile = tiles[gid * 8 : gid * 8 + 8]
        for byte in tile:
            total += bin(byte).count("1")
    return total


def check(name, fn, results):
    try:
        msg = fn()
    except Exception as e:  # noqa: BLE001 — report, don't crash the run
        results.append((name, False, f"raised {type(e).__name__}: {e}"))
        return None
    ok = msg is None
    results.append((name, ok, msg or "ok"))
    return None if ok else True


def main() -> int:
    if not ROM_PATH.is_file():
        print(f"FAIL: ROM not found: {ROM_PATH} (run `make` first)")
        return 1
    if not SYM_PATH.is_file():
        print(
            f"FAIL: symbol file not found: {SYM_PATH}\n"
            "      generate it with: rgblink -Weverything -Wtruncation=1 -d -t "
            f"-l linker/script.ld -o /dev/null -n {SYM_PATH} build/main.o"
        )
        return 1

    rom_bytes = ROM_PATH.read_bytes()

    # Symbol addresses (from the .sym file; avoids hardcoding ROM layout here).
    syms = {}
    for line in SYM_PATH.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith(";"):
            continue
        try:
            bankaddr, name = line.split(maxsplit=1)
            _, addr = bankaddr.split(":")
            syms[name] = int(addr, 16)
        except (ValueError, IndexError):
            continue
    for needed in ("tiles", "text_row", "Init", "FrameLoop"):
        if needed not in syms:
            print(f"FAIL: symbol {needed!r} missing from {SYM_PATH}")
            return 1

    tiles_rom = rom_bytes[syms["tiles"] : syms["tiles"] + N_TILES * 8]
    text_row_rom = rom_bytes[syms["text_row"] : syms["text_row"] + TEXT_ROW_LEN]
    fg_expected = expected_fg_pixels(tiles_rom, text_row_rom)

    results: list[tuple[str, bool, str]] = []

    # ------------------------------------------------------------------ boot
    pb = pyboy.PyBoy(
        str(ROM_PATH),
        window="null",        # headless
        cgb=False,            # force DMG mode (this ROM is DMG-only)
        color_palette=PALETTE,
        sound_emulated=False,
        symbols=str(SYM_PATH),
    )

    def _c_title():
        if "MORSEBOY1" not in pb.cartridge_title:
            return f"unexpected title {pb.cartridge_title!r}"

    check("cartridge title", _c_title, results)

    # PyBoy's built-in DMG boot ROM runs a ~64-frame logo animation before
    # jumping to 0x0100, so give it time to actually reach the game code.
    ok = pb.tick(100)
    results.append(("ROM keeps running (tick x100)", bool(ok), "ok" if ok else "emulation stopped early"))

    # ------------------------------------------------------------ registers
    def _c_bgp():
        got = pb.memory[R_BGP]
        if got != BGP_EXPECTED:
            return f"BGP = 0x{got:02X}, expected 0x{BGP_EXPECTED:02X}"

    def _c_lcdc():
        got = pb.memory[R_LCDC]
        if got != LCDC_EXPECTED:
            return f"LCDC = 0x{got:02X}, expected 0x{LCDC_EXPECTED:02X}"

    check("BGP == $E0", _c_bgp, results)
    check("LCDC == $93", _c_lcdc, results)

    # --------------------------------------------------------------- memory
    def _c_vram():
        got = pb.memory[VRAM_TILES : VRAM_TILES + N_TILES * 8]
        if got != list(tiles_rom):
            for i, (g, e) in enumerate(zip(got, tiles_rom)):
                if g != e:
                    return f"VRAM mismatch at byte {i} (tile {i // 8}, row {i % 8}): 0x{g:02X} != 0x{e:02X}"
            return f"VRAM length {len(got)} != {len(tiles_rom)}"

    def _c_bgmap():
        got = pb.memory[TEXT_ROW_ADDR : TEXT_ROW_ADDR + TEXT_ROW_LEN]
        if got != list(text_row_rom):
            return f"BG map row = {got}, expected {list(text_row_rom)}"

    check("VRAM tile data", _c_vram, results)
    check("BG map text row", _c_bgmap, results)

    # ------------------------------------------------------------------ CPU
    def _c_pc():
        pc = pb.register_file.PC
        lo, hi = syms["FrameLoop"], syms["FrameLoop"] + 8  # the whole FrameLoop
        if not lo <= pc < hi:
            return f"PC = 0x{pc:04X}, expected inside FrameLoop 0x{lo:04X}-0x{hi:04X}"

    check("PC inside FrameLoop", _c_pc, results)

    # ---------------------------------------------------------------- screen
    def _c_screen():
        frame = pb.tick(1, render=True)  # ensure a rendered frame
        if not frame:
            return "tick(render) returned False"
        arr = pb.screen.ndarray.copy()
        if arr.shape != (144, 160, 4):
            return f"screen shape {arr.shape} != (144, 160, 4)"
        # Background: a known-background pixel must be the BG color.
        top_left = tuple(int(v) for v in arr[0, 0])
        if top_left != tuple(rgba(BG_COLOR)):
            return f"pixel(0,0) = {top_left}, expected BG color {tuple(rgba(BG_COLOR))}"
        # Foreground: only the glyphs may be FG; total FG pixel count must
        # match the sum of set bits in the glyph tiles.
        fg_mask = np.all(arr == rgba(FG_COLOR), axis=2)
        fg_got = int(fg_mask.sum())
        if fg_got != fg_expected:
            return f"foreground pixels = {fg_got}, expected {fg_expected}"
        # Foreground must be confined to the text row (map row 4 => y 32..39)
        # and columns 5..14 (x 40..119).
        band = fg_mask[32:40, 40:120]
        if int(band.sum()) != fg_got:
            stray = fg_got - int(band.sum())
            return f"{stray} FG pixels outside the text row/region"

    check("rendered pixels", _c_screen, results)

    # ------------------------------------------------------------ tilemap API
    def _c_tilemap():
        tmap = pb.tilemap_background
        got = [tmap.tile_identifier(x, 4) for x in range(5, 5 + TEXT_ROW_LEN)]
        if got != list(text_row_rom):
            return f"tilemap row 4 = {got}, expected {list(text_row_rom)}"

    def _c_get_tile():
        # Tile 1 = "H": its FG pixels (BGP bit 1 -> PALETTE[1]) must match the
        # bit pattern of the ROM tile bytes (bit 7 = leftmost pixel).
        t = pb.get_tile(1)
        arr = t.ndarray()
        if arr.shape != (8, 8, 4):
            return f"tile ndarray shape {arr.shape} != (8, 8, 4)"
        fg = np.all(arr == rgba(FG_COLOR), axis=2)
        for row in range(8):
            for col in range(8):
                want = bool(tiles_rom[1 * 8 + row] >> (7 - col) & 1)  # tile 1
                if bool(fg[row, col]) != want:
                    return f"tile 1 pixel ({col},{row}) fg={int(fg[row, col])}, expected {int(want)}"

    check("tilemap_background row", _c_tilemap, results)
    check("get_tile(1) = 'H'", _c_get_tile, results)

    # --------------------------------------------------------------- symbols
    def _c_symbols():
        for name, addr in syms.items():
            bank, got = pb.symbol_lookup(name)
            if bank != 0 or got != addr:
                return f"symbol_lookup({name!r}) = ({bank}, 0x{got:04X}), expected (0, 0x{addr:04X})"

    check("symbol_lookup (.sym)", _c_symbols, results)

    # ------------------------------------------------------------------ hooks
    hits = {"n": 0}

    def _hook(ctx):
        hits["n"] += 1

    def _c_hooks():
        pb.hook_register(0, syms["FrameLoop"], _hook, "ctx")
        try:
            ok = pb.tick(60)
            if not ok:
                return "emulation stopped during hook test"
            # FrameLoop is a tight VBlank poll, so the entry address executes
            # many times per frame; a handful per frame is enough to pass.
            if hits["n"] < 300:  # >= 5 per frame
                return f"hook fired {hits['n']}x in 60 frames, expected >= 300"
        finally:
            pb.hook_deregister(0, syms["FrameLoop"])

    check("hook_register @ FrameLoop", _c_hooks, results)

    # ------------------------------------------------------------ save / load
    def _c_state():
        import io

        before = pb.screen.ndarray.copy()
        state = io.BytesIO()
        pb.save_state(state)
        state.seek(0)  # load_state reads sequentially from the current position

        pb2 = pyboy.PyBoy(
            str(ROM_PATH),
            window="null",
            cgb=False,
            color_palette=PALETTE,
            sound_emulated=False,
            symbols=str(SYM_PATH),
        )
        try:
            pb2.load_state(state)
            pb2.tick(1, render=True)
            after = pb2.screen.ndarray.copy()
            if not np.array_equal(before, after):
                diff = int((before != after).any(axis=2).sum())
                return f"screen after load_state differs at {diff} px"
            bgp2 = pb2.memory[R_BGP]
            if bgp2 != BGP_EXPECTED:
                return f"BGP after load_state = 0x{bgp2:02X}"
        finally:
            pb2.stop()

    check("save/load state round-trip", _c_state, results)

    # ------------------------------------------------------------------ input
    def _c_input():
        # The ROM ignores input; this only verifies the API works headless.
        pb.button_press("B")
        pb.button_press("A")
        pb.tick(1, render=False)
        pb.button_release("B")
        pb.button_release("A")
        pb.tick(1, render=False)
        pc = pb.register_file.PC
        lo, hi = syms["FrameLoop"], syms["FrameLoop"] + 8
        if not lo <= pc < hi:
            return f"PC = 0x{pc:04X} after input, expected inside FrameLoop"

    check("input API (B/A)", _c_input, results)

    pb.stop()

    # ---------------------------------------------------------------- report
    width = max(len(n) for n, _, _ in results)
    failed = 0
    for name, ok, msg in results:
        status = "PASS" if ok else "FAIL"
        print(f"  {status}  {name.ljust(width)}  {'' if ok else msg}")
        failed += 0 if ok else 1
    print(f"\n{len(results) - failed}/{len(results)} checks passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
