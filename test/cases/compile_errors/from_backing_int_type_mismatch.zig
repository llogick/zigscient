const E = enum(u32) { a, b, c };
export fn entry1(x: u64) E {
    return @fromBackingInt(x);
}

const S = packed struct(u32) { x: u32 };
export fn entry2(x: u64) S {
    return @fromBackingInt(x);
}

const U = packed union(u32) { x: u32 };
export fn entry3(x: u64) U {
    return @fromBackingInt(x);
}

// error
//
// :3:28: error: expected type 'u32', found 'u64'
// :3:28: note: unsigned 32-bit int cannot represent all possible unsigned 64-bit values
// :8:28: error: expected type 'u32', found 'u64'
// :8:28: note: unsigned 32-bit int cannot represent all possible unsigned 64-bit values
// :13:28: error: expected type 'u32', found 'u64'
// :13:28: note: unsigned 32-bit int cannot represent all possible unsigned 64-bit values
