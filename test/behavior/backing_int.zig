const builtin = @import("builtin");
const std = @import("std");
const expect = std.testing.expect;
const assert = std.debug.assert;

const E1 = enum(u8) {
    a,
    b,
    c,
    d,
    const expected = .{
        .val = @as(E1, .b),
        .int = @as(@typeInfo(E1).@"enum".tag_type, 1),
    };
};
const E2 = enum(i20) {
    x,
    y,
    z = -5,
    const expected = .{
        .val = @as(E2, .z),
        .int = @as(@typeInfo(E2).@"enum".tag_type, -5),
    };
};
const E3 = enum(i32) {
    _,
    const zero: E3 = @bitCast(@as(i32, 0));
    const expected = .{
        .val = @as(E3, .zero),
        .int = @as(@typeInfo(E3).@"enum".tag_type, 0),
    };
};
const E4 = enum(i200) {
    min = -(1 << 199),
    const expected = .{
        .val = @as(E4, .min),
        .int = @as(@typeInfo(E4).@"enum".tag_type, -(1 << 199)),
    };
};
const E5 = enum(u0) {
    a,
    const expected = .{
        .val = @as(E5, .a),
        .int = @as(@typeInfo(E5).@"enum".tag_type, 0),
    };
};

test "@backingInt with enums" {
    const static = struct {
        fn doTheTest(v1: E1, v2: E2, v3: E3, v4: E4, v5: E5) !void {
            const b1 = @backingInt(v1);
            comptime assert(@TypeOf(b1) == @typeInfo(E1).@"enum".tag_type);
            try expect(b1 == E1.expected.int);

            const b2 = @backingInt(v2);
            comptime assert(@TypeOf(b2) == @typeInfo(E2).@"enum".tag_type);
            try expect(b2 == E2.expected.int);

            const b3 = @backingInt(v3);
            comptime assert(@TypeOf(b3) == @typeInfo(E3).@"enum".tag_type);
            try expect(b3 == E3.expected.int);

            const b4 = @backingInt(v4);
            comptime assert(@TypeOf(b4) == @typeInfo(E4).@"enum".tag_type);
            try expect(b4 == E4.expected.int);

            const b5 = @backingInt(v5);
            comptime assert(@TypeOf(b5) == @typeInfo(E5).@"enum".tag_type);
            try expect(b5 == E5.expected.int);
        }
    };
    try static.doTheTest(E1.expected.val, E2.expected.val, E3.expected.val, E4.expected.val, E5.expected.val);
    try comptime static.doTheTest(E1.expected.val, E2.expected.val, E3.expected.val, E4.expected.val, E5.expected.val);
}

test "@fromBackingInt with enums" {
    const static = struct {
        fn doTheTest(
            b1: @typeInfo(E1).@"enum".tag_type,
            b2: @typeInfo(E2).@"enum".tag_type,
            b3: @typeInfo(E3).@"enum".tag_type,
            b4: @typeInfo(E4).@"enum".tag_type,
            b5: @typeInfo(E5).@"enum".tag_type,
        ) !void {
            const v1: E1 = @fromBackingInt(b1);
            try expect(v1 == E1.expected.val);

            const v2: E2 = @fromBackingInt(b2);
            try expect(v2 == E2.expected.val);

            const v3: E3 = @fromBackingInt(b3);
            try expect(v3 == E3.expected.val);

            const v4: E4 = @fromBackingInt(b4);
            try expect(v4 == E4.expected.val);

            const v5: E5 = @fromBackingInt(b5);
            try expect(v5 == E5.expected.val);
        }
    };
    try static.doTheTest(E1.expected.int, E2.expected.int, E3.expected.int, E4.expected.int, E5.expected.int);
    try comptime static.doTheTest(E1.expected.int, E2.expected.int, E3.expected.int, E4.expected.int, E5.expected.int);
}

const T1 = union(E1) {
    a: u8,
    b: []const u16,
    c: []const u8,
    d: i32,
    const expected = .{
        .val = @unionInit(T1, @tagName(E1.expected.val), &.{ 1, 2, 3 }),
        .int = E1.expected.int,
    };
};
const T2 = union(E2) {
    x,
    y: i32,
    z,
    const expected = .{
        .val = @unionInit(T2, @tagName(E2.expected.val), {}),
        .int = E2.expected.int,
    };
};
const T4 = union(E4) {
    min: f32,
    const expected = .{
        .val = @unionInit(T4, @tagName(E4.expected.val), 0.123),
        .int = E4.expected.int,
    };
};
const T5 = union(E5) {
    a: u0,
    const expected = .{
        .val = @unionInit(T5, @tagName(E5.expected.val), 0),
        .int = E5.expected.int,
    };
};

