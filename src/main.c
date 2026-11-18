/* morseboy1 — minimal Game Boy (DMG) demo built with GBDK-2020.
 *
 * Start screen: shows the letters "s o s" with their Morse code
 * (... --- ...) beneath each, using the built-in 8x8 console font.
 * Press start to enter the reference screen.
 *
 * Reference screen: shows one alphabet letter with its Morse code
 * beneath it. Left/right cycles through all 26 letters (hold to keep
 * cycling); start returns to the start screen.
 *
 * Morse keyer: holding the A button sounds a ~500 Hz square wave (a
 * classic CW keyer tone); the tone lasts exactly as long as A is held.
 *
 * Start is debounced: the DMG joypad auto-repeats a held button (33f
 * initial delay, then a 9f cycle), so a press edge alone would still
 * toggle rapidly while Start is held. A press is therefore only accepted
 * when the button has been fully released for START_DEBOUNCE frames.
 */

#include <gbdk/platform.h>
#include <gbdk/console.h>
#include <stdio.h>

/* --- International Morse code for A..Z (index 0 = 'A', 25 = 'Z') ------- */
static const char *const MORSE[26] = {
    ".-",   /* A */
    "-...", /* B */
    "-.-.", /* C */
    "-..",  /* D */
    ".",    /* E */
    "..-.", /* F */
    "--.",  /* G */
    "....", /* H */
    "..",   /* I */
    ".---", /* J */
    "-.-",  /* K */
    ".-..", /* L */
    "--",   /* M */
    "-.",   /* N */
    "---",  /* O */
    ".--.", /* P */
    "--.-", /* Q */
    ".-.",  /* R */
    "...",  /* S */
    "-",    /* T */
    "..-",  /* U */
    "...-", /* V */
    ".--",  /* W */
    "-..-", /* X */
    "-.--", /* Y */
    "--..", /* Z */
};

/* --- Screens -----------------------------------------------------------
 *
 * Both screens use the same 20x18 character grid layout as the original
 * start screen: row 5 = letters, row 6 = Morse code beneath them.
 */
static void draw_sos(void) {
    cls();
    gotoxy(5, 5);
    printf("s   o   s");
    gotoxy(4, 6);
    printf("... --- ...");
    gotoxy(5, 8);
    printf("morseboy1");
}

static void draw_alphabet(uint8_t idx) {
    const char *code = MORSE[idx];
    uint8_t len = 0;
    while (code[len]) len++;
    cls();
    // Letter on the right-middle column (the 20-column grid has no exact
    // center; column 10 looks centered for a single glyph).
    gotoxy(10, 5);
    putchar('A' + idx);
    // Code centered under the letter, small position counter top-left.
    gotoxy((uint8_t)(10 - (len - 1) / 2), 6);
    printf("%s", code);
    gotoxy(0, 0);
    printf("%d/26", idx + 1);
}

/* --- Morse tone (sound channel 1, square wave) ---------------------------
 *
 * Channel 1's 11-bit period value d (NR13 = low 8 bits, NR14 bits 0..2)
 * gives a tone frequency of 131072 / (2048 - d) Hz: the period divider
 * is clocked at 1048576 Hz and the pulse wave is 8 samples long (Pan
 * docs). d = 1786 (0x6FA) gives 131072/262, about 500 Hz — a classic
 * Morse keyer pitch. (The higher the period value, the higher the
 * frequency.)
 *
 * Hardware quirks (Pan docs):
 *  - The APU is off by default and the sound registers are read-only
 *    until it is powered on by writing NR52 with bit 7 set. tone_on()
 *    therefore raises that bit first, then configures the channel.
 *    tone_off() powers the APU off, which stops channel 1 immediately
 *    and clears the channel state for the next press.
 *  - A channel is enabled by writing NR14 with bit 7 (the trigger) set;
 *    NR52's "channel on" bits are read-only. With the length timer
 *    disabled (NR14 bit 6 = 0) the tone continues until the APU is
 *    powered off, so one trigger per key press is enough — the tone
 *    lasts exactly as long as A is held.
 *  - NR12 sets a constant full volume (envelope disabled); the trigger
 *    reloads the volume from NR12 on each key press.
 */
#define TONE_NR11      0x30   /* NR11: 50% duty; length field unused (timer disabled) */
#define TONE_NR12      0xF0   /* NR12: VVVV=7 full volume, no envelope (EPPP=0) */
#define TONE_NR13      0xFA   /* NR13: period low  (d = 0x6FA = 1786, ~500 Hz) */
#define TONE_NR14      0x86   /* NR14: trigger (bit 7) + length off (bit 6) + period high 0b110 */
#define TONE_PAN       0x11   /* NR51: channel 1 to both speakers */
#define TONE_MASTER    0x77   /* NR50: master volume 7 left, 7 right */
#define TONE_NR52_ON   0x80   /* NR52: APU power on (bit 7) */
#define TONE_NR52_OFF  0x00   /* NR52: APU power off */

