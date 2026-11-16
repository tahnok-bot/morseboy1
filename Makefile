# morseboy1 — Game Boy (DMG) starter (RGBDS)
#
# Targets:
#   make        build the ROM          -> build/morseboy1.gb
#   make test   smoke-test in mGBA headless
#   make check  strict diagnostics + header assertion + smoke test
#   make web    run the mGBA WASM web emulator (serves build/ + web/)
#   make clean  remove build artifacts

NAME      := morseboy1
BUILD     := build
ROM_RAW   := $(BUILD)/$(NAME).raw
ROM       := $(BUILD)/$(NAME).gb
TOOLS     := tools

RGBASM   := rgbasm
RGBLINK  := rgblink
RGBFIX   := rgbfix
MGBA     := $(TOOLS)/mgba-headless

# Strict diagnostics (pokecrystal style; the source is warning-free under them).
# Requires RGBDS >= 0.9.4: rgblink/rgbfix/rgbgfx only accept -W from 0.9.4 on.
ASMFLAGS  := -i include -Weverything -Wtruncation=1
LINKFLAGS := -Weverything -Wtruncation=1
FIXFLAGS  := -Weverything
ASM      := src/main.asm
OBJ      := $(BUILD)/main.o

.PHONY: all rom test web clean

all: rom

rom: $(ROM)

$(BUILD):
	mkdir -p $(BUILD)

$(OBJ): $(ASM) include/hardware.inc linker/script.ld | $(BUILD)
	$(RGBASM) $(ASMFLAGS) -o $@ $<

$(ROM_RAW): $(OBJ) linker/script.ld
	# -d: DMG mode — the ROM must not use CGB-only memory (VRAM bank 1, ...)
	$(RGBLINK) $(LINKFLAGS) -d -t -l linker/script.ld -o $@ $<

$(ROM): $(ROM_RAW)
	# pad to 32 KB, fix the Nintendo logo, set header + ROM checksums;
	# -m ROM documents the no-MBC cartridge type explicitly
	$(RGBFIX) $(FIXFLAGS) -v -m ROM -p 0 -o $@ $<

test: rom
	# run the ROM for a couple of seconds; mGBA exits non-zero on invalid ROMs,
	# so exit code 124 (timeout) means it booted and ran fine
	@code=0; timeout 2 $(MGBA) $(ROM) > /tmp/morseboy1-mgba.log 2>&1 || code=$$?; \
	if [ $$code -eq 124 ] || [ $$code -eq 0 ]; then \
		if [ -s /tmp/morseboy1-mgba.log ]; then echo "mGBA logged:"; head -5 /tmp/morseboy1-mgba.log; fi; \
		echo "mGBA headless: ROM ran without errors"; \
	else \
		echo "mGBA headless failed (exit $$code):"; head -10 /tmp/morseboy1-mgba.log; \
		exit $$code; \
	fi

# --- checks (aggregated gate: make check) -----------------------------------

.PHONY: check check-asm check-link check-header check-rom check-shell check-js

check: check-asm check-link check-header check-rom check-shell check-js

# Assemble with the full warning set; fail on any warning/error.
check-asm: | $(BUILD)
	$(RGBASM) $(ASMFLAGS) -o $(BUILD)/check.o $(ASM)

# Link in DMG mode: proves the ROM uses no CGB-only memory.
check-link: check-asm
	$(RGBLINK) $(LINKFLAGS) -d -t -l linker/script.ld -o $(BUILD)/check.raw $(BUILD)/check.o

# Header must already be correct: rgbfix must not need to change anything
# (logo 0x104-0x133, header checksum 0x14D, global checksum 0x14E-0x14F).
check-header: rom
	$(RGBFIX) $(FIXFLAGS) -f lhg $(ROM) -o $(BUILD)/check-header.gb
	@cmp -s $(ROM) $(BUILD)/check-header.gb || \
		{ echo "header check: logo/checksums need fixing (rgbfix -v)"; exit 1; }

# Existing mGBA headless smoke test (timeout 2; 124 = booted & running).
check-rom: test

# Optional: shellcheck on any *.sh; degrades to a notice if not installed.
check-shell:
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "check-shell: shellcheck not installed, skipping"; \
	elif [ -z "$$(find . -name '*.sh' -not -path './node_modules/*')" ]; then \
		echo "check-shell: no *.sh files, nothing to check"; \
	else \
		shellcheck -S warning $$(find . -name '*.sh' -not -path './node_modules/*'); \
	fi

# Zero-dependency JS syntax check.
check-js:
	node --check web/server.mjs

web: rom
	node web/server.mjs

clean:
	rm -rf $(BUILD)
