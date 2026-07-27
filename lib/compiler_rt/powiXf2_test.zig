// ported from https://github.com/llvm-mirror/compiler-rt/blob/release_80/test/builtins/Unit/
// powisf2_test.c, powidf2_test.c, powitf2_test.c, powixf2_test.c
// powihf2 adapted from powisf2 tests

const std = @import("std");
const testing = std.testing;
const math = std.math;

const impl = @import("powiXf2.zig");

const powi_f16 = impl.powi_f16;
const powi_f32 = impl.powi_f32;
const powi_f64 = impl.powi_f64;
const powi_f80 = impl.powi_f80;
const powi_f128 = impl.powi_f128;

fn test_powi_f16(a: f16, b: i32, expected: f16) !void {
    const result = powi_f16(a, b);
    try testing.expectEqual(expected, result);
}

fn test_powi_f32(a: f32, b: i32, expected: f32) !void {
    const result = powi_f32(a, b);
    try testing.expectEqual(expected, result);
}

fn test_powi_f64(a: f64, b: i32, expected: f64) !void {
    const result = powi_f64(a, b);
    try testing.expectEqual(expected, result);
}

fn test_powi_f80(a: f80, b: i32, expected: f80) !void {
    const result = powi_f80(a, b);
    try testing.expectEqual(expected, result);
}

fn test_powi_f128(a: f128, b: i32, expected: f128) !void {
    const result = powi_f128(a, b);
    try testing.expectEqual(expected, result);
}

