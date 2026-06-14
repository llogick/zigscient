const std = @import("std");
const expectEqual = std.testing.expectEqual;

test "coercing large integer type to smaller one when value is comptime-known to fit" {
    const x: u64 = 255;
    const y: u8 = x;
    try expectEqual(255, y);
}

// test
