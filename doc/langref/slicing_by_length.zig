const expectEqual = @import("std").testing.expectEqual;

test "example" {
    var array = [_]i32{ 1, 2, 3, 4 };
    var runtime_start: usize = 1;
    _ = &runtime_start;
    const length = 2;
    const array_ptr_len = array[runtime_start..][0..length];
    try expectEqual(*[length]i32, @TypeOf(array_ptr_len));
}

// test