test powi_f16 {
    const inf_f16 = math.inf(f16);
    try test_powi_f16(0, 0, 1);
    try test_powi_f16(1, 0, 1);
    try test_powi_f16(1.5, 0, 1);
    try test_powi_f16(2, 0, 1);
    try test_powi_f16(inf_f16, 0, 1);

    try test_powi_f16(-0.0, 0, 1);
    try test_powi_f16(-1, 0, 1);
    try test_powi_f16(-1.5, 0, 1);
    try test_powi_f16(-2, 0, 1);
    try test_powi_f16(-inf_f16, 0, 1);

    try test_powi_f16(0, 1, 0);
    try test_powi_f16(0, 2, 0);
    try test_powi_f16(0, 3, 0);
    try test_powi_f16(0, 4, 0);
    try test_powi_f16(0, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), 0);
    try test_powi_f16(0, @as(i32, @bitCast(@as(u32, 0x7FFFFFFF))), 0);

    try test_powi_f16(-0.0, 1, -0.0);
    try test_powi_f16(-0.0, 2, 0);
    try test_powi_f16(-0.0, 3, -0.0);
    try test_powi_f16(-0.0, 4, 0);
    try test_powi_f16(-0.0, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), 0);
    try test_powi_f16(-0.0, @as(i32, @bitCast(@as(u32, 0x7FFFFFFF))), -0.0);

    try test_powi_f16(1, 1, 1);
    try test_powi_f16(1, 2, 1);
    try test_powi_f16(1, 3, 1);
    try test_powi_f16(1, 4, 1);
    try test_powi_f16(1, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), 1);
    try test_powi_f16(1, @as(i32, @bitCast(@as(u32, 0x7FFFFFFF))), 1);

    try test_powi_f16(inf_f16, 1, inf_f16);
    try test_powi_f16(inf_f16, 2, inf_f16);
    try test_powi_f16(inf_f16, 3, inf_f16);
    try test_powi_f16(inf_f16, 4, inf_f16);
    try test_powi_f16(inf_f16, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), inf_f16);
    try test_powi_f16(inf_f16, @as(i32, @bitCast(@as(u32, 0x7FFFFFFF))), inf_f16);

    try test_powi_f16(-inf_f16, 1, -inf_f16);
    try test_powi_f16(-inf_f16, 2, inf_f16);
    try test_powi_f16(-inf_f16, 3, -inf_f16);
    try test_powi_f16(-inf_f16, 4, inf_f16);
    try test_powi_f16(-inf_f16, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), inf_f16);
    try test_powi_f16(-inf_f16, @as(i32, @bitCast(@as(u32, 0x7FFFFFFF))), -inf_f16);
    //
    try test_powi_f16(0, -1, inf_f16);
    try test_powi_f16(0, -2, inf_f16);
    try test_powi_f16(0, -3, inf_f16);
    try test_powi_f16(0, -4, inf_f16);
    try test_powi_f16(0, @as(i32, @bitCast(@as(u32, 0x80000002))), inf_f16); // 0 ^ anything = +inf
    try test_powi_f16(0, @as(i32, @bitCast(@as(u32, 0x80000001))), inf_f16);
    try test_powi_f16(0, @as(i32, @bitCast(@as(u32, 0x80000000))), inf_f16);

    try test_powi_f16(-0.0, -1, -inf_f16);
    try test_powi_f16(-0.0, -2, inf_f16);
    try test_powi_f16(-0.0, -3, -inf_f16);
    try test_powi_f16(-0.0, -4, inf_f16);
    try test_powi_f16(-0.0, @as(i32, @bitCast(@as(u32, 0x80000002))), inf_f16); // -0 ^ anything even = +inf
    try test_powi_f16(-0.0, @as(i32, @bitCast(@as(u32, 0x80000001))), -inf_f16); // -0 ^ anything odd = -inf
    try test_powi_f16(-0.0, @as(i32, @bitCast(@as(u32, 0x80000000))), inf_f16);

    try test_powi_f16(1, -1, 1);
    try test_powi_f16(1, -2, 1);
    try test_powi_f16(1, -3, 1);
    try test_powi_f16(1, -4, 1);
    try test_powi_f16(1, @as(i32, @bitCast(@as(u32, 0x80000002))), 1); // 1.0 ^ anything = 1
    try test_powi_f16(1, @as(i32, @bitCast(@as(u32, 0x80000001))), 1);
    try test_powi_f16(1, @as(i32, @bitCast(@as(u32, 0x80000000))), 1);

    try test_powi_f16(inf_f16, -1, 0);
    try test_powi_f16(inf_f16, -2, 0);
    try test_powi_f16(inf_f16, -3, 0);
    try test_powi_f16(inf_f16, -4, 0);
    try test_powi_f16(inf_f16, @as(i32, @bitCast(@as(u32, 0x80000002))), 0);
    try test_powi_f16(inf_f16, @as(i32, @bitCast(@as(u32, 0x80000001))), 0);
    try test_powi_f16(inf_f16, @as(i32, @bitCast(@as(u32, 0x80000000))), 0);
    //
    try test_powi_f16(-inf_f16, -1, -0.0);
    try test_powi_f16(-inf_f16, -2, 0);
    try test_powi_f16(-inf_f16, -3, -0.0);
    try test_powi_f16(-inf_f16, -4, 0);
    try test_powi_f16(-inf_f16, @as(i32, @bitCast(@as(u32, 0x80000002))), 0);
    try test_powi_f16(-inf_f16, @as(i32, @bitCast(@as(u32, 0x80000001))), -0.0);
    try test_powi_f16(-inf_f16, @as(i32, @bitCast(@as(u32, 0x80000000))), 0);

    try test_powi_f16(2, 10, 1024.0);
    try test_powi_f16(-2, 10, 1024.0);
    try test_powi_f16(2, -10, 1.0 / 1024.0);
    try test_powi_f16(-2, -10, 1.0 / 1024.0);

    try test_powi_f16(2, 14, 16384.0);
    try test_powi_f16(-2, 14, 16384.0);
    try test_powi_f16(2, 15, 32768.0);
    try test_powi_f16(-2, 15, -32768.0);
    try test_powi_f16(2, 16, inf_f16);
    try test_powi_f16(-2, 16, inf_f16);

    try test_powi_f16(2, -13, 1.0 / 8192.0);
    try test_powi_f16(-2, -13, -1.0 / 8192.0);
    try test_powi_f16(2, -15, 1.0 / 32768.0);
    try test_powi_f16(-2, -15, -1.0 / 32768.0);
    try test_powi_f16(2, -16, 0.0); // expected = 0.0 = 1/(-2**16)
    try test_powi_f16(-2, -16, 0.0); // expected = 0.0 = 1/(2**16)
}

