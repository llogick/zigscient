export fn entry() void {
    var a: []u8 = undefined;
    _ = a.*.len;
    _ = &a;
}

// error
//
// :3:10: error: index syntax required to access runtime-known slice
