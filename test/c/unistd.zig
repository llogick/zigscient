const builtin = @import("builtin");
const std = @import("std");

const c = std.c;
const testing = std.testing;

test "swab" {
    if (builtin.target.cpu.arch.isMIPS64() and @sizeOf(usize) == 4) return error.SkipZigTest; // TODO
    if (builtin.target.cpu.arch == .x86_64 and @sizeOf(usize) == 4) return error.SkipZigTest; // TODO
    if (builtin.target.os.tag == .netbsd) return error.SkipZigTest; // TODO
    if (builtin.target.cpu.arch.isX86() and builtin.target.os.tag == .windows and builtin.target.abi == .msvc) return error.SkipZigTest; // TODO

    var a: [4]u8 = undefined;
    @memset(a[0..], '\x00');
    c.swab("abcd", &a, 4);
    try testing.expectEqualSlices(u8, "badc", &a);

    // Partial copy
    @memset(a[0..], '\x00');
    c.swab("abcd", &a, 2);
    try testing.expectEqualSlices(u8, "ba\x00\x00", &a);

    // n < 1
    @memset(a[0..], '\x00');
    c.swab("abcd", &a, 0);
    try testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, &a);
    c.swab("abcd", &a, -1);
    try testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, &a);

    // Odd n
    @memset(a[0..], '\x00');
    c.swab("abcd", &a, 1);
    try testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, &a);
    c.swab("abcd", &a, 3);
    try testing.expectEqualSlices(u8, "ba\x00\x00", &a);
}