test powi_f32 {
    const inf_f32 = math.inf(f32);
    try test_powi_f32(0, 0, 1);
    try test_powi_f32(1, 0, 1);
    try test_powi_f32(1.5, 0, 1);
    try test_powi_f32(2, 0, 1);
    try test_powi_f32(inf_f32, 0, 1);

    try test_powi_f32(-0.0, 0, 1);
    try test_powi_f32(-1, 0, 1);
    try test_powi_f32(-1.5, 0, 1);
    try test_powi_f32(-2, 0, 1);
    try test_powi_f32(-inf_f32, 0, 1);

    try test_powi_f32(0, 1, 0);
    try test_powi_f32(0, 2, 0);
    try test_powi_f32(0, 3, 0);
    try test_powi_f32(0, 4, 0);
    try test_powi_f32(0, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), 0);
    try test_powi_f32(0, @as(i32, @bitCast(@as(u32, 0x7FFFFFFF))), 0);

    try test_powi_f32(-0.0, 1, -0.0);
    try test_powi_f32(-0.0, 2, 0);
    try test_powi_f32(-0.0, 3, -0.0);
    try test_powi_f32(-0.0, 4, 0);
    try test_powi_f32(-0.0, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), 0);
    try test_powi_f32(-0.0, @as(i32, @bitCast(@as(u32, 0x7FFFFFFF))), -0.0);

    try test_powi_f32(1, 1, 1);
    try test_powi_f32(1, 2, 1);
    try test_powi_f32(1, 3, 1);
    try test_powi_f32(1, 4, 1);
    try test_powi_f32(1, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), 1);
    try test_powi_f32(1, @as(i32, @bitCast(@as(u32, 0x7FFFFFFF))), 1);

    try test_powi_f32(inf_f32, 1, inf_f32);
    try test_powi_f32(inf_f32, 2, inf_f32);
    try test_powi_f32(inf_f32, 3, inf_f32);
    try test_powi_f32(inf_f32, 4, inf_f32);
    try test_powi_f32(inf_f32, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), inf_f32);
    try test_powi_f32(inf_f32, @as(i32, @bitCast(@as(u32, 0x7FFFFFFF))), inf_f32);

    try test_powi_f32(-inf_f32, 1, -inf_f32);
    try test_powi_f32(-inf_f32, 2, inf_f32);
    try test_powi_f32(-inf_f32, 3, -inf_f32);
    try test_powi_f32(-inf_f32, 4, inf_f32);
    try test_powi_f32(-inf_f32, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), inf_f32);
    try test_powi_f32(-inf_f32, @as(i32, @bitCast(@as(u32, 0x7FFFFFFF))), -inf_f32);

    try test_powi_f32(0, -1, inf_f32);
    try test_powi_f32(0, -2, inf_f32);
    try test_powi_f32(0, -3, inf_f32);
    try test_powi_f32(0, -4, inf_f32);
    try test_powi_f32(0, @as(i32, @bitCast(@as(u32, 0x80000002))), inf_f32);
    try test_powi_f32(0, @as(i32, @bitCast(@as(u32, 0x80000001))), inf_f32);
    try test_powi_f32(0, @as(i32, @bitCast(@as(u32, 0x80000000))), inf_f32);

    try test_powi_f32(-0.0, -1, -inf_f32);
    try test_powi_f32(-0.0, -2, inf_f32);
    try test_powi_f32(-0.0, -3, -inf_f32);
    try test_powi_f32(-0.0, -4, inf_f32);
    try test_powi_f32(-0.0, @as(i32, @bitCast(@as(u32, 0x80000002))), inf_f32);
    try test_powi_f32(-0.0, @as(i32, @bitCast(@as(u32, 0x80000001))), -inf_f32);
    try test_powi_f32(-0.0, @as(i32, @bitCast(@as(u32, 0x80000000))), inf_f32);

    try test_powi_f32(1, -1, 1);
    try test_powi_f32(1, -2, 1);
    try test_powi_f32(1, -3, 1);
    try test_powi_f32(1, -4, 1);
    try test_powi_f32(1, @as(i32, @bitCast(@as(u32, 0x80000002))), 1);
    try test_powi_f32(1, @as(i32, @bitCast(@as(u32, 0x80000001))), 1);
    try test_powi_f32(1, @as(i32, @bitCast(@as(u32, 0x80000000))), 1);

    try test_powi_f32(inf_f32, -1, 0);
    try test_powi_f32(inf_f32, -2, 0);
    try test_powi_f32(inf_f32, -3, 0);
    try test_powi_f32(inf_f32, -4, 0);
    try test_powi_f32(inf_f32, @as(i32, @bitCast(@as(u32, 0x80000002))), 0);
    try test_powi_f32(inf_f32, @as(i32, @bitCast(@as(u32, 0x80000001))), 0);
    try test_powi_f32(inf_f32, @as(i32, @bitCast(@as(u32, 0x80000000))), 0);

    try test_powi_f32(-inf_f32, -1, -0.0);
    try test_powi_f32(-inf_f32, -2, 0);
    try test_powi_f32(-inf_f32, -3, -0.0);
    try test_powi_f32(-inf_f32, -4, 0);
    try test_powi_f32(-inf_f32, @as(i32, @bitCast(@as(u32, 0x80000002))), 0);
    try test_powi_f32(-inf_f32, @as(i32, @bitCast(@as(u32, 0x80000001))), -0.0);
    try test_powi_f32(-inf_f32, @as(i32, @bitCast(@as(u32, 0x80000000))), 0);

    try test_powi_f32(2.0, 10, 1024.0);
    try test_powi_f32(-2, 10, 1024.0);
    try test_powi_f32(2, -10, 1.0 / 1024.0);
    try test_powi_f32(-2, -10, 1.0 / 1024.0);
    //
    try test_powi_f32(2, 19, 524288.0);
    try test_powi_f32(-2, 19, -524288.0);
    try test_powi_f32(2, -19, 1.0 / 524288.0);
    try test_powi_f32(-2, -19, -1.0 / 524288.0);

    try test_powi_f32(2, 31, 2147483648.0);
    try test_powi_f32(-2, 31, -2147483648.0);
    try test_powi_f32(2, -31, 1.0 / 2147483648.0);
    try test_powi_f32(-2, -31, -1.0 / 2147483648.0);
}

