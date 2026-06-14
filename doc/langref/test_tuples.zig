const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "tuple" {
    const values = .{
        @as(u32, 1234),
        @as(f64, 12.34),
        true,
        "hi",
    } ++ .{ false, false };
    try expectEqual(1234, values[0]);
    try expectEqual(false, values[4]);
    inline for (values, 0..) |v, i| {
        if (i != 2) continue;
        try expect(v);
    }
    try expectEqual(6, values.len);
    try expectEqual('h', values.@"3"[0]);
}

// test
