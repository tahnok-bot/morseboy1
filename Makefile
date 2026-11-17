# morseboy1 — Game Boy (DMG) demo built with GBDK-2020 (C)
#
# Targets:
#   make        build the ROM          -> build/morseboy1.gb
#   make test   smoke-test in mGBA headless
#   make check  build + header assertion + smoke test
#   make web    run the mGBA WASM web emulator (serves build/ + web/)
#   make clean  remove build artifacts
#
# GBDK is installed at ~/gbdk-2020 by default; override with GBDK_ROOT=...

NAME      := morseboy1
BUILD     := build
ROM       := $(BUILD)/$(NAME).gb
TOOLS     := tools

GBDK_ROOT ?= $(HOME)/gbdk-2020
LCC       := $(GBDK_ROOT)/bin/lcc
MGBA      := $(TOOLS)/mgba-headless

CSOURCES  := src/main.c

# Explicit platform selection (per GBDK-2020 docs; lcc's default is the same).
# Verified: adding -Wa-l/-Wl-m/-Wl-j only emits a .noi symbol file and does
# not change the ROM bytes.
LCCFLAGS  := -msm83:gb

.PHONY: all rom test check check-header check-shell check-js web screenshot clean venv

all: rom

rom: $(ROM)

$(BUILD):
	mkdir -p $(BUILD)

$(ROM): $(CSOURCES) | $(BUILD)
	@if [ ! -x "$(LCC)" ]; then \
		echo "GBDK not found: $(LCC)"; \
		echo "  install GBDK-2020 to $(GBDK_ROOT) or pass GBDK_ROOT=/path/to/gbdk-2020"; \
		exit 1; \
	fi
	$(LCC) $(LCCFLAGS) -o $@ $(CSOURCES)
	# GBDK's link step leaves the DMG header incomplete; patch logo, flag,
	# title and checksums so the ROM boots on real hardware (rgbfix's job).
	.venv/bin/python tools/fix_header.py $@ $(NAME)

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

check: rom check-header check-rom check-shell check-js

# Validate the post-link DMG header: 48-byte Nintendo logo at 0x104..0x133,
# CGB flag 0x00 (DMG-only) at 0x143, header + global checksums.
check-header: rom
	.venv/bin/python tools/check_header.py $(ROM)

# PyBoy venv used by tools/screenshot.py (check_header.py is stdlib-only).
venv:
	python3 -m venv .venv
	.venv/bin/pip install -q pyboy pillow

# PyBoy headless pixel capture -> build/morseboy1_frame.png
screenshot: rom
	@if [ ! -x .venv/bin/python ]; then \
		echo "screenshot: .venv missing — run 'make venv' first"; exit 1; \
	fi
	.venv/bin/python tools/screenshot.py $(ROM)

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
