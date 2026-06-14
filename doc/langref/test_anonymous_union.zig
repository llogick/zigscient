const std = @import("std");
const expectEqual = std.testing.expectEqual;

const Number = union {
    int: i32,
    float: f64,
};

test "anonymous union literal syntax" {
    const i: Number = .{ .int = 42 };
    const f = makeNumber();
    try expectEqual(42, i.int);
    try expectEqual(12.34, f.float);
}

fn makeNumber() Number {
    return .{ .float = 12.34 };
}

// test
