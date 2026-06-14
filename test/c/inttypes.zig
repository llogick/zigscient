const builtin = @import("builtin");
const std = @import("std");

const c = std.c;
const testing = std.testing;

test "imaxabs" {
    const val: c.intmax_t = -10;
    try testing.expectEqual(10, c.imaxabs(val));
}

test "imaxdiv" {
    if (builtin.target.cpu.arch.isPowerPC32()) return error.SkipZigTest; // TODO
    if (builtin.target.cpu.arch == .s390x) return error.SkipZigTest; // TODO

    const expected: c.imaxdiv_t = .{ .quot = 9, .rem = 0 };
    try testing.expectEqual(expected, c.imaxdiv(9, 1));
}
