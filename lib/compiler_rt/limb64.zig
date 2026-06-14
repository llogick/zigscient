const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;
const maxInt = std.math.maxInt;
const minInt = std.math.minInt;
const divCeil = std.math.divCeil;

const builtin = @import("builtin");
const compiler_rt = @import("../compiler_rt.zig");
const symbol = @import("../compiler_rt.zig").symbol;

const endian = builtin.cpu.arch.endian();

inline fn limbGet(limbs: []const u64, i: usize) u64 {
    return switch (endian) {
        .little => limbs[i],
        .big => limbs[limbs.len - 1 - i],
    };
}

inline fn limbSet(limbs: []u64, i: usize, value: u64) void {
    switch (endian) {
        .little => limbs[i] = value,
        .big => limbs[limbs.len - 1 - i] = value,
    }
}

fn usedLimbCount(bits: u16) u16 {
    return divCeil(u16, bits, 64) catch unreachable;
}

fn limbCount(bits: u16) u16 {
    return @divExact(std.zig.target.intByteSize(&builtin.target, bits), 8);
}

fn varLimbs(ptr: [*]u64, bits: u16) []u64 {
    const limb_cnt = usedLimbCount(bits);
    const true_limb_cnt = limbCount(bits);
    return switch (endian) {
        .little => ptr[0..limb_cnt],
        .big => ptr[true_limb_cnt - limb_cnt .. true_limb_cnt],
    };
}

fn constLimbs(ptr: [*]const u64, bits: u16) []const u64 {
    const limb_cnt = usedLimbCount(bits);
    const true_limb_cnt = limbCount(bits);
    return switch (endian) {
        .little => ptr[0..limb_cnt],
        .big => ptr[true_limb_cnt - limb_cnt .. true_limb_cnt],
    };
}

fn fixLastLimb(out_ptr: [*]u64, is_signed: bool, bits: u16) void {
    const limb_cnt = usedLimbCount(bits);
    const true_limb_cnt = limbCount(bits);
    if (limb_cnt == true_limb_cnt) return;
    const true_out = out_ptr[0..true_limb_cnt];

    const ms = limbGet(true_out, limb_cnt - 1);
    const sign: u64 = if (!is_signed or @as(i64, @bitCast(ms)) >= 0) 0 else ~@as(u64, 0);
    for (limb_cnt..true_limb_cnt) |i| {
        limbSet(true_out, i, sign);
    }
}

fn Limbs(T: type) type {
    const int_info = @typeInfo(T).int;
    const limb_cnt = comptime limbCount(int_info.bits);
    return [limb_cnt]u64;
}

fn asLimbs(v: anytype) Limbs(@TypeOf(v)) {
    const T = @TypeOf(v);
    const int_info = @typeInfo(T).int;
    const limb_cnt = comptime limbCount(int_info.bits);
    const ET = @Int(int_info.signedness, limb_cnt * 64);
    return @bitCast(@as(ET, v));
}

fn limbWrap(limb: u64, is_signed: bool, bits: u16) u64 {
    assert(bits % 64 != 0);
    const pad_bits: u6 = @intCast(64 - bits % 64);
    if (!is_signed) {
        const s = limb << pad_bits;
        return s >> pad_bits;
    } else {
        const s = @as(i64, @bitCast(limb)) << pad_bits;
        return @bitCast(s >> pad_bits);
    }
}

comptime {
    symbol(&__addo_limb64, "__addo_limb64");
}

fn __addo_limb64(out_ptr: [*]u64, a_ptr: [*]const u64, b_ptr: [*]const u64, is_signed: bool, bits: u16) callconv(.c) bool {
    const limb_cnt = usedLimbCount(bits);
    const out = varLimbs(out_ptr, bits);
    const a = constLimbs(a_ptr, bits);
    const b = constLimbs(b_ptr, bits);

    var carry: u1 = 0;
    var i: usize = 0;
    while (i < limb_cnt - 1) : (i += 1) {
        const s1 = @addWithOverflow(limbGet(a, i), limbGet(b, i));
        const s2 = @addWithOverflow(s1[0], carry);
        carry = s1[1] | s2[1];
        limbSet(out, i, s2[0]);
    }

    const limb: u64 = b: {
        if (!is_signed) {
            const s1 = @addWithOverflow(limbGet(a, i), limbGet(b, i));
            const s2 = @addWithOverflow(s1[0], carry);
            carry = s1[1] | s2[1];
            break :b s2[0];
        } else {
            const as: i64 = @bitCast(limbGet(a, i));
            const bs: i64 = @bitCast(limbGet(b, i));
            const s1 = @addWithOverflow(as, bs);
            const s2 = @addWithOverflow(s1[0], carry);
            carry = s1[1] | s2[1];
            break :b @bitCast(s2[0]);
        }
    };

    if (bits % 64 == 0) {
        limbSet(out, i, limb);
        fixLastLimb(out_ptr, is_signed, bits);
        return carry != 0;
    } else {
        assert(carry == 0);
        const wrapped_limb = limbWrap(limb, is_signed, bits);
        limbSet(out, i, wrapped_limb);
        fixLastLimb(out_ptr, is_signed, bits);
        return wrapped_limb != limb;
    }
}

fn test__addo_limb64(comptime T: type, a: T, b: T, expected: struct { T, bool }) !void {
    const int_info = @typeInfo(T).int;
    const is_signed = int_info.signedness == .signed;

    var a_limbs = asLimbs(a);
    var b_limbs = asLimbs(b);
    var out: Limbs(T) = undefined;
    const overflow = __addo_limb64(&out, &a_limbs, &b_limbs, is_signed, int_info.bits);

    const expected_limbs = asLimbs(expected[0]);
    try testing.expectEqual(expected_limbs, out);
    try testing.expectEqual(expected[1], overflow);
}

