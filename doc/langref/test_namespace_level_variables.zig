var y: i32 = add(10, x);
const x: i32 = add(12, 34);

test "container level variables" {
    try expectEqual(46, x);
    try expectEqual(56, y);
}

fn add(a: i32, b: i32) i32 {
    return a + b;
}

const std = @import("std");
const expectEqual = std.testing.expectEqual;

// test
