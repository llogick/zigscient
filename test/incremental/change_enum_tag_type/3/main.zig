const Foo = enum(u3) {
    a,
    b,
    c,
    d,
    e,
};
pub fn main() !void {
    @compileLog(@typeInfo(Foo).@"enum".tag_type);
}
const std = @import("std");
const io = std.Io.Threaded.global_single_threaded.io();
