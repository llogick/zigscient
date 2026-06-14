const std = @import("std");
const expectEqual = std.testing.expectEqual;

test "0-terminated slice" {
    const slice: [:0]const u8 = "hello";

    try expectEqual(5, slice.len);
    try expectEqual(0, slice[5]);
}

// test
