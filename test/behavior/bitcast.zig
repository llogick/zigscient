const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const math = std.math;
const maxInt = std.math.maxInt;
const minInt = std.math.minInt;
const native_endian = builtin.target.cpu.arch.endian();

test "@bitCast iX -> uX (32, 64)" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest;

    const bit_values = [_]usize{ 32, 64 };

    inline for (bit_values) |bits| {
        try testBitCast(bits);
        try comptime testBitCast(bits);
    }
}

test "@bitCast iX -> uX (8, 16, 128)" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    const bit_values = [_]usize{ 8, 16, 128 };

    inline for (bit_values) |bits| {
        try testBitCast(bits);
        try comptime testBitCast(bits);
    }
}

test "@bitCast iX -> uX exotic integers" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    const bit_values = [_]usize{ 1, 48, 27, 512, 493, 293, 125, 204, 112 };

    inline for (bit_values) |bits| {
        try testBitCast(bits);
        try comptime testBitCast(bits);
    }
}

fn testBitCast(comptime N: usize) !void {
    const iN = @Int(.signed, N);
    const uN = @Int(.unsigned, N);

    try expect(conv_iN(N, -1) == maxInt(uN));
    try expect(conv_uN(N, maxInt(uN)) == -1);

    try expect(conv_iN(N, maxInt(iN)) == maxInt(iN));
    try expect(conv_uN(N, maxInt(iN)) == maxInt(iN));

    try expect(conv_uN(N, 1 << (N - 1)) == minInt(iN));
    try expect(conv_iN(N, minInt(iN)) == (1 << (N - 1)));

    try expect(conv_uN(N, 0) == 0);
    try expect(conv_iN(N, 0) == 0);

    if (N > 24) {
        try expect(conv_uN(N, 0xf23456) == 0xf23456);
    }
}

fn conv_iN(comptime N: usize, x: @Int(.signed, N)) @Int(.unsigned, N) {
    return @as(@Int(.unsigned, N), @bitCast(x));
}

fn conv_uN(comptime N: usize, x: @Int(.unsigned, N)) @Int(.signed, N) {
    return @as(@Int(.signed, N), @bitCast(x));
}

test "nested bitcast" {
    const S = struct {
        fn moo(x: isize) !void {
            try expect(@as(isize, @intCast(42)) == x);
        }

        fn foo(x: isize) !void {
            try @This().moo(
                @as(isize, @bitCast(if (x != 0) @as(usize, @bitCast(x)) else @as(usize, @bitCast(x)))),
            );
        }
    };

    try S.foo(42);
    try comptime S.foo(42);
}

// issue #3010: compiler segfault
test "bitcast literal [4]u8 param to u32" {
    const ip = @as(u32, @bitCast([_]u8{ 255, 255, 255, 255 }));
    try expect(ip == maxInt(u32));
}

test "bitcast generates a temporary value" {
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    var y: u16 = 0x55AA;
    _ = &y;
    const x: u16 = @bitCast(@as([2]u8, @bitCast(y)));
    try expect(y == x);
}

test "@bitCast packed structs at runtime and comptime" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    const Full = packed struct {
        number: u16,
    };
    const Divided = packed struct {
        half1: u8,
        quarter3: u4,
        quarter4: u4,
    };
    const S = struct {
        fn doTheTest() !void {
            var full = Full{ .number = 0x1234 };
            _ = &full;
            const two_halves: Divided = @bitCast(full);
            try expect(two_halves.half1 == 0x34);
            try expect(two_halves.quarter3 == 0x2);
            try expect(two_halves.quarter4 == 0x1);
        }
    };
    try S.doTheTest();
    try comptime S.doTheTest();
}

test "bitcast packed struct to integer and back" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO

    const LevelUpMove = packed struct {
        move_id: u9,
        level: u7,
    };
    const S = struct {
        fn doTheTest() !void {
            var move = LevelUpMove{ .move_id = 1, .level = 2 };
            _ = &move;
            const v: u16 = @bitCast(move);
            const back_to_a_move: LevelUpMove = @bitCast(v);
            try expect(back_to_a_move.move_id == 1);
            try expect(back_to_a_move.level == 2);
        }
    };
    try S.doTheTest();
    try comptime S.doTheTest();
}

test "implicit cast to error union by returning" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO

    const S = struct {
        fn entry() !void {
            try expect((func(-1) catch unreachable) == maxInt(u64));
        }
        pub fn func(sz: i64) anyerror!u64 {
            return @as(u64, @bitCast(sz));
        }
    };
    try S.entry();
    try comptime S.entry();
}

