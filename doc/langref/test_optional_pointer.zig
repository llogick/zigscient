const expectEqual = @import("std").testing.expectEqual;

test "optional pointers" {
    // Pointers cannot be null. If you want a null pointer, use the optional
    // prefix `?` to make the pointer type optional.
    var ptr: ?*i32 = null;

    var x: i32 = 1;
    ptr = &x;

    try expectEqual(1, ptr.?.*);

    // Optional pointers are the same size as normal pointers, because pointer
    // value 0 is used as the null value.
    try expectEqual(@sizeOf(?*i32), @sizeOf(*i32));
}

// test
