const std = @import("std");
const expectEqual = std.testing.expectEqual;

test "coercion to error unions" {
    const x: anyerror!i32 = 1234;
    const y: anyerror!i32 = error.Failure;

    try expectEqual(1234, (try x));
    try std.testing.expectError(error.Failure, y);
}

// test