/* Start debounce: minimum frames the button must read as released before
 * a press edge is accepted. Must exceed the hardware repeat cycle (9f),
 * whose internal release phase is far shorter. */
#define START_DEBOUNCE 12

static void tone_on(void) {
    NR52_REG = TONE_NR52_ON;   /* power the APU on; other sound regs are read-only until this */
    NR10_REG = 0x00;           /* no period sweep */
    NR11_REG = TONE_NR11;
    NR12_REG = TONE_NR12;
    NR13_REG = TONE_NR13;
    NR14_REG = TONE_NR14;      /* trigger: channel 1 starts the tone */
    NR51_REG = TONE_PAN;       /* pan channel 1 to both speakers */
    NR50_REG = TONE_MASTER;
}

static void tone_off(void) {
    NR52_REG = TONE_NR52_OFF;  /* APU off: stops channel 1 immediately */
}

void main(void) {
    // Classic DMG green: the console font's glyph pixels use palette
    // index 3, so they render in the darkest shade.
    BGP_REG = DMG_PALETTE(DMG_WHITE, DMG_WHITE, DMG_DARK_GRAY, DMG_BLACK);

    // Turn the LCD off so VRAM writes are deterministic. The boot ROM
    // leaves its logo on screen: scroll registers are mid-animation and
    // tile-map entries sit around the middle of the screen.
    DISPLAY_OFF;
    SCX_REG = 0;
    SCY_REG = 0;

    // First console call lazily loads the 8x8 font into VRAM. GBDK's
    // putchar maps char c to tile c - 0x20 (verified against the tile
    // map: '1'->17, '/'->15, 'A'->33, 's'->83 ...), so the printable
    // range 0x20..0x7F occupies tiles 0..95 and the space char is the
    // guaranteed-blank tile 0. Clear the whole map, then place the
    // start screen on the 20x18 character grid:
    //   row 5: "s   o   s"   (letters at columns 5, 9, 13)
    //   row 6: "... --- ..." (each 3-char code centered under its letter)
    //   row 8: "morseboy1"   (title, centered)
    putchar(' ');
    draw_sos();

    DISPLAY_ON;

    uint8_t screen = 0;       /* 0 = SOS start screen, 1 = A..Z reference */
    uint8_t letter = 0;       /* A..Z index on the reference screen */
    uint8_t tone_playing = 0;
    uint8_t jprev = 0;        /* previous frame's joypad, for press edges */
    uint8_t rep_left = 8;     /* hold-repeat countdowns (frames) for left/right */
    uint8_t rep_right = 8;
    uint8_t start_quiet = 0xFF; /* frames since Start last read as released */

    while (1) {
        vsync();
        uint8_t j = joypad();
        uint8_t pressed = (uint8_t)(j & ~jprev);
        jprev = j;

        /* A: keyer tone, on both screens. */
        if (j & J_A) {
            if (!tone_playing) {
                tone_on();
                tone_playing = 1;
            }
        } else {
            if (tone_playing) {
                tone_off();
                tone_playing = 0;
            }
        }

        /* Start: switch screens. Press edge only, debounced by the
         * release window: holding Start (including the hardware
         * auto-repeat) flips the screen exactly once. */
        if (j & J_START) {
            if ((pressed & J_START) && start_quiet >= START_DEBOUNCE) {
                if (screen == 0) {
                    screen = 1;
                    letter = 0;
                    draw_alphabet(letter);
                } else {
                    screen = 0;
                    draw_sos();
                }
            }
            start_quiet = 0;
        } else {
            if (start_quiet < 0xFF) {
                start_quiet++;
            }
        }

        /* Left/right: cycle letters on the reference screen. A fresh
         * press moves immediately; holding repeats every 8 frames. */
        if (screen == 1) {
            if (j & J_LEFT) {
                if ((pressed & J_LEFT) || rep_left == 0) {
                    letter = (uint8_t)((letter + 25) % 26);
                    draw_alphabet(letter);
                    rep_left = 8;
                } else {
                    rep_left--;
                }
            } else {
                rep_left = 8;
            }
            if (j & J_RIGHT) {
                if ((pressed & J_RIGHT) || rep_right == 0) {
                    letter = (uint8_t)((letter + 1) % 26);
                    draw_alphabet(letter);
                    rep_right = 8;
                } else {
                    rep_right--;
                }
            } else {
                rep_right = 8;
            }
        }
    }
}
