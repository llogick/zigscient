const E = enum(u8) {
    a,
    b,
    _,
};
const U = union(E) {
    a,
    b,
};
fn foo() U {
    return undefined;
}

export fn entry1() void {
    const u = foo();
    switch (u) {
        .a => {},
    }
}
export fn entry2() void {
    const u = foo();
    switch (u) {
        .a => {},
        .b => {},
        else => {},
    }
}
export fn entry3() void {
    const u = foo();
    switch (u) {
        .a => {},
        .b => {},
        _ => {},
    }
}
export fn entry4() void {
    const u = foo();
    switch (u) {
        .a => {},
        else => {},
        _ => {},
    }
}

// error
//
// :16:5: error: switch must handle all possibilities
// :3:5: note: unhandled enumeration value: 'b'
// :1:11: note: enum 'tmp.E' declared here
// :25:14: error: unreachable else prong; all cases already handled
// :30:5: error: '_' prong only allowed when switching on non-exhaustive enums
// :33:9: note: '_' prong here
// :30:5: note: consider using 'else'
// :38:5: error: '_' prong only allowed when switching on non-exhaustive enums
// :41:9: note: '_' prong here
// :38:5: note: consider using 'else'
