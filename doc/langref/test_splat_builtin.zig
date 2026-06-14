const std = @import("std");
const expectEqualSlices = std.testing.expectEqualSlices;

test "vector @splat" {
    const scalar: u32 = 5;
    const result: @Vector(4, u32) = @splat(scalar);
    try expectEqualSlices(u32, &[_]u32{ 5, 5, 5, 5 }, &@as([4]u32, result));
}

test "array @splat" {
    const scalar: u32 = 5;
    const result: [4]u32 = @splat(scalar);
    try expectEqualSlices(u32, &[_]u32{ 5, 5, 5, 5 }, &@as([4]u32, result));
}

// test
