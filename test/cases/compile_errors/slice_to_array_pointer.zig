export fn entry1() void {
    var array: [2]u16 = .{ 1, 2 };
    const slice: []const u16 = &array;
    foo(slice);
}

export fn entry2() void {
    const slice: []const u16 = undefined;
    foo(slice);
}

export fn entry3() void {
    comptime var slice: []const u16 = &.{ 1, 2 };
    slice.len = undefined;
    foo(slice);
}

export fn entry4() void {
    const slice: []const u16 = &.{ 1, 2, 3 };
    foo(slice);
}

export fn entry5() void {
    const slice: []const u8 = &.{ 1, 2 };
    foo(slice);
}

fn foo(x: *const [2]u16) void {
    _ = x;
}

export fn entry6() void {
    const slice: [:0]const u16 = &.{ 1, 2, 3 };
    bar(slice);
}

export fn entry7() void {
    const slice: [:1]const u16 = &.{ 1, 2 };
    bar(slice);
}

export fn entry8() void {
    const slice: []const u16 = &.{ 1, 2 };
    bar(slice);
}

fn bar(x: *const [2:0]u16) void {
    _ = x;
}

// error
//
// :4:9: error: coercion from slice to array pointer type '*const [2]u16' requires length to be known at compile-time
// :9:9: error: slice with undefined length cannot cast into array pointer type '*const [2]u16'
// :9:9: note: length of slice must be defined and match length of array type
// :15:9: error: slice with undefined length cannot cast into array pointer type '*const [2]u16'
// :15:9: note: length of slice must be defined and match length of array type
// :20:9: error: slice of length 3 cannot cast into array pointer type '*const [2]u16'
// :20:9: note: length of slice must match length of array type
// :25:9: error: expected type '*const [2]u16', found '[]const u8'
// :25:9: note: pointer type child 'u8' cannot cast into pointer type child 'u16'
// :28:11: note: parameter type declared here
// :34:9: error: slice of length 3 cannot cast into array pointer type '*const [2:0]u16'
// :34:9: note: length of slice must match length of array type
// :39:9: error: expected type '*const [2:0]u16', found '[:1]const u16'
// :39:9: note: pointer sentinel '1' cannot cast into pointer sentinel '0'
// :47:11: note: parameter type declared here
// :44:9: error: expected type '*const [2:0]u16', found '[]const u16'
// :44:9: note: destination pointer requires '0' sentinel
// :47:11: note: parameter type declared here
