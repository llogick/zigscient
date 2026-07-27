//! Ported from musl, which is licensed under the MIT license:
//! https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//!
//! https://git.musl-libc.org/cgit/musl/tree/src/math/roundf.c
//! https://git.musl-libc.org/cgit/musl/tree/src/math/round.c

const std = @import("std");
const builtin = @import("builtin");
const math = std.math;
const mem = std.mem;
const expect = std.testing.expect;
const arch = builtin.cpu.arch;
const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;

comptime {
    symbol(&__roundh, "__roundh");
    symbol(&roundf, "roundf");
    symbol(&round, "round");
    symbol(&__roundx, "__roundx");
    symbol(&roundq, "roundf128");
    symbol(&roundl, "roundl");
}

fn __roundh(x: compiler_rt.f16.Abi) callconv(.c) compiler_rt.f16.Abi {
    return compiler_rt.f16.toAbi(round_f16(compiler_rt.f16.fromAbi(x)));
}
pub fn round_f16(x: f16) f16 {
    // TODO: more efficient implementation
    return @floatCast(round_f32(x));
}

fn roundf(x: compiler_rt.f32.Abi) callconv(.c) compiler_rt.f32.Abi {
    return compiler_rt.f32.toAbi(round_f32(compiler_rt.f32.fromAbi(x)));
}
pub fn round_f32(x_: f32) f32 {
    const f32_toint = 1.0 / math.floatEps(f32);

    var x = x_;
    const u: u32 = @bitCast(x);
    const e = (u >> 23) & 0xFF;
    var y: f32 = undefined;

    if (e >= 0x7F + 23) {
        return x;
    }
    if (u >> 31 != 0) {
        x = -x;
    }
    if (e < 0x7F - 1) {
        if (compiler_rt.want_float_exceptions) mem.doNotOptimizeAway(x + f32_toint);
        return 0 * @as(f32, @bitCast(u));
    }

    y = x + f32_toint - f32_toint - x;
    if (y > 0.5) {
        y = y + x - 1;
    } else if (y <= -0.5) {
        y = y + x + 1;
    } else {
        y = y + x;
    }

    if (u >> 31 != 0) {
        return -y;
    } else {
        return y;
    }
}

fn round(x: compiler_rt.f64.Abi) callconv(.c) compiler_rt.f64.Abi {
    return compiler_rt.f64.toAbi(round_f64(compiler_rt.f64.fromAbi(x)));
}
pub fn round_f64(x_: f64) f64 {
    const f64_toint = 1.0 / math.floatEps(f64);

    var x = x_;
    const u: u64 = @bitCast(x);
    const e = (u >> 52) & 0x7FF;
    var y: f64 = undefined;

    if (e >= 0x3FF + 52) {
        return x;
    }
    if (u >> 63 != 0) {
        x = -x;
    }
    if (e < 0x3ff - 1) {
        if (compiler_rt.want_float_exceptions) mem.doNotOptimizeAway(x + f64_toint);
        return 0 * @as(f64, @bitCast(u));
    }

    y = x + f64_toint - f64_toint - x;
    if (y > 0.5) {
        y = y + x - 1;
    } else if (y <= -0.5) {
        y = y + x + 1;
    } else {
        y = y + x;
    }

    if (u >> 63 != 0) {
        return -y;
    } else {
        return y;
    }
}

fn __roundx(x: compiler_rt.f80.Abi) callconv(.c) compiler_rt.f80.Abi {
    return compiler_rt.f80.toAbi(round_f80(compiler_rt.f80.fromAbi(x)));
}
pub fn round_f80(x: f80) f80 {
    // TODO: more efficient implementation
    return @floatCast(round_f128(x));
}

fn roundq(x: compiler_rt.f128.Abi) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(round_f128(compiler_rt.f128.fromAbi(x)));
}
pub fn round_f128(x_: f128) f128 {
    const f128_toint = 1.0 / math.floatEps(f128);

    var x = x_;
    const u: u128 = @bitCast(x);
    const e = (u >> 112) & 0x7FFF;
    var y: f128 = undefined;

    if (e >= 0x3FFF + 112) {
        return x;
    }
    if (u >> 127 != 0) {
        x = -x;
    }
    if (e < 0x3FFF - 1) {
        if (compiler_rt.want_float_exceptions) mem.doNotOptimizeAway(x + f128_toint);
        return 0 * @as(f128, @bitCast(u));
    }

    y = x + f128_toint - f128_toint - x;
    if (y > 0.5) {
        y = y + x - 1;
    } else if (y <= -0.5) {
        y = y + x + 1;
    } else {
        y = y + x;
    }

    if (u >> 127 != 0) {
        return -y;
    } else {
        return y;
    }
}

