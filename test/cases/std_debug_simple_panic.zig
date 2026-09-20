const std = @import("std");

pub const panic = std.debug.simple_panic;

pub fn main() void {
    @panic("this makes the compiler reference the panic namespace");
}

// compile
