const std = @import("std");
const builtin = @import("builtin");
const arch = builtin.cpu.arch;
const math = std.math;
const ld = math.long_double;
const mem = std.mem;
const expect = std.testing.expect;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;
const trig = @import("trig.zig");
const rem_pio2 = @import("rem_pio2.zig").rem_pio2;
const rem_pio2f = @import("rem_pio2f.zig").rem_pio2f;
const rem_pio2l = @import("rem_pio2l.zig").rem_pio2l;
const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;

comptime {
    symbol(&sincosh, "__sincosh");
    symbol(&sincosf, "sincosf");
    symbol(&sincos, "sincos");
    symbol(&sincosx, "__sincosx");
    symbol(&sincosq, "sincosf128");
    symbol(&sincosl, "sincosl");
}

fn sincosh(x: compiler_rt.f16.Abi, r_sin: *compiler_rt.f16.Abi, r_cos: *compiler_rt.f16.Abi) callconv(.c) void {
    const s, const c = sincos_f16(compiler_rt.f16.fromAbi(x));
    r_sin.* = compiler_rt.f16.toAbi(s);
    r_cos.* = compiler_rt.f16.toAbi(c);
}
pub fn sincos_f16(x: f16) struct { f16, f16 } {
    // TODO: more efficient implementation
    const s, const c = sincos_f32(x);
    return .{ @floatCast(s), @floatCast(c) };
}

fn sincosf(x: compiler_rt.f32.Abi, r_sin: *compiler_rt.f32.Abi, r_cos: *compiler_rt.f32.Abi) callconv(.c) void {
    const s, const c = sincos_f32(compiler_rt.f32.fromAbi(x));
    r_sin.* = compiler_rt.f32.toAbi(s);
    r_cos.* = compiler_rt.f32.toAbi(c);
}
pub fn sincos_f32(x: f32) struct { f32, f32 } {
    const sc1pio2: f64 = 1.0 * math.pi / 2.0; // 0x3FF921FB, 0x54442D18
    const sc2pio2: f64 = 2.0 * math.pi / 2.0; // 0x400921FB, 0x54442D18
    const sc3pio2: f64 = 3.0 * math.pi / 2.0; // 0x4012D97C, 0x7F3321D2
    const sc4pio2: f64 = 4.0 * math.pi / 2.0; // 0x401921FB, 0x54442D18

    const pre_ix = @as(u32, @bitCast(x));
    const sign = pre_ix >> 31 != 0;
    const ix = pre_ix & 0x7fffffff;

    // |x| ~<= pi/4
    if (ix <= 0x3f490fda) {
        // |x| < 2**-12
        if (ix < 0x39800000) {
            // raise inexact if x!=0 and underflow if subnormal
            if (compiler_rt.want_float_exceptions) {
                if (ix < 0x00100000) {
                    mem.doNotOptimizeAway(x / 0x1p120);
                } else {
                    mem.doNotOptimizeAway(x + 0x1p120);
                }
            }
            return .{ x, 1.0 };
        }
        return .{ trig.sindf(x), trig.cosdf(x) };
    }

    // |x| ~<= 5*pi/4
    if (ix <= 0x407b53d1) {
        // |x| ~<= 3pi/4
        if (ix <= 0x4016cbe3) {
            if (sign) {
                return .{ -trig.cosdf(x + sc1pio2), trig.sindf(x + sc1pio2) };
            } else {
                return .{ trig.cosdf(sc1pio2 - x), trig.sindf(sc1pio2 - x) };
            }
        }
        //  -sin(x+c) is not correct if x+c could be 0: -0 vs +0
        return .{
            -trig.sindf(if (sign) x + sc2pio2 else x - sc2pio2),
            -trig.cosdf(if (sign) x + sc2pio2 else x - sc2pio2),
        };
    }

    // |x| ~<= 9*pi/4
    if (ix <= 0x40e231d5) {
        // |x| ~<= 7*pi/4
        if (ix <= 0x40afeddf) {
            if (sign) {
                return .{ trig.cosdf(x + sc3pio2), -trig.sindf(x + sc3pio2) };
            } else {
                return .{ -trig.cosdf(x - sc3pio2), trig.sindf(x - sc3pio2) };
            }
        }
        return .{
            trig.sindf(if (sign) x + sc4pio2 else x - sc4pio2),
            trig.cosdf(if (sign) x + sc4pio2 else x - sc4pio2),
        };
    }

    // sin(Inf or NaN) is NaN
    if (ix >= 0x7f800000) {
        const result = x - x;
        return .{ result, result };
    }

    // general argument reduction needed
    var y: f64 = undefined;
    const n = rem_pio2f(x, &y);
    const s = trig.sindf(y);
    const c = trig.cosdf(y);
    return switch (@as(u2, @truncate(@as(u32, @bitCast(n))))) {
        0 => .{ s, c },
        1 => .{ c, -s },
        2 => .{ -s, -c },
        3 => .{ -c, s },
    };
}

