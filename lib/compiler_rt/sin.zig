//! Ported from musl, which is licensed under the MIT license:
//! https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//!
//! https://git.musl-libc.org/cgit/musl/tree/src/math/sinf.c
//! https://git.musl-libc.org/cgit/musl/tree/src/math/sin.c
//! https://git.musl-libc.org/cgit/musl/tree/src/math/sinl.c

const std = @import("std");
const math = std.math;
const ld = math.long_double;
const mem = std.mem;
const expect = std.testing.expect;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;

const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;
const trig = @import("trig.zig");
const rem_pio2 = @import("rem_pio2.zig").rem_pio2;
const rem_pio2f = @import("rem_pio2f.zig").rem_pio2f;
const rem_pio2l = @import("rem_pio2l.zig").rem_pio2l;

comptime {
    symbol(&__sinh, "__sinh");
    symbol(&sinf, "sinf");
    symbol(&sin, "sin");
    symbol(&__sinx, "__sinx");
    symbol(&sinq, "sinf128");
    symbol(&sinl, "sinl");
    symbol(&sinl, "__sinl"); // required by musl
}

fn __sinh(x: compiler_rt.f16.Abi) callconv(.c) compiler_rt.f16.Abi {
    return compiler_rt.f16.toAbi(sin_f16(compiler_rt.f16.fromAbi(x)));
}
pub fn sin_f16(x: f16) f16 {
    // TODO: more efficient implementation
    return @floatCast(sin_f32(x));
}

fn sinf(x: compiler_rt.f32.Abi) callconv(.c) compiler_rt.f32.Abi {
    return compiler_rt.f32.toAbi(sin_f32(compiler_rt.f32.fromAbi(x)));
}
pub fn sin_f32(x: f32) f32 {
    // Small multiples of pi/2 rounded to double precision.
    const s1pio2: f64 = 1.0 * math.pi / 2.0; // 0x3FF921FB, 0x54442D18
    const s2pio2: f64 = 2.0 * math.pi / 2.0; // 0x400921FB, 0x54442D18
    const s3pio2: f64 = 3.0 * math.pi / 2.0; // 0x4012D97C, 0x7F3321D2
    const s4pio2: f64 = 4.0 * math.pi / 2.0; // 0x401921FB, 0x54442D18

    var ix: u32 = @bitCast(x);
    const sign = ix >> 31 != 0;
    ix &= 0x7fffffff;

    if (ix <= 0x3f490fda) { // |x| ~<= pi/4
        if (ix < 0x39800000) { // |x| < 2**-12
            // raise inexact if x!=0 and underflow if subnormal
            if (compiler_rt.want_float_exceptions) {
                if (ix < 0x00800000) {
                    mem.doNotOptimizeAway(x / 0x1p120);
                } else {
                    mem.doNotOptimizeAway(x + 0x1p120);
                }
            }
            return x;
        }
        return trig.sindf(x);
    }
    if (ix <= 0x407b53d1) { // |x| ~<= 5*pi/4
        if (ix <= 0x4016cbe3) { // |x| ~<= 3pi/4
            if (sign) {
                return -trig.cosdf(x + s1pio2);
            } else {
                return trig.cosdf(x - s1pio2);
            }
        }
        return trig.sindf(if (sign) -(x + s2pio2) else -(x - s2pio2));
    }
    if (ix <= 0x40e231d5) { // |x| ~<= 9*pi/4
        if (ix <= 0x40afeddf) { // |x| ~<= 7*pi/4
            if (sign) {
                return trig.cosdf(x + s3pio2);
            } else {
                return -trig.cosdf(x - s3pio2);
            }
        }
        return trig.sindf(if (sign) x + s4pio2 else x - s4pio2);
    }

    // sin(Inf or NaN) is NaN
    if (ix >= 0x7f800000) {
        return x - x;
    }

    var y: f64 = undefined;
    const n = rem_pio2f(x, &y);
    return switch (n & 3) {
        0 => trig.sindf(y),
        1 => trig.cosdf(y),
        2 => trig.sindf(-y),
        else => -trig.cosdf(y),
    };
}

