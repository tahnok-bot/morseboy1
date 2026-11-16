# Tool chain upgrade plan

Scope: apply the recommendations from `docs/research/toolchains.md` and
`docs/research/linting.md` to this repo. Core moves: **pin RGBDS 1.0.4 in CI,
enable strict diagnostics in the build, add a `make check` gate**. Per current
instruction, **PyBoy is deferred** (not part of this plan).

> **Status (2026-11-16):** Phases 2 and 4 done (strict `rgbasm` flags, `rgblink -d`,
> `rgbfix -m ROM`, the `make check` gate, README + source comment updated). Phases
> 1 and 3 (CI) deferred by request. Because the workflow still pins 0.9.3, the
> Makefile stays **0.9.3-compatible**: strict `-W` flags are on `rgbasm` only
> (rgblink/rgbfix accept `-W` from 0.9.4 — add them there once the CI pin moves).

Status of every verification below: run against the current tree on
2026-11-16 in this environment (RGBDS 1.0.4 local, Node v22.23.4), repo files
untouched.

## Current state (verified)

| Item | State |
|---|---|
| Local RGBDS (`/usr/local/bin`) | **already v1.0.4** |
| CI pin (`.gitea/workflows/pages.yaml`) | `RGBDS_VERSION: "0.9.3"` ← stale |
| README / `src/main.asm` header comment | still say "RGBDS 0.9.x" |
| `rgbasm -Weverything -Wtruncation=1` on `src/main.asm` (1.0.4) | **clean, rc=0, zero warnings** |
| `rgblink -Weverything -Wtruncation=1 -d -t` (DMG mode) | **links, rc=0** |
| `rgbfix -Weverything -v -p 0` + no-change header assertion (`-f lhg` + `cmp`) | **header already correct** |
| 1.0.0 removals in source (`ld [c]`, `ldh [$xx]`, `STRIN`/`STRSUB`/`CHARSUB`, multi-char strings as numbers) | **none found** — no `-Wno-obsolete` bridge needed |
| `rgbds-linux-x86_64.tar.xz` asset for v1.0.4 (GitHub API) | **exists** — CI download path unchanged |

Migration risk is therefore minimal; the upgrade is pin + flags + CI gate.

---

## Phase 1 — Pin RGBDS 1.0.4 in CI (core)

**File:** `.gitea/workflows/pages.yaml`

- Change `RGBDS_VERSION: "0.9.3"` → `RGBDS_VERSION: "1.0.4"`.
- No other workflow change needed for this step: the x86_64 tarball download
  line (`rgbds-linux-x86_64.tar.xz`) is identical for 1.0.4 (asset verified),
  and the apt fallback for non-x86_64 runners is unchanged.

**Verify:** push to a test branch / `workflow_dispatch`; confirm the
`rgbasm --version && rgblink --version && rgbfix --version` step prints 1.0.4
and `make site` + `make test` pass.

Why: the research notes call 1.0.4 the "most stable version ever"
(rgblink placement-algorithm overhaul, `-Wtruncation` for `jr`), and 0.9.4+ is
the minimum where `rgblink`/`rgbfix`/`rgbgfx` accept `-W` at all — Phase 2
needs it.

## Phase 2 — Strict diagnostics + `make check` in the Makefile (core)

**File:** `Makefile`

Apply the pokecrystal-style strict flags (verified clean on 1.0.4) and add the
check targets from `linting.md` §8:

1. **Strict flags on the real build rules** (costs nothing — verified clean):
   - `ASMFLAGS  += -Weverything -Wtruncation=1`
   - link rule: `$(RGBLINK) -Weverything -Wtruncation=1 -d -t -l linker/script.ld …`
     (adding `-d` makes the DMG-compatibility guarantee part of *every* build,
     not just a check)
   - fix rule: `$(RGBFIX) -Weverything -v -m ROM -p 0 -o $@ $<`
     (`-m ROM` documents the no-MBC intent and guards the cartridge-type byte)
2. **New targets** (exact set from the research doc, all verified passing):
   - `check` → aggregated CI gate: `check-asm check-link check-header check-rom check-shell check-js`
   - `check-asm` → assemble with `-Weverything -Wtruncation=1`, fail on any warning
   - `check-link` → `rgblink -d -t` (proves the "CGB-compatible" ROM uses no CGB-only memory)
   - `check-header` → `rgbfix -f lhg rom -o tmp && cmp` — a *no-change* assertion that logo/checksums are already correct (never re-fix)
   - `check-rom` → delegates to `test` (existing mGBA headless smoke test)
   - `check-shell` → `shellcheck` if installed, else notice + skip (it is not installed here)
   - `check-js` → `node --check web/server.mjs` (verified passing)
