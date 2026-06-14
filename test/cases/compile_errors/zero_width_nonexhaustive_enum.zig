comptime {
    const E = enum(u0) { a, _ };
    _ = @as(E, undefined);
}

comptime {
    const E = enum(u0) { a, b, _ };
    _ = @as(E, undefined);
}

// error
//
// :2:15: error: non-exhaustive enum specifies every value
// :7:29: error: enum tag value '1' too large for type 'u0'
