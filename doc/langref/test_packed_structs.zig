const std = @import("std");
const native_endian = @import("builtin").target.cpu.arch.endian();
const expectEqual = std.testing.expectEqual;

const Full = packed struct {
    number: u16,
};
const Divided = packed struct {
    half1: u8,
    quarter3: u4,
    quarter4: u4,
};

test "@bitCast between packed structs" {
    try doTheTest();
    try comptime doTheTest();
}

fn doTheTest() !void {
    try expectEqual(2, @sizeOf(Full));
    try expectEqual(2, @sizeOf(Divided));
    const full = Full{ .number = 0x1234 };
    const divided: Divided = @bitCast(full);
    try expectEqual(0x34, divided.half1);
    try expectEqual(0x2, divided.quarter3);
    try expectEqual(0x1, divided.quarter4);

    const ordered: [2]u8 = @bitCast(full);
    switch (native_endian) {
        .big => {
            try expectEqual(0x12, ordered[0]);
            try expectEqual(0x34, ordered[1]);
        },
        .little => {
            try expectEqual(0x34, ordered[0]);
            try expectEqual(0x12, ordered[1]);
        },
    }
}

// test