fn sincos(x: compiler_rt.f64.Abi, r_sin: *compiler_rt.f64.Abi, r_cos: *compiler_rt.f64.Abi) callconv(.c) void {
    const s, const c = sincos_f64(compiler_rt.f64.fromAbi(x));
    r_sin.* = compiler_rt.f64.toAbi(s);
    r_cos.* = compiler_rt.f64.toAbi(c);
}
pub fn sincos_f64(x: f64) struct { f64, f64 } {
    const ix = @as(u32, @truncate(@as(u64, @bitCast(x)) >> 32)) & 0x7fffffff;

    // |x| ~< pi/4
    if (ix <= 0x3fe921fb) {
        // if |x| < 2**-27 * sqrt(2)
        if (ix < 0x3e46a09e) {
            // raise inexact if x != 0 and underflow if subnormal
            if (compiler_rt.want_float_exceptions) {
                if (ix < 0x00100000) {
                    mem.doNotOptimizeAway(x / 0x1p120);
                } else {
                    mem.doNotOptimizeAway(x + 0x1p120);
                }
            }
            return .{ x, 1.0 };
        }
        return .{ trig.sin(x, 0.0, 0), trig.cos(x, 0.0) };
    }

    // sincos(Inf or NaN) is NaN
    if (ix >= 0x7ff00000) {
        const result = x - x;
        return .{ result, result };
    }

    // argument reduction needed
    var y: [2]f64 = undefined;
    const n = rem_pio2(x, &y);
    const s = trig.sin(y[0], y[1], 1);
    const c = trig.cos(y[0], y[1]);
    return switch (@as(u2, @truncate(@as(u32, @bitCast(n))))) {
        0 => .{ s, c },
        1 => .{ c, -s },
        2 => .{ -s, -c },
        3 => .{ -c, s },
    };
}

fn sincosx(x: compiler_rt.f80.Abi, r_sin: *compiler_rt.f80.Abi, r_cos: *compiler_rt.f80.Abi) callconv(.c) void {
    const s, const c = sincos_f80(compiler_rt.f80.fromAbi(x));
    r_sin.* = compiler_rt.f80.toAbi(s);
    r_cos.* = compiler_rt.f80.toAbi(c);
}
pub fn sincos_f80(x: f80) struct { f80, f80 } {
    const se = ld.signExponent(x) & 0x7fff;
    if (se == 0x7fff) {
        const result = x - x;
        return .{ result, result };
    }

    if (@abs(x) < trig.pi_4) {
        if (se < 0x3fff - math.floatMantissaBits(f80)) {
            // raise underflow if subnormal
            if (compiler_rt.want_float_exceptions and se == 0) {
                mem.doNotOptimizeAway(x * 0x1p-120);
            }
            // raise inexact if x!=0
            return .{ x, 1.0 + x };
        }
        return .{ trig.sinx(x, 0.0, 0), trig.cosx(x, 0.0) };
    }

    var y: [2]f80 = undefined;
    const n = rem_pio2l(f80, x, &y);
    const s = trig.sinx(y[0], y[1], 1);
    const c = trig.cosx(y[0], y[1]);
    return switch (@as(u2, @truncate(@as(u32, @bitCast(n))))) {
        0 => .{ s, c },
        1 => .{ c, -s },
        2 => .{ -s, -c },
        3 => .{ -c, s },
    };
}

fn sincosq(x: compiler_rt.f128.Abi, r_sin: *compiler_rt.f128.Abi, r_cos: *compiler_rt.f128.Abi) callconv(.c) void {
    const s, const c = sincos_f128(compiler_rt.f128.fromAbi(x));
    r_sin.* = compiler_rt.f128.toAbi(s);
    r_cos.* = compiler_rt.f128.toAbi(c);
}
pub fn sincos_f128(x: f128) struct { f128, f128 } {
    const se = ld.signExponent(x) & 0x7fff;
    if (se == 0x7fff) {
        const result = x - x;
        return .{ result, result };
    }

    if (@abs(x) < trig.pi_4) {
        if (se < 0x3fff - math.floatMantissaBits(f128)) {
            // raise underflow if subnormal
            if (compiler_rt.want_float_exceptions and se == 0) {
                mem.doNotOptimizeAway(x * 0x1p-120);
            }
            // raise inexact if x!=0
            return .{ x, 1.0 + x };
        }
        return .{ trig.sinq(x, 0.0, 0), trig.cosq(x, 0.0) };
    }

    var y: [2]f128 = undefined;
    const n = rem_pio2l(f128, x, &y);
    const s = trig.sinq(y[0], y[1], 1);
    const c = trig.cosq(y[0], y[1]);
    return switch (@as(u2, @truncate(@as(u32, @bitCast(n))))) {
        0 => .{ s, c },
        1 => .{ c, -s },
        2 => .{ -s, -c },
        3 => .{ -c, s },
    };
}

