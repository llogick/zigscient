const std = @import("std");
const expectEqual = std.testing.expectEqual;

test "vector @reduce" {
    const V = @Vector(4, i32);
    const value = V{ 1, -1, 1, -1 };
    const result = value > @as(V, @splat(0));
    // result is { true, false, true, false };
    try comptime expectEqual(@Vector(4, bool), @TypeOf(result));
    const is_all_true = @reduce(.And, result);
    try comptime expectEqual(bool, @TypeOf(is_all_true));
    try expectEqual(false, is_all_true);
}

// test
