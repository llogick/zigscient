const std = @import("std");
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectEqualSlices = std.testing.expectEqualSlices;

// You can assign constant pointers to arrays to a slice with
// const modifier on the element type. Useful in particular for
// String literals.
test "*const [N]T to []const T" {
    const x1: []const u8 = "hello";
    const x2: []const u8 = &[5]u8{ 'h', 'e', 'l', 'l', 111 };
    try expectEqualStrings(x1, x2);

    const y: []const f32 = &[2]f32{ 1.2, 3.4 };
    try expectEqual(1.2, y[0]);
}

// Likewise, it works when the destination type is an error union.
test "*const [N]T to E![]const T" {
    const x1: anyerror![]const u8 = "hello";
    const x2: anyerror![]const u8 = &[5]u8{ 'h', 'e', 'l', 'l', 111 };
    try expectEqualStrings(try x1, try x2);

    const y: anyerror![]const f32 = &[2]f32{ 1.2, 3.4 };
    try expectEqual(1.2, (try y)[0]);
}

// Likewise, it works when the destination type is an optional.
test "*const [N]T to ?[]const T" {
    const x1: ?[]const u8 = "hello";
    const x2: ?[]const u8 = &[5]u8{ 'h', 'e', 'l', 'l', 111 };
    try expectEqualStrings(x1.?, x2.?);

    const y: ?[]const f32 = &[2]f32{ 1.2, 3.4 };
    try expectEqual(1.2, y.?[0]);
}

// In this cast, the array length becomes the slice length.
test "*[N]T to []T" {
    var buf: [5]u8 = "hello".*;
    const x: []u8 = &buf;
    try expectEqualStrings("hello", x);

    const buf2 = [2]f32{ 1.2, 3.4 };
    const x2: []const f32 = &buf2;
    try expectEqualSlices(f32, &[2]f32{ 1.2, 3.4 }, x2);
}

// Single-item pointers to arrays can be coerced to many-item pointers.
test "*[N]T to [*]T" {
    var buf: [5]u8 = "hello".*;
    const x: [*]u8 = &buf;
    try expectEqual('o', x[4]);
    // x[5] would be an uncaught out of bounds pointer dereference!
}

// Likewise, it works when the destination type is an optional.
test "*[N]T to ?[*]T" {
    var buf: [5]u8 = "hello".*;
    const x: ?[*]u8 = &buf;
    try expectEqual('o', x.?[4]);
}

// Single-item pointers can be cast to len-1 single-item arrays.
test "*T to *[1]T" {
    var x: i32 = 1234;
    const y: *[1]i32 = &x;
    const z: [*]i32 = y;
    try expectEqual(1234, z[0]);
}

// Sentinel-terminated slices can be coerced into sentinel-terminated pointers
test "[:x]T to [*:x]T" {
    const buf: [:0]const u8 = "hello";
    const buf2: [*:0]const u8 = buf;
    try expectEqual('o', buf2[4]);
}

// test
