const std = @import("std");

pub fn main() void {
    _ = bar();
}

inline fn bar() u8 {
    noret();
}

inline fn noret() noreturn {
    std.process.exit(0);
}

// run
