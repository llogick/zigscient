const builtin = @import("builtin");
const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const maxInt = std.math.maxInt;
const minInt = std.math.minInt;

test "@intCast i32 to u7" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    var x: u128 = maxInt(u128);
    var y: i32 = 120;
    _ = .{ &x, &y };
    const z = x >> @as(u7, @intCast(y));
    try expect(z == 0xff);
}

test "coerce i8 to i32 and @intCast back" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO

    var x: i8 = -5;
    var y: i32 = -5;
    _ = .{ &x, &y };
    try expect(y == x);

    var x2: i32 = -5;
    var y2: i8 = -5;
    _ = .{ &x2, &y2 };
    try expect(y2 == @as(i8, @intCast(x2)));
}

test "coerce non byte-sized integers accross 32bits boundary" {
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest; // TODO

    {
        var v: u21 = 6417;
        _ = &v;
        const a: u32 = v;
        const b: u64 = v;
        const c: u64 = a;
        var w: u64 = 0x1234567812345678;
        _ = &w;
        const d: u21 = @truncate(w);
        const e: u60 = d;
        try expectEqual(@as(u32, 6417), a);
        try expectEqual(@as(u64, 6417), b);
        try expectEqual(@as(u64, 6417), c);
        try expectEqual(@as(u21, 0x145678), d);
        try expectEqual(@as(u60, 0x145678), e);
    }

    {
        var v: u10 = 234;
        _ = &v;
        const a: u32 = v;
        const b: u64 = v;
        const c: u64 = a;
        var w: u64 = 0x1234567812345678;
        _ = &w;
        const d: u10 = @truncate(w);
        const e: u60 = d;
        try expectEqual(@as(u32, 234), a);
        try expectEqual(@as(u64, 234), b);
        try expectEqual(@as(u64, 234), c);
        try expectEqual(@as(u21, 0x278), d);
        try expectEqual(@as(u60, 0x278), e);
    }
    {
        var v: u7 = 11;
        _ = &v;
        const a: u32 = v;
        const b: u64 = v;
        const c: u64 = a;
        var w: u64 = 0x1234567812345678;
        _ = &w;
        const d: u7 = @truncate(w);
        const e: u60 = d;
        try expectEqual(@as(u32, 11), a);
        try expectEqual(@as(u64, 11), b);
        try expectEqual(@as(u64, 11), c);
        try expectEqual(@as(u21, 0x78), d);
        try expectEqual(@as(u60, 0x78), e);
    }

    {
        var v: i21 = -6417;
        _ = &v;
        const a: i32 = v;
        const b: i64 = v;
        const c: i64 = a;
        var w: i64 = -12345;
        _ = &w;
        const d: i21 = @intCast(w);
        const e: i60 = d;
        try expectEqual(@as(i32, -6417), a);
        try expectEqual(@as(i64, -6417), b);
        try expectEqual(@as(i64, -6417), c);
        try expectEqual(@as(i21, -12345), d);
        try expectEqual(@as(i60, -12345), e);
    }

    {
        var v: i10 = -234;
        _ = &v;
        const a: i32 = v;
        const b: i64 = v;
        const c: i64 = a;
        var w: i64 = -456;
        _ = &w;
        const d: i10 = @intCast(w);
        const e: i60 = d;
        try expectEqual(@as(i32, -234), a);
        try expectEqual(@as(i64, -234), b);
        try expectEqual(@as(i64, -234), c);
        try expectEqual(@as(i10, -456), d);
        try expectEqual(@as(i60, -456), e);
    }
    {
        var v: i7 = -11;
        _ = &v;
        const a: i32 = v;
        const b: i64 = v;
        const c: i64 = a;
        var w: i64 = -42;
        _ = &w;
        const d: i7 = @intCast(w);
        const e: i60 = d;
        try expectEqual(@as(i32, -11), a);
        try expectEqual(@as(i64, -11), b);
        try expectEqual(@as(i64, -11), c);
        try expectEqual(@as(i7, -42), d);
        try expectEqual(@as(i60, -42), e);
    }
}

fn testIntCast(comptime S: type, a: S, comptime D: type, expected: D) !void {
    const actual: D = @intCast(a);
    try expect(actual == expected);
}

test "@intCast <= 64 bits" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    try testIntCast(i32, minInt(i32), i64, minInt(i32));
    try testIntCast(u32, maxInt(u32), u64, maxInt(u32));
    try testIntCast(u32, maxInt(i32), i64, maxInt(i32));
    try testIntCast(u32, maxInt(u32), i64, maxInt(u32));

    try testIntCast(i32, 0, u32, 0);
    try testIntCast(i32, maxInt(i32), u32, maxInt(i32));
    try testIntCast(i64, 0, u64, 0);
    try testIntCast(i64, maxInt(i64), u64, maxInt(i64));

    try testIntCast(u32, 0, i32, 0);
    try testIntCast(u32, maxInt(i32), i32, maxInt(i32));
    try testIntCast(u64, 0, i64, 0);
    try testIntCast(u64, maxInt(i64), i64, maxInt(i64));

    try testIntCast(i64, minInt(i32), i32, minInt(i32));
    try testIntCast(i64, maxInt(i32), i32, maxInt(i32));
    try testIntCast(u64, maxInt(u32), u32, maxInt(u32));
    try testIntCast(i64, maxInt(u32), u32, maxInt(u32));
}

