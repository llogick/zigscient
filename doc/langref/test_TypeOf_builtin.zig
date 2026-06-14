const std = @import("std");
const expectEqual = std.testing.expectEqual;

test "no runtime side effects" {
    var data: i32 = 0;
    const T = @TypeOf(foo(i32, &data));
    try comptime expectEqual(i32, T);
    try expectEqual(0, data);
}

fn foo(comptime T: type, ptr: *T) T {
    ptr.* += 1;
    return ptr.*;
}

// test
