#+feature dynamic-literals
package sote

import "core:math"
import sa "core:container/small_array"
// import "core:os"
import "base:runtime"
import "base:intrinsics"

import "core:fmt"
import "core:slice"
// import "core:mem"
// import "core:time"
import "core:strings"
// import "core:strconv"

import rl "vendor:raylib"

@private PhysicalInputGamepadQuadrant :: enum { DEADZONE = 0, UP, DOWN, LEFT, RIGHT }
@private PhysicalInputGamepadAxis :: enum { LEFT = 0, RIGHT }
@private PhysicalInputTriggerType :: enum {
    PRESSED, HELD, RELEASED,
    IN_RANGE, OUT_OF_RANGE, ENTER_RANGE, EXIT_RANGE,
    PRESSED_ON_HITBOX,
}

@private PhysicalInput_GamepadAxisPosition :: struct {
    type: PhysicalInputTriggerType,
    quad: PhysicalInputGamepadQuadrant,
    axis: PhysicalInputGamepadAxis,
}

@private PhysicalInput_GamepadButton :: struct {
    type: PhysicalInputTriggerType,
    button: rl.GamepadButton,
}

@private PhysicalInput_Keyboard :: struct {
    type: PhysicalInputTriggerType,
    key: rl.KeyboardKey,
}

@private PhysicalInput_MouseButton :: struct {
    type: PhysicalInputTriggerType,
    button: rl.MouseButton,
}

@private PhysicalInput :: union {
    PhysicalInput_GamepadAxisPosition,
    PhysicalInput_GamepadButton,
    PhysicalInput_Keyboard,
    PhysicalInput_MouseButton,
}

InputSignal :: enum {
    NULL = 0,

    // Group: UI
    UI_UP, UI_DOWN, UI_LEFT, UI_RIGHT, UI_CONFIRM, UI_BACK,
    // Group: Character movement
    CHARA_MOVEMENT_UP, CHARA_MOVEMENT_DOWN, CHARA_MOVEMENT_LEFT, CHARA_MOVEMENT_RIGHT,
    // Group: Text input
    TEXT_INPUT_BACKSPACE, TEXT_INPUT_BACKSPACE_RELEASED, TEXT_INPUT_SUBMIT, TEXT_INPUT_SHIFT, TEXT_INPUT_CONTROL,
    // Group: Debug
}
InputSignalGroup :: bit_set[InputSignal]

INPUT_GROUP_UI := InputSignalGroup{ .UI_UP, .UI_DOWN, .UI_LEFT, .UI_RIGHT }
INPUT_GROUP_CHARA_MOVEMENT := InputSignalGroup{ .CHARA_MOVEMENT_UP, .CHARA_MOVEMENT_DOWN, .CHARA_MOVEMENT_LEFT, .CHARA_MOVEMENT_RIGHT }
INPUT_GROUP_TEXT_INPUT := InputSignalGroup{ .TEXT_INPUT_BACKSPACE, .TEXT_INPUT_BACKSPACE_RELEASED, .TEXT_INPUT_SUBMIT, .TEXT_INPUT_SHIFT, .TEXT_INPUT_CONTROL, }
INPUT_GROUP_DEBUG := InputSignalGroup{  }

// what physical inputs can trigger which InputSignal's?
@private InputBindings :: [InputSignal][]PhysicalInput

