const std = @import("std");
const expectEqual = std.testing.expectEqual;

const BitField = packed struct {
    a: u3,
    b: u3,
    c: u2,
};

var bit_field = BitField{
    .a = 1,
    .b = 2,
    .c = 3,
};

test "pointers of sub-byte-aligned fields share addresses" {
    try expectEqual(@intFromPtr(&bit_field.a), @intFromPtr(&bit_field.b));
    try expectEqual(@intFromPtr(&bit_field.a), @intFromPtr(&bit_field.c));
}

// test
