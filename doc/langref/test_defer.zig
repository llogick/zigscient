const std = @import("std");
const expectEqual = std.testing.expectEqual;
const print = std.debug.print;

fn deferExample() !usize {
    var a: usize = 1;

    {
        defer a = 2;
        a = 1;
    }
    try expectEqual(2, a);

    a = 5;
    return a;
}

test "defer basics" {
    try expectEqual(5, (try deferExample()));
}

// test
