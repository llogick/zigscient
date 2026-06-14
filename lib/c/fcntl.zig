const builtin = @import("builtin");

const std = @import("std");
const linux = std.os.linux;
const off_t = linux.off_t;

const symbol = @import("../c.zig").symbol;
const errno = @import("../c.zig").errno;

comptime {
    if (builtin.target.isMuslLibC()) {
        symbol(&fallocateLinux, "fallocate");
        symbol(&posix_fadviseLinux, "posix_fadvise");
        symbol(&posix_fallocateLinux, "posix_fallocate");
        symbol(&teeLinux, "tee");
    }
}

fn fallocateLinux(fd: c_int, mode: c_int, offset: off_t, len: off_t) callconv(.c) c_int {
    return errno(linux.fallocate(fd, @bitCast(mode), offset, len));
}

fn posix_fadviseLinux(fd: c_int, offset: off_t, len: off_t, advice: c_int) callconv(.c) c_int {
    return errno(linux.fadvise(fd, offset, len, @intCast(advice)));
}

fn posix_fallocateLinux(fd: c_int, offset: off_t, len: off_t) callconv(.c) c_int {
    return errno(linux.fallocate(fd, 0, offset, len));
}

fn teeLinux(src: c_int, dest: c_int, len: usize, flags: c_uint) callconv(.c) isize {
    return errno(linux.tee(src, dest, len, flags));
}
