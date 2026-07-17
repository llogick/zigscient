const E = enum(u32) { x };
export fn entry1() void {
    @compileLog(@as(E, @fromBackingInt(undefined)));
}

const S = packed struct(u32) { x: u32 };
export fn entry2() void {
    @compileLog(@as(S, @fromBackingInt(undefined)));
}

const U = packed union(u32) { x: u32 };
export fn entry3() void {
    @compileLog(@as(U, @fromBackingInt(undefined)));
}

// error
//
// :3:40: error: use of undefined value here causes illegal behavior
//
// Compile Log Output:
// @as(tmp.S, undefined)
// @as(tmp.U, undefined)
