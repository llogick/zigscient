export fn foo() void {
    const S = struct {
        f: u8,
    };
    _ = @as([@sizeOf(S)]u8, @bitCast([1]S{undefined}));
}

export fn bar() void {
    const S = struct {
        f: u8,
    };
    _ = @as([1]S, @bitCast(@as([@sizeOf(S)]u8, undefined)));
}

export fn baz() void {
    _ = @as([1]u32, @bitCast([1]comptime_int{0}));
}

// error
//
// :5:42: error: cannot @bitCast from '[1]tmp.foo.S'
// :12:19: error: cannot @bitCast to '[1]tmp.bar.S'
// :16:45: error: cannot @bitCast from '[1]comptime_int'
