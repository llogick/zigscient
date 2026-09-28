const Tag = u2;
const Foo = enum(Tag) {
    a,
    b,
    c,
    d,
};
pub fn main() !void {
    var val: Foo = undefined;
    val = .a;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &.{});
    try stdout_writer.interface.print("{s}\n", .{@tagName(val)});
}
const std = @import("std");
const io = std.Io.Threaded.global_single_threaded.io();
