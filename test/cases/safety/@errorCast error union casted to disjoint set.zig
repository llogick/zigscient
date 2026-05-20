const std = @import("std");

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = stack_trace;
    if (std.mem.eql(u8, message, "unexpected error code, found error.Bar")) {
        std.process.exit(0);
    }
    std.process.exit(1);
}
pub fn main() !void {
    const bar: error{Foo}!i32 = @errorCast(foo());
    _ = &bar;
    return error.TestFailed;
}
fn foo() anyerror!i32 {
    return error.Bar;
}
// run
// backend=selfhosted,llvm
// target=x86_64-linux,wasm32-wasi
