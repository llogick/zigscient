const expectEqual = @import("std").testing.expectEqual;

test "pointer slicing" {
    var array = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    var start: usize = 2; // var to make it runtime-known
    _ = &start; // suppress 'var is never mutated' error
    const slice = array[start..4];
    try expectEqual(2, slice.len);

    try expectEqual(4, array[3]);
    slice[1] += 1;
    try expectEqual(5, array[3]);
}

// test
