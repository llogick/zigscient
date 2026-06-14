const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "@src" {
    try doTheTest();
}

fn doTheTest() !void {
    const src = @src();

    try expectEqual(10, src.line);
    try expectEqual(17, src.column);
    try expect(std.mem.endsWith(u8, src.fn_name, "doTheTest"));
    try expect(std.mem.endsWith(u8, src.file, "test_src_builtin.zig"));
}

// test
