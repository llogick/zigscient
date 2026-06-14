const builtin = @import("builtin");

const std = @import("std");
const c = std.c;

const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC() or builtin.target.isMinGW()) {
        symbol(&pthread_spin_init, "pthread_spin_init");
        symbol(&pthread_spin_destroy, "pthread_spin_destroy");
        symbol(&pthread_spin_trylock, "pthread_spin_trylock");
        symbol(&pthread_spin_lock, "pthread_spin_lock");
        symbol(&pthread_spin_unlock, "pthread_spin_unlock");
    }
}

const SpinLock = enum(c.pthread_spinlock_t) {
    unlocked = if (builtin.target.isMinGW()) -1 else 0,
    locked = if (builtin.target.isMinGW()) 0 else @intFromEnum(c.E.BUSY),
};

fn pthread_spin_init(s: *c.pthread_spinlock_t, pshared: c_int) callconv(.c) c_int {
    _ = pshared;
    const spin: *SpinLock = @ptrCast(s);
    spin.* = .unlocked;
    return 0;
}

fn pthread_spin_destroy(s: *c.pthread_spinlock_t) callconv(.c) c_int {
    const spin: *SpinLock = @ptrCast(s);
    spin.* = undefined;
    return 0;
}

fn pthread_spin_trylock(s: *c.pthread_spinlock_t) callconv(.c) c_int {
    const spin: *SpinLock = @ptrCast(s);
    return if (@cmpxchgStrong(SpinLock, spin, .unlocked, .locked, .acquire, .monotonic)) |_| @intFromEnum(c.E.BUSY) else 0;
}

fn pthread_spin_lock(s: *c.pthread_spinlock_t) callconv(.c) c_int {
    const spin: *SpinLock = @ptrCast(s);
    if (builtin.single_threaded and @atomicLoad(SpinLock, spin, .monotonic) == .locked) return @intFromEnum(c.E.DEADLK);

    while (@cmpxchgWeak(SpinLock, spin, .unlocked, .locked, .acquire, .monotonic)) |_| {
        std.atomic.spinLoopHint();
    }
    return 0;
}

fn pthread_spin_unlock(s: *c.pthread_spinlock_t) callconv(.c) c_int {
    const spin: *SpinLock = @ptrCast(s);

    // "The results are undefined if the lock is not held by the calling thread"
    std.debug.assert(@atomicRmw(SpinLock, spin, .Xchg, .unlocked, .release) == .locked);
    return 0;
}
