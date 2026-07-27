//! Ported from musl, which is licensed under the MIT license:
//! https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//!
//! https://git.musl-libc.org/cgit/musl/tree/src/math/cosf.c
//! https://git.musl-libc.org/cgit/musl/tree/src/math/cos.c
//! https://git.musl-libc.org/cgit/musl/tree/src/math/cosl.c

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
    symbol(&__cosh, "__cosh");
    symbol(&cosf, "cosf");
    symbol(&cos, "cos");
    symbol(&__cosx, "__cosx");
    symbol(&cosq, "cosf128");
    symbol(&cosl, "cosl");
    symbol(&cosl, "__cosl"); // required by musl
}

fn __cosh(x: compiler_rt.f16.Abi) callconv(.c) compiler_rt.f16.Abi {
    return compiler_rt.f16.toAbi(cos_f16(compiler_rt.f16.fromAbi(x)));
}
pub fn cos_f16(x: f16) f16 {
    // TODO: more efficient implementation
    return @floatCast(cos_f32(x));
}

fn cosf(x: compiler_rt.f32.Abi) callconv(.c) compiler_rt.f32.Abi {
    return compiler_rt.f32.toAbi(cos_f32(compiler_rt.f32.fromAbi(x)));
}
pub fn cos_f32(x: f32) f32 {
    // Small multiples of pi/2 rounded to double precision.
    const c1pio2: f64 = 1.0 * math.pi / 2.0; // 0x3FF921FB, 0x54442D18
    const c2pio2: f64 = 2.0 * math.pi / 2.0; // 0x400921FB, 0x54442D18
    const c3pio2: f64 = 3.0 * math.pi / 2.0; // 0x4012D97C, 0x7F3321D2
    const c4pio2: f64 = 4.0 * math.pi / 2.0; // 0x401921FB, 0x54442D18

    var ix: u32 = @bitCast(x);
    const sign = ix >> 31 != 0;
    ix &= 0x7fffffff;

    if (ix <= 0x3f490fda) { // |x| ~<= pi/4
        if (ix < 0x39800000) { // |x| < 2**-12
            // raise inexact if x != 0
            if (compiler_rt.want_float_exceptions) mem.doNotOptimizeAway(x + 0x1p120);
            return 1.0;
        }
        return trig.cosdf(x);
    }
    if (ix <= 0x407b53d1) { // |x| ~<= 5*pi/4
        if (ix > 0x4016cbe3) { // |x|  ~> 3*pi/4
            return -trig.cosdf(if (sign) x + c2pio2 else x - c2pio2);
        } else {
            if (sign) {
                return trig.sindf(x + c1pio2);
            } else {
                return trig.sindf(c1pio2 - x);
            }
        }
    }
    if (ix <= 0x40e231d5) { // |x| ~<= 9*pi/4
        if (ix > 0x40afeddf) { // |x| ~> 7*pi/4
            return trig.cosdf(if (sign) x + c4pio2 else x - c4pio2);
        } else {
            if (sign) {
                return trig.sindf(-x - c3pio2);
            } else {
                return trig.sindf(x - c3pio2);
            }
        }
    }

    // cos(Inf or NaN) is NaN
    if (ix >= 0x7f800000) {
        return x - x;
    }

    var y: f64 = undefined;
    const n = rem_pio2f(x, &y);
    return switch (n & 3) {
        0 => trig.cosdf(y),
        1 => trig.sindf(-y),
        2 => -trig.cosdf(y),
        else => trig.sindf(y),
    };
}

fn cos(x: compiler_rt.f64.Abi) callconv(.c) compiler_rt.f64.Abi {
    return compiler_rt.f64.toAbi(cos_f64(compiler_rt.f64.fromAbi(x)));
}
pub fn cos_f64(x: f64) f64 {
    var ix = @as(u64, @bitCast(x)) >> 32;
    ix &= 0x7fffffff;

    // |x| ~< pi/4
    if (ix <= 0x3fe921fb) {
        if (ix < 0x3e46a09e) { // |x| < 2**-27 * sqrt(2)
            // raise inexact if x!=0
            if (compiler_rt.want_float_exceptions) mem.doNotOptimizeAway(x + 0x1p120);
            return 1.0;
        }
        return trig.cos(x, 0);
    }

    // cos(Inf or NaN) is NaN
    if (ix >= 0x7ff00000) {
        return x - x;
    }

    var y: [2]f64 = undefined;
    const n = rem_pio2(x, &y);
    return switch (n & 3) {
        0 => trig.cos(y[0], y[1]),
        1 => -trig.sin(y[0], y[1], 1),
        2 => -trig.cos(y[0], y[1]),
        else => trig.sin(y[0], y[1], 1),
    };
}

fn __cosx(x: compiler_rt.f80.Abi) callconv(.c) compiler_rt.f80.Abi {
    return compiler_rt.f80.toAbi(cos_f80(compiler_rt.f80.fromAbi(x)));
}
pub fn cos_f80(x: f80) f80 {
    const se = ld.signExponent(x) & 0x7fff;
    if (se == 0x7fff) {
        return x - x;
    }

    if (@abs(x) < trig.pi_4) {
        if (se < 0x3fff - math.floatMantissaBits(f80)) {
            // raise inexact if x!=0
            return 1.0 + x;
        }
        return trig.cosx(x, 0.0);
    }

    var y: [2]f80 = undefined;
    const n = rem_pio2l(f80, x, &y);
    return switch (n & 3) {
        0 => trig.cosx(y[0], y[1]),
        1 => -trig.sinx(y[0], y[1], 1),
        2 => -trig.cosx(y[0], y[1]),
        else => trig.sinx(y[0], y[1], 1),
    };
}

