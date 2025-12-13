#include "./RGFW/RGFW.h"
#include "./stb/stb_truetype.h"
#include <stdio.h>
#include <assert.h>

#ifdef _MSC_VER
    #include <intrin.h>
#else
    #include <x86intrin.h>
#endif

#ifndef f32
typedef float f32;
#endif
#ifndef f64
typedef double f64;
#endif
#ifndef rune
typedef i32 rune;
#endif
#ifndef true
#define true (1)
#endif
#ifndef false
#define false (0)
#endif
#ifndef bool
#define bool i32
#endif

#define STAR_BYTE 1
#define STAR_KB (1024)
#define STAR_MB (STAR_KB * 1024)
#define STAR_GB (STAR_MB * 1024)

// Basic
u64 star_read_time(void);

typedef struct star_arena {
    u8 *data;
    i32 position;
    i32 cap;
} star_arena;

star_arena star_arena_make(i32 cap);
star_arena star_arena_fork(star_arena *base, i32 sub_cap);
void *star_arena_allocate(star_arena *a, i32 size);

typedef struct star_string {
    u8 *data;
    i32 len;
} star_string;

i32 star_cstring_len(u8 *cstring);
star_string star_string_from_cstring(u8 *cstring);

// Software rendering
typedef struct star_color {
    u8 r, g, b;
} star_color;

typedef struct star_rect {
    i32 x, y, w, h;
} star_rect;

typedef struct star_render_context {
    star_color *pixels;
    i32 pixel_w;
    i32 pixel_h;
    star_rect clear_rects[1024];
    i32 clear_rects_ptr;
} star_render_context;

void star_begin_drawing(star_render_context *ctx);
void star_fill_rect(star_render_context *ctx, i32 x, i32 y, i32 rw, i32 rh, star_color color);

#define ASCII_START ((u8)32)
typedef struct star_glyph {
    i32 x0, y0, x1, y1;
    f32 xoff, yoff, xadvance;
} star_glyph;

typedef struct star_text_measure {
    i32 tallest_h;
    i32 width;
} star_text_measure;

typedef struct star_asciifont {
    u8 *atlas;
    i32 atlas_w;
    i32 atlas_h;
    stbtt_fontinfo font_data;
    f32 ascent, descent, line_gap, line_height;
    star_glyph glyphs[96]; // 32..127
} star_asciifont;

star_asciifont *star_asciifont_make(u8 *ttf_memory, f32 font_size, star_arena *mem);
void star_asciifont_draw_text(star_asciifont *f, star_string text, star_render_context *ctx, i32 x, i32 y, i32 letter_spacing, star_color color);

void star_init_library(void);

#if 1 // #ifdef PSIVSTAR_IMPLEMENTATION
u64 star_read_time(void) {
    unsigned int dummy;
    return __rdtscp(&dummy);
    return (u64)dummy;
}

star_arena star_arena_make(i32 cap) {
    star_arena out = {0};
    out.data = (u8 *)calloc(1, (size_t)cap);
    out.position = 0;
    out.cap = cap;
    return out;
}

star_arena star_arena_fork(star_arena *base, i32 sub_cap) {
    assert(base->position == 0 && sub_cap > 0);
    star_arena out = {0};
    out.data = &base->data[base->cap - sub_cap];
    out.cap = sub_cap;
    out.position = 0;

    base->cap -= sub_cap;
    return out;
}

void *star_arena_allocate(star_arena *a, i32 size) {
    assert(a->position + size < a->cap);
    size = (size | 63) + 1; // align to 64 bytes
    void *out = (void *)&a->data[a->position];
    a->position += size;
    return out;
}

i32 star_cstring_len(u8 *cstring) {
    u8 *c = cstring;
    i32 res = 0;
    while (*c) c++, res++;
    return res;
}

star_string star_string_from_cstring(u8 *cstring) {
    star_string out;
    out.data = (u8 *)cstring;
    out.len = star_cstring_len(cstring);
    return out;
}

