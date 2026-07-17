const builtin = @import("builtin");
const std = @import("std");

const c = std.c;
const fmt = std.fmt;
const math = std.math;
const testing = std.testing;

const expectErrno = @import("../c.zig").expectErrno;
const expectErrnoAny = @import("../c.zig").expectErrnoAny;

test "abs" {
    if (builtin.target.cpu.arch.isMIPS64()) return error.SkipZigTest; // TODO

    const val: c_int = -10;
    try testing.expectEqual(10, c.abs(val));
}

test "labs" {
    if (builtin.target.cpu.arch.isMIPS64() and @sizeOf(usize) == 4) return error.SkipZigTest; // TODO

    const val: c_long = -10;
    try testing.expectEqual(10, c.labs(val));
}

test "llabs" {
    const val: c_longlong = -10;
    try testing.expectEqual(10, c.llabs(val));
}

test "div" {
    if (builtin.target.cpu.arch.isLoongArch()) return error.SkipZigTest; // TODO
    if (builtin.target.cpu.arch.isMIPS64()) return error.SkipZigTest; // TODO
    if (builtin.target.cpu.arch.isPowerPC()) return error.SkipZigTest; // TODO
    if (builtin.target.cpu.arch == .s390x) return error.SkipZigTest; // TODO
    if (builtin.target.cpu.arch == .x86 and builtin.target.os.tag == .windows) return error.SkipZigTest; // TODO

    const expected: c.div_t = .{ .quot = 5, .rem = 5 };
    try testing.expectEqual(expected, c.div(55, 10));
}

test "ldiv" {
    if (builtin.target.cpu.arch.isMIPS64() and @sizeOf(usize) == 4) return error.SkipZigTest; // TODO
    if (builtin.target.cpu.arch.isPowerPC32()) return error.SkipZigTest; // TODO
    if (builtin.target.cpu.arch == .s390x) return error.SkipZigTest; // TODO
    if (builtin.target.cpu.arch == .x86 and builtin.target.os.tag == .windows) return error.SkipZigTest; // TODO

    const expected: c.ldiv_t = .{ .quot = -6, .rem = 2 };
    try testing.expectEqual(expected, c.ldiv(38, -6));
}

test "lldiv" {
    if (builtin.target.cpu.arch.isPowerPC32()) return error.SkipZigTest; // TODO
    if (builtin.target.cpu.arch == .s390x) return error.SkipZigTest; // TODO

    const expected: c.lldiv_t = .{ .quot = 1, .rem = 2 };
    try testing.expectEqual(expected, c.lldiv(5, 3));
}

test "atoi" {
    try testing.expectEqual(0, c.atoi(@ptrCast("stop42true")));
    try testing.expectEqual(42, c.atoi(@ptrCast("42true")));
    try testing.expectEqual(-1, c.atoi(@ptrCast("-01")));
    try testing.expectEqual(1, c.atoi(@ptrCast("+001")));
    try testing.expectEqual(100, c.atoi(@ptrCast("            100")));
    try testing.expectEqual(500, c.atoi(@ptrCast("000000000000500")));
    try testing.expectEqual(1111, c.atoi(@ptrCast("0000000000001111_0000")));
    try testing.expectEqual(0, c.atoi(@ptrCast("0xAA")));
    try testing.expectEqual(700, c.atoi(@ptrCast("700B")));
    try testing.expectEqual(32453, c.atoi(@ptrCast("+32453more")));
    try testing.expectEqual(math.maxInt(c_int), c.atoi(@ptrCast(fmt.comptimePrint("{d}", .{math.maxInt(c_int)}))));
    try testing.expectEqual(math.minInt(c_int), c.atoi(@ptrCast(fmt.comptimePrint("{d}", .{math.minInt(c_int)}))));
}

