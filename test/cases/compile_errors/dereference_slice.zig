fn entry(x: []i32) i32 {
    return x.*;
}
comptime {
    _ = &entry;
}

// error
//
// :2:13: error: index syntax required to access runtime-known slice
