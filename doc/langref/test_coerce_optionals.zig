const std = @import("std");
const expectEqual = std.testing.expectEqual;

test "coerce to optionals" {
    const x: ?i32 = 1234;
    const y: ?i32 = null;

    try expectEqual(1234, x.?);
    try expectEqual(null, y);
}

// test
