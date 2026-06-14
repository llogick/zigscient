const std = @import("std");
const expectEqual = std.testing.expectEqual;

const Point = struct { x: i32, y: i32 };

test "anonymous struct literal" {
    const pt: Point = .{
        .x = 13,
        .y = 67,
    };
    try expectEqual(13, pt.x);
    try expectEqual(67, pt.y);
}

// test
