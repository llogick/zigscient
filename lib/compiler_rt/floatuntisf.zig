const builtin = @import("builtin");
const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;
const floatFromInt = @import("./float_from_int.zig").floatFromInt;

comptime {
    symbol(&__floatuntisf, "__floatuntisf");
}

pub fn __floatuntisf(a: u128) callconv(.c) f32 {
    return floatFromInt(f32, a);
}
