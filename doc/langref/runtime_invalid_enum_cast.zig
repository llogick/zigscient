const std = @import("std");

const Foo = enum(u2) {
    a,
    b,
    c,
};

fn foo(a: u2) void {
    const b: Foo = @fromBackingInt(a);
    std.debug.print("value: {s}\n", .{@tagName(b)});
}

pub fn main() void {
    foo(3);
}

// exe=fail