pub fn roundl(x: c_longdouble) callconv(.c) c_longdouble {
    switch (@typeInfo(c_longdouble).float.bits) {
        64 => return round_f64(x),
        80 => return round_f80(x),
        128 => return round_f128(x),
        else => comptime unreachable,
    }
}

test round_f16 {
    try expect(round_f16(1.3) == 1.0);
    try expect(round_f16(-1.3) == -1.0);
    try expect(round_f16(1.8) == 2.0);
    try expect(round_f16(-1.8) == -2.0);
    try expect(math.isPositiveZero(round_f16(0.2)));
    try expect(math.isNegativeZero(round_f16(-0.2)));
    try expect(math.isPositiveZero(round_f16(0.0)));
    try expect(math.isNegativeZero(round_f16(-0.0)));
    try expect(math.isPositiveInf(round_f16(math.inf(f32))));
    try expect(math.isNegativeInf(round_f16(-math.inf(f32))));
    try expect(math.isNan(round_f16(math.nan(f32))));
}

test round_f32 {
    try expect(round_f32(1.3) == 1.0);
    try expect(round_f32(-1.3) == -1.0);
    try expect(round_f32(1.8) == 2.0);
    try expect(round_f32(-1.8) == -2.0);
    try expect(math.isPositiveZero(round_f32(0.2)));
    try expect(math.isNegativeZero(round_f32(-0.2)));
    try expect(math.isPositiveZero(round_f32(0.0)));
    try expect(math.isNegativeZero(round_f32(-0.0)));
    try expect(math.isPositiveInf(round_f32(math.inf(f32))));
    try expect(math.isNegativeInf(round_f32(-math.inf(f32))));
    try expect(math.isNan(round_f32(math.nan(f32))));
}

test round_f64 {
    try expect(round_f64(1.3) == 1.0);
    try expect(round_f64(-1.3) == -1.0);
    try expect(round_f64(1.8) == 2.0);
    try expect(round_f64(-1.8) == -2.0);
    try expect(math.isPositiveZero(round_f64(0.2)));
    try expect(math.isNegativeZero(round_f64(-0.2)));
    try expect(math.isPositiveZero(round_f64(0.0)));
    try expect(math.isNegativeZero(round_f64(-0.0)));
    try expect(math.isPositiveInf(round_f64(math.inf(f64))));
    try expect(math.isNegativeInf(round_f64(-math.inf(f64))));
    try expect(math.isNan(round_f64(math.nan(f64))));
}

test round_f80 {
    try expect(round_f80(1.3) == 1.0);
    try expect(round_f80(-1.3) == -1.0);
    try expect(round_f80(1.8) == 2.0);
    try expect(round_f80(-1.8) == -2.0);
    try expect(math.isPositiveZero(round_f80(0.2)));
    try expect(math.isNegativeZero(round_f80(-0.2)));
    try expect(math.isPositiveZero(round_f80(0.0)));
    try expect(math.isNegativeZero(round_f80(-0.0)));
    try expect(math.isPositiveInf(round_f80(math.inf(f64))));
    try expect(math.isNegativeInf(round_f80(-math.inf(f64))));
    try expect(math.isNan(round_f80(math.nan(f64))));
}

test round_f128 {
    try expect(round_f128(1.3) == 1.0);
    try expect(round_f128(-1.3) == -1.0);
    try expect(round_f128(1.8) == 2.0);
    try expect(round_f128(-1.8) == -2.0);
    try expect(math.isPositiveZero(round_f128(0.2)));
    try expect(math.isNegativeZero(round_f128(-0.2)));
    try expect(math.isPositiveZero(round_f128(0.0)));
    try expect(math.isNegativeZero(round_f128(-0.0)));
    try expect(math.isPositiveInf(round_f128(math.inf(f128))));
    try expect(math.isNegativeInf(round_f128(-math.inf(f128))));
    try expect(math.isNan(round_f128(math.nan(f128))));
}
