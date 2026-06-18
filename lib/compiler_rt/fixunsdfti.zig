const compiler_rt = @import("../compiler_rt.zig");
const symbol = @import("../compiler_rt.zig").symbol;
const intFromFloat = @import("./int_from_float.zig").intFromFloat;

comptime {
    symbol(&__fixunsdfti, "__fixunsdfti");
}

pub fn __fixunsdfti(a: f64) callconv(.c) u128 {
    return intFromFloat(u128, a);
}
