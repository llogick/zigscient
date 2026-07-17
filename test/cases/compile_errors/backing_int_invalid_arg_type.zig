const S1 = extern struct { x: u32 };
export fn entry1(x: S1) u32 {
    return @backingInt(x);
}

const U1 = extern union { x: u32 };
export fn entry2(x: U1) u32 {
    return @backingInt(x);
}

export fn entry3(x: u32) u32 {
    return @backingInt(x);
}

const S2 = packed struct { x: u32 };
export fn entry4(x: u32) u32 {
    return @backingInt(@as(S2, .{ .x = x }));
}

const U2 = packed union { x: u32 };
export fn entry5(x: u32) u32 {
    return @backingInt(@as(U2, .{ .x = x }));
}

// error
//
// :3:24: error: non-packed struct 'tmp.S1' does not have a backing integer
// :1:19: note: struct declared here
// :8:24: error: non-packed union 'tmp.U1' does not have a backing integer
// :8:24: note: untagged union 'tmp.U1' does not have an enum tag with a backing integer
// :6:19: note: union declared here
// :12:24: error: expected enum, tagged union, packed union or packed struct, found 'u32'
// :17:24: error: @backingInt is ambiguous for type 'tmp.S2'
// :15:19: note: backing integer type of struct is inferred
// :15:19: note: consider explicitly specifying the backing integer type
// :22:24: error: @backingInt is ambiguous for type 'tmp.U2'
// :20:19: note: backing integer type of union is inferred
// :20:19: note: consider explicitly specifying the backing integer type
