const AutoUnion = union { a: u8 };
export fn entry1() void {
    switch (@as(AutoUnion, .{ .a = 123 })) {
        else => {},
    }
}

const ExternUnion = union { a: u8 };
export fn entry2() void {
    switch (@as(ExternUnion, .{ .a = 123 })) {
        else => {},
    }
}

const AutoStruct = struct { a: u8 };
export fn entry3() void {
    switch (@as(AutoStruct, .{ .a = 123 })) {
        else => {},
    }
}

const ExternStruct = extern struct { a: u8 };
export fn entry4() void {
    switch (@as(ExternStruct, .{ .a = 123 })) {
        else => {},
    }
}

export fn entry5() void {
    switch (@as([]const u16, &.{ 1, 2, 3 })) {
        else => {},
    }
}

export fn entry6() void {
    switch (@as([3]u16, .{ 1, 2, 3 })) {
        else => {},
    }
}

export fn entry7() void {
    switch (@as(@Vector(3, u16), .{ 1, 2, 3 })) {
        else => {},
    }
}

export fn entry8() void {
    switch (@as(?u16, 123)) {
        else => {},
    }
}

export fn entry9() void {
    switch (@as(anyerror!u16, 123)) {
        else => {},
    }
}

export fn entry10() void {
    switch (@as(f32, 123)) {
        else => {},
    }
}

export fn entry11() void {
    switch (@as(comptime_float, 123)) {
        else => {},
    }
}

export fn entry12() void {
    switch (undefined) {
        else => {},
    }
}

export fn entry13() void {
    switch (null) {
        else => {},
    }
}

// error
//
// :3:13: error: switch on union with no attached enum
// :1:19: note: consider 'union(enum)' here
// :10:13: error: switch on union with no attached enum
// :8:21: note: consider 'union(enum)' here
// :17:13: error: switch on non-packed struct
// :15:20: note: struct declared here
// :24:13: error: switch on non-packed struct
// :22:29: note: struct declared here
// :30:13: error: switch on type '[]const u16'
// :36:13: error: switch on type '[3]u16'
// :42:13: error: switch on type '@Vector(3, u16)'
// :48:13: error: switch on optional type '?u16'
// :48:13: note: consider using '.?', 'orelse', or 'if'
// :54:13: error: switch on error union type 'anyerror!u16'
// :54:13: note: consider using 'try', 'catch', or 'if'
// :60:13: error: switch on type 'f32'
// :66:13: error: switch on type 'comptime_float'
// :72:13: error: switch on type '@TypeOf(undefined)'
// :78:13: error: switch on type '@TypeOf(null)'
