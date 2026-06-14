const expectEqual = @import("std").testing.expectEqual;

var foo: u8 align(4) = 100;

test "global variable alignment" {
    try expectEqual(4, @typeInfo(@TypeOf(&foo)).pointer.attrs.@"align");
    try expectEqual(*align(4) u8, @TypeOf(&foo));
    const as_pointer_to_array: *align(4) [1]u8 = &foo;
    const as_slice: []align(4) u8 = as_pointer_to_array;
    const as_unaligned_slice: []u8 = as_slice;
    try expectEqual(100, as_unaligned_slice[0]);
}

fn derp() align(@sizeOf(usize) * 2) i32 {
    return 1234;
}
fn noop1() align(1) void {}
fn noop4() align(4) void {}

test "function alignment" {
    try expectEqual(1234, derp());
    try expectEqual(fn () i32, @TypeOf(derp));
    try expectEqual(*align(@sizeOf(usize) * 2) const fn () i32, @TypeOf(&derp));

    noop1();
    try expectEqual(fn () void, @TypeOf(noop1));
    try expectEqual(*align(1) const fn () void, @TypeOf(&noop1));

    noop4();
    try expectEqual(fn () void, @TypeOf(noop4));
    try expectEqual(*align(4) const fn () void, @TypeOf(&noop4));
}

// test