@private DEADZONE :: 0.12
@private DEFAULT_INPUT_BINDINGS := InputBindings{
    .NULL = {},

    .UI_UP = {
        PhysicalInput_GamepadAxisPosition{
            type = .ENTER_RANGE,
            quad = .UP,
            axis = .LEFT,
        },
        PhysicalInput_GamepadButton{
            type = .PRESSED,
            button = .LEFT_FACE_UP,
        },
        PhysicalInput_Keyboard{
            type = .PRESSED,
            key = .UP,
        },
    },
    .UI_DOWN = {
        PhysicalInput_GamepadAxisPosition{
            type = .ENTER_RANGE,
            quad = .DOWN,
            axis = .LEFT,
        },
        PhysicalInput_GamepadButton{
            type = .PRESSED,
            button = .LEFT_FACE_DOWN,
        },
        PhysicalInput_Keyboard{
            type = .PRESSED,
            key = .DOWN,
        },
    },
    .UI_LEFT = {
        PhysicalInput_GamepadAxisPosition{
            type = .ENTER_RANGE,
            quad = .LEFT,
            axis = .LEFT,
        },
        PhysicalInput_GamepadButton{
            type = .PRESSED,
            button = .LEFT_FACE_LEFT,
        },
        PhysicalInput_Keyboard{
            type = .PRESSED,
            key = .LEFT,
        },
    },
    .UI_RIGHT = {
        PhysicalInput_GamepadAxisPosition{
            type = .ENTER_RANGE,
            quad = .RIGHT,
            axis = .LEFT,
        },
        PhysicalInput_GamepadButton{
            type = .PRESSED,
            button = .LEFT_FACE_RIGHT,
        },
        PhysicalInput_Keyboard{
            type = .PRESSED,
            key = .RIGHT,
        },
    },
    .UI_CONFIRM = {
        PhysicalInput_GamepadButton{
            type = .PRESSED,
            button = .RIGHT_FACE_RIGHT,
        },
        PhysicalInput_Keyboard{
            type = .PRESSED,
            key = .ENTER,
        },
        PhysicalInput_Keyboard{
            type = .PRESSED,
            key = .X,
        },
        PhysicalInput_MouseButton{
            type = .PRESSED_ON_HITBOX,
            button = .LEFT,
        },
    },
    .UI_BACK = {
        PhysicalInput_GamepadButton{
            type = .PRESSED,
            button = .RIGHT_FACE_DOWN,
        },
        PhysicalInput_Keyboard{
            type = .PRESSED,
            key = .BACKSPACE,
        },
        PhysicalInput_Keyboard{
            type = .PRESSED,
            key = .Z,
        },
    },

    .CHARA_MOVEMENT_UP = {
        PhysicalInput_GamepadAxisPosition{
            type = .IN_RANGE,
            quad = .UP,
            axis = .LEFT,
        },
        PhysicalInput_GamepadButton{
            type = .HELD,
            button = .LEFT_FACE_UP,
        },
        PhysicalInput_Keyboard{
            type = .HELD,
            key = .UP,
        },
    },
    .CHARA_MOVEMENT_DOWN = {
        PhysicalInput_GamepadAxisPosition{
            type = .IN_RANGE,
            quad = .DOWN,
            axis = .LEFT,
        },
        PhysicalInput_GamepadButton{
            type = .HELD,
            button = .LEFT_FACE_DOWN,
        },
        PhysicalInput_Keyboard{
            type = .HELD,
            key = .DOWN,
        },
    },
    .CHARA_MOVEMENT_LEFT = {
        PhysicalInput_GamepadAxisPosition{
            type = .IN_RANGE,
            quad = .LEFT,
            axis = .LEFT,
        },
        PhysicalInput_GamepadButton{
            type = .HELD,
            button = .LEFT_FACE_LEFT,
        },
        PhysicalInput_Keyboard{
            type = .HELD,
            key = .LEFT,
        },
    },
    .CHARA_MOVEMENT_RIGHT = {
        PhysicalInput_GamepadAxisPosition{
            type = .IN_RANGE,
            quad = .RIGHT,
            axis = .LEFT,
        },
        PhysicalInput_GamepadButton{
            type = .HELD,
            button = .LEFT_FACE_RIGHT,
        },
        PhysicalInput_Keyboard{
            type = .HELD,
            key = .RIGHT,
        },
    },

    .TEXT_INPUT_BACKSPACE = {
        PhysicalInput_Keyboard{
            type = .PRESSED,
            key = .BACKSPACE,
        },
        PhysicalInput_GamepadButton{
            type = .PRESSED,
            button = .RIGHT_FACE_DOWN,
        },
    },
    .TEXT_INPUT_BACKSPACE_RELEASED = {
        PhysicalInput_Keyboard{
            type = .RELEASED,
            key = .BACKSPACE,
        },
        PhysicalInput_GamepadButton{
            type = .RELEASED,
            button = .RIGHT_FACE_DOWN,
        },
    },
    .TEXT_INPUT_SUBMIT = {
        PhysicalInput_Keyboard{
            type = .PRESSED,
            key = .ENTER,
        },
        PhysicalInput_GamepadButton{
            type = .PRESSED,
            button = .RIGHT_FACE_RIGHT,
        },
    },
    .TEXT_INPUT_SHIFT = {
        PhysicalInput_Keyboard{
            type = .HELD,
            key = .LEFT_SHIFT,
        },
        PhysicalInput_Keyboard{
            type = .HELD,
            key = .RIGHT_SHIFT,
        },
    },
    .TEXT_INPUT_CONTROL = {
        PhysicalInput_Keyboard{
            type = .HELD,
            key = .LEFT_CONTROL,
        },
        PhysicalInput_Keyboard{
            type = .HELD,
            key = .RIGHT_CONTROL,
        },
    },
}

