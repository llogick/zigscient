export fn entry2() void {
    comptime var slice: []const u16 = &.{ 1, 2, 3 };
    slice.len = undefined;
    _ = slice.*;
}

export fn entry3() void {
    comptime var slice: []const u16 = &.{ 1, 2, 3 };
    slice.len = undefined;
    _ = &slice.*;
}

export fn entry4() void {
    comptime var slice: []const u8 = "hello";
    slice.len = undefined;
    @compileError(slice);
}

// error
//
// :4:14: error: cannot dereference slice with undefined length
// :10:15: error: cannot dereference slice with undefined length
// :16:19: error: use of slice with undefined length here causes illegal behavior
