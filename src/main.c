/* morseboy1 — minimal Game Boy (DMG) demo built with GBDK-2020.
 *
 * Four screens:
 *
 *   SOS welcome screen (SCREEN_SOS): shows the letters "s o s" with
 *   their Morse code (... --- ...) beneath each, using the built-in
 *   8x8 console font. It is the launch screen (old-game style): shown
 *   once at boot, press start to enter the menu. There is no back
 *   navigation from the menu to this screen.
 *
 *   Menu (SCREEN_MENU): a two-item list — "ref" and "quiz" — navigable
 *   with up/down, the current selection marked with a ">" arrow.
 *   Pressing A opens the selected screen; B does nothing (the welcome
 *   screen is one-way).
 *
 *   Reference screen (SCREEN_REF): shows one alphabet letter with its
 *   Morse code beneath it. Left/right cycles through all 26 letters
 *   (hold to keep cycling); Start plays the Morse code of the current
 *   letter (see play_morse()); B returns to the menu.
 *
 *   Quiz screen (SCREEN_QUIZ): placeholder for the "listen quiz" mode —
 *   shows "quiz" for now. B returns to the menu.
 *
 * Morse keyer: holding the A button sounds a ~500 Hz square wave (a
 * classic CW keyer tone); the tone lasts exactly as long as A is held.
 * On the menu, pressing A also opens the selected screen. On the
 * reference screen, pressing Start plays the Morse code of the current
 * letter with play_morse(), blocking the main loop for the duration.
 *
 * Start, B and A navigation actions are debounced: the DMG joypad
 * auto-repeats a held button (33f initial delay, then a 9f cycle), so a
 * press edge alone would still fire rapidly while the button is held.
 * An action press is therefore only accepted when the button has been
 * fully released for KEY_DEBOUNCE frames.
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
 * All screens use the 20x18 character grid of the DMG console.
 */
#define SCREEN_SOS    0
#define SCREEN_MENU   1
#define SCREEN_REF    2
#define SCREEN_QUIZ   3

/* Menu items, in list order (row = 5 + index). */
#define MENU_ITEMS    2
static const char *const MENU_LABELS[MENU_ITEMS] = {
    "ref",  /* -> reference screen */
    "quiz", /* -> listen quiz screen */
};

static void draw_sos(void) {
    cls();
    gotoxy(5, 5);
    printf("s   o   s");
    gotoxy(4, 6);
    printf("... --- ...");
    gotoxy(5, 8);
    printf("morseboy1");
    // "press start" is 11 chars: (20 - 11) / 2 = 4 centers it horizontally;
    // row 11 leaves two blank rows of space below "morseboy1" (row 8).
    gotoxy(4, 11);
    printf("press start");
}

