const builtin = @import("builtin");
const std = @import("std");

const c = std.c;
const testing = std.testing;

test "strncmp" {
    try testing.expect(c.strncmp(@ptrCast("a"), @ptrCast("b"), 1) < 0);
    try testing.expect(c.strncmp(@ptrCast("a"), @ptrCast("c"), 1) < 0);
    try testing.expect(c.strncmp(@ptrCast("b"), @ptrCast("a"), 1) > 0);
    try testing.expect(c.strncmp(@ptrCast("\xff"), @ptrCast("\x02"), 1) > 0);
}

test "strdup" {
    const org: [*:0]const u8 = "a";
    const cpy_opt = c.strdup(@ptrCast(org));
    const cpy = cpy_opt orelse return error.OutOfMemory;
    defer c.free(cpy);

    const cpy_u8: [*:0]u8 = @ptrCast(cpy);
    try testing.expectEqualStrings(std.mem.span(org), std.mem.span(@as([*:0]const u8, cpy_u8)));
    try testing.expect(@intFromPtr(cpy_u8) != @intFromPtr(org));

    cpy_u8[0] = 'b';
    try testing.expectEqualStrings("a", std.mem.span(org));
    try testing.expectEqualStrings("b", std.mem.span(@as([*:0]const u8, cpy_u8)));
}

test "strndup" {
    if (builtin.target.os.tag == .windows) return; // no strndup
    const org1: [*:0]const u8 = "Hello";

    const copy1_opt = c.strndup(@ptrCast(org1), 100);
    const copy1 = copy1_opt orelse return error.OutOfMemory;
    defer c.free(copy1);
    const copy1_u8: [*:0]u8 = @ptrCast(copy1);
    try testing.expectEqualStrings("Hello", std.mem.span(@as([*:0]const u8, copy1_u8)));

    const org2: [*:0]const u8 = "Hello World!";
    const copy2_opt = c.strndup(@ptrCast(org2), 5);
    const copy2 = copy2_opt orelse return error.OutOfMemory;
    defer c.free(copy2);
    const copy2_u8: [*:0]u8 = @ptrCast(copy2);
    try testing.expectEqualStrings("Hello", std.mem.span(@as([*:0]const u8, copy2_u8)));
    try testing.expectEqual(@as(usize, 5), std.mem.len(copy2_u8));

    const copy3_opt = c.strndup(@ptrCast(org1), 5);
    const copy3 = copy3_opt orelse return error.OutOfMemory;
    defer c.free(copy3);
    const copy3_u8: [*:0]u8 = @ptrCast(copy3);
    try testing.expectEqualStrings("Hello", std.mem.span(@as([*:0]const u8, copy3_u8)));
}
