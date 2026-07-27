const std = @import("std");
const testing = std.testing;
const math = std.math;

const impl = @import("float_from_int.zig");

const f16_floatFromInt_i32 = impl.f16_floatFromInt_i32;
const f16_floatFromInt_u32 = impl.f16_floatFromInt_u32;
const f16_floatFromInt_i64 = impl.f16_floatFromInt_i64;
const f16_floatFromInt_u64 = impl.f16_floatFromInt_u64;
const f16_floatFromInt_i128 = impl.f16_floatFromInt_i128;
const f16_floatFromInt_u128 = impl.f16_floatFromInt_u128;
const f16_floatFromInt_signed = impl.f16_floatFromInt_signed;
const f16_floatFromInt_unsigned = impl.f16_floatFromInt_unsigned;

const f32_floatFromInt_i32 = impl.f32_floatFromInt_i32;
const f32_floatFromInt_u32 = impl.f32_floatFromInt_u32;
const f32_floatFromInt_i64 = impl.f32_floatFromInt_i64;
const f32_floatFromInt_u64 = impl.f32_floatFromInt_u64;
const f32_floatFromInt_i128 = impl.f32_floatFromInt_i128;
const f32_floatFromInt_u128 = impl.f32_floatFromInt_u128;
const f32_floatFromInt_signed = impl.f32_floatFromInt_signed;
const f32_floatFromInt_unsigned = impl.f32_floatFromInt_unsigned;

const f64_floatFromInt_i32 = impl.f64_floatFromInt_i32;
const f64_floatFromInt_u32 = impl.f64_floatFromInt_u32;
const f64_floatFromInt_i64 = impl.f64_floatFromInt_i64;
const f64_floatFromInt_u64 = impl.f64_floatFromInt_u64;
const f64_floatFromInt_i128 = impl.f64_floatFromInt_i128;
const f64_floatFromInt_u128 = impl.f64_floatFromInt_u128;
const f64_floatFromInt_signed = impl.f64_floatFromInt_signed;
const f64_floatFromInt_unsigned = impl.f64_floatFromInt_unsigned;

const f80_floatFromInt_i32 = impl.f80_floatFromInt_i32;
const f80_floatFromInt_u32 = impl.f80_floatFromInt_u32;
const f80_floatFromInt_i64 = impl.f80_floatFromInt_i64;
const f80_floatFromInt_u64 = impl.f80_floatFromInt_u64;
const f80_floatFromInt_i128 = impl.f80_floatFromInt_i128;
const f80_floatFromInt_u128 = impl.f80_floatFromInt_u128;
const f80_floatFromInt_signed = impl.f80_floatFromInt_signed;
const f80_floatFromInt_unsigned = impl.f80_floatFromInt_unsigned;

const f128_floatFromInt_i32 = impl.f128_floatFromInt_i32;
const f128_floatFromInt_u32 = impl.f128_floatFromInt_u32;
const f128_floatFromInt_i64 = impl.f128_floatFromInt_i64;
const f128_floatFromInt_u64 = impl.f128_floatFromInt_u64;
const f128_floatFromInt_i128 = impl.f128_floatFromInt_i128;
const f128_floatFromInt_u128 = impl.f128_floatFromInt_u128;
const f128_floatFromInt_signed = impl.f128_floatFromInt_signed;
const f128_floatFromInt_unsigned = impl.f128_floatFromInt_unsigned;

fn test_f32_floatFromInt_i32(a: i32, expected: u32) !void {
    const r = f32_floatFromInt_i32(a);
    try std.testing.expect(@as(u32, @bitCast(r)) == expected);
}

fn test_f32_floatFromInt_u32(a: u32, expected: u32) !void {
    const r = f32_floatFromInt_u32(a);
    try std.testing.expect(@as(u32, @bitCast(r)) == expected);
}

test f32_floatFromInt_i32 {
    try test_f32_floatFromInt_i32(0, 0x00000000);
    try test_f32_floatFromInt_i32(1, 0x3f800000);
    try test_f32_floatFromInt_i32(-1, 0xbf800000);
    try test_f32_floatFromInt_i32(0x7FFFFFFF, 0x4f000000);
    try test_f32_floatFromInt_i32(@bitCast(@as(u32, @intCast(0x80000000))), 0xcf000000);

    try testing.expect(f32_floatFromInt_i32(math.minInt(i32)) == math.minInt(i32));
}

test f32_floatFromInt_u32 {
    // Test the produced bit pattern
    try test_f32_floatFromInt_u32(0, 0);
    try test_f32_floatFromInt_u32(1, 0x3f800000);
    try test_f32_floatFromInt_u32(0x7FFFFFFF, 0x4f000000);
    try test_f32_floatFromInt_u32(0x80000000, 0x4f000000);
    try test_f32_floatFromInt_u32(0xFFFFFFFF, 0x4f800000);

    try testing.expect(f32_floatFromInt_u32(0) == 0.0);
    try testing.expect(f32_floatFromInt_u32(math.maxInt(u24)) == math.maxInt(u24));
    try testing.expect(f32_floatFromInt_u32(math.maxInt(u24) + 1) == math.maxInt(u24) + 1); // 0x100_0000 - Exact
    try testing.expect(f32_floatFromInt_u32(math.maxInt(u24) + 2) == math.maxInt(u24) + 1); // 0x100_0001 - Tie: Rounds down to even
    try testing.expect(f32_floatFromInt_u32(math.maxInt(u24) + 3) == math.maxInt(u24) + 3); // 0x100_0002 - Exact
    try testing.expect(f32_floatFromInt_u32(math.maxInt(u24) + 4) == math.maxInt(u24) + 5); // 0x100_0003 - Tie: Rounds up to even
    try testing.expect(f32_floatFromInt_u32(math.maxInt(u24) + 5) == math.maxInt(u24) + 5); // 0x100_0004 - Exact
    try testing.expect(f32_floatFromInt_u32(math.maxInt(u32)) == math.maxInt(u32) + 1);
}

fn test_f32_floatFromInt_i64(a: i64, expected: f32) !void {
    const x = f32_floatFromInt_i64(a);
    try testing.expect(x == expected);
}

fn test_f32_floatFromInt_u64(a: u64, expected: f32) !void {
    const x = f32_floatFromInt_u64(a);
    try testing.expect(x == expected);
}

