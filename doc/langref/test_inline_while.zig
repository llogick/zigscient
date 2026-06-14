const expectEqual = @import("std").testing.expectEqual;

test "inline while loop" {
    comptime var i = 0;
    var sum: usize = 0;
    inline while (i < 3) : (i += 1) {
        const T = switch (i) {
            0 => f32,
            1 => i8,
            2 => bool,
            else => unreachable,
        };
        sum += typeNameLength(T);
    }
    try expectEqual(9, sum);
}

fn typeNameLength(comptime T: type) usize {
    return @typeName(T).len;
}

// test
