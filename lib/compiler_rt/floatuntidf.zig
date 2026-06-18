const compiler_rt = @import("../compiler_rt.zig");
const floatFromInt = @import("./float_from_int.zig").floatFromInt;
const symbol = @import("../compiler_rt.zig").symbol;

comptime {
    symbol(&__floatuntidf, "__floatuntidf");
}

pub fn __floatuntidf(a: u128) callconv(.c) f64 {
    return floatFromInt(f64, a);
}
