// The only dependency is RGFW: see top of RGFW.h for compile instructions per each platform (supported are macos/windows/linux)
// But remove anything OpenGL related from linking options etc since we use software/native rendering only
// cc Windows: (zig cc) skeleton.c -lgdi32 -lm

#include <stdio.h>
#include <time.h>

#define PSIVSTAR_IMPLEMENTATION
#include "./lib/psivstar.h"

#define RGFW_IMPLEMENTATION
#define RGFW_NATIVE
#include "./lib/RGFW/RGFW.h"

#define STB_TRUETYPE_IMPLEMENTATION
#include "./lib/stb/stb_truetype.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "./lib/stb/stb_image_write.h"

#define INCBIN_PREFIX
#define INCBIN_STYLE INCBIN_STYLE_SNAKE
#include "./lib/incbin.h"

#define CLAY_IMPLEMENTATION
#include "./lib/clay.h"

#define MAX_PIXEL_SIZE (3000 * 3000)

#define FONT_ID_UI (0)

struct {
    star_arena memory;
    RGFW_window *window;
    RGFW_surface *screen_surface;
    star_render_context rctx;
    bool render;

    // UI
    Clay_Arena clay_mem;
    Clay_Context *clay_ctx;

    // Fonts
    star_asciifont *fonts[16];
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
    Clay_SetLayoutDimensions((Clay_Dimensions){g.window->w, g.window->h});
}

INCBIN(ui_font, "./embed/eurostile.ttf");

static Clay_Dimensions measure_text(Clay_StringSlice text, Clay_TextElementConfig *config, void *user) {
    (void)user;
    Clay_Dimensions out = {0};
    star_string str = (star_string){
      .data = (u8 *)text.chars,
      .len = text.length,
    };
    star_asciifont *font = g.fonts[config->fontId];
    i32 w, h;
    star_asciifont_measure_text(font, str, config->letterSpacing, &w, &h);
    out.width = (f32)w;
    out.height = (f32)h;
    return out;
}

int main(int argc, char **argv) {
    (void)argc;
    (void)argv;
    star_init_library();

    Clay_SetMaxElementCount(196);
    const i32 ui_mem_size = Clay_MinMemorySize() * 2;
    const i32 screen_buffer_size = MAX_PIXEL_SIZE * sizeof(star_color);
    const i32 work_buffer_size = 32 * STAR_MB;
    g.memory = star_arena_make(ui_mem_size + screen_buffer_size + work_buffer_size);
    g.rctx.pixels = star_arena_allocate(&g.memory, screen_buffer_size);
    g.rctx.pixel_w = 1280;
    g.rctx.pixel_h = 720;
    g.render = true;

    g.fonts[FONT_ID_UI] = star_asciifont_make((u8 *)ui_font_data, 96.0f, &g.memory);

    g.window = RGFW_createWindow("Example", 0, 0, 1280, 720, RGFW_windowCenter);
    g.screen_surface = RGFW_createSurface((u8 *)g.rctx.pixels, 1280, 720, RGFW_formatRGB8);

    // Clay init
    g.clay_mem = Clay_CreateArenaWithCapacityAndMemory((size_t)ui_mem_size, star_arena_allocate(&g.memory, ui_mem_size));
    Clay_Initialize(g.clay_mem, (Clay_Dimensions){1280, 720}, (Clay_ErrorHandler){0});
    Clay_SetMeasureTextFunction(measure_text, NULL);

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
            // UI LAYOUT BEGIN
            Clay_BeginLayout();

            CLAY(CLAY_ID("root"), {
                .layout = { .sizing = {CLAY_SIZING_GROW(0), CLAY_SIZING_GROW(0)}, .layoutDirection = CLAY_LEFT_TO_RIGHT, },
                .backgroundColor = (Clay_Color){255, 255, 255, 255},
            }) {
                // Put elements here
            }

            Clay_RenderCommandArray cmds = Clay_EndLayout();
            // UI LAYOUT END

            // RENDER BEGIN
            // RENDER CODE GOES HERE
            for (i32 i = 0; i < cmds.length; i++) {
                Clay_RenderCommand *this = Clay_RenderCommandArray_Get(&cmds, i);
                switch (this->commandType) {
                case CLAY_RENDER_COMMAND_TYPE_NONE:
                    break;
                case CLAY_RENDER_COMMAND_TYPE_BORDER:
                    break;
                case CLAY_RENDER_COMMAND_TYPE_CUSTOM:
                    break;
                case CLAY_RENDER_COMMAND_TYPE_IMAGE:
                    break;
                case CLAY_RENDER_COMMAND_TYPE_RECTANGLE:
                    {
                        Clay_Color c_color = this->renderData.rectangle.backgroundColor;
                        star_color s_color = (star_color){ (u8)c_color.r, (u8)c_color.g, (u8)c_color.b };
                        i32 x, y, w, h;
                        x = this->boundingBox.x; y = this->boundingBox.y; w = this->boundingBox.width; h = this->boundingBox.height;
                        star_fill_rect(&g.rctx, x, y, w, h, s_color);
                    } break;
                case CLAY_RENDER_COMMAND_TYPE_SCISSOR_END:
                    break;
                case CLAY_RENDER_COMMAND_TYPE_SCISSOR_START:
                    break;
                case CLAY_RENDER_COMMAND_TYPE_TEXT:
                    {
                        Clay_Color c_color = this->renderData.text.textColor;
                        star_color s_color = (star_color){ (u8)c_color.r, (u8)c_color.g, (u8)c_color.b };
                        i32 font_id = (i32)this->renderData.text.fontId;
                        star_asciifont *font = g.fonts[font_id];
                        star_string str = (star_string){
                            .data = (u8 *)this->renderData.text.stringContents.chars,
                            .len = this->renderData.text.stringContents.length,
                        };
                        i32 x_start = (i32)this->boundingBox.x;
                        i32 y_start = (i32)this->boundingBox.y;
                        star_asciifont_draw_text(font, str, &g.rctx, x_start, y_start, 1, s_color, false);
                    } break;
                }
            }

            // RENDER END
            RGFW_window_blitSurface(g.window, g.screen_surface);
        }
    }

    return 0;
}
