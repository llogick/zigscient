export fn entry() void {
    comptime @breakpoint();
}

// error
//
// :2:14: error: encountered @breakpoint at comptime
