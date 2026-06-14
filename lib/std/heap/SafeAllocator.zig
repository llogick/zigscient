//! Provides the following guarantees:
//! * `deinit` reports all leaks and frees all backing memory.
//! * All allocation mismatches result in either a panic or segmentation fault.
//! * Allocations from other `SafeAllocator` instances cause a panic (if `Options.canary` differ).
//! * Double frees and operation (resize, remap, and free) races panic or segmentation fault.
//!
//! Given the backing allocator does not reuse memory, this does not reuse memory either and
//! * Most writes after free will segmentation fault or are eventually detected and panic.
//!
//! Thread-safe

// General Design:
//
// Every allocation is trailed by an `AllocFooter` which contains metadata for the allocation and
// stack traces. It is protected by a checksum to catch corruption from allocation overwrites and
// report canary mismatches. An allocation's memory has a minimum alignment of `AllocFooter` so
// that the footer is at a fixed offset determined from the allocation size. An allocation's memory
// is stored either:
// * Inside linearly-filled buckets for small allocations.
// * Inside an allocation directly from the backing allocator.
//
// To track allocations, each thread maintains a table of backing allocations. The table may be
// modified by other threads in the case of a producer-consumer operation, so the table is a linked
// list only expanded by creating new segments. Each thread maintains a linked list of free
// entries, which may contain entries from other threads' tables.
//
// In the case of producer-consumer operations, acquire/release ordering is assumed to be provided
// externally. This is also assumed by all other thread-safe allocators that reuse memory as
// otherwise there would be data races on reuse of allocated memory.

const std = @import("../std.zig");
const math = std.math;
const mem = std.mem;
const Alignment = mem.Alignment;
const assert = std.debug.assert;
const panic = std.debug.panic;

const SafeAllocator = @This();
const scoped_log = std.log.scoped(.SafeAllocator);

pub const Options = struct {
    const is_debug = @import("builtin").mode == .Debug;
    const page_size_log2 = @max(math.log2_int(usize, std.heap.page_size_max), 8);

    stack_trace_frames: usize = if (is_debug and std.debug.sys_can_stack_trace) 7 else 0,
    check_write_after_free: bool = is_debug,
    /// A unique value used to check that allocations created by other
    /// `SafeAllocator` instances are not passed to this one.
    canary: u32 = 0x85dff10f,

    /// Controls the block size and alignment of allocation buckets.
    ///
    /// Changing this is useful to save memory if the backing allocator offers better granuality,
    /// or if the backing allocator has a limit on active allocations, however decreasing this
    /// can harm performance.
    ///
    /// Asserted to be >= 8
    bucket_size_log2: u5 = @max(page_size_log2, 13),
    /// Controls the block size of internal metadata.
    ///
    /// Changing this is useful to save memory if the backing allocator offers better granuality,
    /// or if the backing allocator has a limit on active allocations, however decreasing this
    /// can harm performance.
    ///
    /// Asserted to be >= 8
    block_size_log2: u5 = page_size_log2,
};

var n_threads: usize = 0;
threadlocal var thread_index: usize = 0;

backing: mem.Allocator,
// Needs to be a fixed size so the max `n_threads` value is agreed upon by all instances.
threads: [128]Thread,

bucket_size_log2: u5,
block_size_log2: u5,
/// In `usize`s
stack_trace_size: usize,
/// In `usize`s
allocs_entry_count: usize,
large_alloc_threshold: usize,

canary: u32,
check_write_after_free: bool,

fn bucketSize(s: *SafeAllocator) u32 {
    return @as(u32, 1) << s.bucket_size_log2;
}

fn bucketMask(s: *SafeAllocator) u32 {
    return s.bucketSize() - 1;
}

const Thread = struct {
    /// Avoid false sharing.
    _: void align(std.atomic.cache_line) = {},

    mutex: std.atomic.Mutex,
    fill_bucket: ?*Bucket,
    free_entry: ?*Allocs.Entry,
    allocs_next: usize,
    allocs_first: ?*Allocs,
};

/// Trailed by `[allocs_entry_count]Entry`
const Allocs = extern struct {
    next: ?*Allocs,

    comptime {
        assert(@alignOf(@This()) == @alignOf(usize));
        assert(@sizeOf(@This()) == @sizeOf(usize));
    }

    fn usizes(a: *Allocs, s: *SafeAllocator) []usize {
        return @as([*]usize, @ptrCast(a))[0 .. 1 + s.allocs_entry_count];
    }

    fn entries(a: *Allocs, s: *SafeAllocator) []Entry {
        return @as([*]Entry, @ptrCast(a))[1..][0..s.allocs_entry_count];
    }

    const Entry = packed struct(usize) {
        kind: Kind,
        ptr_high: @Int(.unsigned, @bitSizeOf(usize) - 2),

        const Kind = enum(u2) { free, bucket, large_alloc };

        comptime {
            assert(@alignOf(Entry) >= 4);
            assert(@alignOf(Bucket) >= 4);
            assert(@alignOf(AllocFooter) >= 4);
        }

        fn fromFree(ptr: ?*Entry) Entry {
            return .{
                .ptr_high = @intCast(@intFromPtr(ptr) >> 2),
                .kind = .free,
            };
        }

        fn fromBucket(ptr: *Bucket) Entry {
            return .{
                .ptr_high = @intCast(@intFromPtr(ptr) >> 2),
                .kind = .bucket,
            };
        }

        fn fromLargeAlloc(ptr: *AllocFooter) Entry {
            return .{
                .ptr_high = @intCast(@intFromPtr(ptr) >> 2),
                .kind = .large_alloc,
            };
        }

        fn toFree(ent: Entry) ?*Entry {
            assert(ent.kind == .free);
            return @ptrFromInt(@as(usize, ent.ptr_high) << 2);
        }

        fn toBucket(ent: Entry) *Bucket {
            assert(ent.kind == .bucket);
            return @ptrFromInt(@as(usize, ent.ptr_high) << 2);
        }

        fn toLargeAlloc(ent: Entry) *AllocFooter {
            assert(ent.kind == .large_alloc);
            return @ptrFromInt(@as(usize, ent.ptr_high) << 2);
        }
    };
};

/// This struct contains the header for a bucket. It is always part of a larger
/// allocations of length and alignment `bucketSize()`.
///
/// All allocations inside buckets have a minimum of 8-byte alignment (including length)
/// so that allocations with 8-byte alignment or less do not need to store the location
/// of the previous footer since it is directly before it. This property is used by non-
/// extended footers to omit the offset of the previous footer.
const Bucket = struct {
    entry: *Allocs.Entry,
    /// Accesed atomically with `.acquire` / `.release` ordering to
    /// provide memory ordering for allocation footers, **expect for
    /// the `modify` field**. This needs `.acquire` fenced every time
    /// footer data is updated (`AllocCount.fenceAcqRel`).
    alloc_count: AllocCount,
    /// Accesed atomically with `.monotonic` ordering. Alternatively,
    /// this is also synchronized by `alloc_count`.
    fill: Fill,

    /// So that `@sizeOf(Bucket)` is the start of first allocation if it is 8-byte aligned or less.
    _: void align(8) = {},
    comptime {
        assert(@alignOf(@This()) >= 8);
    }

    const AllocCount = packed struct(u32) {
        n: u31,
        /// If `true`, this bucket cannot be freed yet.
        filling: bool,

        fn fenceAcqRel(a: *AllocCount) void {
            _ = @atomicRmw(AllocCount, a, .Or, .{ .n = 0, .filling = false }, .acq_rel);
        }
    };

    const Fill = packed struct(u32) {
        at: u31,
        last_is_extended: bool,
    };

    fn of(s: *SafeAllocator, ptr: [*]u8) *Bucket {
        const size_log2 = s.bucket_size_log2;
        return @ptrFromInt(@intFromPtr(ptr) >> @intCast(size_log2) << @intCast(size_log2));
    }

    fn fillAt(s: *SafeAllocator, ptr: [*]const u8) u32 {
        return @intCast(@intFromPtr(ptr) & s.bucketMask());
    }

    fn bytes(b: *Bucket, s: *SafeAllocator) []u8 {
        assert(@intFromPtr(b) & s.bucketMask() == 0);
        return @as([*]u8, @ptrCast(b))[0..s.bucketSize()];
    }

    fn lastAlloc(b: *Bucket, s: *SafeAllocator, fill: Fill) ?*AllocFooter {
        return b.allocFooterBefore(s, fill.at, fill.last_is_extended);
    }

    fn allocFooterBefore(b: *Bucket, s: *SafeAllocator, at: u32, is_extended: bool) ?*AllocFooter {
        if (at - @sizeOf(Bucket) == 0) return null;
        const off = at - AllocFooter.lenBucket(s, is_extended);
        assert(off >= @sizeOf(Bucket));
        return @ptrCast(@alignCast(b.bytes(s)[off..]));
    }

    /// Checks that no writes after frees were performed.
    ///
    /// Assumes `b.alloc_count` has been loaded with `.acquire` ordering.
    fn check(b: *Bucket, s: *SafeAllocator) void {
        var footer = b.lastAlloc(s, b.fill).?;
        while (true) {
            const modify = @atomicLoad(
                AllocFooter.Modify,
                &footer.modify,
                // The only possible value should be `.freed` since `b.alloc_count`
                // has been loaded with `.acquire`. However, another thread may be trying to
                // modify the allocation after it is freed and so the other thread is going
                // to panic even if this thread still sees `.freed`.
                .unordered,
            ).storedXor(&footer.modify);
            if (modify != .freed or footer.actualChecksum(s) != footer.checksum ^ s.canary) {
                panic("corrupted footer metadata in bucket at *{x}", .{@intFromPtr(&footer)});
            }

            s.checkFreed(footer);
            footer = footer.bucketPrev(b, s) orelse break;
        }
    }
};

