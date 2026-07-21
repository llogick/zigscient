const std = @import("std");

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = stack_trace;
    if (std.mem.eql(u8, message, "attempt to load uninstantiable type")) {
        std.process.exit(0);
    }
    std.process.exit(1);
}

const E = enum {};
pub fn main() error{TestFailed}!void {
    const bytes: [32]u8 = @splat(0);
    const ptr: *const E = @ptrCast(&bytes);
    _ = ptr.*;
    return error.TestFailed;
}
// run
// backend=selfhosted,llvm
// target=x86_64-linux,aarch64-linux,wasm32-wasi
