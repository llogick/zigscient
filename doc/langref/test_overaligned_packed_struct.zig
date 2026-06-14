const std = @import("std");
const expectEqual = std.testing.expectEqual;

const S = packed struct {
    a: u32,
    b: u32,
};
test "overaligned pointer to packed struct" {
    var foo: S align(4) = .{ .a = 1, .b = 2 };
    const ptr: *align(4) S = &foo;
    const ptr_to_b = &ptr.b;
    try expectEqual(2, ptr_to_b.*);
}

// test
