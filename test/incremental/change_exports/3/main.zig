export fn foo() void {}
const bar: u32 = 123;
const other: u32 = 456;
const does_exports = {
    @export(&bar, .{ .name = "bar" });
    @export(&other, .{ .name = "other" });
};
comptime {
    _ = does_exports;
}
pub fn main() !void {
    const S = struct {
        extern fn foo() void;
        extern const bar: u32;
        extern const other: u32;
    };
    S.foo();
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &.{});
    try stdout_writer.interface.print("{} {}\n", .{ S.bar, S.other });
}
const std = @import("std");
const io = std.Io.Threaded.global_single_threaded.io();
