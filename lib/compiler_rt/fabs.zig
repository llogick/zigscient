const std = @import("std");
const builtin = @import("builtin");
const arch = builtin.cpu.arch;
const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;

comptime {
    symbol(&__fabsh, "__fabsh");
    symbol(&fabsf, "fabsf");
    symbol(&fabs, "fabs");
    symbol(&__fabsx, "__fabsx");
    symbol(&fabsq, "fabsf128");
    symbol(&fabsl, "fabsl");
}

fn __fabsh(a: compiler_rt.f16.Abi) callconv(.c) compiler_rt.f16.Abi {
    return compiler_rt.f16.toAbi(fabs_f16(compiler_rt.f16.fromAbi(a)));
}
pub fn fabs_f16(a: f16) f16 {
    return generic_fabs(a);
}

fn fabsf(a: compiler_rt.f32.Abi) callconv(.c) compiler_rt.f32.Abi {
    return compiler_rt.f32.toAbi(fabs_f32(compiler_rt.f32.fromAbi(a)));
}
pub fn fabs_f32(a: f32) f32 {
    return generic_fabs(a);
}

fn fabs(a: compiler_rt.f64.Abi) callconv(.c) compiler_rt.f64.Abi {
    return compiler_rt.f64.toAbi(fabs_f64(compiler_rt.f64.fromAbi(a)));
}
pub fn fabs_f64(a: f64) f64 {
    return generic_fabs(a);
}

fn __fabsx(a: compiler_rt.f80.Abi) callconv(.c) compiler_rt.f80.Abi {
    return compiler_rt.f80.toAbi(fabs_f80(compiler_rt.f80.fromAbi(a)));
}
pub fn fabs_f80(a: f80) f80 {
    return generic_fabs(a);
}

fn fabsq(a: compiler_rt.f128.Abi) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(fabs_f128(compiler_rt.f128.fromAbi(a)));
}
pub fn fabs_f128(a: f128) f128 {
    return generic_fabs(a);
}

pub fn fabsl(x: c_longdouble) callconv(.c) c_longdouble {
    switch (@typeInfo(c_longdouble).float.bits) {
        64 => return fabs_f64(x),
        80 => return fabs_f80(x),
        128 => return fabs_f128(x),
        else => comptime unreachable,
    }
}

inline fn generic_fabs(x: anytype) @TypeOf(x) {
    const T = @TypeOf(x);
    const TBits = @Int(.unsigned, @typeInfo(T).float.bits);
    const float_bits: TBits = @bitCast(x);
    const remove_sign = ~@as(TBits, 0) >> 1;
    return @bitCast(float_bits & remove_sign);
}
