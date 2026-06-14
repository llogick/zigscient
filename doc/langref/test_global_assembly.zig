const std = @import("std");
const expectEqual = std.testing.expectEqual;

comptime {
    asm (
        \\.global my_func;
        \\.type my_func, @function;
        \\my_func:
        \\  lea (%rdi,%rsi,1),%eax
        \\  retq
    );
}

extern fn my_func(a: i32, b: i32) i32;

test "global assembly" {
    try expectEqual(46, my_func(12, 34));
}

// test
// target=x86_64-linux
// llvm=true
