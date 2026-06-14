const builtin = @import("builtin");
const std = @import("std");

const c = std.c;
const mem = std.mem;
const testing = std.testing;

test "bzero" {
    if (builtin.target.os.tag == .windows) return; // no bzero

    var array: [10]u8 = [_]u8{ '1', '2', '3', '4', '5', '6', '7', '8', '9', '0' };
    var a = mem.zeroes([array.len]u8);
    a[9] = '0';
    c.bzero(&array[0], 9);
    try testing.expect(mem.eql(u8, &array, &a));
}

fn testFfs(comptime T: type) !void {
    const ffs = switch (T) {
        c_int => c.ffs,
        c_long => c.ffsl,
        c_longlong => c.ffsll,
        else => unreachable,
    };

    try testing.expectEqual(0, ffs(0));

    for (0..@bitSizeOf(T)) |i| {
        const bit = @as(T, 1) << @intCast(i);

        try testing.expectEqual(@as(T, @intCast(i + 1)), ffs(bit));
    }
}

test "ffs" {
    if (builtin.target.os.tag == .openbsd) return; // no ffsl/ffsll
    if (builtin.target.os.tag == .windows) return; // no ffs

    try testFfs(c_int);

    if (builtin.target.os.tag == .netbsd) return; // no ffsl/ffsll until 11

    try testFfs(c_long);

    if (@sizeOf(usize) == 4) return error.SkipZigTest; // TODO

    try testFfs(c_longlong);
}

test "strcasecmp" {
    if (builtin.target.os.tag == .windows and builtin.target.abi != .gnu) return; // mingw-only

    try testing.expect(c.strcasecmp(@ptrCast("a"), @ptrCast("b")) < 0);
    try testing.expect(c.strcasecmp(@ptrCast("b"), @ptrCast("a")) > 0);
    try testing.expect(c.strcasecmp(@ptrCast("A"), @ptrCast("b")) < 0);
    try testing.expect(c.strcasecmp(@ptrCast("b"), @ptrCast("A")) > 0);
    try testing.expect(c.strcasecmp(@ptrCast("A"), @ptrCast("A")) == 0);
    try testing.expect(c.strcasecmp(@ptrCast("B"), @ptrCast("b")) == 0);
    try testing.expect(c.strcasecmp(@ptrCast("bb"), @ptrCast("AA")) > 0);
}

test "strncasecmp" {
    if (builtin.target.os.tag == .windows and builtin.target.abi != .gnu) return; // mingw-only

    try testing.expect(c.strncasecmp(@ptrCast("a"), @ptrCast("b"), 1) < 0);
    try testing.expect(c.strncasecmp(@ptrCast("b"), @ptrCast("a"), 1) > 0);
    try testing.expect(c.strncasecmp(@ptrCast("A"), @ptrCast("b"), 1) < 0);
    try testing.expect(c.strncasecmp(@ptrCast("b"), @ptrCast("A"), 1) > 0);
    try testing.expect(c.strncasecmp(@ptrCast("A"), @ptrCast("A"), 1) == 0);
    try testing.expect(c.strncasecmp(@ptrCast("B"), @ptrCast("b"), 1) == 0);
    try testing.expect(c.strncasecmp(@ptrCast("bb"), @ptrCast("AA"), 2) > 0);
}
