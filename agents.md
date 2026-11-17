GBDK-2020 Game Boy (DMG-only, single-bank 32 KB ROM) project.
1. DMG only: keep CGB header flag `$00`, no CGB/palette code.
2. Build with `make` (GBDK at `~/gbdk-2020`, override via `GBDK_ROOT`); verify with `make smoke` (mGBA headless) before calling a change done.
3. Pixel changes: `make venv`, then run the PyBoy pixel checks in `docs/`.
