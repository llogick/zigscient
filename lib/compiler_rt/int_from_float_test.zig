const std = @import("std");
const testing = std.testing;
const math = std.math;

const impl = @import("int_from_float.zig");

const i32_intFromFloat_f16 = impl.i32_intFromFloat_f16;
const u32_intFromFloat_f16 = impl.u32_intFromFloat_f16;
const i64_intFromFloat_f16 = impl.i64_intFromFloat_f16;
const u64_intFromFloat_f16 = impl.u64_intFromFloat_f16;
const i128_intFromFloat_f16 = impl.i128_intFromFloat_f16;
const u128_intFromFloat_f16 = impl.u128_intFromFloat_f16;
const signed_intFromFloat_f16 = impl.signed_intFromFloat_f16;
const unsigned_intFromFloat_f16 = impl.unsigned_intFromFloat_f16;

const i32_intFromFloat_f32 = impl.i32_intFromFloat_f32;
const u32_intFromFloat_f32 = impl.u32_intFromFloat_f32;
const i64_intFromFloat_f32 = impl.i64_intFromFloat_f32;
const u64_intFromFloat_f32 = impl.u64_intFromFloat_f32;
const i128_intFromFloat_f32 = impl.i128_intFromFloat_f32;
const u128_intFromFloat_f32 = impl.u128_intFromFloat_f32;
const signed_intFromFloat_f32 = impl.signed_intFromFloat_f32;
const unsigned_intFromFloat_f32 = impl.unsigned_intFromFloat_f32;

const i32_intFromFloat_f64 = impl.i32_intFromFloat_f64;
const u32_intFromFloat_f64 = impl.u32_intFromFloat_f64;
const i64_intFromFloat_f64 = impl.i64_intFromFloat_f64;
const u64_intFromFloat_f64 = impl.u64_intFromFloat_f64;
const i128_intFromFloat_f64 = impl.i128_intFromFloat_f64;
const u128_intFromFloat_f64 = impl.u128_intFromFloat_f64;
const signed_intFromFloat_f64 = impl.signed_intFromFloat_f64;
const unsigned_intFromFloat_f64 = impl.unsigned_intFromFloat_f64;

const i32_intFromFloat_f80 = impl.i32_intFromFloat_f80;
const u32_intFromFloat_f80 = impl.u32_intFromFloat_f80;
const i64_intFromFloat_f80 = impl.i64_intFromFloat_f80;
const u64_intFromFloat_f80 = impl.u64_intFromFloat_f80;
const i128_intFromFloat_f80 = impl.i128_intFromFloat_f80;
const u128_intFromFloat_f80 = impl.u128_intFromFloat_f80;
const signed_intFromFloat_f80 = impl.signed_intFromFloat_f80;
const unsigned_intFromFloat_f80 = impl.unsigned_intFromFloat_f80;

const i32_intFromFloat_f128 = impl.i32_intFromFloat_f128;
const u32_intFromFloat_f128 = impl.u32_intFromFloat_f128;
const i64_intFromFloat_f128 = impl.i64_intFromFloat_f128;
const u64_intFromFloat_f128 = impl.u64_intFromFloat_f128;
const i128_intFromFloat_f128 = impl.i128_intFromFloat_f128;
const u128_intFromFloat_f128 = impl.u128_intFromFloat_f128;
const signed_intFromFloat_f128 = impl.signed_intFromFloat_f128;
const unsigned_intFromFloat_f128 = impl.unsigned_intFromFloat_f128;

fn test_i32_intFromFloat_f32(a: f32, expected: i32) !void {
    const x = i32_intFromFloat_f32(a);
    try testing.expect(x == expected);
}

fn test_u32_intFromFloat_f32(a: f32, expected: u32) !void {
    const x = u32_intFromFloat_f32(a);
    try testing.expect(x == expected);
}

test i32_intFromFloat_f32 {
    try test_i32_intFromFloat_f32(-math.floatMax(f32), math.minInt(i32));

    try test_i32_intFromFloat_f32(-0x1.FFFFFFFFFFFFFp+1023, math.minInt(i32));
    try test_i32_intFromFloat_f32(-0x1.FFFFFFFFFFFFFp+1023, -0x80000000);

    try test_i32_intFromFloat_f32(-0x1.0000000000000p+127, -0x80000000);
    try test_i32_intFromFloat_f32(-0x1.FFFFFFFFFFFFFp+126, -0x80000000);
    try test_i32_intFromFloat_f32(-0x1.FFFFFFFFFFFFEp+126, -0x80000000);

    try test_i32_intFromFloat_f32(-0x1.0000000000001p+63, -0x80000000);
    try test_i32_intFromFloat_f32(-0x1.0000000000000p+63, -0x80000000);
    try test_i32_intFromFloat_f32(-0x1.FFFFFFFFFFFFFp+62, -0x80000000);
    try test_i32_intFromFloat_f32(-0x1.FFFFFFFFFFFFEp+62, -0x80000000);

    try test_i32_intFromFloat_f32(-0x1.FFFFFEp+62, -0x80000000);
    try test_i32_intFromFloat_f32(-0x1.FFFFFCp+62, -0x80000000);

    try test_i32_intFromFloat_f32(-0x1.000000p+31, -0x80000000);
    try test_i32_intFromFloat_f32(-0x1.FFFFFFp+30, -0x80000000);
    try test_i32_intFromFloat_f32(-0x1.FFFFFEp+30, -0x7FFFFF80);
    try test_i32_intFromFloat_f32(-0x1.FFFFFCp+30, -0x7FFFFF00);

    try test_i32_intFromFloat_f32(-2.01, -2);
    try test_i32_intFromFloat_f32(-2.0, -2);
    try test_i32_intFromFloat_f32(-1.99, -1);
    try test_i32_intFromFloat_f32(-1.0, -1);
    try test_i32_intFromFloat_f32(-0.99, 0);
    try test_i32_intFromFloat_f32(-0.5, 0);

    try test_i32_intFromFloat_f32(-math.floatMin(f32), 0);
    try test_i32_intFromFloat_f32(0.0, 0);
    try test_i32_intFromFloat_f32(math.floatMin(f32), 0);
    try test_i32_intFromFloat_f32(0.5, 0);
    try test_i32_intFromFloat_f32(0.99, 0);
    try test_i32_intFromFloat_f32(1.0, 1);
    try test_i32_intFromFloat_f32(1.5, 1);
    try test_i32_intFromFloat_f32(1.99, 1);
    try test_i32_intFromFloat_f32(2.0, 2);
    try test_i32_intFromFloat_f32(2.01, 2);

    try test_i32_intFromFloat_f32(0x1.FFFFFCp+30, 0x7FFFFF00);
    try test_i32_intFromFloat_f32(0x1.FFFFFEp+30, 0x7FFFFF80);
    try test_i32_intFromFloat_f32(0x1.FFFFFFp+30, 0x7FFFFFFF);
    try test_i32_intFromFloat_f32(0x1.000000p+31, 0x7FFFFFFF);

    try test_i32_intFromFloat_f32(0x1.FFFFFCp+62, 0x7FFFFFFF);
    try test_i32_intFromFloat_f32(0x1.FFFFFEp+62, 0x7FFFFFFF);

    try test_i32_intFromFloat_f32(0x1.FFFFFFFFFFFFEp+62, 0x7FFFFFFF);
    try test_i32_intFromFloat_f32(0x1.FFFFFFFFFFFFFp+62, 0x7FFFFFFF);
    try test_i32_intFromFloat_f32(0x1.0000000000000p+63, 0x7FFFFFFF);
    try test_i32_intFromFloat_f32(0x1.0000000000001p+63, 0x7FFFFFFF);

    try test_i32_intFromFloat_f32(0x1.FFFFFFFFFFFFEp+126, 0x7FFFFFFF);
    try test_i32_intFromFloat_f32(0x1.FFFFFFFFFFFFFp+126, 0x7FFFFFFF);
    try test_i32_intFromFloat_f32(0x1.0000000000000p+127, 0x7FFFFFFF);

    try test_i32_intFromFloat_f32(0x1.FFFFFFFFFFFFFp+1023, 0x7FFFFFFF);
    try test_i32_intFromFloat_f32(0x1.FFFFFFFFFFFFFp+1023, math.maxInt(i32));

    try test_i32_intFromFloat_f32(math.floatMax(f32), math.maxInt(i32));
}