test __addo_limb64 {
    try test__addo_limb64(u64, 1, 2, .{ 3, false });
    try test__addo_limb64(u64, maxInt(u64), 2, .{ 1, true });
    try test__addo_limb64(u65, maxInt(u65), 2, .{ 1, true });
    try test__addo_limb64(u255, 1, 2, .{ 3, false });

    try test__addo_limb64(i64, 1, 2, .{ 3, false });
    try test__addo_limb64(i64, maxInt(i64), 1, .{ minInt(i64), true });
    try test__addo_limb64(i65, maxInt(i65), 1, .{ minInt(i65), true });
    try test__addo_limb64(i255, -3, 2, .{ -1, false });

    try test__addo_limb64(u150, maxInt(u150), 2, .{ 1, true });
    try test__addo_limb64(i150, -3, 2, .{ -1, false });
}

comptime {
    symbol(&__subo_limb64, "__subo_limb64");
}

fn __subo_limb64(out_ptr: [*]u64, a_ptr: [*]const u64, b_ptr: [*]const u64, is_signed: bool, bits: u16) callconv(.c) bool {
    const limb_cnt = usedLimbCount(bits);
    const out = varLimbs(out_ptr, bits);
    const a = constLimbs(a_ptr, bits);
    const b = constLimbs(b_ptr, bits);

    var borrow: u1 = 0;
    var i: usize = 0;
    while (i < limb_cnt - 1) : (i += 1) {
        const s1 = @subWithOverflow(limbGet(a, i), limbGet(b, i));
        const s2 = @subWithOverflow(s1[0], borrow);
        borrow = s1[1] | s2[1];
        limbSet(out, i, s2[0]);
    }

    const limb: u64 = b: {
        if (!is_signed) {
            const s1 = @subWithOverflow(limbGet(a, i), limbGet(b, i));
            const s2 = @subWithOverflow(s1[0], borrow);
            borrow = s1[1] | s2[1];
            break :b s2[0];
        } else {
            const as: i64 = @bitCast(limbGet(a, i));
            const bs: i64 = @bitCast(limbGet(b, i));
            const s1 = @subWithOverflow(as, bs);
            const s2 = @subWithOverflow(s1[0], borrow);
            borrow = s1[1] | s2[1];
            break :b @bitCast(s2[0]);
        }
    };

    if (bits % 64 == 0) {
        limbSet(out, i, limb);
        fixLastLimb(out_ptr, is_signed, bits);
        return borrow != 0;
    } else {
        const wrapped_limb = limbWrap(limb, is_signed, bits);
        limbSet(out, i, wrapped_limb);
        fixLastLimb(out_ptr, is_signed, bits);
        return borrow != 0 or wrapped_limb != limb;
    }
}

fn test__subo_limb64(comptime T: type, a: T, b: T, expected: struct { T, bool }) !void {
    const int_info = @typeInfo(T).int;
    const is_signed = int_info.signedness == .signed;

    var a_limbs = asLimbs(a);
    var b_limbs = asLimbs(b);
    var out: Limbs(T) = undefined;
    const overflow = __subo_limb64(&out, &a_limbs, &b_limbs, is_signed, int_info.bits);

    const expected_limbs = asLimbs(expected[0]);
    try testing.expectEqual(expected_limbs, out);
    try testing.expectEqual(expected[1], overflow);
}

test __subo_limb64 {
    try test__subo_limb64(u64, 3, 2, .{ 1, false });
    try test__subo_limb64(u64, 0, 1, .{ maxInt(u64), true });
    try test__subo_limb64(u65, 0, 1, .{ maxInt(u65), true });
    try test__subo_limb64(u255, 3, 2, .{ 1, false });

    try test__subo_limb64(i64, 1, 2, .{ -1, false });
    try test__subo_limb64(i64, minInt(i64), 1, .{ maxInt(i64), true });
    try test__subo_limb64(i65, minInt(i65), 1, .{ maxInt(i65), true });
    try test__subo_limb64(i255, -1, 2, .{ -3, false });

    try test__subo_limb64(u150, 2, maxInt(u150), .{ 3, true });
    try test__subo_limb64(i150, -3, 2, .{ -5, false });
}

comptime {
    symbol(&__cmp_limb64, "__cmp_limb64");
}

// a < b  -> -1
// a == b ->  0
// a > b  ->  1
fn __cmp_limb64(a_ptr: [*]const u64, b_ptr: [*]const u64, is_signed: bool, bits: u16) callconv(.c) i8 {
    const limb_cnt = usedLimbCount(bits);
    const a = constLimbs(a_ptr, bits);
    const b = constLimbs(b_ptr, bits);

    var i: usize = 0;
    if (is_signed) {
        const sa: i64 = @bitCast(limbGet(a, limb_cnt - 1));
        const sb: i64 = @bitCast(limbGet(b, limb_cnt - 1));
        if (sa < sb) return -1;
        if (sa > sb) return 1;
        i += 1;
    }

    while (i < limb_cnt) : (i += 1) {
        const ai = limbGet(a, limb_cnt - 1 - i);
        const bi = limbGet(b, limb_cnt - 1 - i);
        if (ai < bi) return -1;
        if (ai > bi) return 1;
    }

    return 0;
}

fn test__cmp_limb64(comptime T: type, a: T, b: T, expected: i8) !void {
    const int_info = @typeInfo(T).int;
    const is_signed = int_info.signedness == .signed;

    var a_limbs = asLimbs(a);
    var b_limbs = asLimbs(b);
    const actual = __cmp_limb64(&a_limbs, &b_limbs, is_signed, int_info.bits);

    try testing.expectEqual(expected, actual);
}

