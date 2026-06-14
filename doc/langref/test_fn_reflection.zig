const std = @import("std");
const math = std.math;
const testing = std.testing;

test "fn reflection" {
    try testing.expectEqual(bool, @typeInfo(@TypeOf(testing.expect)).@"fn".param_types[0].?);
    try testing.expectEqual(testing.TmpDir, @typeInfo(@TypeOf(testing.tmpDir)).@"fn".return_type.?);

    try testing.expect(@typeInfo(@TypeOf(math.Log2Int)).@"fn".is_generic);
}

// test