3. **Update the target list comment** at the top of the Makefile to include `make check`.

Keep `test` exactly as-is (the `timeout 2` / exit-124 pattern is correct).

**Verify locally:** `make clean && make && make test && make check` all pass.

## Phase 3 — CI gate (core)

**File:** `.gitea/workflows/pages.yaml`

- Insert a `make check` step after "Build ROM + static site" and before
  "Smoke-test ROM" (check-rom re-runs the smoke test, so the existing
  "Smoke-test ROM" step may be dropped — or kept; both are cheap).
- No secrets or new runners needed.

**Verify:** workflow run shows `check-asm`, `check-link`, `check-header`,
`check-rom`, `check-js` green (check-shell skipped with notice) before deploy.

## Phase 4 — Doc updates (core, cosmetic)

- `README.md`: prereqs line "RGBDS 0.9.x" → "RGBDS 1.0.4 (pinned in CI)";
  add `make check` to the Quick-start block; build-pipeline bullets unchanged
  (same three tools).
- `src/main.asm` header comment: "RGBDS 0.9.x" → "RGBDS 1.0.4".
- Optional one-liner in README "Extending": strict flags are on, new code
  must stay warning-free.

## Phase 5 — Optional hardening (pick what's wanted; none blocking)

All from the research docs, all low-cost, all independently switchable:

| Item | What | Source |
|---|---|---|
| `roms.sha1` reproducibility pin | `sha256sum` of `build/morseboy1.gbc` + `make compare` target (pokecrystal pattern); update the file when the ROM intentionally changes | linting.md §1.4, §8 |
| `rgbasm -M` dependency generation | replace the hand-listed `include/hardware.inc` prerequisite in `$(OBJ)` with generated deps (robustness only; nothing breaks if skipped) | linting.md §1.1 |
| `mgbdis` round-trip target | optional `make roundtrip` (disassemble → rebuild → `cmp`); skip if `mgbdis` not installed. **Not** `rgbdis` — that was never part of RGBDS (negative finding, verified) | linting.md §5 |
| `check-swit` SWI/register unit-test hook | only meaningful once the ROM itself calls SWI and sets a result register; future ROM-side change, not part of this upgrade | linting.md §3.1, §8 |
| Third-party suite smoke runs | `make check-suite`: run `dmg-acid2` / Blargg `cpu_instrs` prebuilts under `tools/mgba-headless` (smoke-level only — validates the emulator, not this ROM) | linting.md §3.2 |
| `-p 0xFF` pad value | rgbfix man page recommends `0xFF` over `0` (flash-write speed, avoids NOP slides into VRAM); behaviorally inert here but changes the ROM bytes → do only with the sha1 pin in place | linting.md §1.3 |
| gbrom independent header check | `pip install gbrom` + report step; redundant with `check-header`, additive only | toolchains.md §4 |

## Deferred (explicitly out of scope for now)

- **PyBoy assertion-based smoke test** — deferred per current instruction.
  Everything needed is already in place to revisit later (`.venv` with PyBoy
  2.9.0, `tools/mgba-headless` `-S`/`-R` hooks, header map in `linker/script.ld`).
- **Emulicious / SameBoy / BGB / VBA-M** — dev-time/manual tools only per the
  research verdicts; no CI or repo changes.
- **WLA DX, Z88DK, GBDK-2020 / original GBDK, asm8, gameboy-asm, gbfix** —
  rejected by both research docs; re-evaluate GBDK-2020 only if the project
  grows multi-bank C code.
- **"GBDK checkasm"** — negative finding: no such GB tool exists (host-CPU
  tool, unrelated); the GB equivalent is the strict RGBDS flags in Phase 2.

## Definition of done

1. CI installs and reports RGBDS 1.0.4; `make site`/`make test` still pass.
2. `make check` exists and passes (asm strict, DMG-mode link, header
   no-change assertion, mGBA smoke, JS syntax check).
3. A workflow push to `main` runs `make check` and blocks deploy on failure.
4. README and source comments reflect 1.0.4; no behavior change to the ROM
   itself (same 32 KB build, same logo/checksums — provable via `check-header`).

## Rollback

Each phase is independent. Rollback = revert the phase's commit: the pin is a
one-line `env:` change, the Makefile changes are additive flags/targets, and
the CI gate is one step. No ROM-side changes in Phases 1–4, so the built
`morseboy1.gbc` is byte-identical before/after (Phase 6's `-p 0xFF` is the
only exception and is gated behind the sha1 pin).