@private InputState :: enum {
    NO_NAVIGATION = 0,
    SITTING_ON_INDEX,
    POINTER_NAVIGATION,
    ANIMATING_INDEX_TO_INDEX,
    ANIMATING_POINTER_TO_INDEX,
}

@private HitboxConnections :: bit_set[enum {
    UP,
    DOWN,
    LEFT,
    RIGHT,
}]

@private MAX_GAMEPADS :: 16
@private POINTER_ANIMATION_SPEED :: 9.25
@private INVALID_INDEX :: [2]int{ -1, -1 }
InputController :: struct {
    // Signaling and physical input ctl
    signals: InputSignalGroup,
    text_input: sa.Small_Array(256, rune),
    inputs_this_frame: sa.Small_Array(64, PhysicalInput),
    bindings: InputBindings,
    gamepads: [MAX_GAMEPADS]struct {
        available: bool,
        // quad/last_quad can only transition between DEADZONE <-> NON-DEADZONE states
        // which is useful for UI_* signals since otherwise the behavior would be weird
        //
        // actual_quad/last_actual_quad are the actual current/prev locations of the axes
        // this is useful for CHARA_MOVEMENT_* signals
        quad, last_quad, actual_quad, last_actual_quad: [PhysicalInputGamepadAxis]PhysicalInputGamepadQuadrant,
    },

    // Pointer ctl
    // Requires a very minimal knowledge of the UI layout to be sent (final hitboxes)
    // this way it knows where to set the pointer
    //
    // This is also neat because it retains `canon_index` which is used
    // to figure out what UI element the user just UI_CONFIRM-ed
    state: InputState,
    pointer_on_any_hitbox: bool,
    animation_progress: f32,
    anim_from_index, anim_to_index, default_index, canon_index: [2]int,
    anim_from_position: [2]int,
    last_hitbox_dimensions, hitbox_dimensions: [2]int,
    hitbox_stack: [128]struct {
        hitbox: [4]int,
        connections: HitboxConnections,
    },
}

input_controller_init :: proc(this: ^InputController, bindings: InputBindings) {
    this^ = {}
    this.bindings = bindings
    this.canon_index = INVALID_INDEX
}
input_controller_init_default :: proc(this: ^InputController) { input_controller_init(this, DEFAULT_INPUT_BINDINGS) }
input_controller_capture :: proc(this: ^InputController, group: InputSignalGroup) { this.signals -= group }
input_controller_has_signal :: proc(this: ^InputController, signal: InputSignal) -> (bool) { return (signal in this.signals) }
input_controller_get_canon_index :: proc(this: ^InputController) -> ([2]int) { return this.canon_index }
input_controller_set_default_index :: proc(this: ^InputController, x, y: int) { this.default_index = { x,y } }

// POINTER AND HITBOX HANDLING
input_controller_xy_to_index :: proc(this: ^InputController, x, y: int) -> (int) {
    out := (y * this.hitbox_dimensions[0]) + x
    assert(out < len(this.hitbox_stack))
    return out
}

input_controller_set_hitbox_dimensions :: proc(this: ^InputController, w, h: int) {
    assert(w >= 0 && h >= 0)
    this.hitbox_dimensions = { w, h }
}

