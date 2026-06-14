const std = @import("std");
const expectEqual = std.testing.expectEqual;

extern "kernel32" fn ExitProcess(exit_code: c_uint) callconv(.winapi) noreturn;

test "foo" {
    const value = bar() catch ExitProcess(1);
    try expectEqual(1234, value);
}

fn bar() anyerror!u32 {
    return 1234;
}

// test
// target=x86_64-windows
