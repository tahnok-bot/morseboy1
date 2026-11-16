# Linting, static analysis & correctness checking for `morseboy1`

Research notes on how to lint and correctness-check this Game Boy / Game Boy Color
starter ROM (RGBDS 0.9.3 baseline, single-bank DMG/CGB-compatible ROM, zero-dependency
Node web server). All local tool behavior below was **verified in this environment**
(RGBDS 0.9.3, Node v22.23.4, `tools/mgba-headless` ELF) unless marked otherwise.

Baseline facts about this repo:

- Build: `rgbasm -i include` → `rgblink -t -l linker/script.ld` → `rgbfix -v -p 0`.
- ROM is 32 KiB, CGB-enhanced flag `0x80` at `0x143`, entry at `0x0150`, no MBC,
  no VRAM bank 1, no banked WRAM (verified: `src/main.asm` has no `VRAM1`/`rVBK`).
- `make test` = `timeout 2 tools/mgba-headless build/morseboy1.gbc`; exit `124`
  (timed out → still running) or `0` counts as pass.
- CI (`.gitea/workflows/pages.yaml`) pins `RGBDS_VERSION: "0.9.3"`.

---

## 1. RGBDS-side checking (0.9.3)

### 1.1 `rgbasm` warning flags (verified from the 0.9.3 man page, `rgbasm.1` DIAGNOSTICS)

