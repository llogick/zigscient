const MappedFile = @This();

const builtin = @import("builtin");
const is_linux = builtin.os.tag == .linux;
const is_windows = builtin.os.tag == .windows;

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const assert = std.debug.assert;
const linux = std.os.linux;
const windows = std.os.windows;

io: Io,
flags: packed struct {
    block_size: std.mem.Alignment,
    copy_file_range_unsupported: bool,
    fallocate_punch_hole_unsupported: bool,
    fallocate_insert_range_unsupported: bool,
},
memory_map: Io.File.MemoryMap,
nodes: std.ArrayList(Node),
free_ni: Node.Index,
large: std.ArrayList(u64),
updates: std.ArrayList(Node.Index),
update_prog_node: std.Progress.Node,
writers: std.SinglyLinkedList,
io_err: ?IoError,
/// If locked, modifying the node layout is not allowed.
/// Modifying node content is always allowed.
nodes_lock: std.debug.SafetyLock = .{},

pub const growth_factor = 4;

pub const IoError = Io.UnexpectedError || error{
    DiskQuota,
    FileTooBig,
    InputOutput,
    NoSpaceLeft,
    AccessDenied,
    PermissionDenied,
    SystemResources,
    LockViolation,
    LockedMemoryLimitExceeded,
    ProcessFdQuotaExceeded,
    SystemFdQuotaExceeded,
    FileBusy,
    DeviceBusy,
    NoDevice,
    PathAlreadyExists,
    IsDir,
    NotFile,
    BrokenPipe,
    NonResizable,
    Unseekable,
};

pub const Error = Allocator.Error || Io.Cancelable || error{
    /// Some I/O operation on the memory-mapped file failed. The underlying error is available in
    /// the `MappedFile.io_err` field.
    MappedFileIo,
};

pub fn init(file: Io.File, gpa: std.mem.Allocator, io: Io) (Allocator.Error || Io.Cancelable || IoError)!MappedFile {
    var mf: MappedFile = .{
        .io = io,
        .flags = undefined,
        .memory_map = .{
            .file = file,
            .memory = &.{},
            .offset = 0,
            .section = null,
        },
        .nodes = .empty,
        .free_ni = .none,
        .large = .empty,
        .updates = .empty,
        .update_prog_node = .none,
        .writers = .{},
        .io_err = null,
    };
    errdefer mf.deinit(gpa);
    const size: u64, const block_size = stat: {
        const stat = file.stat(io) catch |err| switch (err) {
            error.Streaming => return error.PathAlreadyExists,
            else => |e| return e,
        };
        if (stat.kind != .file) return error.PathAlreadyExists;
        break :stat .{ stat.size, @max(std.heap.pageSize(), stat.block_size) };
    };
    mf.flags = .{
        .block_size = .fromByteUnits(std.math.ceilPowerOfTwoAssert(usize, block_size)),
        .copy_file_range_unsupported = false,
        .fallocate_insert_range_unsupported = false,
        .fallocate_punch_hole_unsupported = false,
    };
    try mf.nodes.ensureUnusedCapacity(gpa, 1);
    const root_ni = try mf.addNode(gpa, .{ .add_node = .{
        .size = size,
        .alignment = mf.flags.block_size,
        .fixed = true,
    } });
    assert(root_ni == Node.Index.root);
    try mf.ensureTotalCapacityInner(@intCast(size));
    return mf;
}

pub fn deinit(mf: *MappedFile, gpa: std.mem.Allocator) void {
    mf.unmap();
    mf.nodes.deinit(gpa);
    mf.large.deinit(gpa);
    mf.updates.deinit(gpa);
    mf.update_prog_node.end();
    assert(mf.writers.first == null);
    mf.* = undefined;
}