test powi_f64 {
    const inf_f64 = math.inf(f64);
    try test_powi_f64(0, 0, 1);
    try test_powi_f64(1, 0, 1);
    try test_powi_f64(1.5, 0, 1);
    try test_powi_f64(2, 0, 1);
    try test_powi_f64(inf_f64, 0, 1);

    try test_powi_f64(-0.0, 0, 1);
    try test_powi_f64(-1, 0, 1);
    try test_powi_f64(-1.5, 0, 1);
    try test_powi_f64(-2, 0, 1);
    try test_powi_f64(-inf_f64, 0, 1);

    try test_powi_f64(0, 1, 0);
    try test_powi_f64(0, 2, 0);
    try test_powi_f64(0, 3, 0);
    try test_powi_f64(0, 4, 0);
    try test_powi_f64(0, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), 0);
    try test_powi_f64(0, @as(i32, @bitCast(@as(u32, 0x7FFFFFFF))), 0);

    try test_powi_f64(-0.0, 1, -0.0);
    try test_powi_f64(-0.0, 2, 0);
    try test_powi_f64(-0.0, 3, -0.0);
    try test_powi_f64(-0.0, 4, 0);
    try test_powi_f64(-0.0, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), 0);
    try test_powi_f64(-0.0, @as(i32, @bitCast(@as(u32, 0x7FFFFFFF))), -0.0);

    try test_powi_f64(1, 1, 1);
    try test_powi_f64(1, 2, 1);
    try test_powi_f64(1, 3, 1);
    try test_powi_f64(1, 4, 1);
    try test_powi_f64(1, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), 1);
    try test_powi_f64(1, @as(i32, @bitCast(@as(u32, 0x7FFFFFFF))), 1);

    try test_powi_f64(inf_f64, 1, inf_f64);
    try test_powi_f64(inf_f64, 2, inf_f64);
    try test_powi_f64(inf_f64, 3, inf_f64);
    try test_powi_f64(inf_f64, 4, inf_f64);
    try test_powi_f64(inf_f64, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), inf_f64);
    try test_powi_f64(inf_f64, @as(i32, @bitCast(@as(u32, 0x7FFFFFFF))), inf_f64);

    try test_powi_f64(-inf_f64, 1, -inf_f64);
    try test_powi_f64(-inf_f64, 2, inf_f64);
    try test_powi_f64(-inf_f64, 3, -inf_f64);
    try test_powi_f64(-inf_f64, 4, inf_f64);
    try test_powi_f64(-inf_f64, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), inf_f64);
    try test_powi_f64(-inf_f64, @as(i32, @bitCast(@as(u32, 0x7FFFFFFF))), -inf_f64);

    try test_powi_f64(0, -1, inf_f64);
    try test_powi_f64(0, -2, inf_f64);
    try test_powi_f64(0, -3, inf_f64);
    try test_powi_f64(0, -4, inf_f64);
    try test_powi_f64(0, @as(i32, @bitCast(@as(u32, 0x80000002))), inf_f64);
    try test_powi_f64(0, @as(i32, @bitCast(@as(u32, 0x80000001))), inf_f64);
    try test_powi_f64(0, @as(i32, @bitCast(@as(u32, 0x80000000))), inf_f64);

    try test_powi_f64(-0.0, -1, -inf_f64);
    try test_powi_f64(-0.0, -2, inf_f64);
    try test_powi_f64(-0.0, -3, -inf_f64);
    try test_powi_f64(-0.0, -4, inf_f64);
    try test_powi_f64(-0.0, @as(i32, @bitCast(@as(u32, 0x80000002))), inf_f64);
    try test_powi_f64(-0.0, @as(i32, @bitCast(@as(u32, 0x80000001))), -inf_f64);
    try test_powi_f64(-0.0, @as(i32, @bitCast(@as(u32, 0x80000000))), inf_f64);

    try test_powi_f64(1, -1, 1);
    try test_powi_f64(1, -2, 1);
    try test_powi_f64(1, -3, 1);
    try test_powi_f64(1, -4, 1);
    try test_powi_f64(1, @as(i32, @bitCast(@as(u32, 0x80000002))), 1);
    try test_powi_f64(1, @as(i32, @bitCast(@as(u32, 0x80000001))), 1);
    try test_powi_f64(1, @as(i32, @bitCast(@as(u32, 0x80000000))), 1);

    try test_powi_f64(inf_f64, -1, 0);
    try test_powi_f64(inf_f64, -2, 0);
    try test_powi_f64(inf_f64, -3, 0);
    try test_powi_f64(inf_f64, -4, 0);
    try test_powi_f64(inf_f64, @as(i32, @bitCast(@as(u32, 0x80000002))), 0);
    try test_powi_f64(inf_f64, @as(i32, @bitCast(@as(u32, 0x80000001))), 0);
    try test_powi_f64(inf_f64, @as(i32, @bitCast(@as(u32, 0x80000000))), 0);

    try test_powi_f64(-inf_f64, -1, -0.0);
    try test_powi_f64(-inf_f64, -2, 0);
    try test_powi_f64(-inf_f64, -3, -0.0);
    try test_powi_f64(-inf_f64, -4, 0);
    try test_powi_f64(-inf_f64, @as(i32, @bitCast(@as(u32, 0x80000002))), 0);
    try test_powi_f64(-inf_f64, @as(i32, @bitCast(@as(u32, 0x80000001))), -0.0);
    try test_powi_f64(-inf_f64, @as(i32, @bitCast(@as(u32, 0x80000000))), 0);

    try test_powi_f64(2, 10, 1024.0);
    try test_powi_f64(-2, 10, 1024.0);
    try test_powi_f64(2, -10, 1.0 / 1024.0);
    try test_powi_f64(-2, -10, 1.0 / 1024.0);

    try test_powi_f64(2, 19, 524288.0);
    try test_powi_f64(-2, 19, -524288.0);
    try test_powi_f64(2, -19, 1.0 / 524288.0);
    try test_powi_f64(-2, -19, -1.0 / 524288.0);

    try test_powi_f64(2, 31, 2147483648.0);
    try test_powi_f64(-2, 31, -2147483648.0);
    try test_powi_f64(2, -31, 1.0 / 2147483648.0);
    try test_powi_f64(-2, -31, -1.0 / 2147483648.0);
}