test "@intCast > 128 bits" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    try testIntCast(u8, 123, u140, 123);
    try testIntCast(u127, maxInt(u127), u140, maxInt(u127));
    try testIntCast(i8, -42, i140, -42);
    try testIntCast(i64, minInt(i64), i140, minInt(i64));
    try testIntCast(i127, maxInt(i127), i140, maxInt(i127));
    try testIntCast(u127, 1 << 100, i140, 1 << 100);
    try testIntCast(i127, 1 << 100, u140, 1 << 100);

    try testIntCast(u140, 0, u128, 0);
    try testIntCast(u140, 1 << 100, u128, 1 << 100);
    try testIntCast(u140, maxInt(u128), u128, maxInt(u128));
    try testIntCast(i140, -1, i128, -1);
    try testIntCast(i140, minInt(i128), i128, minInt(i128));
    try testIntCast(i140, maxInt(i128), i128, maxInt(i128));
    try testIntCast(u140, 1 << 100, i128, 1 << 100);
    try testIntCast(i140, 1 << 100, u128, 1 << 100);

    try testIntCast(u16, 255, u256, 255);
    try testIntCast(u128, 1 << 127, u256, 1 << 127);
    try testIntCast(i16, -7, i256, -7);
    try testIntCast(i128, minInt(i128), i256, minInt(i128));
    try testIntCast(u128, maxInt(i128), i256, maxInt(i128));
    try testIntCast(i128, 1 << 100, u256, 1 << 100);

    try testIntCast(u256, 1 << 139, u140, 1 << 139);
    try testIntCast(u256, maxInt(u140), u140, maxInt(u140));
    try testIntCast(i256, -1, i140, -1);
    try testIntCast(i256, minInt(i140), i140, minInt(i140));
    try testIntCast(i256, maxInt(i140), i140, maxInt(i140));
    try testIntCast(u256, 1 << 120, i140, 1 << 120);
    try testIntCast(i256, 1 << 120, u140, 1 << 120);

    try testIntCast(i257, maxInt(i256), i256, maxInt(i256));
    try testIntCast(i257, minInt(i256), i256, minInt(i256));
    try testIntCast(u257, maxInt(u256), u256, maxInt(u256));
    try testIntCast(u257, 1 << 255, u256, 1 << 255);

    try testIntCast(u32, maxInt(u32), i255, maxInt(u32));
    try testIntCast(u64, maxInt(u64), i255, maxInt(u64));
    try testIntCast(u128, maxInt(u128), i255, maxInt(u128));
}

const Piece = packed struct {
    color: Color,
    type: Type,

    const Type = enum(u3) { KING, QUEEN, BISHOP, KNIGHT, ROOK, PAWN };
    const Color = enum(u1) { WHITE, BLACK };

    fn charToPiece(c: u8) !@This() {
        return .{
            .type = try charToPieceType(c),
            .color = if (std.ascii.isUpper(c)) Color.WHITE else Color.BLACK,
        };
    }

    fn charToPieceType(c: u8) !Type {
        return switch (std.ascii.toLower(c)) {
            'p' => .PAWN,
            'k' => .KING,
            'q' => .QUEEN,
            'b' => .BISHOP,
            'n' => .KNIGHT,
            'r' => .ROOK,
            else => error.UnexpectedCharError,
        };
    }
};

// Originally reported at https://github.com/ziglang/zig/issues/14200
test "load non byte-sized optional value" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest; // TODO

    // note: this bug is triggered by the == operator, expectEqual will hide it
    const opt: ?Piece = try Piece.charToPiece('p');
    try expect(opt.?.type == .PAWN);
    try expect(opt.?.color == .BLACK);

    var p: Piece = undefined;
    @as(*u8, @ptrCast(&p)).* = 0b11111011;
    try expect(p.type == .PAWN);
    try expect(p.color == .BLACK);
}

test "load non byte-sized value in struct" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.cpu.arch.endian() != .little) return error.SkipZigTest; // packed struct TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest; // TODO

    // note: this bug is triggered by the == operator, expectEqual will hide it
    // using ptrCast not to depend on unitialised memory state

    var struct0: struct {
        p: Piece,
        int: u8,
    } = undefined;
    @as(*u8, @ptrCast(&struct0.p)).* = 0b11111011;
    try expect(struct0.p.type == .PAWN);
    try expect(struct0.p.color == .BLACK);

    var struct1: packed struct {
        p0: Piece,
        p1: Piece,
        pad: u1,
        p2: Piece,
    } = undefined;
    @as(*u8, @ptrCast(&struct1.p0)).* = 0b11111011;
    struct1.p1 = try Piece.charToPiece('p');
    struct1.p2 = try Piece.charToPiece('p');
    try expect(struct1.p0.type == .PAWN);
    try expect(struct1.p0.color == .BLACK);
    try expect(struct1.p1.type == .PAWN);
    try expect(struct1.p1.color == .BLACK);
    try expect(struct1.p2.type == .PAWN);
    try expect(struct1.p2.color == .BLACK);
}

test "load non byte-sized value in union" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    // note: this bug is triggered by the == operator, expectEqual will hide it
    // using ptrCast not to depend on unitialised memory state

    var union0: packed union {
        p: packed struct(u8) {
            a: Piece,
            b: u4,
        },
        int: u8,
    } = .{ .int = 0 };
    union0.int = 0b11111011;
    try expect(union0.p.a.type == .PAWN);
    try expect(union0.p.a.color == .BLACK);

    var union1: union {
        p: packed struct(u8) {
            a: Piece,
            b: u4,
        },
        int: u8,
    } = .{ .p = .{ .a = .{ .color = .WHITE, .type = .KING }, .b = 0 } };
    @as(*u8, @ptrCast(&union1.p.a)).* = 0b11111011;
    try expect(union1.p.a.type == .PAWN);
    try expect(union1.p.a.color == .BLACK);

    var pieces: [3]Piece = undefined;
    @as(*u8, @ptrCast(&pieces[1])).* = 0b11111011;
    try expect(pieces[1].type == .PAWN);
    try expect(pieces[1].color == .BLACK);
}
