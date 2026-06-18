const compiler_rt = @import("../compiler_rt.zig");
const floatFromInt = @import("./float_from_int.zig").floatFromInt;
const symbol = @import("../compiler_rt.zig").symbol;

comptime {
    symbol(&__floattisf, "__floattisf");
}

pub fn __floattisf(a: i128) callconv(.c) f32 {
    return floatFromInt(f32, a);
}