test "atol" {
    try testing.expectEqual(0, c.atol(@ptrCast("stop42true")));
    try testing.expectEqual(42, c.atol(@ptrCast("42true")));
    try testing.expectEqual(-1, c.atol(@ptrCast("-01")));
    try testing.expectEqual(1, c.atol(@ptrCast("+001")));
    try testing.expectEqual(100, c.atol(@ptrCast("            100")));
    try testing.expectEqual(500, c.atol(@ptrCast("000000000000500")));
    try testing.expectEqual(1111, c.atol(@ptrCast("0000000000001111_0000")));
    try testing.expectEqual(0, c.atol(@ptrCast("0xAA")));
    try testing.expectEqual(700, c.atol(@ptrCast("700B")));
    try testing.expectEqual(32453, c.atol(@ptrCast("+32453more")));
    try testing.expectEqual(math.maxInt(c_long), c.atol(@ptrCast(fmt.comptimePrint("{d}", .{math.maxInt(c_long)}))));
    try testing.expectEqual(math.minInt(c_long), c.atol(@ptrCast(fmt.comptimePrint("{d}", .{math.minInt(c_long)}))));
}

test "atoll" {
    try testing.expectEqual(0, c.atoll(@ptrCast("stop42true")));
    try testing.expectEqual(42, c.atoll(@ptrCast("42true")));
    try testing.expectEqual(-1, c.atoll(@ptrCast("-01")));
    try testing.expectEqual(1, c.atoll(@ptrCast("+001")));
    try testing.expectEqual(100, c.atoll(@ptrCast("            100")));
    try testing.expectEqual(500, c.atoll(@ptrCast("000000000000500")));
    try testing.expectEqual(1111, c.atoll(@ptrCast("0000000000001111_0000")));
    try testing.expectEqual(0, c.atoll(@ptrCast("0xAA")));
    try testing.expectEqual(700, c.atoll(@ptrCast("700B")));
    try testing.expectEqual(32453, c.atoll(@ptrCast("   +32453more")));
    try testing.expectEqual(math.maxInt(c_longlong), c.atoll(@ptrCast(fmt.comptimePrint("{d}", .{math.maxInt(c_longlong)}))));
    try testing.expectEqual(math.minInt(c_longlong), c.atoll(@ptrCast(fmt.comptimePrint("{d}", .{math.minInt(c_longlong)}))));
}

fn testStrToLLikeFunction(
    func: anytype,
    str: [*:0]const c_char,
    base: c_int,
    expected: comptime_int,
    expected_len: ?usize,
    expected_errno: c.E,
) !void {
    var end_ptr: [*:0]c_char = undefined;
    try testing.expectEqual(expected, func(str, if (expected_len == null) null else &end_ptr, base));
    if (expected_len) |len| try testing.expectEqual(len, end_ptr - str);
    try expectErrno(expected_errno);
}

fn testStrToLLikeFunctionAnyErrno(
    func: anytype,
    str: [*:0]const c_char,
    base: c_int,
    expected: comptime_int,
    expected_len: ?usize,
    expected_errnos: []const c.E,
) !void {
    var end_ptr: [*:0]c_char = undefined;
    try testing.expectEqual(expected, func(str, if (expected_len == null) null else &end_ptr, base));
    if (expected_len) |len| try testing.expectEqual(len, end_ptr - str);
    try expectErrnoAny(expected_errnos);
}

