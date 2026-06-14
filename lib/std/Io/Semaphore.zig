//! An unsigned integer that blocks the kernel thread if the number would
//! become negative.
//!
//! This API supports static initialization and does not require deinitialization.
const Semaphore = @This();

const builtin = @import("builtin");

const std = @import("../std.zig");
const Io = std.Io;
const testing = std.testing;

mutex: Io.Mutex = .init,
cond: Io.Condition = .init,
/// It is OK to initialize this field to any value.
permits: usize = 0,

/// Blocks until a `permit` is available and consumes a single one.
/// Unblocks without consuming a `permit` when canceled.
///
/// See also:
/// * `waitTimeout`
/// * `waitUncancelable`
pub fn wait(s: *Semaphore, io: Io) Io.Cancelable!void {
    s.waitTimeout(io, .none) catch |err| switch (err) {
        error.Timeout => unreachable,
        error.Canceled => |e| return e,
    };
}

pub const WaitTimeoutError = Io.Cancelable || Io.Timeout.Error;

/// Blocks until a `permit` is available and consumes a single one.
/// Unblocks without consuming a `permit` when canceled or when the provided
/// timeout expires before a `permit` is available.
///
/// See also:
/// * `wait`
/// * `waitUncancelable`
pub fn waitTimeout(s: *Semaphore, io: Io, timeout: Io.Timeout) WaitTimeoutError!void {
    const deadline = timeout.toDeadline(io);
    try s.mutex.lock(io);
    defer s.mutex.unlock(io);
    while (s.permits == 0) try s.cond.waitTimeout(io, &s.mutex, deadline);
    s.permits -= 1;
    if (s.permits > 0) s.cond.signal(io);
}

/// Blocks until a `permit` is available and consumes a single one.
///
/// See also:
/// * `wait`
/// * `waitTimeout`
pub fn waitUncancelable(s: *Semaphore, io: Io) void {
    s.mutex.lockUncancelable(io);
    defer s.mutex.unlock(io);
    while (s.permits == 0) s.cond.waitUncancelable(io, &s.mutex);
    s.permits -= 1;
    if (s.permits > 0) s.cond.signal(io);
}

/// Makes an additional `permit` available.
pub fn post(s: *Semaphore, io: Io) void {
    s.mutex.lockUncancelable(io);
    defer s.mutex.unlock(io);

    s.permits += 1;
    s.cond.signal(io);
}

test wait {
    const io = testing.io;

    const Context = struct {
        sem: Semaphore = .{ .permits = 1 },
        n: u32 = 0,

        fn worker(ctx: *@This()) !void {
            try ctx.sem.wait(io);
            ctx.n += 1;
            ctx.sem.post(io);
        }
    };

    var ctx: Context = .{};

    var group: Io.Group = .init;
    defer group.cancel(io);

    const num_workers = 3;
    for (0..num_workers) |_| group.async(io, Context.worker, .{&ctx});

    try group.await(io);
    try testing.expectEqual(num_workers, ctx.n);
}

test waitTimeout {
    const io = testing.io;

    const Context = struct {
        ready: Io.Event = .unset,
        sem: Semaphore = .{ .permits = 0 },
        value: u32 = 0,

        fn worker(ctx: *@This()) !void {
            defer ctx.ready.set(io);

            try testing.expectError(error.Timeout, ctx.sem.waitTimeout(io, .{ .duration = .{
                .raw = .fromMilliseconds(1),
                .clock = .awake,
            } }));
            try testing.expectEqual(0, ctx.value);

            ctx.ready.set(io);

            while (ctx.value == 0) try ctx.sem.wait(io);
            try testing.expectEqual(1, ctx.value);
        }
    };

    var ctx: Context = .{};

    var future = io.concurrent(Context.worker, .{&ctx}) catch |err| switch (err) {
        error.ConcurrencyUnavailable => return error.SkipZigTest,
    };
    defer future.cancel(io) catch {};

    try ctx.ready.wait(io);

    ctx.value = 1;
    ctx.sem.post(io);

    try future.await(io);
}

test waitUncancelable {
    const io = testing.io;

    const Context = struct {
        sem: Semaphore = .{ .permits = 1 },
        n: u32 = 0,

        fn worker(ctx: *@This()) !void {
            ctx.sem.waitUncancelable(io);
            ctx.n += 1;
            ctx.sem.post(io);
        }
    };

    var ctx: Context = .{};

    var group: Io.Group = .init;
    defer group.cancel(io);

    const num_workers = 3;
    for (0..num_workers) |_| group.async(io, Context.worker, .{&ctx});

    try group.await(io);
    try testing.expectEqual(num_workers, ctx.n);
}
