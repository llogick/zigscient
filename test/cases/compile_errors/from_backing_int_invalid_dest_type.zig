const S1 = extern struct { x: u32 };
export fn entry1(x: u32) void {
    _ = @as(S1, @fromBackingInt(x));
}

const U1 = extern union { x: u32 };
export fn entry2(x: u32) void {
    _ = @as(U1, @fromBackingInt(x));
}

export fn entry3(x: u32) void {
    _ = @as(u32, @fromBackingInt(x));
}

const S2 = packed struct { x: u32 };
export fn entry4(x: u32) void {
    _ = @as(S2, @fromBackingInt(x));
}

const U2 = packed union { x: u32 };
export fn entry5(x: u32) u32 {
    _ = @as(U2, @fromBackingInt(x));
}

// error
//
// :3:17: error: non-packed struct 'tmp.S1' does not have a backing integer
// :1:19: note: struct declared here
// :8:17: error: non-packed union 'tmp.U1' does not have a backing integer
// :6:19: note: union declared here
// :12:18: error: expected enum, packed union or packed struct, found 'u32'
// :17:17: error: @fromBackingInt is ambiguous for type 'tmp.S2'
// :15:19: note: backing integer type of struct is inferred
// :15:19: note: consider explicitly specifying the backing integer type
// :22:17: error: @fromBackingInt is ambiguous for type 'tmp.U2'
// :20:19: note: backing integer type of union is inferred
// :20:19: note: consider explicitly specifying the backing integer type
