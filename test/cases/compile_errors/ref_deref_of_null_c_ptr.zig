export fn entry() void {
    const ptr: [*c]u8 = null;
    _ = &ptr.*;
}

// error
//
// :3:10: error: null pointer casted to type '*u8'
