const builtin = @import("builtin");
const std = @import("std");
const testing = std.testing;

const impl = @import("extendf.zig");

const f32_floatCast_f16 = impl.f32_floatCast_f16;
const f64_floatCast_f16 = impl.f64_floatCast_f16;
const f80_floatCast_f16 = impl.f80_floatCast_f16;
const f128_floatCast_f16 = impl.f128_floatCast_f16;

const f64_floatCast_f32 = impl.f64_floatCast_f32;
const f80_floatCast_f32 = impl.f80_floatCast_f32;
const f128_floatCast_f32 = impl.f128_floatCast_f32;

const f80_floatCast_f64 = impl.f80_floatCast_f64;
const f128_floatCast_f64 = impl.f128_floatCast_f64;

const f128_floatCast_f80 = impl.f128_floatCast_f80;

fn test_f80_floatCast_f64(a: f64, expected: u80) !void {
    const x = f80_floatCast_f64(a);

    const rep: u80 = @bitCast(x);
    if (rep == expected)
        return;
    // test other possible NaN representation(signal NaN)
    if (std.math.isNan(@as(f80, @bitCast(expected))) and std.math.isNan(x))
        return;
    return error.TestFailure;
}

fn test_f128_floatCast_f64(a: f64, expected_hi: u64, expected_lo: u64) !void {
    const x = f128_floatCast_f64(a);

    const rep: u128 = @bitCast(x);
    const hi: u64 = @intCast(rep >> 64);
    const lo: u64 = @truncate(rep);

    if (hi == expected_hi and lo == expected_lo)
        return;
    // test other possible NaN representation(signal NaN)
    if (expected_hi == 0x7fff800000000000 and expected_lo == 0x0) {
        if ((hi & 0x7fff000000000000) == 0x7fff000000000000 and
            ((hi & 0xffffffffffff) > 0 or lo > 0))
        {
            return;
        }
    }
    return error.TestFailure;
}

fn test_f32_floatCast_f16(a: u16, expected: u32) !void {
    const x = f32_floatCast_f16(@bitCast(a));
    const rep: u32 = @bitCast(x);

    if (rep == expected) {
        if (rep & 0x7fffffff > 0x7f800000) {
            return; // NaN is always unequal.
        }
        if (x == @as(f32, @bitCast(expected))) {
            return;
        }
    }
    return error.TestFailure;
}

fn test_f128_floatCast_f32(a: f32, expected_hi: u64, expected_lo: u64) !void {
    const x = f128_floatCast_f32(a);

    const rep: u128 = @bitCast(x);
    const hi: u64 = @intCast(rep >> 64);
    const lo: u64 = @truncate(rep);

    if (hi == expected_hi and lo == expected_lo)
        return;
    // test other possible NaN representation(signal NaN)
    if (expected_hi == 0x7fff800000000000 and expected_lo == 0x0) {
        if ((hi & 0x7fff000000000000) == 0x7fff000000000000 and
            ((hi & 0xffffffffffff) > 0 or lo > 0))
        {
            return;
        }
    }
    return error.TestFailure;
}

test f80_floatCast_f64 {
    // qNaN
    try test_f80_floatCast_f64(makeQNaN64(), 0x7fffc000000000000000);

    // NaN
    try test_f80_floatCast_f64(makeNaN64(0x7100000000000), 0x7fffe080000000000000);
    // This is bad?

    // inf
    try test_f80_floatCast_f64(makeInf64(), 0x7fff8000000000000000);

    // zero
    try test_f80_floatCast_f64(0.0, 0x0);

    try test_f80_floatCast_f64(0x0.a3456789abcdefp+6, 0x4004a3456789abcdf000);

    try test_f80_floatCast_f64(0x0.edcba987654321fp-8, 0x3ff6edcba98765432000);

    try test_f80_floatCast_f64(0x0.a3456789abcdefp+46, 0x402ca3456789abcdf000);

    try test_f80_floatCast_f64(0x0.edcba987654321fp-44, 0x3fd2edcba98765432000);

    // subnormal
    try test_f80_floatCast_f64(0x1.8000000000001p-1022, 0x3c01c000000000000800);
    try test_f80_floatCast_f64(0x1.8000000000002p-1023, 0x3c00c000000000001000);
}

test f128_floatCast_f64 {
    // qNaN
    try test_f128_floatCast_f64(makeQNaN64(), 0x7fff800000000000, 0x0);

    // NaN
    try test_f128_floatCast_f64(makeNaN64(0x7100000000000), 0x7fff710000000000, 0x0);

    // inf
    try test_f128_floatCast_f64(makeInf64(), 0x7fff000000000000, 0x0);

    // zero
    try test_f128_floatCast_f64(0.0, 0x0, 0x0);

    try test_f128_floatCast_f64(0x1.23456789abcdefp+5, 0x400423456789abcd, 0xf000000000000000);

    try test_f128_floatCast_f64(0x1.edcba987654321fp-9, 0x3ff6edcba9876543, 0x2000000000000000);

    try test_f128_floatCast_f64(0x1.23456789abcdefp+45, 0x402c23456789abcd, 0xf000000000000000);

    try test_f128_floatCast_f64(0x1.edcba987654321fp-45, 0x3fd2edcba9876543, 0x2000000000000000);

    // subnormal
    try test_f128_floatCast_f64(0x1.8p-1022, 0x3c01800000000000, 0x0);
    try test_f128_floatCast_f64(0x1.8p-1023, 0x3c00800000000000, 0x0);
}

