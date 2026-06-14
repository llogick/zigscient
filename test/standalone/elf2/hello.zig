pub fn main(init: std.process.Init) !void {
    const stdout: std.Io.File = .stdout();
    try stdout.writeStreamingAll(init.io, "Hello, World!\n");
}

const std = @import("std");