/// Trails the allocation, which has the following advantages:
/// * For buckets, the footer of the last allocation is always at the current fill.
/// * Aligning the allocation is simpler and wastes less space.
/// * Allocation overwrites are more likely to be caught by the footer getting corrupted.
/// For bucket allocs, this is trailed by `[2][stack_trace_size]usize`.
/// For large allocs, this is trailed by `[1][stack_trace_size]usize`.
const AllocFooter = struct {
    /// Hash of `data` with the seed as the hash of its address so that memcpys of allocation
    /// metadata are detected or are at least caught across runs.
    ///
    /// This stored value is xored with the canary value so that canary mismatches are detected.
    checksum: u32,
    /// Accesed atomically with `.monotonic` ordering to catch operation races.
    ///
    /// This stored value is xored with the hash of its address so that memcpys of allocation
    /// metadata are detected or are at least caught across runs.
    modify: Modify,
    data: Data,

    /// `8`: minimum alignment for `Bucket` allocations
    /// `@alignOf(usize)`: so that the offset of trailing data is at `@sizeOf(@This())`
    _: void align(@max(8, @alignOf(usize))) = {},

    comptime {
        assert(@alignOf(@This()) >= @max(8, @alignOf(usize)));
    }

    const Data = packed struct(u16) {
        len: Len,
        /// Low bits of the alignment.
        ///
        /// For non-extended headers, this is the entire alignment. The location of the previous
        /// header is directly before this allocation since footers in `Bucket` are gauraunteed to
        /// have at least 8-byte alignment.
        alignment: u2,
        /// Used only for bucket allocations.
        prev_extended: bool,

        const Len = enum(u13) {
            _,

            /// This footer is trailed (before the traces) by `Extended`.
            /// The high bits of the alignment are encoded as the offset from `extended_start`.
            ///
            /// This may be set even if `Extended` is not strictly necesary
            /// as a result of resizes and remaps.
            const extended_start: u13 = math.maxInt(u13) - ((@bitSizeOf(usize) - 1) >> 2);
        };
    };

    const Extended = struct {
        len: usize,
        container: Container,

        const Container = union {
            bucket_prev: ?*AllocFooter,
            large_entry: *Allocs.Entry,
        };

        comptime {
            // Exactly `usize` so this is directly after the regular footer
            // and so that traces start directly after `@sizeOf(@This())`.
            assert(@alignOf(@This()) == @alignOf(usize));
        }
    };

    const Modify = enum(u16) {
        // Random non-linear enum values to decrease the chance of undetected corruption.
        none = 0x2962,
        resized = 0x0030,
        remaped = 0x9068,
        freeing = 0x7f3d,
        freed = 0xb98b,
        _,

        fn setNone(m: *Modify) void {
            _ = @atomicRmw(Modify, m, .Xchg, .storedXor(.none, m), .monotonic);
        }

        fn opName(m: Modify) []const u8 {
            return switch (m) {
                .resized => "resize",
                .remaped => "remap",
                .freeing => "free",
                _, .none, .freed => unreachable,
            };
        }

        fn stateName(m: Modify) []const u8 {
            return switch (m) {
                .resized => "after resize",
                .remaped => "after remap",
                .freeing => "during free",
                .freed => "after free",
                _, .none => unreachable,
            };
        }

        fn storedXor(m: Modify, ptr: *Modify) Modify {
            const addr_hash: u16 = @truncate(std.hash.int(@intFromPtr(ptr)));
            return @enumFromInt(@intFromEnum(m) ^ addr_hash);
        }
    };

    fn isExtended(f: *AllocFooter) bool {
        return @intFromEnum(f.data.len) >= Data.Len.extended_start;
    }

    fn extended(f: *AllocFooter) *Extended {
        assert(f.isExtended());
        return @ptrFromInt(@intFromPtr(f) + @sizeOf(AllocFooter));
    }

    fn userMemory(f: *AllocFooter) []u8 {
        const memory_addr = @intFromPtr(f) - allocOffset(f.userLen());
        assert(f.userAlign().check(memory_addr));
        const memory_ptr: [*]u8 = @ptrFromInt(memory_addr);
        return memory_ptr[0..f.userLen()];
    }

    fn userLen(f: *AllocFooter) usize {
        const len_int = @intFromEnum(f.data.len);
        return if (len_int < Data.Len.extended_start) len_int else f.extended().len;
    }

    fn userAlign(f: *AllocFooter) Alignment {
        const high = (@intFromEnum(f.data.len) -| Data.Len.extended_start) << 2;
        return @enumFromInt(high | f.data.alignment);
    }

    fn bucketPrev(f: *AllocFooter, b: *Bucket, s: *SafeAllocator) ?*AllocFooter {
        if (f.isExtended()) return f.extended().container.bucket_prev;
        return b.allocFooterBefore(s, Bucket.fillAt(s, f.userMemory().ptr), f.data.prev_extended);
    }

    fn tracesPtr(f: *AllocFooter) [*]usize {
        const off_footer = @divExact(@sizeOf(AllocFooter), @sizeOf(usize));
        const off_extended = @as(usize, @divExact(@sizeOf(Extended), @sizeOf(usize))) *
            @intFromBool(f.isExtended());
        return @as([*]usize, @ptrCast(f))[off_footer + off_extended ..];
    }

    fn allocTrace(f: *AllocFooter, s: *SafeAllocator) []usize {
        return f.tracesPtr()[0..s.stack_trace_size];
    }

    fn freeTrace(f: *AllocFooter, s: *SafeAllocator) []usize {
        const trace_size = s.stack_trace_size;
        return f.tracesPtr()[trace_size..][0..trace_size];
    }

    fn actualChecksum(f: *AllocFooter, s: *SafeAllocator) u32 {
        if (f.isExtended()) {
            const len = f.extended().len;
            const addr: usize = if (s.isLarge(len, f.userAlign()))
                @intFromPtr(f.extended().container.large_entry)
            else
                @intFromPtr(f.extended().container.bucket_prev);

            const len_bytes: [@sizeOf(usize)]u8 = @bitCast(len);
            const container: [@sizeOf(usize)]u8 = @bitCast(addr);
            const regular_bytes: [2]u8 = @bitCast(f.data);
            const data_bytes = len_bytes ++ container ++ regular_bytes;

            return @truncate(std.hash.Wyhash.hash(@truncate(@intFromPtr(f)), &data_bytes));
        }
        return @truncate(std.hash.int(@as(u16, @bitCast(f.data)) ^ @intFromPtr(f)));
    }

    fn allocOffset(len: usize) usize {
        return Alignment.of(AllocFooter).forward(len);
    }

    fn allocAlign(a: Alignment) Alignment {
        return a.max(.of(AllocFooter));
    }

    /// Assumes the footer is in a bucket allocation; all
    /// large allocations require an extended header.
    fn requiresExtended(len: usize, alignment: Alignment) bool {
        return len >= Data.Len.extended_start or @intFromEnum(alignment) > math.maxInt(u2);
    }

    fn lenBucket(s: *SafeAllocator, is_extended: bool) usize {
        return Alignment.forward(.@"8", @sizeOf(AllocFooter) +
            @as(usize, @sizeOf(Extended)) * @intFromBool(is_extended) +
            s.stack_trace_size * @sizeOf(usize) * 2);
    }

    fn lenLarge(s: *SafeAllocator) usize {
        return @sizeOf(AllocFooter) + @sizeOf(Extended) + s.stack_trace_size * @sizeOf(usize);
    }

    fn allocLenBucket(s: *SafeAllocator, len: usize, is_extended: bool) usize {
        return allocOffset(len) + lenBucket(s, is_extended);
    }

    fn allocLenLarge(s: *SafeAllocator, len: usize) usize {
        return allocOffset(len) + lenLarge(s);
    }

    fn allocOffsetOrOom(len: usize) error{OutOfMemory}!usize {
        return alignForwardOrOom(.of(AllocFooter), len);
    }

    fn allocLenBucketOrOom(
        s: *SafeAllocator,
        len: usize,
        is_extended: bool,
    ) error{OutOfMemory}!usize {
        return addOrOom(try allocOffsetOrOom(len), lenBucket(s, is_extended));
    }

    fn of(user_memory: []u8) *AllocFooter {
        // Avoid panicing now if `memory.ptr` is not correctly aligned since a more
        // useful panic will be provided later by a mismatch or invalid footer.
        const aligned_start = Alignment.backward(.of(AllocFooter), @intFromPtr(user_memory.ptr));
        return @ptrFromInt(aligned_start + allocOffset(user_memory.len));
    }

    fn startModify(f: *AllocFooter, m: Modify, s: *SafeAllocator, mem_fmt: FormatMemory) void {
        const prev = @atomicRmw(
            Modify,
            &f.modify,
            .Xchg,
            .storedXor(m, &f.modify),
            .monotonic,
        ).storedXor(&f.modify);

        if (prev != .none) {
            @branchHint(.cold);
            const op_name = m.opName();
            switch (prev) {
                .none => unreachable,
                .resized, .remaped => panic(
                    \\{s} {s} of {f}
                    \\alloc: {f}
                    \\{s}:
                    // (panic stack trace)
                , .{
                    op_name,
                    prev.stateName(),
                    mem_fmt,
                    // The stack trace may have been overwritten, but at least give it a try
                    formatStackTrace(f.allocTrace(s)),
                    op_name,
                }),
                .freeing, .freed => {
                    if (prev == .freeing) {
                        // Wait for trace to become available
                        const complete: Modify = .storedXor(.freed, &f.modify);
                        while (@atomicLoad(Modify, &f.modify, .monotonic) != complete) {}
                        const b: *Bucket = .of(s, @ptrCast(f));
                        b.alloc_count.fenceAcqRel();
                    }
                    if (m == .freeing) {
                        panic(
                            \\double free of {f}
                            \\alloc: {f}
                            \\first free: {f}
                            \\second free:
                            // (panic stack trace)
                        , .{
                            mem_fmt,
                            formatStackTrace(f.allocTrace(s)),
                            formatStackTrace(f.freeTrace(s)),
                        });
                    } else {
                        panic(
                            \\{s} {s} of {f}
                            \\alloc: {f}
                            \\free: {f}
                            \\{s}:
                            // (panic stack trace)
                        , .{
                            op_name,
                            prev.stateName(),
                            mem_fmt,
                            formatStackTrace(f.allocTrace(s)),
                            formatStackTrace(f.freeTrace(s)),
                            op_name,
                        });
                    }
                },
                _ => panic(
                    "{s} of invalid memory {f} or corrupted metadata",
                    .{ m.opName(), mem_fmt },
                ),
            }
            comptime unreachable;
        }

        const expected_checksum = f.actualChecksum(s);
        if (f.checksum ^ s.canary != expected_checksum) {
            @branchHint(.cold);
            const other_canary = f.checksum ^ expected_checksum;
            panic(
                "{s} of invalid memory {f}, corrupted metadata, or foreign allocation from canary 0x{x}",
                .{ m.opName(), mem_fmt, other_canary },
            );
        }

        if (f.userLen() != mem_fmt.memory.len or f.userAlign() != mem_fmt.alignment) {
            const op_name = m.opName();
            panic(
                \\{s} of {f} mismatches allocation of {f}
                \\alloc: {f}
                \\{s}:
                // (panic stack trace)
            , .{ op_name, mem_fmt, FormatMemory{
                .memory = f.userMemory(),
                .alignment = f.userAlign(),
            }, formatStackTrace(f.allocTrace(s)), op_name });
        }
    }

    /// It is the caller's responsibility to `.acquire` fence the respective `Bucket.alloc_count`.
    fn populate(
        memory: []align(@alignOf(AllocFooter)) u8,
        len: usize,
        alignment: Alignment,
        ra: usize,
        /// `true` for large allocations
        is_extended: bool,
        /// `false` for large allocations
        prev_extended: bool,
        container: Extended.Container,
        s: *SafeAllocator,
    ) *AllocFooter {
        const footer: *AllocFooter = @ptrCast(@alignCast(memory[allocOffset(len)..].ptr));

        if (!is_extended) {
            footer.data = .{
                .len = @enumFromInt(len),
                .alignment = @intCast(@intFromEnum(alignment)),
                .prev_extended = prev_extended,
            };
            assert(!footer.isExtended());
        } else {
            footer.data = .{
                .len = @enumFromInt(Data.Len.extended_start + (@intFromEnum(alignment) >> 2)),
                .alignment = @truncate(@intFromEnum(alignment)),
                .prev_extended = prev_extended,
            };
            assert(footer.isExtended());
            footer.extended().* = .{
                .len = len,
                .container = container,
            };
        }

        captureStackTrace(footer.allocTrace(s), ra);
        footer.checksum = footer.actualChecksum(s) ^ s.canary;
        footer.modify.setNone();

        return footer;
    }
};

