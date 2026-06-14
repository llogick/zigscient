const P = packed union(u8) {
    a: u8,
    b: i8,
};
export fn entry1(p: P) void {
    switch (p) {
        .{ .a = 123 } => |_, tag| _ = tag,
        else => {},
    }
}
export fn entry2(p: P) void {
    label: switch (p) {
        .{ .a = 123 } => |_, tag| _ = tag,
        else => continue :label .{ .a = 123 },
    }
}

const E = enum(u8) { a, b };
export fn entry3(e: E) void {
    switch (e) {
        .a => |_, tag| _ = tag,
        else => {},
    }
}
export fn entry4(e: E) void {
    label: switch (e) {
        .a => |_, tag| _ = tag,
        else => continue :label .a,
    }
}

const Error = error{ MyError, MyOtherError };
export fn entry5(ok: bool) void {
    switch (foo(ok)) {
        error.MyError => |_, tag| _ = tag,
        else => {},
    }
}
export fn entry6(ok: bool) void {
    label: switch (foo(ok)) {
        error.MyError => |_, tag| _ = tag,
        else => continue :label error.MyError,
    }
}
fn foo(ok: bool) Error {
    return if (ok) error.MyError else error.MyOtherError;
}

export fn entry7() void {
    switch (@as(u0, 0)) {
        0 => |_, tag| _ = tag,
    }
}
export fn entry8() void {
    label: switch (@as(u0, 0)) {
        0 => |_, tag| {
            _ = tag;
            continue :label 0;
        },
    }
}

// error
//
// :7:30: error: cannot capture tag of packed union
// :1:18: note: union declared here
// :1:18: note: consider using a tagged union
// :13:30: error: cannot capture tag of packed union
// :1:18: note: union declared here
// :1:18: note: consider using a tagged union
// :21:19: error: cannot capture tag of non-union type 'tmp.E'
// :18:11: note: enum declared here
// :27:19: error: cannot capture tag of non-union type 'tmp.E'
// :18:11: note: enum declared here
// :35:30: error: cannot capture tag of non-union type 'error{MyError,MyOtherError}'
// :41:30: error: cannot capture tag of non-union type 'error{MyError,MyOtherError}'
// :51:18: error: cannot capture tag of non-union type 'u0'
// :56:18: error: cannot capture tag of non-union type 'u0'
