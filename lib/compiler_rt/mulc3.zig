const std = @import("std");
const isNan = std.math.isNan;
const isInf = std.math.isInf;
const copysign = std.math.copysign;

const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;
const Complex = compiler_rt.Complex;

comptime {
    if (@import("builtin").zig_backend != .stage2_c) {
        symbol(&__mulhc3, "__mulhc3");
        symbol(&__mulsc3, "__mulsc3");
        symbol(&__muldc3, "__muldc3");
        symbol(&__mulxc3, "__mulxc3");
        if (compiler_rt.want_ppc_abi) {
            symbol(&__multc3, "__mulkc3");
        } else {
            symbol(&__multc3, "__multc3");
        }
    }
}

fn __mulhc3(lhs_real: compiler_rt.f16.Abi, lhs_imag: compiler_rt.f16.Abi, rhs_real: compiler_rt.f16.Abi, rhs_imag: compiler_rt.f16.Abi) callconv(.c) compiler_rt.f16.complex.Abi {
    return compiler_rt.f16.complex.toAbi(mul_cf16(
        compiler_rt.f16.complex.fromAbi(.{ .real = lhs_real, .imag = lhs_imag }),
        compiler_rt.f16.complex.fromAbi(.{ .real = rhs_real, .imag = rhs_imag }),
    ));
}
pub fn mul_cf16(a: Complex(f16), b: Complex(f16)) Complex(f16) {
    return mulc3(f16, a, b);
}

fn __mulsc3(lhs_real: compiler_rt.f32.Abi, lhs_imag: compiler_rt.f32.Abi, rhs_real: compiler_rt.f32.Abi, rhs_imag: compiler_rt.f32.Abi) callconv(.c) compiler_rt.f32.complex.Abi {
    return compiler_rt.f32.complex.toAbi(mul_cf32(
        compiler_rt.f32.complex.fromAbi(.{ .real = lhs_real, .imag = lhs_imag }),
        compiler_rt.f32.complex.fromAbi(.{ .real = rhs_real, .imag = rhs_imag }),
    ));
}
pub fn mul_cf32(a: Complex(f32), b: Complex(f32)) Complex(f32) {
    return mulc3(f32, a, b);
}

fn __muldc3(lhs_real: compiler_rt.f64.Abi, lhs_imag: compiler_rt.f64.Abi, rhs_real: compiler_rt.f64.Abi, rhs_imag: compiler_rt.f64.Abi) callconv(.c) compiler_rt.f64.complex.Abi {
    return compiler_rt.f64.complex.toAbi(mul_cf64(
        compiler_rt.f64.complex.fromAbi(.{ .real = lhs_real, .imag = lhs_imag }),
        compiler_rt.f64.complex.fromAbi(.{ .real = rhs_real, .imag = rhs_imag }),
    ));
}
pub fn mul_cf64(a: Complex(f64), b: Complex(f64)) Complex(f64) {
    return mulc3(f64, a, b);
}

fn __mulxc3(lhs_real: compiler_rt.f80.Abi, lhs_imag: compiler_rt.f80.Abi, rhs_real: compiler_rt.f80.Abi, rhs_imag: compiler_rt.f80.Abi) callconv(.c) compiler_rt.f80.complex.Abi {
    return compiler_rt.f80.complex.toAbi(mul_cf80(
        compiler_rt.f80.complex.fromAbi(.{ .real = lhs_real, .imag = lhs_imag }),
        compiler_rt.f80.complex.fromAbi(.{ .real = rhs_real, .imag = rhs_imag }),
    ));
}
pub fn mul_cf80(a: Complex(f80), b: Complex(f80)) Complex(f80) {
    return mulc3(f80, a, b);
}

fn __multc3(lhs_real: compiler_rt.f128.Abi, lhs_imag: compiler_rt.f128.Abi, rhs_real: compiler_rt.f128.Abi, rhs_imag: compiler_rt.f128.Abi) callconv(.c) compiler_rt.f128.complex.Abi {
    return compiler_rt.f128.complex.toAbi(mul_cf128(
        compiler_rt.f128.complex.fromAbi(.{ .real = lhs_real, .imag = lhs_imag }),
        compiler_rt.f128.complex.fromAbi(.{ .real = rhs_real, .imag = rhs_imag }),
    ));
}
pub fn mul_cf128(a: Complex(f128), b: Complex(f128)) Complex(f128) {
    return mulc3(f128, a, b);
}

/// Implementation based on Annex G of C17 Standard (N2176)
inline fn mulc3(comptime T: type, lhs: Complex(T), rhs: Complex(T)) Complex(T) {
    var a = lhs.real;
    var b = lhs.imag;
    var c = rhs.real;
    var d = rhs.imag;

    const ac = a * c;
    const bd = b * d;
    const ad = a * d;
    const bc = b * c;

    const zero: T = 0.0;
    const one: T = 1.0;

    const z: Complex(T) = .{
        .real = ac - bd,
        .imag = ad + bc,
    };
    if (isNan(z.real) and isNan(z.imag)) {
        var recalc: bool = false;

        if (isInf(a) or isInf(b)) { // (a + ib) is infinite

            // "Box" the infinity (+/-inf goes to +/-1, all finite values go to 0)
            a = copysign(if (isInf(a)) one else zero, a);
            b = copysign(if (isInf(b)) one else zero, b);

            // Replace NaNs in the other factor with (signed) 0
            if (isNan(c)) c = copysign(zero, c);
            if (isNan(d)) d = copysign(zero, d);

            recalc = true;
        }

        if (isInf(c) or isInf(d)) { // (c + id) is infinite

            // "Box" the infinity (+/-inf goes to +/-1, all finite values go to 0)
            c = copysign(if (isInf(c)) one else zero, c);
            d = copysign(if (isInf(d)) one else zero, d);

            // Replace NaNs in the other factor with (signed) 0
            if (isNan(a)) a = copysign(zero, a);
            if (isNan(b)) b = copysign(zero, b);

            recalc = true;
        }

        if (!recalc and (isInf(ac) or isInf(bd) or isInf(ad) or isInf(bc))) {

            // Recover infinities from overflow by changing NaNs to 0
            if (isNan(a)) a = copysign(zero, a);
            if (isNan(b)) b = copysign(zero, b);
            if (isNan(c)) c = copysign(zero, c);
            if (isNan(d)) d = copysign(zero, d);

            recalc = true;
        }
        if (recalc) {
            return .{
                .real = std.math.inf(T) * (a * c - b * d),
                .imag = std.math.inf(T) * (a * d + b * c),
            };
        }
    }
    return z;
}

test {
    _ = @import("mulc3_test.zig");
}