test u32_intFromFloat_f32 {
    try test_u32_intFromFloat_f32(0.0, 0);

    try test_u32_intFromFloat_f32(0.5, 0);
    try test_u32_intFromFloat_f32(0.99, 0);
    try test_u32_intFromFloat_f32(1.0, 1);
    try test_u32_intFromFloat_f32(1.5, 1);
    try test_u32_intFromFloat_f32(1.99, 1);
    try test_u32_intFromFloat_f32(2.0, 2);
    try test_u32_intFromFloat_f32(2.01, 2);
    try test_u32_intFromFloat_f32(-0.5, 0);
    try test_u32_intFromFloat_f32(-0.99, 0);

    try test_u32_intFromFloat_f32(-1.0, 0);
    try test_u32_intFromFloat_f32(-1.5, 0);
    try test_u32_intFromFloat_f32(-1.99, 0);
    try test_u32_intFromFloat_f32(-2.0, 0);
    try test_u32_intFromFloat_f32(-2.01, 0);

    try test_u32_intFromFloat_f32(0x1.000000p+31, 0x80000000);
    try test_u32_intFromFloat_f32(0x1.000000p+32, 0xFFFFFFFF);
    try test_u32_intFromFloat_f32(0x1.FFFFFEp+31, 0xFFFFFF00);
    try test_u32_intFromFloat_f32(0x1.FFFFFEp+30, 0x7FFFFF80);
    try test_u32_intFromFloat_f32(0x1.FFFFFCp+30, 0x7FFFFF00);

    try test_u32_intFromFloat_f32(-0x1.FFFFFEp+30, 0);
    try test_u32_intFromFloat_f32(-0x1.FFFFFCp+30, 0);
}

fn test_i64_intFromFloat_f32(a: f32, expected: i64) !void {
    const x = i64_intFromFloat_f32(a);
    try testing.expect(x == expected);
}

fn test_u64_intFromFloat_f32(a: f32, expected: u64) !void {
    const x = u64_intFromFloat_f32(a);
    try testing.expect(x == expected);
}

test i64_intFromFloat_f32 {
    try test_i64_intFromFloat_f32(-math.floatMax(f32), math.minInt(i64));

    try test_i64_intFromFloat_f32(-0x1.FFFFFFFFFFFFFp+1023, math.minInt(i64));
    try test_i64_intFromFloat_f32(-0x1.FFFFFFFFFFFFFp+1023, -0x8000000000000000);

    try test_i64_intFromFloat_f32(-0x1.0000000000000p+127, -0x8000000000000000);
    try test_i64_intFromFloat_f32(-0x1.FFFFFFFFFFFFFp+126, -0x8000000000000000);
    try test_i64_intFromFloat_f32(-0x1.FFFFFFFFFFFFEp+126, -0x8000000000000000);

    try test_i64_intFromFloat_f32(-0x1.0000000000001p+63, -0x8000000000000000);
    try test_i64_intFromFloat_f32(-0x1.0000000000000p+63, -0x8000000000000000);
    try test_i64_intFromFloat_f32(-0x1.FFFFFFFFFFFFFp+62, -0x8000000000000000);
    try test_i64_intFromFloat_f32(-0x1.FFFFFFFFFFFFEp+62, -0x8000000000000000);

    try test_i64_intFromFloat_f32(-0x1.FFFFFFp+62, -0x8000000000000000);
    try test_i64_intFromFloat_f32(-0x1.FFFFFEp+62, -0x7fffff8000000000);
    try test_i64_intFromFloat_f32(-0x1.FFFFFCp+62, -0x7fffff0000000000);

    try test_i64_intFromFloat_f32(-2.01, -2);
    try test_i64_intFromFloat_f32(-2.0, -2);
    try test_i64_intFromFloat_f32(-1.99, -1);
    try test_i64_intFromFloat_f32(-1.0, -1);
    try test_i64_intFromFloat_f32(-0.99, 0);
    try test_i64_intFromFloat_f32(-0.5, 0);
    try test_i64_intFromFloat_f32(-math.floatMin(f32), 0);
    try test_i64_intFromFloat_f32(0.0, 0);
    try test_i64_intFromFloat_f32(math.floatMin(f32), 0);
    try test_i64_intFromFloat_f32(0.5, 0);
    try test_i64_intFromFloat_f32(0.99, 0);
    try test_i64_intFromFloat_f32(1.0, 1);
    try test_i64_intFromFloat_f32(1.5, 1);
    try test_i64_intFromFloat_f32(1.99, 1);
    try test_i64_intFromFloat_f32(2.0, 2);
    try test_i64_intFromFloat_f32(2.01, 2);

    try test_i64_intFromFloat_f32(0x1.FFFFFCp+62, 0x7FFFFF0000000000);
    try test_i64_intFromFloat_f32(0x1.FFFFFEp+62, 0x7FFFFF8000000000);
    try test_i64_intFromFloat_f32(0x1.FFFFFFp+62, 0x7FFFFFFFFFFFFFFF);

    try test_i64_intFromFloat_f32(0x1.FFFFFFFFFFFFEp+62, 0x7FFFFFFFFFFFFFFF);
    try test_i64_intFromFloat_f32(0x1.FFFFFFFFFFFFFp+62, 0x7FFFFFFFFFFFFFFF);
    try test_i64_intFromFloat_f32(0x1.0000000000000p+63, 0x7FFFFFFFFFFFFFFF);
    try test_i64_intFromFloat_f32(0x1.0000000000001p+63, 0x7FFFFFFFFFFFFFFF);

    try test_i64_intFromFloat_f32(0x1.FFFFFFFFFFFFEp+126, 0x7FFFFFFFFFFFFFFF);
    try test_i64_intFromFloat_f32(0x1.FFFFFFFFFFFFFp+126, 0x7FFFFFFFFFFFFFFF);
    try test_i64_intFromFloat_f32(0x1.0000000000000p+127, 0x7FFFFFFFFFFFFFFF);

    try test_i64_intFromFloat_f32(0x1.FFFFFFFFFFFFFp+1023, 0x7FFFFFFFFFFFFFFF);
    try test_i64_intFromFloat_f32(0x1.FFFFFFFFFFFFFp+1023, math.maxInt(i64));

    try test_i64_intFromFloat_f32(math.floatMax(f32), math.maxInt(i64));
}

test u64_intFromFloat_f32 {
    try test_u64_intFromFloat_f32(0.0, 0);

    try test_u64_intFromFloat_f32(0.5, 0);
    try test_u64_intFromFloat_f32(0.99, 0);
    try test_u64_intFromFloat_f32(1.0, 1);
    try test_u64_intFromFloat_f32(1.5, 1);
    try test_u64_intFromFloat_f32(1.99, 1);
    try test_u64_intFromFloat_f32(2.0, 2);
    try test_u64_intFromFloat_f32(2.01, 2);
    try test_u64_intFromFloat_f32(-0.5, 0);
    try test_u64_intFromFloat_f32(-0.99, 0);

    try test_u64_intFromFloat_f32(-1.0, 0);
    try test_u64_intFromFloat_f32(-1.5, 0);
    try test_u64_intFromFloat_f32(-1.99, 0);
    try test_u64_intFromFloat_f32(-2.0, 0);
    try test_u64_intFromFloat_f32(-2.01, 0);

    try test_u64_intFromFloat_f32(0x1.FFFFFEp+63, 0xFFFFFF0000000000);
    try test_u64_intFromFloat_f32(0x1.000000p+63, 0x8000000000000000);
    try test_u64_intFromFloat_f32(0x1.FFFFFEp+62, 0x7FFFFF8000000000);
    try test_u64_intFromFloat_f32(0x1.FFFFFCp+62, 0x7FFFFF0000000000);

    try test_u64_intFromFloat_f32(-0x1.FFFFFEp+62, 0x0000000000000000);
    try test_u64_intFromFloat_f32(-0x1.FFFFFCp+62, 0x0000000000000000);
}

fn test_i128_intFromFloat_f32(a: f32, expected: i128) !void {
    const x = i128_intFromFloat_f32(a);
    try testing.expect(x == expected);
}

fn test_u128_intFromFloat_f32(a: f32, expected: u128) !void {
    const x = u128_intFromFloat_f32(a);
    try testing.expect(x == expected);
}

