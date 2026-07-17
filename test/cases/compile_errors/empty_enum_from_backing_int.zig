const E = enum(noreturn) {};

export fn entry1() void {
    const e: E = @fromBackingInt(undefined);
    _ = e;
}

export fn entry2() void {
    const e: E = @fromBackingInt(0);
    _ = e;
}

// error
//
// :4:34: error: expected type 'noreturn', found '@TypeOf(undefined)'
// :4:34: note: cannot coerce to uninstantiable type 'noreturn'
// :9:34: error: expected type 'noreturn', found 'comptime_int'
// :9:34: note: cannot coerce to uninstantiable type 'noreturn'
