package sote
import "base:intrinsics"

FLOAT_TOLERANCE :: 0.00005
float_is_near :: proc(n: $F, near: F) -> (bool)
    where intrinsics.type_is_float(F)
{
    if n-F(FLOAT_TOLERANCE) < near && n+F(FLOAT_TOLERANCE) > near {
        return true
    }
    return false
}

float_to_color_comp :: proc "contextless" (n: $F) -> (u8)
    where intrinsics.type_is_float(F)
{
    return u8(n * 255.0)
}