test __cmp_limb64 {
    try test__cmp_limb64(u64, 1, 2, -1);
    try test__cmp_limb64(u64, 2, 2, 0);
    try test__cmp_limb64(u64, 3, 2, 1);

    try test__cmp_limb64(u65, 1, 2, -1);
    try test__cmp_limb64(u65, maxInt(u65), maxInt(u65), 0);
    try test__cmp_limb64(u65, maxInt(u65), maxInt(u65) - 1, 1);

    try test__cmp_limb64(u255, 1, 2, -1);
    try test__cmp_limb64(u255, 7, 7, 0);
    try test__cmp_limb64(u255, maxInt(u255), maxInt(u255) - 1, 1);

    try test__cmp_limb64(i64, -1, 0, -1);
    try test__cmp_limb64(i64, 0, 0, 0);
    try test__cmp_limb64(i64, 1, 0, 1);

    try test__cmp_limb64(i65, minInt(i65), maxInt(i65), -1);
    try test__cmp_limb64(i65, -1, -1, 0);
    try test__cmp_limb64(i65, maxInt(i65), minInt(i65), 1);

    try test__cmp_limb64(i255, -3, 2, -1);
    try test__cmp_limb64(i255, -5, -5, 0);
    try test__cmp_limb64(i255, 2, -3, 1);

    try test__cmp_limb64(u150, maxInt(u150) - 5, maxInt(u150) - 5, 0);
    try test__cmp_limb64(i150, minInt(i150), -5, -1);
}

comptime {
    symbol(&__and_limb64, "__and_limb64");
}

fn __and_limb64(out_ptr: [*]u64, a_ptr: [*]const u64, b_ptr: [*]const u64, bits: u16) callconv(.c) void {
    const limb_cnt = limbCount(bits);
    const out = out_ptr[0..limb_cnt];
    const a = a_ptr[0..limb_cnt];
    const b = b_ptr[0..limb_cnt];

    var i: usize = 0;
    while (i < limb_cnt) : (i += 1) {
        limbSet(out, i, limbGet(a, i) & limbGet(b, i));
    }
}

fn test__and_limb64(comptime T: type, a: T, b: T, expected: T) !void {
    const int_info = @typeInfo(T).int;

    var a_limbs = asLimbs(a);
    var b_limbs = asLimbs(b);
    var out: Limbs(T) = undefined;
    __and_limb64(&out, &a_limbs, &b_limbs, int_info.bits);

    const expected_limbs = asLimbs(expected);
    try testing.expectEqual(expected_limbs, out);
}

test __and_limb64 {
    try test__and_limb64(u64, 1, 2, 0);
    try test__and_limb64(u64, maxInt(u64), 2, 2);
    try test__and_limb64(u65, maxInt(u65), 2, 2);
    try test__and_limb64(u255, maxInt(u255), 7, 7);

    try test__and_limb64(i64, 1, 2, 0);
    try test__and_limb64(i64, -1, 2, 2);
    try test__and_limb64(i65, minInt(i65), -1, minInt(i65));
    try test__and_limb64(i255, -1, 2, 2);

    try test__and_limb64(u150, maxInt(u150), 7, 7);
    try test__and_limb64(i150, -2, 3, 2);
}

comptime {
    symbol(&__or_limb64, "__or_limb64");
}

fn __or_limb64(out_ptr: [*]u64, a_ptr: [*]const u64, b_ptr: [*]const u64, bits: u16) callconv(.c) void {
    const limb_cnt = limbCount(bits);
    const out = out_ptr[0..limb_cnt];
    const a = a_ptr[0..limb_cnt];
    const b = b_ptr[0..limb_cnt];

    var i: usize = 0;
    while (i < limb_cnt) : (i += 1) {
        limbSet(out, i, limbGet(a, i) | limbGet(b, i));
    }
}

fn test__or_limb64(comptime T: type, a: T, b: T, expected: T) !void {
    const int_info = @typeInfo(T).int;

    var a_limbs = asLimbs(a);
    var b_limbs = asLimbs(b);
    var out: Limbs(T) = undefined;
    __or_limb64(&out, &a_limbs, &b_limbs, int_info.bits);

    const expected_limbs = asLimbs(expected);
    try testing.expectEqual(expected_limbs, out);
}

test __or_limb64 {
    try test__or_limb64(u64, 1, 2, 3);
    try test__or_limb64(u64, maxInt(u64), 2, maxInt(u64));
    try test__or_limb64(u65, maxInt(u65), 2, maxInt(u65));
    try test__or_limb64(u255, 1, 2, 3);

    try test__or_limb64(i64, 1, 2, 3);
    try test__or_limb64(i64, -1, 2, -1);
    try test__or_limb64(i65, minInt(i65), 1, minInt(i65) + 1);
    try test__or_limb64(i255, -3, 2, -1);

    try test__or_limb64(u150, maxInt(u150) - 1, 3, maxInt(u150));
    try test__or_limb64(i150, -2, 3, -1);
}

comptime {
    symbol(&__xor_limb64, "__xor_limb64");
}

fn __xor_limb64(out_ptr: [*]u64, a_ptr: [*]const u64, b_ptr: [*]const u64, bits: u16) callconv(.c) void {
    const limb_cnt = limbCount(bits);
    const out = out_ptr[0..limb_cnt];
    const a = a_ptr[0..limb_cnt];
    const b = b_ptr[0..limb_cnt];

    var i: usize = 0;
    while (i < limb_cnt) : (i += 1) {
        limbSet(out, i, limbGet(a, i) ^ limbGet(b, i));
    }
}

fn test__xor_limb64(comptime T: type, a: T, b: T, expected: T) !void {
    const int_info = @typeInfo(T).int;

    var a_limbs = asLimbs(a);
    var b_limbs = asLimbs(b);
    var out: Limbs(T) = undefined;
    __xor_limb64(&out, &a_limbs, &b_limbs, int_info.bits);

    const expected_limbs = asLimbs(expected);
    try testing.expectEqual(expected_limbs, out);
}

test __xor_limb64 {
    try test__xor_limb64(u64, 1, 2, 3);
    try test__xor_limb64(u64, 3, 2, 1);
    try test__xor_limb64(u65, maxInt(u65), 2, maxInt(u65) - 2);
    try test__xor_limb64(u255, 7, 3, 4);

    try test__xor_limb64(i64, 3, 2, 1);
    try test__xor_limb64(i64, -1, 2, -3);
    try test__xor_limb64(i65, minInt(i65), -1, maxInt(i65));
    try test__xor_limb64(i255, -3, 2, -1);

    try test__xor_limb64(u150, maxInt(u150) - 1, 3, maxInt(u150) - 2);
    try test__xor_limb64(i150, -2, 3, -3);
}

