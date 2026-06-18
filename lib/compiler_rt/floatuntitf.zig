const compiler_rt = @import("../compiler_rt.zig");
const floatFromInt = @import("./float_from_int.zig").floatFromInt;
const symbol = @import("../compiler_rt.zig").symbol;

comptime {
    if (compiler_rt.want_ppc_abi)
        symbol(&__floatuntitf, "__floatuntikf");
    symbol(&__floatuntitf, "__floatuntitf");
}

pub fn __floatuntitf(a: u128) callconv(.c) f128 {
    return floatFromInt(f128, a);
}
