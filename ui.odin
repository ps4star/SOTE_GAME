package sote
import "base:runtime"
import "core:strings"
import "core:fmt"
import "core:slice"
// import "core:time"
import sa "core:container/small_array"

import "./lib/clay"
import rl "vendor:raylib"

@private ImageWrapper :: struct {
    rl_img: rl.Image,
    src: []u8,
}

@private Context :: struct {
    background_img: ImageWrapper,
    background_tex: rl.Texture2D,

    gauge_img: rl.Image,
    gauge_tex: rl.Texture2D,
}
@private ctx: Context

@private prime_background :: proc(img: []u8) {
    if rl.IsImageValid(ctx.background_img.rl_img) && uintptr(slice.as_ptr(img)) == uintptr(slice.as_ptr(ctx.background_img.src)) {
        return
    }
    if rl.IsTextureValid(ctx.background_tex) {
        rl.UnloadTexture(ctx.background_tex)
    }
    ctx.background_img.src = img
    ctx.background_img.rl_img = rl.LoadImageFromMemory(".png", raw_data(img), i32(len(img)))
    ctx.background_tex = rl.LoadTextureFromImage(ctx.background_img.rl_img)
}

@private prime_gauge :: proc() {
    if !rl.IsImageValid(ctx.gauge_img) {
        ctx.gauge_img = rl.LoadImageFromMemory(".png", raw_data(IMG_UI_GAUGE), i32(len(IMG_UI_GAUGE)))
        if rl.IsTextureValid(ctx.gauge_tex) {
            rl.UnloadTexture(ctx.gauge_tex)
        }
        ctx.gauge_tex = rl.LoadTextureFromImage(ctx.gauge_img)
    }
}

Element_None :: struct {}
Element_TitleBackgroundImage :: struct { img: []u8, }
Element_TitleButton :: struct { text: i18n, index: int, }
Element_SettingsBackgroundImage :: struct { img: []u8, }
// Element_CutsceneBackgroundImage :: struct { img: []u8, }

Element_Battle :: struct {}
Element_BattleGauge :: struct { id: BattleEntityID, }

Element_MusicEditor :: struct {}
Element_MusicEditorPrompt :: struct {}
Element_MusicEditorFrame :: struct {}
Element_MusicEditorTrackSurface :: struct { index: int, }

Element_Any :: union {
    Element_None,
    Element_TitleBackgroundImage,
    Element_TitleButton,
    Element_SettingsBackgroundImage,
    // Element_CutsceneBackgroundImage,

    Element_Battle,
    Element_BattleGauge,

    Element_MusicEditor,
    Element_MusicEditorPrompt,
    Element_MusicEditorFrame,
    Element_MusicEditorTrackSurface,
}

text_height :: proc(font_id: int) -> (f32) {
    f := &g.fonts[font_id]
    return f32(f.line_height) * f32(f.size)
}

draw_gauge :: proc(x, y, w, h, progress: f32) {
    // empty := IMG_UI_GAUGE_EMPTY_RECT
    // full := IMG_UI_GAUGE_FULL_RECT
    // full.width *= progress
    // rl.DrawTexturePro(ctx.gauge_tex, empty, {x,y,w,h}, {}, 0, rl.WHITE)
    // rl.DrawTexturePro(ctx.gauge_tex, full, {x,y,w*progress,h}, {}, 0, rl.WHITE)

    rl.DrawRectangleRec({x, y, w, h}, rl.WHITE)
    rl.DrawRectangleRec({x, y, w * progress, h}, rl.BLUE)
}

