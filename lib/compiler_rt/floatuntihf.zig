const compiler_rt = @import("../compiler_rt.zig");
const symbol = @import("../compiler_rt.zig").symbol;
const floatFromInt = @import("./float_from_int.zig").floatFromInt;

comptime {
    symbol(&__floatuntihf, "__floatuntihf");
}

pub fn __floatuntihf(a: u128) callconv(.c) f16 {
    return floatFromInt(f16, a);
}