pub const Node = extern struct {
    parent: Node.Index,
    prev: Node.Index,
    next: Node.Index,
    first: Node.Index,
    last: Node.Index,
    flags: Flags,
    location_payload: Location.Payload,

    pub const Flags = packed struct(u32) {
        location_tag: Location.Tag,
        alignment: std.mem.Alignment,
        /// Whether this node can be moved.
        fixed: bool,
        /// Whether this node has been moved.
        moved: bool,
        /// Whether this node has been resized.
        resized: bool,
        /// Whether this node might contain non-zero bytes.
        has_content: bool,
        /// Whether a moved event on this node bubbles down to children.
        bubbles_moved: bool,
        unused: @Int(.unsigned, 32 - @bitSizeOf(std.mem.Alignment) - 6) = 0,
    };

    pub const Location = union(enum(u1)) {
        small: extern struct {
            /// Relative to `parent`.
            offset: u32,
            size: u32,
        },
        large: extern struct {
            index: usize,
            unused: @Int(.unsigned, 64 - @bitSizeOf(usize)) = 0,
        },

        pub const Tag = @typeInfo(Location).@"union".tag_type.?;
        pub const Payload = extern union {
            small: @FieldType(Location, "small"),
            large: @FieldType(Location, "large"),
        };

        pub fn resolve(loc: Location, mf: *const MappedFile) [2]u64 {
            return switch (loc) {
                .small => |small| .{ small.offset, small.size },
                .large => |large| mf.large.items[large.index..][0..2].*,
            };
        }
    };

    pub const FileLocation = struct {
        offset: u64,
        size: u64,

        pub fn end(fl: FileLocation) u64 {
            return fl.offset + fl.size;
        }
    };

    pub const Index = enum(u32) {
        none,
        _,

        pub const root: Node.Index = .none;

        fn get(ni: Node.Index, mf: *const MappedFile) *Node {
            return &mf.nodes.items[@intFromEnum(ni)];
        }

        pub fn parent(ni: Node.Index, mf: *const MappedFile) Node.Index {
            return ni.get(mf).parent;
        }

        pub fn next(ni: Node.Index, mf: *const MappedFile) Node.Index {
            return ni.get(mf).next;
        }

        pub fn ChildIterator(comptime direction: enum { prev, next }) type {
            return struct {
                mf: *const MappedFile,
                ni: Node.Index,
                pub fn next(it: *@This()) ?Node.Index {
                    const ni = it.ni;
                    if (ni == .none) return null;
                    it.ni = @field(ni.get(it.mf), @tagName(direction));
                    return ni;
                }
            };
        }
        pub fn children(ni: Node.Index, mf: *const MappedFile) ChildIterator(.next) {
            return .{ .mf = mf, .ni = ni.get(mf).first };
        }
        pub fn reverseChildren(ni: Node.Index, mf: *const MappedFile) ChildIterator(.prev) {
            return .{ .mf = mf, .ni = ni.get(mf).last };
        }

        pub fn childrenMoved(ni: Node.Index, gpa: std.mem.Allocator, mf: *MappedFile) Allocator.Error!void {
            var child_ni = ni.get(mf).last;
            while (child_ni != .none) {
                try child_ni.moved(gpa, mf);
                child_ni = child_ni.get(mf).prev;
            }
        }

        pub fn hasMoved(ni: Node.Index, mf: *const MappedFile) bool {
            var parent_ni = ni;
            while (parent_ni != Node.Index.root) {
                const parent_node = parent_ni.get(mf);
                if (!parent_node.flags.bubbles_moved) break;
                if (parent_node.flags.moved) return true;
                parent_ni = parent_node.parent;
            }
            return false;
        }
        pub fn moved(ni: Node.Index, gpa: std.mem.Allocator, mf: *MappedFile) Allocator.Error!void {
            try mf.updates.ensureUnusedCapacity(gpa, 1);
            ni.movedAssumeCapacity(mf);
        }
        pub fn cleanMoved(ni: Node.Index, mf: *const MappedFile) bool {
            const node_moved = &ni.get(mf).flags.moved;
            defer node_moved.* = false;
            return node_moved.*;
        }
        pub fn movedAssumeCapacity(ni: Node.Index, mf: *MappedFile) void {
            if (ni.hasMoved(mf)) return;
            const node = ni.get(mf);
            node.flags.moved = true;
            if (node.flags.resized) return;
            mf.updates.appendAssumeCapacity(ni);
            mf.update_prog_node.increaseEstimatedTotalItems(1);
        }

        pub fn hasResized(ni: Node.Index, mf: *const MappedFile) bool {
            return ni.get(mf).flags.resized;
        }
        pub fn resized(ni: Node.Index, gpa: std.mem.Allocator, mf: *MappedFile) Allocator.Error!void {
            try mf.updates.ensureUnusedCapacity(gpa, 1);
            ni.resizedAssumeCapacity(mf);
        }
        pub fn cleanResized(ni: Node.Index, mf: *const MappedFile) bool {
            const node_resized = &ni.get(mf).flags.resized;
            defer node_resized.* = false;
            return node_resized.*;
        }
        pub fn resizedAssumeCapacity(ni: Node.Index, mf: *MappedFile) void {
            const node = ni.get(mf);
            if (node.flags.resized) return;
            node.flags.resized = true;
            if (node.flags.moved) return;
            mf.updates.appendAssumeCapacity(ni);
            mf.update_prog_node.increaseEstimatedTotalItems(1);
        }

        pub fn alignment(ni: Node.Index, mf: *const MappedFile) std.mem.Alignment {
            return ni.get(mf).flags.alignment;
        }

        fn setLocationAssumeCapacity(ni: Node.Index, mf: *MappedFile, offset: u64, size: u64) void {
            const node = ni.get(mf);
            if (size == 0) node.flags.has_content = false;
            switch (node.location()) {
                .small => |small| {
                    if (small.offset != offset) ni.movedAssumeCapacity(mf);
                    if (small.size != size) ni.resizedAssumeCapacity(mf);
                    if (std.math.cast(u32, offset)) |small_offset| {
                        if (std.math.cast(u32, size)) |small_size| {
                            node.location_payload.small = .{
                                .offset = small_offset,
                                .size = small_size,
                            };
                            return;
                        }
                    }
                    defer mf.large.appendSliceAssumeCapacity(&.{ offset, size });
                    node.flags.location_tag = .large;
                    node.location_payload = .{ .large = .{ .index = mf.large.items.len } };
                },
                .large => |large| {
                    const large_items = mf.large.items[large.index..][0..2];
                    if (large_items[0] != offset) ni.movedAssumeCapacity(mf);
                    if (large_items[1] != size) ni.resizedAssumeCapacity(mf);
                    large_items.* = .{ offset, size };
                },
            }
        }

        pub fn location(ni: Node.Index, mf: *const MappedFile) Location {
            return ni.get(mf).location();
        }

        pub fn fileLocation(
            ni: Node.Index,
            mf: *const MappedFile,
            set_has_content: bool,
        ) FileLocation {
            var offset, const size = ni.location(mf).resolve(mf);
            var parent_ni = ni;
            while (true) {
                const parent_node = parent_ni.get(mf);
                if (set_has_content) parent_node.flags.has_content = true;
                if (parent_ni == .none) break;
                parent_ni = parent_node.parent;
                const parent_offset, _ = parent_ni.location(mf).resolve(mf);
                offset += parent_offset;
            }
            return .{ .offset = offset, .size = size };
        }

        pub fn slice(ni: Node.Index, mf: *const MappedFile) []u8 {
            const file_loc = ni.fileLocation(mf, true);
            return mf.memory_map.memory[@intCast(file_loc.offset)..][0..@intCast(file_loc.size)];
        }

        pub fn sliceConst(ni: Node.Index, mf: *const MappedFile) []const u8 {
            const file_loc = ni.fileLocation(mf, false);
            return mf.memory_map.memory[@intCast(file_loc.offset)..][0..@intCast(file_loc.size)];
        }

        pub fn resize(ni: Node.Index, mf: *MappedFile, gpa: std.mem.Allocator, size: u64) Error!void {
            mf.resizeNode(gpa, ni, size) catch |err| switch (err) {
                error.OutOfMemory,
                error.Canceled,
                => |e| return e,
                else => |e| {
                    mf.io_err = e;
                    return error.MappedFileIo;
                },
            };
            var writers_it = mf.writers.first;
            while (writers_it) |writer_node| : (writers_it = writer_node.next) {
                const w: *Node.Writer = @fieldParentPtr("writer_node", writer_node);
                w.interface.buffer = w.ni.slice(mf);
            }
        }

        pub const RealignNodeOptions = struct {
            /// Shift the node backwards if possible
            try_backwards: bool = false,
        };

        /// Moves and expands a node such that its offset and size are aligned to `new_alignment`.
        /// Asserts that `ni` is not `Node.Index.root`.
        pub fn realign(
            ni: Node.Index,
            mf: *MappedFile,
            gpa: std.mem.Allocator,
            new_alignment: std.mem.Alignment,
            opts: RealignNodeOptions,
        ) Error!void {
            mf.realignNode(gpa, ni, new_alignment, opts) catch |err| switch (err) {
                error.OutOfMemory,
                error.Canceled,
                => |e| return e,
                else => |e| {
                    mf.io_err = e;
                    return error.MappedFileIo;
                },
            };
            mf.updateWriters();
        }

        /// Shrink a node to `size`, exactly.
        /// Asserts that the new size can contain all the children.
        /// If `shift_next` is set, then the following node is shifted backwards into
        /// the free space as much as alignment allows.
        /// Asserts that `size` is >= the end of the last child node.
        pub fn shrink(
            ni: Node.Index,
            mf: *MappedFile,
            gpa: std.mem.Allocator,
            size: u64,
            shift_next: bool,
        ) Error!void {
            try mf.shrinkNode(gpa, ni, size, shift_next);
            mf.updateWriters();
        }

        pub fn writer(ni: Node.Index, mf: *MappedFile, gpa: std.mem.Allocator, w: *Writer) void {
            w.* = .{
                .gpa = gpa,
                .mf = mf,
                .writer_node = .{},
                .ni = ni,
                .interface = .{
                    .buffer = ni.slice(mf),
                    .vtable = &Writer.vtable,
                },
                .err = null,
            };
            mf.writers.prepend(&w.writer_node);
        }
    };

    pub fn location(node: *const Node) Location {
        return switch (node.flags.location_tag) {
            inline else => |tag| @unionInit(
                Location,
                @tagName(tag),
                @field(node.location_payload, @tagName(tag)),
            ),
        };
    }

    pub const Writer = struct {
        gpa: std.mem.Allocator,
        mf: *MappedFile,
        writer_node: std.SinglyLinkedList.Node,
        ni: Node.Index,
        interface: Io.Writer,
        err: ?Error,

        pub fn deinit(w: *Writer) void {
            assert(w.mf.writers.popFirst() == &w.writer_node);
            w.* = undefined;
        }

        const vtable: Io.Writer.VTable = .{
            .drain = drain,
            .sendFile = sendFile,
            .flush = Io.Writer.noopFlush,
            .rebase = growingRebase,
        };

        fn drain(
            interface: *Io.Writer,
            data: []const []const u8,
            splat: usize,
        ) Io.Writer.Error!usize {
            const pattern = data[data.len - 1];
            const splat_len = pattern.len * splat;
            const start_len = interface.end;
            assert(data.len != 0);
            for (data) |bytes| {
                try growingRebase(interface, interface.end, bytes.len + splat_len + 1);
                @memcpy(interface.buffer[interface.end..][0..bytes.len], bytes);
                interface.end += bytes.len;
            }
            if (splat == 0) {
                interface.end -= pattern.len;
            } else switch (pattern.len) {
                0 => {},
                1 => {
                    @memset(interface.buffer[interface.end..][0 .. splat - 1], pattern[0]);
                    interface.end += splat - 1;
                },
                else => for (0..splat - 1) |_| {
                    @memcpy(interface.buffer[interface.end..][0..pattern.len], pattern);
                    interface.end += pattern.len;
                },
            }
            return interface.end - start_len;
        }

        fn sendFile(
            interface: *Io.Writer,
            file_reader: *Io.File.Reader,
            limit: Io.Limit,
        ) Io.Writer.FileError!usize {
            if (limit == .nothing) return 0;
            const pos = file_reader.logicalPos();
            const additional = if (file_reader.getSize()) |size| size - pos else |_| std.atomic.cache_line;
            if (additional == 0) return error.EndOfStream;
            try growingRebase(interface, interface.end, limit.minInt64(additional));
            switch (file_reader.mode) {
                .positional => {
                    const fr_buf = file_reader.interface.buffered();
                    if (fr_buf.len > 0) {
                        const n = interface.write(fr_buf) catch unreachable;
                        file_reader.interface.toss(n);
                        return n;
                    }
                    const w: *Writer = @fieldParentPtr("interface", interface);
                    const n: usize = @intCast(w.mf.copyFileRange(
                        file_reader.file,
                        file_reader.pos,
                        w.ni.fileLocation(w.mf, true).offset + interface.end,
                        limit.minInt(interface.unusedCapacityLen()),
                    ) catch |err| switch (err) {
                        error.Canceled => |e| {
                            w.err = e;
                            return error.WriteFailed;
                        },
                        else => |e| {
                            w.mf.io_err = e;
                            w.err = error.MappedFileIo;
                            return error.WriteFailed;
                        },
                    });
                    if (n == 0) return error.Unimplemented;
                    file_reader.pos += n;
                    interface.end += n;
                    return n;
                },
                .streaming,
                .streaming_simple,
                .positional_simple,
                .failure,
                => {
                    const dest = limit.slice(interface.unusedCapacitySlice());
                    const n = try file_reader.interface.readSliceShort(dest);
                    if (n == 0) return error.EndOfStream;
                    interface.end += n;
                    return n;
                },
            }
        }

        fn growingRebase(
            interface: *Io.Writer,
            preserve: usize,
            unused_capacity: usize,
        ) Io.Writer.Error!void {
            _ = preserve;
            const total_capacity = interface.end + unused_capacity;
            if (interface.buffer.len >= total_capacity) return;
            const w: *Writer = @fieldParentPtr("interface", interface);
            w.ni.resize(w.mf, w.gpa, total_capacity +| total_capacity / growth_factor) catch |err| {
                w.err = err;
                return error.WriteFailed;
            };
        }
    };

    comptime {
        if (!std.debug.runtime_safety) std.debug.assert(@sizeOf(Node) == 32);
    }
};