comptime {
    symbol(&__not_limb64, "__not_limb64");
}

fn __not_limb64(out_ptr: [*]u64, a_ptr: [*]const u64, is_signed: bool, bits: u16) callconv(.c) void {
    const limb_cnt = usedLimbCount(bits);
    const out = varLimbs(out_ptr, bits);
    const a = constLimbs(a_ptr, bits);

    var i: usize = 0;
    while (i < limb_cnt - 1) : (i += 1) {
        limbSet(out, i, ~limbGet(a, i));
    }

    var limb: u64 = ~limbGet(a, i);
    if (!is_signed and bits % 64 != 0) {
        limb = limbWrap(limb, is_signed, bits);
    }
    limbSet(out, i, limb);
    fixLastLimb(out_ptr, is_signed, bits);
}

fn test__not_limb64(comptime T: type, a: T, expected: T) !void {
    const int_info = @typeInfo(T).int;
    const is_signed = int_info.signedness == .signed;

    var a_limbs = asLimbs(a);
    var out: Limbs(T) = undefined;
    __not_limb64(&out, &a_limbs, is_signed, int_info.bits);

    const expected_limbs = asLimbs(expected);
    try testing.expectEqual(expected_limbs, out);
}

test __not_limb64 {
    try test__not_limb64(u64, 1, maxInt(u64) - 1);
    try test__not_limb64(u64, 3, maxInt(u64) - 3);
    try test__not_limb64(u65, maxInt(u65), 0);
    try test__not_limb64(u255, 7, maxInt(u255) - 7);

    try test__not_limb64(i64, 3, -4);
    try test__not_limb64(i64, -1, 0);
    try test__not_limb64(i65, minInt(i65), maxInt(i65));
    try test__not_limb64(i255, -3, 2);

    try test__not_limb64(u150, maxInt(u150), 0);
    try test__not_limb64(i150, maxInt(i150), minInt(i150));
}

comptime {
    symbol(&__shlo_limb64, "__shlo_limb64");
}

fn __shlo_limb64(out_ptr: [*]u64, a_ptr: [*]const u64, shift: u16, is_signed: bool, bits: u16) callconv(.c) bool {
    const limb_cnt = usedLimbCount(bits);
    const out = varLimbs(out_ptr, bits);
    const a = constLimbs(a_ptr, bits);

    assert(shift < bits);

    const limb_shift = shift / 64;
    const bit_shift = shift % 64;

    var carry: u64 = 0;
    var i: usize = 0;
    while (i < limb_cnt - 1) : (i += 1) {
        if (i < limb_shift) {
            limbSet(out, i, 0);
        } else {
            const limb = limbGet(a, i - limb_shift);
            limbSet(out, i, (limb << @intCast(bit_shift)) | carry);
            carry = if (bit_shift != 0) (limb >> @intCast(64 - bit_shift)) else 0;
        }
    }

    const limb = limbGet(a, i - limb_shift);
    const raw_last = (limb << @intCast(bit_shift)) | carry;
    carry = if (bit_shift != 0) (limb >> @intCast(64 - bit_shift)) else 0;

    const last = if (bits % 64 == 0) raw_last else limbWrap(raw_last, is_signed, bits);
    limbSet(out, i, last);

    const sign_extend: u64 = if (is_signed and (last >> 63) == 1) ~@as(u64, 0) else 0;
    const expected_carry: u64 = if (bit_shift == 0) 0 else sign_extend >> @intCast(64 - bit_shift);

    var overflow = carry != expected_carry;
    if (bits % 64 != 0) {
        overflow = overflow or raw_last != last;
    }

    var j = limb_cnt - limb_shift;
    while (j < limb_cnt) : (j += 1) {
        overflow = overflow or limbGet(a, j) != sign_extend;
    }

    fixLastLimb(out_ptr, is_signed, bits);
    return overflow;
}

fn test__shlo_limb64(comptime T: type, a: T, shift: u16, expected: struct { T, bool }) !void {
    const int_info = @typeInfo(T).int;
    const is_signed = int_info.signedness == .signed;

    var a_limbs = asLimbs(a);
    var out: Limbs(T) = undefined;
    const overflow = __shlo_limb64(&out, &a_limbs, shift, is_signed, int_info.bits);

    const expected_limbs = asLimbs(expected[0]);
    try testing.expectEqual(expected_limbs, out);
    try testing.expectEqual(expected[1], overflow);
}

test __shlo_limb64 {
    try test__shlo_limb64(u64, 0x1234_5678_9ABC_DEF0, 4, .{ 0x2345_6789_ABCD_EF00, true });
    try test__shlo_limb64(u64, 0x8000_0000_0000_0001, 63, .{ 0x8000_0000_0000_0000, true });
    try test__shlo_limb64(u65, 1, 64, .{ 0x1_0000_0000_0000_0000, false });
    try test__shlo_limb64(u65, 0x1_0000_0000_0000_0000, 1, .{ 0, true });
    try test__shlo_limb64(u128, 0x1234_5678_9ABC_DEF0_1234_5678_9ABC_DEF0, 4, .{ 0x2345_6789_ABCD_EF01_2345_6789_ABCD_EF00, true });
    try test__shlo_limb64(u255, maxInt(u255), 1, .{ maxInt(u255) - 1, true });
    try test__shlo_limb64(u633, 1 << 299, 333, .{ 1 << 632, false });
    try test__shlo_limb64(u633, 1 << 300, 333, .{ 0, true });
    try test__shlo_limb64(u633, 1 << 298, 333, .{ 1 << 631, false });

    try test__shlo_limb64(i64, -2, 1, .{ -4, false });
    try test__shlo_limb64(i64, minInt(i64), 1, .{ 0, true });
    try test__shlo_limb64(i64, minInt(i64), 63, .{ 0, true });
    try test__shlo_limb64(i65, minInt(i63), 1, .{ minInt(i64), false });
    try test__shlo_limb64(i65, -1, 17, .{ -1 << 17, false });
    try test__shlo_limb64(i65, -3, 64, .{ -1 << 64, true });
    try test__shlo_limb64(i128, -0x1234_5678_9ABC_DEF0_1234_5678_9ABC_DEF0, 4, .{ -0x2345_6789_ABCD_EF01_2345_6789_ABCD_EF00, true });
    try test__shlo_limb64(i255, -3, 1, .{ -6, false });
    try test__shlo_limb64(i633, 1 << 298, 333, .{ 1 << 631, false });
    try test__shlo_limb64(i633, 1 << 299, 333, .{ minInt(i633), true });
    try test__shlo_limb64(i633, 1 << 300, 333, .{ 0, true });
    try test__shlo_limb64(i633, 1 << 297, 333, .{ 1 << 630, false });
    try test__shlo_limb64(i633, -1 << 299, 333, .{ -1 << 632, false });
    try test__shlo_limb64(i633, -1 << 300, 333, .{ 0, true });
    try test__shlo_limb64(i633, -1 << 298, 333, .{ -1 << 631, false });

    try test__shlo_limb64(u150, maxInt(u150), 1, .{ maxInt(u150) - 1, true });
    try test__shlo_limb64(i150, -3, 1, .{ -6, false });
}

