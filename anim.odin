#+feature dynamic-literals
package sote

import "core:math"
import sa "core:container/small_array"
import "core:os"
import "vendor:cgltf"
import "core:c/libc/tests"
import "base:runtime"
import "base:intrinsics"

import "core:fmt"
import "core:slice"
import "core:mem"
import "core:time"
import "core:strings"
import "core:strconv"

import rl "vendor:raylib"

SPEED_INSTANT :: 1_000
progress_linear :: proc(p: ^f32, speed: f32) -> (bool) {
    p^ += speed * g.delta
    if p^ > 1.0 { p^ = 1.0; return true }
    else if p^ < 0.0 { p^ = 0.0; return true }
    return false
}

progress_linear_cycle :: proc(p: ^f32, speed: f32) -> (bool) {
    p^ += speed * g.delta
    if p^ > 1.0 { p^ = 0.0; return true }
    else if p^ < 0.0 { p^ = 1.0; return true }
    return false
}

progress_exp :: proc(p: ^f32, speed: f32) -> (bool) {
    p^ += (1.0 - p^) * speed * g.delta
    if p^ > 1.0 { p^ = 1.0; return true }
    else if p^ < 0.0 { p^ = 0.0; return true }
    return false
}

TurboTimer :: struct {
    turbo_timer, effect_timer: f32,
    turbo_speed, effect_speed: f32,
}

turbo_timer_start :: proc(this: ^TurboTimer, turbo_speed, effect_speed: f32) { this^ = { turbo_speed=turbo_speed, effect_speed=effect_speed } }
turbo_timer_stop :: proc(this: ^TurboTimer) { this^ = {} }
turbo_timer_tick :: proc(this: ^TurboTimer) -> (bool) {
    cond_turbo := progress_linear(&this.turbo_timer, this.turbo_speed)
    if cond_turbo {
        return progress_linear_cycle(&this.effect_timer, this.effect_speed)
    }
    return false
}

// TITLE CTL
TITLE_CTL_SPEED :: f32(0.95)
TitleScreenController :: struct {
    progress: f32, // [0.0, 1.0]
    stage: int,
    backwards: bool,
    goto_after_backwards: Scene,
}

title_screen_init :: proc(ctl: ^TitleScreenController) {
    ctl.progress = 0.0
}

title_screen_tick :: proc(ctl: ^TitleScreenController) {
    if !ctl.backwards {
        if progress_linear(&ctl.progress, TITLE_CTL_SPEED) {
            ctl.stage += 1
            ctl.progress = 0.0
            if ctl.stage > 2 {
                ctl.progress = 1.0
                ctl.stage = 2
            }
        }
        if ctl.stage >= 2 && (input_controller_has_signal(&g.input_ctl, .UI_CONFIRM)) && !ctl.backwards {
            index := input_controller_get_canon_index(&g.input_ctl)[1]
            goto: Scene
            if index == 0 {
                goto = .Battle
                battle_controller_setup(&g.battle_control, IMG_BATTLE_BACKGROUND_KAERI1)
            } else if index == 1 {
                goto = .Settings
                settings_menu_set_goto(&g.settings_control, .MainMenu)
            }
            title_screen_start_reversing(&g.title_control, goto)
        }
    } else {
        if progress_linear(&ctl.progress, -TITLE_CTL_SPEED) {
            g.scene = ctl.goto_after_backwards
            // input_controller_toggle_ui(&g.input_ctl, false)
            ctl^ = {}
        }
    }
}

title_screen_start_reversing :: proc(ctl: ^TitleScreenController, goto: Scene) {
    ctl.backwards = true
    ctl.progress = 1.0
    ctl.stage = 3
    ctl.goto_after_backwards = goto
}

// SETTINGS MENU CTL
SETTINGS_CTL_SPEED :: TITLE_CTL_SPEED
SettingsMenuController :: struct {
    progress: f32, // Fade-in/fade-out
    progress_elements: f32, // Element slide in/out
    stage: int,
    backwards: bool,
    goto_after_backwards: Scene,
}

settings_menu_init :: proc(ctl: ^SettingsMenuController) {
    ctl.progress = 0.0
}

settings_menu_set_goto :: proc(ctl: ^SettingsMenuController, goto: Scene) {
    ctl.goto_after_backwards = goto
}

settings_menu_tick :: proc(ctl: ^SettingsMenuController) {
    if !ctl.backwards {
        if progress_linear(&ctl.progress, SETTINGS_CTL_SPEED) {
            ctl.progress = 1.0
        }
        if input_controller_has_signal(&g.input_ctl, .UI_BACK) {
            ctl.backwards = true
            ctl.progress = 1.0
            ctl.progress_elements = 1.0
            ctl.stage = 1
        }
    } else {
        if progress_linear(&ctl.progress, -SETTINGS_CTL_SPEED) {
            g.scene = ctl.goto_after_backwards
            ctl^ = {}
        }
    }
}