static void draw_menu(uint8_t sel) {
    cls();
    gotoxy(8, 3);
    printf("menu");
    // Item text starts at column 7; the selection arrow sits in column 5.
    gotoxy(7, 5);
    printf("%s", MENU_LABELS[0]);
    gotoxy(7, 6);
    printf("%s", MENU_LABELS[1]);
    gotoxy(5, (uint8_t)(5 + sel));
    putchar('>');
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

static void draw_quiz(void) {
    cls();
    // "quiz" is 4 chars: (20 - 4) / 2 = 8 centers it horizontally.
    gotoxy(8, 8);
    printf("quiz");
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

/* Key debounce: minimum frames the button must read as released before
 * a press edge is accepted. Must exceed the hardware repeat cycle (9f),
 * whose internal release phase is far shorter. */
#define KEY_DEBOUNCE 12

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

/* --- Morse playback -------------------------------------------------------
 *
 * play_morse() sounds a Morse string (dot = '.', dash = '-') on the
 * keyer tone with classic proportions: a dash is three dot-lengths, and
 * every element — including the last of the string — is followed by one
 * dot-length of silence. It is blocking: it waits each element and gap
 * out in a vsync() loop, so the caller yields the main loop for the
 * duration of the whole string (up to ~1.2 s for Q, "--.-").
 *
 * Speed: one dot-length = TONE_UNIT vblanks, 6 frames, about 100 ms
 * (~12 WPM) — comfortable for learning.
 */
#define TONE_UNIT 6  /* frames (vblanks) per dot-length, ~100 ms */

static void wait_frames(uint8_t n) {
    while (n > 0) {
        n--;
        vsync();
    }
}

static void play_morse(const char *code) {
    while (*code) {
        tone_on();
        wait_frames(*code == '-' ? TONE_UNIT * 3 : TONE_UNIT);
        tone_off();
        wait_frames(TONE_UNIT);  /* gap after each element */
        code++;
    }
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
    // guaranteed-blank tile 0.
    putchar(' ');
    draw_sos();

    DISPLAY_ON;

    uint8_t screen = SCREEN_SOS;
    uint8_t menu_sel = 0;      /* menu selection: index into MENU_LABELS */
    uint8_t letter = 0;        /* A..Z index on the reference screen */
    uint8_t tone_playing = 0;
    uint8_t jprev = 0;         /* previous frame's joypad, for press edges */
    uint8_t rep_left = 8;      /* hold-repeat countdowns (frames) for left/right */
    uint8_t rep_right = 8;
    uint8_t start_quiet = 0xFF;/* frames since Start/B/A last read as released */
    uint8_t b_quiet = 0xFF;
    uint8_t a_quiet = 0xFF;

    while (1) {
        vsync();
        uint8_t j = joypad();
        uint8_t pressed = (uint8_t)(j & ~jprev);
        jprev = j;

        /* A: keyer tone, on every screen (level-based: on while held). */
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

        /* Start: open the menu from the SOS screen. Press edge only,
         * debounced by the release window: holding Start (including the
         * hardware auto-repeat) fires exactly once. */
        if (j & J_START) {
            if ((pressed & J_START) && start_quiet >= KEY_DEBOUNCE) {
                if (screen == SCREEN_SOS) {
                    screen = SCREEN_MENU;
                    draw_menu(menu_sel);
                } else if (screen == SCREEN_REF) {
                    /* Play the Morse code of the current letter. This
                     * blocks, and play_morse() ends with the APU off,
                     * so drop the keyer flag: if A is also held, the
                     * keyer tone simply comes back on next frame. */
                    play_morse(MORSE[letter]);
                    tone_playing = 0;
                }
            }
            start_quiet = 0;
        } else {
            if (start_quiet < 0xFF) {
                start_quiet++;
            }
        }

        /* B: back from a mode to the menu. The SOS screen is the
         * welcome/launch screen, so B does nothing on the menu.
         * Debounced like Start. */
        if (j & J_B) {
            if ((pressed & J_B) && b_quiet >= KEY_DEBOUNCE) {
                if (screen == SCREEN_REF || screen == SCREEN_QUIZ) {
                    screen = SCREEN_MENU;
                    draw_menu(menu_sel);
                }
            }
            b_quiet = 0;
        } else {
            if (b_quiet < 0xFF) {
                b_quiet++;
            }
        }

        /* Menu: up/down move the selection (press edge only — the list
         * is short, so no hold-repeat), A opens the selected screen. */
        if (screen == SCREEN_MENU) {
            if (pressed & J_UP) {
                menu_sel = (uint8_t)((menu_sel + MENU_ITEMS - 1) % MENU_ITEMS);
                draw_menu(menu_sel);
            } else if (pressed & J_DOWN) {
                menu_sel = (uint8_t)((menu_sel + 1) % MENU_ITEMS);
                draw_menu(menu_sel);
            }
            if ((j & J_A) && (pressed & J_A) && a_quiet >= KEY_DEBOUNCE) {
                if (menu_sel == 0) {
                    screen = SCREEN_REF;
                    draw_alphabet(letter);
                } else {
                    screen = SCREEN_QUIZ;
                    draw_quiz();
                }
            }
        }
        if (j & J_A) {
            a_quiet = 0;
        } else {
            if (a_quiet < 0xFF) {
                a_quiet++;
            }
        }

        /* Reference screen: left/right cycle letters. A fresh press moves
         * immediately; holding repeats every 8 frames. */
        if (screen == SCREEN_REF) {
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