element :: proc(t: Element_Any) -> (clay.CustomElementConfig) { return { new_clone(t, context.temp_allocator) } }
element_render :: proc(cmd: ^clay.RenderCommand) {
    t := (^Element_Any)(cmd.renderData.custom.customData)^
    switch &variant in t {
    case Element_None:
    case Element_TitleBackgroundImage:
        prime_background(variant.img)

        draw_bg :: proc(alpha: f32, override_to_full := false) {
            alpha := alpha
            original := alpha
            if override_to_full {
                alpha = 1.0
            }
            SIZE_UPTO_ANIMATION_MARGIN :: f32(12)
            dst := rl.Rectangle{0,0,f32(rl.GetScreenWidth()),f32(rl.GetScreenHeight())}
            dst.x += SIZE_UPTO_ANIMATION_MARGIN * (1.0 - alpha)
            dst.y += SIZE_UPTO_ANIMATION_MARGIN * (1.0 - alpha)
            dst.width -= SIZE_UPTO_ANIMATION_MARGIN * 2.0 * (1.0 - alpha)
            dst.height -= SIZE_UPTO_ANIMATION_MARGIN * 2.0 * (1.0 - alpha)
            rl.DrawTexturePro(ctx.background_tex, {0,0,f32(ctx.background_img.rl_img.width),f32(ctx.background_img.rl_img.height)}, dst, {}, 0, rl.Color{255,255,255,u8(255.0 * original)})
        }

        draw_title_text :: proc(alpha: f32) {
            TEXT_Y :: f32(80)
            TEXT_SLIDE_IN_LEFT_MARGIN :: f32(12)
            text := strings.clone_to_cstring(i18n_get(.game_title), context.temp_allocator)
            f := &g.fonts[FONT_ID_TITLE]
            text_size := rl.MeasureTextEx(f.rl_font, text, f32(f.size), 1.0)
            pos := rl.Vector2{
                (f32(rl.GetScreenWidth()) - text_size.x) / 2.0 - TEXT_SLIDE_IN_LEFT_MARGIN * (1.0 - alpha),
                TEXT_Y,
            }
            rl.DrawTextEx(f.rl_font, text, {pos[0]-1, pos[1]}, f32(f.size), 1.0, rl.Color{0,0,0,u8(190.0 * alpha)})
            rl.DrawTextEx(f.rl_font, text, {pos[0]+1, pos[1]}, f32(f.size), 1.0, rl.Color{0,0,0,u8(190.0 * alpha)})
            rl.DrawTextEx(f.rl_font, text, pos, f32(f.size), 1.0, rl.Color{255,255,255,u8(255.0 * alpha)})
        }

        if g.title_control.stage == 0 {
            draw_bg(g.title_control.progress)
        } else if g.title_control.stage == 1 {
            draw_bg(1.0)
            draw_title_text(g.title_control.progress)
        } else if g.title_control.stage == 2 {
            draw_bg(1.0)
            draw_title_text(1.0)
        } else if g.title_control.stage == 3 {
            draw_title_text(g.title_control.progress)
            draw_bg(g.title_control.progress, true)
        }
    
    case Element_TitleButton:
        TITLE_BUTTON_SPACING_Y :: f32(64)
        BUTTON_SLIDE_IN_LEFT_MARGIN :: f32(12)
        LINE_ANIM_MARGIN_UNDER :: f32(8)

        if g.title_control.stage < 2 {
            return
        }

        progress := g.title_control.progress

        text := strings.clone_to_cstring(i18n_get(variant.text), context.temp_allocator)
        f := &g.fonts[FONT_ID_TITLE]
        text_size := rl.MeasureTextEx(f.rl_font, text, f32(f.size), 1.0)

        pos := rl.Vector2{
            f32(cmd.boundingBox.x),
            (f32(cmd.boundingBox.y) + (f32(cmd.boundingBox.height) - text_size.y) / 2.0),
        }

        pos[1] += TITLE_BUTTON_SPACING_Y * f32(variant.index)

        if !g.title_control.backwards {
            // pointer_controller_hitbox_dimensions(&g.pointer_control, 1, 2)
            // pointer_controller_buffer_hitbox(&g.pointer_control, {0, variant.index},
            //     { int(pos[0]), int(pos[1]), int(text_size[0]), int(text_size[1]) },
            //     { variant.index == 1, variant.index == 0, false, false },
            // )
        }

        pos[0] -= BUTTON_SLIDE_IN_LEFT_MARGIN * (1.0 - progress)
        rl.DrawTextEx(f.rl_font, text, pos, f32(f.size), 1.0, rl.Color{255,255,255,u8(255.0 * progress)})
        rl.DrawRectangle(i32(cmd.boundingBox.x), i32(pos[1] + text_size[1] + LINE_ANIM_MARGIN_UNDER), i32(text_size[0] * progress), 1, rl.WHITE)

    case Element_SettingsBackgroundImage:
        // settings_menu_tick(&g.settings_control)
        prime_background(variant.img)
        dst := rl.Rectangle{0,0,f32(rl.GetScreenWidth()),f32(rl.GetScreenHeight())}
        rl.DrawTexturePro(ctx.background_tex, {0,0,f32(ctx.background_img.rl_img.width),f32(ctx.background_img.rl_img.height)}, dst, {}, 0, rl.Color{255,255,255,u8(255.0 * g.settings_control.progress)})
    
    case Element_Battle:
        // battle_controller_tick(&g.battle_control)

        // Draw battle bg
        prime_background(g.battle_control.background_img)
        dst := rl.Rectangle{0,0,f32(rl.GetScreenWidth()),f32(rl.GetScreenHeight())}
        rl.DrawTexturePro(ctx.background_tex, {0,0,f32(ctx.background_img.rl_img.width),f32(ctx.background_img.rl_img.height)}, dst, {}, 0, rl.Color{255,255,255,u8(255.0 * g.battle_control.fade_progress)})
    
    case Element_BattleGauge:
        // prime_gauge()
        if variant.id == .Terry {
            progress := battle_controller_get_gauge(&g.battle_control, variant.id)
            draw_gauge(f32(cmd.boundingBox.x), f32(cmd.boundingBox.y), f32(cmd.boundingBox.width), f32(cmd.boundingBox.height), progress)
        }
    
    case Element_MusicEditor:
        // music_editor_tick(&g.music_editor)
    
    case Element_MusicEditorPrompt:
        this := &g.music_editor
        wrote_blink := false
        if this.ui.prompt_state == .TYPING && this.ui.prompt_blink_timer < 0.5 {
            wrote_blink = true
            strings.write_rune(&this.ui.prompt_contents, (rune)('|'))
        }

        rl.DrawTextEx(g.fonts[FONT_ID_UI].rl_font, strings.clone_to_cstring(strings.to_string(this.ui.prompt_contents), context.temp_allocator), {f32(cmd.boundingBox.x), f32(cmd.boundingBox.y)}, f32(g.fonts[FONT_ID_UI].size), 1.0, rl.Color{255,255,255,255})

        if wrote_blink {
            strings.pop_rune(&this.ui.prompt_contents)
        }
    
    case Element_MusicEditorTrackSurface:
        this := &g.music_editor
        bb := [4]int{ int(cmd.boundingBox.x), int(cmd.boundingBox.y), int(cmd.boundingBox.width), int(cmd.boundingBox.height) }

        if variant.index == 0 {
            input_controller_set_hitbox_dimensions(&g.input_ctl, 1,len(this.piece.tracks))
        }
        input_controller_buffer_hitbox(&g.input_ctl, 0,variant.index, bb, input_controller_auto_connect(&g.input_ctl, 0,variant.index))

        color: rl.Color
        if input_controller_get_canon_index(&g.input_ctl)[1] == variant.index {
            color = rl.RED
            this.ui.track_cursor = variant.index
        } else {
            color = rl.LIGHTGRAY
        }
        rl.DrawRectangleLines(i32(cmd.boundingBox.x)+1, i32(cmd.boundingBox.y)+1+i32(variant.index), i32(cmd.boundingBox.width)-1, i32(cmd.boundingBox.height)-1, color)
    
    case Element_MusicEditorFrame:
        this := &g.music_editor
        rl.DrawRectangleLines(i32(cmd.boundingBox.x)+1, i32(cmd.boundingBox.y)+1, i32(cmd.boundingBox.width)-1, i32(cmd.boundingBox.height)-1, rl.LIGHTGRAY)
    }
}