In 0.9.3 **only `rgbasm` supports `-W`** (verified: the 0.9.3 `rgblink.1`/`rgbfix.1`
man pages contain no `-W` flag; `-W` for link/fix/gfx landed in **0.9.4** per the
[0.9.4 release notes](https://github.com/gbdev/rgbds/releases/tag/v0.9.4)).
So on the repo's 0.9.3 baseline, strict-warning flags can only be applied to `rgbasm`.

Meta warnings (group enablers):

| Flag | Effect (man-page wording, abridged) |
| --- | --- |
| `-Wall` | Warnings "likely to indicate an error or undesired behavior, and that can easily be fixed." |
| `-Wextra` | Extra warnings "less likely to pose a problem, but that may still be wanted." |
| `-Weverything` | "Enables literally every warning." |
| `-Werror` / `-Werror=name` | Turn all (or one) warning(s) into error(s); negatable as `-Wno-error[=name]`. |
| `-w` | Disable all warning output (even when turned into errors). |

Individual warnings (each has a `-Wno-` negation; "enabled by" = included in that meta flag):

| Flag | What it catches |
| --- | --- |
| `Wno-assert` | `WARN`-type assertion failures (`ASSERT` semantics, see `rgbasm(5)`). |
| `Wbackwards-for` *(Wall)* | `FOR` loops whose start/stop are switched relative to the step value. |
| `Wbuiltin-args` *(Wall)* | Incorrect arguments to built-ins, e.g. `STRSLICE` with out-of-bounds indexes. |
| `Wcharmap-redef` *(Wall)* | Re-defining a charmap mapping. |
| `Wdiv` | Dividing `-2**31` by `-1` (overflow, yields itself). |
| `Wempty-macro-arg` *(Wextra)* | Empty macro arguments. |
| `Wempty-strrpl` *(Wall)* | `STRRPL` called with an empty replacement substring. |
| `Wlarge-constant` *(Wall)* | Constant too large for a signed 32-bit integer. |
| `Wmacro-shift` *(Wextra)* | Shifting macro arguments past their limits. |
| `Wno-nested-comment` | `/*` inside a block comment (comments cannot nest; first `*/` ends it all). |
| `Wno-obsolete` | Obsolete constructs such as the `_PI` constant or the `PRINTT` directive. |
| `Wnumeric-string=0\|1\|2` | Multi-character string treated as a number. `=1`: strings > 4 chars (4 fit in 32 bits); `=2`: *any* multi-char string. |
| `Wpurge=0\|1\|2` | Purging symbols likely to have been necessary. `=1`: any exported symbol; `=2`: any label. |
| `Wshift` | Right-shifting a negative value (suggests division instead). |
| `Wshift-amount` | Shift operand negative or > 32. |
| `Wtruncation=0\|1\|2` | Implicit truncation (e.g. `db` of an 8-bit value) losing bits. `=1`: N-bit value ≥ 2**N or < -2**N; `=2` additionally: < -2**(N-1) (two's-complement overflow). |
| `Wunmapped-char=0\|1\|2` | Character goes through charmap conversion with no mapping. `=1`: active charmap non-empty; `=2`: also when charmap empty / not default. |
| `Wunmatched-directive` *(Wextra)* | `PUSHC`/`PUSHO`/`PUSHS` without a matching `POPC`/`POPO`/`POPS`. |
| `Wunterminated-load` *(Wextra)* | `LOAD` block not terminated by `ENDL`. |
| `Wno-user` | The `WARN` built-in is executed. |

Other useful `rgbasm` options for build hygiene (0.9.3):

- `-M depend_file` / `-MG` / `-MP` / `-MT` / `-MQ` — make-style dependency generation;
  the repo currently hard-codes `include/hardware.inc` and `linker/script.ld` as
  prerequisites of `$(OBJ)`. `-M` would make that automatic and robust.
- `-X max_errors` — cap error reporting.
- `-D name=value`, `-I path`, `-b chars`, `-p pad_value`, `-s features:state_file`.

**Verified on this repo (0.9.3, run in a temp dir, repo untouched):**

```text
$ rgbasm -Wall -Wextra -i include -o /tmp/... src/main.asm          # rc=0, zero warnings
$ rgbasm -Weverything -Wtruncation=1 -i include -o /tmp/... src/main.asm  # rc=0, zero warnings
```

The starter source is already clean under the strictest settings, so enabling them
costs nothing today.

### 1.2 `rgblink` options worth using (verified from the 0.9.3 `rgblink.1`)

| Flag | Meaning | Relevance here |
| --- | --- | --- |
| `-d` / `--dmg` | "Enable DMG mode. Prohibit the use of sections that doesn't exist on a DMG, such as VRAM bank 1." Implies `-w`. | **Verified: `rgblink -d -t -l linker/script.ld` links this ROM successfully (rc=0).** Because the ROM claims DMG compatibility (CGB flag `0x80`), linking with `-d` guarantees it doesn't secretly require CGB-only memory. |
| `-t` / `--tiny` | Expand ROM0 from 16 KiB to 32 KiB; fixed ROMX banks other than 1 become errors. | Already used. Correct for a 32 KiB single-bank ROM. |
| `-w` / `--wramx` | Expand WRAM0 from 4 KiB to 8 KiB. | Implied by `-d`; harmless while unused. |
| `-x` / `--nopad` | Don't pad the end of the file; implies `-t`. Man page: "not a replacement for rgbfix -p". | Only for non-ROM binaries; keep current setup. |
| `-M` | Map file lists sections only, not symbols. | Optional diagnostic. |
| `-S file` | Write a symbol file (all visible labels + exported constants). | Good for debugging / round-trip work. |
| `--map file` | Full map of section/symbol placement. | Good for catching accidental address collisions. |

### 1.3 `rgbfix` header/checksum checking (verified from the 0.9.3 `rgbfix.1`)

Key options:

| Flag | Meaning |
| --- | --- |
| `-v` / `--validate` | Equivalent to `-f lhg`: fix Nintendo logo (`0x104–0x133`), header checksum (`0x14D`), global checksum (`0x14E–0x14F`). |
| `-f spec` / `--fix-spec spec` | Fix (lowercase) or intentionally trash (uppercase, binary inverse) `l` logo, `h` header checksum, `g` global checksum. |
| `-p pad` / `--pad-value pad` | Pad to the next valid size (32 KiB … 8192 KiB) and update the cartridge size byte `0x148`. Man page recommends `0xFF` ("to speed up writing the ROM to flash chips, and to avoid 'nop slides' into VRAM"); this repo currently uses `-p 0`. |
| `-c` / `-C` | CGB-compatible flag `0x143` = `0x80` / CGB-only `0xC0`. |
| `-s` | SGB flag `0x146` = `0x03` (ignored by SGB unless old licensee `-l` is `0x33`; rgbfix warns otherwise). |
| `-j` | Non-Japanese flag `0x14A` = `0x01`. |
| `-m mbc` | Cartridge type `0x147`; accepts names (`rgbfix -m help` lists them). |
| `-i`, `-k`, `-l`, `-n`, `-t`, `-r`, `-O`, `-L` | Game ID, new/old licensee, ROM version, title, RAM size, overwrite-without-warning, custom logo file. |

Nuances discovered while verifying (worth keeping straight):

- **`-v` *fixes*, it does not merely check.** It writes the correct values. A pure
  *read-only* validation is: run `rgbfix -f lhg rom -o out` and `cmp` — if the
  original is already correct, nothing changes.
- **Header checksum formula.** rgbfix's source (and its own test vectors in
  `test/fix/header.*`, and independent implementations such as
  [PyBoy](https://github.com/Baekalfen/PyBoy/blob/master/pyboy/core/cartridge/cartridge.py))
  compute: `c = 0; for each byte b in 0x134..0x14C: c = (c - b - 1) mod 256`.
  The frequently-quoted shorthand "negative sum of 0x134–0x14C" omits the per-byte
  `-1` and will disagree with rgbfix by `0x19`. (Formula verified against the
  [RE.wiki header parser](https://reverseengineering.wiki/index.php/Format:Game_Boy_ROM_image)
  which was checked against the acid2 test ROMs.)
- **What hardware actually checks:** the DMG boot ROM compares the logo bytes and the
  header checksum, and locks up on mismatch
  ([Pan Docs, Power-Up Sequence](https://gbdev.io/pandocs/Power_Up_Sequence.html)).
  The global checksum is *not* checked by any hardware — never fail a build over it.
- **Verified on `build/morseboy1.gbc`** (read-only): logo all 48 bytes match the
  canonical DMG logo; header checksum `0xAF` PASS; global checksum `0xA453` PASS;
  `0x143 = 0x80`; size 32768 bytes. `rgbfix --validate` makes **zero changes** to the
  built ROM (rc=0) — the existing build rule is already header-correct.

### 1.4 Strict-warning Makefile practice (prior art)

[pret/pokecrystal's Makefile](https://github.com/pret/pokecrystal/blob/master/Makefile)
(standard reference for strict RGBDS builds) uses:

```make
RGBASMFLAGS  ?= -Weverything -Wtruncation=1
RGBLINKFLAGS ?= -Weverything -Wtruncation=1
RGBFIXFLAGS  ?= -Weverything
RGBGFXFLAGS  ?= -Weverything
```

and a reproducibility target:

```make
compare: $(roms) $(patches)
	@$(SHA1) -c roms.sha1
```

(`sha1sum` on Linux, `shasum` on macOS.) Caveat for this repo: `RGBLINKFLAGS`/
`RGBFIXFLAGS`/`RGBGFXFLAGS` with `-W` only work on **RGBDS ≥ 0.9.4**; the repo pins
0.9.3, where only `rgbasm` accepts `-W`. Either keep `-W` on `rgbasm` only, or bump
`RGBDS_VERSION` in `pages.yaml` to ≥ 0.9.4 first.

A SHA1/`sha256sum` pin of the built ROM is an attractive CI addition (catches
non-reproducible or accidentally-modified builds); pokecrystal maintains
`roms.sha1` for exactly this.

---

## 2. "GBDK checkasm" — negative result

The request mentioned "GBDK's `checkasm`". Finding: **there is no Game Boy or GBDK
tool named `checkasm`** that serves this purpose.

- `checkasm` is a **host-CPU** assembly verification/benchmarking tool:
  [haasn/checkasm](https://github.com/haasn/checkasm) — "tool for verifying
  correctness of assembly code and performance benchmarking" for x86/x86-64, ARM,
  ARM64, RISC-V, LoongArch, etc. (VideoLAN/FFmpeg tooling lineage). It verifies
  *native* assembly for the build host, not Z80/SM83 code.
- The [GBDK-2020](https://github.com/gbdk-2020/gbdk-2020) tree (develop) was
  inspected (top-level Makefile + `.github/workflows/`): no `checkasm` target or
  reference anywhere; the build is `sdcc` (SM83 front end) + `gbdk-lib`/`gbdk-support`.
- GBDK is a C compiler toolchain; it has no RGBDS-style warning-flag system. Its
  closest "lint" is simply `sdcc` compiling without warnings plus the usual
  test-ROM validation (see §3).

Conclusion: don't chase `checkasm`; the GB equivalents are the strict RGBDS flags in
§1 plus the test ROMs in §3.

---

## 3. Test ROMs and validation suites

### 3.1 What "running in mGBA headless" gives (and doesn't)

- The repo's `tools/mgba-headless` is the mGBA headless frontend (current mGBA
  releases top out at **0.10.5**, 2025-03-09; this binary's `--version` prints usage
  rather than a version string, so it is likely a release-built 0.10.x binary).
  Useful options (verified from `-h`): `-b bios`, `-C option=value`, `-l log-level`,
  `-s frameskip`, and the test hooks **`-S SWI`** (run until the Nth SWI call) and
  **`-R REGISTER`** (exit code = register value).
  ([mGBA repo](https://github.com/mgba-emu/mgba), headless source
  [`src/platform/headless-main.c`](https://github.com/mgba-emu/mgba/blob/master/src/platform/headless-main.c)).
- A GB ROM that runs forever never exits on its own, so the existing
  `timeout 2 … ; [ $code -eq 124 ] || [ $code -eq 0 ]` smoke test is the right
  pattern: it distinguishes "mGBA rejected/crashed the ROM" (non-zero exit, fast)
  from "ROM boots and runs" (timeout). It is a **smoke test**, not a correctness test
  — it cannot detect wrong pixels or wrong register values.
- mGBA's own emulator-regression suite lives in the mGBA repo as
  [`cinema/gb/...`](https://github.com/mgba-emu/mgba/tree/master/cinema/gb) (built
  `test.gb` files + `baseline_0000.png` screenshots; Python integration under
  `src/platform/python/cinema/`): suites `acid`, `blargg`, `mooneye-gb`,
  `ramg-mbc3`, `samesuite`, `window`. There is **no** top-level `verification/`
  directory in mGBA master (checked: 404). These ROMs validate *emulators*, but the
  files themselves are the canonical, ready-to-use test ROMs.
- [felixjones/github-mgba-rom-test](https://github.com/felixjones/github-mgba-rom-test)
  is a composite GitHub Action wrapping exactly the `-S <swi> -R <register>` pattern:
  it downloads mGBA, runs
  `mgba-headless -S 3 -R r0 <rom>`, and compares the exit code to a
  `success-code` input. Inputs: `swi-call` (default 3), `read-register` (default
  `r0`), `rom-path`, `success-code` (default 0). This is the standard
  CI-integration pattern for "unit-testing" a GB/GBA ROM — but it requires the ROM
  itself to use `ldh a, c`-style **SWI** calls and set a result register.
  `morseboy1` currently makes no SWI calls, so this is a *future* hook: if a test
  harness is ever added to the ROM (e.g. self-checking palette/VRAM state and
  exiting via SWI with `a = 0` on success), CI can do exactly this.
  (Gitea has no native equivalent of that Action; the local `tools/mgba-headless`
  binary supports the same flags directly, so a `make` target can do it identically.)

### 3.2 Widely used DMG/CGB correctness test ROM collections

Aggregators:

- [c-sp/game-boy-test-roms](https://github.com/c-sp/game-boy-test-roms) — compiled
  test ROMs with per-suite howtos (`src/howto/blargg.md`, `dmg-acid2.md`,
  `cgb-acid2.md`, `cgb-acid-hell.md`, `bully.md`, …) and CI
  (`.github/workflows/build-and-release.yml`) that builds them with `rgbds`/`wla-dx`
  and publishes releases. Practical "grab a prebuilt `.gbc`" source.
- [Rangi42/GBEmulatorShootout](https://github.com/Rangi42/GBEmulatorShootout) —
  automated emulator-accuracy comparison; documents the canonical suite list and
  publishes results at <https://gbdev.io/GBEmulatorShootout/>.
  (Rangi42's own repos: `Rangi42/GBEmulatorShootout` and a `Rangi42/rgbds` fork of
  `gbdev/rgbds`; no standalone Rangi42 test-ROM repo found.)

Individual suites (what emulators are actually graded on):

| Suite | Origin | Notes |
| --- | --- | --- |
| Blargg CPU/sound | [blargg/blink](https://github.com/blargg/blink), [blargg/gb-test-cores](https://github.com/blargg/gb-test-cores) | `cpu_instrs`, `dmg_sound`, `cgb_sound`; the long-standing baseline. |
| Mooneye | [gekkio/mooneye](https://github.com/gekkio/mooneye) | Comprehensive (CPU, timers, LCD, sound, palettes, SGB). |
| acid2 / acid-hell | [mattcurrie/acid](https://github.com/mattcurrie/acid) | `dmg-acid2`, `cgb-acid2`, `cgb-acid-hell`; graphics-focused, CGB palette/LCD torture. |
| SameSuite | [LIJI32/SameSuite](https://github.com/LIJI32/SameSuite) | "developed to aid the development of SameBoy by documenting previously unknown hardware behaviors"; useful for documenting *what the hardware really does*. |
| MBC3 RTC | [aaaaaa123456789/rtc3test](https://github.com/aaaaaa123456789/rtc3test) | RTC correctness (not relevant to this ROM — no MBC — but in the standard list). |
| Bully / Strikethrough | [ashiepaws/bully](https://github.com/ashiepaws/bully), [ashiepaws/strikethrough](https://github.com/ashiepaws/strikethrough) | Graphics/IRQ timing tests. |
| Mealybug Tearoom | [mattcurrie/GBMealybugTearoom](https://github.com/mattcurrie/GBMealybugTearoom) | Timers/LCD. |
| CasualPokePlayer test ROMs | [CasualPokePlayer/test-roms](https://github.com/CasualPokePlayer/test-roms) | Pokeengine-adjacent hardware behavior tests. |

Practical take for `morseboy1`: these suites validate the **emulator**, which is what
the web player (`@thenick775/mgba-wasm`) embeds — they are only indirectly about
this ROM. The direct, cheap correctness layer for *this* ROM is §1 (strict flags +
header validation) plus the §3.1 smoke test. A `make check-suite` target that
downloads a couple of prebuilt ROMs (e.g. `dmg-acid2` + Blargg `cpu_instrs`) and
runs them under `tools/mgba-headless` is a nice optional extra, but note a plain
headless run of a third-party test ROM only tells you "mGBA runs it" — meaningful
results need screenshot comparison (mGBA's `cinema` approach) or ROM-side SWI
reporting, which these ROMs don't provide.

---

## 4. ROM header & cartridge-type validation beyond `rgbfix`

- [mattmuroya/gbrom](https://github.com/mattmuroya/gbrom) — Python CLI that decodes
  the GB header and prints `Logo: PASS/FAIL`, `Header checksum: PASS/FAIL`,
  `Global checksum: PASS/FAIL` plus cartridge metadata. Zero-build (pip) dependency
  for a human-readable header report; good for a `make check-header` that doesn't
  re-implement checksum math.
- [drpaneas/archimedes](https://github.com/drpaneas/archimedes) — CLI that hex-dumps
  header/cartridge internals, licensing info, entry points; good for debugging
  "why does this ROM not boot on hardware".
- The repo's own build already runs `rgbfix -v` on every build, so the logo and
  checksums are *correct by construction*; a check target should therefore be a
  **no-change assertion** (`rgbfix -f lhg … && cmp`) or a `gbrom` report, not a
  re-fix.
- `rgbfix -m help` lists the accepted MBC type names; setting `-m` explicitly in the
  build rule (e.g. `-m ROM` for no MBC) documents intent and guards against an
  accidental non-zero cartridge-type byte from the `db`-based header in
  `src/main.asm`.
- Invalid-opcode / bad-byte checking is not a standard standalone tool; the closest
  are: (a) the Z80 opcodes in the [gbz80(7)](https://rgbds.gbdev.io/docs/master/gbz80.7)
  reference (shipped in the RGBDS release tarball) — illegal opcode bytes mostly
  arise from data/code overlap mistakes, which `rgblink` errors (section
  overlap) already catch at link time; (b) round-trip disassembly (§5), where a
  disassembler will flag undecodable bytes in code ranges.

---

## 5. Disassembly round-trip tooling — `rgbdis` status

**Finding (thoroughly verified): `rgbdis` was never part of `gbdev/rgbds`.**

Evidence:

- GitHub history query `commits?path=src/dis` (and `dis`, `src/dis/rgbdis.c`) on
  [gbdev/rgbds](https://github.com/gbdev/rgbds) returns **zero commits**; the repo
  history goes back to 2009.
- Release tarballs checked, none contain `rgbdis` (no binary, no man page):
  `v0.1.0` (2014, src = `asm/fix/lib/link`), `v0.2.0`, `v0.2.1`, `v0.3.10`
  (docs only for the four tools), and every modern tree `v0.4.0`…`v1.0.4`
  (src = `asm/fix/gfx/link`, man pages = `rgbasm`, `rgblink`, `rgbfix`, `rgbgfx`,
  `rgbds`, `gbz80`). The local **0.9.3** tarball (the repo baseline) contains only
  `rgbasm`, `rgblink`, `rgbfix`, `rgbgfx` + man pages.
- No release note in the range `v0.3.10`…`v1.0.4` mentions `rgbdis` at all (no
  "removed in X" line exists — because there was nothing to remove).
- Version chronology per [rgbds.gbdev.io/versions](https://rgbds.gbdev.io/versions);
  note `v0.8.5` is **not** a real tag (`v0.8.0` is the closest stable of that era),
  so "removed in 0.8.5" style claims should not be made.

So: `rgbdis` is a **separate, legacy community disassembler** that happens to share
the RGBDS naming (e.g.
[Cleverking2003/kdreamlanddis](https://github.com/Cleverking2003/kdreamlanddis)
tells users to "download rgbdis" separately for its `make` build). It is not
distributable via RGBDS releases, has no current maintainer of record, and should
**not** become a build/CI dependency of this repo.

**Maintained alternative:** [mattcurrie/mgbdis](https://github.com/mattcurrie/mgbdis)
(Python ≥ 3.6) disassembles GB/GBA ROMs into **RGBDS-compatible assembly**
(≥ 0.8.0), handles multi-bank ROMs, accepts `.sym` files, uses
`hardware.inc` defines, and *emits a makefile to rebuild the disassembly* — which is
exactly the round-trip pattern (disassemble → rebuild → byte-compare with
`cmp`/`sha256sum`) one would want for verifying or auditing ROM output. If
round-trip checking is ever desired, an optional `make roundtrip` using `mgbdis`
(python-only dependency) is the sane design; skip `rgbdis`.

---

## 6. Palette / tile & asset correctness

- **The CGB hardware rule** relevant to this ROM (which animates BCP/OCP palettes):
  each 8×8 tile may use only **4 colors from a single palette row** (a tile's four
  2-bit color indices reference one row of the 4×4 GBC palette); a tile whose
  colors span two rows will render with half its colors wrong on real CGB hardware.
- [Palette Guard](https://stellod.itch.io/gbc-palette-guard) — Aseprite plugin that
  enforces exactly this rule and can flag/fix offending tiles. This is the right
  tool if tile art moves from inline `db` (as in `src/main.asm`) into external
  assets; for in-assembly `db` tiles it's a manual/convention concern.
- [vulpivia/pixelpal](https://github.com/vulpivia/pixelpal) — CLI to
  `validate`/`convert`/`find` palettes in image files (useful when adding
  `rgbgfx`-generated assets).
- `rgbgfx` (in the 0.9.3 release) converts assets to 1bpp/2bpp/4bpp GB tile
  formats; in 0.9.3 it has **no `-W` flag** (added 0.9.4). There is no
  "tile-color-per-row" checker *inside* RGBDS; Palette Guard is the community
  answer.

---

## 7. Build-side linting for this repo

### 7.1 Shell / Makefile

- `shellcheck` is **not installed** in this environment (checked `PATH`); it's a
  single static binary (apt/brew/gh-release). The Makefile's only nontrivial shell
  is the multi-line `test:` recipe (`code=0; timeout 2 … || code=$?; …`), which
  shellcheck covers once extracted, plus any future `*.sh` (e.g.
  `src/assemble-all.sh`-style scripts if test ROMs are added).
- `node --check` (built into Node) gives a **zero-dependency syntax check** for
  `web/server.mjs` — **verified passing** on the current file.

### 7.2 JavaScript (`web/`)

- The web side is one file, `web/server.mjs` (zero-dependency static server) plus
  `web/index.html`. `package.json` has no lint tooling and a single dependency
  (`@thenick775/mgba-wasm`).
- Sensible progression: (1) `node --check web/server.mjs` now (free);
  (2) optionally add `eslint` + `prettier` as devDependencies with a small config
  only if more JS appears. Full ESLint in CI for a single 100-line server is
  optional, not required.

### 7.3 Other hygiene

- `rgbasm -M` dependency generation (see §1.1) instead of hand-listed prerequisites.
- Optional `sha256sum -c roms.sha1` reproducibility target (pokecrystal pattern, §1.4).
- CI: `.gitea/workflows/pages.yaml` builds with RGBDS 0.9.3 + Node and deploys
  `web/_site/`; adding a `make check` step before the build/deploy is the natural
  place to gate. If `-Weverything` on `rgblink`/`rgbfix` is wanted (pokecrystal
  parity), bump `RGBDS_VERSION` to ≥ 0.9.4 first.

---

## 8. Recommended `make check` setup (concrete)

Targets below are written for the repo's actual layout and its 0.9.3 baseline.
Everything in "core" was verified to pass on the current tree; "optional" items are
marked.

```make
# --- strict diagnostics -------------------------------------------------
# 0.9.3: only rgbasm accepts -W. (On RGBDS >= 0.9.4 you could also give
# rgblink/rgbfix/rgbgfx: -Weverything -Wtruncation=1, as pret/pokecrystal does.)
ASMSTRICT := -Weverything -Wtruncation=1

# --- check targets ------------------------------------------------------
.PHONY: check check-asm check-link check-header check-rom check-shell check-js

# Aggregated gate for CI (pages.yaml): runs everything in core.
check: check-asm check-link check-header check-rom check-shell check-js

# Assemble with the full warning set; fail on any warning/error.
check-asm:
	$(RGBASM) $(ASMFLAGS) $(ASMSTRICT) -o $(BUILD)/check.o $(ASM)

# Link in DMG mode: proves the "CGB-compatible" ROM uses no CGB-only memory
# (VRAM bank 1, banked WRAM, ...). rc=0 verified on the current ROM.
check-link: check-asm
	$(RGBLINK) -d -t -l linker/script.ld -o $(BUILD)/check.raw $(BUILD)/check.o

# Header must already be correct: rgbfix must not need to change anything
# (logo 0x104-0x133, header checksum 0x14D, global checksum 0x14E-0x14F).
check-header: rom
	$(RGBFIX) -f lhg $(ROM) -o $(BUILD)/check-header.gbc
	@cmp -s $(ROM) $(BUILD)/check-header.gbc || \
		{ echo "header check: logo/checksums need fixing (rgbfix -v)"; exit 1; }

# Existing mGBA headless smoke test (timeout 2; 124 = booted & running).
check-rom: test

# Optional: shellcheck on any *.sh (and Makefile recipes if extracted).
# Not installed locally; degrade to a notice instead of failing.
check-shell:
	@command -v shellcheck >/dev/null 2>&1 || { echo "check-shell: shellcheck not installed, skipping"; exit 0; }
	shellcheck -S warning $$(find . -name '*.sh' -not -path './node_modules/*') || exit 1

# Zero-dependency JS syntax check (verified passing).
check-js:
	node --check web/server.mjs
```

Optional extras (only if wanted):

```make
# Reproducibility pin (pokecrystal pattern). Update the file when the ROM
# intentionally changes.
check-romsum:
	sha256sum -c roms.sha1

# mGBA SWI/register "unit test" hook — only meaningful once the ROM calls SWI
# (e.g. `ldh a,c` x3 + `halt`/exit) and sets a result register. Pattern from
# felixjones/github-mgba-rom-test:
check-swit: rom
	$(MGBA) -S 3 -R a $(ROM)   # exit code must be the expected success code (0)

# Round-trip disassembly via mgbdis (Python), NOT rgbdis (see §5):
#   mgbdis build/morseboy1.gbc --sym build/morseboy1.sym -o disasm/ && cd disasm && make && cmp out.gb ../build/morseboy1.gbc
roundtrip: rom
	@command -v mgbdis >/dev/null 2>&1 || { echo "check: mgbdis not installed, skipping"; exit 0; }
	...

# Third-party test ROMs under mGBA (smoke-level only, see §3.2 caveat):
check-suite: rom
	# download dmg-acid2 / blargg cpu_instrs prebuilts (c-sp/game-boy-test-roms)
	# and run each under timeout 2 $(MGBA), expecting exit 124/0
```

Suggested CI change (`.gitea/workflows/pages.yaml`): after installing RGBDS 0.9.3
and Node, run `make check` before `make site`/deploy. Keep `make test` as-is.
If pokecrystal-parity strictness for `rgblink`/`rgbfix` is desired, bump
`RGBDS_VERSION` to `0.9.4` (or later 1.x — the 1.0.x line is current, e.g. 1.0.4)
and add `LINKSTRICT := -Weverything -Wtruncation=1`.

### What each piece catches (summary)

| Target | Catches | Cost |
| --- | --- | --- |
| `check-asm` | Truncation bugs, bad built-in args, unbalanced PUSH*/POP*, unterminated `LOAD`, obsolete constructs, unmapped chars — all at *compile* time. | ~instant, zero deps |
| `check-link` | Accidental use of CGB-only memory in a DMG-compatible ROM; section/section collisions are already hard link errors. | ~instant, zero deps |
| `check-header` | Logo/header-checksum/global-checksum drift if the build rule or header bytes change (real-hardware boot requirement). | ~instant, zero deps |
| `check-rom` | ROM rejected by mGBA, crash-on-boot (not pixel correctness). | 2 s |
| `check-shell` / `check-js` | Shell quoting/typo bugs; JS syntax errors. | ~instant (shellcheck optional install) |
| `check-swit` (future) | Actual in-ROM unit results via `-S`/`-R`. | needs ROM-side SWI hook |
| `roundtrip` (optional) | Build-output corruption/auditing via `mgbdis` disassemble→rebuild→cmp. | python dep |

---

## Sources

- RGBDS 0.9.3 (baseline): [release](https://github.com/gbdev/rgbds/releases/tag/v0.9.3),
  man pages `rgbasm.1`/`rgblink.1`/`rgbfix.1` from the release tarball (verified
  locally), [rgbds(5)](https://rgbds.gbdev.io/docs/master/rgbds.5),
  [gbz80(7)](https://rgbds.gbdev.io/docs/master/gbz80.7),
  [versions/chronology](https://rgbds.gbdev.io/versions).
- `rgbasm` DIAGNOSTICS section (0.9.3 man page) — warning table in §1.1.
- [pret/pokecrystal Makefile](https://github.com/pret/pokecrystal/blob/master/Makefile)
  — strict flag + SHA1 `compare` target (§1.4).
- [gbdev/pandocs — Power-Up Sequence](https://gbdev.io/pandocs/Power_Up_Sequence.html)
  (boot ROM logo + header checksum checks),
  [reverseengineering.wiki — GB ROM format](https://reverseengineering.wiki/index.php/Format:Game_Boy_ROM_image)
  (header fields, checksum formulas, verified against acid2).
- [PyBoy cartridge loader](https://github.com/Baekalfen/PyBoy/blob/master/pyboy/core/cartridge/cartridge.py)
  (independent implementation of the header-checksum formula).
- [mGBA](https://github.com/mgba-emu/mgba) — latest release 0.10.5;
  [`src/platform/headless-main.c`](https://github.com/mgba-emu/mgba/blob/master/src/platform/headless-main.c)
  (`-S`/`-R`); [`cinema/gb/`](https://github.com/mgba-emu/mgba/tree/master/cinema/gb)
  test-ROM tree; `src/platform/python/cinema/` integration.
- [felixjones/github-mgba-rom-test](https://github.com/felixjones/github-mgba-rom-test)
  — composite Action for mGBA `-S`/`-R` ROM unit tests.
- [c-sp/game-boy-test-roms](https://github.com/c-sp/game-boy-test-roms) — prebuilt
  suite collection + build CI.
- [Rangi42/GBEmulatorShootout](https://github.com/Rangi42/GBEmulatorShootout) —
  accuracy shootout + suite catalog, results at
  <https://gbdev.io/GBEmulatorShootout/>.
- Suites: [blargg/blink](https://github.com/blargg/blink),
  [blargg/gb-test-cores](https://github.com/blargg/gb-test-cores),
  [gekkio/mooneye](https://github.com/gekkio/mooneye),
  [mattcurrie/acid](https://github.com/mattcurrie/acid),
  [LIJI32/SameSuite](https://github.com/LIJI32/SameSuite),
  [aaaaaa123456789/rtc3test](https://github.com/aaaaaa123456789/rtc3test),
  [ashiepaws/bully](https://github.com/ashiepaws/bully),
  [mattcurrie/GBMealybugTearoom](https://github.com/mattcurrie/GBMealybugTearoom),
  [CasualPokePlayer/test-roms](https://github.com/CasualPokePlayer/test-roms).
- [haasn/checkasm](https://github.com/haasn/checkasm) — host-CPU asm checker
  (negative result for "GBDK checkasm");
  [gbdk-2020/gbdk-2020](https://github.com/gbdk-2020/gbdk-2020) (no `checkasm`).
- [mattmuroya/gbrom](https://github.com/mattmuroya/gbrom),
  [drpaneas/archimedes](https://github.com/drpaneas/archimedes) — header analyzers.
- [Palette Guard (GBC)](https://stellod.itch.io/gbc-palette-guard) — Aseprite plugin,
  4-colors-per-tile-row rule; [vulpivia/pixelpal](https://github.com/vulpivia/pixelpal)
  — palette CLI.
- [mattcurrie/mgbdis](https://github.com/mattcurrie/mgbdis) — maintained Python
  GB disassembler (RGBDS-compatible output, rebuild makefile).
- `rgbdis` absence: gbdev/rgbds commit-history path queries (0 commits for
  `src/dis`), release tarballs `v0.1.0`…`v1.0.4` (no `rgbdis`), release notes
  (no mention), [rgbds versions page](https://rgbds.gbdev.io/versions);
  third-party standalone usage: [Cleverking2003/kdreamlanddis](https://github.com/Cleverking2003/kdreamlanddis).
- Local repo: `Makefile`, `src/main.asm`, `linker/script.ld`, `web/server.mjs`,
  `.gitea/workflows/pages.yaml`, `package.json`, `tools/mgba-headless`.

*All local checks (warning-flag runs, DMG-mode link, header validation, checksum
math, `node --check`) were executed against the current tree on 2026-11-15 without
modifying repository files.*
