const std = @import("std");
const native_arch = @import("builtin").target.cpu.arch;
const expectEqual = std.testing.expectEqual;

test "@wasmMemoryGrow" {
    if (native_arch != .wasm32) return error.SkipZigTest;

    const prev = @wasmMemorySize(0);
    try expectEqual(@wasmMemoryGrow(0, 1), prev);
    try expectEqual(@wasmMemorySize(0), prev + 1);
}

// test