test powi_f80 {
    const inf_f80 = math.inf(f80);
    try test_powi_f80(0, 0, 1);
    try test_powi_f80(1, 0, 1);
    try test_powi_f80(1.5, 0, 1);
    try test_powi_f80(2, 0, 1);
    try test_powi_f80(inf_f80, 0, 1);

    try test_powi_f80(-0.0, 0, 1);
    try test_powi_f80(-1, 0, 1);
    try test_powi_f80(-1.5, 0, 1);
    try test_powi_f80(-2, 0, 1);
    try test_powi_f80(-inf_f80, 0, 1);

    try test_powi_f80(0, 1, 0);
    try test_powi_f80(0, 2, 0);
    try test_powi_f80(0, 3, 0);
    try test_powi_f80(0, 4, 0);
    try test_powi_f80(0, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), 0);
    try test_powi_f80(0, @as(i32, @bitCast(@as(u32, 0x7FFFFFFF))), 0);

    try test_powi_f80(-0.0, 1, -0.0);
    try test_powi_f80(-0.0, 2, 0);
    try test_powi_f80(-0.0, 3, -0.0);
    try test_powi_f80(-0.0, 4, 0);
    try test_powi_f80(-0.0, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), 0);
    try test_powi_f80(-0.0, @as(i32, @bitCast(@as(u32, 0x7FFFFFFF))), -0.0);

    try test_powi_f80(1, 1, 1);
    try test_powi_f80(1, 2, 1);
    try test_powi_f80(1, 3, 1);
    try test_powi_f80(1, 4, 1);
    try test_powi_f80(1, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), 1);
    try test_powi_f80(1, @as(i32, @bitCast(@as(u32, 0x7FFFFFFF))), 1);

    try test_powi_f80(inf_f80, 1, inf_f80);
    try test_powi_f80(inf_f80, 2, inf_f80);
    try test_powi_f80(inf_f80, 3, inf_f80);
    try test_powi_f80(inf_f80, 4, inf_f80);
    try test_powi_f80(inf_f80, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), inf_f80);
    try test_powi_f80(inf_f80, @as(i32, @bitCast(@as(u32, 0x7FFFFFFF))), inf_f80);

    try test_powi_f80(-inf_f80, 1, -inf_f80);
    try test_powi_f80(-inf_f80, 2, inf_f80);
    try test_powi_f80(-inf_f80, 3, -inf_f80);
    try test_powi_f80(-inf_f80, 4, inf_f80);
    try test_powi_f80(-inf_f80, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), inf_f80);
    try test_powi_f80(-inf_f80, @as(i32, @bitCast(@as(u32, 0x7FFFFFFF))), -inf_f80);

    try test_powi_f80(0, -1, inf_f80);
    try test_powi_f80(0, -2, inf_f80);
    try test_powi_f80(0, -3, inf_f80);
    try test_powi_f80(0, -4, inf_f80);
    try test_powi_f80(0, @as(i32, @bitCast(@as(u32, 0x80000002))), inf_f80);
    try test_powi_f80(0, @as(i32, @bitCast(@as(u32, 0x80000001))), inf_f80);
    try test_powi_f80(0, @as(i32, @bitCast(@as(u32, 0x80000000))), inf_f80);

    try test_powi_f80(-0.0, -1, -inf_f80);
    try test_powi_f80(-0.0, -2, inf_f80);
    try test_powi_f80(-0.0, -3, -inf_f80);
    try test_powi_f80(-0.0, -4, inf_f80);
    try test_powi_f80(-0.0, @as(i32, @bitCast(@as(u32, 0x80000002))), inf_f80);
    try test_powi_f80(-0.0, @as(i32, @bitCast(@as(u32, 0x80000001))), -inf_f80);
    try test_powi_f80(-0.0, @as(i32, @bitCast(@as(u32, 0x80000000))), inf_f80);

    try test_powi_f80(1, -1, 1);
    try test_powi_f80(1, -2, 1);
    try test_powi_f80(1, -3, 1);
    try test_powi_f80(1, -4, 1);
    try test_powi_f80(1, @as(i32, @bitCast(@as(u32, 0x80000002))), 1);
    try test_powi_f80(1, @as(i32, @bitCast(@as(u32, 0x80000001))), 1);
    try test_powi_f80(1, @as(i32, @bitCast(@as(u32, 0x80000000))), 1);

    try test_powi_f80(inf_f80, -1, 0);
    try test_powi_f80(inf_f80, -2, 0);
    try test_powi_f80(inf_f80, -3, 0);
    try test_powi_f80(inf_f80, -4, 0);
    try test_powi_f80(inf_f80, @as(i32, @bitCast(@as(u32, 0x80000002))), 0);
    try test_powi_f80(inf_f80, @as(i32, @bitCast(@as(u32, 0x80000001))), 0);
    try test_powi_f80(inf_f80, @as(i32, @bitCast(@as(u32, 0x80000000))), 0);

    try test_powi_f80(-inf_f80, -1, -0.0);
    try test_powi_f80(-inf_f80, -2, 0);
    try test_powi_f80(-inf_f80, -3, -0.0);
    try test_powi_f80(-inf_f80, -4, 0);
    try test_powi_f80(-inf_f80, @as(i32, @bitCast(@as(u32, 0x80000002))), 0);
    try test_powi_f80(-inf_f80, @as(i32, @bitCast(@as(u32, 0x80000001))), -0.0);
    try test_powi_f80(-inf_f80, @as(i32, @bitCast(@as(u32, 0x80000000))), 0);

    try test_powi_f80(2, 10, 1024.0);
    try test_powi_f80(-2, 10, 1024.0);
    try test_powi_f80(2, -10, 1.0 / 1024.0);
    try test_powi_f80(-2, -10, 1.0 / 1024.0);

    try test_powi_f80(2, 19, 524288.0);
    try test_powi_f80(-2, 19, -524288.0);
    try test_powi_f80(2, -19, 1.0 / 524288.0);
    try test_powi_f80(-2, -19, -1.0 / 524288.0);

    try test_powi_f80(2, 31, 2147483648.0);
    try test_powi_f80(-2, 31, -2147483648.0);
    try test_powi_f80(2, -31, 1.0 / 2147483648.0);
    try test_powi_f80(-2, -31, -1.0 / 2147483648.0);
}

