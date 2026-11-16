;******************************************************************************
; morseboy1 — Game Boy (DMG) starter demo (RGBDS 0.9.x+)
;
; A minimal single-bank ROM that:
;   * targets DMG only (CGB flag $00 in the header at 0x0143, no palette code)
;   * renders "HELLO GBC!" from BG tiles
;   * uses the classic $E0 green BGP
;
; Build:   make          -> build/morseboy1.gb
; Smoke:   make test     -> runs the ROM a couple of seconds in mGBA headless
; Browse:  make web      -> node web/server.mjs  (mGBA WASM emulator)
;******************************************************************************

INCLUDE "hardware.inc"

; -----------------------------------------------------------------------------
; Constants
; -----------------------------------------------------------------------------
def N_TILES equ 9       ; 1 blank + 8 glyphs

; Copy bytes from ROM (de) to RAM (hl), SM83-safe (no LDIR on the Game Boy)
MACRO copy_dir
    ld de, \1
    ld hl, \2
    ld bc, \3
:
    ld a, [de]
    ld [hl], a
    inc de
    inc hl
    dec bc
    ld a, b
    or a, c
    jr nz, :-
ENDM

; -----------------------------------------------------------------------------
; "boot" — 0x0100: entry point + Nintendo logo (0x0104, 48 bytes)
; -----------------------------------------------------------------------------
SECTION "boot", ROM0
    DS 0x0100               ; 0x0000-0x00FF: unused
    jp 0x0150               ; 0x0100: entry — the BIOS jumps here and executes code
    DS 1                    ; 0x0103 (pad to logo at 0x0104)
    db $CE,$ED,$66,$66,$CC,$0D,$00,$0B   ; Nintendo logo (0x0104, 48 bytes)
    db $03,$73,$00,$83,$00,$0C,$00,$0D   ; (full BIOS logo, as stored in
    db $00,$08,$11,$1F,$88,$89,$00,$0E   ;  the hardware — matches rgbfix)
    db $DC,$CC,$6E,$E6,$DD,$DD,$D9,$99
    db $BB,$BB,$67,$63,$6E,$0E,$EC,$CC
    db $DD,$DC,$99,$9F,$BB,$B9,$33,$3E

; -----------------------------------------------------------------------------
; "header" — 0x0134..0x014F (placed by the linker right after "boot")
;   0x0134-0x0143  title (16 bytes; last byte is the CGB flag)
;   0x013F-0x0142  game ID (overlaps the title)
;   0x0143         CGB flag: $00 = DMG only, $80 = DMG+CGB, $C0 = CGB only
;   0x0144-0x0145  new licensee code
;   0x0146         SGB flag
;   0x0147         cartridge type
;   0x0148         ROM size
;   0x0149         RAM size
;   0x014A         destination code
;   0x014B         old licensee code
;   0x014C         version
;   0x014D         header checksum (rgbfix fills)
;   0x014E-0x014F  ROM checksum (rgbfix fills)
; -----------------------------------------------------------------------------
SECTION "header", ROM0
    db "MORSEBOY1  "        ; 0x0134-0x013E: game title (11 bytes)
    db "MB01"               ; 0x013F-0x0142: game ID
    db $00                  ; 0x0143: CGB flag = DMG only (16th title byte)
    db $33, $80             ; 0x0144-0x0145: new licensee code
    db $00                  ; 0x0146: SGB flag
    db $00                  ; 0x0147: cartridge type (ROM only)
    db $00                  ; 0x0148: ROM size (32 KB)
    db $00                  ; 0x0149: RAM size (none)
    db $01                  ; 0x014A: destination code (not Japan)
    db $33                  ; 0x014B: old licensee code (Nintendo)
    db $00                  ; 0x014C: version
    DS 3, $00               ; 0x014D-0x014F: checksums (rgbfix fills)

; -----------------------------------------------------------------------------
; "reset" — 0x0150
; -----------------------------------------------------------------------------
SECTION "reset", ROM0
    ld sp, $FFFE
    di
    jp Init

; -----------------------------------------------------------------------------
; "main" — code
; -----------------------------------------------------------------------------
SECTION "main", ROM0

Init:
    ; -- DMG: classic green palette (what the boot ROM would have set) --
    ld a, $E0
    ld [rBGP], a

    ; -- Copy tile data to VRAM (tile 0 = blank, 1..8 = glyphs) --
    copy_dir tiles, TILEBLOCK0, (N_TILES * 8)

    ; -- Copy the text row into the background map (row 4, x=5..14) --
    copy_dir text_row, ($9800 + (4 * 32) + 5), 10

    ; -- Turn the LCD on: BG + OBJ enabled, 8x8 tiles --
    ld a, LCDC_ON | LCDC_BLOCK01 | LCDC_BG_9800 | LCDC_OBJ_8 | LCDC_OBJ_ON | LCDC_BG_ON
    ld [rLCDC], a

FrameLoop:
    ; -- Wait for VBlank (STAT bit 3 = $08) --
    ld a, [rSTAT]
    and a, $08
    or a, a
    jr z, FrameLoop
    ; -- In VBlank: idle until the next frame --
    jr FrameLoop

; -----------------------------------------------------------------------------
; "data" — tile art, text row
; -----------------------------------------------------------------------------
SECTION "data", ROM0

tiles:
    DS 8, 0                             ; 0: blank (space)
    db $88,$88,$88,$F8,$88,$88,$88,$00  ; 1: H
    db $F8,$80,$80,$F0,$80,$80,$F8,$00  ; 2: E
    db $80,$80,$80,$80,$80,$80,$F8,$00  ; 3: L
    db $70,$88,$88,$88,$88,$88,$70,$00  ; 4: O
    db $70,$80,$80,$B8,$88,$88,$70,$00  ; 5: G
    db $F0,$88,$88,$F0,$88,$88,$F0,$00  ; 6: B
    db $70,$80,$80,$80,$80,$80,$70,$00  ; 7: C
    db $20,$20,$20,$20,$20,$00,$20,$00  ; 8: !

text_row:                               ; H E L L O   G B C !
    db 1, 2, 3, 3, 4, 0, 5, 6, 7, 8

; No "bss" section: this ROM keeps no WRAM variables.
