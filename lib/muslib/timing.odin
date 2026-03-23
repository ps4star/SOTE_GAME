#+feature dynamic-literals
package muslib
import "base:runtime"
import "base:intrinsics"

import "core:fmt"

import ma "vendor:miniaudio"

// "frames" means audio frames
SMPTE_Timecode :: struct {
    hh, mm, ss, ff: int,
}

@private smpte_timecode_wrap :: proc(tc: SMPTE_Timecode, fps: int) -> (out: SMPTE_Timecode) {
    out = tc
    if out.ff >= fps {
        out.ff -= fps
        out.ss += 1
    }
    if out.ss >= 60 {
        out.ss -= 60
        out.mm += 1
    }
    if out.mm >= 60 {
        out.mm -= 60
        out.hh += 1
    }
    return
}

smpte_timecode_offset_smpte :: proc(base, offset: SMPTE_Timecode, fps: int) -> (out: SMPTE_Timecode) {
    out = {
        hh = base.hh + offset.hh,
        mm = base.mm + offset.mm,
        ss = base.ss + offset.ss,
        ff = base.ff + offset.ff,
    }
    out = smpte_timecode_wrap(out, fps)
    return
}

smpte_timecode_offset_seconds :: proc(base: SMPTE_Timecode, seconds: f32, fps: int) -> (out: SMPTE_Timecode) {
    out = base

    frames := f32(seconds) * f32(fps)
    non_decimal_part := f32(int(seconds))
    decimal_part := seconds - non_decimal_part
    frames_left := int(decimal_part * f32(fps))

    out.ff = frames_left
    out.ss += int(non_decimal_part)
    out = smpte_timecode_wrap(out, fps)
    return
}

smpte_timecode_offset_frames :: proc(base: SMPTE_Timecode, frames: int, fps: int) -> (out: SMPTE_Timecode) {
    out = base
    out.ff += frames
    out = smpte_timecode_wrap(base, fps)
    return
}

smpte_timecode_offset :: proc{
    smpte_timecode_offset_frames,
    smpte_timecode_offset_seconds,
    smpte_timecode_offset_smpte,
}

smpte_timecode_negate :: proc(tc: SMPTE_Timecode) -> (SMPTE_Timecode) {
    return {
        hh = -1 * tc.hh,
        mm = -1 * tc.mm,
        ss = -1 * tc.ss,
        ff = -1 * tc.ff,
    }
}

// Semantic sugar for "offset from a 00h:00m:00s:00f timecode"
smpte_timecode_from_seconds :: proc(seconds: f32, fps: int) -> (out: SMPTE_Timecode) {
    out = smpte_timecode_offset_seconds(SMPTE_Timecode{}, seconds, fps)
    return
}

smpte_timecode_to_pcm_frames :: proc(tc: SMPTE_Timecode, fps: int) -> (out: int) {
    tc := smpte_timecode_wrap(tc, fps)
    out = tc.ff
    out += tc.ss * fps
    out += tc.mm * 60 * fps
    out += tc.hh * 60 * 60 * fps
    return
}

smpte_timecode_to_seconds :: proc(tc: SMPTE_Timecode, fps: int) -> (f32) {
    pcm_frames := smpte_timecode_to_pcm_frames(tc, fps)
    return f32(pcm_frames) / f32(fps)
}

// -1 -> tc < cmp
// 0 -> tc == cmp
// 1 -> tc > cmp
smpte_timecode_compare :: proc(tc, cmp: SMPTE_Timecode) -> (int) {
    if tc.hh != cmp.hh {
        if tc.hh > cmp.hh {
            return 1
        } else {
            return -1
        }
    }
    if tc.mm != cmp.mm {
        if tc.mm > cmp.mm {
            return 1
        } else {
            return -1
        }
    }
    if tc.ss != cmp.ss {
        if tc.ss > cmp.ss {
            return 1
        } else {
            return -1
        }
    }
    if tc.ff != cmp.ff {
        if tc.ff > cmp.ff {
            return 1
        } else {
            return -1
        }
    }
    return 0
}