const std = @import("std");
const expectEqual = std.testing.expectEqual;

test "implicit integer to float" {
    var int: u8 = 123;
    _ = &int;
    const float: f32 = int;
    const int_from_float: u8 = @intFromFloat(float);
    try expectEqual(int, int_from_float);
}

// test
