const std = @import("std");
const testing = std.testing;

const impl = @import("truncf.zig");

const f16_floatCast_f32 = impl.f16_floatCast_f32;
const f16_floatCast_f64 = impl.f16_floatCast_f64;
const f16_floatCast_f80 = impl.f16_floatCast_f80;
const f16_floatCast_f128 = impl.f16_floatCast_f128;

const f32_floatCast_f64 = impl.f32_floatCast_f64;
const f32_floatCast_f80 = impl.f32_floatCast_f80;
const f32_floatCast_f128 = impl.f32_floatCast_f128;

const f64_floatCast_f80 = impl.f64_floatCast_f80;
const f64_floatCast_f128 = impl.f64_floatCast_f128;

const f80_floatCast_f128 = impl.f80_floatCast_f128;

fn test_f16_floatCast_f32(a: u32, expected: u16) !void {
    const actual: u16 = @bitCast(f16_floatCast_f32(@bitCast(a)));
    try testing.expect(actual == expected);
}

test f16_floatCast_f32 {
    try test_f16_floatCast_f32(0x7fc00000, 0x7e00); // qNaN
    try test_f16_floatCast_f32(0x7fe00000, 0x7f00); // sNaN

    try test_f16_floatCast_f32(0, 0); // 0
    try test_f16_floatCast_f32(0x80000000, 0x8000); // -0

    try test_f16_floatCast_f32(0x7f800000, 0x7c00); // inf
    try test_f16_floatCast_f32(0xff800000, 0xfc00); // -inf

    try test_f16_floatCast_f32(0x477ff000, 0x7c00); // 65520 -> inf
    try test_f16_floatCast_f32(0xc77ff000, 0xfc00); // -65520 -> -inf

    try test_f16_floatCast_f32(0x71cc3892, 0x7c00); // 0x1.987124876876324p+100 -> inf
    try test_f16_floatCast_f32(0xf1cc3892, 0xfc00); // -0x1.987124876876324p+100 -> -inf

    try test_f16_floatCast_f32(0x38800000, 0x0400); // normal (min), 2**-14
    try test_f16_floatCast_f32(0xb8800000, 0x8400); // normal (min), -2**-14

    try test_f16_floatCast_f32(0x477fe000, 0x7bff); // normal (max), 65504
    try test_f16_floatCast_f32(0xc77fe000, 0xfbff); // normal (max), -65504

    try test_f16_floatCast_f32(0x477fe100, 0x7bff); // normal, 65505 -> 65504
    try test_f16_floatCast_f32(0xc77fe100, 0xfbff); // normal, -65505 -> -65504

    try test_f16_floatCast_f32(0x477fef00, 0x7bff); // normal, 65519 -> 65504
    try test_f16_floatCast_f32(0xc77fef00, 0xfbff); // normal, -65519 -> -65504

    try test_f16_floatCast_f32(0x3f802000, 0x3c01); // normal, 1 + 2**-10
    try test_f16_floatCast_f32(0xbf802000, 0xbc01); // normal, -1 - 2**-10

    try test_f16_floatCast_f32(0x3eaaa000, 0x3555); // normal, approx. 1/3
    try test_f16_floatCast_f32(0xbeaaa000, 0xb555); // normal, approx. -1/3

    try test_f16_floatCast_f32(0x40490fdb, 0x4248); // normal, 3.1415926535
    try test_f16_floatCast_f32(0xc0490fdb, 0xc248); // normal, -3.1415926535

    try test_f16_floatCast_f32(0x45cc3892, 0x6e62); // normal, 0x1.987124876876324p+12

    try test_f16_floatCast_f32(0x3f800000, 0x3c00); // normal, 1
    try test_f16_floatCast_f32(0x38800000, 0x0400); // normal, 0x1.0p-14

    try test_f16_floatCast_f32(0x33800000, 0x0001); // denormal (min), 2**-24
    try test_f16_floatCast_f32(0xb3800000, 0x8001); // denormal (min), -2**-24

    try test_f16_floatCast_f32(0x387fc000, 0x03ff); // denormal (max), 2**-14 - 2**-24
    try test_f16_floatCast_f32(0xb87fc000, 0x83ff); // denormal (max), -2**-14 + 2**-24

    try test_f16_floatCast_f32(0x35800000, 0x0010); // denormal, 0x1.0p-20
    try test_f16_floatCast_f32(0x33280000, 0x0001); // denormal, 0x1.5p-25 -> 0x1.0p-24
    try test_f16_floatCast_f32(0x33000000, 0x0000); // 0x1.0p-25 -> zero
}

fn test_f16_floatCast_f64(a: f64, expected: u16) !void {
    const rep: u16 = @bitCast(f16_floatCast_f64(a));

    if (rep == expected) {
        return;
    }
    // test other possible NaN representation(signal NaN)
    else if (expected == 0x7e00) {
        if ((rep & 0x7c00) == 0x7c00 and (rep & 0x3ff) > 0) {
            return;
        }
    }
    return error.TestFailure;
}

