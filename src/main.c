/* morseboy1 — minimal Game Boy (DMG) demo built with GBDK-2020.
 *
 * Start screen: shows the letters "s o s" with their Morse code
 * (... --- ...) beneath each, using the built-in 8x8 console font.
 *
 * Morse keyer: holding the A button sounds a ~500 Hz square wave (a
 * classic CW keyer tone); the tone lasts exactly as long as A is held.
 */

#include <gbdk/platform.h>
#include <gbdk/console.h>
#include <stdio.h>

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

    // First console call lazily loads the 8x8 font into VRAM (tiles
    // 0..127, identity mapping: char c -> tile c, so the space char is
    // a guaranteed-blank tile). Clear the whole map, then place the
    // start screen on the 20x18 character grid:
    //   row 5: "s   o   s"   (letters at columns 5, 9, 13)
    //   row 6: "... --- ..." (each 3-char code centered under its letter)
    putchar(' ');
    cls();
    gotoxy(5, 5);
    printf("s   o   s");
    gotoxy(4, 6);
    printf("... --- ...");

    DISPLAY_ON;

    uint8_t tone_playing = 0;
    while (1) {
        vsync();
        if (joypad() & J_A) {
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
    }
}
