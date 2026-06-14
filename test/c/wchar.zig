const builtin = @import("builtin");
const std = @import("std");

const c = std.c;
const testing = std.testing;

test "wcsdup" {
    const org: [*:0]const c.wchar_t = &[_:0]c.wchar_t{ 'H', 'e', 'l', 'l', 'o' };
    const cpy_opt = c.wcsdup(org);
    const cpy = cpy_opt orelse return error.OutOfMemory;
    defer c.free(cpy);

    try testing.expectEqual(@as(usize, 5), std.mem.len(@as([*:0]const c.wchar_t, cpy)));

    try testing.expectEqual(@as(c.wchar_t, 'H'), cpy[0]);
    try testing.expectEqual(@as(c.wchar_t, 'e'), cpy[1]);
    try testing.expectEqual(@as(c.wchar_t, 'l'), cpy[2]);
    try testing.expectEqual(@as(c.wchar_t, 'l'), cpy[3]);
    try testing.expectEqual(@as(c.wchar_t, 'o'), cpy[4]);
    try testing.expectEqual(@as(c.wchar_t, 0), cpy[5]);

    try testing.expect(@intFromPtr(cpy) != @intFromPtr(org));

    cpy[0] = 'B';
    try testing.expectEqual(@as(c.wchar_t, 'H'), org[0]);
    try testing.expectEqual(@as(c.wchar_t, 'B'), cpy[0]);
}

test "wcsdup empty string" {
    const org: [*:0]const c.wchar_t = &[_:0]c.wchar_t{};
    const cpy = c.wcsdup(org) orelse return error.OutOfMemory;
    defer c.free(cpy);
    try testing.expectEqual(@as(c.wchar_t, 0), cpy[0]);
}
