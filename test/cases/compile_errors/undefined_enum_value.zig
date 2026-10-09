const E = enum(u8) {
    a = undefined,
    b,
};
const U = union(enum(u8)) {
    a: u32 = undefined,
    b,
};
comptime {
    _ = E.a;
}
comptime {
    _ = U.a;
}

// error
//
// :2:9: error: use of undefined value here causes illegal behavior
// :6:14: error: use of undefined value here causes illegal behavior
