const std = @import("std");
const builtin = @import("builtin");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "variable alignment" {
    var x: i32 = 1234;

    try expectEqual(*i32, @TypeOf(&x));

    try expect(@intFromPtr(&x) % @alignOf(i32) == 0);

    // The implicitly-aligned pointer can be coerced to be explicitly-aligned to
    // the alignment of the underlying type `i32`:
    const ptr: *align(@alignOf(i32)) i32 = &x;

    try expectEqual(1234, ptr.*);
}

// test
