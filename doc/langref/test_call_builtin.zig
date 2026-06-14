const expectEqual = @import("std").testing.expectEqual;

test "noinline function call" {
    try expectEqual(12, @call(.auto, add, .{ 3, 9 }));
}

fn add(a: i32, b: i32) i32 {
    return a + b;
}

// test
