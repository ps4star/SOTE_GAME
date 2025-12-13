#include "./RGFW/RGFW.h"
#include "./stb/stb_truetype.h"
#include "./stb/stb_image_write.h"
#include "./clay.h"
#include <stdio.h>
#include <assert.h>
#include <limits.h> // For INT_MAX, INT_MIN
#include <math.h>

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

#ifndef STAR_MIN
	#define STAR_MIN(x, y) ((x < y) ? x : y)
#endif

#ifndef STAR_MAX
    #define STAR_MAX(x, y) ((x > y) ? x : y)
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

i32 star_cstring_len(const char *cstring);
star_string star_string_from_cstring(const char *cstring);

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
void star_asciifont_measure_text(star_asciifont *font, star_string str, i32 letter_spacing, i32 *w, i32 *h);
void star_asciifont_draw_text(star_asciifont *f, star_string text, star_render_context *ctx, i32 x, i32 y, i32 letter_spacing, star_color color, bool bilinear);

void star_init_library(void);

#if defined(PSIVSTAR_IMPLEMENTATION) || 1
u64 star_read_time(void) {
    unsigned int dummy;
    return (u64)__rdtscp(&dummy);
}

star_arena star_arena_make(i32 cap) {
    assert(cap > 0); // Sanity check: capacity must be positive
    star_arena out = {0};
    out.data = (u8 *)calloc(1, (size_t)cap);
    assert(out.data != NULL); // Sanity check: allocation must succeed
    out.position = 0;
    out.cap = cap;
    return out;
}

star_arena star_arena_fork(star_arena *base, i32 sub_cap) {
    assert(base != NULL); // Sanity check: base arena pointer must not be NULL
    assert(sub_cap > 0); // Sanity check: sub_cap must be positive
    assert(base->position == 0); // Sanity check: base arena should be unused before forking from it
    assert(sub_cap <= base->cap); // Sanity check: sub_cap must not exceed base->cap

    star_arena out = {0};
    out.data = &base->data[base->cap - sub_cap];
    assert(out.data != NULL); // Sanity check: data pointer must be valid
    out.cap = sub_cap;
    out.position = 0;

    base->cap -= sub_cap;
    return out;
}

void *star_arena_allocate(star_arena *a, i32 size) {
    assert(a != NULL); // Sanity check: arena pointer must not be NULL
    assert(a->data != NULL); // Sanity check: arena data pointer must not be NULL
    assert(size > 0); // Sanity check: allocation size must be positive
    i32 aligned_size = (size | 63) + 1; // align to 64 bytes
    assert(a->position + aligned_size <= a->cap); // Sanity check: ensure enough capacity
    void *out = (void *)&a->data[a->position];
    a->position += aligned_size;
    return out;
}

i32 star_cstring_len(const char *cstring) {
    assert(cstring != NULL); // Sanity check: cstring pointer must not be NULL
    u8 *c = (u8 *)cstring;
    i32 res = 0;
    while (*c) c++, res++;
    return res;
}

star_string star_string_from_cstring(const char *cstring) {
    assert(cstring != NULL); // Sanity check: cstring pointer must not be NULL
    star_string out;
    out.data = (u8 *)cstring;
    out.len = star_cstring_len(cstring);
    return out;
}

// Alpha application via Look-Up Table (fastest)
static u8 g_alpha_lut[256 * 256];
static void init_alpha_lut(void) {
    i32 a, c;
    for (a = 0; a < 256; ++a) {
        for (c = 0; c < 256; ++c) {
            // Use whatever formula you like; here: round(c * a / 255)
            g_alpha_lut[(a << 8) | c] = (u8)(((u32)c * (u32)a + 127) / 255);
        }
    }
}

static inline u8 get_alpha_lut(u8 c, u8 a) {
    return g_alpha_lut[((u32)a << 8) | (u32)c];
}