fn cosq(x: compiler_rt.f128.Abi) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(cos_f128(compiler_rt.f128.fromAbi(x)));
}
pub fn cos_f128(x: f128) f128 {
    const se = ld.signExponent(x) & 0x7fff;
    if (se == 0x7fff) {
        return x - x;
    }

    if (@abs(x) < trig.pi_4) {
        if (se < 0x3fff - math.floatMantissaBits(f128)) {
            // raise inexact if x!=0
            return 1.0 + x;
        }
        return trig.cosq(x, 0.0);
    }

    var y: [2]f128 = undefined;
    const n = rem_pio2l(f128, x, &y);
    return switch (n & 3) {
        0 => trig.cosq(y[0], y[1]),
        1 => -trig.sinq(y[0], y[1], 1),
        2 => -trig.cosq(y[0], y[1]),
        else => trig.sinq(y[0], y[1], 1),
    };
}

pub fn cosl(x: c_longdouble) callconv(.c) c_longdouble {
    switch (@typeInfo(c_longdouble).float.bits) {
        64 => return cos_f64(x),
        80 => return cos_f80(x),
        128 => return cos_f128(x),
        else => comptime unreachable,
    }
}

fn testCosSpecial(comptime T: type) !void {
    const f = switch (T) {
        f16 => cos_f16,
        f32 => cos_f32,
        f64 => cos_f64,
        f80 => cos_f80,
        f128 => cos_f128,
        else => comptime unreachable,
    };

    try expect(f(0.0) == 1.0);
    try expect(f(-0.0) == 1.0);
    try expect(math.isNan(f(math.inf(T))));
    try expect(math.isNan(f(-math.inf(T))));
    try expect(math.isNan(f(math.nan(T))));
}

test "cos32.normal" {
    const epsilon = math.floatEps(f32);
    try expectApproxEqAbs(@as(f32, 1.0), cos_f32(0.0), epsilon);
    try expectApproxEqAbs(@as(f32, 0.9800666), cos_f32(0.2), epsilon);
    try expectApproxEqAbs(@as(f32, 0.6276231), cos_f32(0.8923), epsilon);
    try expectApproxEqAbs(@as(f32, 0.0707372), cos_f32(1.5), epsilon);
    try expectApproxEqAbs(@as(f32, 0.0707372), cos_f32(-1.5), epsilon);
    try expectApproxEqAbs(@as(f32, 0.96913195), cos_f32(37.45), epsilon);
    try expectApproxEqAbs(@as(f32, 0.40079966), cos_f32(89.123), epsilon);
}

test "cos32.special" {
    try testCosSpecial(f32);
}

test "cos64.normal" {
    const epsilon = math.floatEps(f64);
    try expectApproxEqAbs(@as(f64, 1.0), cos_f64(0.0), epsilon);
    try expectApproxEqAbs(@as(f64, 0.9800665778412416), cos_f64(0.2), epsilon);
    try expectApproxEqAbs(@as(f64, 0.6276230983360804), cos_f64(0.8923), epsilon);
    try expectApproxEqAbs(@as(f64, 0.0707372016677029), cos_f64(1.5), epsilon);
    try expectApproxEqAbs(@as(f64, 0.0707372016677029), cos_f64(-1.5), epsilon);
    try expectApproxEqAbs(@as(f64, 0.9691317730707778), cos_f64(37.45), epsilon);
    try expectApproxEqAbs(@as(f64, 0.4008006809354791), cos_f64(89.123), epsilon);
}

test "cos64.special" {
    try testCosSpecial(f64);
}

test "cos80.normal" {
    const epsilon = math.floatEps(f80);
    try expectApproxEqAbs(@as(f80, 1.0), cos_f80(0.0), epsilon);
    try expectApproxEqAbs(@as(f80, 0.98006657784124163112419651674816888), cos_f80(0.2), epsilon);
    try expectApproxEqAbs(@as(f80, 0.62762309833608037003563995939286067), cos_f80(0.8923), epsilon);
    try expectApproxEqAbs(@as(f80, 0.070737201667702910088189851434268747), cos_f80(1.5), epsilon);
    try expectApproxEqAbs(@as(f80, 0.070737201667702910088189851434268747), cos_f80(-1.5), epsilon);
    try expectApproxEqAbs(@as(f80, 0.9691317730707771246), cos_f80(37.45), epsilon);
    try expectApproxEqAbs(@as(f80, 0.4008006809354834001), cos_f80(89.123), epsilon);
}

test "cos80.special" {
    try testCosSpecial(f80);
}

test "cos128.normal" {
    const epsilon = math.floatEps(f128);
    try expectApproxEqAbs(@as(f128, 1.0), cos_f128(0.0), epsilon);
    try expectApproxEqAbs(@as(f128, 0.98006657784124163112419651674816888), cos_f128(0.2), epsilon);
    try expectApproxEqAbs(@as(f128, 0.62762309833608037003563995939286067), cos_f128(0.8923), epsilon);
    try expectApproxEqAbs(@as(f128, 0.070737201667702910088189851434268747), cos_f128(1.5), epsilon);
    try expectApproxEqAbs(@as(f128, 0.070737201667702910088189851434268747), cos_f128(-1.5), epsilon);
    try expectApproxEqAbs(@as(f128, 0.96913177307077712443149563847233230), cos_f128(37.45), epsilon);
    try expectApproxEqAbs(@as(f128, 0.40080068093548339848199454493704702), cos_f128(89.123), epsilon);
}

test "cos128.special" {
    try testCosSpecial(f128);
}
