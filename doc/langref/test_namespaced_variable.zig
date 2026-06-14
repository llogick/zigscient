const std = @import("std");
const expectEqual = std.testing.expectEqual;

test "namespaced container level variable" {
    try expectEqual(1235, foo());
    try expectEqual(1236, foo());
}

const S = struct {
    var x: i32 = 1234;
};

fn foo() i32 {
    S.x += 1;
    return S.x;
}

// test