static inline void star_push_clear_rect(star_render_context *ctx, star_rect r) {
    ctx->clear_rects[ctx->clear_rects_ptr++] = r;
}

static inline bool star_rects_overlap(star_rect a, star_rect b) {
    return (a.x < b.x + b.w && a.x + a.w > b.x &&
            a.y < b.y + b.h && a.y + a.h > b.y);
}

static inline star_rect star_rect_union(star_rect a, star_rect b) {
    star_rect r;
    i32 min_x = (a.x < b.x) ? a.x : b.x;
    i32 min_y = (a.y < b.y) ? a.y : b.y;
    i32 max_r = (a.x + a.w > b.x + b.w) ? a.x + a.w : b.x + b.w;
    i32 max_b = (a.y + a.h > b.y + b.h) ? a.y + a.h : b.y + b.h;

    r.x = min_x;
    r.y = min_y;
    r.w = max_r - min_x;
    r.h = max_b - min_y;
    return r;
}

// In-place clear rect merging
i32 star_merge_rects(star_rect *rects, i32 len) {
    if (len <= 0) return 0;
    for (i32 i = 0; i < len; ++i) {
        for (i32 j = i + 1; j < len; ) {
            if (star_rects_overlap(rects[i], rects[j])) {
                // Merge
                rects[i] = star_rect_union(rects[i], rects[j]);
                rects[j] = rects[len - 1];
                len--;
            } else {
                // No overlap
                j++;
            }
        }
    }
    return len;
}

static inline void star_clear_rect(star_render_context *ctx, star_rect r) {
    if (r.x < 0) { r.w += r.x; r.x = 0; }
    if (r.y < 0) { r.h += r.y; r.y = 0; }

    if (r.x >= ctx->pixel_w || r.y >= ctx->pixel_h) return;

    if (r.x + r.w > ctx->pixel_w) r.w = ctx->pixel_w - r.x;
    if (r.y + r.h > ctx->pixel_h) r.h = ctx->pixel_h - r.y;

    if (r.w <= 0 || r.h <= 0) return;

    star_color *row_ptr = ctx->pixels + (r.y * ctx->pixel_w) + r.x;
    i32 row_size_bytes = r.w * sizeof(star_color);

    if (r.w == ctx->pixel_w) {
        memset(row_ptr, 0, row_size_bytes * r.h);
        return;
    }

    for (i32 i = 0; i < r.h; i++) {
        memset(row_ptr, 0, row_size_bytes);
        row_ptr += ctx->pixel_w;
    }
}

void star_begin_drawing(star_render_context *ctx) {
    i32 total_area = ctx->pixel_w * ctx->pixel_h;
    i32 clear_area = 0;
    for (i32 i = 0; i < ctx->clear_rects_ptr; i++) {
        clear_area += ctx->clear_rects[i].w * ctx->clear_rects[i].h;
    }
    if (clear_area * 2 >= total_area) {
        // clear whole screen (>50% is covered by rects anyway)
        memset(ctx->pixels, 0, sizeof(star_color) * total_area);
        return;
    }

    // Clear only the clear rects (smart merge)
    i32 new_count = star_merge_rects(ctx->clear_rects, ctx->clear_rects_ptr);
    for (i32 i = 0; i < new_count; i++) {
        star_clear_rect(ctx, ctx->clear_rects[i]);
    }
    ctx->clear_rects_ptr = 0;
}

