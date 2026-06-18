const compiler_rt = @import("../compiler_rt.zig");
const intFromFloat = @import("./int_from_float.zig").intFromFloat;
const symbol = @import("../compiler_rt.zig").symbol;

comptime {
    symbol(&__fixdfti, "__fixdfti");
}

pub fn __fixdfti(a: f64) callconv(.c) i128 {
    return intFromFloat(i128, a);
}