static inline void star_push_clear_rect(star_render_context *ctx, star_rect r) {
    assert(ctx != NULL); // Sanity check: context pointer must not be NULL
    assert(ctx->clear_rects_ptr < 1024); // Sanity check: prevent buffer overflow
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
    assert(rects != NULL || len == 0); // Sanity check: rects pointer must not be NULL if len > 0
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
    assert(ctx != NULL); // Sanity check: context pointer must not be NULL
    assert(ctx->pixels != NULL); // Sanity check: pixels buffer must not be NULL
    assert(ctx->pixel_w > 0 && ctx->pixel_h > 0); // Sanity check: pixel dimensions must be positive

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
    assert(ctx != NULL); // Sanity check: context pointer must not be NULL
    assert(ctx->pixels != NULL); // Sanity check: pixels buffer must not be NULL
    assert(ctx->pixel_w > 0 && ctx->pixel_h > 0); // Sanity check: pixel dimensions must be positive

    u64 total_area = (u64)ctx->pixel_w * (u64)ctx->pixel_h;
    u64 clear_area = 0;
    for (i32 i = 0; i < ctx->clear_rects_ptr; i++) {
        // Potential overflow if w*h is very large, but handled by i32 limits
        clear_area += (u64)ctx->clear_rects[i].w * ctx->clear_rects[i].h;
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
    assert(ctx != NULL); // Sanity check: context pointer must not be NULL
    assert(ctx->pixels != NULL); // Sanity check: pixels buffer must not be NULL
    assert(ctx->pixel_w > 0 && ctx->pixel_h > 0); // Sanity check: pixel dimensions must be positive

    i32 w = ctx->pixel_w;
    i32 h = ctx->pixel_h;
    if (x < 0) { rw += x; x = 0; }
    if (y < 0) { rh += y; y = 0; }
    if (x >= w || y >= h) return;
    if (x + rw > w) rw = w - x;
    if (y + rh > h) rh = h - y;
    if (rw <= 0 || rh <= 0) return;

    star_push_clear_rect(ctx, (star_rect){ x, y, rw, rh });

    // Pre-calculate the 12 bytes for 4 pixels (RGBRGBRGBRGB)
    u8 pixel_pattern[12];
    for (int i = 0; i < 4; ++i) {
        pixel_pattern[i * 3 + 0] = color.r;
        pixel_pattern[i * 3 + 1] = color.g;
        pixel_pattern[i * 3 + 2] = color.b;
    }

    star_color *row = ctx->pixels + y * w + x;

    for (i32 j = 0; j < rh; ++j) {
        u8 *p = (u8*)row;
        i32 count = rw;

        // Fast path: Process 4 pixels at a time (12 bytes)
        while (count >= 4) {
            memcpy(p, pixel_pattern, 12);
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
    assert(ttf_memory != NULL);
    assert(font_size > 0);
    assert(mem != NULL);

    star_asciifont *font = (star_asciifont *)star_arena_allocate(mem, sizeof(star_asciifont));
    if (!font) {
        return NULL;
    }

    if (!stbtt_InitFont(&font->font_data, ttf_memory, stbtt_GetFontOffsetForIndex(ttf_memory, 0))) {
        return NULL;
    }

    font->atlas_w = 1024;
    font->atlas_h = 1024;
    font->atlas = (u8 *)star_arena_allocate(mem, font->atlas_w * font->atlas_h);
    if (!font->atlas) {
        return NULL;
    }
    memset(font->atlas, 0, font->atlas_w * font->atlas_h);

    f32 scale = stbtt_ScaleForPixelHeight(&font->font_data, font_size);
    int ascent, descent, line_gap;
    stbtt_GetFontVMetrics(&font->font_data, &ascent, &descent, &line_gap);
    font->ascent = (f32)ascent * scale;
    font->descent = (f32)descent * scale;
    font->line_gap = (f32)line_gap * scale;
    font->line_height = font->ascent - font->descent + font->line_gap;

    i32 atlas_x = 1;
    i32 atlas_y = 1;
    i32 max_row_h = 0;

    for (i32 i = 0; i < 96; i++) { // For ASCII 32 to 127
        int codepoint = ASCII_START + i;

        int glyph_idx = stbtt_FindGlyphIndex(&font->font_data, codepoint);
        if (glyph_idx == 0) {
            if (codepoint != '?') {
                int question_glyph_idx = stbtt_FindGlyphIndex(&font->font_data, '?');
                if (question_glyph_idx != 0) glyph_idx = question_glyph_idx;
            }
             if (glyph_idx == 0) continue;
        }

        int ix0, iy0, ix1, iy1;
        stbtt_GetGlyphBitmapBox(&font->font_data, glyph_idx, scale, scale, &ix0, &iy0, &ix1, &iy1);

        int glyph_w = ix1 - ix0;
        int glyph_h = iy1 - iy0;

        if (atlas_x + glyph_w + 1 >= font->atlas_w) {
            atlas_x = 1;
            atlas_y += max_row_h + 1;
            max_row_h = 0;
        }

        if (atlas_y + glyph_h + 1 >= font->atlas_h) {
            assert(0 && "Font atlas is too small");
            return NULL;
        }

        if (glyph_w > 0 && glyph_h > 0) {
            stbtt_MakeGlyphBitmap(&font->font_data,
                                  font->atlas + atlas_x + (atlas_y * font->atlas_w),
                                  glyph_w, glyph_h, font->atlas_w,
                                  scale, scale,
                                  glyph_idx);
        }

        font->glyphs[i].x0 = atlas_x;
        font->glyphs[i].y0 = atlas_y;
        font->glyphs[i].x1 = atlas_x + glyph_w;
        font->glyphs[i].y1 = atlas_y + glyph_h;

        font->glyphs[i].xoff = (f32)ix0;
        font->glyphs[i].yoff = (f32)iy0;

        int advance;
        stbtt_GetGlyphHMetrics(&font->font_data, glyph_idx, &advance, NULL);
        font->glyphs[i].xadvance = (f32)advance * scale;

        atlas_x += glyph_w + 1;
        if (glyph_h > max_row_h) {
            max_row_h = glyph_h;
        }
    }

    return font;
}

void star_asciifont_measure_text(star_asciifont *font, star_string str, i32 letter_spacing, i32 *w, i32 *h) {
    i32 current_x = 0;
    i32 current_y = 0;
    i32 max_line_height = 0;

    for (i32 i = 0; i < str.len; i++) {
        char c = str.data[i];

        if (c == '\n') {
            current_x = 0;
            current_y += font->line_height;
            continue;
        }

        star_glyph *glyph = &font->glyphs[(u32)c - ASCII_START];
        i32 glyph_width = (glyph->x1 - glyph->x0) + letter_spacing;

        current_x += glyph_width;
        if (current_y + (glyph->y1 - glyph->y0) > max_line_height) {
            max_line_height = current_y + (glyph->y1 - glyph->y0);
        }
    }

    if (w) {
        *w = current_x;
    }
    if (h) {
        *h = current_y + font->line_height;
    }
}

void star_asciifont_draw_text(star_asciifont *f, star_string text, star_render_context *ctx, i32 x, i32 y, i32 letter_spacing, star_color color, bool bilinear) {
    // Sanity checks
    assert(f != NULL);
    assert(f->atlas != NULL);
    assert(ctx != NULL);
    assert(ctx->pixels != NULL);
    assert(f->atlas_w > 0 && f->atlas_h > 0);
    assert(ctx->pixel_w > 0 && ctx->pixel_h > 0);
    assert(text.data != NULL || text.len == 0);

    f32 current_x = (f32)x;
    f32 current_y_baseline = (f32)y + f->ascent;

    i32 min_drawn_x = INT_MAX;
    i32 min_drawn_y = INT_MAX;
    i32 max_drawn_x = INT_MIN;
    i32 max_drawn_y = INT_MIN;

    for (i32 i = 0; i < text.len; ++i) {
        u8 char_code = text.data[i];

        if (char_code == '\n') {
            current_x = (f32)x;
            current_y_baseline += f->line_height;
            continue;
        }

        if (char_code < ASCII_START || char_code > 127) {
            star_glyph *space_glyph = &f->glyphs[' ' - ASCII_START];
            current_x += space_glyph->xadvance + (f32)letter_spacing;
            continue;
        }

        star_glyph *glyph = &f->glyphs[char_code - ASCII_START];

        f32 glyph_screen_x_f = current_x + glyph->xoff;
        f32 glyph_screen_y_f = current_y_baseline + glyph->yoff;

        i32 glyph_w = glyph->x1 - glyph->x0;
        i32 glyph_h = glyph->y1 - glyph->y0;

        if (glyph_w <= 0 || glyph_h <= 0) {
            current_x += glyph->xadvance + (f32)letter_spacing;
            continue;
        }

        i32 clip_x_start = STAR_MAX(0, (i32)floorf(glyph_screen_x_f));
        i32 clip_y_start = STAR_MAX(0, (i32)floorf(glyph_screen_y_f));
        i32 clip_x_end = STAR_MIN(ctx->pixel_w, (i32)ceilf(glyph_screen_x_f + glyph_w));
        i32 clip_y_end = STAR_MIN(ctx->pixel_h, (i32)ceilf(glyph_screen_y_f + glyph_h));

        if (clip_x_start < clip_x_end && clip_y_start < clip_y_end) {
            min_drawn_x = STAR_MIN(min_drawn_x, clip_x_start);
            min_drawn_y = STAR_MIN(min_drawn_y, clip_y_start);
            max_drawn_x = STAR_MAX(max_drawn_x, clip_x_end);
            max_drawn_y = STAR_MAX(max_drawn_y, clip_y_end);

            for (i32 gy = clip_y_start; gy < clip_y_end; ++gy) {
                for (i32 gx = clip_x_start; gx < clip_x_end; ++gx) {
                    u8 alpha;
                    f32 atlas_x_f = (f32)glyph->x0 + ((f32)gx - glyph_screen_x_f);
                    f32 atlas_y_f = (f32)glyph->y0 + ((f32)gy - glyph_screen_y_f);
                    i32 ax0 = (i32)floorf(atlas_x_f); i32 ax1 = ax0 + 1;
                    i32 ay0 = (i32)floorf(atlas_y_f); i32 ay1 = ay0 + 1;
                    if (bilinear) {
                        if (ax0 < glyph->x0 || ax1 >= glyph->x1 || ay0 < glyph->y0 || ay1 >= glyph->y1) {
                            continue;
                        }
                         if (ax0 < 0 || ax1 >= f->atlas_w || ay0 < 0 || ay1 >= f->atlas_h) {
                            continue;
                        }

                        f32 x_frac = atlas_x_f - (f32)ax0;
                        f32 y_frac = atlas_y_f - (f32)ay0;

                        u8 a00 = f->atlas[ay0 * f->atlas_w + ax0];
                        u8 a10 = f->atlas[ay0 * f->atlas_w + ax1];
                        u8 a01 = f->atlas[ay1 * f->atlas_w + ax0];
                        u8 a11 = f->atlas[ay1 * f->atlas_w + ax1];

                        f32 top = (f32)a00 * (1.0f - x_frac) + (f32)a10 * x_frac;
                        f32 bottom = (f32)a01 * (1.0f - x_frac) + (f32)a11 * x_frac;
                        f32 alpha_f = top * (1.0f - y_frac) + bottom * y_frac;
                        alpha = (u8)(alpha_f + 0.5f);
                    } else {
                        alpha = f->atlas[ay0 * f->atlas_w + ax0];
                    }

                    if (alpha > 0) {
                        star_color *target_pixel = &ctx->pixels[gy * ctx->pixel_w + gx];
                        target_pixel->r = get_alpha_lut(color.r, alpha);
                        target_pixel->g = get_alpha_lut(color.g, alpha);
                        target_pixel->b = get_alpha_lut(color.b, alpha);
                    }
                }
            }
        }
        current_x += glyph->xadvance + (f32)letter_spacing;
    }

    if (min_drawn_x != INT_MAX) {
        star_rect total_rect = {min_drawn_x, min_drawn_y, max_drawn_x - min_drawn_x, max_drawn_y - min_drawn_y};
        star_push_clear_rect(ctx, total_rect);
    }
}

void star_init_library(void) {
    init_alpha_lut();
}
#endif
