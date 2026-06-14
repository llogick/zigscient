const std = @import("std");
const expectEqual = std.testing.expectEqual;

test "labeled break from labeled block expression" {
    var y: i32 = 123;

    const x = blk: {
        y += 1;
        break :blk y;
    };
    try expectEqual(124, x);
    try expectEqual(124, y);
}

// test
