const builtin = @import("builtin");
const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;
const intFromFloat = @import("./int_from_float.zig").intFromFloat;

comptime {
    symbol(&__fixsfti, "__fixsfti");
}

pub fn __fixsfti(a: f32) callconv(.c) i128 {
    return intFromFloat(i128, a);
}
