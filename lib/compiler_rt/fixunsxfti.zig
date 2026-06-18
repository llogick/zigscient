const builtin = @import("builtin");
const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;
const intFromFloat = @import("./int_from_float.zig").intFromFloat;

comptime {
    symbol(&__fixunsxfti, "__fixunsxfti");
}

pub fn __fixunsxfti(a: f80) callconv(.c) u128 {
    return intFromFloat(u128, a);
}
