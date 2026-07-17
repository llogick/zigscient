const E = enum {};

export fn entry1() void {
    const e: E = undefined;
    _ = e;
}

export fn entry2() void {
    const e: E = @enumFromInt(@as(u8, undefined));
    _ = e;
}

export fn entry3() void {
    const e: E = .a;
    _ = e;
}

export fn entry4() void {
    const e: E = @enumFromInt(0);
    _ = e;
}

// error
//
// :4:18: error: expected type 'tmp.E', found '@TypeOf(undefined)'
// :4:18: note: cannot coerce to uninstantiable type 'tmp.E'
// :1:11: note: enum declared here
// :9:31: error: use of undefined value here causes illegal behavior
// :14:19: error: enum 'tmp.E' has no member named 'a'
// :1:11: note: enum declared here
// :19:18: error: enum 'tmp.E' has no tag with value '0'
// :1:11: note: enum declared here
