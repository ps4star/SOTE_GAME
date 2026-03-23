#+feature dynamic-literals
package muslib
import "base:runtime"
import "base:intrinsics"

import "core:fmt"
import "core:strings"
import "core:time"
import "core:strconv"
import hm "core:container/handle_map"
import sa "core:container/small_array"

import ma "vendor:miniaudio"

Semitone :: int
INVALID_SEMITONE :: min(Semitone)

@private note_name_table := map[u8]int{
    'C' = 0,
    'D' = 2,
    'E' = 4,
    'F' = 5,
    'G' = 7,
    'A' = 9,
    'B' = 11,
}

@private name_note_table := map[int]u8{
    0 = 'C',
    1 = 'C', // #
    2 = 'D',
    3 = 'D', // #
    4 = 'E',
    5 = 'F',
    6 = 'F', // #
    7 = 'G',
    8 = 'G', // #
    9 = 'A',
    10 = 'A', // #
    11 = 'B',
}

semitone_from_string :: proc(note_string: string) -> (note: Semitone) {
    if len(note_string) < 2 {
        return INVALID_SEMITONE
    }
    name := note_string[0]
    idx := 1
    sharpness := 0
    octave_multiply := 1

    if note_string[idx] == '#' {
        idx += 1
        sharpness = 1
    } else if note_string[idx] == 'b' {
        idx += 1
        sharpness = -1
    } else {
        idx += 0
        sharpness = 0
    }

    if note_string[idx] == '-' {
        idx += 1
        octave_multiply = -1
    } else {
        idx += 0
        octave_multiply = 1
    }

    name_value, name_ok := note_name_table[name]; assert(name_ok)
    parsed_octave_value, parse_ok := strconv.parse_uint(note_string[idx:], 10); assert(parse_ok)
    note = Semitone((int(parsed_octave_value) * 12 * octave_multiply) + sharpness + name_value)
    return
}

semitone_to_string :: proc(semitone: Semitone, talloc := context.temp_allocator) -> (s: string) {
    // Only uses sharps
    note_name, ok := name_note_table[abs(semitone) % 12]; assert(ok)
    sb := strings.builder_make_len_cap(0, 32, talloc)
    strings.write_rune(&sb, rune(note_name))
    // Sharps: 1, 3, 6, 8, 10
    if note_name == 1 || note_name == 3 || note_name == 6 || note_name == 8 || note_name == 10 {
        strings.write_rune(&sb, rune('#'))
    }
    if semitone < 0 {
        strings.write_rune(&sb, rune('-'))
        strings.write_uint(&sb, uint(abs(-1 - (abs(semitone+1) / 12))), 10)
    } else {
        strings.write_uint(&sb, uint(semitone / 12), 10)
    }
    s = strings.to_string(sb)
    return
}

Note_Segment :: struct {
    start, end: f32, // in range [0.0, 1.0], start <= end
    start_node: ^ma.node,
}

Note_Event :: struct {
    position: SMPTE_Timecode,
    length: SMPTE_Timecode,
    segments: [dynamic]Note_Segment,
}

Track :: struct {
    events: [dynamic]Note_Event,
}

Piece :: struct {
    allocator: runtime.Allocator,
    tracks: map[string]Track,
}

piece_init :: proc(this: ^Piece, allocator := context.allocator) {
    this.allocator = allocator
    this.tracks = make(map[string]Track, 1024, this.allocator)
}

piece_add_track :: proc(this: ^Piece, track_name: string) {
    assert(track_name not_in this.tracks)
    this.tracks[track_name] = Track{}
    track_ptr := &this.tracks[track_name]

    track_ptr.events = make([dynamic]Note_Event, 0, 1024, this.allocator)
}

piece_remove_track :: proc(this: ^Piece, track_name: string) {
    assert(track_name in this.tracks)
    trk_ptr := &this.tracks[track_name]
    delete_dynamic_array(trk_ptr.events)
    delete_key(&this.tracks, track_name)
}