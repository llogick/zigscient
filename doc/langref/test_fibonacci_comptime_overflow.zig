const expectEqual = @import("std").testing.expectEqual;

fn fibonacci(index: u32) u32 {
    //if (index < 2) return index;
    return fibonacci(index - 1) + fibonacci(index - 2);
}

test "fibonacci" {
    try comptime expectEqual(13, fibonacci(7));
}

// test_error=overflow of integer type