pub fn init(
    /// Must be thread-safe for this allocator to be thread-safe
    backing: mem.Allocator,
    options: Options,
) SafeAllocator {
    assert(options.block_size_log2 >= 8);
    assert(options.bucket_size_log2 >= 8);

    const allocs_entry_count = (@as(usize, 1) << options.block_size_log2) / @sizeOf(usize);
    return .{
        .backing = backing,
        .threads = @splat(.{
            .mutex = .unlocked,
            .fill_bucket = null,
            .free_entry = null,
            .allocs_next = allocs_entry_count,
            .allocs_first = null,
        }),

        .bucket_size_log2 = options.bucket_size_log2,
        .block_size_log2 = options.block_size_log2,
        .stack_trace_size = options.stack_trace_frames +
            @intFromBool(options.stack_trace_frames != 0),
        .allocs_entry_count = allocs_entry_count,
        .large_alloc_threshold = (@as(usize, 1) << options.bucket_size_log2) * 3 / 4,

        .canary = options.canary,
        .check_write_after_free = options.check_write_after_free,
    };
}

/// Returns the number of leaks
pub fn deinit(s: *SafeAllocator) usize {
    return s.deinitLog(true);
}

/// Same as `deinit`, expect if `log` is `false`, it will not log leaks.
pub fn deinitLog(s: *SafeAllocator, log: bool) usize {
    var leaks: usize = 0;
    const thread_count = @atomicRmw(usize, &n_threads, .Or, 0, .monotonic);
    for (s.threads[0..@max(1, thread_count)]) |*t| {
        assert(t.mutex == .unlocked); // use of allocator during `deinit`

        var maybe_allocs = t.allocs_first;
        var n_entries = t.allocs_next;
        while (maybe_allocs) |allocs| {
            for (allocs.entries(s)[0..n_entries]) |*ent| {
                switch (ent.kind) {
                    .free => {
                        @branchHint(.likely);
                    },
                    .bucket => leaks += s.deinitLeakedBucket(ent.toBucket(), log),
                    .large_alloc => {
                        leaks += 1;
                        s.deinitLargeAlloc(ent.toLargeAlloc(), log);
                    },
                }
            }
            maybe_allocs = allocs.next;
            n_entries = s.allocs_entry_count;
            s.backing.rawFree(@ptrCast(allocs.usizes(s)), .of(usize), 0);
        }
    }
    return leaks;
}

/// Returns the true count of leaks
fn deinitLeakedBucket(s: *SafeAllocator, b: *Bucket, log: bool) usize {
    var leaks: usize = 0;

    const expected = @atomicLoad(Bucket.AllocCount, &b.alloc_count, .acquire);
    if (expected.n == 0) assert(expected.filling);

    var footer = b.lastAlloc(s, b.fill).?;
    while (true) {
        const modify = @atomicRmw(
            AllocFooter.Modify,
            &footer.modify,
            .Xchg,
            undefined,
            .monotonic,
        ).storedXor(&footer.modify);

        const bad_modify = modify != .none and modify != .freed;
        if (bad_modify or footer.actualChecksum(s) != footer.checksum ^ s.canary) {
            panic("corrupted footer metadata in bucket at *{x}", .{@intFromPtr(&footer)});
        }

        switch (modify) {
            .none => {
                leaks += 1;
                if (log) scoped_log.err("leaked {f} allocated at: {f}", .{ FormatMemory{
                    .memory = footer.userMemory(),
                    .alignment = footer.userAlign(),
                }, formatStackTrace(footer.allocTrace(s)) });
            },
            .freed => s.checkFreed(footer),
            else => unreachable,
        }

        footer = footer.bucketPrev(b, s) orelse break;
    }
    s.backing.rawFree(b.bytes(s), @enumFromInt(s.bucket_size_log2), 0);

    assert(leaks == expected.n);
    return leaks;
}

fn deinitLargeAlloc(s: *SafeAllocator, footer: *AllocFooter, log: bool) void {
    const modify = footer.modify.storedXor(&footer.modify);
    if (modify != .none or footer.checksum ^ s.canary != footer.actualChecksum(s)) {
        panic("corrupted footer metadata at *{x}", .{@intFromPtr(&footer)});
    }

    const memory = footer.userMemory();
    if (log) scoped_log.err("leaked {f} allocated at {f}", .{ FormatMemory{
        .memory = memory,
        .alignment = footer.userAlign(),
    }, formatStackTrace(footer.allocTrace(s)) });

    s.backing.rawFree(
        memory.ptr[0..AllocFooter.allocLenLarge(s, memory.len)],
        AllocFooter.allocAlign(footer.userAlign()),
        0,
    );
}

/// Returned allocator is thread-safe
pub fn allocator(s: *SafeAllocator) mem.Allocator {
    return .{ .ptr = s, .vtable = &vtable };
}

fn acquireThread(s: *SafeAllocator) *Thread {
    while (true) {
        const t = &s.threads[thread_index];
        if (t.mutex.tryLock()) {
            @branchHint(.likely);
            return t;
        }

        var max = @atomicLoad(usize, &n_threads, .unordered);
        if (max == 0) {
            @branchHint(.unlikely);
            max = @min(std.Thread.getCpuCount() catch s.threads.len, s.threads.len);
            max = @cmpxchgStrong(usize, &n_threads, 0, max, .monotonic, .monotonic) orelse max;
        }

        thread_index += 1;
        // thread_index may be greater than max if the zero is returned by getCpuCount
        thread_index *= @intFromBool(thread_index < max);
    }
}

fn alignForwardOrOom(a: Alignment, addr: usize) error{OutOfMemory}!usize {
    const x = a.toByteUnits() - 1;
    return try addOrOom(addr, x) & ~x;
}

fn addOrOom(a: usize, b: usize) error{OutOfMemory}!usize {
    return math.add(usize, a, b) catch error.OutOfMemory;
}

fn isLarge(s: *SafeAllocator, len: usize, alignment: Alignment) bool {
    const max_align_waste = alignment.toByteUnits() - 1;
    const max_use = max_align_waste + AllocFooter.allocLenBucket(s, len, true);
    return max_use >= s.large_alloc_threshold;
}

fn isLargeOrOom(s: *SafeAllocator, len: usize, alignment: Alignment) error{OutOfMemory}!bool {
    const max_align_waste = alignment.toByteUnits() - 1;
    const max_use = try addOrOom(max_align_waste, try AllocFooter.allocLenBucketOrOom(s, len, true));
    return max_use >= s.large_alloc_threshold;
}

