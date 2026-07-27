//! a raised to integer power of b
//! ported from https://github.com/llvm-mirror/compiler-rt/blob/release_80/lib/builtins/powisf2.c
//! Multiplication order (left-to-right or right-to-left) does not matter for
//! error propagation and this method is optimized for performance, not accuracy.

const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;

comptime {
    symbol(&__powihf2, "__powihf2");
    symbol(&__powisf2, "__powisf2");
    symbol(&__powidf2, "__powidf2");
    symbol(&__powixf2, "__powixf2");
    if (compiler_rt.want_ppc_abi) {
        symbol(&__powitf2, "__powikf2");
    } else {
        symbol(&__powitf2, "__powitf2");
    }
}

inline fn powiXf2(comptime FT: type, a: FT, b: i32) FT {
    var x_a: FT = a;
    var x_b: i32 = b;
    const is_recip: bool = b < 0;
    var r: FT = 1.0;
    while (true) {
        if (@as(u32, @bitCast(x_b)) & @as(u32, 1) != 0) {
            r *= x_a;
        }
        x_b = @divTrunc(x_b, @as(i32, 2));
        if (x_b == 0) break;
        x_a *= x_a; // Multiplication of x_a propagates the error
    }
    return if (is_recip) 1 / r else r;
}

fn __powihf2(a: compiler_rt.f16.Abi, b: i32) callconv(.c) compiler_rt.f16.Abi {
    return compiler_rt.f16.toAbi(powi_f16(compiler_rt.f16.fromAbi(a), b));
}
pub fn powi_f16(a: f16, b: i32) f16 {
    return powiXf2(f16, a, b);
}

fn __powisf2(a: compiler_rt.f32.Abi, b: i32) callconv(.c) compiler_rt.f32.Abi {
    return compiler_rt.f32.toAbi(powi_f32(compiler_rt.f32.fromAbi(a), b));
}
pub fn powi_f32(a: f32, b: i32) f32 {
    return powiXf2(f32, a, b);
}

fn __powidf2(a: compiler_rt.f64.Abi, b: i32) callconv(.c) compiler_rt.f64.Abi {
    return compiler_rt.f64.toAbi(powi_f64(compiler_rt.f64.fromAbi(a), b));
}
pub fn powi_f64(a: f64, b: i32) f64 {
    return powiXf2(f64, a, b);
}

fn __powixf2(a: compiler_rt.f80.Abi, b: i32) callconv(.c) compiler_rt.f80.Abi {
    return compiler_rt.f80.toAbi(powi_f80(compiler_rt.f80.fromAbi(a), b));
}
pub fn powi_f80(a: f80, b: i32) f80 {
    return powiXf2(f80, a, b);
}

fn __powitf2(a: compiler_rt.f128.Abi, b: i32) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(powi_f128(compiler_rt.f128.fromAbi(a), b));
}
pub fn powi_f128(a: f128, b: i32) f128 {
    return powiXf2(f128, a, b);
}

test {
    _ = @import("powiXf2_test.zig");
}