fn test_f16_floatCast_f64_raw(a: u64, expected: u16) !void {
    const actual: u16 = @bitCast(f16_floatCast_f64(@bitCast(a)));
    try testing.expect(actual == expected);
}

test f16_floatCast_f64 {
    try test_f16_floatCast_f64_raw(0x7ff8000000000000, 0x7e00); // qNaN
    try test_f16_floatCast_f64_raw(0x7ff0000000008000, 0x7e00); // NaN

    try test_f16_floatCast_f64_raw(0x7ff0000000000000, 0x7c00); //inf
    try test_f16_floatCast_f64_raw(0xfff0000000000000, 0xfc00); // -inf

    try test_f16_floatCast_f64(0.0, 0x0); // zero
    try test_f16_floatCast_f64_raw(0x80000000 << 32, 0x8000); // -zero

    try test_f16_floatCast_f64(3.1415926535, 0x4248);
    try test_f16_floatCast_f64(-3.1415926535, 0xc248);

    try test_f16_floatCast_f64(0x1.987124876876324p+1000, 0x7c00);
    try test_f16_floatCast_f64(0x1.987124876876324p+12, 0x6e62);
    try test_f16_floatCast_f64(0x1.0p+0, 0x3c00);
    try test_f16_floatCast_f64(0x1.0p-14, 0x0400);

    // denormal
    try test_f16_floatCast_f64(0x1.0p-20, 0x0010);
    try test_f16_floatCast_f64(0x1.0p-24, 0x0001);
    try test_f16_floatCast_f64(-0x1.0p-24, 0x8001);
    try test_f16_floatCast_f64(0x1.5p-25, 0x0001);

    // and back to zero
    try test_f16_floatCast_f64(0x1.0p-25, 0x0000);
    try test_f16_floatCast_f64(-0x1.0p-25, 0x8000);

    // max (precise)
    try test_f16_floatCast_f64(65504.0, 0x7bff);

    // max (rounded)
    try test_f16_floatCast_f64(65519.0, 0x7bff);

    // max (to +inf)
    try test_f16_floatCast_f64(65520.0, 0x7c00);
    try test_f16_floatCast_f64(-65520.0, 0xfc00);
    try test_f16_floatCast_f64(65536.0, 0x7c00);
}

fn test_f32_floatCast_f128(a: f128, expected: u32) !void {
    const x = f32_floatCast_f128(a);

    const rep: u32 = @bitCast(x);
    if (rep == expected) {
        return;
    }
    // test other possible NaN representation(signal NaN)
    else if (expected == 0x7fc00000) {
        if ((rep & 0x7f800000) == 0x7f800000 and (rep & 0x7fffff) > 0) {
            return;
        }
    }
    return error.TestFailure;
}

test f32_floatCast_f128 {
    // qnan
    try test_f32_floatCast_f128(@bitCast(@as(u128, 0x7fff800000000000 << 64)), 0x7fc00000);
    // nan
    try test_f32_floatCast_f128(@bitCast(@as(u128, (0x7fff000000000000 | (0x810000000000 & 0xffffffffffff)) << 64)), 0x7fc08000);
    // inf
    try test_f32_floatCast_f128(@bitCast(@as(u128, 0x7fff000000000000 << 64)), 0x7f800000);
    // zero
    try test_f32_floatCast_f128(0.0, 0x0);

    try test_f32_floatCast_f128(0x1.23a2abb4a2ddee355f36789abcdep+5, 0x4211d156);
    try test_f32_floatCast_f128(0x1.e3d3c45bd3abfd98b76a54cc321fp-9, 0x3b71e9e2);
    try test_f32_floatCast_f128(0x1.234eebb5faa678f4488693abcdefp+4534, 0x7f800000);
    try test_f32_floatCast_f128(0x1.edcba9bb8c76a5a43dd21f334634p-435, 0x0);
}

fn test_f64_floatCast_f128(a: f128, expected: u64) !void {
    const x = f64_floatCast_f128(a);

    const rep: u64 = @bitCast(x);
    if (rep == expected) {
        return;
    }
    // test other possible NaN representation(signal NaN)
    else if (expected == 0x7ff8000000000000) {
        if ((rep & 0x7ff0000000000000) == 0x7ff0000000000000 and (rep & 0xfffffffffffff) > 0) {
            return;
        }
    }
    return error.TestFailure;
}

test f64_floatCast_f128 {
    // qnan
    try test_f64_floatCast_f128(@bitCast(@as(u128, 0x7fff800000000000 << 64)), 0x7ff8000000000000);
    // nan
    try test_f64_floatCast_f128(@bitCast(@as(u128, (0x7fff000000000000 | (0x810000000000 & 0xffffffffffff)) << 64)), 0x7ff8100000000000);
    // inf
    try test_f64_floatCast_f128(@bitCast(@as(u128, 0x7fff000000000000 << 64)), 0x7ff0000000000000);
    // zero
    try test_f64_floatCast_f128(0.0, 0x0);

    try test_f64_floatCast_f128(0x1.af23456789bbaaab347645365cdep+5, 0x404af23456789bbb);
    try test_f64_floatCast_f128(0x1.dedafcff354b6ae9758763545432p-9, 0x3f6dedafcff354b7);
    try test_f64_floatCast_f128(0x1.2f34dd5f437e849b4baab754cdefp+4534, 0x7ff0000000000000);
    try test_f64_floatCast_f128(0x1.edcbff8ad76ab5bf46463233214fp-435, 0x24cedcbff8ad76ab);
}