fn newAllocEntry(s: *SafeAllocator, t: *Thread, ra: usize) error{OutOfMemory}!*Allocs.Entry {
    if (t.free_entry) |ent| {
        @branchHint(.likely);
        t.free_entry = ent.toFree();
        return ent;
    }

    if (s.allocs_entry_count - t.allocs_next != 0) {
        @branchHint(.likely);
        const ent = &t.allocs_first.?.entries(s)[t.allocs_next];
        t.allocs_next += 1;
        return ent;
    }

    const new_segment: *Allocs = @ptrCast(@alignCast(s.backing.rawAlloc(
        (1 + s.allocs_entry_count) * @sizeOf(usize),
        .of(usize),
        ra,
    ) orelse return error.OutOfMemory));
    new_segment.next = t.allocs_first;
    t.allocs_first = new_segment;
    t.allocs_next = 1;
    return &new_segment.entries(s)[0];
}

fn freeAllocEntry(t: *Thread, ent: *Allocs.Entry) void {
    ent.* = .fromFree(t.free_entry);
    t.free_entry = ent;
}

fn overwriteFreed(s: *SafeAllocator, bytes: []u8) void {
    if (!s.check_write_after_free) return;
    // 0x55 is used so that undefined writes of 0xaa are still caught. Another option would be a
    // stream of random bytes seeded by the address, however that makes debugging reads after frees
    // more difficult and has a performance penalty and so is not worth catching slightly more
    // writes after frees.
    @memset(bytes, 0x55);
}

/// Returns the first address of a write after free
fn checkFreed(s: *SafeAllocator, footer: *AllocFooter) void {
    if (!s.check_write_after_free) return;
    const memory = footer.userMemory();
    for (memory) |*b| if (b.* != 0x55) {
        panic(
            \\write after free at *{x}
            \\original alloc of {f}: {f}
            \\free: {f}
            \\stack trace:
            // (panic stack trace)
        , .{
            @intFromPtr(b),
            FormatMemory{ .memory = memory, .alignment = footer.userAlign() },
            formatStackTrace(footer.allocTrace(s)),
            formatStackTrace(footer.freeTrace(s)),
        });
    };
}

const FormatMemory = struct {
    memory: []const u8,
    alignment: Alignment,

    pub fn format(m: FormatMemory, w: *std.Io.Writer) std.Io.Writer.Error!void {
        return w.print(
            "[addr: {x}, len: {} (0x{x}) align: {}]",
            .{ @intFromPtr(m.memory.ptr), m.memory.len, m.memory.len, m.alignment.toByteUnits() },
        );
    }
};

/// The first element stores the length of the stack trace including skipped frames.
/// The remaining elements store the return addresses.
fn captureStackTrace(trace_buf: []usize, ra: usize) void {
    if (trace_buf.len == 0) return;

    if (ra == 0) { // No return address provided
        @branchHint(.unlikely);
        trace_buf[0] = 0;
        return;
    }

    const t = std.debug.captureCurrentStackTrace(.{ .first_address = ra }, trace_buf[1..]);
    const skipped = @intFromEnum(t.skipped) *
        @intFromBool(t.return_addresses.len == trace_buf[1..].len);
    trace_buf[0] = t.return_addresses.len +| skipped;
}

fn formatStackTrace(trace_buf: []usize) std.debug.FormatStackTrace {
    return .{
        .stack_trace = if (trace_buf.len != 0) trace: {
            const frames = trace_buf[0];
            const addrs = trace_buf[1..];
            break :trace .{
                .return_addresses = addrs[0..@min(frames, addrs.len)],
                .skipped = switch (frames) {
                    else => @enumFromInt(frames -| addrs.len),
                    0, math.maxInt(usize) => .unknown,
                },
            };
        } else .{
            .return_addresses = &.{},
            .skipped = .unknown,
        },
        .terminal_mode = std.log.terminalMode(),
    };
}

/// If this fails, future allocations to the bucket are illegal
fn allocBucket(
    s: *SafeAllocator,
    t: *Thread,
    b: *Bucket,
    len: usize,
    alignment: Alignment,
    ra: usize,
) ?[*]u8 {
    const fill = &b.fill;
    const is_extended = AllocFooter.requiresExtended(len, alignment);
    const alloc_len: u32 = @intCast(AllocFooter.allocLenBucket(s, len, is_extended));
    const alloc_align = AllocFooter.allocAlign(alignment);

    var prev_fill = @atomicLoad(Bucket.Fill, fill, .monotonic);
    var start: u32 = undefined;
    var end: u32 = undefined;
    while (true) {
        start = @intCast(alloc_align.forward(prev_fill.at));
        end = start + alloc_len;

        if (end > s.bucketSize()) {
            @branchHint(.unlikely);

            const prev_count = @atomicRmw(
                Bucket.AllocCount,
                &b.alloc_count,
                .Sub,
                .{ .filling = true, .n = 0 },
                .acq_rel,
            );
            assert(prev_count.filling);

            if (prev_count.n == 0) {
                @branchHint(.unlikely);
                freeAllocEntry(t, b.entry);
                b.check(s);
                s.backing.rawFree(b.bytes(s), @enumFromInt(s.bucket_size_log2), ra);
            }

            return null;
        }

        prev_fill = @cmpxchgWeak(
            Bucket.Fill,
            fill,
            prev_fill,
            .{ .at = @intCast(end), .last_is_extended = is_extended },
            .monotonic,
            .monotonic,
        ) orelse {
            @branchHint(.likely);
            break;
        };
        // b.fill was changed during a resize (or a sporadic cmpxchgWeak failure)
    }

    const memory = b.bytes(s)[start..end];
    _ = AllocFooter.populate(
        @alignCast(memory),
        len,
        alignment,
        ra,
        is_extended,
        prev_fill.last_is_extended,
        .{ .bucket_prev = b.lastAlloc(s, prev_fill) },
        s,
    );

    assert(@atomicRmw(
        Bucket.AllocCount,
        &b.alloc_count,
        .Add,
        .{ .filling = false, .n = 1 },
        .acq_rel,
    ).filling);

    return memory.ptr;
}

fn growingResizeBucket(
    s: *SafeAllocator,
    f: *AllocFooter,
    memory: []const u8,
    alignment: Alignment,
    new_len: usize,
    ra: usize,
) bool {
    assert(new_len >= memory.len);
    return s.advanceBucketAlloc(f, Bucket.fillAt(s, memory.ptr), false, alignment, new_len, ra);
}

fn advanceBucketAlloc(
    s: *SafeAllocator,
    old: *AllocFooter,
    new_start: u32,
    start_moved: bool,
    alignment: Alignment,
    new_len: usize,
    ra: usize,
) bool {
    assert(AllocFooter.allocAlign(alignment).check(new_start));
    const b: *Bucket = .of(s, @ptrCast(old));

    const old_is_extended = old.isExtended();
    const old_footer_len = AllocFooter.lenBucket(s, old_is_extended);
    const old_fill: u32 = @intCast(Bucket.fillAt(s, @ptrCast(old)) + old_footer_len);

    const new_is_extended = old_is_extended or start_moved or
        AllocFooter.requiresExtended(new_len, alignment);
    const new_footer_len = AllocFooter.lenBucket(s, new_is_extended);
    const new_fill: u32 = @intCast(new_start + AllocFooter.allocOffset(new_len) + new_footer_len);

    assert(old_fill <= new_fill);
    if (new_fill > s.bucketSize()) {
        return false;
    }

    if (old_fill == new_fill or @cmpxchgStrong(
        Bucket.Fill,
        &b.fill,
        .{ .last_is_extended = old_is_extended, .at = @intCast(old_fill) },
        .{ .last_is_extended = new_is_extended, .at = @intCast(new_fill) },
        .monotonic,
        .monotonic,
    ) != null) {
        return false;
    }

    _ = AllocFooter.populate(
        @alignCast(b.bytes(s)[new_start..new_fill]),
        new_len,
        alignment,
        ra,
        new_is_extended,
        old.data.prev_extended,
        .{ .bucket_prev = old.bucketPrev(b, s) },
        s,
    );
    b.alloc_count.fenceAcqRel();
    return true;
}

const vtable: mem.Allocator.VTable = .{
    .alloc = alloc,
    .free = free,
    .resize = resize,
    .remap = remap,
};

fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, ra: usize) ?[*]u8 {
    assert(len != 0);

    const s: *SafeAllocator = @ptrCast(@alignCast(ctx));
    const t = s.acquireThread();
    defer t.mutex.unlock();

    if (s.isLargeOrOom(len, alignment) catch return null) {
        @branchHint(.unlikely);

        const entry = s.newAllocEntry(t, ra) catch return null;
        const alloc_len = AllocFooter.allocLenLarge(s, len);
        const alloc_align = AllocFooter.allocAlign(alignment);
        const alloc_ptr = s.backing.rawAlloc(alloc_len, alloc_align, ra) orelse {
            freeAllocEntry(t, entry);
            return null;
        };

        const footer = AllocFooter.populate(
            @alignCast(alloc_ptr[0..alloc_len]),
            len,
            alignment,
            ra,
            true,
            false,
            .{ .large_entry = entry },
            s,
        );
        entry.* = .fromLargeAlloc(footer);

        return alloc_ptr;
    }

    if (t.fill_bucket) |bucket| {
        @branchHint(.likely);
        if (s.allocBucket(t, bucket, len, alignment, ra)) |ptr| {
            @branchHint(.likely);
            return ptr;
        }
    }
    t.fill_bucket = null; // In case of OOM below, this bucket will still be unusable for future
    // allocations.

    const entry = s.newAllocEntry(t, ra) catch return null;
    const bucket: *Bucket = @ptrCast(@alignCast(s.backing.rawAlloc(
        s.bucketSize(),
        @enumFromInt(s.bucket_size_log2),
        ra,
    ) orelse {
        freeAllocEntry(t, entry);
        return null;
    }));
    bucket.* = .{
        .entry = entry,
        // No atomic stores necessary because this thread is the
        // first to atomically update these below in allocBucket.
        .alloc_count = .{ .filling = true, .n = 0 },
        .fill = .{ .at = @sizeOf(Bucket), .last_is_extended = false },
    };
    entry.* = .fromBucket(bucket);

    t.fill_bucket = bucket;
    return s.allocBucket(t, bucket, len, alignment, ra);
}