test powi_f128 {
    const inf_f128 = math.inf(f128);
    try test_powi_f128(0, 0, 1);
    try test_powi_f128(1, 0, 1);
    try test_powi_f128(1.5, 0, 1);
    try test_powi_f128(2, 0, 1);
    try test_powi_f128(inf_f128, 0, 1);

    try test_powi_f128(-0.0, 0, 1);
    try test_powi_f128(-1, 0, 1);
    try test_powi_f128(-1.5, 0, 1);
    try test_powi_f128(-2, 0, 1);
    try test_powi_f128(-inf_f128, 0, 1);

    try test_powi_f128(0, 1, 0);
    try test_powi_f128(0, 2, 0);
    try test_powi_f128(0, 3, 0);
    try test_powi_f128(0, 4, 0);
    try test_powi_f128(0, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), 0);
    try test_powi_f128(0, 0x7FFFFFFF, 0);

    try test_powi_f128(-0.0, 1, -0.0);
    try test_powi_f128(-0.0, 2, 0);
    try test_powi_f128(-0.0, 3, -0.0);
    try test_powi_f128(-0.0, 4, 0);
    try test_powi_f128(-0.0, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), 0);
    try test_powi_f128(-0.0, @as(i32, @bitCast(@as(u32, 0x7FFFFFFF))), -0.0);

    try test_powi_f128(1, 1, 1);
    try test_powi_f128(1, 2, 1);
    try test_powi_f128(1, 3, 1);
    try test_powi_f128(1, 4, 1);
    try test_powi_f128(1, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), 1);
    try test_powi_f128(1, @as(i32, @bitCast(@as(u32, 0x7FFFFFFF))), 1);

    try test_powi_f128(inf_f128, 1, inf_f128);
    try test_powi_f128(inf_f128, 2, inf_f128);
    try test_powi_f128(inf_f128, 3, inf_f128);
    try test_powi_f128(inf_f128, 4, inf_f128);
    try test_powi_f128(inf_f128, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), inf_f128);
    try test_powi_f128(inf_f128, @as(i32, @bitCast(@as(u32, 0x7FFFFFFF))), inf_f128);

    try test_powi_f128(-inf_f128, 1, -inf_f128);
    try test_powi_f128(-inf_f128, 2, inf_f128);
    try test_powi_f128(-inf_f128, 3, -inf_f128);
    try test_powi_f128(-inf_f128, 4, inf_f128);
    try test_powi_f128(-inf_f128, @as(i32, @bitCast(@as(u32, 0x7FFFFFFE))), inf_f128);
    try test_powi_f128(-inf_f128, @as(i32, @bitCast(@as(u32, 0x7FFFFFFF))), -inf_f128);

    try test_powi_f128(0, -1, inf_f128);
    try test_powi_f128(0, -2, inf_f128);
    try test_powi_f128(0, -3, inf_f128);
    try test_powi_f128(0, -4, inf_f128);
    try test_powi_f128(0, @as(i32, @bitCast(@as(u32, 0x80000002))), inf_f128);
    try test_powi_f128(0, @as(i32, @bitCast(@as(u32, 0x80000001))), inf_f128);
    try test_powi_f128(0, @as(i32, @bitCast(@as(u32, 0x80000000))), inf_f128);

    try test_powi_f128(-0.0, -1, -inf_f128);
    try test_powi_f128(-0.0, -2, inf_f128);
    try test_powi_f128(-0.0, -3, -inf_f128);
    try test_powi_f128(-0.0, -4, inf_f128);
    try test_powi_f128(-0.0, @as(i32, @bitCast(@as(u32, 0x80000002))), inf_f128);
    try test_powi_f128(-0.0, @as(i32, @bitCast(@as(u32, 0x80000001))), -inf_f128);
    try test_powi_f128(-0.0, @as(i32, @bitCast(@as(u32, 0x80000000))), inf_f128);

    try test_powi_f128(1, -1, 1);
    try test_powi_f128(1, -2, 1);
    try test_powi_f128(1, -3, 1);
    try test_powi_f128(1, -4, 1);
    try test_powi_f128(1, @as(i32, @bitCast(@as(u32, 0x80000002))), 1);
    try test_powi_f128(1, @as(i32, @bitCast(@as(u32, 0x80000001))), 1);
    try test_powi_f128(1, @as(i32, @bitCast(@as(u32, 0x80000000))), 1);

    try test_powi_f128(inf_f128, -1, 0);
    try test_powi_f128(inf_f128, -2, 0);
    try test_powi_f128(inf_f128, -3, 0);
    try test_powi_f128(inf_f128, -4, 0);
    try test_powi_f128(inf_f128, @as(i32, @bitCast(@as(u32, 0x80000002))), 0);
    try test_powi_f128(inf_f128, @as(i32, @bitCast(@as(u32, 0x80000001))), 0);
    try test_powi_f128(inf_f128, @as(i32, @bitCast(@as(u32, 0x80000000))), 0);

    try test_powi_f128(-inf_f128, -1, -0.0);
    try test_powi_f128(-inf_f128, -2, 0);
    try test_powi_f128(-inf_f128, -3, -0.0);
    try test_powi_f128(-inf_f128, -4, 0);
    try test_powi_f128(-inf_f128, @as(i32, @bitCast(@as(u32, 0x80000002))), 0);
    try test_powi_f128(-inf_f128, @as(i32, @bitCast(@as(u32, 0x80000001))), -0.0);
    try test_powi_f128(-inf_f128, @as(i32, @bitCast(@as(u32, 0x80000000))), 0);

    try test_powi_f128(2, 10, 1024.0);
    try test_powi_f128(-2, 10, 1024.0);
    try test_powi_f128(2, -10, 1.0 / 1024.0);
    try test_powi_f128(-2, -10, 1.0 / 1024.0);

    try test_powi_f128(2, 19, 524288.0);
    try test_powi_f128(-2, 19, -524288.0);
    try test_powi_f128(2, -19, 1.0 / 524288.0);
    try test_powi_f128(-2, -19, -1.0 / 524288.0);

    try test_powi_f128(2, 31, 2147483648.0);
    try test_powi_f128(-2, 31, -2147483648.0);
    try test_powi_f128(2, -31, 1.0 / 2147483648.0);
    try test_powi_f128(-2, -31, -1.0 / 2147483648.0);
}
