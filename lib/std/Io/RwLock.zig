//! A lock that supports one writer or many readers.
const RwLock = @This();

const builtin = @import("builtin");

const std = @import("../std.zig");
const Io = std.Io;
const assert = std.debug.assert;
const testing = std.testing;

state: usize,
mutex: Io.Mutex,
semaphore: Io.Semaphore,

pub const init: RwLock = .{
    .state = 0,
    .mutex = .init,
    .semaphore = .{},
};

const is_writing: usize = 1;
const writer: usize = 1 << 1;
const reader: usize = 1 << (1 + @bitSizeOf(Count));
const writer_mask: usize = std.math.maxInt(Count) << @ctz(writer);
const reader_mask: usize = std.math.maxInt(Count) << @ctz(reader);
const Count = @Int(.unsigned, @divFloor(@bitSizeOf(usize) - 1, 2));

pub fn tryLock(rl: *RwLock, io: Io) bool {
    if (rl.mutex.tryLock()) {
        // Unlike `lock`, this never registers in `writer_mask`, so holding the mutex does
        // not stop a reader from taking the fast path; the CAS catches one that raced in
        // after `state` was loaded.
        const state = @atomicLoad(usize, &rl.state, .seq_cst);
        if (state & reader_mask == 0) {
            _ = @cmpxchgStrong(
                usize,
                &rl.state,
                state,
                state | is_writing,
                .seq_cst,
                .seq_cst,
            ) orelse return true;
        }

        rl.mutex.unlock(io);
    }

    return false;
}

pub fn lockUncancelable(rl: *RwLock, io: Io) void {
    _ = @atomicRmw(usize, &rl.state, .Add, writer, .seq_cst);
    rl.mutex.lockUncancelable(io);

    const state = @atomicRmw(usize, &rl.state, .Add, is_writing -% writer, .seq_cst);
    if (state & reader_mask != 0)
        rl.semaphore.waitUncancelable(io);
}

pub fn lock(rl: *RwLock, io: Io) Io.Cancelable!void {
    _ = @atomicRmw(usize, &rl.state, .Add, writer, .seq_cst);
    rl.mutex.lock(io) catch |err| switch (err) {
        error.Canceled => {
            _ = @atomicRmw(usize, &rl.state, .Sub, writer, .seq_cst);
            return error.Canceled;
        },
    };

    const state = @atomicRmw(usize, &rl.state, .Add, is_writing -% writer, .seq_cst);
    if (state & reader_mask != 0)
        rl.semaphore.wait(io) catch |err| switch (err) {
            error.Canceled => {
                // Clearing `is_writing` while still holding the mutex means the last reader
                // either saw it set, and posts a permit only we can consume, or did not and
                // never posts. A stale permit would let the next writer in past the readers.
                const prev_state = @atomicRmw(usize, &rl.state, .And, ~is_writing, .seq_cst);
                if (prev_state & reader_mask == 0) rl.semaphore.waitUncancelable(io);
                rl.mutex.unlock(io);
                return error.Canceled;
            },
        };
}

pub fn unlock(rl: *RwLock, io: Io) void {
    _ = @atomicRmw(usize, &rl.state, .And, ~is_writing, .seq_cst);
    rl.mutex.unlock(io);
}

pub fn tryLockShared(rl: *RwLock, io: Io) bool {
    const state = @atomicLoad(usize, &rl.state, .seq_cst);
    if (state & (is_writing | writer_mask) == 0) {
        _ = @cmpxchgStrong(
            usize,
            &rl.state,
            state,
            state + reader,
            .seq_cst,
            .seq_cst,
        ) orelse return true;
    }

    if (rl.mutex.tryLock()) {
        _ = @atomicRmw(usize, &rl.state, .Add, reader, .seq_cst);
        rl.mutex.unlock(io);
        return true;
    }

    return false;
}

pub fn lockSharedUncancelable(rl: *RwLock, io: Io) void {
    var state = @atomicLoad(usize, &rl.state, .seq_cst);
    while (state & (is_writing | writer_mask) == 0) {
        state = @cmpxchgWeak(
            usize,
            &rl.state,
            state,
            state + reader,
            .seq_cst,
            .seq_cst,
        ) orelse return;
    }

    rl.mutex.lockUncancelable(io);
    _ = @atomicRmw(usize, &rl.state, .Add, reader, .seq_cst);
    rl.mutex.unlock(io);
}