fn addNode(mf: *MappedFile, gpa: std.mem.Allocator, opts: struct {
    parent: Node.Index = .none,
    prev: Node.Index = .none,
    next: Node.Index = .none,
    offset: u64 = 0,
    add_node: AddNodeOptions,
}) (Allocator.Error || Io.Cancelable || IoError)!Node.Index {
    if (opts.add_node.moved or opts.add_node.resized) try mf.updates.ensureUnusedCapacity(gpa, 1);
    mf.nodes_lock.assertUnlocked();
    const location_tag: Node.Location.Tag, const location_payload: Node.Location.Payload = location: {
        if (std.math.cast(u32, opts.offset)) |small_offset| break :location .{ .small, .{
            .small = .{ .offset = small_offset, .size = 0 },
        } };
        try mf.large.ensureUnusedCapacity(gpa, 2);
        defer mf.large.appendSliceAssumeCapacity(&.{ opts.offset, 0 });
        break :location .{ .large, .{ .large = .{ .index = mf.large.items.len } } };
    };
    const free_ni: Node.Index, const free_node = free: switch (mf.free_ni) {
        .none => .{ @enumFromInt(mf.nodes.items.len), mf.nodes.addOneAssumeCapacity() },
        else => |free_ni| {
            const free_node = free_ni.get(mf);
            mf.free_ni = free_node.next;
            break :free .{ free_ni, free_node };
        },
    };
    switch (opts.prev) {
        .none => opts.parent.get(mf).first = free_ni,
        else => |prev_ni| prev_ni.get(mf).next = free_ni,
    }
    switch (opts.next) {
        .none => opts.parent.get(mf).last = free_ni,
        else => |next_ni| next_ni.get(mf).prev = free_ni,
    }
    free_node.* = .{
        .parent = opts.parent,
        .prev = opts.prev,
        .next = opts.next,
        .first = .none,
        .last = .none,
        .flags = .{
            .location_tag = location_tag,
            .alignment = .@"1",
            .fixed = opts.add_node.fixed,
            .moved = true,
            .resized = true,
            .has_content = false,
            .bubbles_moved = opts.add_node.bubbles_moved,
        },
        .location_payload = location_payload,
    };

    {
        try mf.realignNode(gpa, free_ni, opts.add_node.alignment, .{});
        try mf.resizeNode(gpa, free_ni, opts.add_node.size);
        if (opts.add_node.moved or opts.add_node.resized) try mf.updates.ensureUnusedCapacity(gpa, 1);
        free_node.flags.moved = false;
        free_node.flags.resized = false;
    }
    if (opts.add_node.moved) free_ni.movedAssumeCapacity(mf);
    if (opts.add_node.resized) free_ni.resizedAssumeCapacity(mf);
    mf.updateWriters();
    return free_ni;
}

pub const AddNodeOptions = struct {
    size: u64 = 0,
    alignment: std.mem.Alignment = .@"1",
    fixed: bool = false,
    moved: bool = false,
    resized: bool = false,
    bubbles_moved: bool = true,
};

