export fn foo() void {}
const bar: u32 = 123;
const other: u32 = 456;
comptime {
    @export(&bar, .{ .name = "bar" });
}
pub fn main() !void {
    const S = struct {
        extern fn foo() void;
        extern const bar: u32;
    };
    S.foo();
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &.{});
    try stdout_writer.interface.print("{}\n", .{S.bar});
}
const std = @import("std");
const io = std.Io.Threaded.global_single_threaded.io();