test "bitcast packed struct literal to byte" {
    const Foo = packed struct {
        value: u8,
    };
    const casted = @as(u8, @bitCast(Foo{ .value = 0xF }));
    try expect(casted == 0xf);
}

test "comptime bitcast used in expression has the correct type" {
    const Foo = packed struct {
        value: u8,
    };
    try expect(@as(u8, @bitCast(Foo{ .value = 0xF })) == 0xf);
}

test "bitcast passed as tuple element" {
    const S = struct {
        fn foo(args: anytype) !void {
            comptime assert(@TypeOf(args[0]) == f32);
            try expect(args[0] == 12.34);
        }
    };
    try S.foo(.{@as(f32, @bitCast(@as(u32, 0x414570A4)))});
}

test "triple level result location with bitcast sandwich passed as tuple element" {
    const S = struct {
        fn foo(args: anytype) !void {
            comptime assert(@TypeOf(args[0]) == f64);
            try expect(args[0] > 12.33 and args[0] < 12.35);
        }
    };
    try S.foo(.{@as(f64, @as(f32, @bitCast(@as(u32, 0x414570A4))))});
}

test "@bitCast packed struct of floats" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    const Foo = packed struct {
        a: f16 = 0,
        b: f32 = 1,
        c: f64 = 2,
        d: f128 = 3,
    };

    const Foo2 = packed struct {
        a: f16 = 0,
        b: f32 = 1,
        c: f64 = 2,
        d: f128 = 3,
    };

    const S = struct {
        fn doTheTest() !void {
            var foo = Foo{};
            _ = &foo;
            const v: Foo2 = @bitCast(foo);
            try expect(v.a == foo.a);
            try expect(v.b == foo.b);
            try expect(v.c == foo.c);
            try expect(v.d == foo.d);
        }
    };
    try S.doTheTest();
    try comptime S.doTheTest();
}

test "comptime @bitCast packed struct to int and back" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    const S = packed struct {
        void: void = {},
        uint: u8 = 13,
        uint_bit_aligned: u3 = 2,
        iint_pos: i4 = 1,
        iint_neg4: i3 = -4,
        iint_neg2: i3 = -2,
        float: f32 = 3.14,
        @"enum": enum(u2) { A, B = 1, C, D } = .B,
    };
    const Int = @typeInfo(S).@"struct".backing_integer.?;

    // S -> Int
    var s: S = .{};
    _ = &s;
    try expectEqual(@as(Int, @bitCast(s)), comptime @as(Int, @bitCast(S{})));

    // Int -> S
    var i: Int = 0;
    _ = &i;
    const rt_cast = @as(S, @bitCast(i));
    const ct_cast = comptime @as(S, @bitCast(@as(Int, 0)));
    inline for (@typeInfo(S).@"struct".field_names) |field_name| {
        try expectEqual(@field(rt_cast, field_name), @field(ct_cast, field_name));
    }
}

test "bitcast vector to integer and back" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    var vec: @Vector(16, bool) = @splat(true);
    vec[1] = false;

    const int: u16 = @bitCast(vec);
    try expect(int == 0b1111_1111_1111_1101);

    const vec_again: @Vector(16, bool) = @bitCast(int);
    try expect(vec_again[0]);
    try expect(!vec_again[1]);
    try expect(vec_again[2]);
    try expect(vec_again[3]);
    try expect(vec_again[4]);
    try expect(vec_again[5]);
    try expect(vec_again[6]);
    try expect(vec_again[7]);
    try expect(vec_again[8]);
    try expect(vec_again[9]);
    try expect(vec_again[10]);
    try expect(vec_again[11]);
    try expect(vec_again[12]);
    try expect(vec_again[13]);
    try expect(vec_again[14]);
    try expect(vec_again[15]);

    const int_again: u16 = @bitCast(vec_again);
    try expect(int_again == 0b1111_1111_1111_1101);
}