test "@backingInt with tagged unions" {
    const static = struct {
        fn doTheTest(v1: T1, v2: T2, v4: T4, v5: T5) !void {
            const b1 = @backingInt(v1);
            comptime assert(@TypeOf(b1) == @typeInfo(@typeInfo(T1).@"union".tag_type.?).@"enum".tag_type);
            try expect(b1 == E1.expected.int);

            const b2 = @backingInt(v2);
            comptime assert(@TypeOf(b2) == @typeInfo(@typeInfo(T2).@"union".tag_type.?).@"enum".tag_type);
            try expect(b2 == E2.expected.int);

            const b4 = @backingInt(v4);
            comptime assert(@TypeOf(b4) == @typeInfo(@typeInfo(T4).@"union".tag_type.?).@"enum".tag_type);
            try expect(b4 == E4.expected.int);

            const b5 = @backingInt(v5);
            comptime assert(@TypeOf(b5) == @typeInfo(@typeInfo(T5).@"union".tag_type.?).@"enum".tag_type);
            try expect(b5 == E5.expected.int);
        }
    };
    try static.doTheTest(T1.expected.val, T2.expected.val, T4.expected.val, T5.expected.val);
    try comptime static.doTheTest(T1.expected.val, T2.expected.val, T4.expected.val, T5.expected.val);
}

const S1 = packed struct(u8) {
    a: u4,
    b: i4,
    const expected = .{
        .val = @as(S1, .{ .a = 0b1000, .b = 0b0010 }),
        .int = @as(@typeInfo(S1).@"struct".backing_integer.?, 0b0010_1000),
    };
};
const S2 = packed struct(i20) {
    a: u10,
    b: enum(i10) { x, y, z },
    const expected = .{
        .val = @as(S2, .{ .a = 0b0011001100, .b = .z }),
        .int = @as(@typeInfo(S2).@"struct".backing_integer.?, 0b0000000010_0011001100),
    };
};
const S3 = packed struct(i32) {
    a: packed struct(u12) {
        x: u8,
        y: i4,
    },
    b: packed union(i20) {
        x: i20,
        y: enum(u20) { u, v },
    },
    const expected = .{
        .val = @as(S3, .{ .a = .{ .x = 0b10010001, .y = 0b0110 }, .b = .{ .y = .v } }),
        .int = @as(@typeInfo(S3).@"struct".backing_integer.?, 0b00000000000000000001_0110_10010001),
    };
};
const S4 = packed struct(i200) {
    a: u200,
    const expected = .{
        .val = @as(S4, .{ .a = (1 << 199) + 10 }),
        .int = @as(@typeInfo(S4).@"struct".backing_integer.?, @bitCast(@as(u200, (1 << 199) + 10))),
    };
};
const S5 = packed struct(u0) {
    a: u0,
    const expected = .{
        .val = @as(S5, .{ .a = 0 }),
        .int = @as(@typeInfo(S5).@"struct".backing_integer.?, 0),
    };
};

test "@backingInt with packed structs" {
    const static = struct {
        fn doTheTest(v1: S1, v2: S2, v3: S3, v4: S4, v5: S5) !void {
            const b1 = @backingInt(v1);
            comptime assert(@TypeOf(b1) == @typeInfo(S1).@"struct".backing_integer.?);
            try expect(b1 == S1.expected.int);

            const b2 = @backingInt(v2);
            comptime assert(@TypeOf(b2) == @typeInfo(S2).@"struct".backing_integer.?);
            try expect(b2 == S2.expected.int);

            const b3 = @backingInt(v3);
            comptime assert(@TypeOf(b3) == @typeInfo(S3).@"struct".backing_integer.?);
            try expect(b3 == S3.expected.int);

            const b4 = @backingInt(v4);
            comptime assert(@TypeOf(b4) == @typeInfo(S4).@"struct".backing_integer.?);
            try expect(b4 == S4.expected.int);

            const b5 = @backingInt(v5);
            comptime assert(@TypeOf(b5) == @typeInfo(S5).@"struct".backing_integer.?);
            try expect(b5 == S5.expected.int);
        }
    };
    try static.doTheTest(S1.expected.val, S2.expected.val, S3.expected.val, S4.expected.val, S5.expected.val);
    try comptime static.doTheTest(S1.expected.val, S2.expected.val, S3.expected.val, S4.expected.val, S5.expected.val);
}

test "@fromBackingInt with packed structs" {
    const static = struct {
        fn doTheTest(
            b1: @typeInfo(S1).@"struct".backing_integer.?,
            b2: @typeInfo(S2).@"struct".backing_integer.?,
            b3: @typeInfo(S3).@"struct".backing_integer.?,
            b4: @typeInfo(S4).@"struct".backing_integer.?,
            b5: @typeInfo(S5).@"struct".backing_integer.?,
        ) !void {
            const v1: S1 = @fromBackingInt(b1);
            try expect(v1 == S1.expected.val);

            const v2: S2 = @fromBackingInt(b2);
            try expect(v2 == S2.expected.val);

            const v3: S3 = @fromBackingInt(b3);
            try expect(v3 == S3.expected.val);

            // https://codeberg.org/ziglang/zig/issues/35982
            if (builtin.zig_backend != .stage2_x86_64) {
                const v4: S4 = @fromBackingInt(b4);
                try expect(v4 == S4.expected.val);
            }

            const v5: S5 = @fromBackingInt(b5);
            try expect(v5 == S5.expected.val);
        }
    };
    try static.doTheTest(S1.expected.int, S2.expected.int, S3.expected.int, S4.expected.int, S5.expected.int);
    try comptime static.doTheTest(S1.expected.int, S2.expected.int, S3.expected.int, S4.expected.int, S5.expected.int);
}