test f32_floatCast_f16 {
    try test_f32_floatCast_f16(0x7e00, 0x7fc00000); // qNaN
    try test_f32_floatCast_f16(0x7f00, 0x7fe00000); // sNaN
    // On x86 the NaN becomes quiet because the return is pushed on the x87
    // stack due to ABI requirements
    if (builtin.target.cpu.arch != .x86 and builtin.target.os.tag == .windows)
        try test_f32_floatCast_f16(0x7c01, 0x7f802000); // sNaN

    try test_f32_floatCast_f16(0, 0); // 0
    try test_f32_floatCast_f16(0x8000, 0x80000000); // -0

    try test_f32_floatCast_f16(0x7c00, 0x7f800000); // inf
    try test_f32_floatCast_f16(0xfc00, 0xff800000); // -inf

    try test_f32_floatCast_f16(0x0001, 0x33800000); // denormal (min), 2**-24
    try test_f32_floatCast_f16(0x8001, 0xb3800000); // denormal (min), -2**-24

    try test_f32_floatCast_f16(0x03ff, 0x387fc000); // denormal (max), 2**-14 - 2**-24
    try test_f32_floatCast_f16(0x83ff, 0xb87fc000); // denormal (max), -2**-14 + 2**-24

    try test_f32_floatCast_f16(0x0400, 0x38800000); // normal (min), 2**-14
    try test_f32_floatCast_f16(0x8400, 0xb8800000); // normal (min), -2**-14

    try test_f32_floatCast_f16(0x7bff, 0x477fe000); // normal (max), 65504
    try test_f32_floatCast_f16(0xfbff, 0xc77fe000); // normal (max), -65504

    try test_f32_floatCast_f16(0x3c01, 0x3f802000); // normal, 1 + 2**-10
    try test_f32_floatCast_f16(0xbc01, 0xbf802000); // normal, -1 - 2**-10

    try test_f32_floatCast_f16(0x3555, 0x3eaaa000); // normal, approx. 1/3
    try test_f32_floatCast_f16(0xb555, 0xbeaaa000); // normal, approx. -1/3
}

test f128_floatCast_f32 {
    // qNaN
    try test_f128_floatCast_f32(makeQNaN32(), 0x7fff800000000000, 0x0);
    // NaN
    try test_f128_floatCast_f32(makeNaN32(0x410000), 0x7fff820000000000, 0x0);
    // inf
    try test_f128_floatCast_f32(makeInf32(), 0x7fff000000000000, 0x0);
    // zero
    try test_f128_floatCast_f32(0.0, 0x0, 0x0);
    try test_f128_floatCast_f32(0x1.23456p+5, 0x4004234560000000, 0x0);
    try test_f128_floatCast_f32(0x1.edcbap-9, 0x3ff6edcba0000000, 0x0);
    try test_f128_floatCast_f32(0x1.23456p+45, 0x402c234560000000, 0x0);
    try test_f128_floatCast_f32(0x1.edcbap-45, 0x3fd2edcba0000000, 0x0);
}

fn makeQNaN64() f64 {
    return @bitCast(@as(u64, 0x7ff8000000000000));
}

fn makeInf64() f64 {
    return @bitCast(@as(u64, 0x7ff0000000000000));
}

fn makeNaN64(rand: u64) f64 {
    return @bitCast(0x7ff0000000000000 | (rand & 0xfffffffffffff));
}

fn makeQNaN32() f32 {
    return @bitCast(@as(u32, 0x7fc00000));
}

fn makeNaN32(rand: u32) f32 {
    return @bitCast(0x7f800000 | (rand & 0x7fffff));
}

fn makeInf32() f32 {
    return @bitCast(@as(u32, 0x7f800000));
}

fn test_f128_floatCast_f16(a: u16, expected_hi: u64, expected_lo: u64) !void {
    const x = f128_floatCast_f16(@bitCast(a));

    const rep: u128 = @bitCast(x);
    const hi: u64 = @intCast(rep >> 64);
    const lo: u64 = @truncate(rep);

    if (hi == expected_hi and lo == expected_lo)
        return;

    // test other possible NaN representation(signal NaN)
    if (expected_hi == 0x7fff800000000000 and expected_lo == 0x0) {
        if ((hi & 0x7fff000000000000) == 0x7fff000000000000 and
            ((hi & 0xffffffffffff) > 0 or lo > 0))
        {
            return;
        }
    }

    return error.TestFailure;
}

test f128_floatCast_f16 {
    // qNaN
    try test_f128_floatCast_f16(0x7e00, 0x7fff800000000000, 0x0);
    // NaN
    try test_f128_floatCast_f16(0x7d00, 0x7fff400000000000, 0x0);
    // inf
    try test_f128_floatCast_f16(0x7c00, 0x7fff000000000000, 0x0);
    try test_f128_floatCast_f16(0xfc00, 0xffff000000000000, 0x0);
    // zero
    try test_f128_floatCast_f16(0x0000, 0x0000000000000000, 0x0);
    try test_f128_floatCast_f16(0x8000, 0x8000000000000000, 0x0);
    // denormal
    try test_f128_floatCast_f16(0x0010, 0x3feb000000000000, 0x0);
    try test_f128_floatCast_f16(0x0001, 0x3fe7000000000000, 0x0);
    try test_f128_floatCast_f16(0x8001, 0xbfe7000000000000, 0x0);

    // pi
    try test_f128_floatCast_f16(0x4248, 0x4000920000000000, 0x0);
    try test_f128_floatCast_f16(0xc248, 0xc000920000000000, 0x0);

    try test_f128_floatCast_f16(0x508c, 0x4004230000000000, 0x0);
    try test_f128_floatCast_f16(0x1bb7, 0x3ff6edc000000000, 0x0);
}