comptime {
    symbol(&__shr_limb64, "__shr_limb64");
}

fn __shr_limb64(out_ptr: [*]u64, a_ptr: [*]const u64, shift: u16, is_signed: bool, bits: u16) callconv(.c) void {
    const limb_cnt = usedLimbCount(bits);
    const out = varLimbs(out_ptr, bits);
    const a = constLimbs(a_ptr, bits);

    assert(shift < bits);

    const limb_shift = shift / 64;
    const bit_shift = shift % 64;

    const ms = limbGet(a, limb_cnt - 1);
    const sign_extend: u64 = if (is_signed and (ms >> 63) == 1) ~@as(u64, 0) else 0;

    var carry: u64 = if (bit_shift != 0) (sign_extend << @intCast(64 - bit_shift)) else 0;
    var i: usize = 0;
    while (i < limb_cnt) : (i += 1) {
        const j = limb_cnt - 1 - i;
        if (i < limb_shift) {
            limbSet(out, j, sign_extend);
        } else {
            const limb = limbGet(a, j + limb_shift);
            limbSet(out, j, (limb >> @intCast(bit_shift)) | carry);
            carry = if (bit_shift != 0) (limb << @intCast(64 - bit_shift)) else 0;
        }
    }

    fixLastLimb(out_ptr, is_signed, bits);
}

fn test__shr_limb64(comptime T: type, a: T, shift: u16, expected: T) !void {
    const int_info = @typeInfo(T).int;
    const is_signed = int_info.signedness == .signed;

    var a_limbs = asLimbs(a);
    var out: Limbs(T) = undefined;
    __shr_limb64(&out, &a_limbs, shift, is_signed, int_info.bits);

    const expected_limbs = asLimbs(expected);
    try testing.expectEqual(expected_limbs, out);
}

test __shr_limb64 {
    try test__shr_limb64(u64, 0x1234_5678_9ABC_DEF0, 4, 0x0123_4567_89AB_CDEF);
    try test__shr_limb64(u64, 0x8000_0000_0000_0001, 63, 1);
    try test__shr_limb64(u65, 0x1_0000_0000_0000_0000, 64, 1);
    try test__shr_limb64(u65, 0x1_0000_0000_0000_0001, 1, 0x0_8000_0000_0000_0000);
    try test__shr_limb64(u128, 0x1234_5678_9ABC_DEF0_1234_5678_9ABC_DEF0, 4, 0x0123_4567_89AB_CDEF_0123_4567_89AB_CDEF);
    try test__shr_limb64(u255, maxInt(u255), 1, maxInt(u254));
    try test__shr_limb64(u633, 1 << 333, 333, 1);
    try test__shr_limb64(u633, 1 << 334, 333, 2);
    try test__shr_limb64(u633, 1 << 332, 333, 0);

    try test__shr_limb64(i64, -2, 1, -1);
    try test__shr_limb64(i64, minInt(i64), 63, -1);
    try test__shr_limb64(i65, minInt(i65), 1, minInt(i65) | (1 << 63));
    try test__shr_limb64(i65, -1, 17, -1);
    try test__shr_limb64(i128, -0x1234_5678_9ABC_DEF0_1234_5678_9ABC_DEF0, 4, -0x0123_4567_89AB_CDEF_0123_4567_89AB_CDEF);
    try test__shr_limb64(i255, -3, 1, -2);
    try test__shr_limb64(i633, 1 << 333, 333, 1);
    try test__shr_limb64(i633, 1 << 334, 333, 2);
    try test__shr_limb64(i633, 1 << 332, 333, 0);
    try test__shr_limb64(i633, -1 << 333, 333, -1);
    try test__shr_limb64(i633, -1 << 334, 333, -2);
    try test__shr_limb64(i633, -1 << 332, 333, -1);

    try test__shr_limb64(u150, maxInt(u150), 1, maxInt(u149));
    try test__shr_limb64(i150, -3, 1, -2);
}

comptime {
    symbol(&__clz_limb64, "__clz_limb64");
}

fn __clz_limb64(a_ptr: [*]const u64, bits: u16) callconv(.c) u16 {
    const limb_cnt = usedLimbCount(bits);
    const a = constLimbs(a_ptr, bits);

    var res: u16 = 0;
    var i: usize = 0;

    if (bits % 64 != 0) {
        const limb = limbGet(a, limb_cnt - 1);
        if (limb == 0) {
            res += bits % 64;
        } else {
            return @clz(limb << @intCast(64 - bits % 64));
        }
        i += 1;
    }

    while (i < limb_cnt) : (i += 1) {
        const j = limb_cnt - 1 - i;
        const limb = limbGet(a, j);
        if (limb == 0) {
            res += 64;
        } else {
            res += @clz(limb);
            break;
        }
    }

    return res;
}

