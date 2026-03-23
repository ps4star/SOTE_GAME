#+feature dynamic-literals
package sote
import "base:runtime"
// import "core:mem"
import "core:unicode/utf8"
import "base:intrinsics"

import "core:fmt"
// import "core:mem/virtual"
import "core:strings"
import "core:strconv"
import tscan "core:text/scanner"
import sa "core:container/small_array"
// import "core:os"

import ma "vendor:miniaudio"

import mus "./lib/muslib"

/// MUSIC EDITOR CMDS
music_editor_cmd_new_track :: proc(this: ^Music_Editor, line: string) {
    // new_track (NO ARGS)
    // sb := strings.builder_make_len_cap(0, 64, this.allocator)
    // strings.write_string(&sb, "Track ")
    // strings.write_int(&sb, sa.len(this.tracks))
    // sa.push_back(&this.tracks, MusicTrack{
    //     name = strings.clone(strings.to_string(sb), this.allocator),
    //     cached_length = 0.0,
    //     events = make([dynamic]MusicEvent, 0, 1024, this.allocator),
    // })
    // music_editor_input_note(this, sa.len(this.tracks)-1, note_from_string("C4"), 1.0, 0.5)
    // music_editor_cache_midi_track_len(this, sa.len(this.tracks)-1)
    // strings.builder_destroy(&sb)
}

// SURFACE_TRACK_VIEW: enter into currently selected track
music_editor_cmd_enter :: proc(this: ^Music_Editor, line: string) {
    if this.ui.view == .SURFACE_TRACK_VIEW {
        this.ui.view = .TRACK_VIEW
    }
}

// TRACK_VIEW: input a line of Linum note data to selected track
// Linum documentation: https://linum-notation.org/docs
// music_editor_cmd_linum :: proc(this: ^Music_Editor, line: string) {
//     linum_parse_line :: proc(this: ^Music_Editor, line: string, talloc := context.temp_allocator) -> (out: []MusicEvent) {
//         // this.linum_parser = {}
//         // NOTE: Linum duration values are not contextualized here
//         // Must be contextualized to project BPM etc after this proc exits
//         // In this pre-context stage, duration of 1.0 -> quarter note

//         out = {}
//         events := make([dynamic]MusicEvent, 0, 1024, talloc)

//         LinumToken :: enum {
//             INVALID = 0,
//             NOTE_SEPARATOR,
//             NOTE_LITERAL,
//             NEXT_NOTE_OCTAVE_UP,
//             NEXT_NOTE_OCTAVE_DOWN,
//             OCTAVE_UP,
//             OCTAVE_DOWN,
//             ENTER_HALF_DURATION_SECTION,
//             EXIT_HALF_DURATION_SECTION,
//             ENTER_CHORD_SECTION,
//             EXIT_CHORD_SECTION,
//             PREV_NOTE_DURATION_DOUBLE,
//             PREV_NOTE_DURATION_DOTTED, // 1.5x like in sheet music
//         }
//         tokens := make([dynamic]LinumToken, 0, 1024, talloc)

//         // Tokenizer part
//         scanner: tscan.Scanner
//         tscan.init(&scanner, line)
//         scanner.whitespace -= { rune(' ') }
//         // "1=* 2 3 4 < 1 2 3 4"
//         for {
//             r := tscan.scan(&scanner)
//             if r == tscan.EOF { break }

//             if r == tscan.Int {
//                 as_substr := line[scanner.tok_pos:scanner.tok_end]
//                 as_int, as_int_ok := strconv.parse_int(as_substr, 10)
//                 assert(as_int_ok)
//                 assert(as_int >= 0 && as_int <= 999)
//                 fmt.println("NOTE_LITERAL:", as_substr)

//                 append(&tokens, LinumToken.NOTE_LITERAL)
//                 append(&tokens, cast(LinumToken) as_int)
//             } else if r == ' ' {
//                 append(&tokens, LinumToken.NOTE_SEPARATOR)
//             } else if r == '+' {
//                 append(&tokens, LinumToken.NEXT_NOTE_OCTAVE_UP)
//             } else if r == '-' {
//                 append(&tokens, LinumToken.NEXT_NOTE_OCTAVE_DOWN)
//             } else if r == '=' {
//                 append(&tokens, LinumToken.PREV_NOTE_DURATION_DOUBLE)
//             } else if r == '*' {
//                 append(&tokens, LinumToken.PREV_NOTE_DURATION_DOTTED)
//             } else if r == '[' {
//                 append(&tokens, LinumToken.ENTER_HALF_DURATION_SECTION)
//             } else if r == ']' {
//                 append(&tokens, LinumToken.EXIT_HALF_DURATION_SECTION)
//             } else if r == '(' {
//                 append(&tokens, LinumToken.ENTER_CHORD_SECTION)
//             } else if r == ')' {
//                 append(&tokens, LinumToken.EXIT_CHORD_SECTION)
//             } else if r == '>' {
//                 append(&tokens, LinumToken.OCTAVE_UP)
//             } else if r == '<' {
//                 append(&tokens, LinumToken.OCTAVE_DOWN)
//             } else {
//                 panic(fmt.tprintln("Unknown rune found during linum_parse_line scan:", r))
//             }
//         }

