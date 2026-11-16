; morseboy1 — rgblink linker script (RGBDS 0.9.x line-based format)
;
; Single-bank ROM (ROM0, < 32 KB). Sections are placed in ROM0 in this
; order; the entry point is 0x0150 (written by the "boot" section).

ROM0
    ORG $0000
    "boot"                ; 0x0000: entry point + Nintendo logo (ends at 0x0134)
    ORG $0134
    "header"              ; 0x0134: cartridge header (ends at 0x0150)
    ORG $0150
    "reset"               ; 0x0150: entry code
    "main"                ; code
    "data"                ; tile art, text row
