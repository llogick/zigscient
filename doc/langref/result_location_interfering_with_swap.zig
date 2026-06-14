const expectEqual = @import("std").testing.expectEqual;
test "attempt to swap array elements with array initializer" {
    var arr: [2]u32 = .{ 1, 2 };
    arr = .{ arr[1], arr[0] };
    // The previous line is equivalent to the following two lines:
    //   arr[0] = arr[1];
    //   arr[1] = arr[0];
    // So this fails!
    try expectEqual(2, arr[0]); // succeeds
    try expectEqual(1, arr[1]); // fails
}

// test_error=
