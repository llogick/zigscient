const std = @import("std");

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = stack_trace;
    if (std.mem.eql(u8, message, "invalid enum value")) {
        std.process.exit(0);
    }
    std.process.exit(1);
}
const Foo = enum(u8) {
    a,
    b,
    c,
};
pub fn main() !void {
    _ = bar(3);
    return error.TestFailed;
}
fn bar(a: u8) Foo {
    return @bitCast(a);
}

// run
// backend=selfhosted,llvm
// target=x86_64-linux,aarch64-linux
