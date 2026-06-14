const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "fully anonymous struct" {
    try check(.{
        .int = @as(u32, 1234),
        .float = @as(f64, 12.34),
        .b = true,
        .s = "hi",
    });
}

fn check(args: anytype) !void {
    try expectEqual(1234, args.int);
    try expectEqual(12.34, args.float);
    try expect(args.b);
    try expectEqual('h', args.s[0]);
    try expectEqual('i', args.s[1]);
}

// test
