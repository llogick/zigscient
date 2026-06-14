const std = @import("std");
const expectEqualSlices = std.testing.expectEqualSlices;

const Small2 = union(enum) {
    a: i32,
    b: bool,
    c: u8,
};
test "@tagName" {
    try expectEqualSlices(u8, "a", @tagName(Small2.a));
}

// test
