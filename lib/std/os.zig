const builtin = @import("builtin");
const std = @import("std.zig");
const native_os = builtin.os.tag;

pub const linux = @import("os/linux.zig");
pub const plan9 = @import("os/plan9.zig");
pub const uefi = @import("os/uefi.zig");
pub const wasi = @import("os/wasi.zig");
pub const emscripten = @import("os/emscripten.zig");
pub const windows = @import("os/windows.zig");

/// Returns whether the Zig standard library requires libc in order to interface
/// with the operating system on the given target.
pub fn targetRequiresLibC(target: *const std.Target) bool {
    if (target.requiresLibC()) return true;
    return switch (target.os.tag) {
        .linux => switch (target.cpu.arch) {
            // https://codeberg.org/ziglang/zig/issues/30943
            .hppa,
            .hppa64,
            => true,
            else => false,
        },
        .freebsd => true, // https://codeberg.org/ziglang/zig/issues/30981
        .netbsd => true, // https://codeberg.org/ziglang/zig/issues/30980
        .openbsd => true, // https://codeberg.org/ziglang/zig/issues/30982
        else => false,
    };
}

/// Returns whether the Zig standard library requires libc in order to interface
/// with the operating system on the current target.
pub fn requiresLibC() bool {
    return targetRequiresLibC(&builtin.target);
}

test {
    _ = linux;
    if (native_os == .uefi) _ = uefi;
    _ = wasi;
    _ = windows;
}
