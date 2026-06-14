const expectEqual = @import("std").testing.expectEqual;

test "@round" {
    try expectEqual(1, @round(1.4));
    try expectEqual(2, @round(1.5));
    try expectEqual(-1, @round(-1.4));
    try expectEqual(-3, @round(-2.5));
}

// test
