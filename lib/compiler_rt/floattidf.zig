const compiler_rt = @import("../compiler_rt.zig");
const symbol = @import("../compiler_rt.zig").symbol;
const floatFromInt = @import("./float_from_int.zig").floatFromInt;

comptime {
    symbol(&__floattidf, "__floattidf");
}

pub fn __floattidf(a: i128) callconv(.c) f64 {
    return floatFromInt(f64, a);
}
