//! Ported from musl, which is MIT licensed.
//! https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//!
//! https://git.musl-libc.org/cgit/musl/tree/src/math/ceilf.c
//! https://git.musl-libc.org/cgit/musl/tree/src/math/ceil.c
//! https://git.musl-libc.org/cgit/musl/tree/src/math/ceill.c
//!
//! https://git.musl-libc.org/cgit/musl/tree/src/math/floorf.c
//! https://git.musl-libc.org/cgit/musl/tree/src/math/floor.c
//! https://git.musl-libc.org/cgit/musl/tree/src/math/floorl.c

const std = @import("std");
const math = std.math;
const mem = std.mem;
const expect = std.testing.expect;

const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;

comptime {
    // floor
    symbol(&__floorh, "__floorh");
    symbol(&floorf, "floorf");
    symbol(&floor, "floor");
    symbol(&__floorx, "__floorx");
    symbol(&floorq, "floorf128");
    symbol(&floorl, "floorl");

    // ceil
    symbol(&__ceilh, "__ceilh");
    symbol(&ceilf, "ceilf");
    symbol(&ceil, "ceil");
    symbol(&__ceilx, "__ceilx");
    symbol(&ceilq, "ceilf128");
    symbol(&ceill, "ceill");
}

fn __floorh(x: compiler_rt.f16.Abi) callconv(.c) compiler_rt.f16.Abi {
    return compiler_rt.f16.toAbi(floor_f16(compiler_rt.f16.fromAbi(x)));
}
pub fn floor_f16(x: f16) f16 {
    return impl(f16, .floor, x);
}

fn floorf(x: compiler_rt.f32.Abi) callconv(.c) compiler_rt.f32.Abi {
    return compiler_rt.f32.toAbi(floor_f32(compiler_rt.f32.fromAbi(x)));
}
pub fn floor_f32(x: f32) f32 {
    return impl(f32, .floor, x);
}

fn floor(x: compiler_rt.f64.Abi) callconv(.c) compiler_rt.f64.Abi {
    return compiler_rt.f64.toAbi(floor_f64(compiler_rt.f64.fromAbi(x)));
}
pub fn floor_f64(x: f64) f64 {
    return impl(f64, .floor, x);
}

fn __floorx(x: compiler_rt.f80.Abi) callconv(.c) compiler_rt.f80.Abi {
    return compiler_rt.f80.toAbi(floor_f80(compiler_rt.f80.fromAbi(x)));
}
pub fn floor_f80(x: f80) f80 {
    return impl(f80, .floor, x);
}

fn floorq(x: compiler_rt.f128.Abi) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(floor_f128(compiler_rt.f128.fromAbi(x)));
}
pub fn floor_f128(x: f128) f128 {
    return impl(f128, .floor, x);
}

pub fn floorl(x: c_longdouble) callconv(.c) c_longdouble {
    switch (@typeInfo(c_longdouble).float.bits) {
        64 => return floor_f64(x),
        80 => return floor_f80(x),
        128 => return floor_f128(x),
        else => comptime unreachable,
    }
}

fn __ceilh(x: compiler_rt.f16.Abi) callconv(.c) compiler_rt.f16.Abi {
    return compiler_rt.f16.toAbi(ceil_f16(compiler_rt.f16.fromAbi(x)));
}
pub fn ceil_f16(x: f16) f16 {
    return impl(f16, .ceil, x);
}

fn ceilf(x: compiler_rt.f32.Abi) callconv(.c) compiler_rt.f32.Abi {
    return compiler_rt.f32.toAbi(ceil_f32(compiler_rt.f32.fromAbi(x)));
}
pub fn ceil_f32(x: f32) f32 {
    return impl(f32, .ceil, x);
}

fn ceil(x: compiler_rt.f64.Abi) callconv(.c) compiler_rt.f64.Abi {
    return compiler_rt.f64.toAbi(ceil_f64(compiler_rt.f64.fromAbi(x)));
}
pub fn ceil_f64(x: f64) f64 {
    return impl(f64, .ceil, x);
}

fn __ceilx(x: compiler_rt.f80.Abi) callconv(.c) compiler_rt.f80.Abi {
    return compiler_rt.f80.toAbi(ceil_f80(compiler_rt.f80.fromAbi(x)));
}
pub fn ceil_f80(x: f80) f80 {
    return impl(f80, .ceil, x);
}

fn ceilq(x: compiler_rt.f128.Abi) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(ceil_f128(compiler_rt.f128.fromAbi(x)));
}
pub fn ceil_f128(x: f128) f128 {
    return impl(f128, .ceil, x);
}

