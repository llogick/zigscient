const std = @import("std");
const testing = std.testing;

pub extern "c" fn printf(format: [*:0]const u8, ...) c_int;

test "variadic function" {
    try testing.expectEqual(14, printf("Hello, world!\n"));
    try testing.expect(@typeInfo(@TypeOf(printf)).@"fn".attrs.varargs);
}

// test
// link_libc
