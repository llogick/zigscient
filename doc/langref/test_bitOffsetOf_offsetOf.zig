const std = @import("std");
const expectEqual = std.testing.expectEqual;

const BitField = packed struct {
    a: u3,
    b: u3,
    c: u2,
};

test "offsets of non-byte-aligned fields" {
    comptime {
        try expectEqual(0, @bitOffsetOf(BitField, "a"));
        try expectEqual(3, @bitOffsetOf(BitField, "b"));
        try expectEqual(6, @bitOffsetOf(BitField, "c"));

        try expectEqual(0, @offsetOf(BitField, "a"));
        try expectEqual(0, @offsetOf(BitField, "b"));
        try expectEqual(0, @offsetOf(BitField, "c"));
    }
}

// test