pub fn ceill(x: c_longdouble) callconv(.c) c_longdouble {
    switch (@typeInfo(c_longdouble).float.bits) {
        64 => return ceil_f64(x),
        80 => return ceil_f80(x),
        128 => return ceil_f128(x),
        else => comptime unreachable,
    }
}

inline fn impl(comptime T: type, comptime op: enum { floor, ceil }, x: T) T {
    const C = 1.0 / math.floatEps(T);
    const mantissa = math.floatMantissaBits(T);
    const mask = (1 << math.floatExponentBits(T)) - 1;
    const bias = (1 << (math.floatExponentBits(T) - 1)) - 1;

    const bits = @bitSizeOf(T);
    const U = @Int(.unsigned, bits);
    var u: U = @bitCast(x);
    switch (T) {
        f16, f32 => {
            const e = @as(@Int(.signed, bits), @intCast((u >> mantissa) & mask)) - bias;
            if (e >= mantissa) return x;

            if (e >= 0) {
                const m = (@as(U, 1) << @intCast(mantissa - e)) - 1;
                if (u & m == 0) return x;
                if (compiler_rt.want_float_exceptions) mem.doNotOptimizeAway(x + 0x1.0p120);
                if (u >> bits - 1 == @intFromBool(op == .floor)) u += m;
                return @bitCast(u & ~m);
            } else {
                if (compiler_rt.want_float_exceptions) mem.doNotOptimizeAway(x + 0x1.0p120);
                return switch (op) {
                    .floor => if (u >> bits - 1 == 0) 0.0 else if (u << 1 != 0) -1.0 else x,
                    .ceil => if (u >> bits - 1 != 0) -0.0 else if (u << 1 != 0) 1.0 else x,
                };
            }
        },
        f64, f80, f128 => {
            const e = (u >> mantissa) & mask;
            if (e >= bias + math.floatFractionalBits(T) or x == 0) return x;

            const positive = u >> @bitSizeOf(T) - 1 == 0;
            const y: T = if (positive)
                x + C - C - x
            else
                x - C + C - x;

            if (e <= bias - 1) {
                if (compiler_rt.want_float_exceptions) mem.doNotOptimizeAway(y);
                return switch (op) {
                    .floor => if (positive) 0.0 else -1.0,
                    .ceil => if (positive) 1.0 else -0.0,
                };
            }
            switch (op) {
                .floor => if (y > 0) return x + y - 1,
                .ceil => if (y < 0) return x + y + 1,
            }
            return x + y;
        },
        else => unreachable,
    }
}

test floor_f16 {
    try expect(floor_f16(1.3) == 1.0);
    try expect(floor_f16(-1.3) == -2.0);
    try expect(floor_f16(-0.2) == -1.0);
    try expect(math.isPositiveZero(floor_f16(0.2)));
    try expect(math.isPositiveZero(floor_f16(0.0)));
    try expect(math.isNegativeZero(floor_f16(-0.0)));
    try expect(math.isPositiveInf(floor_f16(math.inf(f16))));
    try expect(math.isNegativeInf(floor_f16(-math.inf(f16))));
    try expect(math.isNan(floor_f16(math.nan(f16))));
}

test floor_f32 {
    try expect(floor_f32(1.3) == 1.0);
    try expect(floor_f32(-1.3) == -2.0);
    try expect(floor_f32(-0.2) == -1.0);
    try expect(math.isPositiveZero(floor_f32(0.2)));
    try expect(math.isPositiveZero(floor_f32(0.0)));
    try expect(math.isNegativeZero(floor_f32(-0.0)));
    try expect(math.isPositiveInf(floor_f32(math.inf(f32))));
    try expect(math.isNegativeInf(floor_f32(-math.inf(f32))));
    try expect(math.isNan(floor_f32(math.nan(f32))));
}

test floor_f64 {
    try expect(floor_f64(1.3) == 1.0);
    try expect(floor_f64(-1.3) == -2.0);
    try expect(floor_f64(-0.2) == -1.0);
    try expect(math.isPositiveZero(floor_f64(0.2)));
    try expect(math.isPositiveZero(floor_f64(0.0)));
    try expect(math.isNegativeZero(floor_f64(-0.0)));
    try expect(math.isPositiveInf(floor_f64(math.inf(f64))));
    try expect(math.isNegativeInf(floor_f64(-math.inf(f64))));
    try expect(math.isNan(floor_f64(math.nan(f64))));
}

