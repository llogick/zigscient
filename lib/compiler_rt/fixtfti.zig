const compiler_rt = @import("../compiler_rt.zig");
const intFromFloat = @import("./int_from_float.zig").intFromFloat;
const symbol = @import("../compiler_rt.zig").symbol;

comptime {
    if (compiler_rt.want_ppc_abi)
        symbol(&__fixtfti, "__fixkfti");
    symbol(&__fixtfti, "__fixtfti");
}

pub fn __fixtfti(a: f128) callconv(.c) i128 {
    return intFromFloat(i128, a);
}
