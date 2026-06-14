const std = @import("std");
const expectEqual = std.testing.expectEqual;

test "allowzero" {
    var zero: usize = 0; // var to make to runtime-known
    _ = &zero; // suppress 'var is never mutated' error
    const ptr: *allowzero i32 = @ptrFromInt(zero);
    try expectEqual(0, @intFromPtr(ptr));
}

// test