//         line_duration := f32(1.0)
//         line_octave_base := 4

//         point_octave_offset := 0
//         point_duration_multiply := 1.0

//         last_note: ^MusicEvent = nil

//         in_chord := false

//         // Parse tokens
//         tok_cursor := 0
//         for tok_cursor < len(tokens) {
//             if tokens[tok_cursor] == .NOTE_LITERAL {
//                 assert(tok_cursor + 1 < len(tokens))

//                 note := cast(Note) tokens[tok_cursor+1]
//                 append(&events, MusicEvent{
//                     length = line_duration,
//                     note_on = note,
//                     velocity = 0.5,
//                 })
//                 last_note = &events[len(events) - 1]
//                 tok_cursor += 2
//             } else if tokens[tok_cursor] == .NOTE_SEPARATOR {
//                 point_octave_offset = 0
//                 point_duration_multiply = 1.0
//                 last_note = nil
//                 tok_cursor += 1
//             } else if tokens[tok_cursor] == .NEXT_NOTE_OCTAVE_UP {
//                 point_octave_offset += 1
//                 tok_cursor += 1
//             } else if tokens[tok_cursor] == .NEXT_NOTE_OCTAVE_DOWN {
//                 point_octave_offset -= 1
//                 tok_cursor += 1
//             } else if tokens[tok_cursor] == .OCTAVE_UP {
//                 line_octave_base += 1
//                 tok_cursor += 1
//             } else if tokens[tok_cursor] == .OCTAVE_DOWN {
//                 line_octave_base -= 1
//                 tok_cursor += 1
//             } else if tokens[tok_cursor] == .ENTER_HALF_DURATION_SECTION {
//                 line_duration *= 0.5
//                 tok_cursor += 1
//             } else if tokens[tok_cursor] == .EXIT_HALF_DURATION_SECTION {
//                 line_duration *= 2
//                 tok_cursor += 1
//             } else if tokens[tok_cursor] == .ENTER_CHORD_SECTION {
//                 in_chord = true
//                 tok_cursor += 1
//             } else if tokens[tok_cursor] == .EXIT_CHORD_SECTION {
//                 in_chord = false
//                 tok_cursor += 1
//             } else if tokens[tok_cursor] == .PREV_NOTE_DURATION_DOUBLE {
//                 last_note.length *= 2.0
//                 tok_cursor += 1
//             } else if tokens[tok_cursor] == .PREV_NOTE_DURATION_DOTTED {
//                 last_note.length *= 1.5
//                 tok_cursor += 1
//             } else {
//                 panic("INVALID LinumToken")
//             }
//         }

//         out = events[:]
//         return
//     }
// }



Music_Editor_Cmd_Proc :: proc(this: ^Music_Editor, line: string)
Music_Editor_Cmd_Definition :: struct {
    procedure: Music_Editor_Cmd_Proc,
}
@private MUSIC_EDITOR_CMDS := map[string]Music_Editor_Cmd_Definition{
    "new_track" = {
        procedure=music_editor_cmd_new_track,
    },
    "enter" = {
        procedure=music_editor_cmd_enter,
    },
}

Music_Editor_Prompt_State :: enum {
    NO_PROMPT = 0,
    TYPING,
    SHOW_ERROR_MESSAGE,
}

Music_Editor_View :: enum {
    SURFACE_TRACK_VIEW,
    TRACK_VIEW,
    PATCH_VIEW,
}

Music_Editor :: struct {
    allocator: runtime.Allocator,

    piece: mus.Piece,
    graph_controller: mus.Graph_Controller,

    ui: struct {
        enabled: bool,
        view: Music_Editor_View,

        prompt_state: Music_Editor_Prompt_State,
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
        master: ma.pcm_rb,
        device: ma.device,
    },
}

@private begin_prompt :: proc(this: ^Music_Editor) {
    this.ui.prompt_state = .TYPING
    this.ui.prompt_blink_timer = 0.0
    strings.builder_reset(&this.ui.prompt_contents)
    strings.write_rune(&this.ui.prompt_contents, cast(rune) ':')
}

@private exit_prompt :: #force_inline proc(this: ^Music_Editor) {
    turbo_timer_stop(&this.ui.prompt_backspace_turbo_timer)
    this.ui.prompt_state = .NO_PROMPT
    strings.builder_reset(&this.ui.prompt_contents)
}

