const expectEqual = @import("std").testing.expectEqual;

test "while basic" {
    var i: usize = 0;
    while (i < 10) {
        i += 1;
    }
    try expectEqual(10, i);
}

// test
