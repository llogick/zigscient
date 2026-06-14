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

test "pointer to non-byte-aligned field" {
    try expectEqual(2, bar(&bit_field.b));
}

fn bar(x: *const u3) u3 {
    return x.*;
}

// test_error=expected type
