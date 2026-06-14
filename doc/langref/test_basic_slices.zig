const expectEqual = @import("std").testing.expectEqual;
const expectEqualSlices = @import("std").testing.expectEqualSlices;

test "basic slices" {
    var array = [_]i32{ 1, 2, 3, 4 };
    var known_at_runtime_zero: usize = 0;
    _ = &known_at_runtime_zero;
    const slice = array[known_at_runtime_zero..array.len];

    // alternative initialization using result location
    const alt_slice: []const i32 = &.{ 1, 2, 3, 4 };

    try expectEqualSlices(i32, slice, alt_slice);

    try expectEqual([]i32, @TypeOf(slice));
    try expectEqual(&array[0], &slice[0]);
    try expectEqual(array.len, slice.len);

    // If you slice with comptime-known start and end positions, the result is
    // a pointer to an array, rather than a slice.
    const array_ptr = array[0..array.len];
    try expectEqual(*[array.len]i32, @TypeOf(array_ptr));

    // You can perform a slice-by-length by slicing twice. This allows the compiler
    // to perform some optimisations like recognising a comptime-known length when
    // the start position is only known at runtime.
    var runtime_start: usize = 1;
    _ = &runtime_start;
    const length = 2;
    const array_ptr_len = array[runtime_start..][0..length];
    try expectEqual(*[length]i32, @TypeOf(array_ptr_len));

    // Using the address-of operator on a slice gives a single-item pointer.
    try expectEqual(*i32, @TypeOf(&slice[0]));
    // Using the `ptr` field gives a many-item pointer.
    try expectEqual([*]i32, @TypeOf(slice.ptr));
    try expectEqual(@intFromPtr(slice.ptr), @intFromPtr(&slice[0]));

    // Slices have array bounds checking. If you try to access something out
    // of bounds, you'll get a safety check failure:
    slice[10] += 1;

    // Note that `slice.ptr` does not invoke safety checking, while `&slice[0]`
    // asserts that the slice has len > 0.

    // Empty slices can be created like this:
    const empty1 = &[0]u8{};
    // If the type is known you can use this short hand:
    const empty2: []u8 = &.{};
    try expectEqual(0, empty1.len);
    try expectEqual(0, empty2.len);

    // A zero-length initialization can always be used to create an empty slice, even if the slice is mutable.
    // This is because the pointed-to data is zero bits long, so its immutability is irrelevant.
}

// test_safety=index out of bounds
