#+feature dynamic-literals
package sote
import "base:runtime"
import "core:mem"
import "core:unicode/utf8"
import "base:intrinsics"

import "core:fmt"
import "core:mem/virtual"
import "core:strings"
import sa "core:container/small_array"
import "core:os"

import ma "vendor:miniaudio"

MusicEditorNote :: int

@private music_editor_cache_midi_track_len :: proc(this: ^MusicEditor, slot: int) {
    assert(slot < sa.len(this.midi_tracks))
    trk := sa.get_ptr(&this.midi_tracks, slot)

    length := f32(0)
    for ev in trk.events {
        length += ev.deltas_before
    }
    trk.cached_length = length
}

@private music_editor_input_note :: proc(this: ^MusicEditor, slot: int, note: MusicEditorNote, channel: int, deltas_before: f32, velocity: f32) {
    assert(slot < sa.len(this.midi_tracks))
    trk := sa.get_ptr(&this.midi_tracks, slot)

    append(&trk.events, MusicEditorMIDIEvent{
        note_on = note,
        channel = channel,
        deltas_before = 0,
        velocity = velocity,
    })
    append(&trk.events, MusicEditorMIDIEvent{
        note_off = note,
        channel = channel,
        deltas_before = deltas_before,
        velocity = velocity,
    })
}

music_editor_cmd_new_track :: proc(this: ^MusicEditor, line: string) {
    // new_track (NO ARGS)
    sb := strings.builder_make_len_cap(0, 64, this.allocator)
    strings.write_string(&sb, "Track ")
    strings.write_int(&sb, sa.len(this.midi_tracks))
    sa.push_back(&this.midi_tracks, MusicEditorMIDITrack{
        name = strings.clone(strings.to_string(sb), this.allocator),
        cached_length = 0.0,
        events = make([dynamic]MusicEditorMIDIEvent, 0, 1024, this.allocator),
    })
    music_editor_input_note(this, sa.len(this.midi_tracks)-1, MusicEditorNote(64), 0, 1.0, 0.5)
    music_editor_cache_midi_track_len(this, sa.len(this.midi_tracks)-1)
    strings.builder_destroy(&sb)
}

music_editor_cmd_enter :: proc(this: ^MusicEditor, line: string) {
    if this.ui.view == .SurfaceTrackView {
        this.ui.view = .TrackView
    }
}

MusicEditorCommandProc :: proc(this: ^MusicEditor, line: string)
MusicEditorCommandDefinition :: struct {
    procedure: MusicEditorCommandProc,
}
@private MUSIC_EDITOR_CMDS := map[string]MusicEditorCommandDefinition{
    "new_track" = {
        procedure=music_editor_cmd_new_track,
    },
    "enter" = {
        procedure=music_editor_cmd_enter,
    },
}

MusicEditorMIDIEvent :: struct {
    deltas_before: f32,
    note_on: MusicEditorNote,
    note_off: MusicEditorNote,
    channel: int,
    velocity: f32,
}

MusicEditorMIDITrack :: struct {
    name: string,
    cached_length: f32,
    events: [dynamic]MusicEditorMIDIEvent,

    // Playback
    next_event_clock: f32,
    cursor: int,
}

MusicEditorPromptState :: enum {
    NoPrompt = 0,
    Typing,
    ShowErrorMessage,
}

MusicEditorView :: enum {
    SurfaceTrackView,
    TrackView,
    PatchView,
}

MusicEditor :: struct {
    allocator: runtime.Allocator,
    midi_tracks: sa.Small_Array(512, MusicEditorMIDITrack),

    ui: struct {
        enabled: bool,
        view: MusicEditorView,

        prompt_state: MusicEditorPromptState,
        prompt_contents: strings.Builder,
        prompt_history_buffer: [dynamic]string,
        prompt_history_cursor: int,
        prompt_blink_timer: f32,
        prompt_backspace_turbo_timer: TurboTimer,

        track_cursor: int,
        note_cursor: int,
    },

    playback: struct {
        enabled: bool,
        absolute_clock: f32,
        master: ma.pcm_rb,
        device: ma.device,
    },
}

