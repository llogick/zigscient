//! Ported from musl, which is MIT licensed.
//! https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//!
//! https://git.musl-libc.org/cgit/musl/tree/src/math/truncf.c
//! https://git.musl-libc.org/cgit/musl/tree/src/math/trunc.c

const std = @import("std");
const math = std.math;
const mem = std.mem;
const expect = std.testing.expect;

const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;

comptime {
    symbol(&__trunch, "__trunch");
    symbol(&truncf, "truncf");
    symbol(&trunc, "trunc");
    symbol(&__truncx, "__truncx");
    symbol(&truncq, "truncf128");
    symbol(&truncl, "truncl");
}

fn __trunch(x: compiler_rt.f16.Abi) callconv(.c) compiler_rt.f16.Abi {
    return compiler_rt.f16.toAbi(trunc_f16(compiler_rt.f16.fromAbi(x)));
}
pub fn trunc_f16(x: f16) f16 {
    // TODO: more efficient implementation
    return @floatCast(trunc_f32(x));
}

fn truncf(x: compiler_rt.f32.Abi) callconv(.c) compiler_rt.f32.Abi {
    return compiler_rt.f32.toAbi(trunc_f32(compiler_rt.f32.fromAbi(x)));
}
pub fn trunc_f32(x: f32) f32 {
    const u: u32 = @bitCast(x);
    var e = @as(i32, @intCast(((u >> 23) & 0xFF))) - 0x7F + 9;
    var m: u32 = undefined;

    if (e >= 23 + 9) {
        return x;
    }
    if (e < 9) {
        e = 1;
    }

    m = @as(u32, math.maxInt(u32)) >> @intCast(e);
    if (u & m == 0) {
        return x;
    } else {
        if (compiler_rt.want_float_exceptions) mem.doNotOptimizeAway(x + 0x1p120);
        return @bitCast(u & ~m);
    }
}

fn trunc(x: compiler_rt.f64.Abi) callconv(.c) compiler_rt.f64.Abi {
    return compiler_rt.f64.toAbi(trunc_f64(compiler_rt.f64.fromAbi(x)));
}
pub fn trunc_f64(x: f64) f64 {
    const u: u64 = @bitCast(x);
    var e = @as(i32, @intCast(((u >> 52) & 0x7FF))) - 0x3FF + 12;
    var m: u64 = undefined;

    if (e >= 52 + 12) {
        return x;
    }
    if (e < 12) {
        e = 1;
    }

    m = @as(u64, math.maxInt(u64)) >> @intCast(e);
    if (u & m == 0) {
        return x;
    } else {
        if (compiler_rt.want_float_exceptions) mem.doNotOptimizeAway(x + 0x1p120);
        return @bitCast(u & ~m);
    }
}

fn __truncx(x: compiler_rt.f80.Abi) callconv(.c) compiler_rt.f80.Abi {
    return compiler_rt.f80.toAbi(trunc_f80(compiler_rt.f80.fromAbi(x)));
}
pub fn trunc_f80(x: f80) f80 {
    // TODO: more efficient implementation
    return @floatCast(trunc_f128(x));
}

fn truncq(x: compiler_rt.f128.Abi) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(trunc_f128(compiler_rt.f128.fromAbi(x)));
}
pub fn trunc_f128(x: f128) f128 {
    const u: u128 = @bitCast(x);
    var e = @as(i32, @intCast(((u >> 112) & 0x7FFF))) - 0x3FFF + 16;
    var m: u128 = undefined;

    if (e >= 112 + 16) {
        return x;
    }
    if (e < 16) {
        e = 1;
    }

    m = @as(u128, math.maxInt(u128)) >> @intCast(e);
    if (u & m == 0) {
        return x;
    } else {
        if (compiler_rt.want_float_exceptions) mem.doNotOptimizeAway(x + 0x1p120);
        return @bitCast(u & ~m);
    }
}

pub fn truncl(x: c_longdouble) callconv(.c) c_longdouble {
    switch (@typeInfo(c_longdouble).float.bits) {
        64 => return trunc_f64(x),
        80 => return trunc_f80(x),
        128 => return trunc_f128(x),
        else => comptime unreachable,
    }
}

test trunc_f16 {
    try expect(trunc_f16(1.3) == 1.0);
    try expect(trunc_f16(-1.3) == -1.0);
    try expect(math.isPositiveZero(trunc_f16(0.2)));
    try expect(math.isNegativeZero(trunc_f16(-0.2)));
    try expect(math.isPositiveZero(trunc_f16(0.0)));
    try expect(math.isNegativeZero(trunc_f16(-0.0)));
    try expect(math.isPositiveInf(trunc_f16(math.inf(f32))));
    try expect(math.isNegativeInf(trunc_f16(-math.inf(f32))));
    try expect(math.isNan(trunc_f16(math.nan(f32))));
}

test trunc_f32 {
    try expect(trunc_f32(1.3) == 1.0);
    try expect(trunc_f32(-1.3) == -1.0);
    try expect(math.isPositiveZero(trunc_f32(0.2)));
    try expect(math.isNegativeZero(trunc_f32(-0.2)));
    try expect(math.isPositiveZero(trunc_f32(0.0)));
    try expect(math.isNegativeZero(trunc_f32(-0.0)));
    try expect(math.isPositiveInf(trunc_f32(math.inf(f32))));
    try expect(math.isNegativeInf(trunc_f32(-math.inf(f32))));
    try expect(math.isNan(trunc_f32(math.nan(f32))));
}

test trunc_f64 {
    try expect(trunc_f64(1.3) == 1.0);
    try expect(trunc_f64(-1.3) == -1.0);
    try expect(math.isPositiveZero(trunc_f64(0.2)));
    try expect(math.isNegativeZero(trunc_f64(-0.2)));
    try expect(math.isPositiveZero(trunc_f64(0.0)));
    try expect(math.isNegativeZero(trunc_f64(-0.0)));
    try expect(math.isPositiveInf(trunc_f64(math.inf(f64))));
    try expect(math.isNegativeInf(trunc_f64(-math.inf(f64))));
    try expect(math.isNan(trunc_f64(math.nan(f64))));
}

test trunc_f80 {
    try expect(trunc_f80(1.3) == 1.0);
    try expect(trunc_f80(-1.3) == -1.0);
    try expect(math.isPositiveZero(trunc_f80(0.2)));
    try expect(math.isNegativeZero(trunc_f80(-0.2)));
    try expect(math.isPositiveZero(trunc_f80(0.0)));
    try expect(math.isNegativeZero(trunc_f80(-0.0)));
    try expect(math.isPositiveInf(trunc_f80(math.inf(f64))));
    try expect(math.isNegativeInf(trunc_f80(-math.inf(f64))));
    try expect(math.isNan(trunc_f80(math.nan(f64))));
}

test trunc_f128 {
    try expect(trunc_f128(1.3) == 1.0);
    try expect(trunc_f128(-1.3) == -1.0);
    try expect(math.isPositiveZero(trunc_f128(0.2)));
    try expect(math.isNegativeZero(trunc_f128(-0.2)));
    try expect(math.isPositiveZero(trunc_f128(0.0)));
    try expect(math.isNegativeZero(trunc_f128(-0.0)));
    try expect(math.isPositiveInf(trunc_f128(math.inf(f128))));
    try expect(math.isNegativeInf(trunc_f128(-math.inf(f128))));
    try expect(math.isNan(trunc_f128(math.nan(f128))));
}
