const E1 = enum(u32) {};
export fn entry1() void {
    const e: E1 = undefined;
    _ = e;
}

const E2 = enum(noreturn) { a, b, c };
export fn entry2() void {
    const e: E2 = undefined;
    _ = e;
}

// error
//
// :1:17: error: empty exhaustive enums must be backed by 'noreturn'
// :7:17: error: non-empty enums cannot be backed by 'noreturn'