input_controller_buffer_hitbox :: proc(this: ^InputController, x, y: int, hitbox: [4]int, connections: HitboxConnections) {
    assert(x >= 0 && x < this.hitbox_dimensions[0] && y >= 0 && y < this.hitbox_dimensions[1])
    assert(hitbox[0] >= 0 && hitbox[1] >= 0 && hitbox[2] >= 0 && hitbox[3] >= 0)
    this.hitbox_stack[input_controller_xy_to_index(this, x, y)] = { hitbox = hitbox, connections = connections }
}

input_controller_get_hitbox :: proc(this: ^InputController, x, y: int) -> ([4]int) {
    assert(x >= 0 && x < this.hitbox_dimensions[0] && y >= 0 && y < this.hitbox_dimensions[1])
    return this.hitbox_stack[input_controller_xy_to_index(this, x, y)].hitbox
}

input_controller_auto_connect :: proc(this: ^InputController, x, y: int) -> (out: HitboxConnections) {
    is_valid_index :: #force_inline proc(this: ^InputController, x, y: int) -> (bool) {
        return !(x >= this.hitbox_dimensions[0] || x < 0 || y >= this.hitbox_dimensions[1] || y < 0)
    }
    // out = {}
    if is_valid_index(this, x+1, y) { out += { .RIGHT }     }
    if is_valid_index(this, x-1, y) { out += { .LEFT }      }
    if is_valid_index(this, x, y+1) { out += { .DOWN }      }
    if is_valid_index(this, x, y-1) { out += { .UP }        }
    return
}

input_controller_get_text_input_as_string :: #force_inline proc(this: ^InputController, talloc: runtime.Allocator) -> (string) {
    sb := strings.builder_make_len_cap(0, 256, talloc)
    for r in sa.slice(&this.text_input) { strings.write_rune(&sb, r) }
    return strings.to_string(sb)
}

input_controller_text_input_includes :: #force_inline proc(this: ^InputController, r: rune) -> (bool) {
    for input_r in sa.slice(&this.text_input) {
        if input_r == r { return true }
    }
    return false
}

