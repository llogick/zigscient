comptime {
    const eu: anyerror!u8 = 10;
    const i: comptime_int = eu;
    _ = i;
}

comptime {
    const op: ?u8 = 10;
    const i: comptime_int = op;
    _ = i;
}

comptime {
    const op: anyerror!comptime_int = 10;
    const i: u8 = op;
    _ = i;
}

comptime {
    const op: ?comptime_int = 10;
    const i: u8 = op;
    _ = i;
}

// error
//
// :3:29: error: expected type 'comptime_int', found 'anyerror!u8'
// :9:29: error: expected type 'comptime_int', found '?u8'
// :15:19: error: expected type 'u8', found 'anyerror!comptime_int'
// :21:19: error: expected type 'u8', found '?comptime_int'
