const std = @import("std");
const expectEqual = std.testing.expectEqual;
const minInt = std.math.minInt;
const maxInt = std.math.maxInt;

test "wraparound addition and subtraction" {
    const x: i32 = maxInt(i32);
    const min_val = x +% 1;
    try expectEqual(minInt(i32), min_val);
    const max_val = min_val -% 1;
    try expectEqual(maxInt(i32), max_val);
}

// test
