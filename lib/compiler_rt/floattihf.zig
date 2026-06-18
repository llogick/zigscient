const builtin = @import("builtin");
const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;
const floatFromInt = @import("./float_from_int.zig").floatFromInt;

comptime {
    symbol(&__floattihf, "__floattihf");
}

pub fn __floattihf(a: i128) callconv(.c) f16 {
    return floatFromInt(f16, a);
}
