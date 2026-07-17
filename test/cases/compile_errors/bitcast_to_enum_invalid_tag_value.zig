const E = enum(u8) { a, b, c };
export fn entry1() void {
    const x: E = @bitCast(@as(u8, 3));
    _ = x;
}

export fn entry2() void {
    const x: E = @bitCast(@as(u8, undefined));
    _ = x;
}

// error
//
// :3:18: error: enum 'tmp.E' has no tag with value '3'
// :1:11: note: enum declared here
// :8:27: error: use of undefined value here causes illegal behavior
