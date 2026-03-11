#+feature dynamic-literals
package muslib

import "core:strconv"
import "core:strings"

// Music notes range from
// 0 -> C0
// -max(int) -> C-<some insane amount of octaves>
// max(int) -> C<some insane amount of octaves>
// In practice the editor can place some lower/upper bound on this
Note :: int
INVALID_NOTE :: min(Note)

@private char_to_note_table := map[rune]Note{
    'C' = 0,
    'D' = 2,
    'E' = 4,
    'F' = 5,
    'G' = 7,
    'A' = 9,
    'B' = 11,
}

note_from_string :: proc(s: string) -> (Note) {
    assert(len(s) >= 2)
    note_name := (rune)(s[0])
    sharpness := 0
    octave_multiply := 1
    idx := 1

    // look for # / b / ''
    if s[idx] == '#' {
        sharpness = 1
        idx += 1
    } else if s[idx] == 'b' {
        sharpness = -1
        idx += 1
    } else {
        sharpness = 0
        idx += 0
    }

    // look for - / ''
    if s[idx] == '-' {
        octave_multiply = -1
        idx += 1
    } else {
        octave_multiply = 1
        idx += 0
    }

    // grab number value
    octave_number_str := s[idx:]
    as_uint, parse_uint_ok := strconv.parse_uint(octave_number_str, 10)
    assert(parse_uint_ok)

    final := (int(as_uint) * 12 * octave_multiply) + char_to_note_table[note_name] + sharpness
    return (Note)(final)
}