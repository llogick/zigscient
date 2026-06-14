const std = @import("std");

pub fn main(init: std.process.Init) void {
    for (init.preopens.map.keys(), 0..) |preopen, i| {
        std.log.info("{d}: {s}", .{ i, preopen });
    }
}

// exe=succeed
// target=wasm32-wasi