@private begin_prompt :: proc(this: ^MusicEditor) {
    this.ui.prompt_state = .Typing
    this.ui.prompt_blink_timer = 0.0
    strings.builder_reset(&this.ui.prompt_contents)
    strings.write_rune(&this.ui.prompt_contents, cast(rune) ':')
}

@private exit_prompt :: #force_inline proc(this: ^MusicEditor) {
    turbo_timer_stop(&this.ui.prompt_backspace_turbo_timer)
    this.ui.prompt_state = .NoPrompt
    strings.builder_reset(&this.ui.prompt_contents)
}

@private backspace :: #force_inline proc(this: ^MusicEditor) {
    if strings.builder_len(this.ui.prompt_contents) > 1 {
        strings.pop_rune(&this.ui.prompt_contents)
    } else {
        exit_prompt(this)
    }
}

@private add_string_to_prompt :: proc(this: ^MusicEditor, str: string) {
    if strings.builder_len(this.ui.prompt_contents) + len(str) + 8 < strings.builder_cap(this.ui.prompt_contents) {
        strings.write_string(&this.ui.prompt_contents, str)
    }
}

@private submit_line :: proc(this: ^MusicEditor) {
    if this.ui.prompt_state == .ShowErrorMessage {
        this.ui.prompt_state = .Typing
        return
    }
    if this.ui.prompt_state == .NoPrompt {
        panic("called submit_line with no prompt")
    }

    // Add to history
    str := strings.clone(strings.to_string(this.ui.prompt_contents), this.allocator)
    strings.builder_reset(&this.ui.prompt_contents)
    this.ui.prompt_state = .NoPrompt

    idx := 1
    for idx < len(str) {
        r, sz := utf8.decode_rune_in_string(str[idx:])
        if r == (rune)(' ') {
            break
        }
        idx += sz
    }
    cmd_part := str[1:idx]

    // Skip whitespace until first actual argument
    for idx < len(str) {
        r, sz := utf8.decode_rune_in_string(str[idx:])
        if !strings.is_space(r) {
            break
        }
        idx += sz
    }
    arguments_part := str[idx:]

    if (cmd_part in MUSIC_EDITOR_CMDS) {
        // Execute cmd
        exe_proc := MUSIC_EDITOR_CMDS[cmd_part].procedure
        if exe_proc != nil {
            exe_proc(this, arguments_part)
        } else {
            panic("NIL MUSIC EDITOR PROC")
        }
    }
    append(&this.ui.prompt_history_buffer, str)
}

@private snd_callback :: proc "c" (dev: ^ma.device, output, input: rawptr, frame_count: u32) {
    context = runtime.default_context()
    this := (^MusicEditor)(dev.pUserData)
    count := frame_count
    data: rawptr = nil

    deltas := f32(frame_count) / f32(ma.pcm_rb_get_sample_rate(&this.playback.master))
    
    playback: if this.playback.enabled {
        ma.pcm_rb_acquire_write(&this.playback.master, &count, &data); assert(data != nil)

        pcm_data: []f32 = (transmute([^]f32) data)[:frame_count]
        for i := 0; i < this.midi_tracks.len; i += 1 {
            trk := sa.get_ptr(&this.midi_tracks, i)
            if trk.cursor >= len(trk.events) {
                continue
            }
            this_event := &trk.events[trk.cursor]

            // prev := trk.next_event_clock
            trk.next_event_clock += deltas
            event_time_diff := trk.next_event_clock - this_event.deltas_before
            percentage_into_buffer := event_time_diff / deltas
            if event_time_diff >= 0 {
                fmt.println("FIRE EVENT:", this_event^)

                trk.next_event_clock -= this_event.deltas_before
                trk.cursor += 1
            }
        }
        ma.pcm_rb_commit_write(&this.playback.master, count)

        // Final copy
        ma.pcm_rb_acquire_read(&this.playback.master, &count, &data); assert(data != nil)
        intrinsics.mem_copy(output, data, int(count) * size_of(f32) * int(ma.pcm_rb_get_channels(&this.playback.master)))
        ma.pcm_rb_commit_read(&this.playback.master, count)
    }
}

