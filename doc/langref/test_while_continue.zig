const expectEqual = @import("std").testing.expectEqual;

test "while continue" {
    var i: usize = 0;
    while (true) {
        i += 1;
        if (i < 10)
            continue;
        break;
    }
    try expectEqual(10, i);
}

// test