test "strtol" {
    if (builtin.target.cpu.arch.isX86() and builtin.target.os.tag == .windows and builtin.target.abi == .msvc) return error.SkipZigTest; // TODO

    c._errno().* = @backingInt(c.E.SUCCESS);
    try testStrToLLikeFunctionAnyErrno(c.strtol, @ptrCast("stop42true"), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunction(c.strtol, @ptrCast("42true"), 0, 42, 2, .SUCCESS);
    try testStrToLLikeFunction(c.strtol, @ptrCast("-01"), 0, -1, 3, .SUCCESS);
    try testStrToLLikeFunction(c.strtol, @ptrCast("+001"), 0, 1, 4, .SUCCESS);
    try testStrToLLikeFunction(c.strtol, @ptrCast("            100"), 0, 100, 15, .SUCCESS);
    try testStrToLLikeFunction(c.strtol, @ptrCast("000000000000500"), 0, 0o500, 15, .SUCCESS);
    try testStrToLLikeFunction(c.strtol, @ptrCast("000000000000500"), 10, 500, 15, .SUCCESS);
    try testStrToLLikeFunction(c.strtol, @ptrCast("           0500"), 0, 0o500, 15, .SUCCESS);
    try testStrToLLikeFunction(c.strtol, @ptrCast("0000000000001111_0000"), 10, 1111, 16, .SUCCESS);
    try testStrToLLikeFunction(c.strtol, @ptrCast("            1111_0000"), 0, 1111, 16, .SUCCESS);
    try testStrToLLikeFunction(c.strtol, @ptrCast("0xAA"), 0, 0xAA, 4, .SUCCESS);
    try testStrToLLikeFunction(c.strtol, @ptrCast("0xAA"), 10, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtol, @ptrCast("0xAA"), 16, 0xAA, 4, .SUCCESS);
    try testStrToLLikeFunction(c.strtol, @ptrCast("0xAA"), 36, 43138, 4, .SUCCESS);
    try testStrToLLikeFunction(c.strtol, @ptrCast("700B"), 0, 700, 3, .SUCCESS);
    try testStrToLLikeFunction(c.strtol, @ptrCast("32453more"), 0, 32453, 5, .SUCCESS);
    try testStrToLLikeFunction(c.strtol, @ptrCast(fmt.comptimePrint("{d}", .{math.maxInt(c_long)})), 0, math.maxInt(c_long), null, .SUCCESS);
    try testStrToLLikeFunction(c.strtol, @ptrCast(fmt.comptimePrint("{d}", .{math.minInt(c_long)})), 0, math.minInt(c_long), null, .SUCCESS);
    try testStrToLLikeFunction(c.strtol, @ptrCast(fmt.comptimePrint("{d}", .{math.maxInt(c_long) + 1})), 0, math.maxInt(c_long), null, .RANGE);
    try testStrToLLikeFunction(c.strtol, @ptrCast(fmt.comptimePrint("{d}", .{math.minInt(c_long) - 1})), 0, math.minInt(c_long), null, .RANGE);
    try testStrToLLikeFunctionAnyErrno(c.strtol, @ptrCast(""), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunctionAnyErrno(c.strtol, @ptrCast(""), 12, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunctionAnyErrno(c.strtol, @ptrCast("-"), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunctionAnyErrno(c.strtol, @ptrCast(" -"), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunctionAnyErrno(c.strtol, @ptrCast(" "), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunction(c.strtol, @ptrCast("0"), 0, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtol, @ptrCast("0"), 8, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtol, @ptrCast("09"), 0, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtol, @ptrCast("09"), 10, 9, 2, .SUCCESS);
    if (builtin.os.tag != .windows)
        try testStrToLLikeFunction(c.strtol, @ptrCast("0x"), 0, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtol, @ptrCast("1"), 37, 0, null, .INVAL);
    try testStrToLLikeFunction(c.strtol, @ptrCast("1"), 1, 0, null, .INVAL);
    try testStrToLLikeFunction(c.strtol, @ptrCast("1"), -1, 0, null, .INVAL);
}

test "strtoll" {
    if (builtin.target.cpu.arch.isX86() and builtin.target.os.tag == .windows and builtin.target.abi == .msvc) return error.SkipZigTest; // TODO

    c._errno().* = @backingInt(c.E.SUCCESS);
    try testStrToLLikeFunctionAnyErrno(c.strtoll, @ptrCast("stop42true"), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunction(c.strtoll, @ptrCast("42true"), 0, 42, 2, .SUCCESS);
    try testStrToLLikeFunction(c.strtoll, @ptrCast("-01"), 0, -1, 3, .SUCCESS);
    try testStrToLLikeFunction(c.strtoll, @ptrCast("+001"), 0, 1, 4, .SUCCESS);
    try testStrToLLikeFunction(c.strtoll, @ptrCast("            100"), 0, 100, 15, .SUCCESS);
    try testStrToLLikeFunction(c.strtoll, @ptrCast("000000000000500"), 0, 0o500, 15, .SUCCESS);
    try testStrToLLikeFunction(c.strtoll, @ptrCast("000000000000500"), 10, 500, 15, .SUCCESS);
    try testStrToLLikeFunction(c.strtoll, @ptrCast("           0500"), 0, 0o500, 15, .SUCCESS);
    try testStrToLLikeFunction(c.strtoll, @ptrCast("0000000000001111_0000"), 10, 1111, 16, .SUCCESS);
    try testStrToLLikeFunction(c.strtoll, @ptrCast("            1111_0000"), 0, 1111, 16, .SUCCESS);
    try testStrToLLikeFunction(c.strtoll, @ptrCast("0xAA"), 0, 0xAA, 4, .SUCCESS);
    try testStrToLLikeFunction(c.strtoll, @ptrCast("0xAA"), 10, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoll, @ptrCast("0xAA"), 16, 0xAA, 4, .SUCCESS);
    try testStrToLLikeFunction(c.strtoll, @ptrCast("0xAA"), 36, 43138, 4, .SUCCESS);
    try testStrToLLikeFunction(c.strtoll, @ptrCast("700B"), 0, 700, 3, .SUCCESS);
    try testStrToLLikeFunction(c.strtoll, @ptrCast("32453more"), 0, 32453, 5, .SUCCESS);
    try testStrToLLikeFunction(c.strtoll, @ptrCast(fmt.comptimePrint("{d}", .{math.maxInt(c_longlong)})), 0, math.maxInt(c_longlong), null, .SUCCESS);
    try testStrToLLikeFunction(c.strtoll, @ptrCast(fmt.comptimePrint("{d}", .{math.minInt(c_longlong)})), 0, math.minInt(c_longlong), null, .SUCCESS);
    try testStrToLLikeFunction(c.strtoll, @ptrCast(fmt.comptimePrint("{d}", .{math.maxInt(c_longlong) + 1})), 0, math.maxInt(c_longlong), null, .RANGE);
    try testStrToLLikeFunction(c.strtoll, @ptrCast(fmt.comptimePrint("{d}", .{math.minInt(c_longlong) - 1})), 0, math.minInt(c_longlong), null, .RANGE);
    try testStrToLLikeFunctionAnyErrno(c.strtoll, @ptrCast(""), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunctionAnyErrno(c.strtoll, @ptrCast(""), 12, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunctionAnyErrno(c.strtoll, @ptrCast("-"), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunctionAnyErrno(c.strtoll, @ptrCast(" -"), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunctionAnyErrno(c.strtoll, @ptrCast(" "), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunction(c.strtoll, @ptrCast("0"), 0, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoll, @ptrCast("0"), 8, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoll, @ptrCast("09"), 0, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoll, @ptrCast("09"), 10, 9, 2, .SUCCESS);
    if (builtin.os.tag != .windows)
        try testStrToLLikeFunction(c.strtoll, @ptrCast("0x"), 0, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoll, @ptrCast("1"), 37, 0, null, .INVAL);
    try testStrToLLikeFunction(c.strtoll, @ptrCast("1"), 1, 0, null, .INVAL);
    try testStrToLLikeFunction(c.strtoll, @ptrCast("1"), -1, 0, null, .INVAL);
}

test "strtoul" {
    if (builtin.target.cpu.arch.isX86() and builtin.target.os.tag == .windows and builtin.target.abi == .msvc) return error.SkipZigTest; // TODO

    c._errno().* = @backingInt(c.E.SUCCESS);
    try testStrToLLikeFunctionAnyErrno(c.strtoul, @ptrCast("stop42true"), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunction(c.strtoul, @ptrCast("42true"), 0, 42, 2, .SUCCESS);
    try testStrToLLikeFunction(c.strtoul, @ptrCast("-01"), 0, math.maxInt(c_ulong), 3, .SUCCESS);
    try testStrToLLikeFunction(c.strtoul, @ptrCast("+001"), 0, 1, 4, .SUCCESS);
    try testStrToLLikeFunction(c.strtoul, @ptrCast("            100"), 0, 100, 15, .SUCCESS);
    try testStrToLLikeFunction(c.strtoul, @ptrCast("000000000000500"), 0, 0o500, 15, .SUCCESS);
    try testStrToLLikeFunction(c.strtoul, @ptrCast("000000000000500"), 10, 500, 15, .SUCCESS);
    try testStrToLLikeFunction(c.strtoul, @ptrCast("           0500"), 0, 0o500, 15, .SUCCESS);
    try testStrToLLikeFunction(c.strtoul, @ptrCast("0000000000001111_0000"), 10, 1111, 16, .SUCCESS);
    try testStrToLLikeFunction(c.strtoul, @ptrCast("            1111_0000"), 0, 1111, 16, .SUCCESS);
    try testStrToLLikeFunction(c.strtoul, @ptrCast("0xAA"), 0, 0xAA, 4, .SUCCESS);
    try testStrToLLikeFunction(c.strtoul, @ptrCast("0xAA"), 10, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoul, @ptrCast("0xAA"), 16, 0xAA, 4, .SUCCESS);
    try testStrToLLikeFunction(c.strtoul, @ptrCast("0xAA"), 36, 43138, 4, .SUCCESS);
    try testStrToLLikeFunction(c.strtoul, @ptrCast("700B"), 0, 700, 3, .SUCCESS);
    try testStrToLLikeFunction(c.strtoul, @ptrCast("32453more"), 0, 32453, 5, .SUCCESS);
    try testStrToLLikeFunction(c.strtoul, @ptrCast(fmt.comptimePrint("{d}", .{math.maxInt(c_ulong)})), 0, math.maxInt(c_ulong), null, .SUCCESS);
    try testStrToLLikeFunction(c.strtoul, @ptrCast(fmt.comptimePrint("{d}", .{math.maxInt(c_ulong) + 1})), 0, math.maxInt(c_ulong), null, .RANGE);
    try testStrToLLikeFunctionAnyErrno(c.strtoul, @ptrCast(""), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunctionAnyErrno(c.strtoul, @ptrCast(""), 12, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunctionAnyErrno(c.strtoul, @ptrCast("-"), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunctionAnyErrno(c.strtoul, @ptrCast(" -"), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunctionAnyErrno(c.strtoul, @ptrCast(" "), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunction(c.strtoul, @ptrCast("0"), 0, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoul, @ptrCast("0"), 8, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoul, @ptrCast("09"), 0, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoul, @ptrCast("09"), 10, 9, 2, .SUCCESS);
    if (builtin.os.tag != .windows)
        try testStrToLLikeFunction(c.strtoul, @ptrCast("0x"), 0, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoul, @ptrCast("1"), 37, 0, null, .INVAL);
    try testStrToLLikeFunction(c.strtoul, @ptrCast("1"), 1, 0, null, .INVAL);
    try testStrToLLikeFunction(c.strtoul, @ptrCast("1"), -1, 0, null, .INVAL);
}

test "strtoull" {
    if (builtin.target.cpu.arch.isX86() and builtin.target.os.tag == .windows and builtin.target.abi == .msvc) return error.SkipZigTest; // TODO

    c._errno().* = @backingInt(c.E.SUCCESS);
    try testStrToLLikeFunctionAnyErrno(c.strtoull, @ptrCast("stop42true"), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunction(c.strtoull, @ptrCast("42true"), 0, 42, 2, .SUCCESS);
    try testStrToLLikeFunction(c.strtoull, @ptrCast("-01"), 0, math.maxInt(c_ulonglong), 3, .SUCCESS);
    try testStrToLLikeFunction(c.strtoull, @ptrCast("+001"), 0, 1, 4, .SUCCESS);
    try testStrToLLikeFunction(c.strtoull, @ptrCast("            100"), 0, 100, 15, .SUCCESS);
    try testStrToLLikeFunction(c.strtoull, @ptrCast("000000000000500"), 0, 0o500, 15, .SUCCESS);
    try testStrToLLikeFunction(c.strtoull, @ptrCast("000000000000500"), 10, 500, 15, .SUCCESS);
    try testStrToLLikeFunction(c.strtoull, @ptrCast("           0500"), 0, 0o500, 15, .SUCCESS);
    try testStrToLLikeFunction(c.strtoull, @ptrCast("0000000000001111_0000"), 10, 1111, 16, .SUCCESS);
    try testStrToLLikeFunction(c.strtoull, @ptrCast("            1111_0000"), 0, 1111, 16, .SUCCESS);
    try testStrToLLikeFunction(c.strtoull, @ptrCast("0xAA"), 0, 0xAA, 4, .SUCCESS);
    try testStrToLLikeFunction(c.strtoull, @ptrCast("0xAA"), 10, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoull, @ptrCast("0xAA"), 16, 0xAA, 4, .SUCCESS);
    try testStrToLLikeFunction(c.strtoull, @ptrCast("0xAA"), 36, 43138, 4, .SUCCESS);
    try testStrToLLikeFunction(c.strtoull, @ptrCast("700B"), 0, 700, 3, .SUCCESS);
    try testStrToLLikeFunction(c.strtoull, @ptrCast("32453more"), 0, 32453, 5, .SUCCESS);
    try testStrToLLikeFunction(c.strtoull, @ptrCast(fmt.comptimePrint("{d}", .{math.maxInt(c_ulonglong)})), 0, math.maxInt(c_ulonglong), null, .SUCCESS);
    try testStrToLLikeFunction(c.strtoull, @ptrCast(fmt.comptimePrint("{d}", .{math.maxInt(c_ulonglong) + 1})), 0, math.maxInt(c_ulonglong), null, .RANGE);
    try testStrToLLikeFunctionAnyErrno(c.strtoull, @ptrCast(""), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunctionAnyErrno(c.strtoull, @ptrCast(""), 12, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunctionAnyErrno(c.strtoull, @ptrCast("-"), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunctionAnyErrno(c.strtoull, @ptrCast(" -"), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunctionAnyErrno(c.strtoull, @ptrCast(" "), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunction(c.strtoull, @ptrCast("0"), 0, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoull, @ptrCast("0"), 8, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoull, @ptrCast("09"), 0, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoull, @ptrCast("09"), 10, 9, 2, .SUCCESS);
    if (builtin.os.tag != .windows)
        try testStrToLLikeFunction(c.strtoull, @ptrCast("0x"), 0, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoull, @ptrCast("1"), 37, 0, null, .INVAL);
    try testStrToLLikeFunction(c.strtoull, @ptrCast("1"), 1, 0, null, .INVAL);
    try testStrToLLikeFunction(c.strtoull, @ptrCast("1"), -1, 0, null, .INVAL);
}

test "strtoimax" {
    if (builtin.target.cpu.arch.isX86() and builtin.target.os.tag == .windows and builtin.target.abi == .msvc) return error.SkipZigTest; // TODO

    c._errno().* = @backingInt(c.E.SUCCESS);
    try testStrToLLikeFunctionAnyErrno(c.strtoimax, @ptrCast("stop42true"), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunction(c.strtoimax, @ptrCast("42true"), 0, 42, 2, .SUCCESS);
    try testStrToLLikeFunction(c.strtoimax, @ptrCast("-01"), 0, -1, 3, .SUCCESS);
    try testStrToLLikeFunction(c.strtoimax, @ptrCast("+001"), 0, 1, 4, .SUCCESS);
    try testStrToLLikeFunction(c.strtoimax, @ptrCast("            100"), 0, 100, 15, .SUCCESS);
    try testStrToLLikeFunction(c.strtoimax, @ptrCast("000000000000500"), 0, 0o500, 15, .SUCCESS);
    try testStrToLLikeFunction(c.strtoimax, @ptrCast("000000000000500"), 10, 500, 15, .SUCCESS);
    try testStrToLLikeFunction(c.strtoimax, @ptrCast("           0500"), 0, 0o500, 15, .SUCCESS);
    try testStrToLLikeFunction(c.strtoimax, @ptrCast("0000000000001111_0000"), 10, 1111, 16, .SUCCESS);
    try testStrToLLikeFunction(c.strtoimax, @ptrCast("            1111_0000"), 0, 1111, 16, .SUCCESS);
    try testStrToLLikeFunction(c.strtoimax, @ptrCast("0xAA"), 0, 0xAA, 4, .SUCCESS);
    try testStrToLLikeFunction(c.strtoimax, @ptrCast("0xAA"), 10, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoimax, @ptrCast("0xAA"), 16, 0xAA, 4, .SUCCESS);
    try testStrToLLikeFunction(c.strtoimax, @ptrCast("0xAA"), 36, 43138, 4, .SUCCESS);
    try testStrToLLikeFunction(c.strtoimax, @ptrCast("700B"), 0, 700, 3, .SUCCESS);
    try testStrToLLikeFunction(c.strtoimax, @ptrCast("32453more"), 0, 32453, 5, .SUCCESS);
    try testStrToLLikeFunction(c.strtoimax, @ptrCast(fmt.comptimePrint("{d}", .{math.maxInt(c.intmax_t)})), 0, math.maxInt(c.intmax_t), null, .SUCCESS);
    try testStrToLLikeFunction(c.strtoimax, @ptrCast(fmt.comptimePrint("{d}", .{math.minInt(c.intmax_t)})), 0, math.minInt(c.intmax_t), null, .SUCCESS);
    try testStrToLLikeFunction(c.strtoimax, @ptrCast(fmt.comptimePrint("{d}", .{math.maxInt(c.intmax_t) + 1})), 0, math.maxInt(c.intmax_t), null, .RANGE);
    try testStrToLLikeFunction(c.strtoimax, @ptrCast(fmt.comptimePrint("{d}", .{math.minInt(c.intmax_t) - 1})), 0, math.minInt(c.intmax_t), null, .RANGE);
    try testStrToLLikeFunctionAnyErrno(c.strtoimax, @ptrCast(""), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunctionAnyErrno(c.strtoimax, @ptrCast(""), 12, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunctionAnyErrno(c.strtoimax, @ptrCast("-"), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunctionAnyErrno(c.strtoimax, @ptrCast(" -"), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunctionAnyErrno(c.strtoimax, @ptrCast(" "), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunction(c.strtoimax, @ptrCast("0"), 0, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoimax, @ptrCast("0"), 8, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoimax, @ptrCast("09"), 0, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoimax, @ptrCast("09"), 10, 9, 2, .SUCCESS);
    if (builtin.os.tag != .windows)
        try testStrToLLikeFunction(c.strtoimax, @ptrCast("0x"), 0, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoimax, @ptrCast("1"), 37, 0, null, .INVAL);
    try testStrToLLikeFunction(c.strtoimax, @ptrCast("1"), 1, 0, null, .INVAL);
    try testStrToLLikeFunction(c.strtoimax, @ptrCast("1"), -1, 0, null, .INVAL);
}

test "strtoumax" {
    if (builtin.target.cpu.arch.isX86() and builtin.target.os.tag == .windows and builtin.target.abi == .msvc) return error.SkipZigTest; // TODO

    c._errno().* = @backingInt(c.E.SUCCESS);
    try testStrToLLikeFunctionAnyErrno(c.strtoumax, @ptrCast("stop42true"), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunction(c.strtoumax, @ptrCast("42true"), 0, 42, 2, .SUCCESS);
    try testStrToLLikeFunction(c.strtoumax, @ptrCast("-01"), 0, math.maxInt(c.uintmax_t), 3, .SUCCESS);
    try testStrToLLikeFunction(c.strtoumax, @ptrCast("+001"), 0, 1, 4, .SUCCESS);
    try testStrToLLikeFunction(c.strtoumax, @ptrCast("            100"), 0, 100, 15, .SUCCESS);
    try testStrToLLikeFunction(c.strtoumax, @ptrCast("000000000000500"), 0, 0o500, 15, .SUCCESS);
    try testStrToLLikeFunction(c.strtoumax, @ptrCast("000000000000500"), 10, 500, 15, .SUCCESS);
    try testStrToLLikeFunction(c.strtoumax, @ptrCast("           0500"), 0, 0o500, 15, .SUCCESS);
    try testStrToLLikeFunction(c.strtoumax, @ptrCast("0000000000001111_0000"), 10, 1111, 16, .SUCCESS);
    try testStrToLLikeFunction(c.strtoumax, @ptrCast("            1111_0000"), 0, 1111, 16, .SUCCESS);
    try testStrToLLikeFunction(c.strtoumax, @ptrCast("0xAA"), 0, 0xAA, 4, .SUCCESS);
    try testStrToLLikeFunction(c.strtoumax, @ptrCast("0xAA"), 10, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoumax, @ptrCast("0xAA"), 16, 0xAA, 4, .SUCCESS);
    try testStrToLLikeFunction(c.strtoumax, @ptrCast("0xAA"), 36, 43138, 4, .SUCCESS);
    try testStrToLLikeFunction(c.strtoumax, @ptrCast("700B"), 0, 700, 3, .SUCCESS);
    try testStrToLLikeFunction(c.strtoumax, @ptrCast("32453more"), 0, 32453, 5, .SUCCESS);
    try testStrToLLikeFunction(c.strtoumax, @ptrCast(fmt.comptimePrint("{d}", .{math.maxInt(c_ulonglong)})), 0, math.maxInt(c_ulonglong), null, .SUCCESS);
    try testStrToLLikeFunction(c.strtoumax, @ptrCast(fmt.comptimePrint("{d}", .{math.maxInt(c_ulonglong) + 1})), 0, math.maxInt(c_ulonglong), null, .RANGE);
    try testStrToLLikeFunctionAnyErrno(c.strtoumax, @ptrCast(""), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunctionAnyErrno(c.strtoumax, @ptrCast(""), 12, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunctionAnyErrno(c.strtoumax, @ptrCast("-"), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunctionAnyErrno(c.strtoumax, @ptrCast(" -"), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunctionAnyErrno(c.strtoumax, @ptrCast(" "), 0, 0, 0, &.{ .SUCCESS, .INVAL });
    try testStrToLLikeFunction(c.strtoumax, @ptrCast("0"), 0, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoumax, @ptrCast("0"), 8, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoumax, @ptrCast("09"), 0, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoumax, @ptrCast("09"), 10, 9, 2, .SUCCESS);
    if (builtin.os.tag != .windows)
        try testStrToLLikeFunction(c.strtoumax, @ptrCast("0x"), 0, 0, 1, .SUCCESS);
    try testStrToLLikeFunction(c.strtoumax, @ptrCast("1"), 37, 0, null, .INVAL);
    try testStrToLLikeFunction(c.strtoumax, @ptrCast("1"), 1, 0, null, .INVAL);
    try testStrToLLikeFunction(c.strtoumax, @ptrCast("1"), -1, 0, null, .INVAL);
}

test "bsearch" {
    const Comparison = struct {
        pub fn compare(a: *const anyopaque, b: *const anyopaque) callconv(.c) c_int {
            const a_u16: *const u16 = @ptrCast(@alignCast(a));
            const b_u16: *const u16 = @ptrCast(@alignCast(b));

            return switch (math.order(a_u16.*, b_u16.*)) {
                .gt => 1,
                .eq => 0,
                .lt => -1,
            };
        }
    };

    const items: []const u16 = &.{ 0, 5, 7, 9, 10, 200, 512, 768 };

    try testing.expectEqual(@as(?*anyopaque, null), c.bsearch(&@as(u16, 2000), items.ptr, items.len, @sizeOf(u16), Comparison.compare));

    for (items) |*value| {
        try testing.expectEqual(@as(*const anyopaque, value), c.bsearch(value, items.ptr, items.len, @sizeOf(u16), Comparison.compare));
    }
}

test {
    _ = @import("stdlib/drand48.zig");
}
