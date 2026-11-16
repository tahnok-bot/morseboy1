# Game Boy DMG/CGB toolchain research

Research date: 2026 (see source links). Scope: alternatives/complements to the
current setup for a tiny single-bank, pure-SM83-assembly 32 KB ROM, plus
emulators and ROM-validation tooling for headless CI-style smoke testing.

## Current setup (baseline)

- **Assembler/linker/fixer:** RGBDS `rgbasm` + `rgblink` + `rgbfix`, driven by a
  custom linker script (`linker/script.ld`), padded to 32 KB with logo/header/
  checksum fixes (`rgbfix -v -p 0`).
- **Smoke test:** prebuilt mGBA headless binary (`tools/mgba-headless`, a custom
  mGBA build exposing `-S <SWI>` — run until a SWI is called — and
  `-R <register>` — return a GP register as exit code — on top of stock
  options). `make test` runs the ROM for 2 s under `timeout`; non-124/0 exit
  means failure.
- **Web:** mGBA WASM (`@thenick775/mgba-wasm`) served by a Node dev server.
- **Language:** 100% SM83 assembly, single bank, no cartridge RAM header
  features beyond the classic header.

---

## 1. Assemblers / RGBDS status

### RGBDS (the incumbent)

RGBDS is the de-facto standard SM83 toolchain and is in **strong active
maintenance**: [github.com/gbdev/rgbds](https://github.com/gbdev/rgbds), with
frequent releases by the GBDev team (Rangi42, ISSOtm).

**Version line (clarification of the "0.10.x" question):** RGBDS went
**0.9.x → 1.0.x**; there is no 0.10.x line. Full timeline:

| Version | Date | Notes |
|---|---|---|
| 0.9.0 | 2024-12-25 | deprecations (`ldio`, `ld [c]`, `ldh [$xx]`, multi-char strings as numbers); `PUSHS`/`PUSHO`/`PUSHC`; `0x/0b/0o` prefixes |
| 0.9.1 | 2025-02-02 | `--help` everywhere; undeprecated `[$ff00+c]`; macro arg limit removed |
| 0.9.2 | 2025-05-04 | 0-indexed string funcs (`STRFIND`, `STRRFIND`, `STRCHAR`, `STRSLICE`, `CHARCMP`, `CHARSIZE`, `REVCHAR`); negative macro `\<-n>`; `rgbgfx -B`; **`rgbfix -o` to a different output file** |
| 0.9.3 | 2025-06-30 | `CHARVAL` for multi-value charmaps; `rgbgfx -c dmg=XX` |
| 0.9.4 | 2025-07-31 | `[[ fragment literals ]]`, `READFILE`/`BYTELEN`/`STRBYTE`, `-W` diagnostics for rgblink/rgbfix/rgbgfx, `rgbasm -MC`, multiple `-P` preincludes |
| 1.0.0 | 2025-11-01 | **semver starts**; *removed*: multi-value strings as numbers, `ldio [c]`/`ld [c]`/`ldh [$xx]`; *deprecated*: single-char strings as numbers, `STRIN`/`STRRIN`/`STRSUB`/`CHARSUB` (→ 0-indexed `STRCHAR`/`STRFIND`/`STRSLICE`), `rgbfix -O` (→ `-Wno-overwrite`); colored diagnostics; `===`/`!==` |
| 1.0.1 | 2026-01-01 | bugfixes (AFL-fuzzing driven) |
| 1.0.2(+hotfix) | 2026-07 | bugfixes/edits |
| 1.0.3 | 2026-08-01 | fixes v1.0.2 regression (backwards `jr` ROM0→HRAM), `INCBIN` >2 GiB |
| 1.0.4 | 2026-09-22 | "most stable version ever": placement-algorithm overhaul in `rgblink` (hangs/invalid placements fixed), `-Wtruncation` for `jr`, no feature additions |

Release links: [v0.9.1](https://github.com/gbdev/rgbds/releases/tag/v0.9.1),
[v0.9.2](https://github.com/gbdev/rgbds/releases/tag/v0.9.2),
[v0.9.4](https://github.com/gbdev/rgbds/releases/tag/v0.9.4),
[v1.0.0](https://github.com/gbdev/rgbds/releases/tag/v1.0.0),
[v1.0.4](https://github.com/gbdev/rgbds/releases/tag/v1.0.4).

**Fit/migration:** upgrading 0.9.x → 1.0.4 is **low-effort** for this project:
the removed 1.0.0 constructs (`ld [c]`, `ldh [$xx]`, 1-indexed string funcs)
are not idiomatic in a small starter codebase, and `-Wno-obsolete` can silence
any legacy usage while migrating. Upsides: much faster and more robust
`rgblink`, better diagnostics, `rgbfix -o` to a different file (cleaner Makefile
pipelining), and a stable semver to pin in CI. **Recommendation: upgrade and
pin `1.0.4`.**

### WLA DX

- [WLA DX project page](https://www.villehelin.com/wla.html),
  [GitHub](https://github.com/midnightcowboy/wla-dx) (successor to Ville
  Helin's original, 1998–2008).
- Single assembler/linker for many platforms incl. **GB-Z80**
  (`.platform GBZ80`), with a different model: no separate object/linker script
  language — you get direct `org`/bank placement, labels, and a memory-map
  system (`.memorymap`) inside the assembler.
- **Maintenance:** actively updated; versions run well past 10.x (10.7 era as
  of 2026), released from the midnightcowboy fork with community maintenance.
  License is non-standard (custom WLA DX license — check before commercial use).
- **Fit:** a legitimate alternative assembler, but **not a complement** for this
  project: adopting it means rewriting the build (different directives:
  `org`, `section .romx`, `.asm`/`.link` file conventions, no RGBDS-style
  linker script). It shines for multi-platform Z80 codebases or when you want
  RGBDS-free tooling; for a 32 KB single-bank pure-asm ROM, RGBDS is strictly
  more mainstream, better documented for GB, and better maintained for GB
  specifically.
- **Verdict: don't migrate. Keep as a known alternative only.**

### Other SM83 assemblers (asmgb, asm8, etc.)

- **"asmgb"** — searches surface the 1990s-era ASMGB assemblers (historical,
  DOS-era); no modern maintained project under that name was found.
- **asm8** ([github.com/nufuto/asm8](https://github.com/nufuto/asm8)) — a
  maintained SM83-assembling assembler (also targets other 8-bit CPUs) with
  modern ergonomics; small community, far fewer GB-specific features/precedents
  than RGBDS. Not worth adopting for a GB project.
- **gameboy-asm** ([github.com/AstatinChan/gameboy-asm](https://github.com/AstatinChan/gameboy-asm)) —
  personal Go-based SM83/Game Boy assembler; 1 contributor, 1 prerelease.
  Experimental, not a toolchain bet.
- **z88dk's z80asm** — only worth mentioning inside the Z88DK section (below).

**Verdict: no credible challenger to RGBDS for pure-asm GB work.**

---

## 2. C compilers (only relevant if/when code moves to C or C/asm hybrid)

### GBDK-2020

- [github.com/gbdk-2020/gbdk-2020](https://github.com/gbdk-2020/gbdk-2020),
  docs at [gbdk.org](https://gbdk.org/docs/api/docs_releases.html).
- **Maintenance: very active.** Releases: 4.0 (2020-10) → 4.1 (2022-10) →
  4.1.1 (2022-11) → 4.2 (2023-08) → 4.3.0 (2024-06) → 4.4.0 (2025-05) →
  **4.5.0 (2025-12, latest)**.
- Stack: patched **SDCC** (sm83 port), `lcc` driver, `sdldgb`/`makebin`
  linking, C libraries (graphics/input/timer/sfx), source-level debug via
  `.cdb` + Emulicious/VS Code.
- **Original GBDK (the "GBDK 2013" line)** — created 1999, **ceased updates in
  2002 at v2.96a**; superseded by GBDK-2020. See
  [GBDK on GBDevWiki](https://gbdev.gg8.se/wiki/articles/GBDK). Any reference
  to "GBDK 2013" predates the modern line and is not maintained; **if C is
  ever wanted, use GBDK-2020, not the original.**
- **Fit:** GBDK's sweet spot is larger C+asm games with its CRT/library. For a
  32 KB pure-asm ROM it adds little; but it is the *lowest-friction path* to
  C for GB (prebuilt sm83 port, GB-specific libs, `lcc`).
- **Verdict: keep off the critical path; the right choice *if* C is adopted later.**

### Z88DK

- [github.com/z88dk/z88dk](https://github.com/z88dk/z88dk) — C + assembly
  toolchain for Z80-family machines (GB is one port; also ZX Spectrum, MSX,
  Game Gear, etc.). Latest release **v2.4 (2025-10-02)**; very active project
  with a large multi-platform community.
- Uses its own `z80asm`/`asmasm` + `sdcc`-compatible pipeline (GB port is
  `gb_z80`), its own CRT/lib, and can link with RGBDS.
- **Fit:** heavier abstraction, GB is a *secondary* platform (Spectrum-centric
  culture); GB-specific libs are thinner than GBDK's. For pure GB work,
  GBDK-2020 is the more purpose-built C option.
- **Verdict: don't adopt for a GB-only project; relevant only for
  multi-Z80-platform reuse.**

---

## 3. Emulators for DMG/CGB testing & verification

Reference for relative accuracy: **GBEmulatorShootout**
([github.com/gbdev/GBEmulatorShootout](https://github.com/gbdev/GBEmulatorShootout/)) —
automated comparison of Blargg, Mooneye, Matt Currie's acid tests, SameSuite,
MBC3 RTC, etc. Current leaders: **mGBA, SameBoy, BGB, ares, Emulicious,
VBA-M, PyBoy** all score very high on the GB core tests.

### mGBA (current) — [github.com/mgba-emu/mgba](https://github.com/mgba-emu/mgba)

- Mature (2011+), very accurate GB/CGB, actively maintained.
- Headless CLI is first-class: stock `mgba -q --no-window --no-sound rom` runs
  headless; `-m/--read-mem <addr> <len>` dumps memory to stdout; the repo's
  `tools/mgba-headless` is a **custom build that adds `-S <SWI>` (exit when a
  SWI is called) and `-R <register>` (GP register → exit code)** — genuinely
  useful for scripted ROM self-tests (a ROM can signal pass/fail via a
  register/SWI). Upstream also builds a similar `mgba-rom-test` utility from
  source (`-DBUILD_ROM_TEST=ON`).
- Also: Lua scripting, GDB remote stub, libretro core, WASM port (already used
  in `web/`).
- **Verdict: keep. Best-in-class fit for the existing CI smoke test.**

### BGB — [bgb.bircd.org](https://bgb.bircd.org/manual.html)

- Emulator/debugger by birch; **very actively maintained** (1.6.7 on
  2026-11-05; steady releases since 1.5.x in 2024). "If your rom works in BGB,
  it will most likely work on hardware."
- **Best headless automation story among the GUI emulators**:
  `-headless` (`-hf` = headless + runfast), `-autoexit` (exit on debugger break
  or demo end), `-screenonexit <file>` (screenshot on exit), `-stateonexit`,
  `-br`/`-wp` (breakpoints/watchpoints), `-nowarn`, exit code 0/1.
  Caveat: **Windows/Wine only** (no native Linux/macOS binaries; AUR packages it
  via Wine), which weakens it for Linux CI — usable as a *secondary cross-check*
  in a Wine container or locally.
- **Verdict: worth adding as an optional secondary smoke-test target** (high
  accuracy, strong GB-hardware fidelity, decent headless flags), with the
  Wine-only caveat.

### Emulicious — [emulicious.net](https://emulicious.net/)

- Java-based multi-system emulator focused on **debugging** (interactive
  disassembler, tracer, profiler, coverage, reverse stepping, remote debug to
  VS Code via the `emulicious-debugger` extension). Frequent updates through
  2024; maintained by Calindro.
- Desktop app; **no practical headless/CLI mode** — not a CI tool.
- **Verdict: excellent *interactive* debugger for GB (especially with RGBDS
  `.sym`/`.lst`), zero CI value. Optional dev-time tool only.**

### VBA-M (VisualBoyAdvance-M) — [github.com/visualboyadvance-m/visualboyadvance-m](https://github.com/visualboyadvance-m/visualboyadvance-m)

- Mature, actively maintained (libretro core is the main distribution channel).
- SDL frontend; no first-class headless-automation CLI (automation is typically
  via the libretro core). Good for manual GBC cross-checks and as a
  RetroArch-based playground, not for scripted CI.
- **Verdict: fine as a manual cross-check; not better than mGBA for CI.**

### SameBoy — [sameboy.github.io](https://sameboy.github.io/), [github.com/LIJI32/SameBoy](https://github.com/LIJI32/SameBoy)

- Top-tier accuracy (regularly the highest scorer in GBEmulatorShootout);
  **actively maintained** — 1.0 (2024-12) → 1.0.5 (2026), frequent releases
  with accuracy-focused changelogs.
- Desktop GUI (Cocoa/SDL/iOS); **no headless CLI** — the emulation core is
  reused by third parties (e.g. Boyless/gbemu-cli) if headless use is needed.
- **Verdict: keep as a manual verification workhorse (esp. CGB palette/timing
  edge cases); not a CI substitute for mGBA.**

### PyBoy — [github.com/Baekalfen/PyBoy](https://github.com/Baekalfen/PyBoy), docs [docs.pyboy.dk](https://docs.pyboy.dk/)

- Python emulator with **first-class headless scripting**: `PyBoy("rom.gb",
  window="null")`, `tick(n)`, memory indexing, screen buffer (Pillow/NumPy),
  deterministic; v2.9.x line, actively maintained (2026).
- The cleanest way to write *assertion-based* tests (read a RAM address after
  N frames, hash a screenshot) in Python, without any C binding work.
- Slower than native mGBA (pure Python), but trivial for a 32 KB ROM.
- **Verdict: worth adopting as the *next step* for the smoke test** — e.g.
  `pip install pyboy`, run 300 frames headless, assert a RAM flag/palette
  register, screenshot-compare. Strong CI citizen.

### Gambatte / gambaterm

- Core Gambatte (r571-era, ~2020; effectively feature-frozen) + SDL frontend
  without a no-window flag; [gambatte-terminal](https://github.com/vxgmichel/gambatte-terminal)
  is a maintained terminal frontend with `--break-after N` (stop after N
  frames) — interesting for TUI demos, marginal for CI.
- **Verdict: skip; mGBA covers this better.**

---

## 4. ROM header fixing / validation beyond `rgbfix`

| Tool | What it does | Status | Notes for this project |
|---|---|---|---|
| **rgbfix** (RGBDS) | Pad/align, Nintendo logo, header fields (CGB flag, cartridge type, RAM size), header+ROM checksum, MBC list (`-m`), `-v` verbose | Actively maintained (1.0.4) | Already in use; does everything this ROM needs. `rgbfix -v` prints the computed header for eyeball verification. |
| **gbrom** — [github.com/mattmuroya/gbrom](https://github.com/mattmuroya/gbrom) | Python CLI that *decodes* a ROM header and **validates boot logo, header checksum, global checksum** | Small community project, low maintenance signals | Complementary *verifier*: `gbrom build/morseboy1.gbc` as a post-build CI assertion that the header invariants hold (independent of rgbfix, catches bad padding/checksum regressions). Cheap to add. |
| **gbfix** — [github.com/elseyf/gbfix](https://github.com/elseyf/gbfix) | C++ ROM header fixer (logo, CGB flag, cartridge/RAM/ROM type, header & global checksum) | Personal project, low activity | Overlaps rgbfix's job; no advantage for this project. Skip. |

Other notes: `rgblink` (1.0.4) validates section placement against the linker
script at link time (assertions/bank fits), and the mGBA/Gambatte/Emulicious
loaders all re-check the header/length on boot — so the existing pipeline
already has layered validation. `gbrom` is the only genuinely additive piece.

---

## 5. Fit summary for this project (single-bank, 32 KB, pure asm)

| Candidate | Maturity | Maintenance | Fit here | Migration effort | Verdict |
|---|---|---|---|---|---|
| RGBDS 1.0.4 | ★★★★★ (de-facto standard) | ★★★★★ (monthly-ish releases, semver) | Perfect — already in use | Trivial (pin version, check for removed 1.0.0 constructs; `-Wno-obsolete` bridge) | **Upgrade & pin** |
| WLA DX | ★★★★ | ★★★★ (2026 releases) | OK but re-architecture; custom license | High (rewrite build, different directive set) | No |
| asm8 / gameboy-asm / "asmgb" | ★–★★ | ★–★★★ | Poor fit; tiny communities | n/a | No |
| GBDK-2020 4.5.0 | ★★★★★ | ★★★★★ | Only if C is adopted; heavy for 32 KB asm | Medium (new toolchain alongside, `lcc` + libs) | Keep in back pocket |
| Original GBDK ("2013") | dead | ✝ 2002 | No | n/a | No |
| Z88DK v2.4 | ★★★★ | ★★★★★ | Secondary platform culture; GB not primary | Medium | No (GB-only) |
| mGBA (stock + custom headless) | ★★★★★ | ★★★★★ | Perfect — already in use | n/a | **Keep** |
| BGB 1.6.7 | ★★★★★ | ★★★★★ (2026-11-05) | Good secondary accuracy cross-check | Low (Wine on Linux) | Optional add |
| Emulicious | ★★★★ | ★★★ (2024-era) | Interactive debugging only | Low (just run the JAR) | Optional dev tool |
| VBA-M | ★★★★ | ★★★★ | Manual cross-check only | Low | Optional |
| SameBoy 1.0.5 | ★★★★★ | ★★★★★ | Manual verification (CGB edge cases) | Low | Optional dev tool |
| PyBoy 2.9.x | ★★★★ | ★★★★ (Python) | Best fit for *assertion-based* CI | Low (`pip install pyboy`) | **Adopt for CI assertions** |
| Gambatte/gambaterm | ★★★ | ★★ | No better than mGBA | n/a | No |
| gbrom | ★★★ | ★★ | Independent header/checksum verifier | Very low (pip) | **Add to CI** |
| gbfix | ★★ | ★ | Redundant with rgbfix | n/a | No |

---

## 6. Recommendation

1. **Keep RGBDS + mGBA as the core.** Both are the most maintained,
   most accurate, and best-matched tools for a pure-asm DMG/CGB ROM.
2. **Upgrade RGBDS to 1.0.4** (no 0.10.x exists; 0.9.x → 1.0.x is the line).
   Pin the version in CI. Audit `src/` for the 1.0.0 removals
   (`ld [c]`, `ldh [$xx]`, `STRIN/STRSUB/CHARSUB` 1-indexed string funcs);
   `-Wno-obsolete` bridges any stragglers.
3. **Strengthen the smoke test with PyBoy** (headless, `window="null"`,
   `tick(N)`, RAM reads, screenshot): turn "it ran for 2 s" into "frame N
   shows X in memory / palette register / screen region". Optional second
   stage: `gbrom` to independently validate logo + header + global checksum.
4. **Optional dev-time tools, not CI:** Emulicious (interactive debugger with
   RGBDS `.sym` support) and/or SameBoy (CGB palette/timing accuracy). BGB is a
   solid *secondary CI cross-check* if a Wine-based check is acceptable
   (`bgb -hf -screenonexit shot.png -autoexit rom`).
5. **Don't** adopt WLA DX, Z88DK, GBDK-2020, or original GBDK unless the
   project grows multi-bank C code — re-evaluate GBDK-2020 (4.5.0) at that
   point.

### Sources
- RGBDS releases: [v0.9.1](https://github.com/gbdev/rgbds/releases/tag/v0.9.1), [v0.9.2](https://github.com/gbdev/rgbds/releases/tag/v0.9.2), [v0.9.4](https://github.com/gbdev/rgbds/releases/tag/v0.9.4), [v1.0.0](https://github.com/gbdev/rgbds/releases/tag/v1.0.0), [v1.0.3](https://github.com/gbdev/rgbds/releases/tag/v1.0.3), [v1.0.4](https://github.com/gbdev/rgbds/releases/tag/v1.0.4)
- WLA DX: [project page](https://www.villehelin.com/wla.html), [successor GitHub](https://github.com/midnightcowboy/wla-dx)
- GBDK-2020: [repo](https://github.com/gbdk-2020/gbdk-2020), [release notes](https://gbdk.org/docs/api/docs_releases.html); original GBDK history: [GBDevWiki](https://gbdev.gg8.se/wiki/articles/GBDK)
- Z88DK: [repo](https://github.com/z88dk/z88dk) (v2.4, 2025-10-02)
- asm8: [repo](https://github.com/nufuto/asm8); gameboy-asm: [repo](https://github.com/AstatinChan/gameboy-asm)
- mGBA: [repo](https://github.com/mgba-emu/mgba); headless CI pattern: [mcejp's GBA benchmarking post](https://mcejp.github.io/2023/10/30/gba-benchmarking.html)
- GBEmulatorShootout: [repo](https://github.com/gbdev/GBEmulatorShootout/)
- BGB: [manual (headless flags)](https://bgb.bircd.org/manual.html), [version history](https://bgb.bircd.org/history.html)
- Emulicious: [site](https://emulicious.net/), [news](https://emulicious.net/category/news/), [VS Code debugger extension](https://github.com/Calindro/emulicious-debugger)
- VBA-M: [repo](https://github.com/visualboyadvance-m/visualboyadvance-m)
- SameBoy: [downloads](https://sameboy.github.io/downloads/), [repo](https://github.com/LIJI32/SameBoy)
- PyBoy: [repo](https://github.com/Baekalfen/PyBoy), [API docs](https://docs.pyboy.dk/api/pyboy.html)
- gambatte-terminal: [repo](https://github.com/vxgmichel/gambatte-terminal)
- gbrom: [repo](https://github.com/mattmuroya/gbrom); gbfix: [repo](https://github.com/elseyf/gbfix)
