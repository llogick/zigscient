//! This exists to satisfy the `std.posix` interface for WASI w/o libc. Most of the stuff here is
//! taken from wasi-libc, i.e. it is essentially made up from the perspective of pure WASI. This
//! should be removed alongside `std.posix` eventually.

const builtin = @import("builtin");
const std = @import("../std.zig");

const wasi = std.os.wasi;

pub const pid_t = i32;
pub const fd_t = wasi.fd_t;
pub const uid_t = u32;
pub const gid_t = u32;
pub const mode_t = u0;
pub const nlink_t = u64;
pub const ino_t = wasi.inode_t;

pub const time_t = i64;
pub const timespec = extern struct {
    sec: time_t,
    nsec: c_long,

    pub fn fromTimestamp(tm: wasi.timestamp_t) @This() {
        const sec: wasi.timestamp_t = tm / 1_000_000_000;
        const nsec = tm - sec * 1_000_000_000;
        return .{
            .sec = @as(time_t, @intCast(sec)),
            .nsec = @as(isize, @intCast(nsec)),
        };
    }

    pub fn toTimestamp(ts: @This()) wasi.timestamp_t {
        return @as(wasi.timestamp_t, @intCast(ts.sec * 1_000_000_000)) +
            @as(wasi.timestamp_t, @intCast(ts.nsec));
    }
};

pub const pollfd = extern struct {
    fd: fd_t,
    events: i16,
    revents: i16 = undefined,
};

pub const rlimit_resource = void;

pub const E = wasi.errno_t;

pub const SIG = void;
pub const Sigaction = void;

pub const PROT = void;

pub const MCL = void;

pub const AT = struct {
    pub const EACCESS = 0x0;
    pub const SYMLINK_NOFOLLOW = 0x1;
    pub const SYMLINK_FOLLOW = 0x2;
    pub const REMOVEDIR = 0x4;

    pub const FDCWD: fd_t = 3;
};

pub const IFNAMESIZE = {};

pub const STDIN_FILENO = 0;
pub const STDOUT_FILENO = 1;
pub const STDERR_FILENO = 2;

pub const PATH_MAX = 4096;
pub const IOV_MAX = 1024;

pub const getrandom = {};

pub const mlock = {};
pub const mlock2 = {};
pub const munlock = {};
pub const mlockall = {};
pub const munlockall = {};

pub const cmsg_align = {};