void star_fill_rect(star_render_context *ctx, i32 x, i32 y, i32 rw, i32 rh, star_color color) {
    i32 w = ctx->pixel_w;
    i32 h = ctx->pixel_h;
    if (x < 0) { rw += x; x = 0; }
    if (y < 0) { rh += y; y = 0; }
    if (x >= w || y >= h) return;
    if (x + rw > w) rw = w - x;
    if (y + rh > h) rh = h - y;
    if (rw <= 0 || rh <= 0) return;

    star_push_clear_rect(ctx, (star_rect){ x, y, rw, rh });

    // Pre-calculate the 3 integers that cover 4 pixels (RGB RGB RGB RGB)
    u32 c = (u32)color.r | ((u32)color.g << 8) | ((u32)color.b << 16);

    // We need to shift the pattern for the 32-bit writes
    u32 chunk0 = c | ((u32)color.r << 24);              // R G B R
    u32 chunk1 = (u32)color.g | ((u32)color.b << 8) | ((u32)color.r << 16) | ((u32)color.g << 24); // G B R G
    u32 chunk2 = (u32)color.b | ((u32)color.r << 8) | ((u32)color.g << 16) | ((u32)color.b << 24); // B R G B

    star_color *row = ctx->pixels + y * w + x;

    for (i32 j = 0; j < rh; ++j) {
        u8 *p = (u8*)row;
        i32 count = rw;

        // Fast path: Process 4 pixels at a time
        while (count >= 4) {
            memcpy(p,     &chunk0, 4);
            memcpy(p + 4, &chunk1, 4);
            memcpy(p + 8, &chunk2, 4);
            p += 12;
            count -= 4;
        }

        // Slow path: Handle remaining 1-3 pixels
        while (count > 0) {
            star_color *sc = (star_color*)p;
            *sc = color;
            p += 3;
            count--;
        }
        row += w;
    }
}

star_asciifont *star_asciifont_make(u8 *ttf_memory, f32 font_size, star_arena *mem) {
    stbtt_bakedchar char_data[96] = {0};

    star_asciifont *out = (star_asciifont *)star_arena_allocate(mem, sizeof(star_asciifont));
    i32 bitmap_w = 96 * ((i32)font_size * 2);
    i32 bitmap_h = ((i32)font_size * 2);
    out->atlas = (u8 *)star_arena_allocate(mem, bitmap_w * bitmap_h * sizeof(u8));
    out->atlas_w = bitmap_w;
    out->atlas_h = bitmap_h;

    // Render chars into our bitmap
    i32 result = stbtt_BakeFontBitmap(ttf_memory, 0, font_size, out->atlas, out->atlas_w, out->atlas_h, ASCII_START, 128-ASCII_START, char_data);
    if (result <= 0) {
        assert(0);
    }

    stbtt_InitFont(&out->font_data, ttf_memory, 0);
    int ascent, descent, line_gap;
    stbtt_GetFontVMetrics(&out->font_data, &ascent, &descent, &line_gap);
    f32 scale = stbtt_ScaleForPixelHeight(&out->font_data, font_size);

    out->ascent = (f32)ascent * scale;
    out->descent = (f32)descent * scale;
    out->line_gap = (f32)line_gap * scale;
    out->line_height = out->ascent - out->descent + out->line_gap;

    // Bake the chars
    for (i32 i = 0; i < 128-ASCII_START; i++) {
        out->glyphs[i].x0 = (i32)char_data[i].x0;
        out->glyphs[i].x1 = (i32)char_data[i].x1;
        out->glyphs[i].y0 = (i32)char_data[i].y0;
        out->glyphs[i].y1 = (i32)char_data[i].y1;
        out->glyphs[i].xoff = char_data[i].xoff;
        out->glyphs[i].yoff = char_data[i].yoff;
        out->glyphs[i].xadvance = char_data[i].xadvance;
    }
    return out;
}

// Alpha application via Look-Up Table (fastest)
static u8 g_alpha_lut[256 * 256] __attribute__((aligned(64)));
static void init_alpha_lut(void) {
    int a, c;
    for (a = 0; a < 256; ++a) {
        for (c = 0; c < 256; ++c) {
            // Use whatever formula you like; here: round(c * a / 255)
            g_alpha_lut[(a << 8) | c] = (u8)(((unsigned)c * (unsigned)a + 127) / 255);
        }
    }
}

static inline u8 get_alpha_lut(u8 c, u8 a) {
    return g_alpha_lut[((unsigned)a << 8) | (unsigned)c];
}

void star_init_library(void) {
    init_alpha_lut();
}
#endif