pub fn sincosl(x: c_longdouble, r_sin: *c_longdouble, r_cos: *c_longdouble) callconv(.c) void {
    r_sin.*, r_cos.* = switch (@typeInfo(c_longdouble).float.bits) {
        64 => sincos_f64(x),
        80 => sincos_f80(x),
        128 => sincos_f128(x),
        else => comptime unreachable,
    };
}

fn testSincosSpecial(comptime T: type) !void {
    const f = switch (T) {
        f16 => sincos_f16,
        f32 => sincos_f32,
        f64 => sincos_f64,
        f80 => sincos_f80,
        f128 => sincos_f128,
        else => @compileError("unimplemented"),
    };

    var s: T = undefined;
    var c: T = undefined;

    s, c = f(0.0);
    try expect(math.isPositiveZero(s));
    try expect(c == 1.0);

    s, c = f(-0.0);
    try expect(math.isNegativeZero(s));
    try expect(c == 1.0);

    s, c = f(math.inf(T));
    try expect(math.isNan(s));
    try expect(math.isNan(c));

    s, c = f(-math.inf(T));
    try expect(math.isNan(s));
    try expect(math.isNan(c));

    s, c = f(math.nan(T));
    try expect(math.isNan(s));
    try expect(math.isNan(c));
}

test "sincos32.normal" {
    const epsilon = math.floatEps(f32);
    var s: f32 = undefined;
    var c: f32 = undefined;

    s, c = sincos_f32(0.0);
    try expectApproxEqAbs(@as(f32, 0.0), s, epsilon);
    try expectApproxEqAbs(@as(f32, 1.0), c, epsilon);

    s, c = sincos_f32(0.2);
    try expectApproxEqAbs(@as(f32, 0.19866933), s, epsilon);
    try expectApproxEqAbs(@as(f32, 0.9800666), c, epsilon);

    s, c = sincos_f32(0.8923);
    try expectApproxEqAbs(@as(f32, 0.77851737), s, epsilon);
    try expectApproxEqAbs(@as(f32, 0.6276231), c, epsilon);

    s, c = sincos_f32(1.5);
    try expectApproxEqAbs(@as(f32, 0.997495), s, epsilon);
    try expectApproxEqAbs(@as(f32, 0.0707372), c, epsilon);

    s, c = sincos_f32(-1.5);
    try expectApproxEqAbs(@as(f32, -0.997495), s, epsilon);
    try expectApproxEqAbs(@as(f32, 0.0707372), c, epsilon);

    s, c = sincos_f32(37.45);
    try expectApproxEqAbs(@as(f32, -0.24654257), s, epsilon);
    try expectApproxEqAbs(@as(f32, 0.96913195), c, epsilon);

    s, c = sincos_f32(89.123);
    try expectApproxEqAbs(@as(f32, 0.9161657), s, epsilon);
    try expectApproxEqAbs(@as(f32, 0.40079966), c, epsilon);
}

test "sincos32.special" {
    try testSincosSpecial(f32);
}

test "sincos64.normal" {
    const epsilon = math.floatEps(f64);
    var s: f64 = undefined;
    var c: f64 = undefined;

    s, c = sincos_f64(0.0);
    try expectApproxEqAbs(@as(f64, 0.0), s, epsilon);
    try expectApproxEqAbs(@as(f64, 1.0), c, epsilon);

    s, c = sincos_f64(0.2);
    try expectApproxEqAbs(@as(f64, 0.19866933079506122), s, epsilon);
    try expectApproxEqAbs(@as(f64, 0.9800665778412416), c, epsilon);

    s, c = sincos_f64(0.8923);
    try expectApproxEqAbs(@as(f64, 0.7785173385577349), s, epsilon);
    try expectApproxEqAbs(@as(f64, 0.6276230983360804), c, epsilon);

    s, c = sincos_f64(1.5);
    try expectApproxEqAbs(@as(f64, 0.9974949866040544), s, epsilon);
    try expectApproxEqAbs(@as(f64, 0.0707372016677029), c, epsilon);

    s, c = sincos_f64(-1.5);
    try expectApproxEqAbs(@as(f64, -0.9974949866040544), s, epsilon);
    try expectApproxEqAbs(@as(f64, 0.0707372016677029), c, epsilon);

    s, c = sincos_f64(37.45);
    try expectApproxEqAbs(@as(f64, -0.24654331551411082), s, epsilon);
    try expectApproxEqAbs(@as(f64, 0.9691317730707778), c, epsilon);

    s, c = sincos_f64(89.123);
    try expectApproxEqAbs(@as(f64, 0.9161652766622714), s, epsilon);
    try expectApproxEqAbs(@as(f64, 0.4008006809354791), c, epsilon);
}

