// The only dependency is RGFW: see top of RGFW.h for compile instructions per each platform (supported are macos/windows/linux)
// But remove anything OpenGL related from -l options etc since we use software/native rendering only
// cc Windows: (zig cc) mooncol.c -lgdi32

#include <stdio.h>
#include <time.h>

#define PSIVSTAR_IMPLEMENTATION
#include "./lib/psivstar.h"

#define RGFW_IMPLEMENTATION
#define RGFW_NATIVE
#include "./lib/RGFW/RGFW.h"

#define STB_TRUETYPE_IMPLEMENTATION
#include "./lib/stb/stb_truetype.h"

#define INCBIN_PREFIX
#define INCBIN_STYLE INCBIN_STYLE_SNAKE
#include "./lib/incbin.h"

static const i32 MAX_PIXEL_SIZE = (3000 * 3000);

struct {
    star_arena memory;
    RGFW_window *window;
    RGFW_surface *screen_surface;
    star_render_context rctx;
    bool render;

    // Fonts
    star_asciifont *ui_font;
} g;

static void on_resize(void) {
    i32 new_w = g.window->w;
    i32 new_h = g.window->h;
    i32 new_size = new_w * new_h;

    if (new_w <= 0 || new_h <= 0) {
        return;
    }
    assert(new_size <= MAX_PIXEL_SIZE);
    g.screen_surface = RGFW_createSurface((u8 *)g.rctx.pixels, new_w, new_h, RGFW_formatRGB8);
    g.rctx.pixel_w = new_w;
    g.rctx.pixel_h = new_h;

    // Clear entire screen
    memset(g.rctx.pixels, 0, sizeof(star_color) * g.rctx.pixel_w * g.rctx.pixel_h);
}

INCBIN(ui_font, "./embed/eurostile.ttf");

int main(int argc, char **argv) {
    (void)argc;
    (void)argv;
    star_init_library();

    const i32 screen_buffer_size = MAX_PIXEL_SIZE * sizeof(star_color);
    const i32 work_buffer_size = 24 * STAR_MB;
    g.memory = star_arena_make(screen_buffer_size + work_buffer_size);
    g.rctx.pixels = star_arena_allocate(&g.memory, screen_buffer_size);
    g.rctx.pixel_w = 1280;
    g.rctx.pixel_h = 720;
    g.render = true;

    g.ui_font = star_asciifont_make((u8 *)ui_font_data, 96.0f, &g.memory);

    g.window = RGFW_createWindow("Example", 0, 0, 1280, 720, RGFW_windowCenter);
    g.screen_surface = RGFW_createSurface((u8 *)g.rctx.pixels, 1280, 720, RGFW_formatRGB8);
    while (RGFW_window_shouldClose(g.window) == RGFW_FALSE) {
        RGFW_event evt;
        while (RGFW_window_checkEvent(g.window, &evt)) {
            if (evt.type == RGFW_windowResized) {
                on_resize();
                g.render = true;
            } else if (evt.type == RGFW_windowMaximized) {
                on_resize();
                g.render = true;
            } else if (evt.type == RGFW_windowRestored) {
                on_resize();
                g.render = true;
            } else if (evt.type == RGFW_windowMinimized) {
                g.render = false;
            } else if (evt.type == RGFW_quit) {
                return 0;
            }
        }
        if (g.render) {
            // RENDER BEGIN

            // RENDER CODE GOES HERE

            // RENDER END
            RGFW_window_blitSurface(g.window, g.screen_surface);
        }
    }

    return 0;
}
