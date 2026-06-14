const std = @import("std");
const expectEqualStrings = std.testing.expectEqualStrings;
const mem = std.mem;

test "cast *[1][*:0]const u8 to []const ?[*:0]const u8" {
    const window_name = [1][*:0]const u8{"window name"};
    const x: []const ?[*:0]const u8 = &window_name;
    try expectEqualStrings("window name", mem.span(x[0].?));
}

// test