// PERF
// ~14us (debug) / ~4.5us (favor_size)
@(optimization_mode="favor_size")
input_controller_gather_signals :: proc(this: ^InputController) {
    this.signals = {}
    sa.clear(&this.text_input)
    sa.clear(&this.inputs_this_frame)
    any_gamepad_in_quad :: proc(this: ^InputController, quad: PhysicalInputGamepadQuadrant, axis: PhysicalInputGamepadAxis) -> (bool) {
        for i := 0; i < MAX_GAMEPADS; i += 1 {
            if !this.gamepads[i].available { continue }
            if this.gamepads[i].actual_quad[axis] == quad {
                return true
            }
        }
        return false
    }

    any_gamepad_entered_quad :: proc(this: ^InputController, quad: PhysicalInputGamepadQuadrant, axis: PhysicalInputGamepadAxis) -> (bool) {
        for i := 0; i < MAX_GAMEPADS; i += 1 {
            if !this.gamepads[i].available { continue }
            if this.gamepads[i].quad[axis] == quad && this.gamepads[i].last_quad[axis] != quad {
                return true
            }
        }
        return false
    }

    any_gamepad_exited_quad :: proc(this: ^InputController, quad: PhysicalInputGamepadQuadrant, axis: PhysicalInputGamepadAxis) -> (bool) {
        for i := 0; i < MAX_GAMEPADS; i += 1 {
            if !this.gamepads[i].available { continue }
            if this.gamepads[i].quad[axis] != quad && this.gamepads[i].last_quad[axis] == quad {
                return true
            }
        }
        return false
    }

    any_gamepad_button_pressed :: proc(this: ^InputController, button: rl.GamepadButton) -> (bool) {
        for i := 0; i < MAX_GAMEPADS; i += 1 {
            if !this.gamepads[i].available { continue }
            if rl.IsGamepadButtonPressed(i32(i), button) {
                return true
            }
        }
        return false
    }

    any_gamepad_button_held :: proc(this: ^InputController, button: rl.GamepadButton) -> (bool) {
        for i := 0; i < MAX_GAMEPADS; i += 1 {
            if !this.gamepads[i].available { continue }
            if rl.IsGamepadButtonDown(i32(i), button) {
                return true
            }
        }
        return false
    }

    any_gamepad_button_released :: proc(this: ^InputController, button: rl.GamepadButton) -> (bool) {
        for i := 0; i < MAX_GAMEPADS; i += 1 {
            if !this.gamepads[i].available { continue }
            if rl.IsGamepadButtonReleased(i32(i), button) {
                return true
            }
        }
        return false
    }

    // Acquire necessary gamepad info
    for i := 0; i < MAX_GAMEPADS; i += 1 {
        this_gp := &this.gamepads[i]
        if rl.IsGamepadAvailable(i32(i)) {
            this_gp.available = true

            LEFT_AXES := [?]rl.GamepadAxis{ .LEFT_X, .LEFT_Y }
            RIGHT_AXES := [?]rl.GamepadAxis{ .RIGHT_X, .RIGHT_Y }

            c_axis := 0
            this_gp.last_quad = this_gp.quad
            for c_axis < 2 {
                determine_quad :: proc(this: ^InputController, pos_x, pos_y: f32) -> (PhysicalInputGamepadQuadrant) {
                    // TODO: replace DEADZONE with this.deadzone customizable variable
                    in_deadzone :: proc(this: ^InputController, pos: f32) -> (bool) {
                        return !((pos > 0 && pos > DEADZONE) || (pos < 0 && pos < -DEADZONE))
                    }

                    if in_deadzone(this, pos_x) && in_deadzone(this, pos_y) { return .DEADZONE }
                    else if in_deadzone(this, pos_x) { return (pos_y > 0 ? .DOWN : .UP) }
                    else if in_deadzone(this, pos_y) { return (pos_x > 0 ? .RIGHT : .LEFT) }
                    return .DEADZONE
                }
                list: []rl.GamepadAxis = (c_axis == 0 ? LEFT_AXES[:] : RIGHT_AXES[:])
                which_axis: PhysicalInputGamepadAxis = (c_axis == 0 ? .LEFT : .RIGHT)
                pos_x := rl.GetGamepadAxisMovement(i32(i), list[0])
                pos_y := rl.GetGamepadAxisMovement(i32(i), list[1])
                q := determine_quad(this, pos_x, pos_y)

                // Only set quad upon transition from DEADZONE <-> NON-DEADZONE
                if q == .DEADZONE {
                    this_gp.quad[which_axis] = .DEADZONE
                } else if this_gp.quad[which_axis] == .DEADZONE && q != .DEADZONE {
                    this_gp.quad[which_axis] = q
                }

                this_gp.last_actual_quad[which_axis] = this_gp.actual_quad[which_axis]
                this_gp.actual_quad[which_axis] = q
                c_axis += 1
            }
        } else {
            this_gp^ = {}
        }
    }

    // Read keyboard string input
    for {
    	r := rl.GetCharPressed()
        if r == 0 { break }
        sa.push_back(&this.text_input, (rune)(r))
    }

    // Convert PhysicalInput -> Abstract signal
    toggle :: #force_inline proc(this: ^InputController, key: InputSignal, cond: bool) {
        if cond {
            this.signals += { key }
        }
    }
    for &sig, key in this.bindings {
        for &point in sig {
            switch v in point {
            case PhysicalInput_GamepadAxisPosition:
                assert(v.type == .IN_RANGE || v.type == .OUT_OF_RANGE || v.type == .ENTER_RANGE || v.type == .EXIT_RANGE)
                cond := false
                if v.type == .IN_RANGE {
                    cond = any_gamepad_in_quad(this, v.quad, v.axis)
                } else if v.type == .OUT_OF_RANGE {
                    cond = !any_gamepad_in_quad(this, v.quad, v.axis)
                } else if v.type == .ENTER_RANGE {
                    cond = any_gamepad_entered_quad(this, v.quad, v.axis)
                } else if v.type == .EXIT_RANGE {
                    cond = any_gamepad_exited_quad(this, v.quad, v.axis)
                }
                toggle(this, key, cond)
            case PhysicalInput_GamepadButton:
                assert(v.type == .PRESSED || v.type == .HELD || v.type == .RELEASED)
                cond := false
                if v.type == .PRESSED {
                    cond = any_gamepad_button_pressed(this, v.button)
                } else if v.type == .HELD {
                    cond = any_gamepad_button_held(this, v.button)
                } else if v.type == .RELEASED {
                    cond = any_gamepad_button_released(this, v.button)
                }
                toggle(this, key, cond)
            case PhysicalInput_Keyboard:
                assert(v.type == .PRESSED || v.type == .HELD || v.type == .RELEASED)
                cond := false
                if v.type == .PRESSED {
                    cond = rl.IsKeyPressed(v.key)
                } else if v.type == .HELD {
                    cond = rl.IsKeyDown(v.key)
                } else if v.type == .RELEASED {
                    cond = rl.IsKeyReleased(v.key)
                }
                toggle(this, key, cond)
            case PhysicalInput_MouseButton:
                assert(v.type == .PRESSED || v.type == .HELD || v.type == .RELEASED || v.type == .PRESSED_ON_HITBOX)
                cond := false
                if v.type == .PRESSED {
                    cond = rl.IsMouseButtonPressed(v.button)
                } else if v.type == .HELD {
                    cond = rl.IsMouseButtonDown(v.button)
                } else if v.type == .RELEASED {
                    cond = rl.IsMouseButtonReleased(v.button)
                } else if v.type == .PRESSED_ON_HITBOX {
                    cond = rl.IsMouseButtonPressed(v.button) && this.pointer_on_any_hitbox
                }
                toggle(this, key, cond)
            }
        }
    }

    when DEBUG {
        // if this.signals > {} do fmt.println(this.signals)
    }
}

