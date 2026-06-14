const std = @import("std");
const expectEqual = std.testing.expectEqual;

const Point = struct {
    x: u32,
    y: u32,

    pub var z: u32 = 1;
};

test "field access by string" {
    var p = Point{ .x = 0, .y = 0 };

    @field(p, "x") = 4;
    @field(p, "y") = @field(p, "x") + 1;

    try expectEqual(4, @field(p, "x"));
    try expectEqual(5, @field(p, "y"));
}

test "decl access by string" {
    try expectEqual(1, @field(Point, "z"));

    @field(Point, "z") = 2;
    try expectEqual(2, @field(Point, "z"));
}

// test
