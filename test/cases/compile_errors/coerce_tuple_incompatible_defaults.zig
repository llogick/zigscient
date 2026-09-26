comptime {
    const one = .{@as(u32, 1)};
    const two = .{@as(u32, 2)};
    const coerced: @TypeOf(one) = two;
    _ = coerced;
}

// error
//
// :4:35: error: value stored in comptime field does not match the default value of the field