pub fn lockShared(rl: *RwLock, io: Io) Io.Cancelable!void {
    var state = @atomicLoad(usize, &rl.state, .seq_cst);
    while (state & (is_writing | writer_mask) == 0) {
        state = @cmpxchgWeak(
            usize,
            &rl.state,
            state,
            state + reader,
            .seq_cst,
            .seq_cst,
        ) orelse return;
    }

    try rl.mutex.lock(io);
    _ = @atomicRmw(usize, &rl.state, .Add, reader, .seq_cst);
    rl.mutex.unlock(io);
}

pub fn unlockShared(rl: *RwLock, io: Io) void {
    const state = @atomicRmw(usize, &rl.state, .Sub, reader, .seq_cst);

    if ((state & reader_mask == reader) and (state & is_writing != 0))
        rl.semaphore.post(io);
}

test "internal state" {
    const io = testing.io;

    var rl: Io.RwLock = .init;

    // The following failed prior to the fix for Issue #13163,
    // where the WRITER flag was subtracted by the lock method.

    rl.lockUncancelable(io);
    rl.unlock(io);
    try testing.expectEqual(rl, Io.RwLock.init);

    try rl.lock(io);
    rl.unlock(io);
    try testing.expectEqual(rl, Io.RwLock.init);
}

test "smoke test" {
    const io = testing.io;

    var rl: Io.RwLock = .init;

    rl.lockUncancelable(io);
    try testing.expect(!rl.tryLock(io));
    try testing.expect(!rl.tryLockShared(io));
    rl.unlock(io);

    try rl.lock(io);
    try testing.expect(!rl.tryLock(io));
    try testing.expect(!rl.tryLockShared(io));
    rl.unlock(io);

    try testing.expect(rl.tryLock(io));
    try testing.expect(!rl.tryLock(io));
    try testing.expect(!rl.tryLockShared(io));
    rl.unlock(io);

    rl.lockSharedUncancelable(io);
    try testing.expect(!rl.tryLock(io));
    try testing.expect(rl.tryLockShared(io));
    rl.unlockShared(io);
    rl.unlockShared(io);

    try testing.expect(rl.tryLockShared(io));
    try testing.expect(!rl.tryLock(io));
    try testing.expect(rl.tryLockShared(io));
    rl.unlockShared(io);
    rl.unlockShared(io);

    rl.lockUncancelable(io);
    rl.unlock(io);
}

test "concurrent access" {
    if (builtin.single_threaded) return;

    const io = testing.io;
    const num_writers: usize = 2;
    const num_readers: usize = 4;
    const num_writes: usize = 1000;
    const num_reads: usize = 2000;

    const Runner = struct {
        const Runner = @This();

        io: Io,

        rl: Io.RwLock,
        writes: usize,
        reads: std.atomic.Value(usize),

        val_a: usize,
        val_b: usize,

        fn reader(run: *Runner, thread_idx: usize) !void {
            var prng = std.Random.DefaultPrng.init(thread_idx);
            const rnd = prng.random();
            while (true) {
                run.rl.lockSharedUncancelable(run.io);
                defer run.rl.unlockShared(run.io);

                try testing.expect(run.writes <= num_writes);
                if (run.reads.fetchAdd(1, .monotonic) >= num_reads) break;

                // We use `volatile` accesses so that we can make sure the memory is accessed either
                // side of a yield, maximising chances of a race.
                const a_ptr: *const volatile usize = &run.val_a;
                const b_ptr: *const volatile usize = &run.val_b;

                const old_a = a_ptr.*;
                if (rnd.boolean()) try std.Thread.yield();
                const old_b = b_ptr.*;
                try testing.expect(old_a == old_b);
            }
        }

        fn writer(run: *Runner, thread_idx: usize) !void {
            var prng = std.Random.DefaultPrng.init(thread_idx);
            const rnd = prng.random();
            while (true) {
                run.rl.lockUncancelable(run.io);
                defer run.rl.unlock(run.io);

                try testing.expect(run.writes <= num_writes);
                if (run.writes == num_writes) break;

                // We use `volatile` accesses so that we can make sure the memory is accessed either
                // side of a yield, maximising chances of a race.
                const a_ptr: *volatile usize = &run.val_a;
                const b_ptr: *volatile usize = &run.val_b;

                const new_val = rnd.int(usize);

                const old_a = a_ptr.*;
                a_ptr.* = new_val;
                if (rnd.boolean()) try std.Thread.yield();
                const old_b = b_ptr.*;
                b_ptr.* = new_val;
                try testing.expect(old_a == old_b);

                run.writes += 1;
            }
        }
    };

    var run: Runner = .{
        .io = io,
        .rl = .init,
        .writes = 0,
        .reads = .init(0),
        .val_a = 0,
        .val_b = 0,
    };
    var write_threads: [num_writers]std.Thread = undefined;
    var read_threads: [num_readers]std.Thread = undefined;

    for (&write_threads, 0..) |*t, i| t.* = try .spawn(.{}, Runner.writer, .{ &run, i });
    for (&read_threads, num_writers..) |*t, i| t.* = try .spawn(.{}, Runner.reader, .{ &run, i });

    for (write_threads) |t| t.join();
    for (read_threads) |t| t.join();

    try testing.expect(run.writes == num_writes);
    try testing.expect(run.reads.raw >= num_reads);
}

