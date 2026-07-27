const std = @import("std");
const builtin = @import("builtin");
const math = std.math;
const arch = builtin.cpu.arch;
const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;

comptime {
    symbol(&__fmaxh, "__fmaxh");
    symbol(&fmaxf, "fmaxf");
    symbol(&fmax, "fmax");
    symbol(&__fmaxx, "__fmaxx");
    symbol(&fmaxq, "fmaxf128");
    symbol(&fmaxl, "fmaxl");
}

fn __fmaxh(x: compiler_rt.f16.Abi, y: compiler_rt.f16.Abi) callconv(.c) compiler_rt.f16.Abi {
    return compiler_rt.f16.toAbi(fmax_f16(compiler_rt.f16.fromAbi(x), compiler_rt.f16.fromAbi(y)));
}
pub fn fmax_f16(x: f16, y: f16) f16 {
    return generic_fmax(f16, x, y);
}

fn fmaxf(x: compiler_rt.f32.Abi, y: compiler_rt.f32.Abi) callconv(.c) compiler_rt.f32.Abi {
    return compiler_rt.f32.toAbi(fmax_f32(compiler_rt.f32.fromAbi(x), compiler_rt.f32.fromAbi(y)));
}
pub fn fmax_f32(x: f32, y: f32) f32 {
    return generic_fmax(f32, x, y);
}

fn fmax(x: compiler_rt.f64.Abi, y: compiler_rt.f64.Abi) callconv(.c) compiler_rt.f64.Abi {
    return compiler_rt.f64.toAbi(fmax_f64(compiler_rt.f64.fromAbi(x), compiler_rt.f64.fromAbi(y)));
}
pub fn fmax_f64(x: f64, y: f64) f64 {
    return generic_fmax(f64, x, y);
}

fn __fmaxx(x: compiler_rt.f80.Abi, y: compiler_rt.f80.Abi) callconv(.c) compiler_rt.f80.Abi {
    return compiler_rt.f80.toAbi(fmax_f80(compiler_rt.f80.fromAbi(x), compiler_rt.f80.fromAbi(y)));
}
pub fn fmax_f80(x: f80, y: f80) f80 {
    return generic_fmax(f80, x, y);
}

fn fmaxq(x: compiler_rt.f128.Abi, y: compiler_rt.f128.Abi) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(fmax_f128(compiler_rt.f128.fromAbi(x), compiler_rt.f128.fromAbi(y)));
}
pub fn fmax_f128(x: f128, y: f128) f128 {
    return generic_fmax(f128, x, y);
}

pub fn fmaxl(x: c_longdouble, y: c_longdouble) callconv(.c) c_longdouble {
    switch (@typeInfo(c_longdouble).float.bits) {
        64 => return fmax_f64(x, y),
        80 => return fmax_f80(x, y),
        128 => return fmax_f128(x, y),
        else => comptime unreachable,
    }
}

inline fn generic_fmax(comptime T: type, x: T, y: T) T {
    if (math.isNan(x))
        return y;
    if (math.isNan(y))
        return x;
    if (math.signbit(x) != math.signbit(y))
        return if (math.signbit(x)) y else x;
    return if (x < y) y else x;
}

test "generic_fmax" {
    inline for ([_]type{ f32, f64, c_longdouble, f80, f128 }) |T| {
        const nan_val = math.nan(T);
        const Int = @Int(.unsigned, @bitSizeOf(T));

        try std.testing.expect(math.isNan(generic_fmax(T, nan_val, nan_val)));
        try std.testing.expectEqual(@as(T, 1.0), generic_fmax(T, nan_val, 1.0));
        try std.testing.expectEqual(@as(T, 1.0), generic_fmax(T, 1.0, nan_val));

        try std.testing.expectEqual(@as(T, 10.0), generic_fmax(T, 1.0, 10.0));
        try std.testing.expectEqual(@as(T, 1.0), generic_fmax(T, 1.0, -1.0));

        try std.testing.expectEqual(@as(Int, @bitCast(@as(T, 0.0))), @as(Int, @bitCast(generic_fmax(T, 0.0, -0.0))));
        try std.testing.expectEqual(@as(Int, @bitCast(@as(T, 0.0))), @as(Int, @bitCast(generic_fmax(T, -0.0, 0.0))));
    }
}
