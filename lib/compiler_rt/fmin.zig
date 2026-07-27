const std = @import("std");
const builtin = @import("builtin");
const math = std.math;
const arch = builtin.cpu.arch;
const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;

comptime {
    symbol(&__fminh, "__fminh");
    symbol(&fminf, "fminf");
    symbol(&fmin, "fmin");
    symbol(&__fminx, "__fminx");
    symbol(&fminq, "fminf128");
    symbol(&fminl, "fminl");
}

fn __fminh(x: compiler_rt.f16.Abi, y: compiler_rt.f16.Abi) callconv(.c) compiler_rt.f16.Abi {
    return compiler_rt.f16.toAbi(fmin_f16(compiler_rt.f16.fromAbi(x), compiler_rt.f16.fromAbi(y)));
}
pub fn fmin_f16(x: f16, y: f16) f16 {
    return generic_fmin(f16, x, y);
}

fn fminf(x: compiler_rt.f32.Abi, y: compiler_rt.f32.Abi) callconv(.c) compiler_rt.f32.Abi {
    return compiler_rt.f32.toAbi(fmin_f32(compiler_rt.f32.fromAbi(x), compiler_rt.f32.fromAbi(y)));
}
pub fn fmin_f32(x: f32, y: f32) f32 {
    return generic_fmin(f32, x, y);
}

fn fmin(x: compiler_rt.f64.Abi, y: compiler_rt.f64.Abi) callconv(.c) compiler_rt.f64.Abi {
    return compiler_rt.f64.toAbi(fmin_f64(compiler_rt.f64.fromAbi(x), compiler_rt.f64.fromAbi(y)));
}
pub fn fmin_f64(x: f64, y: f64) f64 {
    return generic_fmin(f64, x, y);
}

fn __fminx(x: compiler_rt.f80.Abi, y: compiler_rt.f80.Abi) callconv(.c) compiler_rt.f80.Abi {
    return compiler_rt.f80.toAbi(fmin_f80(compiler_rt.f80.fromAbi(x), compiler_rt.f80.fromAbi(y)));
}
pub fn fmin_f80(x: f80, y: f80) f80 {
    return generic_fmin(f80, x, y);
}

fn fminq(x: compiler_rt.f128.Abi, y: compiler_rt.f128.Abi) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(fmin_f128(compiler_rt.f128.fromAbi(x), compiler_rt.f128.fromAbi(y)));
}
pub fn fmin_f128(x: f128, y: f128) f128 {
    return generic_fmin(f128, x, y);
}

pub fn fminl(x: c_longdouble, y: c_longdouble) callconv(.c) c_longdouble {
    switch (@typeInfo(c_longdouble).float.bits) {
        64 => return fmin_f64(x, y),
        80 => return fmin_f80(x, y),
        128 => return fmin_f128(x, y),
        else => comptime unreachable,
    }
}

inline fn generic_fmin(comptime T: type, x: T, y: T) T {
    if (math.isNan(x))
        return y;
    if (math.isNan(y))
        return x;
    if (math.signbit(x) != math.signbit(y))
        return if (math.signbit(x)) x else y;
    return if (x < y) x else y;
}

test "generic_fmin" {
    inline for ([_]type{ f32, f64, c_longdouble, f80, f128 }) |T| {
        const nan_val = math.nan(T);
        const Int = @Int(.unsigned, @bitSizeOf(T));

        try std.testing.expect(math.isNan(generic_fmin(T, nan_val, nan_val)));
        try std.testing.expectEqual(@as(T, 1.0), generic_fmin(T, nan_val, 1.0));
        try std.testing.expectEqual(@as(T, 1.0), generic_fmin(T, 1.0, nan_val));

        try std.testing.expectEqual(@as(T, 1.0), generic_fmin(T, 1.0, 10.0));
        try std.testing.expectEqual(@as(T, -1.0), generic_fmin(T, 1.0, -1.0));

        try std.testing.expectEqual(@as(Int, @bitCast(@as(T, -0.0))), @as(Int, @bitCast(generic_fmin(T, 0.0, -0.0))));
        try std.testing.expectEqual(@as(Int, @bitCast(@as(T, -0.0))), @as(Int, @bitCast(generic_fmin(T, -0.0, 0.0))));
    }
}
