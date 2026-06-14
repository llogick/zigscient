const expectEqual = @import("std").testing.expectEqual;

test "address of syntax" {
    // Get the address of a variable:
    const x: i32 = 1234;
    const x_ptr = &x;

    // Dereference a pointer:
    try expectEqual(1234, x_ptr.*);

    // When you get the address of a const variable, you get a const single-item pointer.
    try expectEqual(*const i32, @TypeOf(x_ptr));

    // If you want to mutate the value, you'd need an address of a mutable variable:
    var y: i32 = 5678;
    const y_ptr = &y;
    try expectEqual(*i32, @TypeOf(y_ptr));
    y_ptr.* += 1;
    try expectEqual(5679, y_ptr.*);
}

test "pointer array access" {
    // Taking an address of an individual element gives a
    // single-item pointer. This kind of pointer
    // does not support pointer arithmetic.
    var array = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    const ptr = &array[2];
    try expectEqual(*u8, @TypeOf(ptr));

    try expectEqual(3, array[2]);
    ptr.* += 1;
    try expectEqual(4, array[2]);
}

test "slice syntax" {
    // Get a pointer to a variable:
    var x: i32 = 1234;
    const x_ptr = &x;

    // Convert to array pointer using slice syntax:
    const x_array_ptr = x_ptr[0..1];
    try expectEqual(*[1]i32, @TypeOf(x_array_ptr));

    // Coerce to many-item pointer:
    const x_many_ptr: [*]i32 = x_array_ptr;
    try expectEqual(1234, x_many_ptr[0]);
}

// test