test i128_intFromFloat_f32 {
    try test_i128_intFromFloat_f32(-math.floatMax(f32), math.minInt(i128));

    try test_i128_intFromFloat_f32(-0x1.FFFFFFFFFFFFFp+1023, math.minInt(i128));
    try test_i128_intFromFloat_f32(-0x1.FFFFFFFFFFFFFp+1023, -0x80000000000000000000000000000000);

    try test_i128_intFromFloat_f32(-0x1.0000000000000p+127, -0x80000000000000000000000000000000);
    try test_i128_intFromFloat_f32(-0x1.FFFFFFFFFFFFFp+126, -0x80000000000000000000000000000000);
    try test_i128_intFromFloat_f32(-0x1.FFFFFFFFFFFFEp+126, -0x80000000000000000000000000000000);
    try test_i128_intFromFloat_f32(-0x1.FFFFFF0000000p+126, -0x80000000000000000000000000000000);
    try test_i128_intFromFloat_f32(-0x1.FFFFFE0000000p+126, -0x7FFFFF80000000000000000000000000);
    try test_i128_intFromFloat_f32(-0x1.FFFFFC0000000p+126, -0x7FFFFF00000000000000000000000000);

    try test_i128_intFromFloat_f32(-0x1.0000000000001p+63, -0x8000000000000000);
    try test_i128_intFromFloat_f32(-0x1.0000000000000p+63, -0x8000000000000000);
    try test_i128_intFromFloat_f32(-0x1.FFFFFFFFFFFFFp+62, -0x8000000000000000);
    try test_i128_intFromFloat_f32(-0x1.FFFFFFFFFFFFEp+62, -0x8000000000000000);

    try test_i128_intFromFloat_f32(-0x1.FFFFFFp+62, -0x8000000000000000);
    try test_i128_intFromFloat_f32(-0x1.FFFFFEp+62, -0x7fffff8000000000);
    try test_i128_intFromFloat_f32(-0x1.FFFFFCp+62, -0x7fffff0000000000);

    try test_i128_intFromFloat_f32(-0x1.000000p+31, -0x80000000);
    try test_i128_intFromFloat_f32(-0x1.FFFFFFp+30, -0x80000000);
    try test_i128_intFromFloat_f32(-0x1.FFFFFEp+30, -0x7FFFFF80);
    try test_i128_intFromFloat_f32(-0x1.FFFFFCp+30, -0x7FFFFF00);

    try test_i128_intFromFloat_f32(-2.01, -2);
    try test_i128_intFromFloat_f32(-2.0, -2);
    try test_i128_intFromFloat_f32(-1.99, -1);
    try test_i128_intFromFloat_f32(-1.0, -1);
    try test_i128_intFromFloat_f32(-0.99, 0);
    try test_i128_intFromFloat_f32(-0.5, 0);
    try test_i128_intFromFloat_f32(-math.floatMin(f32), 0);
    try test_i128_intFromFloat_f32(0.0, 0);
    try test_i128_intFromFloat_f32(math.floatMin(f32), 0);
    try test_i128_intFromFloat_f32(0.5, 0);
    try test_i128_intFromFloat_f32(0.99, 0);
    try test_i128_intFromFloat_f32(1.0, 1);
    try test_i128_intFromFloat_f32(1.5, 1);
    try test_i128_intFromFloat_f32(1.99, 1);
    try test_i128_intFromFloat_f32(2.0, 2);
    try test_i128_intFromFloat_f32(2.01, 2);

    try test_i128_intFromFloat_f32(0x1.FFFFFCp+30, 0x7FFFFF00);
    try test_i128_intFromFloat_f32(0x1.FFFFFEp+30, 0x7FFFFF80);
    try test_i128_intFromFloat_f32(0x1.FFFFFFp+30, 0x80000000);
    try test_i128_intFromFloat_f32(0x1.000000p+31, 0x80000000);

    try test_i128_intFromFloat_f32(0x1.FFFFFCp+62, 0x7FFFFF0000000000);
    try test_i128_intFromFloat_f32(0x1.FFFFFEp+62, 0x7FFFFF8000000000);
    try test_i128_intFromFloat_f32(0x1.FFFFFFp+62, 0x8000000000000000);

    try test_i128_intFromFloat_f32(0x1.FFFFFFFFFFFFEp+62, 0x8000000000000000);
    try test_i128_intFromFloat_f32(0x1.FFFFFFFFFFFFFp+62, 0x8000000000000000);
    try test_i128_intFromFloat_f32(0x1.0000000000000p+63, 0x8000000000000000);
    try test_i128_intFromFloat_f32(0x1.0000000000001p+63, 0x8000000000000000);

    try test_i128_intFromFloat_f32(0x1.FFFFFC0000000p+126, 0x7FFFFF00000000000000000000000000);
    try test_i128_intFromFloat_f32(0x1.FFFFFE0000000p+126, 0x7FFFFF80000000000000000000000000);
    try test_i128_intFromFloat_f32(0x1.FFFFFF0000000p+126, 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
    try test_i128_intFromFloat_f32(0x1.FFFFFFFFFFFFEp+126, 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
    try test_i128_intFromFloat_f32(0x1.FFFFFFFFFFFFFp+126, 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
    try test_i128_intFromFloat_f32(0x1.0000000000000p+127, 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);

    try test_i128_intFromFloat_f32(0x1.FFFFFFFFFFFFFp+1023, 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
    try test_i128_intFromFloat_f32(0x1.FFFFFFFFFFFFFp+1023, math.maxInt(i128));

    try test_i128_intFromFloat_f32(math.floatMax(f32), math.maxInt(i128));
}

test u128_intFromFloat_f32 {
    try test_u128_intFromFloat_f32(0.0, 0);

    try test_u128_intFromFloat_f32(0.5, 0);
    try test_u128_intFromFloat_f32(0.99, 0);
    try test_u128_intFromFloat_f32(1.0, 1);
    try test_u128_intFromFloat_f32(1.5, 1);
    try test_u128_intFromFloat_f32(1.99, 1);
    try test_u128_intFromFloat_f32(2.0, 2);
    try test_u128_intFromFloat_f32(2.01, 2);
    try test_u128_intFromFloat_f32(-0.5, 0);
    try test_u128_intFromFloat_f32(-0.99, 0);

    try test_u128_intFromFloat_f32(-1.0, 0);
    try test_u128_intFromFloat_f32(-1.5, 0);
    try test_u128_intFromFloat_f32(-1.99, 0);
    try test_u128_intFromFloat_f32(-2.0, 0);
    try test_u128_intFromFloat_f32(-2.01, 0);

    try test_u128_intFromFloat_f32(0x1.FFFFFEp+63, 0xFFFFFF0000000000);
    try test_u128_intFromFloat_f32(0x1.000000p+63, 0x8000000000000000);
    try test_u128_intFromFloat_f32(0x1.FFFFFEp+62, 0x7FFFFF8000000000);
    try test_u128_intFromFloat_f32(0x1.FFFFFCp+62, 0x7FFFFF0000000000);
    try test_u128_intFromFloat_f32(0x1.FFFFFEp+127, 0xFFFFFF00000000000000000000000000);
    try test_u128_intFromFloat_f32(0x1.000000p+127, 0x80000000000000000000000000000000);
    try test_u128_intFromFloat_f32(0x1.FFFFFEp+126, 0x7FFFFF80000000000000000000000000);
    try test_u128_intFromFloat_f32(0x1.FFFFFCp+126, 0x7FFFFF00000000000000000000000000);

    try test_u128_intFromFloat_f32(-0x1.FFFFFEp+62, 0x0000000000000000);
    try test_u128_intFromFloat_f32(-0x1.FFFFFCp+62, 0x0000000000000000);
    try test_u128_intFromFloat_f32(-0x1.FFFFFEp+126, 0x0000000000000000);
    try test_u128_intFromFloat_f32(-0x1.FFFFFCp+126, 0x0000000000000000);
    try test_u128_intFromFloat_f32(math.floatMax(f32), 0xffffff00000000000000000000000000);
    try test_u128_intFromFloat_f32(math.inf(f32), math.maxInt(u128));
}

fn test_intFromFloat_f32(comptime T: type, expected: T, a: f32) !void {
    const int = @typeInfo(T).int;
    var actual: T = undefined;
    _ = switch (int.signedness) {
        .signed => signed_intFromFloat_f32,
        .unsigned => unsigned_intFromFloat_f32,
    }(@ptrCast(&actual), a);
    try testing.expect(expected == actual);
}

test signed_intFromFloat_f32 {
    try test_intFromFloat_f32(i256, -1 << 127, -0x1p127);
    try test_intFromFloat_f32(i256, -1 << 100, -0x1p100);
    try test_intFromFloat_f32(i256, -1 << 50, -0x1p50);
    try test_intFromFloat_f32(i256, -1 << 1, -0x1p1);
    try test_intFromFloat_f32(i256, -1 << 0, -0x1p0);
    try test_intFromFloat_f32(i256, 0, 0);
    try test_intFromFloat_f32(i256, 1 << 0, 0x1p0);
    try test_intFromFloat_f32(i256, 1 << 1, 0x1p1);
    try test_intFromFloat_f32(i256, 1 << 50, 0x1p50);
    try test_intFromFloat_f32(i256, 1 << 100, 0x1p100);
    try test_intFromFloat_f32(i256, 1 << 127, 0x1p127);
}

test unsigned_intFromFloat_f32 {
    try test_intFromFloat_f32(u256, 0, 0);
    try test_intFromFloat_f32(u256, 1 << 0, 0x1p0);
    try test_intFromFloat_f32(u256, 1 << 1, 0x1p1);
    try test_intFromFloat_f32(u256, 1 << 50, 0x1p50);
    try test_intFromFloat_f32(u256, 1 << 100, 0x1p100);
    try test_intFromFloat_f32(u256, 1 << 127, 0x1p127);
}

fn test_i32_intFromFloat_f64(a: f64, expected: i32) !void {
    const x = i32_intFromFloat_f64(a);
    try testing.expect(x == expected);
}

fn test_u32_intFromFloat_f64(a: f64, expected: u32) !void {
    const x = u32_intFromFloat_f64(a);
    try testing.expect(x == expected);
}

test i32_intFromFloat_f64 {
    try test_i32_intFromFloat_f64(-math.floatMax(f64), math.minInt(i32));

    try test_i32_intFromFloat_f64(-0x1.FFFFFFFFFFFFFp+1023, math.minInt(i32));
    try test_i32_intFromFloat_f64(-0x1.FFFFFFFFFFFFFp+1023, -0x80000000);

    try test_i32_intFromFloat_f64(-0x1.0000000000000p+127, -0x80000000);
    try test_i32_intFromFloat_f64(-0x1.FFFFFFFFFFFFFp+126, -0x80000000);
    try test_i32_intFromFloat_f64(-0x1.FFFFFFFFFFFFEp+126, -0x80000000);

    try test_i32_intFromFloat_f64(-0x1.0000000000001p+63, -0x80000000);
    try test_i32_intFromFloat_f64(-0x1.0000000000000p+63, -0x80000000);
    try test_i32_intFromFloat_f64(-0x1.FFFFFFFFFFFFFp+62, -0x80000000);
    try test_i32_intFromFloat_f64(-0x1.FFFFFFFFFFFFEp+62, -0x80000000);

    try test_i32_intFromFloat_f64(-0x1.FFFFFEp+62, -0x80000000);
    try test_i32_intFromFloat_f64(-0x1.FFFFFCp+62, -0x80000000);

    try test_i32_intFromFloat_f64(-0x1.000000p+31, -0x80000000);
    try test_i32_intFromFloat_f64(-0x1.FFFFFFp+30, -0x7FFFFFC0);
    try test_i32_intFromFloat_f64(-0x1.FFFFFEp+30, -0x7FFFFF80);

    try test_i32_intFromFloat_f64(-2.01, -2);
    try test_i32_intFromFloat_f64(-2.0, -2);
    try test_i32_intFromFloat_f64(-1.99, -1);
    try test_i32_intFromFloat_f64(-1.0, -1);
    try test_i32_intFromFloat_f64(-0.99, 0);
    try test_i32_intFromFloat_f64(-0.5, 0);
    try test_i32_intFromFloat_f64(-math.floatMin(f64), 0);
    try test_i32_intFromFloat_f64(0.0, 0);
    try test_i32_intFromFloat_f64(math.floatMin(f64), 0);
    try test_i32_intFromFloat_f64(0.5, 0);
    try test_i32_intFromFloat_f64(0.99, 0);
    try test_i32_intFromFloat_f64(1.0, 1);
    try test_i32_intFromFloat_f64(1.5, 1);
    try test_i32_intFromFloat_f64(1.99, 1);
    try test_i32_intFromFloat_f64(2.0, 2);
    try test_i32_intFromFloat_f64(2.01, 2);

    try test_i32_intFromFloat_f64(0x1.FFFFFEp+30, 0x7FFFFF80);
    try test_i32_intFromFloat_f64(0x1.FFFFFFp+30, 0x7FFFFFC0);
    try test_i32_intFromFloat_f64(0x1.000000p+31, 0x7FFFFFFF);

    try test_i32_intFromFloat_f64(0x1.FFFFFCp+62, 0x7FFFFFFF);
    try test_i32_intFromFloat_f64(0x1.FFFFFEp+62, 0x7FFFFFFF);

    try test_i32_intFromFloat_f64(0x1.FFFFFFFFFFFFEp+62, 0x7FFFFFFF);
    try test_i32_intFromFloat_f64(0x1.FFFFFFFFFFFFFp+62, 0x7FFFFFFF);
    try test_i32_intFromFloat_f64(0x1.0000000000000p+63, 0x7FFFFFFF);
    try test_i32_intFromFloat_f64(0x1.0000000000001p+63, 0x7FFFFFFF);

    try test_i32_intFromFloat_f64(0x1.FFFFFFFFFFFFEp+126, 0x7FFFFFFF);
    try test_i32_intFromFloat_f64(0x1.FFFFFFFFFFFFFp+126, 0x7FFFFFFF);
    try test_i32_intFromFloat_f64(0x1.0000000000000p+127, 0x7FFFFFFF);

    try test_i32_intFromFloat_f64(0x1.FFFFFFFFFFFFFp+1023, 0x7FFFFFFF);
    try test_i32_intFromFloat_f64(0x1.FFFFFFFFFFFFFp+1023, math.maxInt(i32));

    try test_i32_intFromFloat_f64(math.floatMax(f64), math.maxInt(i32));
}

test u32_intFromFloat_f64 {
    try test_u32_intFromFloat_f64(0.0, 0);

    try test_u32_intFromFloat_f64(0.5, 0);
    try test_u32_intFromFloat_f64(0.99, 0);
    try test_u32_intFromFloat_f64(1.0, 1);
    try test_u32_intFromFloat_f64(1.5, 1);
    try test_u32_intFromFloat_f64(1.99, 1);
    try test_u32_intFromFloat_f64(2.0, 2);
    try test_u32_intFromFloat_f64(2.01, 2);
    try test_u32_intFromFloat_f64(-0.5, 0);
    try test_u32_intFromFloat_f64(-0.99, 0);
    try test_u32_intFromFloat_f64(-1.0, 0);
    try test_u32_intFromFloat_f64(-1.5, 0);
    try test_u32_intFromFloat_f64(-1.99, 0);
    try test_u32_intFromFloat_f64(-2.0, 0);
    try test_u32_intFromFloat_f64(-2.01, 0);

    try test_u32_intFromFloat_f64(0x1.000000p+31, 0x80000000);
    try test_u32_intFromFloat_f64(0x1.000000p+32, 0xFFFFFFFF);
    try test_u32_intFromFloat_f64(0x1.FFFFFEp+31, 0xFFFFFF00);
    try test_u32_intFromFloat_f64(0x1.FFFFFEp+30, 0x7FFFFF80);
    try test_u32_intFromFloat_f64(0x1.FFFFFCp+30, 0x7FFFFF00);

    try test_u32_intFromFloat_f64(-0x1.FFFFFEp+30, 0);
    try test_u32_intFromFloat_f64(-0x1.FFFFFCp+30, 0);

    try test_u32_intFromFloat_f64(0x1.FFFFFFFEp+31, 0xFFFFFFFF);
    try test_u32_intFromFloat_f64(0x1.FFFFFFFC00000p+30, 0x7FFFFFFF);
    try test_u32_intFromFloat_f64(0x1.FFFFFFF800000p+30, 0x7FFFFFFE);
}

fn test_i64_intFromFloat_f64(a: f64, expected: i64) !void {
    const x = i64_intFromFloat_f64(a);
    try testing.expect(x == expected);
}

fn test_u64_intFromFloat_f64(a: f64, expected: u64) !void {
    const x = u64_intFromFloat_f64(a);
    try testing.expect(x == expected);
}

test i64_intFromFloat_f64 {
    try test_i64_intFromFloat_f64(-math.floatMax(f64), math.minInt(i64));

    try test_i64_intFromFloat_f64(-0x1.FFFFFFFFFFFFFp+1023, math.minInt(i64));
    try test_i64_intFromFloat_f64(-0x1.FFFFFFFFFFFFFp+1023, -0x8000000000000000);

    try test_i64_intFromFloat_f64(-0x1.0000000000000p+127, -0x8000000000000000);
    try test_i64_intFromFloat_f64(-0x1.FFFFFFFFFFFFFp+126, -0x8000000000000000);
    try test_i64_intFromFloat_f64(-0x1.FFFFFFFFFFFFEp+126, -0x8000000000000000);

    try test_i64_intFromFloat_f64(-0x1.0000000000001p+63, -0x8000000000000000);
    try test_i64_intFromFloat_f64(-0x1.0000000000000p+63, -0x8000000000000000);
    try test_i64_intFromFloat_f64(-0x1.FFFFFFFFFFFFFp+62, -0x7FFFFFFFFFFFFC00);
    try test_i64_intFromFloat_f64(-0x1.FFFFFFFFFFFFEp+62, -0x7FFFFFFFFFFFF800);

    try test_i64_intFromFloat_f64(-0x1.FFFFFEp+62, -0x7fffff8000000000);
    try test_i64_intFromFloat_f64(-0x1.FFFFFCp+62, -0x7fffff0000000000);

    try test_i64_intFromFloat_f64(-2.01, -2);
    try test_i64_intFromFloat_f64(-2.0, -2);
    try test_i64_intFromFloat_f64(-1.99, -1);
    try test_i64_intFromFloat_f64(-1.0, -1);
    try test_i64_intFromFloat_f64(-0.99, 0);
    try test_i64_intFromFloat_f64(-0.5, 0);
    try test_i64_intFromFloat_f64(-math.floatMin(f64), 0);
    try test_i64_intFromFloat_f64(0.0, 0);
    try test_i64_intFromFloat_f64(math.floatMin(f64), 0);
    try test_i64_intFromFloat_f64(0.5, 0);
    try test_i64_intFromFloat_f64(0.99, 0);
    try test_i64_intFromFloat_f64(1.0, 1);
    try test_i64_intFromFloat_f64(1.5, 1);
    try test_i64_intFromFloat_f64(1.99, 1);
    try test_i64_intFromFloat_f64(2.0, 2);
    try test_i64_intFromFloat_f64(2.01, 2);

    try test_i64_intFromFloat_f64(0x1.FFFFFCp+62, 0x7FFFFF0000000000);
    try test_i64_intFromFloat_f64(0x1.FFFFFEp+62, 0x7FFFFF8000000000);

    try test_i64_intFromFloat_f64(0x1.FFFFFFFFFFFFEp+62, 0x7FFFFFFFFFFFF800);
    try test_i64_intFromFloat_f64(0x1.FFFFFFFFFFFFFp+62, 0x7FFFFFFFFFFFFC00);
    try test_i64_intFromFloat_f64(0x1.0000000000000p+63, 0x7FFFFFFFFFFFFFFF);
    try test_i64_intFromFloat_f64(0x1.0000000000001p+63, 0x7FFFFFFFFFFFFFFF);

    try test_i64_intFromFloat_f64(0x1.FFFFFFFFFFFFEp+126, 0x7FFFFFFFFFFFFFFF);
    try test_i64_intFromFloat_f64(0x1.FFFFFFFFFFFFFp+126, 0x7FFFFFFFFFFFFFFF);
    try test_i64_intFromFloat_f64(0x1.0000000000000p+127, 0x7FFFFFFFFFFFFFFF);

    try test_i64_intFromFloat_f64(0x1.FFFFFFFFFFFFFp+1023, 0x7FFFFFFFFFFFFFFF);
    try test_i64_intFromFloat_f64(0x1.FFFFFFFFFFFFFp+1023, math.maxInt(i64));

    try test_i64_intFromFloat_f64(math.floatMax(f64), math.maxInt(i64));
}

test u64_intFromFloat_f64 {
    try test_u64_intFromFloat_f64(0.0, 0);
    try test_u64_intFromFloat_f64(0.5, 0);
    try test_u64_intFromFloat_f64(0.99, 0);
    try test_u64_intFromFloat_f64(1.0, 1);
    try test_u64_intFromFloat_f64(1.5, 1);
    try test_u64_intFromFloat_f64(1.99, 1);
    try test_u64_intFromFloat_f64(2.0, 2);
    try test_u64_intFromFloat_f64(2.01, 2);
    try test_u64_intFromFloat_f64(-0.5, 0);
    try test_u64_intFromFloat_f64(-0.99, 0);
    try test_u64_intFromFloat_f64(-1.0, 0);
    try test_u64_intFromFloat_f64(-1.5, 0);
    try test_u64_intFromFloat_f64(-1.99, 0);
    try test_u64_intFromFloat_f64(-2.0, 0);
    try test_u64_intFromFloat_f64(-2.01, 0);

    try test_u64_intFromFloat_f64(0x1.FFFFFEp+62, 0x7FFFFF8000000000);
    try test_u64_intFromFloat_f64(0x1.FFFFFCp+62, 0x7FFFFF0000000000);

    try test_u64_intFromFloat_f64(-0x1.FFFFFEp+62, 0);
    try test_u64_intFromFloat_f64(-0x1.FFFFFCp+62, 0);

    try test_u64_intFromFloat_f64(0x1.FFFFFFFFFFFFFp+63, 0xFFFFFFFFFFFFF800);
    try test_u64_intFromFloat_f64(0x1.0000000000000p+63, 0x8000000000000000);
    try test_u64_intFromFloat_f64(0x1.FFFFFFFFFFFFFp+62, 0x7FFFFFFFFFFFFC00);
    try test_u64_intFromFloat_f64(0x1.FFFFFFFFFFFFEp+62, 0x7FFFFFFFFFFFF800);

    try test_u64_intFromFloat_f64(-0x1.FFFFFFFFFFFFFp+62, 0);
    try test_u64_intFromFloat_f64(-0x1.FFFFFFFFFFFFEp+62, 0);
}

fn test_i128_intFromFloat_f64(a: f64, expected: i128) !void {
    const x = i128_intFromFloat_f64(a);
    try testing.expect(x == expected);
}

fn test_u128_intFromFloat_f64(a: f64, expected: u128) !void {
    const x = u128_intFromFloat_f64(a);
    try testing.expect(x == expected);
}

test i128_intFromFloat_f64 {
    try test_i128_intFromFloat_f64(-math.floatMax(f64), math.minInt(i128));

    try test_i128_intFromFloat_f64(-0x1.FFFFFFFFFFFFFp+1023, math.minInt(i128));
    try test_i128_intFromFloat_f64(-0x1.FFFFFFFFFFFFFp+1023, -0x80000000000000000000000000000000);

    try test_i128_intFromFloat_f64(-0x1.0000000000000p+127, -0x80000000000000000000000000000000);
    try test_i128_intFromFloat_f64(-0x1.FFFFFFFFFFFFFp+126, -0x7FFFFFFFFFFFFC000000000000000000);
    try test_i128_intFromFloat_f64(-0x1.FFFFFFFFFFFFEp+126, -0x7FFFFFFFFFFFF8000000000000000000);

    try test_i128_intFromFloat_f64(-0x1.0000000000001p+63, -0x8000000000000800);
    try test_i128_intFromFloat_f64(-0x1.0000000000000p+63, -0x8000000000000000);
    try test_i128_intFromFloat_f64(-0x1.FFFFFFFFFFFFFp+62, -0x7FFFFFFFFFFFFC00);
    try test_i128_intFromFloat_f64(-0x1.FFFFFFFFFFFFEp+62, -0x7FFFFFFFFFFFF800);

    try test_i128_intFromFloat_f64(-0x1.FFFFFEp+62, -0x7fffff8000000000);
    try test_i128_intFromFloat_f64(-0x1.FFFFFCp+62, -0x7fffff0000000000);

    try test_i128_intFromFloat_f64(-2.01, -2);
    try test_i128_intFromFloat_f64(-2.0, -2);
    try test_i128_intFromFloat_f64(-1.99, -1);
    try test_i128_intFromFloat_f64(-1.0, -1);
    try test_i128_intFromFloat_f64(-0.99, 0);
    try test_i128_intFromFloat_f64(-0.5, 0);
    try test_i128_intFromFloat_f64(-math.floatMin(f64), 0);
    try test_i128_intFromFloat_f64(0.0, 0);
    try test_i128_intFromFloat_f64(math.floatMin(f64), 0);
    try test_i128_intFromFloat_f64(0.5, 0);
    try test_i128_intFromFloat_f64(0.99, 0);
    try test_i128_intFromFloat_f64(1.0, 1);
    try test_i128_intFromFloat_f64(1.5, 1);
    try test_i128_intFromFloat_f64(1.99, 1);
    try test_i128_intFromFloat_f64(2.0, 2);
    try test_i128_intFromFloat_f64(2.01, 2);

    try test_i128_intFromFloat_f64(0x1.FFFFFCp+62, 0x7FFFFF0000000000);
    try test_i128_intFromFloat_f64(0x1.FFFFFEp+62, 0x7FFFFF8000000000);

    try test_i128_intFromFloat_f64(0x1.FFFFFFFFFFFFEp+62, 0x7FFFFFFFFFFFF800);
    try test_i128_intFromFloat_f64(0x1.FFFFFFFFFFFFFp+62, 0x7FFFFFFFFFFFFC00);
    try test_i128_intFromFloat_f64(0x1.0000000000000p+63, 0x8000000000000000);
    try test_i128_intFromFloat_f64(0x1.0000000000001p+63, 0x8000000000000800);

    try test_i128_intFromFloat_f64(0x1.FFFFFFFFFFFFEp+126, 0x7FFFFFFFFFFFF8000000000000000000);
    try test_i128_intFromFloat_f64(0x1.FFFFFFFFFFFFFp+126, 0x7FFFFFFFFFFFFC000000000000000000);
    try test_i128_intFromFloat_f64(0x1.0000000000000p+127, 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);

    try test_i128_intFromFloat_f64(0x1.FFFFFFFFFFFFFp+1023, 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
    try test_i128_intFromFloat_f64(0x1.FFFFFFFFFFFFFp+1023, math.maxInt(i128));

    try test_i128_intFromFloat_f64(math.floatMax(f64), math.maxInt(i128));
}

test u128_intFromFloat_f64 {
    try test_u128_intFromFloat_f64(0.0, 0);

    try test_u128_intFromFloat_f64(0.5, 0);
    try test_u128_intFromFloat_f64(0.99, 0);
    try test_u128_intFromFloat_f64(1.0, 1);
    try test_u128_intFromFloat_f64(1.5, 1);
    try test_u128_intFromFloat_f64(1.99, 1);
    try test_u128_intFromFloat_f64(2.0, 2);
    try test_u128_intFromFloat_f64(2.01, 2);
    try test_u128_intFromFloat_f64(-0.5, 0);
    try test_u128_intFromFloat_f64(-0.99, 0);
    try test_u128_intFromFloat_f64(-1.0, 0);
    try test_u128_intFromFloat_f64(-1.5, 0);
    try test_u128_intFromFloat_f64(-1.99, 0);
    try test_u128_intFromFloat_f64(-2.0, 0);
    try test_u128_intFromFloat_f64(-2.01, 0);

    try test_u128_intFromFloat_f64(0x1.FFFFFEp+62, 0x7FFFFF8000000000);
    try test_u128_intFromFloat_f64(0x1.FFFFFCp+62, 0x7FFFFF0000000000);

    try test_u128_intFromFloat_f64(-0x1.FFFFFEp+62, 0);
    try test_u128_intFromFloat_f64(-0x1.FFFFFCp+62, 0);

    try test_u128_intFromFloat_f64(0x1.FFFFFFFFFFFFFp+63, 0xFFFFFFFFFFFFF800);
    try test_u128_intFromFloat_f64(0x1.0000000000000p+63, 0x8000000000000000);
    try test_u128_intFromFloat_f64(0x1.FFFFFFFFFFFFFp+62, 0x7FFFFFFFFFFFFC00);
    try test_u128_intFromFloat_f64(0x1.FFFFFFFFFFFFEp+62, 0x7FFFFFFFFFFFF800);

    try test_u128_intFromFloat_f64(0x1.FFFFFFFFFFFFFp+127, 0xFFFFFFFFFFFFF8000000000000000000);
    try test_u128_intFromFloat_f64(0x1.0000000000000p+127, 0x80000000000000000000000000000000);
    try test_u128_intFromFloat_f64(0x1.FFFFFFFFFFFFFp+126, 0x7FFFFFFFFFFFFC000000000000000000);
    try test_u128_intFromFloat_f64(0x1.FFFFFFFFFFFFEp+126, 0x7FFFFFFFFFFFF8000000000000000000);
    try test_u128_intFromFloat_f64(0x1.0000000000000p+128, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);

    try test_u128_intFromFloat_f64(-0x1.FFFFFFFFFFFFFp+62, 0);
    try test_u128_intFromFloat_f64(-0x1.FFFFFFFFFFFFEp+62, 0);
}

fn test_intFromFloat_f64(comptime T: type, expected: T, a: f64) !void {
    const int = @typeInfo(T).int;
    var actual: T = undefined;
    _ = switch (int.signedness) {
        .signed => signed_intFromFloat_f64,
        .unsigned => unsigned_intFromFloat_f64,
    }(@ptrCast(&actual), a);
    try testing.expect(expected == actual);
}

test signed_intFromFloat_f64 {
    try test_intFromFloat_f64(i256, -1 << 255, -0x1p255);
    try test_intFromFloat_f64(i256, -1 << 127, -0x1p127);
    try test_intFromFloat_f64(i256, -1 << 100, -0x1p100);
    try test_intFromFloat_f64(i256, -1 << 50, -0x1p50);
    try test_intFromFloat_f64(i256, -1 << 1, -0x1p1);
    try test_intFromFloat_f64(i256, -1 << 0, -0x1p0);
    try test_intFromFloat_f64(i256, 0, 0);
    try test_intFromFloat_f64(i256, 1 << 0, 0x1p0);
    try test_intFromFloat_f64(i256, 1 << 1, 0x1p1);
    try test_intFromFloat_f64(i256, 1 << 50, 0x1p50);
    try test_intFromFloat_f64(i256, 1 << 100, 0x1p100);
    try test_intFromFloat_f64(i256, 1 << 127, 0x1p127);
    try test_intFromFloat_f64(i256, 1 << 254, 0x1p254);
}

test unsigned_intFromFloat_f64 {
    try test_intFromFloat_f64(u256, 0, 0);
    try test_intFromFloat_f64(u256, 1 << 0, 0x1p0);
    try test_intFromFloat_f64(u256, 1 << 1, 0x1p1);
    try test_intFromFloat_f64(u256, 1 << 50, 0x1p50);
    try test_intFromFloat_f64(u256, 1 << 100, 0x1p100);
    try test_intFromFloat_f64(u256, 1 << 127, 0x1p127);
    try test_intFromFloat_f64(u256, 1 << 255, 0x1p255);
}

fn test_i32_intFromFloat_f128(a: f128, expected: i32) !void {
    const x = i32_intFromFloat_f128(a);
    try testing.expect(x == expected);
}

fn test_u32_intFromFloat_f128(a: f128, expected: u32) !void {
    const x = u32_intFromFloat_f128(a);
    try testing.expect(x == expected);
}

test i32_intFromFloat_f128 {
    try test_i32_intFromFloat_f128(-math.floatMax(f128), math.minInt(i32));

    try test_i32_intFromFloat_f128(-0x1.FFFFFFFFFFFFFp+1023, math.minInt(i32));
    try test_i32_intFromFloat_f128(-0x1.FFFFFFFFFFFFFp+1023, -0x80000000);

    try test_i32_intFromFloat_f128(-0x1.0000000000000p+127, -0x80000000);
    try test_i32_intFromFloat_f128(-0x1.FFFFFFFFFFFFFp+126, -0x80000000);
    try test_i32_intFromFloat_f128(-0x1.FFFFFFFFFFFFEp+126, -0x80000000);

    try test_i32_intFromFloat_f128(-0x1.0000000000001p+63, -0x80000000);
    try test_i32_intFromFloat_f128(-0x1.0000000000000p+63, -0x80000000);
    try test_i32_intFromFloat_f128(-0x1.FFFFFFFFFFFFFp+62, -0x80000000);
    try test_i32_intFromFloat_f128(-0x1.FFFFFFFFFFFFEp+62, -0x80000000);

    try test_i32_intFromFloat_f128(-0x1.FFFFFEp+62, -0x80000000);
    try test_i32_intFromFloat_f128(-0x1.FFFFFCp+62, -0x80000000);

    try test_i32_intFromFloat_f128(-0x1.000000p+31, -0x80000000);
    try test_i32_intFromFloat_f128(-0x1.FFFFFFp+30, -0x7FFFFFC0);
    try test_i32_intFromFloat_f128(-0x1.FFFFFEp+30, -0x7FFFFF80);
    try test_i32_intFromFloat_f128(-0x1.FFFFFCp+30, -0x7FFFFF00);

    try test_i32_intFromFloat_f128(-2.01, -2);
    try test_i32_intFromFloat_f128(-2.0, -2);
    try test_i32_intFromFloat_f128(-1.99, -1);
    try test_i32_intFromFloat_f128(-1.0, -1);
    try test_i32_intFromFloat_f128(-0.99, 0);
    try test_i32_intFromFloat_f128(-0.5, 0);
    try test_i32_intFromFloat_f128(-math.floatMin(f32), 0);
    try test_i32_intFromFloat_f128(0.0, 0);
    try test_i32_intFromFloat_f128(math.floatMin(f32), 0);
    try test_i32_intFromFloat_f128(0.5, 0);
    try test_i32_intFromFloat_f128(0.99, 0);
    try test_i32_intFromFloat_f128(1.0, 1);
    try test_i32_intFromFloat_f128(1.5, 1);
    try test_i32_intFromFloat_f128(1.99, 1);
    try test_i32_intFromFloat_f128(2.0, 2);
    try test_i32_intFromFloat_f128(2.01, 2);

    try test_i32_intFromFloat_f128(0x1.FFFFFCp+30, 0x7FFFFF00);
    try test_i32_intFromFloat_f128(0x1.FFFFFEp+30, 0x7FFFFF80);
    try test_i32_intFromFloat_f128(0x1.FFFFFFp+30, 0x7FFFFFC0);
    try test_i32_intFromFloat_f128(0x1.000000p+31, 0x7FFFFFFF);

    try test_i32_intFromFloat_f128(0x1.FFFFFCp+62, 0x7FFFFFFF);
    try test_i32_intFromFloat_f128(0x1.FFFFFEp+62, 0x7FFFFFFF);

    try test_i32_intFromFloat_f128(0x1.FFFFFFFFFFFFEp+62, 0x7FFFFFFF);
    try test_i32_intFromFloat_f128(0x1.FFFFFFFFFFFFFp+62, 0x7FFFFFFF);
    try test_i32_intFromFloat_f128(0x1.0000000000000p+63, 0x7FFFFFFF);
    try test_i32_intFromFloat_f128(0x1.0000000000001p+63, 0x7FFFFFFF);

    try test_i32_intFromFloat_f128(0x1.FFFFFFFFFFFFEp+126, 0x7FFFFFFF);
    try test_i32_intFromFloat_f128(0x1.FFFFFFFFFFFFFp+126, 0x7FFFFFFF);
    try test_i32_intFromFloat_f128(0x1.0000000000000p+127, 0x7FFFFFFF);

    try test_i32_intFromFloat_f128(0x1.FFFFFFFFFFFFFp+1023, 0x7FFFFFFF);
    try test_i32_intFromFloat_f128(0x1.FFFFFFFFFFFFFp+1023, math.maxInt(i32));

    try test_i32_intFromFloat_f128(math.floatMax(f128), math.maxInt(i32));
}

test u32_intFromFloat_f128 {
    try test_u32_intFromFloat_f128(math.inf(f128), 0xffffffff);
    try test_u32_intFromFloat_f128(0, 0x0);
    try test_u32_intFromFloat_f128(0x1.23456789abcdefp+5, 0x24);
    try test_u32_intFromFloat_f128(0x1.23456789abcdefp-3, 0x0);
    try test_u32_intFromFloat_f128(0x1.23456789abcdefp+20, 0x123456);
    try test_u32_intFromFloat_f128(0x1.23456789abcdefp+40, 0xffffffff);
    try test_u32_intFromFloat_f128(0x1.23456789abcdefp+256, 0xffffffff);
    try test_u32_intFromFloat_f128(-0x1.23456789abcdefp+3, 0x0);

    try test_u32_intFromFloat_f128(0x1p+32, 0xFFFFFFFF);
}

fn test_i64_intFromFloat_f128(a: f128, expected: i64) !void {
    const x = i64_intFromFloat_f128(a);
    try testing.expect(x == expected);
}

fn test_u64_intFromFloat_f128(a: f128, expected: u64) !void {
    const x = u64_intFromFloat_f128(a);
    try testing.expect(x == expected);
}

test i64_intFromFloat_f128 {
    try test_i64_intFromFloat_f128(-math.floatMax(f128), math.minInt(i64));

    try test_i64_intFromFloat_f128(-0x1.FFFFFFFFFFFFFp+1023, math.minInt(i64));
    try test_i64_intFromFloat_f128(-0x1.FFFFFFFFFFFFFp+1023, -0x8000000000000000);

    try test_i64_intFromFloat_f128(-0x1.0000000000000p+127, -0x8000000000000000);
    try test_i64_intFromFloat_f128(-0x1.FFFFFFFFFFFFFp+126, -0x8000000000000000);
    try test_i64_intFromFloat_f128(-0x1.FFFFFFFFFFFFEp+126, -0x8000000000000000);

    try test_i64_intFromFloat_f128(-0x1.0000000000001p+63, -0x8000000000000000);
    try test_i64_intFromFloat_f128(-0x1.0000000000000p+63, -0x8000000000000000);
    try test_i64_intFromFloat_f128(-0x1.FFFFFFFFFFFFFp+62, -0x7FFFFFFFFFFFFC00);
    try test_i64_intFromFloat_f128(-0x1.FFFFFFFFFFFFEp+62, -0x7FFFFFFFFFFFF800);

    try test_i64_intFromFloat_f128(-0x1.FFFFFEp+62, -0x7FFFFF8000000000);
    try test_i64_intFromFloat_f128(-0x1.FFFFFCp+62, -0x7FFFFF0000000000);

    try test_i64_intFromFloat_f128(-0x1.000000p+31, -0x80000000);
    try test_i64_intFromFloat_f128(-0x1.FFFFFFp+30, -0x7FFFFFC0);
    try test_i64_intFromFloat_f128(-0x1.FFFFFEp+30, -0x7FFFFF80);
    try test_i64_intFromFloat_f128(-0x1.FFFFFCp+30, -0x7FFFFF00);

    try test_i64_intFromFloat_f128(-2.01, -2);
    try test_i64_intFromFloat_f128(-2.0, -2);
    try test_i64_intFromFloat_f128(-1.99, -1);
    try test_i64_intFromFloat_f128(-1.0, -1);
    try test_i64_intFromFloat_f128(-0.99, 0);
    try test_i64_intFromFloat_f128(-0.5, 0);
    try test_i64_intFromFloat_f128(-math.floatMin(f64), 0);
    try test_i64_intFromFloat_f128(0.0, 0);
    try test_i64_intFromFloat_f128(math.floatMin(f64), 0);
    try test_i64_intFromFloat_f128(0.5, 0);
    try test_i64_intFromFloat_f128(0.99, 0);
    try test_i64_intFromFloat_f128(1.0, 1);
    try test_i64_intFromFloat_f128(1.5, 1);
    try test_i64_intFromFloat_f128(1.99, 1);
    try test_i64_intFromFloat_f128(2.0, 2);
    try test_i64_intFromFloat_f128(2.01, 2);

    try test_i64_intFromFloat_f128(0x1.FFFFFCp+30, 0x7FFFFF00);
    try test_i64_intFromFloat_f128(0x1.FFFFFEp+30, 0x7FFFFF80);
    try test_i64_intFromFloat_f128(0x1.FFFFFFp+30, 0x7FFFFFC0);
    try test_i64_intFromFloat_f128(0x1.000000p+31, 0x80000000);

    try test_i64_intFromFloat_f128(0x1.FFFFFCp+62, 0x7FFFFF0000000000);
    try test_i64_intFromFloat_f128(0x1.FFFFFEp+62, 0x7FFFFF8000000000);

    try test_i64_intFromFloat_f128(0x1.FFFFFFFFFFFFEp+62, 0x7FFFFFFFFFFFF800);
    try test_i64_intFromFloat_f128(0x1.FFFFFFFFFFFFFp+62, 0x7FFFFFFFFFFFFC00);
    try test_i64_intFromFloat_f128(0x1.0000000000000p+63, 0x7FFFFFFFFFFFFFFF);
    try test_i64_intFromFloat_f128(0x1.0000000000001p+63, 0x7FFFFFFFFFFFFFFF);

    try test_i64_intFromFloat_f128(0x1.FFFFFFFFFFFFEp+126, 0x7FFFFFFFFFFFFFFF);
    try test_i64_intFromFloat_f128(0x1.FFFFFFFFFFFFFp+126, 0x7FFFFFFFFFFFFFFF);
    try test_i64_intFromFloat_f128(0x1.0000000000000p+127, 0x7FFFFFFFFFFFFFFF);

    try test_i64_intFromFloat_f128(0x1.FFFFFFFFFFFFFp+1023, 0x7FFFFFFFFFFFFFFF);
    try test_i64_intFromFloat_f128(0x1.FFFFFFFFFFFFFp+1023, math.maxInt(i64));

    try test_i64_intFromFloat_f128(math.floatMax(f128), math.maxInt(i64));
}

test u64_intFromFloat_f128 {
    try test_u64_intFromFloat_f128(0.0, 0);

    try test_u64_intFromFloat_f128(0.5, 0);
    try test_u64_intFromFloat_f128(0.99, 0);
    try test_u64_intFromFloat_f128(1.0, 1);
    try test_u64_intFromFloat_f128(1.5, 1);
    try test_u64_intFromFloat_f128(1.99, 1);
    try test_u64_intFromFloat_f128(2.0, 2);
    try test_u64_intFromFloat_f128(2.01, 2);
    try test_u64_intFromFloat_f128(-0.5, 0);
    try test_u64_intFromFloat_f128(-0.99, 0);
    try test_u64_intFromFloat_f128(-1.0, 0);
    try test_u64_intFromFloat_f128(-1.5, 0);
    try test_u64_intFromFloat_f128(-1.99, 0);
    try test_u64_intFromFloat_f128(-2.0, 0);
    try test_u64_intFromFloat_f128(-2.01, 0);

    try test_u64_intFromFloat_f128(0x1.FFFFFEp+62, 0x7FFFFF8000000000);
    try test_u64_intFromFloat_f128(0x1.FFFFFCp+62, 0x7FFFFF0000000000);

    try test_u64_intFromFloat_f128(-0x1.FFFFFEp+62, 0);
    try test_u64_intFromFloat_f128(-0x1.FFFFFCp+62, 0);

    try test_u64_intFromFloat_f128(0x1.FFFFFFFFFFFFFp+62, 0x7FFFFFFFFFFFFC00);
    try test_u64_intFromFloat_f128(0x1.FFFFFFFFFFFFEp+62, 0x7FFFFFFFFFFFF800);

    try test_u64_intFromFloat_f128(-0x1.FFFFFFFFFFFFFp+62, 0);
    try test_u64_intFromFloat_f128(-0x1.FFFFFFFFFFFFEp+62, 0);

    try test_u64_intFromFloat_f128(0x1.FFFFFFFFFFFFFFFEp+63, 0xFFFFFFFFFFFFFFFF);
    try test_u64_intFromFloat_f128(0x1.0000000000000002p+63, 0x8000000000000001);
    try test_u64_intFromFloat_f128(0x1.0000000000000000p+63, 0x8000000000000000);
    try test_u64_intFromFloat_f128(0x1.FFFFFFFFFFFFFFFCp+62, 0x7FFFFFFFFFFFFFFF);
    try test_u64_intFromFloat_f128(0x1.FFFFFFFFFFFFFFF8p+62, 0x7FFFFFFFFFFFFFFE);
    try test_u64_intFromFloat_f128(0x1p+64, 0xFFFFFFFFFFFFFFFF);

    try test_u64_intFromFloat_f128(-0x1.0000000000000000p+63, 0);
    try test_u64_intFromFloat_f128(-0x1.FFFFFFFFFFFFFFFCp+62, 0);
    try test_u64_intFromFloat_f128(-0x1.FFFFFFFFFFFFFFF8p+62, 0);
}

fn test_i128_intFromFloat_f128(a: f128, expected: i128) !void {
    const x = i128_intFromFloat_f128(a);
    try testing.expect(x == expected);
}

fn test_u128_intFromFloat_f128(a: f128, expected: u128) !void {
    const x = u128_intFromFloat_f128(a);
    try testing.expect(x == expected);
}

test i128_intFromFloat_f128 {
    try test_i128_intFromFloat_f128(-math.floatMax(f128), math.minInt(i128));

    try test_i128_intFromFloat_f128(-0x1.FFFFFFFFFFFFFp+1023, math.minInt(i128));
    try test_i128_intFromFloat_f128(-0x1.FFFFFFFFFFFFFp+1023, -0x80000000000000000000000000000000);

    try test_i128_intFromFloat_f128(-0x1.0000000000000p+127, -0x80000000000000000000000000000000);
    try test_i128_intFromFloat_f128(-0x1.FFFFFFFFFFFFFp+126, -0x7FFFFFFFFFFFFC000000000000000000);
    try test_i128_intFromFloat_f128(-0x1.FFFFFFFFFFFFEp+126, -0x7FFFFFFFFFFFF8000000000000000000);

    try test_i128_intFromFloat_f128(-0x1.0000000000001p+63, -0x8000000000000800);
    try test_i128_intFromFloat_f128(-0x1.0000000000000p+63, -0x8000000000000000);
    try test_i128_intFromFloat_f128(-0x1.FFFFFFFFFFFFFp+62, -0x7FFFFFFFFFFFFC00);
    try test_i128_intFromFloat_f128(-0x1.FFFFFFFFFFFFEp+62, -0x7FFFFFFFFFFFF800);

    try test_i128_intFromFloat_f128(-0x1.FFFFFEp+62, -0x7fffff8000000000);
    try test_i128_intFromFloat_f128(-0x1.FFFFFCp+62, -0x7fffff0000000000);

    try test_i128_intFromFloat_f128(-2.01, -2);
    try test_i128_intFromFloat_f128(-2.0, -2);
    try test_i128_intFromFloat_f128(-1.99, -1);
    try test_i128_intFromFloat_f128(-1.0, -1);
    try test_i128_intFromFloat_f128(-0.99, 0);
    try test_i128_intFromFloat_f128(-0.5, 0);
    try test_i128_intFromFloat_f128(-math.floatMin(f128), 0);
    try test_i128_intFromFloat_f128(0.0, 0);
    try test_i128_intFromFloat_f128(math.floatMin(f128), 0);
    try test_i128_intFromFloat_f128(0.5, 0);
    try test_i128_intFromFloat_f128(0.99, 0);
    try test_i128_intFromFloat_f128(1.0, 1);
    try test_i128_intFromFloat_f128(1.5, 1);
    try test_i128_intFromFloat_f128(1.99, 1);
    try test_i128_intFromFloat_f128(2.0, 2);
    try test_i128_intFromFloat_f128(2.01, 2);

    try test_i128_intFromFloat_f128(0x1.FFFFFCp+62, 0x7FFFFF0000000000);
    try test_i128_intFromFloat_f128(0x1.FFFFFEp+62, 0x7FFFFF8000000000);

    try test_i128_intFromFloat_f128(0x1.FFFFFFFFFFFFEp+62, 0x7FFFFFFFFFFFF800);
    try test_i128_intFromFloat_f128(0x1.FFFFFFFFFFFFFp+62, 0x7FFFFFFFFFFFFC00);
    try test_i128_intFromFloat_f128(0x1.0000000000000p+63, 0x8000000000000000);
    try test_i128_intFromFloat_f128(0x1.0000000000001p+63, 0x8000000000000800);

    try test_i128_intFromFloat_f128(0x1.FFFFFFFFFFFFEp+126, 0x7FFFFFFFFFFFF8000000000000000000);
    try test_i128_intFromFloat_f128(0x1.FFFFFFFFFFFFFp+126, 0x7FFFFFFFFFFFFC000000000000000000);
    try test_i128_intFromFloat_f128(0x1.0000000000000p+127, 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);

    try test_i128_intFromFloat_f128(0x1.FFFFFFFFFFFFFp+1023, 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
    try test_i128_intFromFloat_f128(0x1.FFFFFFFFFFFFFp+1023, math.maxInt(i128));

    try test_i128_intFromFloat_f128(math.floatMax(f128), math.maxInt(i128));
}

test u128_intFromFloat_f128 {
    try test_u128_intFromFloat_f128(math.inf(f128), 0xffffffffffffffffffffffffffffffff);

    try test_u128_intFromFloat_f128(0.0, 0);

    try test_u128_intFromFloat_f128(0.5, 0);
    try test_u128_intFromFloat_f128(0.99, 0);
    try test_u128_intFromFloat_f128(1.0, 1);
    try test_u128_intFromFloat_f128(1.5, 1);
    try test_u128_intFromFloat_f128(1.99, 1);
    try test_u128_intFromFloat_f128(2.0, 2);
    try test_u128_intFromFloat_f128(2.01, 2);
    try test_u128_intFromFloat_f128(-0.01, 0);
    try test_u128_intFromFloat_f128(-0.99, 0);

    try test_u128_intFromFloat_f128(0x1p+128, 0xffffffffffffffffffffffffffffffff);

    try test_u128_intFromFloat_f128(0x1.FFFFFEp+126, 0x7fffff80000000000000000000000000);
    try test_u128_intFromFloat_f128(0x1.FFFFFEp+127, 0xffffff00000000000000000000000000);
    try test_u128_intFromFloat_f128(0x1.FFFFFEp+128, 0xffffffffffffffffffffffffffffffff);
    try test_u128_intFromFloat_f128(0x1.FFFFFEp+129, 0xffffffffffffffffffffffffffffffff);
}

fn test_u128_intFromFloat_f16(a: f16, expected: u128) !void {
    const x = impl.u128_intFromFloat_f16(a);
    try testing.expect(x == expected);
}

test u128_intFromFloat_f16 {
    try test_u128_intFromFloat_f16(math.inf(f16), math.maxInt(u128));
    try test_u128_intFromFloat_f16(math.floatMax(f16), 65504);
}

fn test_u128_intFromFloat_f80(a: f80, expected: u128) !void {
    const x = impl.u128_intFromFloat_f80(a);
    try testing.expect(x == expected);
}

test u128_intFromFloat_f80 {
    try test_u128_intFromFloat_f80(math.inf(f80), math.maxInt(u128));
    try test_u128_intFromFloat_f80(math.floatMax(f80), math.maxInt(u128));
    try test_u128_intFromFloat_f80(math.maxInt(u64), math.maxInt(u64));
}
