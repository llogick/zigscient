const std = @import("std");
const expectEqual = std.testing.expectEqual;

const Tagged = union(enum(u32)) {
    int: i64 = 123,
    boolean: bool = 67,
};

test "tag values" {
    const int: Tagged = .{ .int = -40 };
    try expectEqual(123, @intFromEnum(int));

    const boolean: Tagged = .{ .boolean = false };
    try expectEqual(67, @intFromEnum(boolean));
}

// test
