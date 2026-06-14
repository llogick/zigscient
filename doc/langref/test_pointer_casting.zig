const std = @import("std");
const expectEqual = std.testing.expectEqual;

test "pointer casting" {
    const bytes align(@alignOf(u32)) = [_]u8{ 0x12, 0x12, 0x12, 0x12 };
    const u32_ptr: *const u32 = @ptrCast(&bytes);
    try expectEqual(0x12121212, u32_ptr.*);

    // Even this example is contrived - there are better ways to do the above than
    // pointer casting. For example, using a slice narrowing cast:
    const u32_value = std.mem.bytesAsSlice(u32, bytes[0..])[0];
    try expectEqual(0x12121212, u32_value);

    // And even another way, the most straightforward way to do it:
    try expectEqual(0x12121212, @as(u32, @bitCast(bytes)));
}

test "pointer child type" {
    // pointer types have a `child` field which tells you the type they point to.
    try expectEqual(u32, @typeInfo(*u32).pointer.child);
}

// test
