const std = @import("std");
const math = std.math;
const maxInt = math.maxInt;
const minInt = math.minInt;
const builtin = @import("builtin");
const assert = std.debug.assert;
const expect = std.testing.expect;

test "truncate u0 to larger integer allowed and has comptime-known result" {
    var x: u0 = 0;
    _ = &x;
    const y = @as(u8, @truncate(x));
    comptime assert(y == 0);
}

test "truncate.u0.literal" {
    const z: u0 = @truncate(0);
    try expect(z == 0);
}

test "truncate.u0.const" {
    const c0: usize = 0;
    const z: u0 = @truncate(c0);
    try expect(z == 0);
}

test "truncate.u0.var" {
    var d: u8 = 2;
    _ = &d;
    const z: u0 = @truncate(d);
    try expect(z == 0);
}

test "truncate on comptime integer" {
    const x: u16 = @truncate(9999);
    try expect(x == 9999);
    const y: u16 = @truncate(-21555);
    try expect(y == 0xabcd);
    const z: i16 = @truncate(-65537);
    try expect(z == -1);
    const w: u1 = @truncate(1 << 100);
    try expect(w == 0);
}

fn testTruncate(comptime S: type, a: S, comptime D: type, expected: D) !void {
    const actual: D = @truncate(a);
    try expect(actual == expected);
}

test "@truncate > 128 bits" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    try testTruncate(u140, 0, u128, 0);
    try testTruncate(u140, maxInt(u140), u128, maxInt(u128));
    try testTruncate(u140, 1 << 139, u128, 0);
    try testTruncate(u140, (1 << 139) | (1 << 64) | 0x55, u128, (1 << 64) | 0x55);
    try testTruncate(u140, (1 << 100) | (1 << 63), u128, (1 << 100) | (1 << 63));
    try testTruncate(u140, (1 << 130) | 0xabcd, u16, 0xabcd);

    try testTruncate(u256, 1 << 200, u128, 0);
    try testTruncate(u256, (1 << 200) | (1 << 127) | 1, u128, (1 << 127) | 1);
    try testTruncate(u256, maxInt(u256), u128, maxInt(u128));
    try testTruncate(u256, (1 << 255) | (1 << 128) | 0x1234_5678_9abc_def0, u64, 0x1234_5678_9abc_def0);
    try testTruncate(u256, (1 << 250) | (1 << 32), u32, 0);
    try testTruncate(u256, (1 << 129) | (1 << 63), u64, 1 << 63);

    try testTruncate(i140, 0, i128, 0);
    try testTruncate(i140, -1, i128, -1);
    try testTruncate(i140, -2, i8, -2);
    try testTruncate(i140, -1 << 80, i64, 0);
    try testTruncate(i140, (-1 << 80) | 0x1234, i16, 0x1234);
    try testTruncate(i140, minInt(i140), i128, 0);
    try testTruncate(i140, maxInt(i140), i128, -1);
    try testTruncate(i140, (1 << 127) - 1, i128, maxInt(i128));

    try testTruncate(i256, -1, i128, -1);
    try testTruncate(i256, minInt(i256), i128, 0);
    try testTruncate(i256, (-1 << 128) | maxInt(i128), i128, maxInt(i128));
    try testTruncate(i256, (-1 << 200) | (1 << 127), i128, minInt(i128));
    try testTruncate(i256, -255, i8, 1);
    try testTruncate(i256, (-1 << 64) | 0x1234_5678, i32, 0x1234_5678);

    try testTruncate(i257, maxInt(i257), i256, -1);
    try testTruncate(u257, maxInt(u257), u256, maxInt(u256));
}

test "truncate on vectors" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    const S = struct {
        fn doTheTest() !void {
            var v1: @Vector(4, u16) = .{ 0xaabb, 0xccdd, 0xeeff, 0x1122 };
            _ = &v1;
            const v2: @Vector(4, u8) = @truncate(v1);
            try expect(std.mem.eql(u8, &@as([4]u8, v2), &[4]u8{ 0xbb, 0xdd, 0xff, 0x22 }));
        }
    };
    try comptime S.doTheTest();
    try S.doTheTest();
}
