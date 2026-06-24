const S = extern struct { x: u32 };
export fn foo(s: S) void {
    const as_int: u32 = @bitCast(s);
    _ = as_int;
}

// error
//
// :3:34: error: cannot @bitCast from 'tmp.S'
// :1:18: note: struct declared here
