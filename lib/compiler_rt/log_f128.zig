/// Implementation of "Table-driven implementation of the logarithm function in IEEE floating-point arithmetic"
/// by PTP Tang in ACM Transactions on Mathematical Software (TOMS), 1990
///
/// https://dl.acm.org/doi/pdf/10.1145/98267.98294
///
/// Adapted to work for f128 and bases 2 and 10 by Christophe Delage.
///
/// This file contains the code shared between logq, log2q and log10q.
const log_f128 = @This();

const std = @import("std");
const math = std.math;

pub const log2size = 7;
pub const size = 1 << log2size;

/// Filter out special cases for log in bases {e,2,10}.
///
/// If x is finite and positive, returns null.
/// Returns the appropriate NaN or inf otherwise.
pub fn specialCases(x: f128) ?f128 {
    if (!math.isFinite(x)) {
        if (math.isNan(x)) {
            if (math.isSignalNan(x)) math.raiseInvalid();
            return math.nan(f128);
        }
        if (math.isPositiveInf(x)) return x;
    }
    if (x <= 0.0) {
        if (x >= 0.0) {
            math.raiseDivByZero();
            return -math.inf(f128);
        }
        math.raiseInvalid();
        return math.nan(f128);
    }

    return null;
}

pub const Proc1 = struct {
    pub const Poly = struct {
        a1: f128,
        a3: f128,
        a5: f128,
        a7: f128,
        a9: f64,
        a11: f64,
    };
    pub const HiLo = struct { hi: f128, lo: f128 };
    poly: Poly,
    tab: [size + 1]HiLo,
};

pub fn proc1(comptime p: Proc1, x: f128) f128 {
    const ym = frexp2(x);
    const y = ym.significand;
    const m = ym.exponent;

    const F0 = @round(math.ldexp(y, log2size));
    const j0: usize = @intFromFloat(F0);
    const j = j0 - size;
    const F = math.ldexp(F0, -log2size);
    const f = y - F;

    const u = (f + f) / (y + F);
    const v = u * u;
    const v64: f64 = @floatCast(v);

    const p9 = p.poly.a9 + v64 * p.poly.a11;
    const p7 = p.poly.a7 + v * p9;
    const p5 = p.poly.a5 + v * p7;
    const p3 = p.poly.a3 + v * p5;

    const q = u * v * p3;

    const xm: f128 = @floatFromInt(m);
    const l_hi = xm * p.tab[128].hi + p.tab[j].hi;
    const l_lo = xm * p.tab[128].lo + p.tab[j].lo;

    if (comptime p.poly.a1 == 1.0)
        return l_hi + (u + (q + l_lo))
    else
        return l_hi + (u * p.poly.a1 + (q + l_lo));
}

pub const Proc2 = struct {
    // exp(-1 / 16) rounded down
    pub const lo: f128 = 0.939413062813475786119710824622305;
    // exp(1 / 16) rounded up
    pub const hi: f128 = 1.0644944589178594295633905946428897;

    pub const Poly = struct {
        b1_hi: f128,
        b1_lo: f128,
        b3: f128,
        b5: f128,
        b7: f128,
        b9: f128,
        b11: f128,
        b13: f128,
        b15: f64,
        b17: f64,
        b19: f64,
    };

    poly: Poly,
};

pub fn proc2(comptime p: Proc2, x: f128) f128 {
    std.debug.assert(Proc2.lo < x and x < Proc2.hi);

    const f = x - 1.0;
    const g = 1 / (2 + f);
    const u = 2 * f * g;
    const v = u * u;
    const uv = u * v;
    const v64: f64 = @floatCast(v);

    const p17 = p.poly.b17 + v64 * p.poly.b19;
    const p15 = p.poly.b15 + v64 * p17;
    const p13 = p.poly.b13 + v * p15;
    const p11 = p.poly.b11 + v * p13;
    const p9 = p.poly.b9 + v * p11;
    const p7 = p.poly.b7 + v * p9;
    const p5 = p.poly.b5 + v * p7;

    const q_hi = uv * p.poly.b3;
    const q_lo = uv * v * p5;

    const f_hi: f128 = @as(f64, @floatCast(f));
    const f_lo = f - f_hi;

    const u_hi: f128 = @as(f64, @floatCast(u));
    const u_lo = ((2 * (f - u_hi) - u_hi * f_hi) - u_hi * f_lo) * g;

    if (comptime p.poly.b1_hi == 1.0 and p.poly.b1_lo == 0.0)
        return u_hi + (u_lo + (q_hi + q_lo));

    // t = u * p.poly.b1
    const t_hi = u_hi * p.poly.b1_hi;
    const t_lo = u_lo * p.poly.b1_hi + u * p.poly.b1_lo;

    // y = t + q
    const y_hi = t_hi + q_hi;
    const y_lo = t_lo + (t_hi - y_hi + q_hi) + q_lo;

    return y_hi + y_lo;
}

/// Returns (f, k) such that x = f * 2^k and f in [1,2).
/// Asserts that x is finite and positive.
pub fn frexp2(x: f128) math.Frexp(f128) {
    std.debug.assert(math.isFinite(x));
    std.debug.assert(x > 0.0);

    const bits: u128 = @bitCast(x);
    const uexp: i32 = @intCast(bits >> 112);

    std.debug.assert(uexp >= 0);

    if (uexp == 0) {
        const shift: u7 = @intCast(@clz(bits) - 15);

        const exp = -@as(i32, shift) - 0x3ffe;
        const frac: f128 = @bitCast((bits << shift) | (0x3fff << 112));
        return .{ .significand = frac, .exponent = exp };
    }

    const exp = uexp - 0x3fff;
    const frac: f128 = @bitCast((0x3fff << 112) | ((bits << 16) >> 16));
    return .{ .significand = frac, .exponent = exp };
}
