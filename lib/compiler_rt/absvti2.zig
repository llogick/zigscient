const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;
const absv = @import("absv.zig").absv;

comptime {
    symbol(&__absvti2, "__absvti2");
}

pub fn __absvti2(a: i128) callconv(.c) i128 {
    return absv(i128, a);
}
