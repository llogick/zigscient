export fn entry1() void {
    const E = enum(u31) { A, B, C };
    _ = @sizeOf(extern struct {
        x: E,
    });
}
export fn entry2() void {
    const E = enum(noreturn) {};
    _ = @sizeOf(extern struct {
        x: E,
    });
}

// error
//
// :4:12: error: extern structs cannot contain fields of type 'tmp.entry1.E'
// :2:15: note: enum tag type 'u31' is not extern compatible
// :2:15: note: only integers with 0 or power of two bits are extern compatible
// :2:15: note: enum declared here
// :10:12: error: extern structs cannot contain fields of type 'tmp.entry2.E'
// :8:15: note: enum tag type 'noreturn' is not extern compatible
// :8:15: note: 'noreturn' is only allowed as a return type
// :8:15: note: enum declared here
