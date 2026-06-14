const builtin = @import("builtin");

const std = @import("std");
const intmax_t = std.c.intmax_t;
const imaxdiv_t = std.c.imaxdiv_t;

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        // Functions specific to musl and wasi-libc.
        symbol(&imaxabs, "imaxabs");
        symbol(&imaxdiv, "imaxdiv");
    }
}

fn imaxabs(a: intmax_t) callconv(.c) intmax_t {
    return @intCast(@abs(a));
}

fn imaxdiv(a: intmax_t, b: intmax_t) callconv(.c) imaxdiv_t {
    return .{
        .quot = @divTrunc(a, b),
        .rem = @rem(a, b),
    };
}
