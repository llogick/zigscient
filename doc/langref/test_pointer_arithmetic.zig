const expectEqual = @import("std").testing.expectEqual;

test "pointer arithmetic with many-item pointer" {
    const array = [_]i32{ 1, 2, 3, 4 };
    var ptr: [*]const i32 = &array;

    try expectEqual(1, ptr[0]);
    ptr += 1;
    try expectEqual(2, ptr[0]);

    // slicing a many-item pointer without an end is equivalent to
    // pointer arithmetic: `ptr[start..] == ptr + start`
    try expectEqual(ptr[1..], ptr + 1);

    // subtraction between any two pointers except slices based on element size is supported
    try expectEqual(1, &ptr[1] - &ptr[0]);
}

test "pointer arithmetic with slices" {
    var array = [_]i32{ 1, 2, 3, 4 };
    var length: usize = 0; // var to make it runtime-known
    _ = &length; // suppress 'var is never mutated' error
    var slice = array[length..array.len];

    try expectEqual(1, slice[0]);
    try expectEqual(4, slice.len);

    slice.ptr += 1;
    // now the slice is in an bad state since len has not been updated

    try expectEqual(2, slice[0]);
    try expectEqual(4, slice.len);
}

// test