test "sincos64.special" {
    try testSincosSpecial(f64);
}

test "sincos80.normal" {
    const epsilon = math.floatEps(f80);
    var s: f80 = undefined;
    var c: f80 = undefined;

    s, c = sincos_f80(0.0);
    try expectApproxEqAbs(@as(f80, 0.0), s, epsilon);
    try expectApproxEqAbs(@as(f80, 1.0), c, epsilon);

    s, c = sincos_f80(0.2);
    try expectApproxEqAbs(@as(f80, 0.19866933079506121545941262711838975), s, epsilon);
    try expectApproxEqAbs(@as(f80, 0.98006657784124163112419651674816888), c, epsilon);

    s, c = sincos_f80(0.8923);
    try expectApproxEqAbs(@as(f80, 0.77851733855773487830689285621486050), s, epsilon);
    try expectApproxEqAbs(@as(f80, 0.62762309833608037003563995939286067), c, epsilon);

    s, c = sincos_f80(1.5);
    try expectApproxEqAbs(@as(f80, 0.99749498660405443094172337114148732), s, epsilon);
    try expectApproxEqAbs(@as(f80, 0.070737201667702910088189851434268747), c, epsilon);

    s, c = sincos_f80(-1.5);
    try expectApproxEqAbs(@as(f80, -0.99749498660405443094172337114148732), s, epsilon);
    try expectApproxEqAbs(@as(f80, 0.070737201667702910088189851434268747), c, epsilon);

    s, c = sincos_f80(37.45);
    try expectApproxEqAbs(@as(f80, -0.24654331551411356504), s, epsilon);
    try expectApproxEqAbs(@as(f80, 0.9691317730707771246), c, epsilon);

    s, c = sincos_f80(89.123);
    try expectApproxEqAbs(@as(f80, 0.91616527666226951006), s, epsilon);
    try expectApproxEqAbs(@as(f80, 0.4008006809354834001), c, epsilon);
}

test "sincos80.special" {
    try testSincosSpecial(f80);
}

test "sincos128.normal" {
    const epsilon = math.floatEps(f128);
    var s: f128 = undefined;
    var c: f128 = undefined;

    s, c = sincos_f128(0.0);
    try expectApproxEqAbs(@as(f128, 0.0), s, epsilon);
    try expectApproxEqAbs(@as(f128, 1.0), c, epsilon);

    s, c = sincos_f128(0.2);
    try expectApproxEqAbs(@as(f128, 0.19866933079506121545941262711838975), s, epsilon);
    try expectApproxEqAbs(@as(f128, 0.98006657784124163112419651674816888), c, epsilon);

    s, c = sincos_f128(0.8923);
    try expectApproxEqAbs(@as(f128, 0.77851733855773487830689285621486050), s, epsilon);
    try expectApproxEqAbs(@as(f128, 0.62762309833608037003563995939286067), c, epsilon);

    s, c = sincos_f128(1.5);
    try expectApproxEqAbs(@as(f128, 0.99749498660405443094172337114148732), s, epsilon);
    try expectApproxEqAbs(@as(f128, 0.070737201667702910088189851434268747), c, epsilon);

    s, c = sincos_f128(-1.5);
    try expectApproxEqAbs(@as(f128, -0.99749498660405443094172337114148732), s, epsilon);
    try expectApproxEqAbs(@as(f128, 0.070737201667702910088189851434268747), c, epsilon);

    s, c = sincos_f128(37.45);
    try expectApproxEqAbs(@as(f128, -0.24654331551411356571238581321661085), s, epsilon);
    try expectApproxEqAbs(@as(f128, 0.96913177307077712443149563847233230), c, epsilon);

    s, c = sincos_f128(89.123);
    try expectApproxEqAbs(@as(f128, 0.91616527666226951075019849560482170), s, epsilon);
    try expectApproxEqAbs(@as(f128, 0.40080068093548339848199454493704702), c, epsilon);
}

test "sincos128.special" {
    try testSincosSpecial(f128);
}
