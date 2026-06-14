const std = @import("std");
const expectEqual = std.testing.expectEqual;

test "coerce to optionals wrapped in error union" {
    const x: anyerror!?i32 = 1234;
    const y: anyerror!?i32 = null;

    try expectEqual(1234, (try x).?);
    try expectEqual(null, (try y));
}

// test
