const compiler_rt = @import("../compiler_rt.zig");
const floatFromInt = @import("./float_from_int.zig").floatFromInt;
const symbol = @import("../compiler_rt.zig").symbol;

comptime {
    if (compiler_rt.want_ppc_abi) {
        symbol(&__floatunsitf, "__floatunsikf");
    } else if (compiler_rt.want_sparc64_abi) {
        symbol(&_Qp_uitoq, "_Qp_uitoq");
    } else if (compiler_rt.want_sparc32_abi) {
        symbol(&__floatunsitf, "_Q_utoq");
    }
    symbol(&__floatunsitf, "__floatunsitf");
}

pub fn __floatunsitf(a: u32) callconv(.c) f128 {
    return floatFromInt(f128, a);
}

fn _Qp_uitoq(c: *f128, a: u32) callconv(.c) void {
    c.* = floatFromInt(f128, a);
}
