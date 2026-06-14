const expectEqual = @import("std").testing.expectEqual;

test "optional type" {
    // Declare an optional and coerce from null:
    var foo: ?i32 = null;

    // Coerce from child type of an optional
    foo = 1234;

    // Use compile-time reflection to access the child type of the optional:
    try comptime expectEqual(i32, @typeInfo(@TypeOf(foo)).optional.child);
}

// test