pub fn addOnlyChildNode(
    mf: *MappedFile,
    gpa: std.mem.Allocator,
    parent_ni: Node.Index,
    opts: AddNodeOptions,
) Error!Node.Index {
    try mf.nodes.ensureUnusedCapacity(gpa, 1);
    const parent = parent_ni.get(mf);
    assert(parent.first == .none and parent.last == .none);
    return mf.addNode(gpa, .{
        .parent = parent_ni,
        .add_node = opts,
    }) catch |err| switch (err) {
        error.OutOfMemory,
        error.Canceled,
        => |e| return e,
        else => |e| {
            mf.io_err = e;
            return error.MappedFileIo;
        },
    };
}

pub fn addFirstChildNode(
    mf: *MappedFile,
    gpa: std.mem.Allocator,
    parent_ni: Node.Index,
    opts: AddNodeOptions,
) Error!Node.Index {
    try mf.nodes.ensureUnusedCapacity(gpa, 1);
    const parent = parent_ni.get(mf);
    return mf.addNode(gpa, .{
        .parent = parent_ni,
        .next = parent.first,
        .add_node = opts,
    }) catch |err| switch (err) {
        error.OutOfMemory,
        error.Canceled,
        => |e| return e,
        else => |e| {
            mf.io_err = e;
            return error.MappedFileIo;
        },
    };
}

pub fn addLastChildNode(
    mf: *MappedFile,
    gpa: std.mem.Allocator,
    parent_ni: Node.Index,
    opts: AddNodeOptions,
) Error!Node.Index {
    try mf.nodes.ensureUnusedCapacity(gpa, 1);
    const parent = parent_ni.get(mf);
    return mf.addNode(gpa, .{
        .parent = parent_ni,
        .prev = parent.last,
        .offset = offset: switch (parent.last) {
            .none => 0,
            else => |last_ni| {
                const last_offset, const last_size = last_ni.location(mf).resolve(mf);
                break :offset last_offset + last_size;
            },
        },
        .add_node = opts,
    }) catch |err| switch (err) {
        error.OutOfMemory,
        error.Canceled,
        => |e| return e,
        else => |e| {
            mf.io_err = e;
            return error.MappedFileIo;
        },
    };
}

pub fn addNodeAfter(
    mf: *MappedFile,
    gpa: std.mem.Allocator,
    prev_ni: Node.Index,
    opts: AddNodeOptions,
) Error!Node.Index {
    assert(prev_ni != .none);
    try mf.nodes.ensureUnusedCapacity(gpa, 1);
    const prev = prev_ni.get(mf);
    const prev_offset, const prev_size = prev.location().resolve(mf);
    return mf.addNode(gpa, .{
        .parent = prev.parent,
        .prev = prev_ni,
        .next = prev.next,
        .offset = prev_offset + prev_size,
        .add_node = opts,
    }) catch |err| switch (err) {
        error.OutOfMemory,
        error.Canceled,
        => |e| return e,
        else => |e| {
            mf.io_err = e;
            return error.MappedFileIo;
        },
    };
}

fn shrinkNode(
    mf: *MappedFile,
    gpa: std.mem.Allocator,
    ni: Node.Index,
    size: u64,
    shift_next: bool,
) !void {
    mf.nodes_lock.assertUnlocked();
    const node = ni.get(mf);
    const old_offset, _ = node.location().resolve(mf);

    // This would require unmapping first
    assert(ni != Node.Index.root);

    if (node.last != .none) {
        const last = node.last.get(mf);
        const last_offset, const last_size = last.location().resolve(mf);
        assert(last_offset + last_size > size);
    }

    try mf.large.ensureUnusedCapacity(gpa, 4);
    try mf.updates.ensureUnusedCapacity(gpa, 2);

    ni.setLocationAssumeCapacity(mf, old_offset, size);
    if (!shift_next or node.next == .none) return;

    const next = node.next.get(mf);
    const old_next_offset, const next_size = next.location().resolve(mf);
    const padding = old_next_offset - (old_offset + size);
    const new_next_offset = next.flags.alignment.forward(@intCast(old_next_offset - padding));

    if (next.flags.has_content and new_next_offset < old_next_offset) {
        const old_file_offset = node.next.fileLocation(mf, false).offset;
        const new_file_offset = (old_file_offset - old_next_offset) + new_next_offset;
        @memmove(
            mf.memory_map.memory[@intCast(new_file_offset)..][0..@intCast(next_size)],
            mf.memory_map.memory[@intCast(old_file_offset)..][0..@intCast(next_size)],
        );
        @memset(mf.memory_map.memory[@intCast(new_file_offset + next_size)..@intCast(old_file_offset + next_size)], 0);
    }

    node.next.setLocationAssumeCapacity(mf, new_next_offset, next_size);
}