fn test__clz_limb64(comptime T: type, a: T, expected: u16) !void {
    const int_info = @typeInfo(T).int;

    var a_limbs = asLimbs(a);
    const out = __clz_limb64(&a_limbs, int_info.bits);

    try testing.expectEqual(expected, out);
}

test __clz_limb64 {
    try test__clz_limb64(u64, 0, 64);
    try test__clz_limb64(u65, 1 << 64, 0);
    try test__clz_limb64(u65, 1 << 9, 55);
    try test__clz_limb64(u128, 1 << 31, 96);
    try test__clz_limb64(u255, 1 << 62, 192);

    try test__clz_limb64(i64, -1, 0);
    try test__clz_limb64(i65, minInt(i65), 0);
    try test__clz_limb64(i65, 1 << 32, 32);
    try test__clz_limb64(i128, 0, 128);
    try test__clz_limb64(i255, 1 << 130, 124);

    try test__clz_limb64(u150, 1 << 31, 118);
    try test__clz_limb64(i150, maxInt(u65) - 1, 85);
}

comptime {
    symbol(&__ctz_limb64, "__ctz_limb64");
}

fn __ctz_limb64(a_ptr: [*]const u64, bits: u16) callconv(.c) u16 {
    const limb_cnt = usedLimbCount(bits);
    const a = constLimbs(a_ptr, bits);

    var res: u16 = 0;
    var i: usize = 0;
    while (i < limb_cnt - 1) : (i += 1) {
        const limb = limbGet(a, i);
        if (limb == 0) {
            res += 64;
        } else {
            res += @ctz(limb);
            return res;
        }
    }

    const limb = limbGet(a, i);
    if (bits % 64 != 0 and limb == 0) {
        res += bits % 64;
    } else {
        res += @ctz(limb);
    }

    return res;
}

fn test__ctz_limb64(comptime T: type, a: T, expected: u16) !void {
    const int_info = @typeInfo(T).int;

    var a_limbs = asLimbs(a);
    const out = __ctz_limb64(&a_limbs, int_info.bits);

    try testing.expectEqual(expected, out);
}

test __ctz_limb64 {
    try test__ctz_limb64(u64, 1 << 17, 17);
    try test__ctz_limb64(u65, 1 << 64, 64);
    try test__ctz_limb64(u65, 0, 65);
    try test__ctz_limb64(u128, 1 << 100, 100);
    try test__ctz_limb64(u255, 1 << 200, 200);

    try test__ctz_limb64(i64, -1 << 9, 9);
    try test__ctz_limb64(i65, minInt(i65), 64);
    try test__ctz_limb64(i65, 0, 65);
    try test__ctz_limb64(i128, -1 << 73, 73);
    try test__ctz_limb64(i255, 1 << 130, 130);

    try test__ctz_limb64(u150, 1 << 101, 101);
    try test__ctz_limb64(i150, -1 << 74, 74);
}

comptime {
    symbol(&__popcount_limb64, "__popcount_limb64");
}

fn __popcount_limb64(a_ptr: [*]const u64, bits: u16) callconv(.c) u16 {
    const limb_cnt = usedLimbCount(bits);
    const a = constLimbs(a_ptr, bits);

    var res: u16 = 0;
    var i: usize = 0;
    while (i < limb_cnt - 1) : (i += 1) {
        res += @popCount(limbGet(a, i));
    }

    var limb = limbGet(a, i);
    if (bits % 64 != 0) {
        limb <<= @intCast(64 - bits % 64);
    }
    res += @popCount(limb);

    return res;
}

fn test__popcount_limb64(comptime T: type, a: T, expected: u16) !void {
    const int_info = @typeInfo(T).int;

    var a_limbs = asLimbs(a);
    const out = __popcount_limb64(&a_limbs, int_info.bits);

    try testing.expectEqual(expected, out);
}

test __popcount_limb64 {
    try test__popcount_limb64(u64, 0xF0F0_0000_0000_0001, 9);
    try test__popcount_limb64(u65, 1 << 64, 1);
    try test__popcount_limb64(u65, maxInt(u65), 65);
    try test__popcount_limb64(u128, (1 << 100) | (1 << 5) | 1, 3);
    try test__popcount_limb64(u255, maxInt(u255), 255);

    try test__popcount_limb64(i64, -1, 64);
    try test__popcount_limb64(i65, minInt(i65), 1);
    try test__popcount_limb64(i65, -1, 65);
    try test__popcount_limb64(i128, -1 << 7, 121);
    try test__popcount_limb64(i255, -1 << 200, 55);

    try test__popcount_limb64(u150, (1 << 149) | (1 << 65) | 1, 3);
    try test__popcount_limb64(i150, -1 << 7, 143);
}

comptime {
    symbol(&__bitreverse_limb64, "__bitreverse_limb64");
}

fn __bitreverse_limb64(out_ptr: [*]u64, a_ptr: [*]const u64, is_signed: bool, bits: u16) callconv(.c) void {
    const limb_cnt = usedLimbCount(bits);
    const out = varLimbs(out_ptr, bits);
    const a = constLimbs(a_ptr, bits);

    var i: usize = 0;
    while (i < limb_cnt) : (i += 1) {
        const j = limb_cnt - 1 - i;
        limbSet(out, j, @bitReverse(limbGet(a, i)));
    }

    if (bits % 64 != 0) {
        __shr_limb64(out_ptr, out_ptr, 64 - bits % 64, is_signed, bits);
    }
    fixLastLimb(out_ptr, is_signed, bits);
}

fn test__bitreverse_limb64(comptime T: type, a: T, expected: T) !void {
    const int_info = @typeInfo(T).int;
    const is_signed = int_info.signedness == .signed;

    var a_limbs = asLimbs(a);
    var out: Limbs(T) = undefined;
    __bitreverse_limb64(&out, &a_limbs, is_signed, int_info.bits);

    const expected_limbs = asLimbs(expected);
    try testing.expectEqual(expected_limbs, out);
}

