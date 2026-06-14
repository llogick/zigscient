const expectEqual = @import("std").testing.expectEqual;

test "while break" {
    var i: usize = 0;
    while (true) {
        if (i == 10)
            break;
        i += 1;
    }
    try expectEqual(10, i);
}

// test
