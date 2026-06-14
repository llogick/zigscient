const expectEqual = @import("std").testing.expectEqual;

fn fibonacci(index: u32) u32 {
    if (index < 2) return index;
    return fibonacci(index - 1) + fibonacci(index - 2);
}

test "fibonacci" {
    // test fibonacci at run-time
    try expectEqual(13, fibonacci(7));

    // test fibonacci at compile-time
    try comptime expectEqual(13, fibonacci(7));
}

// test
