const std = @import("std");
const expectEqual = std.testing.expectEqual;

test "static local variable" {
    try expectEqual(1235, foo());
    try expectEqual(1236, foo());
}

fn foo() i32 {
    const S = struct {
        var x: i32 = 1234;
    };
    S.x += 1;
    return S.x;
}

// test
