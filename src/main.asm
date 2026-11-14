;******************************************************************************
; morseboy1 — Game Boy / Game Boy Color starter demo (RGBDS 0.9.x)
;
; A minimal single-bank ROM that:
;   * targets both DMG and CGB (CGB flag 0x80 in the header at 0x0143)
;   * renders "HELLO GBC!" from BG tiles
;   * on CGB: cycles the background color (BCP/OCP palette animation)
;   * on DMG: uses the classic $E0 green BGP
;
; Build:   make          -> build/morseboy1.gbc
; Smoke:   make test     -> runs the ROM a couple of seconds in mGBA headless
; Browse:  make web      -> node web/server.mjs  (mGBA WASM emulator)
;******************************************************************************

INCLUDE "hardware.inc"

; -----------------------------------------------------------------------------
; Constants
; -----------------------------------------------------------------------------
def N_TILES equ 9       ; 1 blank + 8 glyphs
def N_CYCLE equ 8       ; number of background colors in the cycle
def FRAMES_PER_COLOR equ 8     ; frame count between palette steps

; 16-bit CGB colors: bits 0-4 blue, 5-9 green, 10-14 red
def PAL_BG0  equ (0  << 10) | (8  << 5) | 24   ; deep blue
def PAL_TXT  equ (31 << 10) | (31 << 5) | 31   ; white
def PAL_OB0  equ (31 << 10) | (31 << 5) | 31   ; white (for future sprites)
def PAL_OB1  equ (0  << 10) | (0  << 5) | 0    ; black

; Background colors cycled every FRAMES_PER_COLOR frames (CGB only)
def CYC_0 equ (0  << 10) | (8  << 5) | 24   ; deep blue
def CYC_1 equ (12 << 10) | (0  << 5) | 24   ; deep purple
def CYC_2 equ (24 << 10) | (4  << 5) | 4    ; dark red
def CYC_3 equ (0  << 10) | (20 << 5) | 8    ; dark green
def CYC_4 equ (0  << 10) | (24 << 5) | 22   ; dark teal
def CYC_5 equ (24 << 10) | (12 << 5) | 0    ; dark orange
def CYC_6 equ (10 << 10) | (10 << 5) | 14   ; dark slate
def CYC_7 equ (4  << 10) | (4  << 5) | 6    ; near black

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

; Write one 16-bit CGB palette via the BCP registers.
; \1 = palette number (0-7 = BG, 8-15 = OBJ), \2 = 16-bit color value
MACRO write_cgb_pal
    ld a, (\1 << 1)
    ld [rBCPS], a
    ld a, (\2 & $FF)
    ld [rBCPD], a
    ld a, (\2 >> 8)
    ld [rBCPD], a
ENDM

; -----------------------------------------------------------------------------
; "boot" — 0x0100: entry point + Nintendo logo (0x0104, 48 bytes)
; -----------------------------------------------------------------------------
SECTION "boot", ROM0
    DS 0x0100               ; 0x0000-0x00FF: unused
    jp 0x0150               ; 0x0100: entry — the BIOS jumps here and executes code
    DS 1                    ; 0x0103 (pad to logo at 0x0104)
    db $CE,$ED,$66,$66,$CC,$0D,$00,$0B   ; Nintendo logo (0x0104, 48 bytes)
    db $03,$73,$00,$83,$00,$0C,$00,$0D   ; as stored in the CGB BIOS
    db $00,$08,$11,$1F,$88,$89,$00,$0E
    db $DC,$CC,$6E,$E6,$DD,$DD,$D9,$99
    db $BB,$BB,$67,$63,$6E,$0E,$EC,$CC
    db $DD,$DC,$99,$9F,$BB,$B9,$33,$3E

; -----------------------------------------------------------------------------
; "header" — 0x0134..0x014F (placed by the linker right after "boot")
;   0x0134-0x0143  title (16 bytes; last byte is the CGB flag)
;   0x013F-0x0142  game ID (overlaps the title)
;   0x0143         CGB flag: $80 = DMG+CGB, $C0 = CGB only
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
    db $80                  ; 0x0143: CGB flag = DMG + CGB (16th title byte)
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
    ; -- Detect CGB: KEY1 ($FF4D) reads back $FE on CGB, $7E on DMG --
    ld a, 0
    ld [rKEY1], a
    ld a, [rKEY1]
    and a, $FE
    cp a, $FE
    ld a, 0
    jr nz, .dmg
    ld a, 1
.dmg
    ld [is_cgb], a

    ; -- DMG: classic green palette (what the boot ROM would have set) --
    ;    On CGB this hits BGPAL7_H, which we never use: harmless.
    ld a, $E0
    ld [rBGP], a

    ; -- CGB: palettes 0 (background) and 1 (text) via BCP/OCP --
    ld a, [is_cgb]
    or a, a
    jr z, .skip_cgb_pals
    write_cgb_pal 0, PAL_BG0   ; BGPAL0 = background color
    write_cgb_pal 1, PAL_TXT   ; BGPAL1 = text color
    write_cgb_pal 8, PAL_OB0   ; OBPAL0 (for future sprites)
    write_cgb_pal 9, PAL_OB1   ; OBPAL1
.skip_cgb_pals

    ; -- Copy tile data to VRAM (tile 0 = blank, 1..8 = glyphs) --
    copy_dir tiles, TILEBLOCK0, (N_TILES * 8)

    ; -- Copy the text row into the background map (row 4, x=5..14) --
    copy_dir text_row, ($9800 + (4 * 32) + 5), 10

    ; -- Zero the frame/palette counters --
    ld a, 0
    ld [frames], a
    ld [pal], a

    ; -- Turn the LCD on: BG + OBJ enabled, 8x8 tiles --
    ld a, LCDC_ON | LCDC_BLOCK01 | LCDC_BG_9800 | LCDC_OBJ_8 | LCDC_OBJ_ON | LCDC_BG_ON
    ld [rLCDC], a

FrameLoop:
    ; -- Wait for VBlank (STAT bit 3 = $08) --
    ld a, [rSTAT]
    and a, $08
    or a, a
    jr z, FrameLoop

    ; -- Every FRAMES_PER_COLOR frames, step the background color (CGB only) --
    ld a, [is_cgb]
    or a, a
    jr z, .tick
    ld a, [frames]
    cp a, (FRAMES_PER_COLOR - 1)
    jr nz, .tick
    ld a, [pal]
    inc a
    and a, (N_CYCLE - 1)
    ld [pal], a
    ; BGPAL0 = BCP index 0; index into the color table (2 bytes per color)
    ld l, a
    ld h, 0
    add hl, hl
    ld de, cycle_colors
    add hl, de
    ld c, [hl]              ; low byte of the color
    inc hl
    ld b, [hl]              ; high byte of the color
    ; BGPAL0 = BCP index 0, no auto-increment
    ld a, 0
    ld [rBCPS], a
    ld a, c
    ld [rBCPD], a
    ld a, b
    ld [rBCPD], a
    ld a, 0
    ld [frames], a
.tick
    ld a, [frames]
    inc a
    ld [frames], a
    jr FrameLoop

; -----------------------------------------------------------------------------
; "data" — tile art, text row, palette cycle
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

cycle_colors:
    dw CYC_0, CYC_1, CYC_2, CYC_3
    dw CYC_4, CYC_5, CYC_6, CYC_7

; -----------------------------------------------------------------------------
; "bss" — zero-initialized WRAM variables
; -----------------------------------------------------------------------------
SECTION "bss", WRAM0
    is_cgb: DS 1
    frames: DS 1
    pal:    DS 1
