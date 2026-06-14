const std = @import("std");
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

test "peer resolve int widening" {
    const a: i8 = 12;
    const b: i16 = 34;
    const c = a + b;
    try expectEqual(46, c);
    try expectEqual(i16, @TypeOf(c));
}

test "peer resolve small int and float" {
    // This only works for integer types that can coerce to the float type.
    // Larger integer types will cause a compiler error; no float widening occurs.
    var i: u8 = 12;
    var f: f32 = 34;
    _ = .{ &i, &f };
    const x = i + f;
    try expectEqual(x, 46.0);
    try expectEqual(@TypeOf(x), f32);
}

test "peer resolve arrays of different size to const slice" {
    try expectEqualStrings("true", boolToStr(true));
    try expectEqualStrings("false", boolToStr(false));
    try comptime expectEqualStrings("true", boolToStr(true));
    try comptime expectEqualStrings("false", boolToStr(false));
}
fn boolToStr(b: bool) []const u8 {
    return if (b) "true" else "false";
}

test "peer resolve array and const slice" {
    try testPeerResolveArrayConstSlice(true);
    try comptime testPeerResolveArrayConstSlice(true);
}
fn testPeerResolveArrayConstSlice(b: bool) !void {
    const value1 = if (b) "aoeu" else @as([]const u8, "zz");
    const value2 = if (b) @as([]const u8, "zz") else "aoeu";
    try expectEqualStrings("aoeu", value1);
    try expectEqualStrings("zz", value2);
}

test "peer type resolution: ?T and T" {
    try expectEqual(0, peerTypeTAndOptionalT(true, false).?);
    try expectEqual(3, peerTypeTAndOptionalT(false, false).?);
    comptime {
        try expectEqual(0, peerTypeTAndOptionalT(true, false).?);
        try expectEqual(3, peerTypeTAndOptionalT(false, false).?);
    }
}
fn peerTypeTAndOptionalT(c: bool, b: bool) ?usize {
    if (c) {
        return if (b) null else @as(usize, 0);
    }

    return @as(usize, 3);
}

test "peer type resolution: *[0]u8 and []const u8" {
    try expectEqual(0, peerTypeEmptyArrayAndSlice(true, "hi").len);
    try expectEqual(1, peerTypeEmptyArrayAndSlice(false, "hi").len);
    comptime {
        try expectEqual(0, peerTypeEmptyArrayAndSlice(true, "hi").len);
        try expectEqual(1, peerTypeEmptyArrayAndSlice(false, "hi").len);
    }
}
fn peerTypeEmptyArrayAndSlice(a: bool, slice: []const u8) []const u8 {
    if (a) {
        return &[_]u8{};
    }

    return slice[0..1];
}
test "peer type resolution: *[0]u8, []const u8, and anyerror![]u8" {
    {
        var data = "hi".*;
        const slice = data[0..];
        try expectEqual(0, (try peerTypeEmptyArrayAndSliceAndError(true, slice)).len);
        try expectEqual(1, (try peerTypeEmptyArrayAndSliceAndError(false, slice)).len);
    }
    comptime {
        var data = "hi".*;
        const slice = data[0..];
        try expectEqual(0, (try peerTypeEmptyArrayAndSliceAndError(true, slice)).len);
        try expectEqual(1, (try peerTypeEmptyArrayAndSliceAndError(false, slice)).len);
    }
}
fn peerTypeEmptyArrayAndSliceAndError(a: bool, slice: []u8) anyerror![]u8 {
    if (a) {
        return &[_]u8{};
    }

    return slice[0..1];
}

test "peer type resolution: *const T and ?*T" {
    const a: *const usize = @ptrFromInt(0x12345678);
    const b: ?*usize = @ptrFromInt(0x12345678);
    try expectEqual(a, b);
    try expectEqual(b, a);
}

test "peer type resolution: error union switch" {
    // The non-error and error cases are only peers if the error case is just a switch expression;
    // the pattern `if (x) {...} else |err| blk: { switch (err) {...} }` does not consider the
    // non-error and error case to be peers.
    var a: error{ A, B, C }!u32 = 0;
    _ = &a;
    const b = if (a) |x|
        x + 3
    else |err| switch (err) {
        error.A => 0,
        error.B => 1,
        error.C => null,
    };
    try expectEqual(?u32, @TypeOf(b));

    // The non-error and error cases are only peers if the error case is just a switch expression;
    // the pattern `x catch |err| blk: { switch (err) {...} }` does not consider the unwrapped `x`
    // and error case to be peers.
    const c = a catch |err| switch (err) {
        error.A => 0,
        error.B => 1,
        error.C => null,
    };
    try expectEqual(?u32, @TypeOf(c));
}

// test