const U1 = packed union(u8) {
    a: u8,
    b: i8,
    const expected = .{
        .val = @as(U1, .{ .b = -123 }),
        .int = @as(@typeInfo(U1).@"union".backing_integer.?, @bitCast(@as(i8, -123))),
    };
};
const U2 = packed union(i20) {
    a: u20,
    b: enum(i20) { x, y, z },
    const expected = .{
        .val = @as(U2, .{ .b = .z }),
        .int = @as(@typeInfo(U2).@"union".backing_integer.?, 0b00000000000000000000000000000010),
    };
};
const U3 = packed union(i32) {
    a: packed struct(u32) {
        x: u18,
        y: i14,
    },
    b: packed union(u32) {
        x: i32,
        y: enum(u32) { u, v },
    },
    const expected = .{
        .val = @as(U3, .{ .b = .{ .y = .v } }),
        .int = @as(@typeInfo(U3).@"union".backing_integer.?, 0b00000000000000000000000000000001),
    };
};
const U4 = packed union(i200) {
    a: u200,
    const expected = .{
        .val = @as(U4, .{ .a = (1 << 199) + 10 }),
        .int = @as(@typeInfo(U4).@"union".backing_integer.?, @bitCast(@as(u200, (1 << 199) + 10))),
    };
};
const U5 = packed union(u0) {
    a: u0,
    const expected = .{
        .val = @as(U5, .{ .a = 0 }),
        .int = @as(@typeInfo(U5).@"union".backing_integer.?, 0),
    };
};

test "@backingInt with packed unions" {
    const static = struct {
        fn doTheTest(v1: U1, v2: U2, v3: U3, v4: U4, v5: U5) !void {
            const b1 = @backingInt(v1);
            comptime assert(@TypeOf(b1) == @typeInfo(U1).@"union".backing_integer.?);
            try expect(b1 == U1.expected.int);

            const b2 = @backingInt(v2);
            comptime assert(@TypeOf(b2) == @typeInfo(U2).@"union".backing_integer.?);
            try expect(b2 == U2.expected.int);

            const b3 = @backingInt(v3);
            comptime assert(@TypeOf(b3) == @typeInfo(U3).@"union".backing_integer.?);
            try expect(b3 == U3.expected.int);

            const b4 = @backingInt(v4);
            comptime assert(@TypeOf(b4) == @typeInfo(U4).@"union".backing_integer.?);
            try expect(b4 == U4.expected.int);

            const b5 = @backingInt(v5);
            comptime assert(@TypeOf(b5) == @typeInfo(U5).@"union".backing_integer.?);
            try expect(b5 == U5.expected.int);
        }
    };
    try static.doTheTest(U1.expected.val, U2.expected.val, U3.expected.val, U4.expected.val, U5.expected.val);
    try comptime static.doTheTest(U1.expected.val, U2.expected.val, U3.expected.val, U4.expected.val, U5.expected.val);
}

test "@fromBackingInt with packed unions" {
    const static = struct {
        fn doTheTest(
            b1: @typeInfo(U1).@"union".backing_integer.?,
            b2: @typeInfo(U2).@"union".backing_integer.?,
            b3: @typeInfo(U3).@"union".backing_integer.?,
            b4: @typeInfo(U4).@"union".backing_integer.?,
            b5: @typeInfo(U5).@"union".backing_integer.?,
        ) !void {
            const v1: U1 = @fromBackingInt(b1);
            try expect(v1 == U1.expected.val);

            const v2: U2 = @fromBackingInt(b2);
            try expect(v2 == U2.expected.val);

            const v3: U3 = @fromBackingInt(b3);
            try expect(v3 == U3.expected.val);

            // https://codeberg.org/ziglang/zig/issues/35982
            if (builtin.zig_backend != .stage2_x86_64) {
                const v4: U4 = @fromBackingInt(b4);
                try expect(v4 == U4.expected.val);
            }

            const v5: U5 = @fromBackingInt(b5);
            try expect(v5 == U5.expected.val);
        }
    };
    try static.doTheTest(U1.expected.int, U2.expected.int, U3.expected.int, U4.expected.int, U5.expected.int);
    try comptime static.doTheTest(U1.expected.int, U2.expected.int, U3.expected.int, U4.expected.int, U5.expected.int);
}

test "@fromBackingInt provides result type to its argument" {
    const E = enum(u32) { a, b, c };
    const static = struct {
        fn doTheTest(x: u8) !void {
            const e: E = @fromBackingInt(x);
            try expect(e == .b);
            try expect(@backingInt(e) == x);
        }
    };
    try static.doTheTest(1);
    try comptime static.doTheTest(1);
}