music_editor_init :: proc(this: ^MusicEditor, allocator: runtime.Allocator, ui_enabled: bool) {
    this^ = {}
    this.allocator = allocator
    this.ui.enabled = ui_enabled
    this.ui.prompt_contents = strings.builder_make_len_cap(0, 4096, this.allocator)
    this.ui.prompt_history_buffer = make([dynamic]string, 0, 1024, this.allocator)
    this.ui.prompt_history_cursor = -1
    this.ui.note_cursor = -1
    this.ui.track_cursor = -1

    this.playback.absolute_clock = 0.0
    this.playback.enabled = false

    ma.pcm_rb_init(.f32, 2, 44_100, nil, nil, &this.playback.master)
    ma.pcm_rb_set_sample_rate(&this.playback.master, 44_100)

    dev_conf := ma.device_config_init(.playback)
    dev_conf.dataCallback = snd_callback
    dev_conf.pUserData = this
    dev_conf.playback.channels = 2
    dev_conf.playback.channelMixMode = .simple
    dev_conf.playback.format = .f32
    ma.device_init(nil, &dev_conf, &this.playback.device)
    ma.device_start(&this.playback.device)

    begin_prompt(this)
}

music_editor_tick :: proc(this: ^MusicEditor) {
    update_prompt: if this.ui.enabled {
        BACKSPACE_TURBO_SPEED :: 2
        input_as_string := input_controller_get_text_input_as_string(&g.input_ctl, context.temp_allocator)
        if len(input_as_string) > 0 {
            // fmt.println(input_as_string)
        }
        if this.ui.prompt_state == .NoPrompt {
            turbo_timer_stop(&this.ui.prompt_backspace_turbo_timer)
            if strings.index_rune(input_as_string, (rune)(':')) > -1 {
                begin_prompt(this)
                return
            }
        } else if this.ui.prompt_state == .Typing {
            input_controller_capture(&g.input_ctl, INPUT_GROUP_UI)
            if input_controller_has_signal(&g.input_ctl, .TEXT_INPUT_SUBMIT) {
                submit_line(this)
                return
            }

            progress_linear_cycle(&this.ui.prompt_blink_timer, 1)

            // Handle backspace
            if input_controller_has_signal(&g.input_ctl, .TEXT_INPUT_BACKSPACE) {
                backspace(this)
                turbo_timer_start(&this.ui.prompt_backspace_turbo_timer, BACKSPACE_TURBO_SPEED, BACKSPACE_TURBO_SPEED * 20)
            } else if input_controller_has_signal(&g.input_ctl, .TEXT_INPUT_BACKSPACE_RELEASED) {
                turbo_timer_stop(&this.ui.prompt_backspace_turbo_timer)
            }
            if turbo_timer_tick(&this.ui.prompt_backspace_turbo_timer) { backspace(this) }

            if len(input_as_string) > 0 {
                add_string_to_prompt(this, input_as_string)
            }
        } else if this.ui.prompt_state == .ShowErrorMessage {
            // TODO: implement show error message thing
            turbo_timer_stop(&this.ui.prompt_backspace_turbo_timer)
        }
    }

    update_view: if this.ui.enabled {
        if this.ui.view == .SurfaceTrackView {
            if input_controller_has_signal(&g.input_ctl, .UI_CONFIRM) {
                if this.ui.track_cursor >= 0 {
                    this.ui.view = .TrackView
                    return
                }
            }
        } else if this.ui.view == .TrackView {

        } else if this.ui.view == .PatchView {

        }
    }
}

music_editor_toggle_playback :: proc(this: ^MusicEditor, playback: bool) {
    this.playback.enabled = playback
}