test "lock canceling" {
    const io = testing.io;

    var rl: Io.RwLock = .init;

    rl.lockSharedUncancelable(io);
    var sfuture = io.concurrent(semaphoreLockCancel, .{ &rl, io }) catch |err| switch (err) {
        error.ConcurrencyUnavailable => return error.SkipZigTest,
    };
    try std.testing.expectEqual(error.Canceled, sfuture.cancel(io));
    rl.unlockShared(io);
    try testing.expectEqual(rl, Io.RwLock.init);

    rl.lockUncancelable(io);
    var mfuture = io.concurrent(mutexLockCancel, .{ &rl, io }) catch |err| switch (err) {
        error.ConcurrencyUnavailable => return error.SkipZigTest,
    };
    try std.testing.expectEqual(error.Canceled, mfuture.cancel(io));
    rl.unlock(io);
    try testing.expectEqual(rl, Io.RwLock.init);
}

test "tryLock does not race with readers" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const Context = struct {
        rl: Io.RwLock,

        fn reader(ctx: *@This(), io: Io) !void {
            while (true) {
                if (ctx.rl.tryLockShared(io)) ctx.rl.unlockShared(io);
                try io.checkCancel();
            }
        }
    };

    var ctx: Context = .{ .rl = .init };
    const io = testing.io;

    var future = io.concurrent(Context.reader, .{ &ctx, io }) catch |err| switch (err) {
        error.ConcurrencyUnavailable => return error.SkipZigTest,
    };
    defer future.cancel(io) catch {};

    for (0..1000) |_| {
        if (!ctx.rl.tryLock(io)) continue;
        defer ctx.rl.unlock(io);
        const state = @atomicLoad(usize, &ctx.rl.state, .seq_cst);
        try testing.expectEqual(0, state & reader_mask);
    }

    try testing.expectEqual(0, ctx.rl.semaphore.permits);
}

test "canceled writer does not leak a semaphore permit" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const Writer = struct {
        fn lockUnlock(rl: *Io.RwLock, io: Io) Io.Cancelable!void {
            try rl.lock(io);
            rl.unlock(io);
        }
    };

    const io = testing.io;

    var rl: Io.RwLock = .init;

    for (0..1000) |_| {
        rl.lockSharedUncancelable(io);

        var wfuture = io.concurrent(Writer.lockUnlock, .{ &rl, io }) catch |err| switch (err) {
            error.ConcurrencyUnavailable => {
                rl.unlockShared(io);
                return error.SkipZigTest;
            },
        };
        var rfuture = io.concurrent(Io.RwLock.unlockShared, .{ &rl, io }) catch |err| switch (err) {
            error.ConcurrencyUnavailable => {
                rl.unlockShared(io);
                wfuture.await(io) catch {};
                return error.SkipZigTest;
            },
        };

        // Races the last reader's `post` against the writer's cancelation.
        wfuture.cancel(io) catch {};
        rfuture.await(io);

        try testing.expectEqual(0, rl.state);
        try testing.expectEqual(0, rl.semaphore.permits);
    }
}

fn semaphoreLockCancel(rl: *Io.RwLock, io: Io) !void {
    try rl.lock(io); //tests semaphore cancelling
}

fn mutexLockCancel(rl: *Io.RwLock, io: Io) !void {
    //tests mutex canceling
    try std.testing.expectEqual(error.Canceled, rl.lockShared(io));
    io.recancel();
    try std.testing.expectEqual(error.Canceled, rl.lock(io));
    return error.Canceled;
}
