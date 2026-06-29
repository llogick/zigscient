const std = @import("std");
const expect = std.testing.expect;

test "assignment to overlapping memory" {
    try theTest();
    try comptime theTest();
}

fn theTest() !void {
    var a1: [3]usize = .{ 0, 1, 2 };
    const b1: [3]usize = .{ 0, 0, 1 };
    a1[1..3].* = a1[0..2].*;
    for (a1, b1) |a, b| {
        try expect(a == b);
    }

    var a2: [3]usize = .{ 0, 1, 2 };
    const b2: [3]usize = .{ 1, 2, 2 };
    a2[0..2].* = a2[1..3].*;
    for (a2, b2) |a, b| {
        try expect(a == b);
    }

    var a3: [16]u8 = .{
        0, 1, 2,  3,  4,  5,  6,  7,
        8, 9, 10, 11, 12, 13, 14, 15,
    };
    const b3: [16]u8 = .{
        0, 0, 1, 2,  3,  4,  5,  6,
        7, 8, 9, 10, 11, 12, 13, 14,
    };
    a3[1..16].* = a3[0..15].*;
    for (a3, b3) |a, b| {
        try expect(a == b);
    }

    var a4: [16]u8 = .{
        0, 1, 2,  3,  4,  5,  6,  7,
        8, 9, 10, 11, 12, 13, 14, 15,
    };
    const b4: [16]u8 = .{
        1, 2,  3,  4,  5,  6,  7,  8,
        9, 10, 11, 12, 13, 14, 15, 15,
    };
    a4[0..15].* = a4[1..16].*;
    for (a4, b4) |a, b| {
        try expect(a == b);
    }
}