fn free(ctx: *anyopaque, memory: []u8, alignment: Alignment, ra: usize) void {
    const s: *SafeAllocator = @ptrCast(@alignCast(ctx));
    const f: *AllocFooter = .of(memory);
    f.startModify(.freeing, s, .{ .memory = memory, .alignment = alignment });

    if (s.isLarge(memory.len, alignment)) {
        @branchHint(.unlikely);

        const t = s.acquireThread();
        freeAllocEntry(t, f.extended().container.large_entry);
        t.mutex.unlock();
        s.backing.rawFree(
            memory.ptr[0..AllocFooter.allocLenLarge(s, memory.len)],
            AllocFooter.allocAlign(alignment),
            ra,
        );
        return;
    }

    const b: *Bucket = .of(s, memory.ptr);
    s.overwriteFreed(memory);
    captureStackTrace(f.freeTrace(s), ra);

    // Fence the alloc count before setting `f.modify` to `.freed`.
    // This way, if another thread is waiting for the trace to become
    // available, it will not be racing with us to see this `.release`.
    //
    // The below alloc count update can not be moved up here instead
    // since that would allow another thread to see the `.freeing` state.
    b.alloc_count.fenceAcqRel();

    // If this result is different than .freeing, then some other thread
    // is in the process of panicing. So, just ignore it. (This is also
    // the reasoning for several other places.)
    _ = @atomicRmw(
        AllocFooter.Modify,
        &f.modify,
        .Xchg,
        .storedXor(.freed, &f.modify),
        .monotonic,
    );

    const prev_count = @atomicRmw(
        Bucket.AllocCount,
        &b.alloc_count,
        .Sub,
        .{ .filling = false, .n = 1 },
        .acq_rel,
    );

    if (prev_count.n - 1 == 0 and !prev_count.filling) {
        @branchHint(.unlikely);
        const t = s.acquireThread();
        freeAllocEntry(t, b.entry);
        t.mutex.unlock();
        b.check(s);
        s.backing.rawFree(b.bytes(s), @enumFromInt(s.bucket_size_log2), ra);
    }
}

fn resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ra: usize) bool {
    assert(new_len != 0);

    const s: *SafeAllocator = @ptrCast(@alignCast(ctx));
    const f: *AllocFooter = .of(memory);
    f.startModify(.resized, s, .{ .memory = memory, .alignment = alignment });

    // Check that the allocation is not moving between a bucket and large allocation. This is
    // done after the above so that it is still checked that valid memory is passed and there
    // is no double modify.
    const from_large_alloc = s.isLarge(memory.len, alignment);
    const to_large_alloc = s.isLargeOrOom(new_len, alignment) catch {
        f.modify.setNone();
        return false;
    };
    if (from_large_alloc != to_large_alloc) {
        @branchHint(.unlikely);
        f.modify.setNone();
        return false;
    }

    if (from_large_alloc) {
        @branchHint(.unlikely);

        const entry = f.extended().container.large_entry;
        const new_alloc_len = AllocFooter.allocLenLarge(s, new_len);
        if (!s.backing.rawResize(
            memory.ptr[0..AllocFooter.allocLenLarge(s, memory.len)],
            AllocFooter.allocAlign(alignment),
            new_alloc_len,
            ra,
        )) {
            f.modify.setNone();
            return false;
        }

        const new_footer = AllocFooter.populate(
            @alignCast(memory.ptr[0..new_alloc_len]),
            new_len,
            alignment,
            ra,
            true,
            false,
            .{ .large_entry = entry },
            s,
        );
        assert(entry.kind == .large_alloc);
        entry.* = .fromLargeAlloc(new_footer);
        return true;
    }

    if (new_len < memory.len) {
        // Resize shrinks are disallowed in all cases since the linked list would be broken. Even
        // if this footer is the final one, the fill value would need decreased which would allow
        // memory to be reused.
        f.modify.setNone();
        return false;
    }

    if (s.growingResizeBucket(f, memory, alignment, new_len, ra)) {
        @branchHint(.likely);
        return true;
    } else {
        f.modify.setNone();
        return false;
    }
}

fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ra: usize) ?[*]u8 {
    assert(new_len != 0);

    const s: *SafeAllocator = @ptrCast(@alignCast(ctx));
    const f: *AllocFooter = .of(memory);
    f.startModify(.remaped, s, .{ .memory = memory, .alignment = alignment });

    // Check that the allocation is not moving between a bucket and large allocation. This is
    // done after the above so that it is still checked that valid memory is passed and there
    // is no double modify.
    const from_large_alloc = s.isLarge(memory.len, alignment);
    const to_large_alloc = s.isLargeOrOom(new_len, alignment) catch {
        f.modify.setNone();
        return null;
    };
    if (from_large_alloc != to_large_alloc) {
        @branchHint(.unlikely);
        f.modify.setNone();
        return null;
    }

    if (from_large_alloc) {
        @branchHint(.unlikely);

        const entry = f.extended().container.large_entry;
        const new_alloc_len = AllocFooter.allocLenLarge(s, new_len);
        const new_memory = s.backing.rawRemap(
            memory.ptr[0..AllocFooter.allocLenLarge(s, memory.len)],
            AllocFooter.allocAlign(alignment),
            new_alloc_len,
            ra,
        ) orelse {
            f.modify.setNone();
            return null;
        };

        const new_footer = AllocFooter.populate(
            @alignCast(new_memory[0..new_alloc_len]),
            new_len,
            alignment,
            ra,
            true,
            false,
            .{ .large_entry = entry },
            s,
        );
        assert(entry.kind == .large_alloc);
        entry.* = .fromLargeAlloc(new_footer);
        return new_memory;
    }

    if (new_len < memory.len) {
        // Move the allocation forward to avoid bucket reuse

        const fixed_start = Bucket.fillAt(s, @ptrCast(f)) - AllocFooter.allocOffset(new_len);
        const moved_start = alignment.forward(fixed_start);
        if (moved_start != fixed_start or !f.isExtended()) {
            @branchHint(.unlikely);
            // For `moved_start != fixed_start`: the footer needs moved forward as well to
            // maintain the correct allocOffset.
            //
            // For `!f.isExtended()`: since the memory will no longer be directly after the
            // previous footer, the footer needs promoted to an extended one to encode the
            // location of the previous footer.
            if (!s.advanceBucketAlloc(f, @intCast(moved_start), true, alignment, new_len, ra)) {
                @branchHint(.unlikely);
                f.modify.setNone();
                return null;
            }
            const new_memory = Bucket.bytes(.of(s, @ptrCast(f)), s)[moved_start..][0..new_len];
            @memmove(new_memory, memory[0..new_memory.len]);
            return new_memory.ptr;
        }

        // The footer can be modified in place
        const b: *Bucket = .of(s, @ptrCast(f));
        f.extended().len = new_len;
        f.checksum = f.actualChecksum(s) ^ s.canary;
        captureStackTrace(f.allocTrace(s), ra);

        f.modify.setNone();
        b.alloc_count.fenceAcqRel();

        const new_memory = f.userMemory();
        @memmove(new_memory, memory[0..new_memory.len]);
        return new_memory.ptr;
    }

    if (s.growingResizeBucket(f, memory, alignment, new_len, ra)) {
        @branchHint(.likely);
        return memory.ptr;
    } else {
        f.modify.setNone();
        return null;
    }
}

const Smith = std.testing.Smith;

