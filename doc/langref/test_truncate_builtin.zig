const std = @import("std");
const expectEqual = std.testing.expectEqual;

test "integer truncation" {
    const a: u16 = 0xabcd;
    const b: u8 = @truncate(a);
    try expectEqual(0xcd, b);
}

// test