fn bitCastWrapper16(x: f16) u16 {
    return @as(u16, @bitCast(x));
}
fn bitCastWrapper32(x: f32) u32 {
    return @as(u32, @bitCast(x));
}
fn bitCastWrapper64(x: f64) u64 {
    return @as(u64, @bitCast(x));
}
fn bitCastWrapper128(x: f128) u128 {
    return @as(u128, @bitCast(x));
}
test "bitcast nan float does not modify signaling bit" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch.isPowerPC()) return error.SkipZigTest;

    const snan_u16: u16 = 0x7D00;
    const snan_u32: u32 = 0x7FA00000;
    const snan_u64: u64 = 0x7FF4000000000000;
    const snan_u128: u128 = 0x7FFF4000000000000000000000000000;

    // 16 bit
    const snan_f16_const = math.snan(f16);
    try expectEqual(snan_u16, @as(u16, @bitCast(snan_f16_const)));
    try expectEqual(snan_u16, bitCastWrapper16(snan_f16_const));

    var snan_f16_var = math.snan(f16);
    _ = &snan_f16_var;
    try expectEqual(snan_u16, @as(u16, @bitCast(snan_f16_var)));
    try expectEqual(snan_u16, bitCastWrapper16(snan_f16_var));

    // 32 bit
    const snan_f32_const = math.snan(f32);
    try expectEqual(snan_u32, @as(u32, @bitCast(snan_f32_const)));
    try expectEqual(snan_u32, bitCastWrapper32(snan_f32_const));

    var snan_f32_var = math.snan(f32);
    _ = &snan_f32_var;
    try expectEqual(snan_u32, @as(u32, @bitCast(snan_f32_var)));
    try expectEqual(snan_u32, bitCastWrapper32(snan_f32_var));

    // 64 bit
    const snan_f64_const = math.snan(f64);
    try expectEqual(snan_u64, @as(u64, @bitCast(snan_f64_const)));
    try expectEqual(snan_u64, bitCastWrapper64(snan_f64_const));

    var snan_f64_var = math.snan(f64);
    _ = &snan_f64_var;
    try expectEqual(snan_u64, @as(u64, @bitCast(snan_f64_var)));
    try expectEqual(snan_u64, bitCastWrapper64(snan_f64_var));

    // 128 bit
    const snan_f128_const = math.snan(f128);
    try expectEqual(snan_u128, @as(u128, @bitCast(snan_f128_const)));
    try expectEqual(snan_u128, bitCastWrapper128(snan_f128_const));

    var snan_f128_var = math.snan(f128);
    _ = &snan_f128_var;
    try expectEqual(snan_u128, @as(u128, @bitCast(snan_f128_var)));
    try expectEqual(snan_u128, bitCastWrapper128(snan_f128_var));
}

test "@bitCast of packed struct of bools all true" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest; // TODO

    const P = packed struct {
        b0: bool,
        b1: bool,
        b2: bool,
        b3: bool,
    };
    var p = std.mem.zeroes(P);
    p.b0 = true;
    p.b1 = true;
    p.b2 = true;
    p.b3 = true;
    try expect(@as(u8, @as(u4, @bitCast(p))) == 15);
}

test "@bitCast of packed struct of bools all false" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest; // TODO

    const P = packed struct {
        b0: bool,
        b1: bool,
        b2: bool,
        b3: bool,
    };
    var p = std.mem.zeroes(P);
    p.b0 = false;
    p.b1 = false;
    p.b2 = false;
    p.b3 = false;
    try expect(@as(u8, @as(u4, @bitCast(p))) == 0);
}

test "@bitCast of packed struct with void field to integer" {
    const S = packed struct(u8) {
        v: void,
        x: u8,

        fn doTheTest(x: u8) !void {
            // Intentionally using `@as` to avoid RLS which masks the bug
            const foo = @as(@This(), .{ .v = {}, .x = x });
            const as_int: u8 = @bitCast(foo);
            try expect(as_int == x);
        }
    };
    try S.doTheTest(123);
    try comptime S.doTheTest(123);
}

test "@bitCast vector to array with different element size" {
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    const static = struct {
        fn doTheTest(v: @Vector(4, u5)) !void {
            const result: [5]u4 = @bitCast(v);
            // See the definition of `v` in the test proper for these values.
            try expect(result[0] == 0b0010);
            try expect(result[1] == 0b1110);
            try expect(result[2] == 0b0101);
            try expect(result[3] == 0b0110);
            try expect(result[4] == 0b0000);
        }
    };
    // The strange digit groupings here are to indicate how this maps to `expected` above.
    const v: @Vector(4, u5) = .{
        0b0_0010,
        0b01_111,
        0b110_01,
        0b0000_0,
    };
    try static.doTheTest(v);
    try comptime static.doTheTest(v);
}

