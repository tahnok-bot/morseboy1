/* morseboy1 — minimal Game Boy (DMG) demo built with GBDK-2020.
 *
 * Prints "hi hi" centered on the background using the built-in 8x8
 * console font (stdio).
 */

#include <gbdk/platform.h>
#include <gbdk/console.h>
#include <stdio.h>

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
    // a guaranteed-blank tile). Clear the whole map, then center
    // "hi hi" (5 columns) on the 20x18 character grid.
    putchar(' ');
    cls();
    gotoxy(7, 8);
    printf("hi hi");

    DISPLAY_ON;

    while (1) {
        vsync();
    }
}