test __bitreverse_limb64 {
    try test__bitreverse_limb64(u64, 1 << 7, 1 << 56);
    try test__bitreverse_limb64(u65, 1 << 64, 1);
    try test__bitreverse_limb64(u65, 1 << 9, 1 << 55);
    try test__bitreverse_limb64(u128, 1 << 100, 1 << 27);
    try test__bitreverse_limb64(u255, 1 << 200, 1 << 54);

    try test__bitreverse_limb64(i64, -1, -1);
    try test__bitreverse_limb64(i65, 1 << 32, 1 << 32);
    try test__bitreverse_limb64(i65, minInt(i65), 1);
    try test__bitreverse_limb64(i128, 1 << 63, 1 << 64);
    try test__bitreverse_limb64(i255, 1 << 130, 1 << 124);

    try test__bitreverse_limb64(u150, 1 << 9, 1 << 140);
    try test__bitreverse_limb64(i150, minInt(i150), 1);
}

comptime {
    symbol(&__byteswap_limb64, "__byteswap_limb64");
}

fn __byteswap_limb64(out_ptr: [*]u64, a_ptr: [*]const u64, is_signed: bool, bits: u16) callconv(.c) void {
    const limb_cnt = usedLimbCount(bits);
    const out = varLimbs(out_ptr, bits);
    const a = constLimbs(a_ptr, bits);

    assert(bits % 8 == 0);

    var i: usize = 0;
    while (i < limb_cnt) : (i += 1) {
        const j = limb_cnt - 1 - i;
        limbSet(out, j, @byteSwap(limbGet(a, i)));
    }

    if (bits % 64 != 0) {
        __shr_limb64(out_ptr, out_ptr, 64 - bits % 64, is_signed, bits);
    }
    fixLastLimb(out_ptr, is_signed, bits);
}

fn test__byteswap_limb64(comptime T: type, a: T, expected: T) !void {
    const int_info = @typeInfo(T).int;
    const is_signed = int_info.signedness == .signed;

    var a_limbs = asLimbs(a);
    var out: Limbs(T) = undefined;
    __byteswap_limb64(&out, &a_limbs, is_signed, int_info.bits);

    const expected_limbs = asLimbs(expected);
    try testing.expectEqual(expected_limbs, out);
}

test __byteswap_limb64 {
    try test__byteswap_limb64(u64, 0x0123_4567_89AB_CDEF, 0xEFCD_AB89_6745_2301);
    try test__byteswap_limb64(u72, 0x01_23_45_67_89_AB_CD_EF_11, 0x11_EF_CD_AB_89_67_45_23_01);
    try test__byteswap_limb64(u128, 1 << 72, 1 << 48);
    try test__byteswap_limb64(u248, 1, 1 << 240);
    try test__byteswap_limb64(u256, 1 << 120, 1 << 128);

    try test__byteswap_limb64(i64, minInt(i64), 128);
    try test__byteswap_limb64(i72, 1, 1 << 64);
    try test__byteswap_limb64(i72, -1, -1);
    try test__byteswap_limb64(i128, 1 << 56, 1 << 64);
    try test__byteswap_limb64(i248, minInt(i248), 128);

    try test__byteswap_limb64(u152, 1, 1 << 144);
    try test__byteswap_limb64(i152, 1 << 56, 1 << 88);
}

comptime {
    symbol(&__mulo_limb64, "__mulo_limb64");
}

inline fn add3(x: *[3]u64, start: usize, v0: u64) void {
    var i = start;
    var v = v0;
    while (i < 3) : (i += 1) {
        const s = @addWithOverflow(x[i], v);
        x[i] = s[0];
        if (s[1] == 0) break;
        v = 1;
    }
}

fn mulwide(a: u64, b: u64) [2]u64 {
    const muldXi = @import("mulXi3.zig").muldXi;
    const limbs: [2]u64 = @bitCast(muldXi(u64, a, b));
    return switch (endian) {
        .little => limbs,
        .big => .{ limbs[1], limbs[0] },
    };
}

fn __mulo_limb64(out_ptr: [*]u64, a_ptr: [*]const u64, b_ptr: [*]const u64, is_signed: bool, bits: u16) callconv(.c) bool {
    const limb_cnt = usedLimbCount(bits);

    const out = varLimbs(out_ptr, bits);
    const a = constLimbs(a_ptr, bits);
    const b = constLimbs(b_ptr, bits);

    @memset(out, 0);

    const all_ones = ~@as(u64, 0);
    const a_neg = is_signed and ((limbGet(a, limb_cnt - 1) >> 63) != 0);
    const b_neg = is_signed and ((limbGet(b, limb_cnt - 1) >> 63) != 0);

    var carry: [3]u64 = @splat(0);
    var hi_zero = true;
    var hi_ones = true;
    var hi_borrow: u1 = 0;
    var raw_last: u64 = 0;

    var k: usize = 0;
    while (k < 2 * limb_cnt) : (k += 1) {
        var acc = carry;

        var i: usize = if (k < limb_cnt) 0 else k - (limb_cnt - 1);
        while (i < limb_cnt and i <= k) : (i += 1) {
            const j = k - i;
            if (j >= limb_cnt) continue;

            const p = mulwide(limbGet(a, i), limbGet(b, j));
            add3(&acc, 0, p[0]);
            add3(&acc, 1, p[1]);
        }

        var limb = acc[0];
        if (k < limb_cnt) {
            limbSet(out, k, limb);
            if (k == limb_cnt - 1) raw_last = limb;
        } else {
            if (is_signed) {
                const h = k - limb_cnt;

                const s0 = @subWithOverflow(limb, if (a_neg) limbGet(b, h) else 0);
                const s1 = @subWithOverflow(s0[0], if (b_neg) limbGet(a, h) else 0);
                const s2 = @subWithOverflow(s1[0], hi_borrow);

                limb = s2[0];
                hi_borrow = @intFromBool(s0[1] != 0 or s1[1] != 0 or s2[1] != 0);
            }

            hi_zero = hi_zero and limb == 0;
            hi_ones = hi_ones and limb == all_ones;
        }

        carry = .{ acc[1], acc[2], 0 };
    }

    const last = if (bits % 64 == 0) raw_last else limbWrap(raw_last, is_signed, bits);
    if (bits % 64 != 0) {
        limbSet(out, limb_cnt - 1, last);
    }

    fixLastLimb(out_ptr, is_signed, bits);

    if (!is_signed) {
        return !hi_zero or raw_last != last;
    }

    const sign_extend: u64 = if ((last >> 63) == 1) all_ones else 0;
    return (raw_last != last) or if (sign_extend == 0) !hi_zero else !hi_ones;
}