test f32_floatFromInt_i64 {
    try test_f32_floatFromInt_i64(0, 0.0);
    try test_f32_floatFromInt_i64(1, 1.0);
    try test_f32_floatFromInt_i64(2, 2.0);
    try test_f32_floatFromInt_i64(-1, -1.0);
    try test_f32_floatFromInt_i64(-2, -2.0);
    try test_f32_floatFromInt_i64(0x7FFFFF8000000000, 0x1.FFFFFEp+62);
    try test_f32_floatFromInt_i64(0x7FFFFF0000000000, 0x1.FFFFFCp+62);
    try test_f32_floatFromInt_i64(@bitCast(@as(u64, 0x8000008000000000)), -0x1.FFFFFEp+62);
    try test_f32_floatFromInt_i64(@bitCast(@as(u64, 0x8000010000000000)), -0x1.FFFFFCp+62);
    try test_f32_floatFromInt_i64(@bitCast(@as(u64, 0x8000000000000000)), -0x1.000000p+63);
    try test_f32_floatFromInt_i64(@bitCast(@as(u64, 0x8000000000000001)), -0x1.000000p+63);
    try test_f32_floatFromInt_i64(0x0007FB72E8000000, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_i64(0x0007FB72EA000000, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_i64(0x0007FB72EB000000, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_i64(0x0007FB72EBFFFFFF, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_i64(0x0007FB72EC000000, 0x1.FEDCBCp+50);
    try test_f32_floatFromInt_i64(0x0007FB72E8000001, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_i64(0x0007FB72E6000000, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_i64(0x0007FB72E7000000, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_i64(0x0007FB72E7FFFFFF, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_i64(0x0007FB72E4000001, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_i64(0x0007FB72E4000000, 0x1.FEDCB8p+50);
}

test f32_floatFromInt_u64 {
    try test_f32_floatFromInt_u64(0, 0.0);
    try test_f32_floatFromInt_u64(1, 1.0);
    try test_f32_floatFromInt_u64(2, 2.0);
    try test_f32_floatFromInt_u64(0x7FFFFF8000000000, 0x1.FFFFFEp+62);
    try test_f32_floatFromInt_u64(0x7FFFFF0000000000, 0x1.FFFFFCp+62);
    try test_f32_floatFromInt_u64(0x8000008000000000, 0x1p+63);
    try test_f32_floatFromInt_u64(0x8000010000000000, 0x1.000002p+63);
    try test_f32_floatFromInt_u64(0x8000000000000000, 0x1p+63);
    try test_f32_floatFromInt_u64(0x8000000000000001, 0x1p+63);
    try test_f32_floatFromInt_u64(0xFFFFFFFFFFFFFFFE, 0x1p+64);
    try test_f32_floatFromInt_u64(0xFFFFFFFFFFFFFFFF, 0x1p+64);
    try test_f32_floatFromInt_u64(0x0007FB72E8000000, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_u64(0x0007FB72EA000000, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_u64(0x0007FB72EB000000, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_u64(0x0007FB72EBFFFFFF, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_u64(0x0007FB72EC000000, 0x1.FEDCBCp+50);
    try test_f32_floatFromInt_u64(0x0007FB72E8000001, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_u64(0x0007FB72E6000000, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_u64(0x0007FB72E7000000, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_u64(0x0007FB72E7FFFFFF, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_u64(0x0007FB72E4000001, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_u64(0x0007FB72E4000000, 0x1.FEDCB8p+50);
}

fn test_f32_floatFromInt_i128(a: i128, expected: f32) !void {
    const x = f32_floatFromInt_i128(a);
    try testing.expect(x == expected);
}

fn test_f32_floatFromInt_u128(a: u128, expected: f32) !void {
    const x = f32_floatFromInt_u128(a);
    try testing.expect(x == expected);
}

test f32_floatFromInt_i128 {
    try test_f32_floatFromInt_i128(0, 0.0);

    try test_f32_floatFromInt_i128(1, 1.0);
    try test_f32_floatFromInt_i128(2, 2.0);
    try test_f32_floatFromInt_i128(-1, -1.0);
    try test_f32_floatFromInt_i128(-2, -2.0);

    try test_f32_floatFromInt_i128(0x7FFFFF8000000000, 0x1.FFFFFEp+62);
    try test_f32_floatFromInt_i128(0x7FFFFF0000000000, 0x1.FFFFFCp+62);

    try test_f32_floatFromInt_i128(make_ti(0xFFFFFFFFFFFFFFFF, 0x8000008000000000), -0x1.FFFFFEp+62);
    try test_f32_floatFromInt_i128(make_ti(0xFFFFFFFFFFFFFFFF, 0x8000010000000000), -0x1.FFFFFCp+62);

    try test_f32_floatFromInt_i128(make_ti(0xFFFFFFFFFFFFFFFF, 0x8000000000000000), -0x1.000000p+63);
    try test_f32_floatFromInt_i128(make_ti(0xFFFFFFFFFFFFFFFF, 0x8000000000000001), -0x1.000000p+63);

    try test_f32_floatFromInt_i128(0x0007FB72E8000000, 0x1.FEDCBAp+50);

    try test_f32_floatFromInt_i128(0x0007FB72EA000000, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_i128(0x0007FB72EB000000, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_i128(0x0007FB72EBFFFFFF, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_i128(0x0007FB72EC000000, 0x1.FEDCBCp+50);
    try test_f32_floatFromInt_i128(0x0007FB72E8000001, 0x1.FEDCBAp+50);

    try test_f32_floatFromInt_i128(0x0007FB72E6000000, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_i128(0x0007FB72E7000000, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_i128(0x0007FB72E7FFFFFF, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_i128(0x0007FB72E4000001, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_i128(0x0007FB72E4000000, 0x1.FEDCB8p+50);

    try test_f32_floatFromInt_i128(make_ti(0x0007FB72E8000000, 0), 0x1.FEDCBAp+114);

    try test_f32_floatFromInt_i128(make_ti(0x0007FB72EA000000, 0), 0x1.FEDCBAp+114);
    try test_f32_floatFromInt_i128(make_ti(0x0007FB72EB000000, 0), 0x1.FEDCBAp+114);
    try test_f32_floatFromInt_i128(make_ti(0x0007FB72EBFFFFFF, 0), 0x1.FEDCBAp+114);
    try test_f32_floatFromInt_i128(make_ti(0x0007FB72EC000000, 0), 0x1.FEDCBCp+114);
    try test_f32_floatFromInt_i128(make_ti(0x0007FB72E8000001, 0), 0x1.FEDCBAp+114);

    try test_f32_floatFromInt_i128(make_ti(0x0007FB72E6000000, 0), 0x1.FEDCBAp+114);
    try test_f32_floatFromInt_i128(make_ti(0x0007FB72E7000000, 0), 0x1.FEDCBAp+114);
    try test_f32_floatFromInt_i128(make_ti(0x0007FB72E7FFFFFF, 0), 0x1.FEDCBAp+114);
    try test_f32_floatFromInt_i128(make_ti(0x0007FB72E4000001, 0), 0x1.FEDCBAp+114);
    try test_f32_floatFromInt_i128(make_ti(0x0007FB72E4000000, 0), 0x1.FEDCB8p+114);
}

test f32_floatFromInt_u128 {
    try test_f32_floatFromInt_u128(0, 0.0);

    try test_f32_floatFromInt_u128(1, 1.0);
    try test_f32_floatFromInt_u128(2, 2.0);
    try test_f32_floatFromInt_u128(20, 20.0);

    try test_f32_floatFromInt_u128(0x7FFFFF8000000000, 0x1.FFFFFEp+62);
    try test_f32_floatFromInt_u128(0x7FFFFF0000000000, 0x1.FFFFFCp+62);

    try test_f32_floatFromInt_u128(make_uti(0x8000008000000000, 0), 0x1.000001p+127);
    try test_f32_floatFromInt_u128(make_uti(0x8000000000000800, 0), 0x1.0p+127);
    try test_f32_floatFromInt_u128(make_uti(0x8000010000000000, 0), 0x1.000002p+127);

    try test_f32_floatFromInt_u128(make_uti(0x8000000000000000, 0), 0x1.000000p+127);

    try test_f32_floatFromInt_u128(0x0007FB72E8000000, 0x1.FEDCBAp+50);

    try test_f32_floatFromInt_u128(0x0007FB72EA000000, 0x1.FEDCBA8p+50);
    try test_f32_floatFromInt_u128(0x0007FB72EB000000, 0x1.FEDCBACp+50);

    try test_f32_floatFromInt_u128(0x0007FB72EC000000, 0x1.FEDCBBp+50);

    try test_f32_floatFromInt_u128(0x0007FB72E6000000, 0x1.FEDCB98p+50);
    try test_f32_floatFromInt_u128(0x0007FB72E7000000, 0x1.FEDCB9Cp+50);
    try test_f32_floatFromInt_u128(0x0007FB72E4000000, 0x1.FEDCB9p+50);

    try test_f32_floatFromInt_u128(0xFFFFFFFFFFFFFFFE, 0x1p+64);
    try test_f32_floatFromInt_u128(0xFFFFFFFFFFFFFFFF, 0x1p+64);

    try test_f32_floatFromInt_u128(0x0007FB72E8000000, 0x1.FEDCBAp+50);

    try test_f32_floatFromInt_u128(0x0007FB72EA000000, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_u128(0x0007FB72EB000000, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_u128(0x0007FB72EBFFFFFF, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_u128(0x0007FB72EC000000, 0x1.FEDCBCp+50);
    try test_f32_floatFromInt_u128(0x0007FB72E8000001, 0x1.FEDCBAp+50);

    try test_f32_floatFromInt_u128(0x0007FB72E6000000, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_u128(0x0007FB72E7000000, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_u128(0x0007FB72E7FFFFFF, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_u128(0x0007FB72E4000001, 0x1.FEDCBAp+50);
    try test_f32_floatFromInt_u128(0x0007FB72E4000000, 0x1.FEDCB8p+50);

    try test_f32_floatFromInt_u128(make_uti(0x0000000000001FED, 0xCB90000000000001), 0x1.FEDCBAp+76);
    try test_f32_floatFromInt_u128(make_uti(0x0000000000001FED, 0xCBA0000000000000), 0x1.FEDCBAp+76);
    try test_f32_floatFromInt_u128(make_uti(0x0000000000001FED, 0xCBAFFFFFFFFFFFFF), 0x1.FEDCBAp+76);
    try test_f32_floatFromInt_u128(make_uti(0x0000000000001FED, 0xCBB0000000000000), 0x1.FEDCBCp+76);
    try test_f32_floatFromInt_u128(make_uti(0x0000000000001FED, 0xCBB0000000000001), 0x1.FEDCBCp+76);
    try test_f32_floatFromInt_u128(make_uti(0x0000000000001FED, 0xCBBFFFFFFFFFFFFF), 0x1.FEDCBCp+76);
    try test_f32_floatFromInt_u128(make_uti(0x0000000000001FED, 0xCBC0000000000000), 0x1.FEDCBCp+76);
    try test_f32_floatFromInt_u128(make_uti(0x0000000000001FED, 0xCBC0000000000001), 0x1.FEDCBCp+76);
    try test_f32_floatFromInt_u128(make_uti(0x0000000000001FED, 0xCBD0000000000000), 0x1.FEDCBCp+76);
    try test_f32_floatFromInt_u128(make_uti(0x0000000000001FED, 0xCBD0000000000001), 0x1.FEDCBEp+76);
    try test_f32_floatFromInt_u128(make_uti(0x0000000000001FED, 0xCBDFFFFFFFFFFFFF), 0x1.FEDCBEp+76);
    try test_f32_floatFromInt_u128(make_uti(0x0000000000001FED, 0xCBE0000000000000), 0x1.FEDCBEp+76);

    // Test overflow to infinity
    try test_f32_floatFromInt_u128(math.maxInt(u128), @bitCast(math.inf(f32)));
}

fn test_f32_floatFromInt(expected: u32, comptime T: type, a: T) !void {
    const int = @typeInfo(T).int;
    const r = switch (int.signedness) {
        .signed => f32_floatFromInt_signed,
        .unsigned => f32_floatFromInt_unsigned,
    }(@ptrCast(&a));
    try testing.expect(expected == @as(u32, @bitCast(r)));
}

test f32_floatFromInt_signed {
    try test_f32_floatFromInt(0xFF000000, i256, -1 << 127);
    try test_f32_floatFromInt(0xFF000000, i256, -math.maxInt(u127));
    try test_f32_floatFromInt(0xDF012347, i256, -0x8123468100000000);
    try test_f32_floatFromInt(0xDF012347, i256, -0x8123468000000001);
    try test_f32_floatFromInt(0xDF012346, i256, -0x8123468000000000);
    try test_f32_floatFromInt(0xDF012346, i256, -0x8123458100000000);
    try test_f32_floatFromInt(0xDF012346, i256, -0x8123458000000001);
    try test_f32_floatFromInt(0xDF012346, i256, -0x8123458000000000);
    try test_f32_floatFromInt(0xDF012345, i256, -0x8123456789ABCDEF);
    try test_f32_floatFromInt(0xBF800000, i256, -1);
    try test_f32_floatFromInt(0x00000000, i256, 0);
    try test_f32_floatFromInt(0x5F012345, i256, 0x8123456789ABCDEF);
    try test_f32_floatFromInt(0x5F012346, i256, 0x8123458000000000);
    try test_f32_floatFromInt(0x5F012346, i256, 0x8123458000000001);
    try test_f32_floatFromInt(0x5F012346, i256, 0x8123458100000000);
    try test_f32_floatFromInt(0x5F012346, i256, 0x8123468000000000);
    try test_f32_floatFromInt(0x5F012347, i256, 0x8123468000000001);
    try test_f32_floatFromInt(0x5F012347, i256, 0x8123468100000000);
    try test_f32_floatFromInt(0x7F000000, i256, math.maxInt(u127));
    try test_f32_floatFromInt(0x7F000000, i256, 1 << 127);
}

test f32_floatFromInt_unsigned {
    try test_f32_floatFromInt(0x00000000, u256, 0);
    try test_f32_floatFromInt(0x5F012345, u256, 0x8123456789ABCDEF);
    try test_f32_floatFromInt(0x5F012346, u256, 0x8123458000000000);
    try test_f32_floatFromInt(0x5F012346, u256, 0x8123458000000001);
    try test_f32_floatFromInt(0x5F012346, u256, 0x8123458080000000);
    try test_f32_floatFromInt(0x5F012346, u256, 0x8123468000000000);
    try test_f32_floatFromInt(0x5F012347, u256, 0x8123468000000001);
    try test_f32_floatFromInt(0x5F012347, u256, 0x8123468080000000);
    try test_f32_floatFromInt(0x7F000000, u256, math.maxInt(u127));
    try test_f32_floatFromInt(0x7F000000, u256, 1 << 127);
    try test_f32_floatFromInt(0x7F800000, u256, math.maxInt(u256));
}

fn test_f64_floatFromInt_i32(a: i32, expected: u64) !void {
    const r = f64_floatFromInt_i32(a);
    try std.testing.expect(@as(u64, @bitCast(r)) == expected);
}

fn test_f64_floatFromInt_u32(a: u32, expected: u64) !void {
    const r = f64_floatFromInt_u32(a);
    try std.testing.expect(@as(u64, @bitCast(r)) == expected);
}

test f64_floatFromInt_i32 {
    try test_f64_floatFromInt_i32(0, 0x0000000000000000);
    try test_f64_floatFromInt_i32(1, 0x3ff0000000000000);
    try test_f64_floatFromInt_i32(-1, 0xbff0000000000000);
    try test_f64_floatFromInt_i32(0x7FFFFFFF, 0x41dfffffffc00000);
    try test_f64_floatFromInt_i32(@bitCast(@as(u32, @intCast(0x80000000))), 0xc1e0000000000000);
}

test f64_floatFromInt_u32 {
    try test_f64_floatFromInt_u32(0, 0x0000000000000000);
    try test_f64_floatFromInt_u32(1, 0x3ff0000000000000);
    try test_f64_floatFromInt_u32(0x7FFFFFFF, 0x41dfffffffc00000);
    try test_f64_floatFromInt_u32(@intCast(0x80000000), 0x41e0000000000000);
    try test_f64_floatFromInt_u32(@intCast(0xFFFFFFFF), 0x41efffffffe00000);
}

fn test_f64_floatFromInt_i64(a: i64, expected: f64) !void {
    const r = f64_floatFromInt_i64(a);
    try testing.expect(r == expected);
}

fn test_f64_floatFromInt_u64(a: u64, expected: f64) !void {
    const r = f64_floatFromInt_u64(a);
    try testing.expect(r == expected);
}

test f64_floatFromInt_i64 {
    try test_f64_floatFromInt_i64(0, 0.0);
    try test_f64_floatFromInt_i64(1, 1.0);
    try test_f64_floatFromInt_i64(2, 2.0);
    try test_f64_floatFromInt_i64(20, 20.0);
    try test_f64_floatFromInt_i64(-1, -1.0);
    try test_f64_floatFromInt_i64(-2, -2.0);
    try test_f64_floatFromInt_i64(-20, -20.0);
    try test_f64_floatFromInt_i64(0x7FFFFF8000000000, 0x1.FFFFFEp+62);
    try test_f64_floatFromInt_i64(0x7FFFFFFFFFFFF800, 0x1.FFFFFFFFFFFFEp+62);
    try test_f64_floatFromInt_i64(0x7FFFFF0000000000, 0x1.FFFFFCp+62);
    try test_f64_floatFromInt_i64(0x7FFFFFFFFFFFF000, 0x1.FFFFFFFFFFFFCp+62);
    try test_f64_floatFromInt_i64(@bitCast(@as(u64, @intCast(0x8000008000000000))), -0x1.FFFFFEp+62);
    try test_f64_floatFromInt_i64(@bitCast(@as(u64, @intCast(0x8000000000000800))), -0x1.FFFFFFFFFFFFEp+62);
    try test_f64_floatFromInt_i64(@bitCast(@as(u64, @intCast(0x8000010000000000))), -0x1.FFFFFCp+62);
    try test_f64_floatFromInt_i64(@bitCast(@as(u64, @intCast(0x8000000000001000))), -0x1.FFFFFFFFFFFFCp+62);
    try test_f64_floatFromInt_i64(@bitCast(@as(u64, @intCast(0x8000000000000000))), -0x1.000000p+63);
    try test_f64_floatFromInt_i64(@bitCast(@as(u64, @intCast(0x8000000000000001))), -0x1.000000p+63); // 0x8000000000000001
    try test_f64_floatFromInt_i64(0x0007FB72E8000000, 0x1.FEDCBAp+50);
    try test_f64_floatFromInt_i64(0x0007FB72EA000000, 0x1.FEDCBA8p+50);
    try test_f64_floatFromInt_i64(0x0007FB72EB000000, 0x1.FEDCBACp+50);
    try test_f64_floatFromInt_i64(0x0007FB72EBFFFFFF, 0x1.FEDCBAFFFFFFCp+50);
    try test_f64_floatFromInt_i64(0x0007FB72EC000000, 0x1.FEDCBBp+50);
    try test_f64_floatFromInt_i64(0x0007FB72E8000001, 0x1.FEDCBA0000004p+50);
    try test_f64_floatFromInt_i64(0x0007FB72E6000000, 0x1.FEDCB98p+50);
    try test_f64_floatFromInt_i64(0x0007FB72E7000000, 0x1.FEDCB9Cp+50);
    try test_f64_floatFromInt_i64(0x0007FB72E7FFFFFF, 0x1.FEDCB9FFFFFFCp+50);
    try test_f64_floatFromInt_i64(0x0007FB72E4000001, 0x1.FEDCB90000004p+50);
    try test_f64_floatFromInt_i64(0x0007FB72E4000000, 0x1.FEDCB9p+50);
    try test_f64_floatFromInt_i64(0x023479FD0E092DC0, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_i64(0x023479FD0E092DA1, 0x1.1A3CFE870496Dp+57);
    try test_f64_floatFromInt_i64(0x023479FD0E092DB0, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_i64(0x023479FD0E092DB8, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_i64(0x023479FD0E092DB6, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_i64(0x023479FD0E092DBF, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_i64(0x023479FD0E092DC1, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_i64(0x023479FD0E092DC7, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_i64(0x023479FD0E092DC8, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_i64(0x023479FD0E092DCF, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_i64(0x023479FD0E092DD0, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_i64(0x023479FD0E092DD1, 0x1.1A3CFE870496Fp+57);
    try test_f64_floatFromInt_i64(0x023479FD0E092DD8, 0x1.1A3CFE870496Fp+57);
    try test_f64_floatFromInt_i64(0x023479FD0E092DDF, 0x1.1A3CFE870496Fp+57);
    try test_f64_floatFromInt_i64(0x023479FD0E092DE0, 0x1.1A3CFE870496Fp+57);
}

test f64_floatFromInt_u64 {
    try test_f64_floatFromInt_u64(0, 0.0);
    try test_f64_floatFromInt_u64(1, 1.0);
    try test_f64_floatFromInt_u64(2, 2.0);
    try test_f64_floatFromInt_u64(20, 20.0);
    try test_f64_floatFromInt_u64(0x7FFFFF8000000000, 0x1.FFFFFEp+62);
    try test_f64_floatFromInt_u64(0x7FFFFFFFFFFFF800, 0x1.FFFFFFFFFFFFEp+62);
    try test_f64_floatFromInt_u64(0x7FFFFF0000000000, 0x1.FFFFFCp+62);
    try test_f64_floatFromInt_u64(0x7FFFFFFFFFFFF000, 0x1.FFFFFFFFFFFFCp+62);
    try test_f64_floatFromInt_u64(0x8000008000000000, 0x1.000001p+63);
    try test_f64_floatFromInt_u64(0x8000000000000800, 0x1.0000000000001p+63);
    try test_f64_floatFromInt_u64(0x8000010000000000, 0x1.000002p+63);
    try test_f64_floatFromInt_u64(0x8000000000001000, 0x1.0000000000002p+63);
    try test_f64_floatFromInt_u64(0x8000000000000000, 0x1p+63);
    try test_f64_floatFromInt_u64(0x8000000000000001, 0x1p+63);
    try test_f64_floatFromInt_u64(0x0007FB72E8000000, 0x1.FEDCBAp+50);
    try test_f64_floatFromInt_u64(0x0007FB72EA000000, 0x1.FEDCBA8p+50);
    try test_f64_floatFromInt_u64(0x0007FB72EB000000, 0x1.FEDCBACp+50);
    try test_f64_floatFromInt_u64(0x0007FB72EBFFFFFF, 0x1.FEDCBAFFFFFFCp+50);
    try test_f64_floatFromInt_u64(0x0007FB72EC000000, 0x1.FEDCBBp+50);
    try test_f64_floatFromInt_u64(0x0007FB72E8000001, 0x1.FEDCBA0000004p+50);
    try test_f64_floatFromInt_u64(0x0007FB72E6000000, 0x1.FEDCB98p+50);
    try test_f64_floatFromInt_u64(0x0007FB72E7000000, 0x1.FEDCB9Cp+50);
    try test_f64_floatFromInt_u64(0x0007FB72E7FFFFFF, 0x1.FEDCB9FFFFFFCp+50);
    try test_f64_floatFromInt_u64(0x0007FB72E4000001, 0x1.FEDCB90000004p+50);
    try test_f64_floatFromInt_u64(0x0007FB72E4000000, 0x1.FEDCB9p+50);
    try test_f64_floatFromInt_u64(0x023479FD0E092DC0, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_u64(0x023479FD0E092DA1, 0x1.1A3CFE870496Dp+57);
    try test_f64_floatFromInt_u64(0x023479FD0E092DB0, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_u64(0x023479FD0E092DB8, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_u64(0x023479FD0E092DB6, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_u64(0x023479FD0E092DBF, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_u64(0x023479FD0E092DC1, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_u64(0x023479FD0E092DC7, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_u64(0x023479FD0E092DC8, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_u64(0x023479FD0E092DCF, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_u64(0x023479FD0E092DD0, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_u64(0x023479FD0E092DD1, 0x1.1A3CFE870496Fp+57);
    try test_f64_floatFromInt_u64(0x023479FD0E092DD8, 0x1.1A3CFE870496Fp+57);
    try test_f64_floatFromInt_u64(0x023479FD0E092DDF, 0x1.1A3CFE870496Fp+57);
    try test_f64_floatFromInt_u64(0x023479FD0E092DE0, 0x1.1A3CFE870496Fp+57);
}

fn test_f64_floatFromInt_i128(a: i128, expected: f64) !void {
    const x = f64_floatFromInt_i128(a);
    try testing.expect(x == expected);
}

fn test_f64_floatFromInt_u128(a: u128, expected: f64) !void {
    const x = f64_floatFromInt_u128(a);
    try testing.expect(x == expected);
}

test f64_floatFromInt_i128 {
    try test_f64_floatFromInt_i128(0, 0.0);

    try test_f64_floatFromInt_i128(1, 1.0);
    try test_f64_floatFromInt_i128(2, 2.0);
    try test_f64_floatFromInt_i128(20, 20.0);
    try test_f64_floatFromInt_i128(-1, -1.0);
    try test_f64_floatFromInt_i128(-2, -2.0);
    try test_f64_floatFromInt_i128(-20, -20.0);

    try test_f64_floatFromInt_i128(0x7FFFFF8000000000, 0x1.FFFFFEp+62);
    try test_f64_floatFromInt_i128(0x7FFFFFFFFFFFF800, 0x1.FFFFFFFFFFFFEp+62);
    try test_f64_floatFromInt_i128(0x7FFFFF0000000000, 0x1.FFFFFCp+62);
    try test_f64_floatFromInt_i128(0x7FFFFFFFFFFFF000, 0x1.FFFFFFFFFFFFCp+62);

    try test_f64_floatFromInt_i128(make_ti(0x8000008000000000, 0), -0x1.FFFFFEp+126);
    try test_f64_floatFromInt_i128(make_ti(0x8000000000000800, 0), -0x1.FFFFFFFFFFFFEp+126);
    try test_f64_floatFromInt_i128(make_ti(0x8000010000000000, 0), -0x1.FFFFFCp+126);
    try test_f64_floatFromInt_i128(make_ti(0x8000000000001000, 0), -0x1.FFFFFFFFFFFFCp+126);

    try test_f64_floatFromInt_i128(make_ti(0x8000000000000000, 0), -0x1.000000p+127);
    try test_f64_floatFromInt_i128(make_ti(0x8000000000000001, 0), -0x1.000000p+127);

    try test_f64_floatFromInt_i128(0x0007FB72E8000000, 0x1.FEDCBAp+50);

    try test_f64_floatFromInt_i128(0x0007FB72EA000000, 0x1.FEDCBA8p+50);
    try test_f64_floatFromInt_i128(0x0007FB72EB000000, 0x1.FEDCBACp+50);
    try test_f64_floatFromInt_i128(0x0007FB72EBFFFFFF, 0x1.FEDCBAFFFFFFCp+50);
    try test_f64_floatFromInt_i128(0x0007FB72EC000000, 0x1.FEDCBBp+50);
    try test_f64_floatFromInt_i128(0x0007FB72E8000001, 0x1.FEDCBA0000004p+50);

    try test_f64_floatFromInt_i128(0x0007FB72E6000000, 0x1.FEDCB98p+50);
    try test_f64_floatFromInt_i128(0x0007FB72E7000000, 0x1.FEDCB9Cp+50);
    try test_f64_floatFromInt_i128(0x0007FB72E7FFFFFF, 0x1.FEDCB9FFFFFFCp+50);
    try test_f64_floatFromInt_i128(0x0007FB72E4000001, 0x1.FEDCB90000004p+50);
    try test_f64_floatFromInt_i128(0x0007FB72E4000000, 0x1.FEDCB9p+50);

    try test_f64_floatFromInt_i128(0x023479FD0E092DC0, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_i128(0x023479FD0E092DA1, 0x1.1A3CFE870496Dp+57);
    try test_f64_floatFromInt_i128(0x023479FD0E092DB0, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_i128(0x023479FD0E092DB8, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_i128(0x023479FD0E092DB6, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_i128(0x023479FD0E092DBF, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_i128(0x023479FD0E092DC1, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_i128(0x023479FD0E092DC7, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_i128(0x023479FD0E092DC8, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_i128(0x023479FD0E092DCF, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_i128(0x023479FD0E092DD0, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_i128(0x023479FD0E092DD1, 0x1.1A3CFE870496Fp+57);
    try test_f64_floatFromInt_i128(0x023479FD0E092DD8, 0x1.1A3CFE870496Fp+57);
    try test_f64_floatFromInt_i128(0x023479FD0E092DDF, 0x1.1A3CFE870496Fp+57);
    try test_f64_floatFromInt_i128(0x023479FD0E092DE0, 0x1.1A3CFE870496Fp+57);

    try test_f64_floatFromInt_i128(make_ti(0x023479FD0E092DC0, 0), 0x1.1A3CFE870496Ep+121);
    try test_f64_floatFromInt_i128(make_ti(0x023479FD0E092DA1, 1), 0x1.1A3CFE870496Dp+121);
    try test_f64_floatFromInt_i128(make_ti(0x023479FD0E092DB0, 2), 0x1.1A3CFE870496Ep+121);
    try test_f64_floatFromInt_i128(make_ti(0x023479FD0E092DB8, 3), 0x1.1A3CFE870496Ep+121);
    try test_f64_floatFromInt_i128(make_ti(0x023479FD0E092DB6, 4), 0x1.1A3CFE870496Ep+121);
    try test_f64_floatFromInt_i128(make_ti(0x023479FD0E092DBF, 5), 0x1.1A3CFE870496Ep+121);
    try test_f64_floatFromInt_i128(make_ti(0x023479FD0E092DC1, 6), 0x1.1A3CFE870496Ep+121);
    try test_f64_floatFromInt_i128(make_ti(0x023479FD0E092DC7, 7), 0x1.1A3CFE870496Ep+121);
    try test_f64_floatFromInt_i128(make_ti(0x023479FD0E092DC8, 8), 0x1.1A3CFE870496Ep+121);
    try test_f64_floatFromInt_i128(make_ti(0x023479FD0E092DCF, 9), 0x1.1A3CFE870496Ep+121);
    try test_f64_floatFromInt_i128(make_ti(0x023479FD0E092DD0, 0), 0x1.1A3CFE870496Ep+121);
    try test_f64_floatFromInt_i128(make_ti(0x023479FD0E092DD1, 11), 0x1.1A3CFE870496Fp+121);
    try test_f64_floatFromInt_i128(make_ti(0x023479FD0E092DD8, 12), 0x1.1A3CFE870496Fp+121);
    try test_f64_floatFromInt_i128(make_ti(0x023479FD0E092DDF, 13), 0x1.1A3CFE870496Fp+121);
    try test_f64_floatFromInt_i128(make_ti(0x023479FD0E092DE0, 14), 0x1.1A3CFE870496Fp+121);
}

test f64_floatFromInt_u128 {
    try test_f64_floatFromInt_u128(0, 0.0);

    try test_f64_floatFromInt_u128(1, 1.0);
    try test_f64_floatFromInt_u128(2, 2.0);
    try test_f64_floatFromInt_u128(20, 20.0);

    try test_f64_floatFromInt_u128(0x7FFFFF8000000000, 0x1.FFFFFEp+62);
    try test_f64_floatFromInt_u128(0x7FFFFFFFFFFFF800, 0x1.FFFFFFFFFFFFEp+62);
    try test_f64_floatFromInt_u128(0x7FFFFF0000000000, 0x1.FFFFFCp+62);
    try test_f64_floatFromInt_u128(0x7FFFFFFFFFFFF000, 0x1.FFFFFFFFFFFFCp+62);

    try test_f64_floatFromInt_u128(make_uti(0x8000008000000000, 0), 0x1.000001p+127);
    try test_f64_floatFromInt_u128(make_uti(0x8000000000000800, 0), 0x1.0000000000001p+127);
    try test_f64_floatFromInt_u128(make_uti(0x8000010000000000, 0), 0x1.000002p+127);
    try test_f64_floatFromInt_u128(make_uti(0x8000000000001000, 0), 0x1.0000000000002p+127);

    try test_f64_floatFromInt_u128(make_uti(0x8000000000000000, 0), 0x1.000000p+127);
    try test_f64_floatFromInt_u128(make_uti(0x8000000000000001, 0), 0x1.0000000000000002p+127);

    try test_f64_floatFromInt_u128(0x0007FB72E8000000, 0x1.FEDCBAp+50);

    try test_f64_floatFromInt_u128(0x0007FB72EA000000, 0x1.FEDCBA8p+50);
    try test_f64_floatFromInt_u128(0x0007FB72EB000000, 0x1.FEDCBACp+50);
    try test_f64_floatFromInt_u128(0x0007FB72EBFFFFFF, 0x1.FEDCBAFFFFFFCp+50);
    try test_f64_floatFromInt_u128(0x0007FB72EC000000, 0x1.FEDCBBp+50);
    try test_f64_floatFromInt_u128(0x0007FB72E8000001, 0x1.FEDCBA0000004p+50);

    try test_f64_floatFromInt_u128(0x0007FB72E6000000, 0x1.FEDCB98p+50);
    try test_f64_floatFromInt_u128(0x0007FB72E7000000, 0x1.FEDCB9Cp+50);
    try test_f64_floatFromInt_u128(0x0007FB72E7FFFFFF, 0x1.FEDCB9FFFFFFCp+50);
    try test_f64_floatFromInt_u128(0x0007FB72E4000001, 0x1.FEDCB90000004p+50);
    try test_f64_floatFromInt_u128(0x0007FB72E4000000, 0x1.FEDCB9p+50);

    try test_f64_floatFromInt_u128(0x023479FD0E092DC0, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_u128(0x023479FD0E092DA1, 0x1.1A3CFE870496Dp+57);
    try test_f64_floatFromInt_u128(0x023479FD0E092DB0, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_u128(0x023479FD0E092DB8, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_u128(0x023479FD0E092DB6, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_u128(0x023479FD0E092DBF, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_u128(0x023479FD0E092DC1, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_u128(0x023479FD0E092DC7, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_u128(0x023479FD0E092DC8, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_u128(0x023479FD0E092DCF, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_u128(0x023479FD0E092DD0, 0x1.1A3CFE870496Ep+57);
    try test_f64_floatFromInt_u128(0x023479FD0E092DD1, 0x1.1A3CFE870496Fp+57);
    try test_f64_floatFromInt_u128(0x023479FD0E092DD8, 0x1.1A3CFE870496Fp+57);
    try test_f64_floatFromInt_u128(0x023479FD0E092DDF, 0x1.1A3CFE870496Fp+57);
    try test_f64_floatFromInt_u128(0x023479FD0E092DE0, 0x1.1A3CFE870496Fp+57);

    try test_f64_floatFromInt_u128(make_uti(0x023479FD0E092DC0, 0), 0x1.1A3CFE870496Ep+121);
    try test_f64_floatFromInt_u128(make_uti(0x023479FD0E092DA1, 1), 0x1.1A3CFE870496Dp+121);
    try test_f64_floatFromInt_u128(make_uti(0x023479FD0E092DB0, 2), 0x1.1A3CFE870496Ep+121);
    try test_f64_floatFromInt_u128(make_uti(0x023479FD0E092DB8, 3), 0x1.1A3CFE870496Ep+121);
    try test_f64_floatFromInt_u128(make_uti(0x023479FD0E092DB6, 4), 0x1.1A3CFE870496Ep+121);
    try test_f64_floatFromInt_u128(make_uti(0x023479FD0E092DBF, 5), 0x1.1A3CFE870496Ep+121);
    try test_f64_floatFromInt_u128(make_uti(0x023479FD0E092DC1, 6), 0x1.1A3CFE870496Ep+121);
    try test_f64_floatFromInt_u128(make_uti(0x023479FD0E092DC7, 7), 0x1.1A3CFE870496Ep+121);
    try test_f64_floatFromInt_u128(make_uti(0x023479FD0E092DC8, 8), 0x1.1A3CFE870496Ep+121);
    try test_f64_floatFromInt_u128(make_uti(0x023479FD0E092DCF, 9), 0x1.1A3CFE870496Ep+121);
    try test_f64_floatFromInt_u128(make_uti(0x023479FD0E092DD0, 0), 0x1.1A3CFE870496Ep+121);
    try test_f64_floatFromInt_u128(make_uti(0x023479FD0E092DD1, 11), 0x1.1A3CFE870496Fp+121);
    try test_f64_floatFromInt_u128(make_uti(0x023479FD0E092DD8, 12), 0x1.1A3CFE870496Fp+121);
    try test_f64_floatFromInt_u128(make_uti(0x023479FD0E092DDF, 13), 0x1.1A3CFE870496Fp+121);
    try test_f64_floatFromInt_u128(make_uti(0x023479FD0E092DE0, 14), 0x1.1A3CFE870496Fp+121);
}

fn test_f128_floatFromInt_i32(a: i32, expected: u128) !void {
    const r = f128_floatFromInt_i32(a);
    try std.testing.expect(@as(u128, @bitCast(r)) == expected);
}

fn test_f128_floatFromInt_u32(a: u32, expected_hi: u64, expected_lo: u64) !void {
    const x = f128_floatFromInt_u32(a);

    const x_repr: u128 = @bitCast(x);
    const x_hi: u64 = @intCast(x_repr >> 64);
    const x_lo: u64 = @truncate(x_repr);

    if (x_hi == expected_hi and x_lo == expected_lo) {
        return;
    }
    // nan repr
    else if (expected_hi == 0x7fff800000000000 and expected_lo == 0x0) {
        if ((x_hi & 0x7fff000000000000) == 0x7fff000000000000 and ((x_hi & 0xffffffffffff) > 0 or x_lo > 0)) {
            return;
        }
    }
    return error.TestFailure;
}

test f128_floatFromInt_i32 {
    try test_f128_floatFromInt_i32(0, 0);
    try test_f128_floatFromInt_i32(0x7FFFFFFF, 0x401dfffffffc00000000000000000000);
    try test_f128_floatFromInt_i32(0x12345678, 0x401b2345678000000000000000000000);
    try test_f128_floatFromInt_i32(-0x12345678, 0xc01b2345678000000000000000000000);
    try test_f128_floatFromInt_i32(@bitCast(@as(u32, @intCast(0xffffffff))), 0xbfff0000000000000000000000000000);
    try test_f128_floatFromInt_i32(@bitCast(@as(u32, @intCast(0x80000000))), 0xc01e0000000000000000000000000000);
}

test f128_floatFromInt_u32 {
    try test_f128_floatFromInt_u32(0x7fffffff, 0x401dfffffffc0000, 0x0);
    try test_f128_floatFromInt_u32(0, 0x0, 0x0);
    try test_f128_floatFromInt_u32(0xffffffff, 0x401efffffffe0000, 0x0);
    try test_f128_floatFromInt_u32(0x12345678, 0x401b234567800000, 0x0);
}

fn test_f128_floatFromInt_i64(a: i64, expected: f128) !void {
    const x = f128_floatFromInt_i64(a);
    try testing.expect(x == expected);
}

fn test_f128_floatFromInt_u64(a: u64, expected_hi: u64, expected_lo: u64) !void {
    const x = f128_floatFromInt_u64(a);

    const x_repr: u128 = @bitCast(x);
    const x_hi: u64 = @intCast(x_repr >> 64);
    const x_lo: u64 = @truncate(x_repr);

    if (x_hi == expected_hi and x_lo == expected_lo) {
        return;
    }
    // nan repr
    else if (expected_hi == 0x7fff800000000000 and expected_lo == 0x0) {
        if ((x_hi & 0x7fff000000000000) == 0x7fff000000000000 and ((x_hi & 0xffffffffffff) > 0 or x_lo > 0)) {
            return;
        }
    }
    return error.TestFailure;
}

test f128_floatFromInt_i64 {
    try test_f128_floatFromInt_i64(0x7fffffffffffffff, make_tf(0x403dffffffffffff, 0xfffc000000000000));
    try test_f128_floatFromInt_i64(0x123456789abcdef1, make_tf(0x403b23456789abcd, 0xef10000000000000));
    try test_f128_floatFromInt_i64(0x2, make_tf(0x4000000000000000, 0x0));
    try test_f128_floatFromInt_i64(0x1, make_tf(0x3fff000000000000, 0x0));
    try test_f128_floatFromInt_i64(0x0, make_tf(0x0, 0x0));
    try test_f128_floatFromInt_i64(@bitCast(@as(u64, 0xffffffffffffffff)), make_tf(0xbfff000000000000, 0x0));
    try test_f128_floatFromInt_i64(@bitCast(@as(u64, 0xfffffffffffffffe)), make_tf(0xc000000000000000, 0x0));
    try test_f128_floatFromInt_i64(-0x123456789abcdef1, make_tf(0xc03b23456789abcd, 0xef10000000000000));
    try test_f128_floatFromInt_i64(@bitCast(@as(u64, 0x8000000000000000)), make_tf(0xc03e000000000000, 0x0));
}

test f128_floatFromInt_u64 {
    try test_f128_floatFromInt_u64(0xffffffffffffffff, 0x403effffffffffff, 0xfffe000000000000);
    try test_f128_floatFromInt_u64(0xfffffffffffffffe, 0x403effffffffffff, 0xfffc000000000000);
    try test_f128_floatFromInt_u64(0x8000000000000000, 0x403e000000000000, 0x0);
    try test_f128_floatFromInt_u64(0x7fffffffffffffff, 0x403dffffffffffff, 0xfffc000000000000);
    try test_f128_floatFromInt_u64(0x123456789abcdef1, 0x403b23456789abcd, 0xef10000000000000);
    try test_f128_floatFromInt_u64(0x2, 0x4000000000000000, 0x0);
    try test_f128_floatFromInt_u64(0x1, 0x3fff000000000000, 0x0);
    try test_f128_floatFromInt_u64(0x0, 0x0, 0x0);
}

fn test_f128_floatFromInt_i128(a: i128, expected: f128) !void {
    const x = f128_floatFromInt_i128(a);
    try testing.expect(x == expected);
}

fn test_f128_floatFromInt_u128(a: u128, expected: f128) !void {
    const x = f128_floatFromInt_u128(a);
    try testing.expect(x == expected);
}

test f128_floatFromInt_i128 {
    try test_f128_floatFromInt_i128(0, 0.0);

    try test_f128_floatFromInt_i128(1, 1.0);
    try test_f128_floatFromInt_i128(2, 2.0);
    try test_f128_floatFromInt_i128(20, 20.0);
    try test_f128_floatFromInt_i128(-1, -1.0);
    try test_f128_floatFromInt_i128(-2, -2.0);
    try test_f128_floatFromInt_i128(-20, -20.0);

    try test_f128_floatFromInt_i128(0x7FFFFF8000000000, 0x1.FFFFFEp+62);
    try test_f128_floatFromInt_i128(0x7FFFFFFFFFFFF800, 0x1.FFFFFFFFFFFFEp+62);
    try test_f128_floatFromInt_i128(0x7FFFFF0000000000, 0x1.FFFFFCp+62);
    try test_f128_floatFromInt_i128(0x7FFFFFFFFFFFF000, 0x1.FFFFFFFFFFFFCp+62);

    try test_f128_floatFromInt_i128(make_ti(0x8000008000000000, 0), -0x1.FFFFFEp+126);
    try test_f128_floatFromInt_i128(make_ti(0x8000000000000800, 0), -0x1.FFFFFFFFFFFFEp+126);
    try test_f128_floatFromInt_i128(make_ti(0x8000010000000000, 0), -0x1.FFFFFCp+126);
    try test_f128_floatFromInt_i128(make_ti(0x8000000000001000, 0), -0x1.FFFFFFFFFFFFCp+126);

    try test_f128_floatFromInt_i128(make_ti(0x8000000000000000, 0), -0x1.000000p+127);
    try test_f128_floatFromInt_i128(make_ti(0x8000000000000001, 0), -0x1.FFFFFFFFFFFFFFFCp+126);

    try test_f128_floatFromInt_i128(0x0007FB72E8000000, 0x1.FEDCBAp+50);

    try test_f128_floatFromInt_i128(0x0007FB72EA000000, 0x1.FEDCBA8p+50);
    try test_f128_floatFromInt_i128(0x0007FB72EB000000, 0x1.FEDCBACp+50);
    try test_f128_floatFromInt_i128(0x0007FB72EBFFFFFF, 0x1.FEDCBAFFFFFFCp+50);
    try test_f128_floatFromInt_i128(0x0007FB72EC000000, 0x1.FEDCBBp+50);
    try test_f128_floatFromInt_i128(0x0007FB72E8000001, 0x1.FEDCBA0000004p+50);

    try test_f128_floatFromInt_i128(0x0007FB72E6000000, 0x1.FEDCB98p+50);
    try test_f128_floatFromInt_i128(0x0007FB72E7000000, 0x1.FEDCB9Cp+50);
    try test_f128_floatFromInt_i128(0x0007FB72E7FFFFFF, 0x1.FEDCB9FFFFFFCp+50);
    try test_f128_floatFromInt_i128(0x0007FB72E4000001, 0x1.FEDCB90000004p+50);
    try test_f128_floatFromInt_i128(0x0007FB72E4000000, 0x1.FEDCB9p+50);

    try test_f128_floatFromInt_i128(0x023479FD0E092DC0, 0x1.1A3CFE870496Ep+57);
    try test_f128_floatFromInt_i128(0x023479FD0E092DA1, 0x1.1A3CFE870496D08p+57);
    try test_f128_floatFromInt_i128(0x023479FD0E092DB0, 0x1.1A3CFE870496D8p+57);
    try test_f128_floatFromInt_i128(0x023479FD0E092DB8, 0x1.1A3CFE870496DCp+57);
    try test_f128_floatFromInt_i128(0x023479FD0E092DB6, 0x1.1A3CFE870496DBp+57);
    try test_f128_floatFromInt_i128(0x023479FD0E092DBF, 0x1.1A3CFE870496DF8p+57);
    try test_f128_floatFromInt_i128(0x023479FD0E092DC1, 0x1.1A3CFE870496E08p+57);
    try test_f128_floatFromInt_i128(0x023479FD0E092DC7, 0x1.1A3CFE870496E38p+57);
    try test_f128_floatFromInt_i128(0x023479FD0E092DC8, 0x1.1A3CFE870496E4p+57);
    try test_f128_floatFromInt_i128(0x023479FD0E092DCF, 0x1.1A3CFE870496E78p+57);
    try test_f128_floatFromInt_i128(0x023479FD0E092DD0, 0x1.1A3CFE870496E8p+57);
    try test_f128_floatFromInt_i128(0x023479FD0E092DD1, 0x1.1A3CFE870496E88p+57);
    try test_f128_floatFromInt_i128(0x023479FD0E092DD8, 0x1.1A3CFE870496ECp+57);
    try test_f128_floatFromInt_i128(0x023479FD0E092DDF, 0x1.1A3CFE870496EF8p+57);
    try test_f128_floatFromInt_i128(0x023479FD0E092DE0, 0x1.1A3CFE870496Fp+57);

    try test_f128_floatFromInt_i128(make_ti(0x023479FD0E092DC0, 0), 0x1.1A3CFE870496Ep+121);
    try test_f128_floatFromInt_i128(make_ti(0x023479FD0E092DA1, 1), 0x1.1A3CFE870496D08p+121);
    try test_f128_floatFromInt_i128(make_ti(0x023479FD0E092DB0, 2), 0x1.1A3CFE870496D8p+121);
    try test_f128_floatFromInt_i128(make_ti(0x023479FD0E092DB8, 3), 0x1.1A3CFE870496DCp+121);
    try test_f128_floatFromInt_i128(make_ti(0x023479FD0E092DB6, 4), 0x1.1A3CFE870496DBp+121);
    try test_f128_floatFromInt_i128(make_ti(0x023479FD0E092DBF, 5), 0x1.1A3CFE870496DF8p+121);
    try test_f128_floatFromInt_i128(make_ti(0x023479FD0E092DC1, 6), 0x1.1A3CFE870496E08p+121);
    try test_f128_floatFromInt_i128(make_ti(0x023479FD0E092DC7, 7), 0x1.1A3CFE870496E38p+121);
    try test_f128_floatFromInt_i128(make_ti(0x023479FD0E092DC8, 8), 0x1.1A3CFE870496E4p+121);
    try test_f128_floatFromInt_i128(make_ti(0x023479FD0E092DCF, 9), 0x1.1A3CFE870496E78p+121);
    try test_f128_floatFromInt_i128(make_ti(0x023479FD0E092DD0, 0), 0x1.1A3CFE870496E8p+121);
    try test_f128_floatFromInt_i128(make_ti(0x023479FD0E092DD1, 11), 0x1.1A3CFE870496E88p+121);
    try test_f128_floatFromInt_i128(make_ti(0x023479FD0E092DD8, 12), 0x1.1A3CFE870496ECp+121);
    try test_f128_floatFromInt_i128(make_ti(0x023479FD0E092DDF, 13), 0x1.1A3CFE870496EF8p+121);
    try test_f128_floatFromInt_i128(make_ti(0x023479FD0E092DE0, 14), 0x1.1A3CFE870496Fp+121);

    try test_f128_floatFromInt_i128(make_ti(0, 0xFFFFFFFFFFFFFFFF), 0x1.FFFFFFFFFFFFFFFEp+63);

    try test_f128_floatFromInt_i128(make_ti(0x123456789ABCDEF0, 0x123456789ABC2801), 0x1.23456789ABCDEF0123456789ABC3p+124);
    try test_f128_floatFromInt_i128(make_ti(0x123456789ABCDEF0, 0x123456789ABC3000), 0x1.23456789ABCDEF0123456789ABC3p+124);
    try test_f128_floatFromInt_i128(make_ti(0x123456789ABCDEF0, 0x123456789ABC37FF), 0x1.23456789ABCDEF0123456789ABC3p+124);
    try test_f128_floatFromInt_i128(make_ti(0x123456789ABCDEF0, 0x123456789ABC3800), 0x1.23456789ABCDEF0123456789ABC4p+124);
    try test_f128_floatFromInt_i128(make_ti(0x123456789ABCDEF0, 0x123456789ABC4000), 0x1.23456789ABCDEF0123456789ABC4p+124);
    try test_f128_floatFromInt_i128(make_ti(0x123456789ABCDEF0, 0x123456789ABC47FF), 0x1.23456789ABCDEF0123456789ABC4p+124);
    try test_f128_floatFromInt_i128(make_ti(0x123456789ABCDEF0, 0x123456789ABC4800), 0x1.23456789ABCDEF0123456789ABC4p+124);
    try test_f128_floatFromInt_i128(make_ti(0x123456789ABCDEF0, 0x123456789ABC4801), 0x1.23456789ABCDEF0123456789ABC5p+124);
    try test_f128_floatFromInt_i128(make_ti(0x123456789ABCDEF0, 0x123456789ABC57FF), 0x1.23456789ABCDEF0123456789ABC5p+124);
}

test f128_floatFromInt_u128 {
    try test_f128_floatFromInt_u128(0, 0.0);

    try test_f128_floatFromInt_u128(1, 1.0);
    try test_f128_floatFromInt_u128(2, 2.0);
    try test_f128_floatFromInt_u128(20, 20.0);

    try test_f128_floatFromInt_u128(0x7FFFFF8000000000, 0x1.FFFFFEp+62);
    try test_f128_floatFromInt_u128(0x7FFFFFFFFFFFF800, 0x1.FFFFFFFFFFFFEp+62);
    try test_f128_floatFromInt_u128(0x7FFFFF0000000000, 0x1.FFFFFCp+62);
    try test_f128_floatFromInt_u128(0x7FFFFFFFFFFFF000, 0x1.FFFFFFFFFFFFCp+62);
    try test_f128_floatFromInt_u128(0x7FFFFFFFFFFFFFFF, 0xF.FFFFFFFFFFFFFFEp+59);
    try test_f128_floatFromInt_u128(0xFFFFFFFFFFFFFFFE, 0xF.FFFFFFFFFFFFFFEp+60);
    try test_f128_floatFromInt_u128(0xFFFFFFFFFFFFFFFF, 0xF.FFFFFFFFFFFFFFFp+60);

    try test_f128_floatFromInt_u128(0x8000008000000000, 0x8.000008p+60);
    try test_f128_floatFromInt_u128(0x8000000000000800, 0x8.0000000000008p+60);
    try test_f128_floatFromInt_u128(0x8000010000000000, 0x8.00001p+60);
    try test_f128_floatFromInt_u128(0x8000000000001000, 0x8.000000000001p+60);

    try test_f128_floatFromInt_u128(0x8000000000000000, 0x8p+60);
    try test_f128_floatFromInt_u128(0x8000000000000001, 0x8.000000000000001p+60);

    try test_f128_floatFromInt_u128(0x0007FB72E8000000, 0x1.FEDCBAp+50);

    try test_f128_floatFromInt_u128(0x0007FB72EA000000, 0x1.FEDCBA8p+50);
    try test_f128_floatFromInt_u128(0x0007FB72EB000000, 0x1.FEDCBACp+50);
    try test_f128_floatFromInt_u128(0x0007FB72EBFFFFFF, 0x1.FEDCBAFFFFFFCp+50);
    try test_f128_floatFromInt_u128(0x0007FB72EC000000, 0x1.FEDCBBp+50);
    try test_f128_floatFromInt_u128(0x0007FB72E8000001, 0x1.FEDCBA0000004p+50);

    try test_f128_floatFromInt_u128(0x0007FB72E6000000, 0x1.FEDCB98p+50);
    try test_f128_floatFromInt_u128(0x0007FB72E7000000, 0x1.FEDCB9Cp+50);
    try test_f128_floatFromInt_u128(0x0007FB72E7FFFFFF, 0x1.FEDCB9FFFFFFCp+50);
    try test_f128_floatFromInt_u128(0x0007FB72E4000001, 0x1.FEDCB90000004p+50);
    try test_f128_floatFromInt_u128(0x0007FB72E4000000, 0x1.FEDCB9p+50);

    try test_f128_floatFromInt_u128(0x023479FD0E092DC0, 0x1.1A3CFE870496Ep+57);
    try test_f128_floatFromInt_u128(0x023479FD0E092DA1, 0x1.1A3CFE870496D08p+57);
    try test_f128_floatFromInt_u128(0x023479FD0E092DB0, 0x1.1A3CFE870496D8p+57);
    try test_f128_floatFromInt_u128(0x023479FD0E092DB8, 0x1.1A3CFE870496DCp+57);
    try test_f128_floatFromInt_u128(0x023479FD0E092DB6, 0x1.1A3CFE870496DBp+57);
    try test_f128_floatFromInt_u128(0x023479FD0E092DBF, 0x1.1A3CFE870496DF8p+57);
    try test_f128_floatFromInt_u128(0x023479FD0E092DC1, 0x1.1A3CFE870496E08p+57);
    try test_f128_floatFromInt_u128(0x023479FD0E092DC7, 0x1.1A3CFE870496E38p+57);
    try test_f128_floatFromInt_u128(0x023479FD0E092DC8, 0x1.1A3CFE870496E4p+57);
    try test_f128_floatFromInt_u128(0x023479FD0E092DCF, 0x1.1A3CFE870496E78p+57);
    try test_f128_floatFromInt_u128(0x023479FD0E092DD0, 0x1.1A3CFE870496E8p+57);
    try test_f128_floatFromInt_u128(0x023479FD0E092DD1, 0x1.1A3CFE870496E88p+57);
    try test_f128_floatFromInt_u128(0x023479FD0E092DD8, 0x1.1A3CFE870496ECp+57);
    try test_f128_floatFromInt_u128(0x023479FD0E092DDF, 0x1.1A3CFE870496EF8p+57);
    try test_f128_floatFromInt_u128(0x023479FD0E092DE0, 0x1.1A3CFE870496Fp+57);

    try test_f128_floatFromInt_u128(make_uti(0x023479FD0E092DC0, 0), 0x1.1A3CFE870496Ep+121);
    try test_f128_floatFromInt_u128(make_uti(0x023479FD0E092DA1, 1), 0x1.1A3CFE870496D08p+121);
    try test_f128_floatFromInt_u128(make_uti(0x023479FD0E092DB0, 2), 0x1.1A3CFE870496D8p+121);
    try test_f128_floatFromInt_u128(make_uti(0x023479FD0E092DB8, 3), 0x1.1A3CFE870496DCp+121);
    try test_f128_floatFromInt_u128(make_uti(0x023479FD0E092DB6, 4), 0x1.1A3CFE870496DBp+121);
    try test_f128_floatFromInt_u128(make_uti(0x023479FD0E092DBF, 5), 0x1.1A3CFE870496DF8p+121);
    try test_f128_floatFromInt_u128(make_uti(0x023479FD0E092DC1, 6), 0x1.1A3CFE870496E08p+121);
    try test_f128_floatFromInt_u128(make_uti(0x023479FD0E092DC7, 7), 0x1.1A3CFE870496E38p+121);
    try test_f128_floatFromInt_u128(make_uti(0x023479FD0E092DC8, 8), 0x1.1A3CFE870496E4p+121);
    try test_f128_floatFromInt_u128(make_uti(0x023479FD0E092DCF, 9), 0x1.1A3CFE870496E78p+121);
    try test_f128_floatFromInt_u128(make_uti(0x023479FD0E092DD0, 0), 0x1.1A3CFE870496E8p+121);
    try test_f128_floatFromInt_u128(make_uti(0x023479FD0E092DD1, 11), 0x1.1A3CFE870496E88p+121);
    try test_f128_floatFromInt_u128(make_uti(0x023479FD0E092DD8, 12), 0x1.1A3CFE870496ECp+121);
    try test_f128_floatFromInt_u128(make_uti(0x023479FD0E092DDF, 13), 0x1.1A3CFE870496EF8p+121);
    try test_f128_floatFromInt_u128(make_uti(0x023479FD0E092DE0, 14), 0x1.1A3CFE870496Fp+121);

    try test_f128_floatFromInt_u128(make_uti(0, 0xFFFFFFFFFFFFFFFF), 0x1.FFFFFFFFFFFFFFFEp+63);

    try test_f128_floatFromInt_u128(make_uti(0xFFFFFFFFFFFFFFFF, 0x0000000000000000), 0x1.FFFFFFFFFFFFFFFEp+127);
    try test_f128_floatFromInt_u128(make_uti(0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF), 0x1.0000000000000000p+128);

    try test_f128_floatFromInt_u128(make_uti(0x123456789ABCDEF0, 0x123456789ABC2801), 0x1.23456789ABCDEF0123456789ABC3p+124);
    try test_f128_floatFromInt_u128(make_uti(0x123456789ABCDEF0, 0x123456789ABC3000), 0x1.23456789ABCDEF0123456789ABC3p+124);
    try test_f128_floatFromInt_u128(make_uti(0x123456789ABCDEF0, 0x123456789ABC37FF), 0x1.23456789ABCDEF0123456789ABC3p+124);
    try test_f128_floatFromInt_u128(make_uti(0x123456789ABCDEF0, 0x123456789ABC3800), 0x1.23456789ABCDEF0123456789ABC4p+124);
    try test_f128_floatFromInt_u128(make_uti(0x123456789ABCDEF0, 0x123456789ABC4000), 0x1.23456789ABCDEF0123456789ABC4p+124);
    try test_f128_floatFromInt_u128(make_uti(0x123456789ABCDEF0, 0x123456789ABC47FF), 0x1.23456789ABCDEF0123456789ABC4p+124);
    try test_f128_floatFromInt_u128(make_uti(0x123456789ABCDEF0, 0x123456789ABC4800), 0x1.23456789ABCDEF0123456789ABC4p+124);
    try test_f128_floatFromInt_u128(make_uti(0x123456789ABCDEF0, 0x123456789ABC4801), 0x1.23456789ABCDEF0123456789ABC5p+124);
    try test_f128_floatFromInt_u128(make_uti(0x123456789ABCDEF0, 0x123456789ABC57FF), 0x1.23456789ABCDEF0123456789ABC5p+124);
}

fn make_ti(high: u64, low: u64) i128 {
    var result: u128 = high;
    result <<= 64;
    result |= low;
    return @bitCast(result);
}

fn make_uti(high: u64, low: u64) u128 {
    var result: u128 = high;
    result <<= 64;
    result |= low;
    return result;
}

fn make_tf(high: u64, low: u64) f128 {
    var result: u128 = high;
    result <<= 64;
    result |= low;
    return @bitCast(result);
}

test f16_floatFromInt_u32 {
    try testing.expect(f16_floatFromInt_u32(0) == 0.0);
    try testing.expect(f16_floatFromInt_u32(1) == 1.0);
    try testing.expect(f16_floatFromInt_u32(65504) == 65504);
    try testing.expect(f16_floatFromInt_u32(65504 + (1 << 4)) == math.inf(f16));
}

test f80_floatFromInt_u32 {
    try testing.expect(f80_floatFromInt_u32(0) == 0.0);
    try testing.expect(f80_floatFromInt_u32(1) == 1.0);
    try testing.expect(f80_floatFromInt_u32(math.maxInt(u24) + 0) == math.maxInt(u24));
}

test f80_floatFromInt_u64 {
    try testing.expect(f80_floatFromInt_u64(math.maxInt(u64) + 0) == math.maxInt(u64) + 0);
}

test f80_floatFromInt_i128 {
    try testing.expect(f80_floatFromInt_i128(-12) == -12);
}

test f80_floatFromInt_u128 {
    try testing.expect(f80_floatFromInt_u128(math.maxInt(u64) + 1) == math.maxInt(u64) + 1);

    try testing.expect(f80_floatFromInt_u128(math.maxInt(u64) + 0) == math.maxInt(u64));
    try testing.expect(f80_floatFromInt_u128(math.maxInt(u64) + 1) == math.maxInt(u64) + 1); // Exact
    try testing.expect(f80_floatFromInt_u128(math.maxInt(u64) + 2) == math.maxInt(u64) + 1); // Rounds down
    try testing.expect(f80_floatFromInt_u128(math.maxInt(u64) + 3) == math.maxInt(u64) + 3); // Tie - Exact
    try testing.expect(f80_floatFromInt_u128(math.maxInt(u64) + 4) == math.maxInt(u64) + 5); // Rounds up

    try testing.expect(f80_floatFromInt_u128(math.maxInt(u65) + 0) == math.maxInt(u65) + 1); // Rounds up
    try testing.expect(f80_floatFromInt_u128(math.maxInt(u65) + 1) == math.maxInt(u65) + 1); // Exact
    try testing.expect(f80_floatFromInt_u128(math.maxInt(u65) + 2) == math.maxInt(u65) + 1); // Rounds down
    try testing.expect(f80_floatFromInt_u128(math.maxInt(u65) + 3) == math.maxInt(u65) + 1); // Tie - Rounds down
    try testing.expect(f80_floatFromInt_u128(math.maxInt(u65) + 4) == math.maxInt(u65) + 5); // Rounds up
    try testing.expect(f80_floatFromInt_u128(math.maxInt(u65) + 5) == math.maxInt(u65) + 5); // Exact
}
