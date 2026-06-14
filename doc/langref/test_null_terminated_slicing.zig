const std = @import("std");
const expectEqual = std.testing.expectEqual;

test "0-terminated slicing" {
    var array = [_]u8{ 3, 2, 1, 0, 3, 2, 1, 0 };
    var runtime_length: usize = 3;
    _ = &runtime_length;
    const slice = array[0..runtime_length :0];

    try expectEqual([:0]u8, @TypeOf(slice));
    try expectEqual(3, slice.len);
}

// test