fn test_f32_floatCast_f64(a: f64, expected: u32) !void {
    const x = f32_floatCast_f64(a);

    const rep: u32 = @bitCast(x);
    if (rep == expected) {
        return;
    }
    // test other possible NaN representation(signal NaN)
    else if (expected == 0x7fc00000) {
        if ((rep & 0x7f800000) == 0x7f800000 and (rep & 0x7fffff) > 0) {
            return;
        }
    }
    return error.TestFailure;
}

test f32_floatCast_f64 {
    // nan & qnan
    try test_f32_floatCast_f64(@bitCast(@as(u64, 0x7ff8000000000000)), 0x7fc00000);
    try test_f32_floatCast_f64(@bitCast(@as(u64, 0x7ff0000000000001)), 0x7fc00000);
    // inf
    try test_f32_floatCast_f64(@bitCast(@as(u64, 0x7ff0000000000000)), 0x7f800000);
    try test_f32_floatCast_f64(@bitCast(@as(u64, 0xfff0000000000000)), 0xff800000);

    try test_f32_floatCast_f64(0.0, 0x0);
    try test_f32_floatCast_f64(1.0, 0x3f800000);
    try test_f32_floatCast_f64(-1.0, 0xbf800000);

    // huge number becomes inf
    try test_f32_floatCast_f64(340282366920938463463374607431768211456.0, 0x7f800000);
}

fn test_f16_floatCast_f128(a: f128, expected: u16) !void {
    const x = f16_floatCast_f128(a);

    const rep: u16 = @bitCast(x);
    try testing.expect(rep == expected);
}

test f16_floatCast_f128 {
    // qNaN
    try test_f16_floatCast_f128(@bitCast(@as(u128, 0x7fff8000000000000000000000000000)), 0x7e00);
    // NaN
    try test_f16_floatCast_f128(@bitCast(@as(u128, 0x7fff0000000000000000000000000001)), 0x7e00);
    // inf
    try test_f16_floatCast_f128(@bitCast(@as(u128, 0x7fff0000000000000000000000000000)), 0x7c00);
    try test_f16_floatCast_f128(-@as(f128, @bitCast(@as(u128, 0x7fff0000000000000000000000000000))), 0xfc00);
    // zero
    try test_f16_floatCast_f128(0.0, 0x0);
    try test_f16_floatCast_f128(-0.0, 0x8000);

    try test_f16_floatCast_f128(3.1415926535, 0x4248);
    try test_f16_floatCast_f128(-3.1415926535, 0xc248);
    try test_f16_floatCast_f128(0x1.987124876876324p+100, 0x7c00);
    try test_f16_floatCast_f128(0x1.987124876876324p+12, 0x6e62);
    try test_f16_floatCast_f128(0x1.0p+0, 0x3c00);
    try test_f16_floatCast_f128(0x1.0p-14, 0x0400);
    // denormal
    try test_f16_floatCast_f128(0x1.0p-20, 0x0010);
    try test_f16_floatCast_f128(0x1.0p-24, 0x0001);
    try test_f16_floatCast_f128(-0x1.0p-24, 0x8001);
    try test_f16_floatCast_f128(0x1.5p-25, 0x0001);
    // and back to zero
    try test_f16_floatCast_f128(0x1.0p-25, 0x0000);
    try test_f16_floatCast_f128(-0x1.0p-25, 0x8000);
    // max (precise)
    try test_f16_floatCast_f128(65504.0, 0x7bff);
    // max (rounded)
    try test_f16_floatCast_f128(65519.0, 0x7bff);
    // max (to +inf)
    try test_f16_floatCast_f128(65520.0, 0x7c00);
    try test_f16_floatCast_f128(65536.0, 0x7c00);
    try test_f16_floatCast_f128(-65520.0, 0xfc00);

    try test_f16_floatCast_f128(0x1.23a2abb4a2ddee355f36789abcdep+5, 0x508f);
    try test_f16_floatCast_f128(0x1.e3d3c45bd3abfd98b76a54cc321fp-9, 0x1b8f);
    try test_f16_floatCast_f128(0x1.234eebb5faa678f4488693abcdefp+453, 0x7c00);
    try test_f16_floatCast_f128(0x1.edcba9bb8c76a5a43dd21f334634p-43, 0x0);
}

fn test_f80_floatCast_f128(a: f128, expected: f80) !void {
    const x = f80_floatCast_f128(a);
    try testing.expect(x == expected);
}

test f80_floatCast_f128 {
    try test_f80_floatCast_f128(1.5, 1.5);
    try test_f80_floatCast_f128(2.5, 2.5);
    try test_f80_floatCast_f128(-2.5, -2.5);
    try test_f80_floatCast_f128(0.0, 0.0);
}