fn sin(x: compiler_rt.f64.Abi) callconv(.c) compiler_rt.f64.Abi {
    return compiler_rt.f64.toAbi(sin_f64(compiler_rt.f64.fromAbi(x)));
}
pub fn sin_f64(x: f64) f64 {
    var ix = @as(u64, @bitCast(x)) >> 32;
    ix &= 0x7fffffff;

    // |x| ~< pi/4
    if (ix <= 0x3fe921fb) {
        if (ix < 0x3e500000) { // |x| < 2**-26
            // raise inexact if x != 0 and underflow if subnormal
            if (compiler_rt.want_float_exceptions) {
                if (ix < 0x00100000) {
                    mem.doNotOptimizeAway(x / 0x1p120);
                } else {
                    mem.doNotOptimizeAway(x + 0x1p120);
                }
            }
            return x;
        }
        return trig.sin(x, 0.0, 0);
    }

    // sin(Inf or NaN) is NaN
    if (ix >= 0x7ff00000) {
        return x - x;
    }

    var y: [2]f64 = undefined;
    const n = rem_pio2(x, &y);
    return switch (n & 3) {
        0 => trig.sin(y[0], y[1], 1),
        1 => trig.cos(y[0], y[1]),
        2 => -trig.sin(y[0], y[1], 1),
        else => -trig.cos(y[0], y[1]),
    };
}

fn __sinx(x: compiler_rt.f80.Abi) callconv(.c) compiler_rt.f80.Abi {
    return compiler_rt.f80.toAbi(sin_f80(compiler_rt.f80.fromAbi(x)));
}
pub fn sin_f80(x: f80) f80 {
    const se = ld.signExponent(x) & 0x7fff;
    if (se == 0x7fff) {
        return x - x;
    }

    if (@abs(x) < trig.pi_4) {
        if (se < 0x3fff - (math.floatMantissaBits(f80) / 2)) {
            // raise inexact if x!=0 and underflow if subnormal
            if (compiler_rt.want_float_exceptions) {
                mem.doNotOptimizeAway(if (se == 0) x * 0x1p-120 else x + 0x1p120);
            }
            return x;
        }
        return trig.sinx(x, 0.0, 0);
    }

    var y: [2]f80 = undefined;
    const n = rem_pio2l(f80, x, &y);
    return switch (n & 3) {
        0 => trig.sinx(y[0], y[1], 1),
        1 => trig.cosx(y[0], y[1]),
        2 => -trig.sinx(y[0], y[1], 1),
        else => -trig.cosx(y[0], y[1]),
    };
}

fn sinq(x: compiler_rt.f128.Abi) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(sin_f128(compiler_rt.f128.fromAbi(x)));
}
pub fn sin_f128(x: f128) f128 {
    const se = ld.signExponent(x) & 0x7fff;
    if (se == 0x7fff) {
        return x - x;
    }

    if (@abs(x) < trig.pi_4) {
        if (se < 0x3fff - (math.floatMantissaBits(f128) / 2)) {
            // raise inexact if x!=0 and underflow if subnormal
            if (compiler_rt.want_float_exceptions) {
                mem.doNotOptimizeAway(if (se == 0) x * 0x1p-120 else x + 0x1p120);
            }
            return x;
        }
        return trig.sinq(x, 0.0, 0);
    }

    var y: [2]f128 = undefined;
    const n = rem_pio2l(f128, x, &y);
    return switch (n & 3) {
        0 => trig.sinq(y[0], y[1], 1),
        1 => trig.cosq(y[0], y[1]),
        2 => -trig.sinq(y[0], y[1], 1),
        else => -trig.cosq(y[0], y[1]),
    };
}

pub fn sinl(x: c_longdouble) callconv(.c) c_longdouble {
    switch (@typeInfo(c_longdouble).float.bits) {
        64 => return sin_f64(x),
        80 => return sin_f80(x),
        128 => return sin_f128(x),
        else => comptime unreachable,
    }
}

fn testSinSpecial(comptime T: type) !void {
    const f = switch (T) {
        f16 => sin_f16,
        f32 => sin_f32,
        f64 => sin_f64,
        f80 => sin_f80,
        f128 => sin_f128,
        else => comptime unreachable,
    };

    try expect(math.isPositiveZero(f(0.0)));
    try expect(math.isNegativeZero(f(-0.0)));
    try expect(math.isNan(f(math.inf(T))));
    try expect(math.isNan(f(-math.inf(T))));
    try expect(math.isNan(f(math.nan(T))));
}

