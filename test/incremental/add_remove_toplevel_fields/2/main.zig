const S = @This();
pub fn main(init: std.process.Init) !void {
    var stdout_writer = std.Io.File.stdout().writerStreaming(init.io, &.{});
    printFieldCount(&stdout_writer.interface) catch |err| switch (err) {
        error.WriteFailed => return stdout_writer.err.?,
    };
    printOneField(&stdout_writer.interface) catch |err| switch (err) {
        error.WriteFailed => return stdout_writer.err.?,
    };
}
fn printFieldCount(w: *Writer) Writer.Error!void {
    try w.print("{d} ", .{@typeInfo(S).@"struct".field_names.len});
}
fn printOneField(w: *Writer) Writer.Error!void {
    const val: S = .{ .x = 100 };
    try w.print("{d}\n", .{val.x});
}
const std = @import("std");
const Writer = std.Io.Writer;
