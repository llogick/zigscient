const std = @import("std");
const expectEqual = std.testing.expectEqual;

const Payload = union {
    int: i64,
    float: f64,
    boolean: bool,
};
test "simple union" {
    var payload = Payload{ .int = 1234 };
    try expectEqual(1234, payload.int);
    payload = Payload{ .float = 12.34 };
    try expectEqual(12.34, payload.float);
}

// test
