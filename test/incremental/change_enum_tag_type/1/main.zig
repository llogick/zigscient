const Tag = u2;
const Foo = enum(Tag) {
    a,
    b,
    c,
    d,
    e,
};
pub fn main() !void {
    var val: Foo = undefined;
    val = .a;
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &.{});
    try stdout_writer.interface.print("{s}\n", .{@tagName(val)});
}
comptime {
    // These can't be true at the same time; analysis should stop as soon as it sees `Foo`
    std.debug.assert(@backingInt(Foo.e) == 4);
    std.debug.assert(@TypeOf(@backingInt(Foo.e)) == Tag);
}
const std = @import("std");
const io = std.Io.Threaded.global_single_threaded.io();