test "@bitCast packed struct to array of bits" {
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    const S = packed struct(u16) {
        foo: u5,
        bar: i7,
        baz: u3,
        qux: bool,
        fn doTheTest(val: @This(), comptime Bits: type) !void {
            const bits: Bits = @bitCast(val);

            // foo
            try expect(bits[0] == 1);
            try expect(bits[1] == 0);
            try expect(bits[2] == 0);
            try expect(bits[3] == 1);
            try expect(bits[4] == 0);
            // bar
            try expect(bits[5] == 0);
            try expect(bits[6] == 1);
            try expect(bits[7] == 1);
            try expect(bits[8] == 1);
            try expect(bits[9] == 1);
            try expect(bits[10] == 1);
            try expect(bits[11] == 1);
            // baz
            try expect(bits[12] == 0);
            try expect(bits[13] == 1);
            try expect(bits[14] == 0);
            // qux
            try expect(bits[15] == 1);
        }
    };

    const val: S = .{
        .foo = 0b01001,
        .bar = -2,
        .baz = 0b010,
        .qux = true,
    };

    try val.doTheTest(@Vector(16, u1));
    try val.doTheTest([16]u1);

    try comptime val.doTheTest(@Vector(16, u1));
    try comptime val.doTheTest([16]u1);
}

test "@bitCast nested arrays of vectors" {
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    const Src = [2][2]@Vector(4, u5);
    const Dest = [5]@Vector(2, u8);

    // The strange digit groupings here are to indicate how this maps to the output.
    const src: Src = .{ .{
        .{ 0b00011, 0b00_100, 0b11100, 0b0010_1 },
        .{ 0b1_0110, 0b11011, 0b101_10, 0b10101 },
    }, .{
        .{ 0b10101, 0b00_001, 0b01011, 0b0001_0 },
        .{ 0b0_0001, 0b01111, 0b111_10, 0b00001 },
    } };

    const expected: Dest = .{
        .{ 0b10000011, 0b11110000 },
        .{ 0b01100010, 0b10110111 },
        .{ 0b10101101, 0b00110101 },
        .{ 0b00101100, 0b00010001 },
        .{ 0b10011110, 0b00001111 },
    };

    const static = struct {
        fn doTheTest(src_arg: Src) !void {
            const actual: Dest = @bitCast(src_arg);
            for (actual, expected) |actual_vec, expected_vec| {
                try expect(actual_vec[0] == expected_vec[0]);
                try expect(actual_vec[1] == expected_vec[1]);
            }
        }
    };

    try static.doTheTest(src);
    try comptime static.doTheTest(src);
}

test "@bitCast nested arrays of bool to scalar" {
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    const static = struct {
        fn doTheTest(src: [4][4]bool) !void {
            const result: u16 = @bitCast(src);
            try expect(result == 0b1100_0101_1010_0011);
        }
    };
    const src: [4][4]bool = .{
        .{ true, true, false, false }, // 0b0011
        .{ false, true, false, true }, // 0b1010
        .{ true, false, true, false }, // 0b0101
        .{ false, false, true, true }, // 0b1100
    };
    try static.doTheTest(src);
    try comptime static.doTheTest(src);
}

test "@bitCast deeply nested arrays to scalar" {
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    const static = struct {
        fn doTheTest(src: [2][1][3][5]u4) !void {
            const signed: i120 = @bitCast(src);
            try expect(signed < 0); // top nibble is 0x8 so sign bit is 1
            const unsigned: u120 = @bitCast(src);
            try expect(unsigned == 0x8873B_5BF6F_F4020_0E7AC_1EFED_40F51);
            try expect(@as(i120, @bitCast(unsigned)) == signed);
            try expect(@as(u120, @bitCast(signed)) == unsigned);
        }
    };
    const src: [2][1][3][5]u4 = .{ .{.{
        .{ 0x1, 0x5, 0xF, 0x0, 0x4 },
        .{ 0xD, 0xE, 0xF, 0xE, 0x1 },
        .{ 0xC, 0xA, 0x7, 0xE, 0x0 },
    }}, .{.{
        .{ 0x0, 0x2, 0x0, 0x4, 0xF },
        .{ 0xF, 0x6, 0xF, 0xB, 0x5 },
        .{ 0xB, 0x3, 0x7, 0x8, 0x8 },
    }} };
    try static.doTheTest(src);
    try comptime static.doTheTest(src);
}