/// Shared between single-threaded and multi-threaded fuzzing.
const fuzz_probs = struct {
    const alignment: []const Smith.Weight = &.{
        .rangeAtMost(Alignment, .@"1", .@"16", 32), // ~75%
        .rangeAtMost(Alignment, .@"16", @enumFromInt(@bitSizeOf(usize) - 1), 1),
        .value(Alignment, @enumFromInt(@bitSizeOf(usize) - 1), 32), // More likely overflow cases
    };

    const eos: []const Smith.Weight = &.{
        // Very high false weight so that expanding allocation tables, OOM cases,
        // and multi-threaded consumer-producer cases get tested thoroughly.
        .value(bool, false, 255),
        .value(bool, true, 1),
    };

    fn generateOptions(smith: *Smith) Options {
        @disableInstrumentation();

        const size_log2_weights: []const Smith.Weight = &.{
            .value(u5, 8, 1024), // 8x odds of below
            .rangeAtMost(u5, 8, 16, 16),
            .rangeAtMost(u5, 17, 31, 1), // 1/32 odds of above since these just OOM with the fixed buffer
        };
        return .{
            .stack_trace_frames = smith.valueWeighted(u16, &.{
                .value(u16, 0, 1 << 18), // 4x - stack traces have no tested properties except I.B.
                .rangeAtMost(u16, 0, math.maxInt(u16), 1),
            }),
            // If set, it is aimed to allocate much fewer bytes since freeing becomes O(n).
            // Without this, it is O(1) since mem.Allocator is bypassed so there is no memsets
            // of the data.
            .check_write_after_free = smith.valueWeighted(bool, &.{
                .value(bool, false, 31),
                .value(bool, false, 1),
            }),
            .canary = smith.value(u32),

            .block_size_log2 = smith.valueWeighted(u5, size_log2_weights),
            .bucket_size_log2 = smith.valueWeighted(u5, size_log2_weights),
        };
    }

    const Op = enum(u8) { alloc, free, resize, remap };
    fn generateOp(smith: *Smith, any_allocs: bool) Op {
        @disableInstrumentation();
        return if (any_allocs) smith.valueWeighted(Op, &.{
            .rangeAtMost(Op, .alloc, .free, 4),
            .rangeAtMost(Op, .resize, .remap, 1),
        }) else .alloc;
    }

    fn generateSplat(smith: *Smith) ?u8 {
        @disableInstrumentation();

        // Same rationale for `check_write_after_free`
        const n = smith.valueWeighted(u16, &.{
            .value(u16, 256, 256 * 31),
            .rangeAtMost(u16, 0, 255, 1),
        });
        return if (n == 256) null else @intCast(n);
    }

    fn generateLen(smith: *Smith, will_memset: bool) usize {
        @disableInstrumentation();

        // 1 << 24 indicates to generate an unweighted usize.
        // 1 << 25 indicates to provide a value relative to the maximum usize.
        const len = smith.valueWeightedWithHash(
            u32,
            if (!will_memset) comptime &.{
                // zig fmt: off
                .rangeLessThan(u32, 1      , 1 << 6 , 1 << 15), // 2^21 - 2^4 times below so 16x odds
                .rangeLessThan(u32, 1 <<  6, 1 << 17, 1      ), // 2^17 - 2^4 times below so 16x odds
                .value        (u32, 1 << 24,          1 << 12), // 2^12
                .value        (u32, 1 << 25,          1 << 12), // 2^12
                // zig fmt: on
            } else comptime &.{
                // zig fmt: off
                .rangeLessThan(u32, 1      , 1 <<  6, 1 << 17), // 2^23 - 2^6 times below so 64x odds
                .rangeLessThan(u32, 1 <<  6, 1 << 17, 1      ), // 2^17 - 2^6 times below so 64x odds
                .value        (u32, 1 << 24,          1 << 10), // 2^10
                .value        (u32, 1 << 25,          1 << 10), // 2^10
                // zig fmt: on
            },
            // Give the fuzzer different hashes when the weights used differ
            // so that it does not reuse values from other probabilities.
            if (!will_memset) 0x38a74424 else 0xec581ff0,
        );

        if (len == 1 << 24) return @max(1, smith.value(usize));
        if (len == 1 << 25) return @as(usize, math.maxInt(usize)) - smith.value(u16);
        return len;
    }

    fn checkSplat(splat: ?u8, bytes: []const u8) void {
        @disableInstrumentation();

        const byte = splat orelse return;
        for (bytes) |*b| if (b.* != byte) {
            panic("SafeAllocator corrupted allocation data at *{x}", .{@intFromPtr(b)});
        };
    }
};

test "fuzz single threaded" {
    // This single threaded fuzz test has the following advantages:
    // * Higher throughput and deterministic, which helps the fuzzer.
    // * Easier debugging of single-threaded reproducable bugs.
    const testing_buf = try std.testing.allocator.alloc(u8, 65536);
    defer std.testing.allocator.free(testing_buf);
    const backing_buf = try std.testing.allocator.alloc(u8, 1 << 17);
    defer std.testing.allocator.free(backing_buf);
    try std.testing.fuzz(FuzzSingleThreadedContext{
        .testing_buf = testing_buf,
        .backing_buf = backing_buf,
    }, fuzzSingleThreaded, .{});
}

const FuzzSingleThreadedContext = struct {
    testing_buf: []u8,
    backing_buf: []u8,
};

/// Guarantees memory will not be reused.
const FuzzSingleThreadedAllocator = struct {
    gpa: mem.Allocator,
    smith: *std.testing.Smith,

    buf: []u8,
    fill: usize,
    allocs: std.MultiArrayList(AllocInfo),

    const AllocInfo = struct {
        ptr: [*]u8,
        len: usize,
        alignment: Alignment,
    };

    fn allocator(f: *FuzzSingleThreadedAllocator) mem.Allocator {
        @disableInstrumentation();
        return .{ .ptr = f, .vtable = &.{
            .alloc = FuzzSingleThreadedAllocator.alloc,
            .free = FuzzSingleThreadedAllocator.free,
            .resize = FuzzSingleThreadedAllocator.resize,
            .remap = FuzzSingleThreadedAllocator.remap,
        } };
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, _: usize) ?[*]u8 {
        @disableInstrumentation();

        const f: *FuzzSingleThreadedAllocator = @ptrCast(@alignCast(ctx));
        f.allocs.ensureUnusedCapacity(f.gpa, 1) catch return null;

        const ptr = f.allocInner(len, alignment) orelse return null;
        f.allocs.appendAssumeCapacity(.{
            .ptr = ptr,
            .len = len,
            .alignment = alignment,
        });
        return ptr;
    }

    fn allocInner(f: *FuzzSingleThreadedAllocator, len: usize, alignment: Alignment) ?[*]u8 {
        @disableInstrumentation();

        const start_addr = alignment.forward(@intFromPtr(f.buf[f.fill..].ptr));
        const start = @as([*]u8, @ptrFromInt(start_addr)) - f.buf.ptr;
        if (start +| len > f.buf.len or f.smith.boolWeighted(31, 1)) return null;
        f.fill = start + len;
        return f.buf[start..][0..len].ptr;
    }

    fn allocIndex(f: *FuzzSingleThreadedAllocator, memory: []u8, alignment: Alignment) usize {
        @disableInstrumentation();

        const allocs_slice = f.allocs.slice();
        const i = mem.indexOfScalar([*]u8, allocs_slice.items(.ptr), memory.ptr) orelse panic(
            "invalid SafeAllocator free of {f}",
            .{FormatMemory{ .memory = memory, .alignment = alignment }},
        );
        const expected_len = allocs_slice.items(.len)[i];
        const expected_align = allocs_slice.items(.alignment)[i];
        if (memory.len != expected_len or allocs_slice.items(.alignment)[i] != expected_align) {
            panic("SafeAllocator free {f} mismatches alloc {f}", .{
                FormatMemory{ .memory = memory, .alignment = alignment },
                FormatMemory{ .memory = memory.ptr[0..expected_len], .alignment = expected_align },
            });
        }
        return i;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: Alignment, _: usize) void {
        @disableInstrumentation();

        const f: *FuzzSingleThreadedAllocator = @ptrCast(@alignCast(ctx));
        f.allocs.swapRemove(f.allocIndex(memory, alignment));
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, _: usize) bool {
        @disableInstrumentation();

        const f: *FuzzSingleThreadedAllocator = @ptrCast(@alignCast(ctx));
        const i = f.allocIndex(memory, alignment);

        const start = memory.ptr - f.buf.ptr;
        const old_end = start + memory.len;
        const new_end = start +| new_len;
        if (new_end > f.buf.len or f.smith.value(bool)) {
            return false;
        }

        if (new_len <= memory.len) {
            // The fill is not decreased so memory is not reused.
        } else if (f.fill == old_end) {
            f.fill = new_end;
        } else {
            return false;
        }
        f.allocs.items(.len)[i] = new_len;
        return true;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, _: usize) ?[*]u8 {
        @disableInstrumentation();

        const f: *FuzzSingleThreadedAllocator = @ptrCast(@alignCast(ctx));
        if (f.smith.value(bool)) {
            const resized = FuzzSingleThreadedAllocator.resize(
                ctx,
                memory,
                alignment,
                new_len,
                undefined,
            );
            return if (resized) memory.ptr else null;
        }

        const i = f.allocIndex(memory, alignment);
        if (f.smith.value(bool)) return null;

        const new_ptr = f.allocInner(new_len, alignment) orelse return null;
        const copy_len = @min(memory.len, new_len);
        @memcpy(new_ptr[0..copy_len], memory[0..copy_len]);

        f.allocs.set(i, .{
            .ptr = new_ptr,
            .len = new_len,
            .alignment = alignment,
        });
        return new_ptr;
    }
};