@private backspace :: #force_inline proc(this: ^Music_Editor) {
    if strings.builder_len(this.ui.prompt_contents) > 1 {
        strings.pop_rune(&this.ui.prompt_contents)
    } else {
        exit_prompt(this)
    }
}

@private add_string_to_prompt :: proc(this: ^Music_Editor, str: string) {
    if strings.builder_len(this.ui.prompt_contents) + len(str) + 8 < strings.builder_cap(this.ui.prompt_contents) {
        strings.write_string(&this.ui.prompt_contents, str)
    }
}

@private submit_line :: proc(this: ^Music_Editor) {
    if this.ui.prompt_state == .SHOW_ERROR_MESSAGE {
        this.ui.prompt_state = .TYPING
        return
    }
    if this.ui.prompt_state == .NO_PROMPT {
        panic("called submit_line with no prompt")
    }

    // Add to history
    str := strings.clone(strings.to_string(this.ui.prompt_contents), this.allocator)
    strings.builder_reset(&this.ui.prompt_contents)
    this.ui.prompt_state = .NO_PROMPT

    idx := 1
    for idx < len(str) {
        r, sz := utf8.decode_rune_in_string(str[idx:])
        if r == (rune)(' ') {
            break
        }
        idx += sz
    }
    if idx > len(str) { return }
    cmd_part := str[1:idx]

    // Skip whitespace until first actual argument
    for idx < len(str) {
        r, sz := utf8.decode_rune_in_string(str[idx:])
        if !(r == ' ' || r == '\t' || r == '\n' || r == '\r') {
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
    this := (^Music_Editor)(dev.pUserData)
    count := frame_count
    data: rawptr = nil

    deltas := f32(frame_count) / f32(ma.pcm_rb_get_sample_rate(&this.playback.master))
    
    playback: if this.playback.enabled {
        ma.pcm_rb_acquire_write(&this.playback.master, &count, &data); assert(data != nil)
        pcm_data: []f32 = (transmute([^]f32) data)[:frame_count]
        {
            _ = mus.Audio_Spec{}
            this.graph_controller.audio_spec = {
                channels = int(ma.pcm_rb_get_channels(&this.playback.master)),
                format = ma.pcm_rb_get_format(&this.playback.master),
                sample_rate = int(ma.pcm_rb_get_sample_rate(&this.playback.master)),
            }
            // mus.graph_controller_graph_read_pcm_frames(&this.graph_controller, "debug", pcm_data, int(count))
        }
        ma.pcm_rb_commit_write(&this.playback.master, count)

        // Final copy
        ma.pcm_rb_acquire_read(&this.playback.master, &count, &data); assert(data != nil)
        intrinsics.mem_copy(output, data, int(count) * size_of(f32) * int(ma.pcm_rb_get_channels(&this.playback.master)))
        ma.pcm_rb_commit_read(&this.playback.master, count)
    }
}

music_editor_init :: proc(this: ^Music_Editor, allocator: runtime.Allocator, ui_enabled: bool) {
    this^ = {}
    this.allocator = allocator
    this.ui.enabled = ui_enabled
    if this.ui.enabled {
        this.ui.prompt_contents = strings.builder_make_len_cap(0, 4096, this.allocator)
        this.ui.prompt_history_buffer = make([dynamic]string, 0, 1024, this.allocator)
        this.ui.prompt_history_cursor = -1
        this.ui.note_cursor = -1
        this.ui.track_cursor = -1
    }

    this.playback.enabled = true

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

music_editor_tick :: proc(this: ^Music_Editor) {
    update_ui: if this.ui.enabled {
        // update_prompt
        BACKSPACE_TURBO_SPEED :: 2
        input_as_string := input_controller_get_text_input_as_string(&g.input_ctl, context.temp_allocator)
        if this.ui.prompt_state == .NO_PROMPT {
            turbo_timer_stop(&this.ui.prompt_backspace_turbo_timer)
            if strings.index_rune(input_as_string, (rune)(':')) > -1 {
                begin_prompt(this)
                return
            }
        } else if this.ui.prompt_state == .TYPING {
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
        } else if this.ui.prompt_state == .SHOW_ERROR_MESSAGE {
            // TODO: implement show error message thing
            turbo_timer_stop(&this.ui.prompt_backspace_turbo_timer)
        }

        // update_view
        if this.ui.view == .SURFACE_TRACK_VIEW {
            if input_controller_has_signal(&g.input_ctl, .UI_CONFIRM) {
                if this.ui.track_cursor >= 0 {
                    this.ui.view = .TRACK_VIEW
                    return
                }
            }
        } else if this.ui.view == .TRACK_VIEW {

        } else if this.ui.view == .PATCH_VIEW {

        }
    }
}

// music_editor_set_playback_enabled :: proc(this: ^Music_Editor, enabled: bool) {
//     this.playback.enabled = enabled
// }