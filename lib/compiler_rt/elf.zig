const builtin = @import("builtin");
const std = @import("std");

const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;

/// More operating systems are expected to be added here:
///
/// * FreeBSD: https://codeberg.org/ziglang/zig/issues/30981
/// * NetBSD: https://codeberg.org/ziglang/zig/issues/30980
/// * OpenBSD: https://codeberg.org/ziglang/zig/issues/30982
const use_zig_start = switch (builtin.target.os.tag) {
    .linux,
    => !builtin.link_libc,
    else => false,
};

comptime {
    if (use_zig_start) {
        _ = @import("elf/auxv.zig");
        _ = @import("elf/tls.zig");
    }
}
