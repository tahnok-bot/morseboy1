# morseboy1 — Game Boy / Game Boy Color starter (RGBDS)
#
# Targets:
#   make        build the ROM          -> build/morseboy1.gbc
#   make test   smoke-test in mGBA headless
#   make web    run the mGBA WASM web emulator (serves build/ + web/)
#   make site   assemble the deployable static site -> web/_site/
#   make clean  remove build artifacts

NAME      := morseboy1
BUILD     := build
ROM_RAW   := $(BUILD)/$(NAME).raw
ROM       := $(BUILD)/$(NAME).gbc
TOOLS     := tools
SITE      := web/_site
MGBA_DIST := node_modules/@thenick775/mgba-wasm/dist

RGBASM   := rgbasm
RGBLINK  := rgblink
RGBFIX   := rgbfix
MGBA     := $(TOOLS)/mgba-headless

ASMFLAGS := -i include
ASM      := src/main.asm
OBJ      := $(BUILD)/main.o

.PHONY: all rom test web site clean

all: rom

rom: $(ROM)

$(BUILD):
	mkdir -p $(BUILD)

$(OBJ): $(ASM) include/hardware.inc linker/script.ld | $(BUILD)
	$(RGBASM) $(ASMFLAGS) -o $@ $<

$(ROM_RAW): $(OBJ) linker/script.ld
	$(RGBLINK) -t -l linker/script.ld -o $@ $<

$(ROM): $(ROM_RAW)
	# pad to 32 KB, fix the Nintendo logo, set header + ROM checksums
	$(RGBFIX) -v -p 0 -o $@ $<

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

web: rom
	node web/server.mjs

site: rom
	mkdir -p $(SITE)
	cp web/index.html $(SITE)/index.html
	cp web/_headers $(SITE)/_headers
	cp $(MGBA_DIST)/mgba.js $(MGBA_DIST)/mgba.wasm $(SITE)/
	cp $(ROM) $(SITE)/morseboy1.gbc
	@echo "static site ready in $(SITE)/ (COOP/COEP via _headers — see README)"

clean:
	rm -rf $(BUILD) $(SITE)