fn resizeNode(
    mf: *MappedFile,
    gpa: std.mem.Allocator,
    ni: Node.Index,
    requested_size: u64,
) (Allocator.Error || Io.Cancelable || IoError)!void {
    mf.nodes_lock.assertUnlocked();
    const io = mf.io;
    const node = ni.get(mf);
    const old_offset, const old_size = node.location().resolve(mf);
    const new_size = node.flags.alignment.forward(@intCast(requested_size));

    // Resize the entire file
    if (ni == Node.Index.root) {
        try mf.ensureCapacityForSetLocation(gpa);
        mf.memory_map.write(io) catch |err| switch (err) {
            error.WouldBlock => return error.Unexpected, // file was not opened as non-blocking
            error.NotOpenForWriting => return error.Unexpected, // we definitely opened the file for writing
            else => |e| return e,
        };
        try mf.memory_map.file.setLength(io, new_size);
        try mf.ensureTotalCapacityInner(@intCast(new_size));
        ni.setLocationAssumeCapacity(mf, old_offset, new_size);
        return;
    }
    const parent = node.parent.get(mf);
    _, var old_parent_size = parent.location().resolve(mf);
    const trailing_end = trailing_end: switch (node.next) {
        .none => old_parent_size,
        else => |next_ni| {
            const next_offset, _ = next_ni.location(mf).resolve(mf);
            break :trailing_end next_offset;
        },
    };
    assert(old_offset + old_size <= trailing_end);
    if (old_offset + new_size <= trailing_end) {
        // Expand the node into trailing free space
        try mf.ensureCapacityForSetLocation(gpa);
        ni.setLocationAssumeCapacity(mf, old_offset, new_size);
        return;
    }
    if (is_linux and !mf.flags.fallocate_insert_range_unsupported and
        node.flags.alignment.order(mf.flags.block_size).compare(.gte))
    insert_range: {
        const range_file_offset = ni.fileLocation(mf, false).offset + old_size;
        const range_size = node.flags.alignment.forward(
            @intCast(requested_size +| requested_size / growth_factor),
        ) - old_size;

        // If this node is being realigned, its current state might not
        // meet the requirements for fallocate
        if (!mf.flags.block_size.check(@intCast(range_file_offset)) or
            !mf.flags.block_size.check(@intCast(range_size)))
            break :insert_range;

        mf.memory_map.write(io) catch |err| switch (err) {
            error.WouldBlock => return error.Unexpected, // file was not opened as non-blocking
            error.NotOpenForWriting => return error.Unexpected, // we definitely opened the file for writing
            else => |e| return e,
        };
        // Ask the filesystem driver to insert extents into the file without copying any data
        const last_offset, const last_size = parent.last.location(mf).resolve(mf);
        const last_end = last_offset + last_size;
        assert(last_end <= old_parent_size);
        _, const file_size = Node.Index.root.location(mf).resolve(mf);
        while (true) switch (linux.errno(switch (std.math.order(range_file_offset, file_size)) {
            .lt => linux.fallocate(
                mf.memory_map.file.handle,
                linux.FALLOC.FL_INSERT_RANGE,
                @intCast(range_file_offset),
                @intCast(range_size),
            ),
            .eq => linux.ftruncate(mf.memory_map.file.handle, @intCast(range_file_offset + range_size)),
            .gt => unreachable,
        })) {
            .SUCCESS => {
                var enclosing_ni = ni;
                while (true) {
                    try mf.ensureCapacityForSetLocation(gpa);
                    const enclosing = enclosing_ni.get(mf);
                    const enclosing_offset, const old_enclosing_size =
                        enclosing.location().resolve(mf);
                    const new_enclosing_size = old_enclosing_size + range_size;
                    enclosing_ni.setLocationAssumeCapacity(mf, enclosing_offset, new_enclosing_size);
                    if (enclosing_ni == Node.Index.root) {
                        assert(enclosing_offset == 0);
                        try mf.ensureTotalCapacityInner(@intCast(new_enclosing_size));
                        break;
                    }
                    var after_ni = enclosing.next;
                    while (after_ni != .none) {
                        try mf.ensureCapacityForSetLocation(gpa);
                        const after = after_ni.get(mf);
                        const after_offset, const after_size = after.location().resolve(mf);
                        after_ni.setLocationAssumeCapacity(
                            mf,
                            range_size + after_offset,
                            after_size,
                        );
                        after_ni = after.next;
                    }
                    enclosing_ni = enclosing.parent;
                }
                return;
            },
            .INTR => continue,
            .BADF, .FBIG, .INVAL => unreachable,
            .IO => return error.InputOutput,
            .NODEV => return error.NotFile,
            .NOSPC => return error.NoSpaceLeft,
            .NOSYS, .OPNOTSUPP => {
                mf.flags.fallocate_insert_range_unsupported = true;
                break :insert_range;
            },
            .PERM => return error.PermissionDenied,
            .SPIPE => return error.Unseekable,
            .TXTBSY => return error.FileBusy,
            else => |e| return std.posix.unexpectedErrno(e),
        };
    }
    if (node.next == .none) {
        // As this is the last node, we simply need more space in the parent
        const new_parent_size = old_offset + new_size;
        try mf.resizeNode(gpa, node.parent, new_parent_size +| new_parent_size / growth_factor);
        try mf.ensureCapacityForSetLocation(gpa);
        ni.setLocationAssumeCapacity(mf, old_offset, new_size);
        return;
    }
    if (!node.flags.fixed) {
        // Make space at the end of the parent for this floating node
        const last = parent.last.get(mf);
        const last_offset, const last_size = last.location().resolve(mf);
        const new_offset = node.flags.alignment.forward(@intCast(last_offset + last_size));
        const new_parent_size = new_offset + new_size;
        if (new_parent_size > old_parent_size)
            try mf.resizeNode(gpa, node.parent, new_parent_size +| new_parent_size / growth_factor);
        try mf.ensureCapacityForSetLocation(gpa);
        const next_ni = node.next;
        next_ni.get(mf).prev = node.prev;
        switch (node.prev) {
            .none => parent.first = next_ni,
            else => |prev_ni| prev_ni.get(mf).next = next_ni,
        }
        last.next = ni;
        node.prev = parent.last;
        node.next = .none;
        parent.last = ni;
        if (node.flags.has_content) {
            const parent_file_offset = node.parent.fileLocation(mf, false).offset;
            try mf.moveRange(
                parent_file_offset + old_offset,
                parent_file_offset + new_offset,
                old_size,
            );
        }
        ni.setLocationAssumeCapacity(mf, new_offset, new_size);
        return;
    }
    // Search for the first floating node following this fixed node
    var last_fixed_ni = ni;
    var first_floating_ni = node.next;
    var shift = new_size - old_size;
    var max_shift_align: std.mem.Alignment = .@"1";
    var direction: enum { forward, reverse } = .forward;
    while (true) {
        assert(last_fixed_ni != .none);
        const last_fixed = last_fixed_ni.get(mf);
        assert(last_fixed.flags.fixed);
        const old_last_fixed_offset, const last_fixed_size = last_fixed.location().resolve(mf);
        const new_last_fixed_offset = old_last_fixed_offset + shift;
        make_space: switch (first_floating_ni) {
            else => {
                const first_floating = first_floating_ni.get(mf);
                const old_first_floating_offset, const first_floating_size =
                    first_floating.location().resolve(mf);
                assert(old_last_fixed_offset + last_fixed_size <= old_first_floating_offset);
                if (new_last_fixed_offset + last_fixed_size <= old_first_floating_offset)
                    break :make_space;
                assert(direction == .forward);
                max_shift_align = max_shift_align.max(first_floating.flags.alignment.max(last_fixed.flags.alignment));
                if (first_floating.flags.fixed) {
                    shift = max_shift_align.forward(@intCast(
                        @max(shift, first_floating_size),
                    ));

                    // Not enough space, try the next node
                    last_fixed_ni = first_floating_ni;
                    first_floating_ni = first_floating.next;
                    continue;
                }
                // Move the found floating node to make space for preceding fixed nodes
                const last = parent.last.get(mf);
                const last_offset, const last_size = last.location().resolve(mf);
                const new_first_floating_offset = max_shift_align.forward(
                    @intCast(@max(new_last_fixed_offset + last_fixed_size, last_offset + last_size)),
                );
                const new_parent_size = new_first_floating_offset + first_floating_size;
                if (new_parent_size > old_parent_size) {
                    try mf.resizeNode(
                        gpa,
                        node.parent,
                        new_parent_size +| new_parent_size / growth_factor,
                    );
                    _, old_parent_size = parent.location().resolve(mf);
                }
                try mf.ensureCapacityForSetLocation(gpa);
                if (parent.last != first_floating_ni) {
                    first_floating.prev = parent.last;
                    parent.last = first_floating_ni;
                    last.next = first_floating_ni;
                    last_fixed.next = first_floating.next;
                    switch (first_floating.next) {
                        .none => {},
                        else => |next_ni| next_ni.get(mf).prev = last_fixed_ni,
                    }
                    first_floating.next = .none;
                }
                if (first_floating.flags.has_content) {
                    const parent_file_offset =
                        node.parent.fileLocation(mf, false).offset;
                    try mf.moveRange(
                        parent_file_offset + old_first_floating_offset,
                        parent_file_offset + new_first_floating_offset,
                        first_floating_size,
                    );
                }
                first_floating_ni.setLocationAssumeCapacity(
                    mf,
                    new_first_floating_offset,
                    first_floating_size,
                );
                // Continue the search after the just-moved floating node
                first_floating_ni = last_fixed.next;
                continue;
            },
            .none => {
                assert(direction == .forward);
                const new_parent_size = new_last_fixed_offset + last_fixed_size;
                if (new_parent_size > old_parent_size) {
                    try mf.resizeNode(
                        gpa,
                        node.parent,
                        new_parent_size +| new_parent_size / growth_factor,
                    );
                    _, old_parent_size = parent.location().resolve(mf);
                }
            },
        }
        try mf.ensureCapacityForSetLocation(gpa);
        if (last_fixed_ni == ni) {
            // The original fixed node now has enough space
            last_fixed_ni.setLocationAssumeCapacity(
                mf,
                old_last_fixed_offset,
                new_size,
            );
            return;
        }
        // Move a fixed node into trailing free space
        if (last_fixed.flags.has_content) {
            const parent_file_offset = node.parent.fileLocation(mf, false).offset;
            try mf.moveRange(
                parent_file_offset + old_last_fixed_offset,
                parent_file_offset + new_last_fixed_offset,
                last_fixed_size,
            );
        }
        last_fixed_ni.setLocationAssumeCapacity(mf, new_last_fixed_offset, last_fixed_size);
        // Retry the previous nodes now that there is enough space
        first_floating_ni = last_fixed_ni;
        last_fixed_ni = last_fixed.prev;
        direction = .reverse;
    }
}

