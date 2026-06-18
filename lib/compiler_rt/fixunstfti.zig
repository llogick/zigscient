const builtin = @import("builtin");
const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;
const intFromFloat = @import("./int_from_float.zig").intFromFloat;

comptime {
    if (compiler_rt.want_ppc_abi)
        symbol(&__fixunstfti, "__fixunskfti");
    symbol(&__fixunstfti, "__fixunstfti");
}

pub fn __fixunstfti(a: f128) callconv(.c) u128 {
    return intFromFloat(u128, a);
}
