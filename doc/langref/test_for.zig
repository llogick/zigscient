const expectEqual = @import("std").testing.expectEqual;

test "for basics" {
    const items = [_]i32{ 4, 5, 3, -1, 4 };
    var sum: i32 = 0;

    // For loops iterate over slices and arrays.
    for (items) |value| {
        // Break and continue are supported.
        if (value < 0) {
            continue;
        }
        sum += value;
    }
    try expectEqual(16, sum);

    // Use slicing to iterate over a portion of a slice or array.
    sum = 0;
    for (items[0..2]) |value| {
        sum += value;
    }
    try expectEqual(9, sum);
}

test "for ranges" {
    const items = [_]u8{1, 2, 3};
    var sum: usize = 0;

    // To access the index of iteration, specify an unbounded range as the
    // second condition, as well as a second capture value.
    for (items, 0..) |e, i| {
        try expectEqual(usize, @TypeOf(i));
        sum += i; 
        try expectEqual(e, i + 1);
    }
    try expectEqual(3, sum); // 0 + 1 + 2

    // To iterate over consecutive integers, use bounded range syntax.
    // A lone unbounded range is a compile error.
    sum = 0;
    for (0..5) |i| {
        sum += i;
    }
    try expectEqual(10, sum);
}

test "multi object for" {
    const items = [_]usize{ 1, 2, 3 };
    const items2 = [_]usize{ 4, 5, 6 };
    var count: usize = 0;

    // Iterate over multiple objects.
    // All bounded objects must have equal lengths.
    // There must be at least one bounded object.
    for (items, items2) |i, j| {
        count += i + j;
    }

    try expectEqual(21, count);
}

test "for reference" {
    var items = [_]i32{ 3, 4, 2 };

    // Iterate over the slice by reference by
    // specifying that the capture value is a pointer.
    for (&items) |*value| {
        value.* += 1;
    }

    try expectEqual(4, items[0]);
    try expectEqual(5, items[1]);
    try expectEqual(3, items[2]);
}

test "for else" {
    // For allows an else attached to it, the same as a while loop.
    // The else branch is evaluated when the loop completes without a break.
    const items = [_]i32{ 3, 4, 5 };

    const result = for (items) |value| {
        if (value > 10) break value;
    } else 0;

    try expectEqual(0, result);

    const more_items = [_]i32{ 3, 4, 11, 5 };

    const another_result = for (more_items) |value| {
        if (value > 10) break value;
    } else 0;

    try expectEqual(11, another_result);
}

// test
