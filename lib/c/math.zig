const builtin = @import("builtin");

const std = @import("std");
const math = std.math;
const ld = math.long_double;

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMinGW()) {
        symbol(&isnan, "isnan");
        symbol(&isnan, "__isnan");
        symbol(&isnanf, "isnanf");
        symbol(&isnanf, "__isnanf");
        symbol(&isnanl, "isnanl");
        symbol(&isnanl, "__isnanl");

        symbol(&math.floatTrueMin(f64), "__DENORM");
        symbol(&math.inf(f64), "__INF");
        symbol(&math.nan(f64), "__QNAN");
        symbol(&math.snan(f64), "__SNAN");

        symbol(&math.floatTrueMin(f32), "__DENORMF");
        symbol(&math.inf(f32), "__INFF");
        symbol(&math.nan(f32), "__QNANF");
        symbol(&math.snan(f32), "__SNANF");

        symbol(&math.floatTrueMin(c_longdouble), "__DENORML");
        symbol(&math.inf(c_longdouble), "__INFL");
        symbol(&math.nan(c_longdouble), "__QNANL");
        symbol(&math.snan(c_longdouble), "__SNANL");
    }

    if (builtin.target.isMinGW() or builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&frexpf, "frexpf");
        symbol(&frexpl, "frexpl");
        symbol(&hypotf, "hypotf");
        symbol(&hypotl, "hypotl");
        symbol(&lrintl, "lrintl");
        symbol(&lroundl, "lroundl");
        symbol(&modfl, "modfl");
        symbol(&rintl, "rintl");
    }

    if ((builtin.target.isMinGW() and @sizeOf(f64) != @sizeOf(c_longdouble)) or builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&atanl, "atanl");
        symbol(&copysignl, "copysignl");
        symbol(&fdiml, "fdiml");
        symbol(&nanl, "nanl");
    }

    if ((builtin.target.isMinGW() and builtin.cpu.arch == .x86) or builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&acosf, "acosf");
        symbol(&atanf, "atanf");
        symbol(&coshf, "coshf");
        symbol(&modff, "modff");
        symbol(&tanhf, "tanhf");
    }

    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&acos, "acos");
        symbol(&acoshf, "acoshf");
        symbol(&asin, "asin");
        symbol(&atan, "atan");
        symbol(&cbrt, "cbrt");
        symbol(&cbrtf, "cbrtf");
        symbol(&cosh, "cosh");
        symbol(&exp10, "exp10");
        symbol(&exp10f, "exp10f");
        symbol(&fdim, "fdim");
        symbol(&fdimf, "fdimf");
        symbol(&finite, "finite");
        symbol(&finitef, "finitef");
        symbol(&frexp, "frexp");
        symbol(&hypot, "hypot");
        symbol(&log1p, "log1p");
        symbol(&log1pf, "log1pf");
        symbol(&lrint, "lrint");
        symbol(&lrintf, "lrintf");
        symbol(&lround, "lround");
        symbol(&lroundf, "lroundf");
        symbol(&modf, "modf");
        symbol(&nan, "nan");
        symbol(&nanf, "nanf");
        symbol(&pow10, "pow10");
        symbol(&pow10f, "pow10f");
        symbol(&tanh, "tanh");
    }

    if (builtin.target.isMuslLibC()) {
        symbol(&copysign, "copysign");
        symbol(&copysignf, "copysignf");
        symbol(&rint, "rint");
        symbol(&rintf, "rintf");
    }
}

fn acos(x: f64) callconv(.c) f64 {
    return math.acos(x);
}

fn acosf(x: f32) callconv(.c) f32 {
    return math.acos(x);
}

fn acoshf(x: f32) callconv(.c) f32 {
    return math.acosh(x);
}

fn asin(x: f64) callconv(.c) f64 {
    return math.asin(x);
}

fn atan(x: f64) callconv(.c) f64 {
    return math.atan(x);
}

fn atanf(x: f32) callconv(.c) f32 {
    return math.atan(x);
}