test "sin32.normal" {
    const epsilon = math.floatEps(f32);
    try expectApproxEqAbs(@as(f32, 0.0), sin_f32(0.0), epsilon);
    try expectApproxEqAbs(@as(f32, 0.19866933), sin_f32(0.2), epsilon);
    try expectApproxEqAbs(@as(f32, 0.77851737), sin_f32(0.8923), epsilon);
    try expectApproxEqAbs(@as(f32, 0.997495), sin_f32(1.5), epsilon);
    try expectApproxEqAbs(@as(f32, -0.997495), sin_f32(-1.5), epsilon);
    try expectApproxEqAbs(@as(f32, -0.24654257), sin_f32(37.45), epsilon);
    try expectApproxEqAbs(@as(f32, 0.9161657), sin_f32(89.123), epsilon);
}

test "sin32.special" {
    try testSinSpecial(f32);
}

test "sin64.normal" {
    const epsilon = math.floatEps(f64);
    try expectApproxEqAbs(@as(f64, 0.0), sin_f64(0.0), epsilon);
    try expectApproxEqAbs(@as(f64, 0.19866933079506122), sin_f64(0.2), epsilon);
    try expectApproxEqAbs(@as(f64, 0.7785173385577349), sin_f64(0.8923), epsilon);
    try expectApproxEqAbs(@as(f64, 0.9974949866040544), sin_f64(1.5), epsilon);
    try expectApproxEqAbs(@as(f64, -0.9974949866040544), sin_f64(-1.5), epsilon);
    try expectApproxEqAbs(@as(f64, -0.24654331551411082), sin_f64(37.45), epsilon);
    try expectApproxEqAbs(@as(f64, 0.9161652766622714), sin_f64(89.123), epsilon);
}

test "sin64.special" {
    try testSinSpecial(f64);
}

test "sin80.normal" {
    const epsilon = math.floatEps(f80);
    try expectApproxEqAbs(@as(f80, 0.0), sin_f80(0.0), epsilon);
    try expectApproxEqAbs(@as(f80, 0.19866933079506121545941262711838975), sin_f80(0.2), epsilon);
    try expectApproxEqAbs(@as(f80, 0.77851733855773487830689285621486050), sin_f80(0.8923), epsilon);
    try expectApproxEqAbs(@as(f80, 0.99749498660405443094172337114148732), sin_f80(1.5), epsilon);
    try expectApproxEqAbs(@as(f80, -0.99749498660405443094172337114148732), sin_f80(-1.5), epsilon);
    try expectApproxEqAbs(@as(f80, -0.24654331551411356504), sin_f80(37.45), epsilon);
    try expectApproxEqAbs(@as(f80, 0.91616527666226951006), sin_f80(89.123), epsilon);
}

test "sin80.special" {
    try testSinSpecial(f80);
}

test "sin128.normal" {
    const epsilon = math.floatEps(f128);
    try expectApproxEqAbs(@as(f128, 0.0), sin_f128(0.0), epsilon);
    try expectApproxEqAbs(@as(f128, 0.19866933079506121545941262711838975), sin_f128(0.2), epsilon);
    try expectApproxEqAbs(@as(f128, 0.77851733855773487830689285621486050), sin_f128(0.8923), epsilon);
    try expectApproxEqAbs(@as(f128, 0.99749498660405443094172337114148732), sin_f128(1.5), epsilon);
    try expectApproxEqAbs(@as(f128, -0.99749498660405443094172337114148732), sin_f128(-1.5), epsilon);
    try expectApproxEqAbs(@as(f128, -0.24654331551411356571238581321661085), sin_f128(37.45), epsilon);
    try expectApproxEqAbs(@as(f128, 0.91616527666226951075019849560482170), sin_f128(89.123), epsilon);
}

test "sin128.special" {
    try testSinSpecial(f128);
}

test "sin32 #9901" {
    const float: f32 = @bitCast(@as(u32, 0b11100011111111110000000000000000));
    _ = sin_f32(float);
}

test "sin64 #9901" {
    const float: f64 = @bitCast(@as(u64, 0b1111111101000001000000001111110111111111100000000000000000000001));
    _ = sin_f64(float);
}
