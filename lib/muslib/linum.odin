package star_muslib
import "base:runtime"
import "base:intrinsics"

import "core:fmt"
import "core:os"
import "core:strings"
import "core:mem"
import "core:time"
import sa "core:container/small_array"

// Based on https://linum-notation.org/docs/

// Default = quarter note

// [..n]: Note duration is halved within brackets
// (..n): Chord

// =: Double len; used like "1="
// *: 1.5x len; same as dot in sheet music; used like "1=*"
// Must put all = before any *

// >: Permanent octave shift up (resets on next line)
// <: Permanent octave shift down (resets on next line)
// +: Temporary octave shift up (following expr only)
// -: Temporary octave shift down (following expr only)

LinumParser :: struct {
    octave_offset: Note, // The current "<"/">" state

}

linum_parse :: proc(this: ^LinumParser, line: string) {

}