fn atanl(x: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => std.c.atan(x),
        else => math.atan(x),
    };
}

fn cbrt(x: f64) callconv(.c) f64 {
    return math.cbrt(x);
}

fn cbrtf(x: f32) callconv(.c) f32 {
    return math.cbrt(x);
}

fn copysign(x: f64, y: f64) callconv(.c) f64 {
    return math.copysign(x, y);
}

fn copysignf(x: f32, y: f32) callconv(.c) f32 {
    return math.copysign(x, y);
}

fn copysignl(x: c_longdouble, y: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => std.c.copysign(x, y),
        else => math.copysign(x, y),
    };
}

fn cosh(x: f64) callconv(.c) f64 {
    return math.cosh(x);
}

fn coshf(x: f32) callconv(.c) f32 {
    return math.cosh(x);
}

fn exp10(x: f64) callconv(.c) f64 {
    return math.pow(f64, 10.0, x);
}

fn exp10f(x: f32) callconv(.c) f32 {
    return math.pow(f32, 10.0, x);
}

fn fdimGeneric(comptime T: type, x: T, y: T) T {
    if (math.isNan(x))
        return x;

    if (math.isNan(y))
        return y;

    if (x > y)
        return x - y;
    return 0;
}

fn fdim(x: f64, y: f64) callconv(.c) f64 {
    return fdimGeneric(f64, x, y);
}

fn fdimf(x: f32, y: f32) callconv(.c) f32 {
    return fdimGeneric(f32, x, y);
}

fn fdiml(x: c_longdouble, y: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => std.c.fdim(x, y),
        else => fdimGeneric(c_longdouble, x, y),
    };
}

fn finite(x: f64) callconv(.c) c_int {
    return @intFromBool(math.isFinite(x));
}

fn finitef(x: f32) callconv(.c) c_int {
    return @intFromBool(math.isFinite(x));
}

fn frexpGeneric(comptime T: type, x: T, e: *c_int) T {
    // libc expects `*e` to be unspecified in this case; an unspecified C value
    // should be a valid value of the relevant type, yet Zig's std
    // implementation sets it to `undefined` -- which can even be nonsense
    // according to the type (int). Therefore, we're setting it to a valid
    // int value in Zig -- a zero.
    //
    // This mirrors the handling of infinities, where libc also expects
    // unspecified for the value of `*e` and Zig std sets it to a zero.
    if (math.isNan(x)) {
        e.* = 0;
        return x;
    }

    const r = math.frexp(x);
    e.* = r.exponent;
    return r.significand;
}

fn frexp(x: f64, e: *c_int) callconv(.c) f64 {
    return frexpGeneric(f64, x, e);
}

fn frexpf(x: f32, e: *c_int) callconv(.c) f32 {
    return frexpGeneric(f32, x, e);
}

fn frexpl(x: c_longdouble, e: *c_int) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => std.c.frexp(x, e),
        else => frexpGeneric(c_longdouble, x, e),
    };
}

fn hypot(x: f64, y: f64) callconv(.c) f64 {
    return math.hypot(x, y);
}

fn hypotf(x: f32, y: f32) callconv(.c) f32 {
    return math.hypot(x, y);
}

fn hypotl(x: c_longdouble, y: c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => std.c.hypot(x, y),
        else => math.hypot(x, y),
    };
}

fn isnan(x: f64) callconv(.c) c_int {
    return @intFromBool(math.isNan(x));
}

fn isnanf(x: f32) callconv(.c) c_int {
    return @intFromBool(math.isNan(x));
}

fn isnanl(x: c_longdouble) callconv(.c) c_int {
    return @intFromBool(math.isNan(x));
}

fn log1p(x: f64) callconv(.c) f64 {
    return math.log1p(x);
}

fn log1pf(x: f32) callconv(.c) f32 {
    return math.log1p(x);
}

fn lrint(x: f64) callconv(.c) c_long {
    return @trunc(rint(x));
}

fn lrintf(x: f32) callconv(.c) c_long {
    return @trunc(rintf(x));
}