test floor_f80 {
    try expect(floor_f80(1.3) == 1.0);
    try expect(floor_f80(-1.3) == -2.0);
    try expect(floor_f80(-0.2) == -1.0);
    try expect(math.isPositiveZero(floor_f80(0.2)));
    try expect(math.isPositiveZero(floor_f80(0.0)));
    try expect(math.isNegativeZero(floor_f80(-0.0)));
    try expect(math.isPositiveInf(floor_f80(math.inf(f80))));
    try expect(math.isNegativeInf(floor_f80(-math.inf(f80))));
    try expect(math.isNan(floor_f80(math.nan(f80))));
}

test floor_f128 {
    try expect(floor_f128(1.3) == 1.0);
    try expect(floor_f128(-1.3) == -2.0);
    try expect(floor_f128(-0.2) == -1.0);
    try expect(math.isPositiveZero(floor_f128(0.2)));
    try expect(math.isPositiveZero(floor_f128(0.0)));
    try expect(math.isNegativeZero(floor_f128(-0.0)));
    try expect(math.isPositiveInf(floor_f128(math.inf(f128))));
    try expect(math.isNegativeInf(floor_f128(-math.inf(f128))));
    try expect(math.isNan(floor_f128(math.nan(f128))));
}

test ceil_f16 {
    try expect(ceil_f16(1.3) == 2.0);
    try expect(ceil_f16(-1.3) == -1.0);
    try expect(ceil_f16(0.2) == 1.0);
    try expect(math.isNegativeZero(ceil_f16(-0.2)));
    try expect(math.isPositiveZero(ceil_f16(0.0)));
    try expect(math.isNegativeZero(ceil_f16(-0.0)));
    try expect(math.isPositiveInf(ceil_f16(math.inf(f16))));
    try expect(math.isNegativeInf(ceil_f16(-math.inf(f16))));
    try expect(math.isNan(ceil_f16(math.nan(f16))));
}

test ceil_f32 {
    try expect(ceil_f32(1.3) == 2.0);
    try expect(ceil_f32(-1.3) == -1.0);
    try expect(ceil_f32(0.2) == 1.0);
    try expect(math.isNegativeZero(ceil_f32(-0.2)));
    try expect(math.isPositiveZero(ceil_f32(0.0)));
    try expect(math.isNegativeZero(ceil_f32(-0.0)));
    try expect(math.isPositiveInf(ceil_f32(math.inf(f32))));
    try expect(math.isNegativeInf(ceil_f32(-math.inf(f32))));
    try expect(math.isNan(ceil_f32(math.nan(f32))));
}

test ceil_f64 {
    try expect(ceil_f64(1.3) == 2.0);
    try expect(ceil_f64(-1.3) == -1.0);
    try expect(ceil_f64(0.2) == 1.0);
    try expect(math.isNegativeZero(ceil_f64(-0.2)));
    try expect(math.isPositiveZero(ceil_f64(0.0)));
    try expect(math.isNegativeZero(ceil_f64(-0.0)));
    try expect(math.isPositiveInf(ceil_f64(math.inf(f64))));
    try expect(math.isNegativeInf(ceil_f64(-math.inf(f64))));
    try expect(math.isNan(ceil_f64(math.nan(f64))));
}

test ceil_f80 {
    try expect(ceil_f80(1.3) == 2.0);
    try expect(ceil_f80(-1.3) == -1.0);
    try expect(ceil_f80(0.2) == 1.0);
    try expect(math.isNegativeZero(ceil_f80(-0.2)));
    try expect(math.isPositiveZero(ceil_f80(0.0)));
    try expect(math.isNegativeZero(ceil_f80(-0.0)));
    try expect(math.isPositiveInf(ceil_f80(math.inf(f80))));
    try expect(math.isNegativeInf(ceil_f80(-math.inf(f80))));
    try expect(math.isNan(ceil_f80(math.nan(f80))));
}

test ceil_f128 {
    try expect(ceil_f128(1.3) == 2.0);
    try expect(ceil_f128(-1.3) == -1.0);
    try expect(ceil_f128(0.2) == 1.0);
    try expect(math.isNegativeZero(ceil_f128(-0.2)));
    try expect(math.isPositiveZero(ceil_f128(0.0)));
    try expect(math.isNegativeZero(ceil_f128(-0.0)));
    try expect(math.isPositiveInf(ceil_f128(math.inf(f128))));
    try expect(math.isNegativeInf(ceil_f128(-math.inf(f128))));
    try expect(math.isNan(ceil_f128(math.nan(f128))));
}