@(optimization_mode="favor_size")
input_controller_update_pointer :: proc(this: ^InputController) {
    mouse_delta := rl.GetMouseDelta()
    mouse_pos := [2]int{ int(rl.GetMouseX()), int(rl.GetMouseY()) }

    index_delta_given_signals :: proc(this: ^InputController) -> (d_index: [2]int, any_fired: bool) {
        if (.UI_UP in this.signals) {
            any_fired = true
            if this.canon_index[1] - 1 < 0 { return }
            return { 0, -1 }, true
        } else if (.UI_DOWN in this.signals) {
            any_fired = true
            if this.canon_index[1] + 1 >= this.hitbox_dimensions[1] { return }
            return { 0, 1 }, true
        } else if (.UI_LEFT in this.signals) {
            any_fired = true
            if this.canon_index[0] - 1 < 0 { return }
            return { -1, 0 }, true
        } else if (.UI_RIGHT in this.signals) {
            any_fired = true
            if this.canon_index[0] + 1 >= this.hitbox_dimensions[0] { return }
            return { 1, 0 }, true
        }
        return
    }

    is_rect_overlap :: #force_inline proc(cmp1, cmp2: [4]int) -> (bool) {
        if cmp1[0] >= cmp2[0] && cmp1[0] <= cmp2[0]+cmp2[2] && cmp1[1] >= cmp2[1] && cmp1[1] <= cmp2[1]+cmp2[3] {
            return true
        }
        return false
    }

    pointer_logic: for {
        if this.hitbox_dimensions[0] <= 0 || this.hitbox_dimensions[1] <= 0 {
            this.state = .NO_NAVIGATION
        } else if this.hitbox_dimensions != this.last_hitbox_dimensions {
            this.state = .ANIMATING_POINTER_TO_INDEX
            this.animation_progress = 0.0
            this.anim_from_position = { int(rl.GetMouseX()), int(rl.GetMouseY()) }
            if this.default_index == INVALID_INDEX || this.default_index == {0,0} {
                this.anim_to_index = {0,0}
            } else {
                this.anim_to_index = this.default_index
            }
        }

        // Pointer/hitbox logic
        if this.state == .SITTING_ON_INDEX {
            if mouse_delta != {0, 0} {
                // User manually moved pointer
                this.state = .POINTER_NAVIGATION
                this.animation_progress = 0.0
                continue pointer_logic
            }

            // This only happens on frame 0
            if this.canon_index == INVALID_INDEX {
                this.canon_index = {0, 0}
                this.anim_from_index = INVALID_INDEX
            }

            d, any_fired := index_delta_given_signals(this)
            new_index := this.canon_index + d
            if any_fired {
                // In bounds and also non-{0,0}
                // Setup state to begin animating towards our new target_index
                if this.anim_from_index != INVALID_INDEX {
                    this.anim_from_index = this.canon_index
                }

                this.canon_index = new_index
                this.state = .ANIMATING_INDEX_TO_INDEX
                this.animation_progress = 0.0
                this.anim_to_index = new_index
            }
        } else if this.state == .POINTER_NAVIGATION {
            _, any_direction_pressed := index_delta_given_signals(this)
            if any_direction_pressed && mouse_delta == {0, 0} {
                this.state = .ANIMATING_POINTER_TO_INDEX
                this.animation_progress = 0.0
                this.anim_from_position = { int(mouse_pos[0]), int(mouse_pos[1]) }
            }
        }
        break pointer_logic
    }

    // Pointer animation logic
    if this.state == .ANIMATING_INDEX_TO_INDEX || this.state == .ANIMATING_POINTER_TO_INDEX {
        anim_from_index_location :: #force_inline proc(this: ^InputController) -> ([2]int) {
            if this.state == .ANIMATING_POINTER_TO_INDEX {
                return this.anim_from_position
            }
            hb := this.hitbox_stack[input_controller_xy_to_index(this, this.anim_from_index[0], this.anim_from_index[1])].hitbox
            return { hb[0] + hb[2]/2, hb[1] + hb[3]/2 }
        }
        anim_to_index_location :: #force_inline proc(this: ^InputController) -> ([2]int) {
            hb := this.hitbox_stack[input_controller_xy_to_index(this, this.anim_to_index[0], this.anim_to_index[1])].hitbox
            return { hb[0] + hb[2]/2, hb[1] + hb[3]/2 }
        }

        from := anim_from_index_location(this)
        to := anim_to_index_location(this)

        if progress_linear(&this.animation_progress, POINTER_ANIMATION_SPEED) {
            this.state = .SITTING_ON_INDEX
            this.animation_progress = 0.0
            this.anim_from_index = this.anim_to_index
            this.canon_index = this.anim_to_index
            rl.SetMousePosition(i32(to[0]), i32(to[1]))
        } else {
            lerp_x := math.lerp(f32(from[0]), f32(to[0]), this.animation_progress)
            lerp_y := math.lerp(f32(from[1]), f32(to[1]), this.animation_progress)
            rl.SetMousePosition(i32(lerp_x), i32(lerp_y))
        }
    }

    mx := mouse_pos[0]; my := mouse_pos[1]
    this.pointer_on_any_hitbox = false
    outer: for y := 0; y < this.hitbox_dimensions[1]; y += 1 {
        for x := 0; x < this.hitbox_dimensions[0]; x += 1 {
            hitbox := input_controller_get_hitbox(this, x, y)
            if is_rect_overlap({mx, my, 0, 0}, hitbox) {
                if this.state == .POINTER_NAVIGATION {
                    this.canon_index = {x, y}
                }
                rl.SetMouseCursor(.POINTING_HAND)
                this.pointer_on_any_hitbox = true
                break outer
            }
        }
    }
    if !this.pointer_on_any_hitbox {
        rl.SetMouseCursor(.DEFAULT)
        if this.state == .POINTER_NAVIGATION {
            // Not hovering any valid hitbox rn
            this.canon_index = INVALID_INDEX
            input_controller_capture(this, { .UI_CONFIRM })
        }
    }

    this.last_hitbox_dimensions = this.hitbox_dimensions
    this.hitbox_dimensions = {}
    this.hitbox_stack = {}
    this.default_index = INVALID_INDEX
}