fn lrintl(x: c_longdouble) callconv(.c) c_long {
    return @trunc(rintl(x));
}

fn lround(x: f64) callconv(.c) c_long {
    return @round(x);
}

fn lroundf(x: f32) callconv(.c) c_long {
    return @round(x);
}

fn lroundl(x: c_longdouble) callconv(.c) c_long {
    return @round(x);
}

fn modfGeneric(comptime T: type, x: T, iptr: *T) T {
    if (math.isNegativeInf(x)) {
        iptr.* = -math.inf(T);
        return -0.0;
    }

    if (math.isPositiveInf(x)) {
        iptr.* = math.inf(T);
        return 0.0;
    }

    if (math.isNan(x)) {
        iptr.* = math.nan(T);
        return math.nan(T);
    }

    const r = math.modf(x);
    iptr.* = r.ipart;

    // If the result is a negative zero, we must be explicit about
    // returning a negative zero.
    return if (math.isNegativeZero(x) or (x < 0.0 and x == r.ipart)) -0.0 else r.fpart;
}

fn modf(x: f64, iptr: *f64) callconv(.c) f64 {
    return modfGeneric(f64, x, iptr);
}

fn modff(x: f32, iptr: *f32) callconv(.c) f32 {
    return modfGeneric(f32, x, iptr);
}

fn modfl(x: c_longdouble, iptr: *c_longdouble) callconv(.c) c_longdouble {
    return switch (@typeInfo(c_longdouble).float.bits) {
        64 => std.c.modf(x, iptr),
        else => modfGeneric(c_longdouble, x, iptr),
    };
}

fn nan(_: [*:0]const c_char) callconv(.c) f64 {
    return math.nan(f64);
}

fn nanf(_: [*:0]const c_char) callconv(.c) f32 {
    return math.nan(f32);
}

fn nanl(_: [*:0]const c_char) callconv(.c) c_longdouble {
    return math.nan(c_longdouble);
}

fn pow10(x: f64) callconv(.c) f64 {
    return exp10(x);
}

fn pow10f(x: f32) callconv(.c) f32 {
    return exp10f(x);
}

fn rint(x: f64) callconv(.c) f64 {
    const toint: f64 = 1.0 / math.floatEps(f64);
    const a: u64 = @bitCast(x);
    const e = a >> 52 & 0x7ff;
    const s = a >> 63;
    var y: f64 = undefined;

    if (e >= 0x3ff + 52) {
        return x;
    }
    if (s == 1) {
        y = x - toint + toint;
    } else {
        y = x + toint - toint;
    }
    if (y == 0) {
        return if (s == 1) -0.0 else 0;
    }
    return y;
}

fn rintf(x: f32) callconv(.c) f32 {
    const toint: f32 = 1.0 / math.floatEps(f32);
    const a: u32 = @bitCast(x);
    const e = a >> 23 & 0xff;
    const s = a >> 31;
    var y: f32 = undefined;

    if (e >= 0x7f + 23) {
        return x;
    }

    if (s == 1) {
        y = x - toint + toint;
    } else {
        y = x + toint - toint;
    }

    if (y == 0) {
        return if (s == 1) -0.0 else 0;
    }
    return y;
}

fn rintl(x: c_longdouble) callconv(.c) c_longdouble {
    if (@typeInfo(c_longdouble).float.bits == 64)
        return rint(x);

    const toint: c_longdouble = 1 << math.floatFractionalBits(c_longdouble);
    const se = ld.signExponent(x);

    if (se & 0x7fff >= 0x3fff + math.floatFractionalBits(c_longdouble))
        return x;

    var y: c_longdouble = undefined;
    if ((se >> 15) == 1) {
        y = x - toint + toint;
    } else {
        y = x + toint - toint;
    }

    if (y == 0)
        return 0 * x;
    return y;
}

fn tanh(x: f64) callconv(.c) f64 {
    return math.tanh(x);
}

fn tanhf(x: f32) callconv(.c) f32 {
    return math.tanh(x);
}