fn fuzzSingleThreaded(ctx: FuzzSingleThreadedContext, smith: *Smith) !void {
    @disableInstrumentation();

    var gpa_instance: std.heap.FixedBufferAllocator = .init(ctx.testing_buf);
    const gpa = gpa_instance.allocator();
    var backing_gpa_instance: FuzzSingleThreadedAllocator = .{
        .gpa = gpa,
        .smith = smith,

        .buf = ctx.backing_buf,
        .fill = 0,
        .allocs = .empty,
    };
    const backing_gpa = backing_gpa_instance.allocator();

    const options = fuzz_probs.generateOptions(smith);
    var s: SafeAllocator = .init(backing_gpa, options);
    const no_ra: usize = 0;

    var allocs: std.MultiArrayList(struct {
        memory: []u8,
        alignment: Alignment,
        splat: ?u8,
    }) = .empty;
    var used_memory: std.ArrayList(struct {
        start: usize,
        end: usize,
    }) = .empty;

    while (!smith.eosWeighted(fuzz_probs.eos)) {
        const op = fuzz_probs.generateOp(smith, allocs.len != 0);
        const new_mem: []const u8, const old_mem: ?[]const u8 = new_alloc: switch (op) {
            .alloc => {
                used_memory.ensureUnusedCapacity(gpa, 1) catch break;
                allocs.ensureUnusedCapacity(gpa, 1) catch break;

                const splat = fuzz_probs.generateSplat(smith);
                const will_memset = options.check_write_after_free or splat != null;
                const len = fuzz_probs.generateLen(smith, will_memset);
                const alignment = smith.valueWeighted(Alignment, fuzz_probs.alignment);

                const ptr = alloc(&s, len, alignment, no_ra) orelse continue;
                if (!alignment.check(@intFromPtr(ptr))) @panic("bad returned alignment");
                const memory = ptr[0..len];
                if (splat) |b| @memset(memory, b);

                allocs.appendAssumeCapacity(.{
                    .memory = memory,
                    .alignment = alignment,
                    .splat = splat,
                });
                break :new_alloc .{ memory, null };
            },
            .free => {
                const i = smith.valueRangeLessThan(u32, 0, @intCast(allocs.len));
                const alloc_info = allocs.get(i);
                allocs.swapRemove(i);

                fuzz_probs.checkSplat(alloc_info.splat, alloc_info.memory);
                free(&s, alloc_info.memory, alloc_info.alignment, no_ra);
                continue;
            },
            .resize => {
                used_memory.ensureUnusedCapacity(gpa, 1) catch break;
                const i = smith.valueRangeLessThan(u32, 0, @intCast(allocs.len));
                const allocs_slice = allocs.slice();

                const prev_alloc = allocs_slice.get(i);
                const old_len = prev_alloc.memory.len;

                const alloc_memory = &allocs_slice.items(.memory)[i];
                const splat = prev_alloc.splat;
                const will_memset = options.check_write_after_free or splat != null;

                const new_len = fuzz_probs.generateLen(smith, will_memset);
                if (!resize(&s, prev_alloc.memory, prev_alloc.alignment, new_len, no_ra)) {
                    fuzz_probs.checkSplat(prev_alloc.splat, prev_alloc.memory);
                    continue;
                }
                alloc_memory.len = new_len;

                fuzz_probs.checkSplat(prev_alloc.splat, alloc_memory.*[0..@min(old_len, new_len)]);
                if (splat) |b| @memset(alloc_memory.*[@min(old_len, new_len)..], b);

                break :new_alloc .{ alloc_memory.*, prev_alloc.memory };
            },
            .remap => {
                used_memory.ensureUnusedCapacity(gpa, 1) catch break;
                const i = smith.valueRangeLessThan(u32, 0, @intCast(allocs.len));
                const allocs_slice = allocs.slice();

                const prev_alloc = allocs_slice.get(i);
                const old_len = prev_alloc.memory.len;

                const alloc_memory = &allocs_slice.items(.memory)[i];
                const alignment = prev_alloc.alignment;
                const splat = prev_alloc.splat;
                const will_memset = options.check_write_after_free or splat != null;

                const new_len = fuzz_probs.generateLen(smith, will_memset);
                const new_ptr = remap(
                    &s,
                    prev_alloc.memory,
                    prev_alloc.alignment,
                    new_len,
                    no_ra,
                ) orelse {
                    fuzz_probs.checkSplat(prev_alloc.splat, prev_alloc.memory);
                    continue;
                };
                alloc_memory.* = new_ptr[0..new_len];

                if (!alignment.check(@intFromPtr(new_ptr))) @panic("bad returned alignment");
                fuzz_probs.checkSplat(prev_alloc.splat, alloc_memory.*[0..@min(old_len, new_len)]);
                if (splat) |b| @memset(alloc_memory.*[@min(old_len, new_len)..], b);

                break :new_alloc .{ alloc_memory.*, prev_alloc.memory };
            },
        };

        const new_start = @intFromPtr(new_mem.ptr);
        const new_end = new_start + new_mem.len;
        const old_start = if (old_mem) |old| @intFromPtr(old.ptr) else 0;
        const old_end = new_start + if (old_mem) |old| old.len else 0;
        for (used_memory.items) |used| {
            if (old_start <= used.end and used.start <= old_end) {
                continue;
            }
            if (new_start <= used.end and used.start <= new_end) {
                panic(
                    "memory reuse between [addr: {x}, len: {}] and new [addr: {x}, len: {}]",
                    .{ used.start, used.end, new_start, new_end },
                );
            }
        }
        used_memory.appendAssumeCapacity(.{ .start = new_start, .end = new_end });
    }

    try std.testing.expectEqual(allocs.len, s.deinitLog(false));
    const leaks_slice = backing_gpa_instance.allocs.slice();
    for (0..leaks_slice.len) |i| {
        const leak = leaks_slice.get(i);
        std.log.err("SafeAllocator leaked {f}", .{FormatMemory{
            .memory = leak.ptr[0..leak.len],
            .alignment = leak.alignment,
        }});
    }
    try std.testing.expectEqual(0, leaks_slice.len); // no leaks
}

test "fuzz multi threaded" {
    if (@import("builtin").single_threaded) return error.SkipZigTest;

    const testing_buf = try std.testing.allocator.alloc(u8, 65536);
    defer std.testing.allocator.free(testing_buf);
    const backing_buf = try std.testing.allocator.alloc(u8, 1 << 17);
    defer std.testing.allocator.free(backing_buf);

    // `std.testing` instances are overwritten during `std.testing.fuzz` so
    // it is necessary to use our own io and gpa instances.
    var threaded_io: std.Io.Threaded = .init(std.heap.smp_allocator, .{});
    defer threaded_io.deinit();
    const io = threaded_io.io();

    var ops: FuzzMultiThreadedContext.ThreadOps = undefined;
    ops.run = .{ .n = false };
    var group: std.Io.Group = .init;
    defer group.cancel(io);
    for (0..FuzzMultiThreadedContext.n_threads) |_| {
        try group.concurrent(io, fuzzMultiThreadedWorker, .{ io, &ops });
    }

    try std.testing.fuzz(FuzzMultiThreadedContext{
        .testing_buf = testing_buf,
        .backing_buf = backing_buf,

        .io = io,
        .ops = &ops,
    }, fuzzMultiThreaded, .{});
}

const FuzzMultiThreadedContext = struct {
    testing_buf: []u8,
    backing_buf: []u8,

    io: std.Io,
    ops: *ThreadOps,

    const n_threads = 4;

    const ThreadOps = struct {
        /// Switches between two values for each time a run starts.
        run: Run,
        /// While this can be calculated as `n_threads - (i -| ops.items.len)`,
        /// this also serves as `.release` synchronization for each thread.
        running: u32,

        instance: SafeAllocator,
        i: usize,
        items: []Op,

        const Run = packed struct(u32) {
            n: bool,
            pad: u31 = 0,

            fn wait(ptr: *Run, val: Run, io: std.Io) error{Canceled}!void {
                assert(val.pad == 0);
                while (true) {
                    // This cannot load a previous value since this thread previously loaded the
                    // latest value.
                    const prev = @atomicLoad(Run, ptr, .acquire);
                    assert(prev.pad == 0);
                    if (prev == val) break;

                    try io.futexWait(Run, ptr, prev);
                }
            }

            fn next(r: Run) Run {
                assert(r.pad == 0);
                return .{ .n = !r.n };
            }
        };

        const Op = union(fuzz_probs.Op) {
            alloc: struct {
                len: usize,
                alignment: Alignment,

                splat: ?u8,
                /// Not embeded directly in the struct as a workaround for tsan since a
                /// switch directly on `Op` loads the entire value non-atomically.
                result: *MemoryDependency,
            },
            free: struct {
                memory: *MemoryDependency,
                alignment: Alignment,

                splat: ?u8,
            },
            resize: Realloc,
            remap: Realloc,

            const Realloc = struct {
                memory: *MemoryDependency,
                alignment: Alignment,
                new_len: usize,

                splat: ?u8,
                /// Not embeded directly in the struct as a workaround for tsan since a
                /// switch directly on `Op` loads the entire value non-atomically.
                result: *MemoryDependency,
            };

            const MemoryDependency = struct {
                ready: std.Io.Event,
                /// Null if the memory failed to be allocated
                memory: ?[]u8,

                const init: MemoryDependency = .{
                    .ready = .unset,
                    .memory = undefined,
                };

                fn get(dep: *MemoryDependency, io: std.Io) ?[]u8 {
                    dep.ready.waitUncancelable(io);
                    return dep.memory;
                }
            };
        };
    };
};

