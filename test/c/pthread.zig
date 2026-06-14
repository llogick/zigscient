const builtin = @import("builtin");
const std = @import("std");

const c = std.c;
const math = std.math;
const testing = std.testing;

test "pthread_spinlock_t" {
    if (builtin.target.os.tag.isDarwin()) return; // Darwin doesn't have `pthread_spin_*`
    if (builtin.target.os.tag == .windows and builtin.target.abi != .gnu) return; // winpthreads-only

    var spin: c.pthread_spinlock_t = undefined;
    _ = c.pthread_spin_init(&spin, c.PTHREAD_PROCESS_PRIVATE);
    defer _ = c.pthread_spin_destroy(&spin);

    try std.testing.expectEqual(@intFromEnum(c.E.SUCCESS), c.pthread_spin_trylock(&spin));
    try std.testing.expectEqual(@intFromEnum(c.E.SUCCESS), c.pthread_spin_unlock(&spin));

    try std.testing.expectEqual(@intFromEnum(c.E.SUCCESS), c.pthread_spin_lock(&spin));
    try std.testing.expectEqual(@intFromEnum(c.E.SUCCESS), c.pthread_spin_unlock(&spin));
}
