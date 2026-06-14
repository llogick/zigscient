const expectEqual = @import("std").testing.expectEqual;

fn addFortyTwo(x: anytype) @TypeOf(x) {
    return x + 42;
}

test "fn type inference" {
    try expectEqual(43, addFortyTwo(1));
    try expectEqual(comptime_int, @TypeOf(addFortyTwo(1)));
    const y: i64 = 2;
    try expectEqual(44, addFortyTwo(y));
    try expectEqual(i64, @TypeOf(addFortyTwo(y)));
}

// test