/// Guarantees memory will not be reused.
const FuzzMultiThreadedAllocator = struct {
    gpa: mem.Allocator,

    fill: usize,
    active_allocs: usize,
    fail_i: usize,
    fixed_remap_i: usize,

    // The below are assumed to be externally synchronized
    // i.e. each thread has an acquire fence before **first** using the allocator
    buf: []u8,
    fails: []const bool,
    fixed_remaps: []const bool,

    fn allocator(f: *FuzzMultiThreadedAllocator) mem.Allocator {
        @disableInstrumentation();
        return .{ .ptr = f, .vtable = &.{
            .alloc = FuzzMultiThreadedAllocator.alloc,
            .free = FuzzMultiThreadedAllocator.free,
            .resize = FuzzMultiThreadedAllocator.resize,
            .remap = FuzzMultiThreadedAllocator.remap,
        } };
    }

    fn maybeFail(f: *FuzzMultiThreadedAllocator) bool {
        @disableInstrumentation();
        const i = @atomicRmw(usize, &f.fail_i, .Add, 1, .monotonic);
        return i < f.fails.len and f.fails[i];
    }

    fn maybeFixedRemap(f: *FuzzMultiThreadedAllocator) bool {
        @disableInstrumentation();
        const i = @atomicRmw(usize, &f.fixed_remap_i, .Add, 1, .monotonic);
        return i < f.fixed_remaps.len and f.fixed_remaps[i];
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, _: usize) ?[*]u8 {
        @disableInstrumentation();

        const f: *FuzzMultiThreadedAllocator = @ptrCast(@alignCast(ctx));
        const memory = f.allocInner(len, alignment) orelse return null;
        _ = @atomicRmw(usize, &f.active_allocs, .Add, 1, .monotonic);
        return memory;
    }

    fn allocInner(f: *FuzzMultiThreadedAllocator, len: usize, alignment: Alignment) ?[*]u8 {
        var prev_fill = @atomicLoad(usize, &f.fill, .monotonic);
        var start: usize = undefined;
        while (true) {
            const start_addr = alignment.forward(@intFromPtr(f.buf[prev_fill..].ptr));
            start = @as([*]u8, @ptrFromInt(start_addr)) - f.buf.ptr;
            if (start +| len > f.buf.len or f.maybeFail()) return null;
            prev_fill = @cmpxchgStrong(
                usize,
                &f.fill,
                prev_fill,
                start + len,
                .monotonic,
                .monotonic,
            ) orelse {
                @branchHint(.likely);
                break;
            };
        }
        return f.buf[start..][0..len].ptr;
    }

    fn free(ctx: *anyopaque, _: []u8, _: Alignment, _: usize) void {
        @disableInstrumentation();

        const f: *FuzzMultiThreadedAllocator = @ptrCast(@alignCast(ctx));
        assert(@atomicRmw(usize, &f.active_allocs, .Sub, 1, .monotonic) != 0);
    }

    fn resize(ctx: *anyopaque, memory: []u8, _: Alignment, new_len: usize, _: usize) bool {
        @disableInstrumentation();

        const f: *FuzzMultiThreadedAllocator = @ptrCast(@alignCast(ctx));
        const start = memory.ptr - f.buf.ptr;
        const old_end = start + memory.len;
        const new_end = start +| new_len;
        if (new_end > f.buf.len or f.maybeFail()) {
            return false;
        }

        if (new_len <= memory.len) {
            // The fill is not decreased so memory is not reused.
            return true;
        }

        return @cmpxchgStrong(usize, &f.fill, old_end, new_end, .monotonic, .monotonic) == null;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, _: usize) ?[*]u8 {
        @disableInstrumentation();

        if (maybeFixedRemap(@ptrCast(@alignCast(ctx)))) {
            const resized = FuzzMultiThreadedAllocator.resize(
                ctx,
                memory,
                alignment,
                new_len,
                undefined,
            );
            return if (resized) memory.ptr else null;
        }

        const f: *FuzzMultiThreadedAllocator = @ptrCast(@alignCast(ctx));
        const new_ptr = f.allocInner(new_len, alignment) orelse return null;
        const copy_len = @min(memory.len, new_len);
        @memcpy(new_ptr[0..copy_len], memory[0..copy_len]);
        return new_ptr;
    }
};

fn fuzzMultiThreaded(ctx: FuzzMultiThreadedContext, smith: *Smith) !void {
    @disableInstrumentation();

    var gpa_instance: std.heap.FixedBufferAllocator = .init(ctx.testing_buf);
    const gpa = gpa_instance.allocator();

    var op_count: u32 = 0;
    while (!smith.eosWeighted(fuzz_probs.eos)) op_count += 1;
    const Op = FuzzMultiThreadedContext.ThreadOps.Op;
    const ops = gpa.alloc(Op, op_count) catch return error.SkipZigTest;
    const op_results = gpa.alloc(Op.MemoryDependency, op_count) catch return error.SkipZigTest;
    @memset(op_results, .init);

    const allocs = gpa.alloc(struct {
        memory: *FuzzMultiThreadedContext.ThreadOps.Op.MemoryDependency,
        alignment: Alignment,
        splat: ?u8,
    }, op_count) catch return error.SkipZigTest;
    var allocs_n: u32 = 0;
    var expected_remaps: usize = 0;

    const options = fuzz_probs.generateOptions(smith);
    for (ops, op_results) |*op, *result| switch (fuzz_probs.generateOp(smith, allocs_n != 0)) {
        .alloc => {
            const splat = fuzz_probs.generateSplat(smith);
            const will_memset = options.check_write_after_free or splat != null;
            op.* = .{ .alloc = .{
                .len = fuzz_probs.generateLen(smith, will_memset),
                .alignment = smith.valueWeighted(Alignment, fuzz_probs.alignment),

                .splat = splat,
                .result = result,
            } };
            allocs[allocs_n] = .{
                .memory = result,
                .alignment = op.alloc.alignment,
                .splat = splat,
            };
            allocs_n += 1;
        },
        .free => {
            const i = smith.valueRangeLessThan(u32, 0, allocs_n);
            op.* = .{ .free = .{
                .memory = allocs[i].memory,
                .alignment = allocs[i].alignment,

                .splat = allocs[i].splat,
            } };

            allocs_n -= 1;
            allocs[i] = allocs[allocs_n];
        },
        .resize, .remap => |kind| {
            op.* = switch (kind) {
                .remap => .{ .remap = undefined },
                .resize => .{ .resize = undefined },
                else => unreachable,
            };
            const realloc = switch (kind) {
                .remap => &op.remap,
                .resize => &op.resize,
                else => unreachable,
            };
            expected_remaps += @intFromBool(kind == .remap);

            const i = smith.valueRangeLessThan(u32, 0, allocs_n);
            realloc.* = .{
                .memory = allocs[i].memory,
                .alignment = allocs[i].alignment,
                .new_len = fuzz_probs.generateLen(smith, options.check_write_after_free),

                .splat = allocs[i].splat,
                .result = result,
            };
            allocs[i].memory = result;
        },
    };

    const fails: []bool = gpa.alloc(bool, ops.len * 2 + smith.value(u8)) catch &.{};
    const fixed_remaps: []bool = gpa.alloc(bool, expected_remaps + smith.value(u8)) catch &.{};
    for (fails) |*f| f.* = smith.boolWeighted(31, 1);
    for (fixed_remaps) |*f| f.* = smith.value(bool);
    var backing_gpa_instance: FuzzMultiThreadedAllocator = .{
        .gpa = gpa,

        .fill = 0,
        .active_allocs = 0,
        .fail_i = 0,
        .fixed_remap_i = 0,

        .buf = ctx.backing_buf,
        .fails = fails,
        .fixed_remaps = fixed_remaps,
    };
    const backing_gpa = backing_gpa_instance.allocator();

    ctx.ops.instance = .init(backing_gpa, options);
    ctx.ops.i = 0;
    ctx.ops.items = ops;

    ctx.ops.running = FuzzMultiThreadedContext.n_threads;
    // Loading `ctx.ops.run` non-atomically is fine since this is the only thread that writes to it.
    @atomicStore(FuzzMultiThreadedContext.ThreadOps.Run, &ctx.ops.run, ctx.ops.run.next(), .release);
    ctx.io.futexWake(FuzzMultiThreadedContext.ThreadOps.Run, &ctx.ops.run, math.maxInt(u32));
    while (true) {
        const prev_running = @atomicLoad(u32, &ctx.ops.running, .acquire);
        if (prev_running == 0) break;
        ctx.io.futexWaitUncancelable(u32, &ctx.ops.running, prev_running);
    }

    var expected_allocs = allocs_n;
    for (allocs[0..allocs_n]) |a| {
        expected_allocs -= @intFromBool(a.memory.memory == null);
    }
    try std.testing.expectEqual(expected_allocs, ctx.ops.instance.deinitLog(false));
    try std.testing.expectEqual(0, backing_gpa_instance.active_allocs); // no leaks
}

fn fuzzMultiThreadedWorker(
    io: std.Io,
    ops: *FuzzMultiThreadedContext.ThreadOps,
) error{Canceled}!void {
    const no_ra: usize = 0;
    var next_run: FuzzMultiThreadedContext.ThreadOps.Run = .{ .n = true };
    while (true) {
        try ops.run.wait(next_run, io);
        next_run = .next(next_run);

        while (true) {
            const i = @atomicRmw(usize, &ops.i, .Add, 1, .monotonic);
            if (i >= ops.items.len) {
                // `.acq_rel` is necessary since acquire loads only synchronize with the thread
                // which the read value was written from, not all previous writer threads.
                const prev_rem = @atomicRmw(u32, &ops.running, .Sub, 1, .acq_rel);
                if (prev_rem - 1 == 0) {
                    io.futexWake(u32, &ops.running, 1);
                }
                break;
            }

            switch (ops.items[i]) {
                .alloc => |call| {
                    const alloc_ptr = alloc(&ops.instance, call.len, call.alignment, no_ra);
                    if (alloc_ptr) |memory_ptr| {
                        const memory = memory_ptr[0..call.len];
                        if (call.splat) |b| @memset(memory, b);
                        call.result.memory = memory;
                    } else {
                        call.result.memory = null;
                    }
                    call.result.ready.set(io);
                },
                .free => |call| {
                    const memory = call.memory.get(io) orelse continue;
                    fuzz_probs.checkSplat(call.splat, memory);
                    free(&ops.instance, memory, call.alignment, no_ra);
                },
                .resize, .remap => |call, kind| {
                    const memory = call.memory.get(io) orelse {
                        call.result.memory = null;
                        call.result.ready.set(io);
                        continue;
                    };
                    const new_memory: []u8 = switch (kind) {
                        .remap => if (remap(
                            &ops.instance,
                            memory,
                            call.alignment,
                            call.new_len,
                            no_ra,
                        )) |new_ptr| new_ptr[0..call.new_len] else memory,
                        .resize => if (resize(
                            &ops.instance,
                            memory,
                            call.alignment,
                            call.new_len,
                            no_ra,
                        )) memory.ptr[0..call.new_len] else memory,
                        else => unreachable,
                    };

                    const old_len = memory.len;
                    const new_len = new_memory.len;
                    fuzz_probs.checkSplat(call.splat, new_memory[0..@min(old_len, new_len)]);
                    if (call.splat) |b| @memset(new_memory[@min(old_len, new_len)..], b);

                    call.result.memory = new_memory;
                    call.result.ready.set(io);
                },
            }
        }
    }
}
