const std = @import("std");
const isNan = std.math.isNan;
const isInf = std.math.isInf;
const scalbn = std.math.scalbn;
const ilogb = std.math.ilogb;
const maxInt = std.math.maxInt;
const minInt = std.math.minInt;
const isFinite = std.math.isFinite;
const copysign = std.math.copysign;

const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;
const Complex = compiler_rt.Complex;

comptime {
    if (@import("builtin").zig_backend != .stage2_c) {
        symbol(&__divhc3, "__divhc3");
        symbol(&__divsc3, "__divsc3");
        symbol(&__divdc3, "__divdc3");
        symbol(&__divxc3, "__divxc3");
        if (compiler_rt.want_ppc_abi) {
            symbol(&__divtc3, "__divkc3");
        } else {
            symbol(&__divtc3, "__divtc3");
        }
    }
}

fn __divhc3(lhs_real: compiler_rt.f16.Abi, lhs_imag: compiler_rt.f16.Abi, rhs_real: compiler_rt.f16.Abi, rhs_imag: compiler_rt.f16.Abi) callconv(.c) compiler_rt.f16.complex.Abi {
    return compiler_rt.f16.complex.toAbi(div_cf16(
        compiler_rt.f16.complex.fromAbi(.{ .real = lhs_real, .imag = lhs_imag }),
        compiler_rt.f16.complex.fromAbi(.{ .real = rhs_real, .imag = rhs_imag }),
    ));
}
pub fn div_cf16(a: Complex(f16), b: Complex(f16)) Complex(f16) {
    return divc3(f16, a, b);
}

fn __divsc3(lhs_real: compiler_rt.f32.Abi, lhs_imag: compiler_rt.f32.Abi, rhs_real: compiler_rt.f32.Abi, rhs_imag: compiler_rt.f32.Abi) callconv(.c) compiler_rt.f32.complex.Abi {
    return compiler_rt.f32.complex.toAbi(div_cf32(
        compiler_rt.f32.complex.fromAbi(.{ .real = lhs_real, .imag = lhs_imag }),
        compiler_rt.f32.complex.fromAbi(.{ .real = rhs_real, .imag = rhs_imag }),
    ));
}
pub fn div_cf32(a: Complex(f32), b: Complex(f32)) Complex(f32) {
    return divc3(f32, a, b);
}

fn __divdc3(lhs_real: compiler_rt.f64.Abi, lhs_imag: compiler_rt.f64.Abi, rhs_real: compiler_rt.f64.Abi, rhs_imag: compiler_rt.f64.Abi) callconv(.c) compiler_rt.f64.complex.Abi {
    return compiler_rt.f64.complex.toAbi(div_cf64(
        compiler_rt.f64.complex.fromAbi(.{ .real = lhs_real, .imag = lhs_imag }),
        compiler_rt.f64.complex.fromAbi(.{ .real = rhs_real, .imag = rhs_imag }),
    ));
}
pub fn div_cf64(a: Complex(f64), b: Complex(f64)) Complex(f64) {
    return divc3(f64, a, b);
}

fn __divxc3(lhs_real: compiler_rt.f80.Abi, lhs_imag: compiler_rt.f80.Abi, rhs_real: compiler_rt.f80.Abi, rhs_imag: compiler_rt.f80.Abi) callconv(.c) compiler_rt.f80.complex.Abi {
    return compiler_rt.f80.complex.toAbi(div_cf80(
        compiler_rt.f80.complex.fromAbi(.{ .real = lhs_real, .imag = lhs_imag }),
        compiler_rt.f80.complex.fromAbi(.{ .real = rhs_real, .imag = rhs_imag }),
    ));
}
pub fn div_cf80(a: Complex(f80), b: Complex(f80)) Complex(f80) {
    return divc3(f80, a, b);
}

fn __divtc3(lhs_real: compiler_rt.f128.Abi, lhs_imag: compiler_rt.f128.Abi, rhs_real: compiler_rt.f128.Abi, rhs_imag: compiler_rt.f128.Abi) callconv(.c) compiler_rt.f128.complex.Abi {
    return compiler_rt.f128.complex.toAbi(div_cf128(
        compiler_rt.f128.complex.fromAbi(.{ .real = lhs_real, .imag = lhs_imag }),
        compiler_rt.f128.complex.fromAbi(.{ .real = rhs_real, .imag = rhs_imag }),
    ));
}
pub fn div_cf128(a: Complex(f128), b: Complex(f128)) Complex(f128) {
    return divc3(f128, a, b);
}

/// Implementation based on Annex G of C17 Standard (N2176)
inline fn divc3(comptime T: type, lhs: Complex(T), rhs: Complex(T)) Complex(T) {
    const a = lhs.real;
    const b = lhs.imag;
    var c = rhs.real;
    var d = rhs.imag;

    // logbw used to prevent under/over-flow
    const logbw = ilogb(@max(@abs(c), @abs(d)));
    const logbw_finite = logbw != maxInt(i32) and logbw != minInt(i32);
    const ilogbw = if (logbw_finite) b: {
        c = scalbn(c, -logbw);
        d = scalbn(d, -logbw);
        break :b logbw;
    } else 0;
    const denom = c * c + d * d;
    const result: Complex(T) = .{
        .real = scalbn((a * c + b * d) / denom, -ilogbw),
        .imag = scalbn((b * c - a * d) / denom, -ilogbw),
    };

    // Recover infinities and zeros that computed as NaN+iNaN;
    // the only cases are non-zero/zero, infinite/finite, and finite/infinite, ...
    if (isNan(result.real) and isNan(result.imag)) {
        const zero: T = 0.0;
        const one: T = 1.0;

        if ((denom == 0.0) and (!isNan(a) or !isNan(b))) {
            return .{
                .real = copysign(std.math.inf(T), c) * a,
                .imag = copysign(std.math.inf(T), c) * b,
            };
        } else if ((isInf(a) or isInf(b)) and isFinite(c) and isFinite(d)) {
            const boxed_a = copysign(if (isInf(a)) one else zero, a);
            const boxed_b = copysign(if (isInf(b)) one else zero, b);
            return .{
                .real = std.math.inf(T) * (boxed_a * c - boxed_b * d),
                .imag = std.math.inf(T) * (boxed_b * c - boxed_a * d),
            };
        } else if (logbw == maxInt(i32) and isFinite(a) and isFinite(b)) {
            const boxed_c = copysign(if (isInf(c)) one else zero, c);
            const boxed_d = copysign(if (isInf(d)) one else zero, d);
            return .{
                .real = 0.0 * (a * boxed_c + b * boxed_d),
                .imag = 0.0 * (b * boxed_c - a * boxed_d),
            };
        }
    }

    return result;
}

test {
    _ = @import("divc3_test.zig");
}