fn realignNode(
    mf: *MappedFile,
    gpa: std.mem.Allocator,
    ni: Node.Index,
    new_alignment: std.mem.Alignment,
    opts: Node.Index.RealignNodeOptions,
) (Allocator.Error || Io.Cancelable || IoError)!void {
    mf.nodes_lock.assertUnlocked();

    const node = ni.get(mf);
    {
        const prev_alignment = node.flags.alignment;
        node.flags.alignment = new_alignment;
        if (new_alignment.compare(.lte, prev_alignment)) return;
    }

    const old_offset, const size = node.location().resolve(mf);
    if (ni == Node.Index.root) return mf.resizeNode(gpa, ni, size);

    const new_size = new_alignment.forward(@intCast(size));
    if (new_alignment.check(@intCast(old_offset))) return mf.resizeNode(gpa, ni, new_size);

    _, const parent_size = node.parent.location(mf).resolve(mf);
    const trailing_end = trailing_end: switch (node.next) {
        .none => parent_size,
        else => |next_ni| {
            const next_offset, _ = next_ni.location(mf).resolve(mf);
            break :trailing_end next_offset;
        },
    };

    if (opts.try_backwards) {
        const backward_offset = new_alignment.backward(@intCast(old_offset));
        const prev_end = if (node.prev == .none) 0 else prev: {
            const prev_offset, const prev_size = node.prev.location(mf).resolve(mf);
            break :prev prev_offset + prev_size;
        };

        if (backward_offset >= prev_end) {
            try mf.ensureCapacityForSetLocation(gpa);

            if (node.flags.has_content) {
                const old_file_offset = ni.fileLocation(mf, false).offset;
                const new_file_offset = (old_file_offset - old_offset) + backward_offset;
                @memmove(
                    mf.memory_map.memory[@intCast(new_file_offset)..][0..@intCast(size)],
                    mf.memory_map.memory[@intCast(old_file_offset)..][0..@intCast(size)],
                );
                @memset(mf.memory_map.memory[@intCast(new_file_offset + size)..@intCast(old_file_offset + size)], 0);
            }

            if (backward_offset + new_size <= trailing_end) {
                ni.setLocationAssumeCapacity(mf, backward_offset, new_size);
            } else {
                ni.setLocationAssumeCapacity(mf, backward_offset, size);
                try mf.resizeNode(gpa, ni, new_size);
            }

            return;
        }
    }

    const forward_offset = new_alignment.forward(@intCast(old_offset));
    if (forward_offset + new_size <= trailing_end) {
        // Shift into the free space if possible
        try mf.ensureCapacityForSetLocation(gpa);
        if (node.flags.has_content) {
            const old_file_offset = ni.fileLocation(mf, false).offset;
            const new_file_offset = (old_file_offset - old_offset) + forward_offset;
            if (new_file_offset < old_file_offset + size) {
                @memmove(
                    mf.memory_map.memory[@intCast(new_file_offset)..][0..@intCast(size)],
                    mf.memory_map.memory[@intCast(old_file_offset)..][0..@intCast(size)],
                );
            } else try mf.moveRange(old_file_offset, new_file_offset, size);
            @memset(mf.memory_map.memory[@intCast(new_file_offset + size)..][0..@intCast(new_size - size)], 0);
        }

        ni.setLocationAssumeCapacity(mf, forward_offset, new_size);
    } else {
        const temp_size = new_alignment.forward(@intCast(new_size + 1));
        try mf.resizeNode(gpa, ni, temp_size);
        const new_offset, _ = ni.location(mf).resolve(mf);

        try mf.ensureCapacityForSetLocation(gpa);

        // Non-fixed nodes may now be aligned if the resize moved them
        const new_forward_offset = new_alignment.forward(@intCast(new_offset));
        const final_offset = if (new_forward_offset != new_offset) final_offset: {
            if (node.flags.has_content) {
                const old_file_offset = ni.fileLocation(mf, false).offset;
                const new_file_offset = (old_file_offset - new_offset) + new_forward_offset;
                @memmove(
                    mf.memory_map.memory[@intCast(new_file_offset)..][0..@intCast(size)],
                    mf.memory_map.memory[@intCast(old_file_offset)..][0..@intCast(size)],
                );
                @memset(mf.memory_map.memory[@intCast(old_file_offset)..@intCast(new_file_offset)], 0);
            }

            break :final_offset new_forward_offset;
        } else new_offset;

        ni.setLocationAssumeCapacity(mf, final_offset, new_size);
    }
}

fn updateWriters(mf: *MappedFile) void {
    var writers_it = mf.writers.first;
    while (writers_it) |writer_node| : (writers_it = writer_node.next) {
        const w: *Node.Writer = @fieldParentPtr("writer_node", writer_node);
        w.interface.buffer = w.ni.slice(mf);
    }
}

fn moveRange(mf: *MappedFile, old_file_offset: u64, new_file_offset: u64, size: u64) (Io.Cancelable || IoError)!void {
    // make a copy of this node at the new location
    try mf.copyRange(old_file_offset, new_file_offset, size);
    // delete the copy of this node at the old location
    if (is_linux and !mf.flags.fallocate_punch_hole_unsupported and
        size >= mf.flags.block_size.toByteUnits() * 2 - 1) while (true)
        switch (linux.errno(linux.fallocate(
            mf.memory_map.file.handle,
            linux.FALLOC.FL_PUNCH_HOLE | linux.FALLOC.FL_KEEP_SIZE,
            @intCast(old_file_offset),
            @intCast(size),
        ))) {
            .SUCCESS => return,
            .INTR => continue,
            .BADF, .FBIG, .INVAL => unreachable,
            .IO => return error.InputOutput,
            .NODEV => return error.NotFile,
            .NOSPC => return error.NoSpaceLeft,
            .NOSYS, .OPNOTSUPP => {
                mf.flags.fallocate_punch_hole_unsupported = true;
                break;
            },
            .PERM => return error.PermissionDenied,
            .SPIPE => return error.Unseekable,
            .TXTBSY => return error.FileBusy,
            else => |e| return std.posix.unexpectedErrno(e),
        };
    @memset(mf.memory_map.memory[@intCast(old_file_offset)..][0..@intCast(size)], 0);
}

