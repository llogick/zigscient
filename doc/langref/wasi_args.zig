const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    for (0.., args) |i, arg| {
        std.debug.print("{d}: {s}\n", .{ i, arg });
    }
}

// exe=succeed
// target=wasm32-wasi
