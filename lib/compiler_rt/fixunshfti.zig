const compiler_rt = @import("../compiler_rt.zig");
const intFromFloat = @import("./int_from_float.zig").intFromFloat;
const symbol = @import("../compiler_rt.zig").symbol;

comptime {
    symbol(&__fixunshfti, "__fixunshfti");
}

pub fn __fixunshfti(a: f16) callconv(.c) u128 {
    return intFromFloat(u128, a);
}