fn test__mulo_limb64(comptime T: type, a: T, b: T, expected: struct { T, bool }) !void {
    const int_info = @typeInfo(T).int;
    const is_signed = int_info.signedness == .signed;

    var a_limbs = asLimbs(a);
    var b_limbs = asLimbs(b);
    var out: Limbs(T) = undefined;
    const overflow = __mulo_limb64(&out, &a_limbs, &b_limbs, is_signed, int_info.bits);

    const expected_limbs = asLimbs(expected[0]);
    try testing.expectEqual(expected_limbs, out);
    try testing.expectEqual(expected[1], overflow);
}

test __mulo_limb64 {
    try test__mulo_limb64(u64, 3, 5, .{ 15, false });
    try test__mulo_limb64(u64, maxInt(u64), 2, .{ maxInt(u64) - 1, true });
    try test__mulo_limb64(u65, 1 << 32, 1 << 32, .{ 1 << 64, false });
    try test__mulo_limb64(u65, 1 << 64, 2, .{ 0, true });
    try test__mulo_limb64(u128, 1 << 80, 1 << 40, .{ 1 << 120, false });
    try test__mulo_limb64(u128, 1 << 100, 1 << 40, .{ 0, true });
    try test__mulo_limb64(u255, 7, 9, .{ 63, false });
    try test__mulo_limb64(u255, maxInt(u255), 2, .{ maxInt(u255) - 1, true });

    try test__mulo_limb64(i64, -3, 2, .{ -6, false });
    try test__mulo_limb64(i64, maxInt(i64), 2, .{ -2, true });
    try test__mulo_limb64(i65, 1 << 63, 2, .{ minInt(i65), true });
    try test__mulo_limb64(i65, -1 << 32, 1 << 16, .{ -1 << 48, false });
    try test__mulo_limb64(i128, 1 << 100, 1 << 27, .{ minInt(i128), true });
    try test__mulo_limb64(i128, -1 << 80, 1 << 40, .{ -1 << 120, false });
    try test__mulo_limb64(i255, -3, 2, .{ -6, false });
    try test__mulo_limb64(i255, maxInt(i255), 2, .{ -2, true });

    try test__mulo_limb64(u200, 0, maxInt(u200), .{ 0, false });
    try test__mulo_limb64(u200, 1, maxInt(u200), .{ maxInt(u200), false });
    try test__mulo_limb64(u200, 1 << 100, 1 << 99, .{ 1 << 199, false });
    try test__mulo_limb64(u200, 1 << 100, 1 << 100, .{ 0, true });
    try test__mulo_limb64(u200, maxInt(u200), maxInt(u200), .{ 1, true });

    try test__mulo_limb64(i200, 0, -1, .{ 0, false });
    try test__mulo_limb64(i200, -1, -1, .{ 1, false });
    try test__mulo_limb64(i200, -1, minInt(i200), .{ minInt(i200), true });
    try test__mulo_limb64(i200, maxInt(i200), 2, .{ -2, true });
    try test__mulo_limb64(i200, 1 << 100, 1 << 98, .{ 1 << 198, false });
    try test__mulo_limb64(i200, 1 << 100, 1 << 99, .{ minInt(i200), true });
    try test__mulo_limb64(i200, maxInt(i200), maxInt(i200), .{ 1, true });
    try test__mulo_limb64(i200, minInt(i200), minInt(i200), .{ 0, true });

    try test__mulo_limb64(u150, maxInt(u150), 2, .{ maxInt(u150) - 1, true });
    try test__mulo_limb64(i150, maxInt(i150), 2, .{ -2, true });
}

comptime {
    symbol(&__abs_limb64, "__abs_limb64");
}

fn __abs_limb64(out_ptr: [*]u64, a_ptr: [*]const u64, bits: u16) callconv(.c) void {
    const limb_cnt = limbCount(bits);
    const out = out_ptr[0..limb_cnt];
    const a = a_ptr[0..limb_cnt];

    const ms = limbGet(a, limb_cnt - 1);
    if ((ms >> 63) == 0) {
        @memcpy(out, a);
        return;
    }

    var carry: u1 = 1;
    var i: usize = 0;
    while (i < limb_cnt) : (i += 1) {
        const s = @addWithOverflow(~limbGet(a, i), carry);
        limbSet(out, i, s[0]);
        carry = s[1];
    }
}

fn test__abs_limb64(comptime T: type, a: T, expected: @Int(.unsigned, @typeInfo(T).int.bits)) !void {
    const int_info = @typeInfo(T).int;
    comptime assert(int_info.signedness == .signed);

    var a_limbs = asLimbs(a);
    var out: Limbs(@TypeOf(expected)) = undefined;
    __abs_limb64(&out, &a_limbs, int_info.bits);

    const expected_limbs = asLimbs(expected);
    try testing.expectEqual(expected_limbs, out);
}

test __abs_limb64 {
    try test__abs_limb64(i64, 0, 0);
    try test__abs_limb64(i64, -1, 1);
    try test__abs_limb64(i64, minInt(i64), 1 << 63);
    try test__abs_limb64(i65, -1, 1);
    try test__abs_limb64(i65, minInt(i65), 1 << 64);
    try test__abs_limb64(i65, maxInt(i65), maxInt(i65));
    try test__abs_limb64(i128, -1 << 80, 1 << 80);
    try test__abs_limb64(i128, 1 << 64, 1 << 64);
    try test__abs_limb64(i200, -1 << 198, 1 << 198);
    try test__abs_limb64(i255, -5, 5);
    try test__abs_limb64(i255, minInt(i255), 1 << 254);

    try test__abs_limb64(i150, -40, 40);
}
