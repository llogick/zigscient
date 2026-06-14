const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const expect = testing.expect;
const expectEqualStrings = testing.expectEqualStrings;

test "tuple declaration type info" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    {
        const T = struct { comptime u32 = 1, []const u8 };
        const info = @typeInfo(T).@"struct";

        try expect(info.is_tuple);
        try expect(info.layout == .auto);
        try expect(info.backing_integer == null);
        try expect(info.field_names.len == 2);
        try expect(info.decl_names.len == 0);

        try expectEqualStrings(info.field_names[0], "0");
        try expect(info.field_types[0] == u32);
        try expect(info.field_attrs[0].defaultValue(info.field_types[0]) == 1);
        try expect(info.field_attrs[0].@"comptime");
        try expect(info.field_attrs[0].@"align" == null);

        try expectEqualStrings(info.field_names[1], "1");
        try expect(info.field_types[1] == []const u8);
        try expect(info.field_attrs[1].defaultValue(info.field_types[1]) == null);
        try expect(!info.field_attrs[1].@"comptime");
        try expect(info.field_attrs[1].@"align" == null);
    }
}

test "tuple declaration usage" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    const T = struct { u32, []const u8 };
    var t: T = .{ 1, "foo" };
    _ = &t;
    try expect(t[0] == 1);
    try expectEqualStrings(t[1], "foo");

    var t2: T = .{ 2, "bar" };
    _ = &t2;
    const cat = t ++ t2;
    try expect(@TypeOf(cat) != T);
    try expect(cat.len == 4);
    try expect(cat[2] == 2);
    try expectEqualStrings(cat[3], "bar");
}
