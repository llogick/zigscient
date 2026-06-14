const std = @import("std");
const expectEqual = std.testing.expectEqual;

test {
    const a = {};
    try expectEqual(void, @TypeOf(a));
}

// test
