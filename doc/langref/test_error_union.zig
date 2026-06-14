const expectEqual = @import("std").testing.expectEqual;

test "error union" {
    var foo: anyerror!i32 = undefined;

    // Coerce from child type of an error union:
    foo = 1234;

    // Coerce from an error set:
    foo = error.SomeError;

    // Use compile-time reflection to access the payload type of an error union:
    try comptime expectEqual(i32, @typeInfo(@TypeOf(foo)).error_union.payload);

    // Use compile-time reflection to access the error set type of an error union:
    try comptime expectEqual(anyerror, @typeInfo(@TypeOf(foo)).error_union.error_set);
}

// test