fn copyRange(mf: *MappedFile, old_file_offset: u64, new_file_offset: u64, size: u64) (Io.Cancelable || IoError)!void {
    const copy_size = try mf.copyFileRange(mf.memory_map.file, old_file_offset, new_file_offset, size);
    if (copy_size < size) @memcpy(
        mf.memory_map.memory[@intCast(new_file_offset + copy_size)..][0..@intCast(size - copy_size)],
        mf.memory_map.memory[@intCast(old_file_offset + copy_size)..][0..@intCast(size - copy_size)],
    );
}

fn copyFileRange(
    mf: *MappedFile,
    old_file: Io.File,
    old_file_offset: u64,
    new_file_offset: u64,
    size: u64,
) (Io.Cancelable || IoError)!u64 {
    const io = mf.io;
    mf.memory_map.write(io) catch |err| switch (err) {
        error.WouldBlock => return error.Unexpected, // file was not opened as non-blocking
        error.NotOpenForWriting => return error.Unexpected, // we definitely opened the file for writing
        else => |e| return e,
    };
    var remaining_size = size;
    if (is_linux and !mf.flags.copy_file_range_unsupported) {
        var old_file_offset_mut: i64 = @intCast(old_file_offset);
        var new_file_offset_mut: i64 = @intCast(new_file_offset);
        while (remaining_size >= mf.flags.block_size.toByteUnits() * 2 - 1) {
            const copy_len = linux.copy_file_range(
                old_file.handle,
                &old_file_offset_mut,
                mf.memory_map.file.handle,
                &new_file_offset_mut,
                @intCast(remaining_size),
                0,
            );
            switch (linux.errno(copy_len)) {
                .SUCCESS => {
                    if (copy_len == 0) break;
                    remaining_size -= copy_len;
                    if (remaining_size == 0) break;
                },
                .INTR => continue,
                .BADF, .FBIG, .INVAL, .OVERFLOW => unreachable,
                .IO => return error.InputOutput,
                .ISDIR => return error.IsDir,
                .NOMEM => return error.SystemResources,
                .NOSPC => return error.NoSpaceLeft,
                .NOSYS, .OPNOTSUPP, .XDEV => {
                    mf.flags.copy_file_range_unsupported = true;
                    break;
                },
                .PERM => return error.PermissionDenied,
                .TXTBSY => return error.FileBusy,
                else => |e| return std.posix.unexpectedErrno(e),
            }
        }
    }
    return size - remaining_size;
}

fn ensureCapacityForSetLocation(mf: *MappedFile, gpa: std.mem.Allocator) Allocator.Error!void {
    try mf.large.ensureUnusedCapacity(gpa, 2);
    try mf.updates.ensureUnusedCapacity(gpa, 1);
}

pub fn ensureTotalCapacity(mf: *MappedFile, new_capacity: usize) Error!void {
    mf.ensureTotalCapacityInner(new_capacity) catch |err| switch (err) {
        error.OutOfMemory,
        error.Canceled,
        => |e| return e,

        else => |e| {
            mf.io_err = e;
            return error.MappedFileIo;
        },
    };
}
fn ensureTotalCapacityInner(mf: *MappedFile, new_capacity: usize) (Allocator.Error || Io.Cancelable || IoError)!void {
    if (mf.memory_map.memory.len >= new_capacity) return;
    try mf.ensureTotalCapacityPreciseInner(new_capacity +| new_capacity / growth_factor);
}

pub fn ensureTotalCapacityPrecise(mf: *MappedFile, new_capacity: usize) Error!void {
    mf.ensureTotalCapacityPreciseInner(new_capacity) catch |err| switch (err) {
        error.OutOfMemory,
        error.Canceled,
        => |e| return e,

        else => |e| {
            mf.io_err = e;
            return error.MappedFileIo;
        },
    };
}
fn ensureTotalCapacityPreciseInner(mf: *MappedFile, new_capacity: usize) (Allocator.Error || Io.Cancelable || IoError)!void {
    if (mf.memory_map.memory.len >= new_capacity) return;
    const io = mf.io;
    const aligned_capacity = mf.flags.block_size.forward(new_capacity);

    if (mf.memory_map.memory.len > 0) {
        if (mf.memory_map.setLength(io, aligned_capacity)) |_| {
            return;
        } else |err| switch (err) {
            error.OperationUnsupported => {},
            else => |e| return e,
        }

        mf.memory_map.write(io) catch |err| switch (err) {
            error.WouldBlock => return error.Unexpected, // file was not opened as non-blocking
            error.NotOpenForWriting => return error.Unexpected, // we definitely opened the file for writing
            else => |e| return e,
        };
        unmap(mf);
    }

    const file = mf.memory_map.file;
    mf.memory_map = Io.File.MemoryMap.create(io, file, .{ .len = aligned_capacity }) catch |err| switch (err) {
        error.WouldBlock => return error.Unexpected, // file was not opened as non-blocking
        error.NotOpenForReading => return error.Unexpected, // we definitely opened the file for writing
        else => |e| return e,
    };
}

pub fn unmap(mf: *MappedFile) void {
    if (mf.memory_map.memory.len == 0) return;
    const io = mf.io;
    const file = mf.memory_map.file;
    mf.memory_map.destroy(io);
    mf.memory_map.memory = &.{};
    mf.memory_map.file = file;
}

pub fn flush(mf: *MappedFile) (Io.Cancelable || error{MappedFileIo})!void {
    mf.flushInner() catch |err| switch (err) {
        error.Canceled => |e| return e,

        error.WouldBlock, // file was not opened as non-blocking
        error.NotOpenForWriting, // we definitely opened the file for writing
        error.ReadOnlyFileSystem,
        => {
            mf.io_err = error.Unexpected;
            return error.MappedFileIo;
        },

        else => |e| {
            mf.io_err = e;
            return error.MappedFileIo;
        },
    };
}

fn flushInner(mf: *MappedFile) (Io.File.WritePositionalError || Io.File.SetTimestampsError)!void {
    try mf.memory_map.write(mf.io);
    if (is_windows) try mf.memory_map.file.setTimestampsNow(mf.io);
}

fn verify(mf: *MappedFile) void {
    const root = Node.Index.root.get(mf);
    assert(root.parent == .none);
    assert(root.prev == .none);
    assert(root.next == .none);
    mf.verifyNode(Node.Index.root);
}

fn verifyNode(mf: *MappedFile, parent_ni: Node.Index) void {
    const parent = parent_ni.get(mf);
    const parent_offset, const parent_size = parent.location().resolve(mf);
    var prev_ni: Node.Index = .none;
    var prev_end: u64 = 0;
    var ni = parent.first;
    while (true) {
        if (ni == .none) {
            assert(parent.last == prev_ni);
            return;
        }
        const node = ni.get(mf);
        assert(node.parent == parent_ni);
        const offset, const size = node.location().resolve(mf);
        assert(node.flags.alignment.check(@intCast(offset)));
        assert(node.flags.alignment.check(@intCast(size)));
        const end = offset + size;
        assert(end <= parent_offset + parent_size);
        assert(offset >= prev_end);
        assert(node.prev == prev_ni);
        mf.verifyNode(ni);
        prev_ni = ni;
        prev_end = end;
        ni = node.next;
    }
}

const testing = std.testing;
fn testVerifyContent(mf: *@This(), ni: Node.Index, value: u8, init_len: usize) !void {
    // Not using std.mem.allEqual, so we can get useful output
    const slice = ni.slice(mf);
    var buf: [256]u8 = undefined;
    @memset(buf[0..init_len], value);
    @memset(buf[init_len..], 0);
    try testing.expectEqualSlices(u8, buf[0..slice.len], slice);
}

test {
    const gpa = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var file = try tmp_dir.dir.createFile(testing.io, "test.mf", .{ .read = true });
    defer file.close(testing.io);

    var mf = try init(file, gpa, testing.io);
    defer mf.deinit(gpa);

    const a = try mf.addFirstChildNode(gpa, .root, .{ .fixed = true, .alignment = .@"4" });
    const c = try mf.addLastChildNode(gpa, .root, .{ .fixed = true, .alignment = .@"4" });
    const b = try mf.addNodeAfter(gpa, a, .{ .fixed = true, .alignment = .@"16" });
    const d = try mf.addNodeAfter(gpa, b, .{ .alignment = .@"4" });

    const a_init_size = 8;
    const b_init_size = 16;
    const c_init_size = 24;
    const d_init_size = 28;

    // Resize without content
    {
        // Verify size is aligned forward
        try d.resize(&mf, gpa, d_init_size - 1);
        try a.resize(&mf, gpa, a_init_size - 2);
        try c.resize(&mf, gpa, c_init_size);
        try b.resize(&mf, gpa, b_init_size);
        mf.verify();

        const a_loc, const a_size = a.location(&mf).resolve(&mf);
        const b_loc, const b_size = b.location(&mf).resolve(&mf);
        const c_loc, const c_size = c.location(&mf).resolve(&mf);
        _, const d_size = d.location(&mf).resolve(&mf);
        try testing.expect(a_size >= a_init_size);
        try testing.expect(b_size >= b_init_size);
        try testing.expect(c_size >= c_init_size);
        try testing.expect(d_size >= d_init_size);
        try testing.expect(b_loc >= a_loc + a_size);
        try testing.expect(c_loc >= b_loc + b_size);
    }

    const a_exp_size = 24;
    const b_exp_size = 28;
    const c_exp_size = 48;
    const d_exp_size = 32;

    // Resize with content
    {
        @memset(a.slice(&mf)[0..a_init_size], 0xaa);
        @memset(b.slice(&mf)[0..b_init_size], 0xbb);
        @memset(c.slice(&mf)[0..c_init_size], 0xcc);
        @memset(d.slice(&mf)[0..d_init_size], 0xdd);

        try a.resize(&mf, gpa, a_exp_size);
        try b.resize(&mf, gpa, b_exp_size);
        try c.resize(&mf, gpa, c_exp_size);
        try d.resize(&mf, gpa, d_exp_size);
        mf.verify();

        const a_loc, const a_size = a.location(&mf).resolve(&mf);
        const b_loc, const b_size = b.location(&mf).resolve(&mf);
        const c_loc, const c_size = c.location(&mf).resolve(&mf);
        _, const d_size = d.location(&mf).resolve(&mf);
        try testing.expect(a_size >= a_exp_size);
        try testing.expect(b_size >= b_exp_size);
        try testing.expect(c_size >= c_exp_size);
        try testing.expect(d_size >= d_exp_size);
        try testing.expect(b_loc >= a_loc + a_size);
        try testing.expect(c_loc >= b_loc + b_size);

        try testVerifyContent(&mf, a, 0xaa, a_init_size);
        try testVerifyContent(&mf, b, 0xbb, b_init_size);
        try testVerifyContent(&mf, c, 0xcc, c_init_size);
        try testVerifyContent(&mf, d, 0xdd, d_init_size);
    }

    const child_init: []const struct { std.mem.Alignment, usize } = &.{
        .{ .@"16", 16 },
        .{ .@"1", 1 },
        .{ .@"1", 19 },
        .{ .@"1", 3 },
        .{ .@"8", 30 },
        .{ .@"2", 5 },
        .{ .@"1", 60 },
        .{ .@"2", 2 },
        .{ .@"16", 32 },
    };

    var children: [child_init.len]Node.Index = undefined;

    // Differently-aligned fixed sibling nodes
    {
        for (children[0 .. children.len - 1], child_init[0 .. children.len - 1], 0..) |*ni, opts, i| {
            ni.* = try mf.addLastChildNode(gpa, b, .{
                .alignment = opts.@"0",
                .size = opts.@"1",
                .fixed = true,
            });

            @memset(ni.slice(&mf)[0..opts.@"1"], @intCast(i + 1));
        }
        // Shift differently-aligned nodes by inserting a node
        children[children.len - 1] = try mf.addNodeAfter(gpa, children[3], .{
            .alignment = child_init[children.len - 1].@"0",
            .size = child_init[children.len - 1].@"1",
            .fixed = true,
        });
        @memset(children[children.len - 1].slice(&mf), @intCast(children.len));

        mf.verify();
        for (children, child_init, 0..) |ni, opts, i| {
            try testVerifyContent(&mf, ni, @intCast(i + 1), opts.@"1");
        }
    }

    // Shifting child nodes forward due via resize of parent.prev
    {
        try testing.expect(a.location(&mf).resolve(&mf)[1] < 64);
        try a.resize(&mf, gpa, 64);

        try testVerifyContent(&mf, a, 0xaa, a_init_size);
        try testVerifyContent(&mf, c, 0xcc, c_init_size);
        try testVerifyContent(&mf, d, 0xdd, d_init_size);
        for (children, child_init, 0..) |ni, opts, i| {
            try testVerifyContent(&mf, ni, @intCast(i + 1), opts.@"1");
        }
    }

    // Re-align last node into trailing free space within parent
    {
        try b.resize(&mf, gpa, b.location(&mf).resolve(&mf)[1] + 64);

        const last = children[children.len - 2];
        try last.realign(&mf, gpa, .@"4", true);
        mf.verify();

        for (children, child_init, 0..) |ni, opts, i|
            try testVerifyContent(&mf, ni, @intCast(i + 1), opts.@"1");
        try testVerifyContent(&mf, c, 0xcc, c_init_size);
    }

    // Re-align, shifting sibling nodes
    {
        try children[1].realign(&mf, gpa, .@"8", true);
        mf.verify();

        for (children, child_init, 0..) |ni, opts, i|
            try testVerifyContent(&mf, ni, @intCast(i + 1), opts.@"1");
        try testVerifyContent(&mf, c, 0xcc, c_init_size);
    }

    // Shrink and shift start of trailing node into free space
    {
        try mf.shrinkNode(gpa, a, 16, true);
        mf.verify();

        const a_loc, const a_size = a.location(&mf).resolve(&mf);
        const b_loc, _ = b.location(&mf).resolve(&mf);
        try testing.expectEqual(b_loc, a_loc + a_size);

        try testVerifyContent(&mf, a, 0xaa, a_init_size);
        try testVerifyContent(&mf, c, 0xcc, c_init_size);
        try testVerifyContent(&mf, d, 0xdd, d_init_size);
        for (children, child_init, 0..) |ni, opts, i| {
            try testVerifyContent(&mf, ni, @intCast(i + 1), opts.@"1");
        }
    }
}
