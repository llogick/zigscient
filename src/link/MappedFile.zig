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
    block_size: Alignment,
    copy_file_range_unsupported: bool,
    fallocate_punch_hole_unsupported: bool,
    fallocate_insert_range_unsupported: bool,
},
memory_map: Io.File.MemoryMap,
nodes: std.ArrayList(Node),
free_ni: Node.Index.Optional,
large: std.ArrayList(u64),
updates: std.ArrayList(Node.Index),
/// This progress node's estimated total items is increased once for each node appended to `updates`.
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

/// This separate `Alignment` type exists because neither of the other options is really suitable:
///
/// * `std.mem.Alignment` is based on `usize`, which---while technically okay since the file is
///   memory-mapped---is in practice very annoying to work with in linker implementations
///
/// * `InternPool.Alignment` is based on `u64`, which is better, but it has the value `.none`, which
///   is also really annoying to handle, because no alignment is ever nullable in this API
///
/// At some point we should probably just change `InternPool.Alignment` to be non-optional, and add
/// a new `InternPool.Alignment.Optional` type for the case where it can actually be `.none`. At
/// that point we can transition this code to using `InternPool.Alignment` (although it should
/// probably be namespaced elsewhere, it has nothing to do with the `InternPool`!).
pub const Alignment = enum(u6) {
    @"1" = 0,
    @"2" = 1,
    @"4" = 2,
    @"8" = 3,
    @"16" = 4,
    @"32" = 5,
    @"64" = 6,
    _,

    pub fn fromIp(a: @import("../InternPool.zig").Alignment) Alignment {
        assert(a != .none);
        return @bitCast(a);
    }

    pub fn toLog2Units(a: Alignment) u6 {
        return @backingInt(a);
    }

    pub fn fromLog2Units(a: u6) Alignment {
        return @fromBackingInt(a);
    }

    pub fn toByteUnits(a: Alignment) u64 {
        return @as(u64, 1) << @backingInt(a);
    }

    pub fn fromByteUnits(n: u64) Alignment {
        assert(std.math.isPowerOfTwo(n));
        return @fromBackingInt(@intCast(@ctz(n)));
    }

    pub fn order(lhs: Alignment, rhs: Alignment) std.math.Order {
        return std.math.order(@backingInt(lhs), @backingInt(rhs));
    }

    pub fn compare(lhs: Alignment, op: std.math.CompareOperator, rhs: Alignment) bool {
        return std.math.compare(@backingInt(lhs), op, @backingInt(rhs));
    }

    pub fn max(lhs: Alignment, rhs: Alignment) Alignment {
        return @fromBackingInt(@max(@backingInt(lhs), @backingInt(rhs)));
    }

    pub fn min(lhs: Alignment, rhs: Alignment) Alignment {
        return @fromBackingInt(@min(@backingInt(lhs), @backingInt(rhs)));
    }

    pub inline fn of(comptime T: type) Alignment {
        return comptime .fromByteUnits(@alignOf(T));
    }

    /// Given that a base address is known to be aligned to `a`, computes the known alignment of
    /// that base address plus `off`.
    pub fn offset(a: Alignment, off: u64) Alignment {
        return .fromLog2Units(@min(a.toLog2Units(), @ctz(off)));
    }

    /// Align an address forwards to this alignment.
    pub fn forward(a: Alignment, addr: u64) u64 {
        const x = (@as(u64, 1) << @backingInt(a)) - 1;
        return (addr + x) & ~x;
    }

    /// Align an address backwards to this alignment.
    pub fn backward(a: Alignment, addr: u64) u64 {
        const x = (@as(u64, 1) << @backingInt(a)) - 1;
        return addr & ~x;
    }

    /// Check if an address is aligned to this amount.
    pub fn check(a: Alignment, addr: u64) bool {
        return @ctz(addr) >= @backingInt(a);
    }
};

pub fn init(file: Io.File, gpa: Allocator, io: Io) (Allocator.Error || Io.Cancelable || IoError)!MappedFile {
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

    const root_location: Node.Location = l: {
        if (std.math.cast(u32, size)) |small_size| {
            break :l .{ .small = .{ .offset = 0, .size = small_size } };
        }
        try mf.large.appendSlice(gpa, &.{ 0, size });
        break :l .{ .large = .{ .index = 0 } };
    };
    try mf.nodes.append(gpa, .{
        .parent = .none,
        .prev = .none,
        .next = .none,
        .first = .none,
        .last = .none,
        .flags = .{
            .alignment = mf.flags.block_size,
            .position = .floating,
            .bubbles_moved = true,
            .enable_next_moved = false,
            .location_tag = root_location,
            .moved = false,
            .resized = false,
            .next_moved = false,
            .has_content = false,
        },
        .location_payload = switch (root_location) {
            .small => |small| .{ .small = small },
            .large => |large| .{ .large = large },
        },
    });

    mf.ensureTotalCapacity(@intCast(size)) catch |err| switch (err) {
        error.MappedFileIo => return mf.io_err.?,
        else => |e| return e,
    };

    return mf;
}

pub fn deinit(mf: *MappedFile, gpa: Allocator) void {
    mf.unmap();
    mf.nodes.deinit(gpa);
    mf.large.deinit(gpa);
    mf.updates.deinit(gpa);
    mf.update_prog_node.end();
    assert(mf.writers.first == null);
    mf.* = undefined;
}

pub const Node = extern struct {
    parent: Node.Index.Optional,
    prev: Node.Index.Optional,
    next: Node.Index.Optional,
    first: Node.Index.Optional,
    last: Node.Index.Optional,
    flags: Flags,
    location_payload: Location.Payload,

    /// Any non-leaf node may designate its first N children as "header" nodes. This means that its
    /// first N children must be densely packed together and positioned at the start of the parent.
    /// The implementation guarantees that it will never re-order these nodes, nor will it introduce
    /// padding between them.
    ///
    /// Likewise, any non-leaf node may designate its *last* M children as "footer" nodes, which are
    /// like header nodes except they are positioned at the *end* of the parent rather than the
    /// start.
    ///
    /// Nodes which are neither headers nor footers are called "floating". The implementation is
    /// always free to re-order floating nodes relative to one another, and to add or remove padding
    /// between them.
    pub const Position = enum(u2) {
        header,
        footer,
        floating,
    };

    pub const Flags = packed struct(u32) {
        /// While the number of header and footer nodes within a parent node is logically a part of
        /// that parent, we actually store this information on the child nodes for efficiency: this
        /// field indicates whether each child is a header node, a footer node, or a floating node.
        ///
        /// This value is meaningless for the root node, so is arbitrarily set to `.floating`.
        position: Position,
        /// For floating nodes, this node's offset into its parent will always be aligned to this
        /// boundary. (This is not the case for header and footer nodes due to the requirement that
        /// they be densely packed against the start/end of the parent node.)
        ///
        /// This node's size will also always be aligned to this boundary. (This applies regardless
        /// of whether this is a floating node, a header node, or a footer node.)
        alignment: Alignment,
        /// Whether `moved` events on this node bubble down to children.
        bubbles_moved: bool,
        /// Whether `next_moved` events are reported in `updates`.
        enable_next_moved: bool,

        location_tag: Location.Tag,
        /// Whether this node has been moved.
        moved: bool,
        /// Whether this node has been resized.
        resized: bool,
        /// Whether the next sibling has moved or is a different node.
        next_moved: bool,
        /// Whether this node might contain initialized bytes.
        has_content: bool,
        unused: u17 = 0,
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

    pub const AddOptions = struct {
        /// Must be aligned to the given `alignment`.
        size: u64 = 0,
        alignment: Alignment = .@"1",
        bubbles_moved: bool = true,
        enable_next_moved: bool = false,

        moved: bool = false,
        resized: bool = false,
        next_moved: bool = false,
    };

    pub const Index = enum(u32) {
        root,
        _,

        pub const Optional = enum(u32) {
            none = std.math.maxInt(u32),
            _,

            pub fn unwrap(oi: Optional) ?Index {
                return switch (oi) {
                    _ => @fromBackingInt(@backingInt(oi)),
                    .none => null,
                };
            }
            pub fn wrap(i: Index) Optional {
                const oi: Optional = @bitCast(i);
                assert(oi != .none);
                return oi;
            }
        };

        fn get(ni: Node.Index, mf: *const MappedFile) *Node {
            return &mf.nodes.items[@backingInt(ni)];
        }

        /// Adds a floating child node to `parent_ni`. Returns the index of the new child.
        pub fn addFloatingChild(parent_ni: Node.Index, gpa: Allocator, mf: *MappedFile, opts: AddOptions) Error!Node.Index {
            return mf.addNode(gpa, .{
                .add_options = opts,
                .position = .floating,
                .parent = parent_ni,
                .prev = parent_ni.lastHeader(mf),
            });
        }
        /// Adds a header child node to `parent_ni`. Returns the index of the new child.
        ///
        /// Asserts that `parent_ni` has no existing header children.
        pub fn addOnlyHeaderChild(parent_ni: Node.Index, gpa: Allocator, mf: *MappedFile, opts: AddOptions) Error!Node.Index {
            if (parent_ni.first(mf).unwrap()) |first_ni| {
                assert(first_ni.position(mf) != .header); // `parent_ni` already has a header child
            }
            return parent_ni.addHeaderChildAfter(gpa, mf, .none, opts);
        }
        /// Adds a header child node to `parent_ni`. Returns the index of the new child.
        ///
        /// If `prev_oni` is `.none`, the new child is placed at the very start of the parent,
        /// before any existing header nodes.
        ///
        /// Otherwise, asserts that `prev_oni` is a header node and a child of `parent_ni`, and
        /// places the new child node immediately after `prev_oni`.
        pub fn addHeaderChildAfter(parent_ni: Node.Index, gpa: Allocator, mf: *MappedFile, prev_oni: Node.Index.Optional, opts: AddOptions) Error!Node.Index {
            return mf.addNode(gpa, .{
                .add_options = opts,
                .position = .header,
                .parent = parent_ni,
                .prev = prev_oni,
            });
        }
        /// Adds a footer child node to `parent_ni`. Returns the index of the new child.
        ///
        /// Asserts that `parent_ni` has no existing footer children.
        pub fn addOnlyFooterChild(parent_ni: Node.Index, gpa: Allocator, mf: *MappedFile, opts: AddOptions) Error!Node.Index {
            if (parent_ni.last(mf).unwrap()) |last_ni| {
                assert(last_ni.position(mf) != .footer); // `parent_ni` already has a footer child
            }
            return parent_ni.addFooterChildBefore(gpa, mf, .none, opts);
        }
        /// Adds a footer child node to `parent_ni`. Returns the index of the new child.
        ///
        /// If `next_oni` is `.none`, the new child is placed at the very end of the parent, after
        /// any existing footer nodes.
        ///
        /// Otherwise, asserts that `next_oni` is a footer node and a child of `parent_ni`, and
        /// places the new child node immediately before `next_oni`.
        pub fn addFooterChildBefore(parent_ni: Node.Index, gpa: Allocator, mf: *MappedFile, next_oni: Node.Index.Optional, opts: AddOptions) Error!Node.Index {
            const prev_oni: Node.Index.Optional = prev: {
                const next_ni = next_oni.unwrap() orelse {
                    break :prev parent_ni.last(mf);
                };
                break :prev next_ni.prev(mf);
            };
            return mf.addNode(gpa, .{
                .add_options = opts,
                .position = .footer,
                .parent = parent_ni,
                .prev = prev_oni,
            });
        }

        /// Alias for `Optional.wrap`, provided for convenience when a result type is not available.
        pub const toOptional = Optional.wrap;

        pub fn parent(ni: Node.Index, mf: *const MappedFile) Node.Index.Optional {
            return ni.get(mf).parent;
        }

        pub fn first(ni: Node.Index, mf: *const MappedFile) Node.Index.Optional {
            return ni.get(mf).first;
        }

        pub fn last(ni: Node.Index, mf: *const MappedFile) Node.Index.Optional {
            return ni.get(mf).last;
        }

        fn lastHeader(ni: Node.Index, mf: *const MappedFile) Node.Index.Optional {
            var header_ni = ni.first(mf).unwrap() orelse return .none;
            if (header_ni.position(mf) != .header) return .none;
            while (true) {
                const next_ni = header_ni.next(mf).unwrap() orelse break;
                if (next_ni.position(mf) != .header) break;
                header_ni = next_ni;
            }
            return .wrap(header_ni);
        }
        fn firstFooter(ni: Node.Index, mf: *const MappedFile) Node.Index.Optional {
            var footer_ni = ni.last(mf).unwrap() orelse return .none;
            if (footer_ni.position(mf) != .footer) return .none;
            while (true) {
                const prev_ni = footer_ni.prev(mf).unwrap() orelse break;
                if (prev_ni.position(mf) != .footer) break;
                footer_ni = prev_ni;
            }
            return .wrap(footer_ni);
        }

        /// Asserts that `ni` is not `.root`, because `Position` is meaningless for the root node.
        pub fn position(ni: Node.Index, mf: *const MappedFile) Node.Position {
            assert(ni != .root);
            return ni.get(mf).flags.position;
        }

        pub fn next(ni: Node.Index, mf: *const MappedFile) Node.Index.Optional {
            return ni.get(mf).next;
        }
        fn setNext(
            ni: Node.Index,
            gpa: Allocator,
            mf: *MappedFile,
            next_ni: Node.Index.Optional,
        ) Allocator.Error!void {
            const next_ptr = &ni.get(mf).next;
            if (next_ptr.* == next_ni) return;
            next_ptr.* = next_ni;
            try ni.nextMoved(gpa, mf);
        }

        pub fn prev(ni: Node.Index, mf: *const MappedFile) Node.Index.Optional {
            return ni.get(mf).prev;
        }

        pub fn childrenMoved(ni: Node.Index, gpa: Allocator, mf: *MappedFile) Allocator.Error!void {
            var child_oni = ni.get(mf).last;
            while (child_oni.unwrap()) |child_ni| {
                try child_ni.moved(gpa, mf);
                child_oni = child_ni.get(mf).prev;
            }
        }

        pub fn hasMoved(ni: Node.Index, mf: *const MappedFile) bool {
            var parent_ni = ni;
            while (parent_ni != .root) {
                const parent_node = parent_ni.get(mf);
                if (!parent_node.flags.bubbles_moved) break;
                if (parent_node.flags.moved) return true;
                parent_ni = parent_node.parent.unwrap().?;
            }
            return false;
        }
        pub fn moved(ni: Node.Index, gpa: Allocator, mf: *MappedFile) Allocator.Error!void {
            try mf.updates.ensureUnusedCapacity(gpa, 2);
            ni.movedAssumeCapacity(mf);
        }
        pub fn cleanMoved(ni: Node.Index, mf: *MappedFile) bool {
            const node_moved = &ni.get(mf).flags.moved;
            defer node_moved.* = false;
            return node_moved.*;
        }
        pub fn movedAssumeCapacity(ni: Node.Index, mf: *MappedFile) void {
            const node = ni.get(mf);
            if (node.prev.unwrap()) |prev_ni| prev_ni.nextMovedAssumeCapacity(mf);
            if (ni.hasMoved(mf)) return;
            node.flags.moved = true;
            if (node.flags.resized or node.flags.next_moved) return;
            mf.updates.appendAssumeCapacity(ni);
            mf.update_prog_node.increaseEstimatedTotalItems(1);
        }

        pub fn hasResized(ni: Node.Index, mf: *const MappedFile) bool {
            return ni.get(mf).flags.resized;
        }
        pub fn resized(ni: Node.Index, gpa: Allocator, mf: *MappedFile) Allocator.Error!void {
            try mf.updates.ensureUnusedCapacity(gpa, 1);
            ni.resizedAssumeCapacity(mf);
        }
        pub fn cleanResized(ni: Node.Index, mf: *MappedFile) bool {
            const node_resized = &ni.get(mf).flags.resized;
            defer node_resized.* = false;
            return node_resized.*;
        }
        pub fn resizedAssumeCapacity(ni: Node.Index, mf: *MappedFile) void {
            const node = ni.get(mf);
            if (node.flags.resized) return;
            node.flags.resized = true;
            if (node.flags.moved or node.flags.next_moved) return;
            mf.updates.appendAssumeCapacity(ni);
            mf.update_prog_node.increaseEstimatedTotalItems(1);
        }

        pub fn hasNextMoved(ni: Node.Index, mf: *const MappedFile) bool {
            return ni.get(mf).flags.next_moved;
        }
        pub fn nextMoved(ni: Node.Index, gpa: Allocator, mf: *MappedFile) Allocator.Error!void {
            try mf.updates.ensureUnusedCapacity(gpa, 1);
            ni.nextMovedAssumeCapacity(mf);
        }
        pub fn cleanNextMoved(ni: Node.Index, mf: *MappedFile) bool {
            const node_next_moved = &ni.get(mf).flags.next_moved;
            defer node_next_moved.* = false;
            return node_next_moved.*;
        }
        pub fn nextMovedAssumeCapacity(ni: Node.Index, mf: *MappedFile) void {
            const node = ni.get(mf);
            if (!node.flags.enable_next_moved or node.flags.next_moved) return;
            node.flags.next_moved = true;
            if (node.flags.moved or node.flags.resized) return;
            mf.updates.appendAssumeCapacity(ni);
            mf.update_prog_node.increaseEstimatedTotalItems(1);
        }

        pub fn alignment(ni: Node.Index, mf: *const MappedFile) Alignment {
            return ni.get(mf).flags.alignment;
        }

        fn setLocation(ni: Node.Index, gpa: Allocator, mf: *MappedFile, offset: u64, size: u64) Allocator.Error!void {
            try mf.large.ensureUnusedCapacity(gpa, 2);
            try mf.updates.ensureUnusedCapacity(gpa, 2);
            const node = ni.get(mf);
            if (node.flags.position == .floating) {
                assert(node.flags.alignment.check(offset));
            }
            assert(node.flags.alignment.check(size));
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
                if (parent_ni == .root) {
                    assert(parent_node.parent == .none);
                    break;
                }
                parent_ni = parent_node.parent.unwrap().?;
                const parent_offset, _ = parent_ni.location(mf).resolve(mf);
                offset += parent_offset;
            }
            return .{ .offset = offset, .size = size };
        }

        pub fn slice(ni: Node.Index, mf: *const MappedFile) []u8 {
            const file_loc = ni.fileLocation(mf, true);
            return mf.memory_map.memory[@intCast(file_loc.offset)..][0..@intCast(file_loc.size)];
        }

        pub fn slicePadding(ni: Node.Index, mf: *const MappedFile) []u8 {
            const file_loc = ni.fileLocation(mf, false);
            return mf.memory_map.memory[@intCast(file_loc.offset)..][0..@intCast(file_loc.size)];
        }

        pub fn sliceConst(ni: Node.Index, mf: *const MappedFile) []const u8 {
            const file_loc = ni.fileLocation(mf, false);
            return mf.memory_map.memory[@intCast(file_loc.offset)..][0..@intCast(file_loc.size)];
        }

        pub fn delete(ni: Node.Index, gpa: Allocator, mf: *MappedFile) Allocator.Error!void {
            const node = ni.get(mf);
            assert(node.first == .none and node.last == .none); // has children
            mf.removeNodesFromChildList(gpa, ni, ni);
            const updated = node.flags.moved or node.flags.resized or node.flags.next_moved;
            node.* = undefined;
            node.next = ni.toOptional();
            if (!updated) assert(ni.pendingDelete(mf));
        }

        pub fn pendingDelete(ni: Node.Index, mf: *MappedFile) bool {
            const node = ni.get(mf);
            if (node.next != ni.toOptional()) return false;
            node.next = mf.free_ni;
            mf.free_ni = ni.toOptional();
            return true;
        }

        /// Ensures that the size of `ni` is at least `min_size`. Valid for any node.
        ///
        /// Applies `growth_factor` if necessary (so the caller should *not* apply `growth_factor`).
        pub fn ensureMinimumSize(ni: Node.Index, gpa: Allocator, mf: *MappedFile, min_size: u64) Error!void {
            _, const current_size = ni.location(mf).resolve(mf);
            if (current_size >= min_size) return;
            const new_size = ni.alignment(mf).forward(min_size +| min_size / growth_factor);
            try mf.growNode(gpa, ni, new_size, .{
                .exact_size = false,
                .move_footers = true,
            });
            mf.updateWriters();
        }

        /// Sets the size of `ni` to exactly `size`.
        ///
        /// Asserts that `ni` is a leaf node, i.e. has no children.
        ///
        /// Asserts that `size` is aligned to `ni.alignment(mf)`.
        pub fn resizeLeaf(ni: Node.Index, gpa: Allocator, mf: *MappedFile, size: u64) Error!void {
            assert(ni.first(mf) == .none);
            // The alignment of `size` is asserted by `shrinkLeafNode` and `growNode`.
            _, const old_size = ni.location(mf).resolve(mf);
            switch (std.math.order(size, old_size)) {
                .lt => try mf.shrinkLeafNode(gpa, ni, size),
                .eq => {}, // `old_size` must be well-aligned, so `size` is too
                .gt => try mf.growNode(gpa, ni, size, .{
                    .exact_size = true,
                    .move_footers = false, // irrelevant, since we have no footers
                }),
            }
            mf.updateWriters();
        }

        /// Updates a node's alignment to exactly `new_alignment`. Valid for any node.
        ///
        /// If the node's current offset or size is not sufficiently aligned, it will be moved
        /// and/or resized to match the new alignment. The node's size may be increased by any
        /// amount, as if `ensureMinimumSize` were used.
        pub fn realign(ni: Node.Index, gpa: Allocator, mf: *MappedFile, new_alignment: Alignment) Error!void {
            try mf.realignNode(gpa, ni, new_alignment);
            mf.updateWriters();
        }

        pub fn writer(ni: Node.Index, gpa: Allocator, mf: *MappedFile, w: *Writer) void {
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
        gpa: Allocator,
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
                    ) catch |err| {
                        w.err = err;
                        return error.WriteFailed;
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
            const w: *Writer = @fieldParentPtr("interface", interface);
            w.ni.ensureMinimumSize(w.gpa, w.mf, interface.end + unused_capacity) catch |err| {
                w.err = err;
                return error.WriteFailed;
            };
        }
    };

    comptime {
        if (!std.debug.runtime_safety) assert(@sizeOf(Node) == 32);
    }
};

/// Asserts that `opts.position` is compatible with `opts.prev` (i.e. that this addition will not
/// violate the requirement that header nodes come before floating nodes come before footer nodes).
fn addNode(mf: *MappedFile, gpa: Allocator, opts: struct {
    add_options: Node.AddOptions,
    position: Node.Position,
    parent: Node.Index,
    /// If `position == .floating`, this is just used as an initial value, and may be immediately
    /// replaced when finding a location for this node. In this case, it is still necessary that
    /// `prev` be compatible with `position` (so `prev` must be either a floating node or the last
    /// header node in `parent`).
    prev: Node.Index.Optional,
}) Error!Node.Index {
    mf.nodes_lock.assertUnlocked();

    try mf.nodes.ensureUnusedCapacity(gpa, 1);
    try mf.large.ensureUnusedCapacity(gpa, 2);

    const new_ni: Node.Index = new: {
        if (mf.free_ni.unwrap()) |free_ni| {
            mf.free_ni = free_ni.get(mf).next;
            break :new free_ni;
        }
        const new_ni: Node.Index = @fromBackingInt(@intCast(mf.nodes.items.len));
        _ = mf.nodes.addOneAssumeCapacity();
        break :new new_ni;
    };

    const next_oni: Node.Index.Optional = if (opts.prev.unwrap()) |prev_ni| next: {
        assert(prev_ni.parent(mf) == opts.parent.toOptional()); // `prev` is not a child of `parent`
        break :next prev_ni.get(mf).next;
    } else opts.parent.first(mf);

    // Validate node ordering
    switch (opts.position) {
        .floating => {
            if (opts.prev.unwrap()) |prev_ni| {
                assert(prev_ni.position(mf) != .footer); // tried to add floating node after footer node
            }
            if (next_oni.unwrap()) |next_ni| {
                assert(next_ni.position(mf) != .header); // tried to add floating node before header node
            }
        },
        .header => if (opts.prev.unwrap()) |prev_ni| {
            switch (prev_ni.position(mf)) {
                .header => {},
                .floating => unreachable, // tried to add header node after floating node
                .footer => unreachable, // tried to add header node after footer node
            }
        },
        .footer => if (next_oni.unwrap()) |next_ni| {
            switch (next_ni.position(mf)) {
                .header => unreachable, // tried to add footer node before header node
                .floating => unreachable, // tried to add footer node before floating node
                .footer => {},
            }
        },
    }

    // Initialize the node as empty with alignment 1
    const location: Node.Location = loc: {
        const offset: u64 = switch (opts.position) {
            .header, .floating => offset: {
                const prev_ni = opts.prev.unwrap() orelse break :offset 0;
                const prev_offset, const prev_size = prev_ni.location(mf).resolve(mf);
                break :offset prev_offset + prev_size;
            },
            .footer => offset: {
                const next_ni = next_oni.unwrap() orelse {
                    _, const parent_size = opts.parent.location(mf).resolve(mf);
                    break :offset parent_size;
                };
                const next_offset, _ = next_ni.location(mf).resolve(mf);
                break :offset next_offset;
            },
        };
        if (std.math.cast(u32, offset)) |small_offset| {
            break :loc .{ .small = .{ .offset = small_offset, .size = 0 } };
        }
        const large_index = mf.large.items.len;
        mf.large.appendSliceAssumeCapacity(&.{ offset, 0 });
        break :loc .{ .large = .{ .index = large_index } };
    };
    new_ni.get(mf).* = .{
        .parent = .wrap(opts.parent),
        .prev = .none,
        .next = .none,
        .first = .none,
        .last = .none,
        .flags = .{
            .position = opts.position,
            .alignment = .@"1",
            .bubbles_moved = opts.add_options.bubbles_moved,
            .enable_next_moved = opts.add_options.enable_next_moved,
            .location_tag = location,
            .moved = false,
            .resized = false,
            .next_moved = false,
            .has_content = false,
        },
        .location_payload = switch (location) {
            .small => |small| .{ .small = small },
            .large => |large| .{ .large = large },
        },
    };

    try mf.addNodesToChildListBefore(gpa, next_oni, new_ni, new_ni);

    try mf.realignNode(gpa, new_ni, opts.add_options.alignment);
    if (opts.add_options.size > 0) {
        try mf.growNode(gpa, new_ni, opts.add_options.size, .{
            .exact_size = true,
            .move_footers = false, // irrelevant, since we have no footers
        });
    }
    mf.updateWriters();

    new_ni.get(mf).flags.moved = false;
    new_ni.get(mf).flags.resized = false;
    new_ni.get(mf).flags.next_moved = false;

    if (opts.add_options.moved) try new_ni.moved(gpa, mf);
    if (opts.add_options.resized) try new_ni.resized(gpa, mf);
    if (opts.add_options.next_moved) try new_ni.nextMoved(gpa, mf);

    return new_ni;
}

fn shrinkLeafNode(
    mf: *MappedFile,
    gpa: Allocator,
    ni: Node.Index,
    new_size: u64,
) Error!void {
    mf.nodes_lock.assertUnlocked();

    const old_offset, const old_size = ni.location(mf).resolve(mf);

    assert(new_size < old_size);
    assert(ni.alignment(mf).check(new_size));
    assert(ni.first(mf) == .none); // `ni` must be a leaf node

    const parent_ni = ni.parent(mf).unwrap() orelse {
        assert(ni == .root);
        mf.memory_map.write(mf.io) catch |err| {
            mf.io_err = switch (err) {
                error.Canceled => |e| return e,
                error.WouldBlock => error.Unexpected, // file was not opened as non-blocking
                error.NotOpenForWriting => error.Unexpected, // we definitely opened the file for writing
                else => |e| e,
            };
            return error.MappedFileIo;
        };
        mf.memory_map.file.setLength(mf.io, new_size) catch |err| switch (err) {
            error.Canceled => |e| return e,
            else => |e| {
                mf.io_err = e;
                return error.MappedFileIo;
            },
        };
        try mf.ensureTotalCapacityPrecise(@intCast(new_size));
        try ni.setLocation(gpa, mf, old_offset, new_size);
        return;
    };

    switch (ni.position(mf)) {
        .header => {
            const shift = old_size - new_size;

            try ni.setLocation(gpa, mf, old_offset, new_size);

            // We need to shift backwards all header nodes following us.
            const next_header_ni = ni.next(mf).unwrap() orelse return;
            if (next_header_ni.position(mf) != .header) return;

            var header_ni = next_header_ni;
            while (true) {
                const old_header_off, const old_header_size = header_ni.location(mf).resolve(mf);
                try header_ni.setLocation(gpa, mf, old_header_off - shift, old_header_size);

                const next_ni = header_ni.next(mf).unwrap() orelse break;
                if (next_ni.position(mf) != .header) break;
                header_ni = next_ni;
            }

            // Now we must shift the actual header bytes of those nodes backwards.
            const parent_file_off = parent_ni.fileLocation(mf, false).offset;
            const move_src_off = old_offset + old_size;
            const move_dest_off = old_offset + new_size;
            assert(next_header_ni.location(mf).resolve(mf)[0] == move_dest_off); // `move_dest_off` because we already updated the location
            const move_size = size: {
                // `header_ni` is the last header in the parent.
                const last_off, const last_size = header_ni.location(mf).resolve(mf);
                const move_end = last_off + last_size;
                break :size move_end - move_dest_off; // `move_dest_off` because we already updated the location
            };
            try mf.moveRange(
                parent_file_off + move_src_off,
                parent_file_off + move_dest_off,
                move_size,
            );
        },
        .floating => {
            try ni.setLocation(gpa, mf, old_offset, new_size);
        },
        .footer => {
            const shift = old_size - new_size;

            const new_offset = old_offset + shift;
            try ni.setLocation(gpa, mf, new_offset, new_size);

            const prev_footers_size = prev_footers_size: {
                // We need to shift forwards all footer nodes preceding us.
                const prev_footer_ni = ni.prev(mf).unwrap() orelse {
                    break :prev_footers_size 0;
                };
                if (prev_footer_ni.position(mf) != .footer) {
                    break :prev_footers_size 0;
                }

                var footer_ni = prev_footer_ni;
                while (true) {
                    const old_footer_off, const old_footer_size = footer_ni.location(mf).resolve(mf);
                    try footer_ni.setLocation(gpa, mf, old_footer_off + shift, old_footer_size);

                    const prev_ni = footer_ni.prev(mf).unwrap() orelse break;
                    if (prev_ni.position(mf) != .footer) break;
                    footer_ni = prev_ni;
                }

                // `footer_ni` is the first footer in the parent. This expression gets its *new*
                // offset because we already did the `setLocation` calls.
                const first_footer_new_offset = footer_ni.location(mf).resolve(mf)[0];

                break :prev_footers_size new_offset - first_footer_new_offset;
            };

            // Now we must shift the actual footer bytes forwards, including our own.
            const parent_file_offset = parent_ni.fileLocation(mf, false).offset;
            try mf.moveRange(
                parent_file_offset + old_offset - prev_footers_size,
                parent_file_offset + new_offset - prev_footers_size,
                prev_footers_size + new_size,
            );
        },
    }
}

const GrowOptions = struct {
    /// If `true`, the node size must be set to exactly the given size.
    ///
    /// If `false`, the given size is a minimum, and the actual new node size may be larger.
    exact_size: bool,
    /// If `true`, footers within the resized node will be moved forwards to its new end.
    ///
    /// If `false`, footers will all remain at their current offsets (so the nodes are in a
    /// temporarily invalid state), and moving them is the responsibility of the *caller*.
    move_footers: bool,
};

/// Increases the size of a node.
///
/// Asserts that `new_size` is aligned to `ni.alignment(mf)`, even if `!grow_options.exact_size`.
///
/// Asserts that `new_size` is greater than the current size of `ni`.
fn growNode(
    mf: *MappedFile,
    gpa: Allocator,
    ni: Node.Index,
    new_size: u64,
    grow_options: GrowOptions,
) Error!void {
    mf.nodes_lock.assertUnlocked();

    const node = ni.get(mf);

    const old_offset, const old_size = node.location().resolve(mf);

    assert(node.flags.alignment.check(old_size));
    assert(node.flags.alignment.check(new_size));
    assert(new_size > old_size);

    const parent_ni = node.parent.unwrap() orelse {
        assert(ni == .root);

        if (try mf.growNodeViaInsertRange(gpa, ni, new_size, grow_options)) {
            return;
        }

        mf.memory_map.write(mf.io) catch |err| {
            mf.io_err = switch (err) {
                error.Canceled => |e| return e,
                error.WouldBlock => error.Unexpected, // file was not opened as non-blocking
                error.NotOpenForWriting => error.Unexpected, // we definitely opened the file for writing
                else => |e| e,
            };
            return error.MappedFileIo;
        };
        mf.memory_map.file.setLength(mf.io, new_size) catch |err| switch (err) {
            error.Canceled => |e| return e,
            else => |e| {
                mf.io_err = e;
                return error.MappedFileIo;
            },
        };
        try mf.ensureTotalCapacityPrecise(@intCast(new_size));
        try ni.setLocation(gpa, mf, old_offset, new_size);
        if (grow_options.move_footers) {
            // We need to move any footers to be at the *new* end of the file.
            if (ni.firstFooter(mf).unwrap()) |first_footer_ni| {
                const old_footers_offset, _ = first_footer_ni.location(mf).resolve(mf);
                const footers_size = old_size - old_footers_offset;
                try mf.moveRange(
                    old_footers_offset,
                    old_footers_offset + (new_size - old_size),
                    footers_size,
                );
                // Also update the footers' locations.
                var cur_ni = first_footer_ni;
                while (true) {
                    const old_footer_offset, const footer_size = cur_ni.location(mf).resolve(mf);
                    try cur_ni.setLocation(gpa, mf, old_footer_offset + (new_size - old_size), footer_size);
                    cur_ni = cur_ni.next(mf).unwrap() orelse break;
                }
            }
        }
        return;
    };

    switch (node.flags.position) {
        .header => {
            if (try mf.growNodeViaInsertRange(gpa, ni, new_size, grow_options)) {
                return;
            }

            try mf.ensureAdditionalHeaderCapacity(gpa, parent_ni, new_size - old_size);

            // `old_offset` is still valid because header nodes don't move when the parent resizes.

            const last_header_ni: Node.Index = last_header: {
                var header_ni = ni;
                while (true) {
                    const next_ni = header_ni.next(mf).unwrap() orelse break;
                    if (next_ni.position(mf) != .header) break;
                    header_ni = next_ni;
                }
                break :last_header header_ni;
            };
            const last_header_offset, const last_header_size = last_header_ni.location(mf).resolve(mf);
            const old_headers_size = last_header_offset + last_header_size;

            // This is the first footer *inside* of `ni`.
            const first_sub_footer_oni: Node.Index.Optional = footer: {
                if (!grow_options.move_footers) {
                    // Pretend there are no footers so as to not move them.
                    break :footer .none;
                }
                break :footer ni.firstFooter(mf);
            };
            const sub_footers_size = size: {
                const first_sub_footer_ni = first_sub_footer_oni.unwrap() orelse break :size 0;
                const first_sub_footer_offset, _ = first_sub_footer_ni.location(mf).resolve(mf);
                break :size old_size - first_sub_footer_offset;
            };

            // We need to shift two things forwards; any header nodes which follow us, and any
            // footer nodes *within* us (since they need to be at the end of our new size).
            const parent_file_offset = parent_ni.fileLocation(mf, false).offset;
            try mf.moveRange(
                parent_file_offset + old_offset + old_size - sub_footers_size,
                parent_file_offset + old_offset + new_size - sub_footers_size,
                old_headers_size - (old_offset + old_size - sub_footers_size),
            );

            // Any footers inside of us have had their offsets changed due to us growing:
            if (first_sub_footer_oni.unwrap()) |first_sub_footer_ni| {
                var cur_ni = first_sub_footer_ni;
                while (true) {
                    const old_sub_footer_offset, const sub_footer_size = cur_ni.location(mf).resolve(mf);
                    try cur_ni.setLocation(
                        gpa,
                        mf,
                        old_sub_footer_offset + (new_size - old_size),
                        sub_footer_size,
                    );
                    cur_ni = cur_ni.next(mf).unwrap() orelse break;
                }
            }

            // Update the offsets of all header nodes following us:
            {
                var moved_header_ni = last_header_ni;
                while (moved_header_ni != ni) {
                    assert(moved_header_ni.position(mf) == .header);
                    const moved_header_offset, const moved_header_size = moved_header_ni.location(mf).resolve(mf);
                    try moved_header_ni.setLocation(
                        gpa,
                        mf,
                        moved_header_offset - old_size + new_size,
                        moved_header_size,
                    );
                    moved_header_ni = moved_header_ni.prev(mf).unwrap().?;
                }
            }

            // Finally, update our own size:
            try ni.setLocation(gpa, mf, old_offset, new_size);
            return;
        },
        .floating => {
            try mf.growFloatingNodeWithAlignment(gpa, ni, null, new_size, grow_options);
        },
        .footer => {
            if (try mf.growNodeViaInsertRange(gpa, ni, new_size, grow_options)) {
                return;
            }

            // This is the first footer *inside* of `ni` (unrelated to the fact that `ni` is itself
            // a footer within its parent). We'll need this later in any case, so just find it now.
            const first_sub_footer_oni: Node.Index.Optional = footer: {
                if (!grow_options.move_footers) {
                    // Pretend there are no nested footers so as to not move them.
                    break :footer .none;
                }
                break :footer ni.firstFooter(mf);
            };

            // We have two different strategies for growing a footer node, with different advantages
            // and disadvantages; so first we must decide which to use.
            const strat: union(enum) {
                /// Expand into pre-footer padding space in the parent node (growing the parent if
                /// necessary). This strategy has the benefit that it can reclaim padding bytes in
                /// the parent, but it has the disadvantage that it requires moving this node's
                /// existing content backwards in the file, which may be expensive (particularly
                /// since the src and dest ranges are likely to overlap).
                grow_backwards,

                /// Grow the parent node with `GrowOptions.move_footers` set to `false`, and
                /// implicitly grow ourselves into the newly available space. This usually requires
                /// a lot less moving of bytes, but never reclaims unused space before the parent's
                /// footers, and is sometimes straight-up impossible.
                grow_parent_at_end: struct {
                    add_size: u64,
                    exact_size: bool,
                },
            } = strat: {
                // If this node is small, the move overhead is trivial, so prefer `.grow_backwards`
                // to avoid unnecessary growth of the parent node.
                if (old_size <= mf.flags.block_size.toByteUnits() * 2) {
                    break :strat .grow_backwards;
                }

                // It may also be worth doing `.grow_backwards` if the parent has a *lot* of space
                // we could grow into. More specifically, if "free space we can grow into" makes up
                // a significant proportion of the parent's total size, then that implies the parent
                // has quite poor utilization of space, *and* that we can significantly improve that
                // statistic by growing into that space.
                if (old_size + mf.availableFooterCapacity(parent_ni) >= new_size) {
                    break :strat .grow_backwards;
                }

                if (grow_options.exact_size) {
                    const add_size = new_size - old_size;
                    if (parent_ni.alignment(mf).check(add_size)) {
                        break :strat .{ .grow_parent_at_end = .{
                            .add_size = add_size,
                            .exact_size = true,
                        } };
                    } else {
                        // We *can't* ask the parent to grow by this much, so we have no choice.
                        break :strat .grow_backwards;
                    }
                }

                if (parent_ni.alignment(mf).compare(.lt, node.flags.alignment)) {
                    // Because the parent's alignment is less than our own, if we gave them the
                    // freedom to pick a size, they might choose one which results in *us* having a
                    // size incompatible with our alignment. Therefore, to prevent that, we need to
                    // request an *exact* size from the parent in this case.
                    break :strat .{ .grow_parent_at_end = .{
                        .add_size = new_size - old_size,
                        .exact_size = true,
                    } };
                }

                // The parent's alignment is greater than or equal to our own, so we only need to
                // give the parent a *minimum* size (although we need to ensure it matches their
                // alignment since it could be greater than our own).
                break :strat .{ .grow_parent_at_end = .{
                    .add_size = parent_ni.alignment(mf).forward(new_size - old_size),
                    .exact_size = false,
                } };
            };

            switch (strat) {
                .grow_backwards => {
                    // First, we might need to grow the parent to make enough space.
                    {
                        const available_size = mf.availableFooterCapacity(parent_ni);
                        if (old_size + available_size < new_size) {
                            _, const old_parent_size: u64 = parent_ni.location(mf).resolve(mf);
                            const min_parent_size = old_parent_size + (new_size - old_size - available_size);
                            const new_parent_size = parent_ni.alignment(mf).forward(
                                min_parent_size +| min_parent_size / growth_factor,
                            );
                            try mf.growNode(gpa, parent_ni, new_parent_size, .{
                                .exact_size = false,
                                .move_footers = true,
                            });
                            assert(old_size + mf.availableFooterCapacity(parent_ni) >= new_size);
                        }
                    }

                    // Now we need to grow! To do that, we must move `ni` itself, and every footer
                    // before it in `parent_ni`, backwards. Unlike header nodes, `ni` is included in
                    // the shift, because the bytes we're adding need to go at the *end* of `ni`
                    // rather than its start.

                    // This is the same as `parent_ni.firstFooter(mf)`, it's just more efficient to
                    // start at `ni` than to start at `parent_ni.last(mf)`.
                    const first_parent_footer_ni: Node.Index = first_footer: {
                        var footer_ni = ni;
                        while (true) {
                            const prev_ni = footer_ni.prev(mf).unwrap() orelse break;
                            if (prev_ni.position(mf) != .footer) break;
                            footer_ni = prev_ni;
                        }
                        break :first_footer footer_ni;
                    };

                    const shift = new_size - old_size;

                    // Update our own offset and size:
                    try ni.setLocation(
                        gpa,
                        mf,
                        node.location().resolve(mf)[0] - shift,
                        new_size,
                    );

                    // Any footers *inside* of `ni` have had their offsets changed, because they are
                    // now positioned at the *new* end of `ni`:
                    {
                        var footer_oni = first_sub_footer_oni;
                        while (footer_oni.unwrap()) |footer_ni| : (footer_oni = footer_ni.next(mf)) {
                            const old_footer_offset, const footer_size = footer_ni.location(mf).resolve(mf);
                            try footer_ni.setLocation(gpa, mf, old_footer_offset + shift, footer_size);
                        }
                    }

                    // Any footers *before* `ni` (in `parent_ni`) have been shifted backwards. We'll
                    // also be moving their actual bytes in a moment, so track whether they have
                    // content (if nothing does then we'll be able to skip the `moveRange`). That
                    // flag is initially whether `ni` has content because we're shifting our own
                    // bytes backwards too.
                    var moved_has_content: bool = node.flags.has_content;
                    {
                        var footer_ni = first_parent_footer_ni;
                        while (footer_ni != ni) : (footer_ni = footer_ni.next(mf).unwrap().?) {
                            moved_has_content = moved_has_content or footer_ni.get(mf).flags.has_content;
                            const old_footer_offset, const footer_size = footer_ni.location(mf).resolve(mf);
                            try footer_ni.setLocation(gpa, mf, old_footer_offset - shift, footer_size);
                        }
                    }

                    if (moved_has_content) {
                        // We moved at least one thing containing initialized bytes, so we need to
                        // move the actual data. However, we should *not* move the bytes of any
                        // nested footers inside of `ni`, because they've been "moved" to the end
                        // of our new size, which is the same file location as before.
                        const sub_footers_size = size: {
                            const first_sub_footer_ni = first_sub_footer_oni.unwrap() orelse break :size 0;
                            const first_sub_footer_offset, _ = first_sub_footer_ni.location(mf).resolve(mf);
                            break :size new_size - first_sub_footer_offset;
                        };
                        const new_offset: u64, _ = node.location().resolve(mf);
                        const new_footers_offset: u64, _ = first_parent_footer_ni.location(mf).resolve(mf);
                        const parent_file_offset = parent_ni.fileLocation(mf, false).offset;
                        try mf.moveRange(
                            parent_file_offset + new_footers_offset + shift,
                            parent_file_offset + new_footers_offset,
                            (new_offset - new_footers_offset) + // accounts for every footer before `ni`
                                (old_size - sub_footers_size), // accounts for `ni` itself, excluding nested footers
                        );
                    }
                },
                .grow_parent_at_end => |grow_parent| {
                    _, const old_parent_size: u64 = parent_ni.location(mf).resolve(mf);
                    try mf.growNode(gpa, parent_ni, old_parent_size + grow_parent.add_size, .{
                        .exact_size = grow_parent.exact_size,
                        .move_footers = false,
                    });
                    _, const new_parent_size: u64 = parent_ni.location(mf).resolve(mf);
                    const shift = new_parent_size - old_parent_size;

                    // Here's what we have left to do:
                    //
                    // * Increase our own size by `shift` to absorb the added space.
                    //
                    // * If there are any footers *inside* `ni`, increase their offsets by `shift`.
                    //
                    // * If there are any footers *after* `ni` (inside `parent_ni`), increase their
                    //   offsets by `shift`.
                    //
                    // * Do a `moveRange` corresponding to those offset changes. This is a single
                    //   range which starts at the footers *inside* `ni`.

                    const actual_new_size = old_size + shift;
                    if (grow_options.exact_size) {
                        assert(actual_new_size == new_size);
                    }

                    try ni.setLocation(
                        gpa,
                        mf,
                        node.location().resolve(mf)[0],
                        actual_new_size,
                    );

                    // This will track whether any node with a changed offset actually contains
                    // initialized bytes. If not, there'll be no need to call `moveRange`.
                    var moved_has_content: bool = false;

                    // Set any nested footers' offsets (and include them in `moved_has_content`).
                    {
                        var footer_oni = first_sub_footer_oni;
                        while (footer_oni.unwrap()) |footer_ni| : (footer_oni = footer_ni.next(mf)) {
                            assert(footer_ni.position(mf) == .footer);
                            moved_has_content = moved_has_content or footer_ni.get(mf).flags.has_content;
                            const footer_old_offset: u64, const footer_size: u64 = footer_ni.location(mf).resolve(mf);
                            try footer_ni.setLocation(gpa, mf, footer_old_offset + shift, footer_size);
                        }
                    }

                    // Now set offsets for footers after `ni` inside of `parent_ni`.
                    {
                        var footer_oni = ni.next(mf);
                        while (footer_oni.unwrap()) |footer_ni| : (footer_oni = footer_ni.next(mf)) {
                            assert(footer_ni.position(mf) == .footer);
                            moved_has_content = moved_has_content or footer_ni.get(mf).flags.has_content;
                            const footer_old_offset: u64, const footer_size: u64 = footer_ni.location(mf).resolve(mf);
                            try footer_ni.setLocation(gpa, mf, footer_old_offset + shift, footer_size);
                        }
                    }

                    if (moved_has_content) {
                        // We moved at least one footer containing initialized bytes, so we need to
                        // move the actual data. Compute how big the footers inside `ni` are...
                        const sub_footers_size: u64 = size: {
                            const first_sub_footer_ni = first_sub_footer_oni.unwrap() orelse break :size 0;
                            const first_sub_footer_offset, _ = first_sub_footer_ni.location(mf).resolve(mf);
                            // `actual_new_size` is used here since we already updated the nested footers' offsets above.
                            break :size actual_new_size - first_sub_footer_offset;
                        };
                        // ...and how big the footers *after* `ni`, inside `parent_ni`, are...
                        const post_footers_size: u64 = old_parent_size - (old_offset + old_size);
                        // ...and move them both.
                        const parent_file_off = parent_ni.fileLocation(mf, false).offset;
                        const total_move_size = sub_footers_size + post_footers_size;
                        assert(total_move_size != 0);
                        try mf.moveRange(
                            parent_file_off + old_parent_size - total_move_size,
                            parent_file_off + new_parent_size - total_move_size,
                            total_move_size,
                        );
                    }
                },
            }
        },
    }
}

/// Moves a floating node to an unused region with the given size, which may be greater than the
/// current size. If `new_alignment` is not `null`, then the offset and size of the new region will
/// have that alignment instead of `ni.alignment(mf)`.
///
/// Asserts that `ni` is a floating node (and not `.root`).
///
/// Asserts that `new_size` is aligned to `new_alignment orelse ni.alignment(mf)`.
///
/// Asserts that `new_size` is greater than or equal to the current size of `ni`.
fn growFloatingNodeWithAlignment(
    mf: *MappedFile,
    gpa: Allocator,
    ni: Node.Index,
    new_alignment: ?Alignment,
    new_size: u64,
    grow_options: GrowOptions,
) Error!void {
    mf.nodes_lock.assertUnlocked();

    const parent_ni = ni.parent(mf).unwrap().?; // `ni` cannot be `.root`
    const old_offset, const old_size = ni.location(mf).resolve(mf);

    const alignment = new_alignment orelse ni.alignment(mf);

    assert(new_size >= old_size);
    assert(ni.position(mf) == .floating);
    assert(alignment.check(new_size));

    grow_in_place: {
        if (!alignment.check(old_offset)) {
            break :grow_in_place;
        }
        const limit: u64 = limit: {
            const next_ni = ni.next(mf).unwrap() orelse break :limit parent_ni.location(mf).resolve(mf)[1];
            const next_offset, _ = next_ni.location(mf).resolve(mf);
            break :limit next_offset;
        };
        if (old_offset + new_size > limit) {
            break :grow_in_place; // the parent is not big enough
        }
        // Great, we can grow this node without changing its offset or moving any siblings.
        try ni.setLocation(gpa, mf, old_offset, new_size);
        if (grow_options.move_footers) {
            // If we have any footers, we need to move them to the end of our new size, and update
            // their offsets accordingly.
            if (ni.firstFooter(mf).unwrap()) |first_footer_ni| {
                var cur_ni = first_footer_ni;
                var footers_have_content = false;
                while (true) {
                    footers_have_content = footers_have_content or cur_ni.get(mf).flags.has_content;
                    const old_footer_offset, const footer_size = cur_ni.location(mf).resolve(mf);
                    try cur_ni.setLocation(gpa, mf, old_footer_offset + (new_size - old_size), footer_size);
                    cur_ni = cur_ni.next(mf).unwrap() orelse break;
                }
                if (footers_have_content) {
                    const parent_file_off = parent_ni.fileLocation(mf, false).offset;
                    // This gets the *new* offset because we already updated the offsets above.
                    const new_footers_offset, _ = first_footer_ni.location(mf).resolve(mf);
                    const footers_size = new_size - new_footers_offset;
                    try mf.moveRange(
                        parent_file_off + old_offset + old_size - footers_size,
                        parent_file_off + old_offset + new_size - footers_size,
                        footers_size,
                    );
                }
            }
        }
        return;
    }

    const new_loc: struct {
        offset: u64,
        prev: Node.Index.Optional,
    } = new_loc: {
        _, const parent_size = parent_ni.location(mf).resolve(mf);

        {
            // See if there's space at the start of the parent.
            const last_header_oni = parent_ni.lastHeader(mf);
            const headers_end: u64 = if (last_header_oni.unwrap()) |last_header_ni| headers_end: {
                const last_header_off, const last_header_size = last_header_ni.location(mf).resolve(mf);
                break :headers_end last_header_off + last_header_size;
            } else 0;
            const limit: u64 = limit: {
                const after_header_oni: Node.Index.Optional = after_header: {
                    if (last_header_oni.unwrap()) |last_header_ni| {
                        break :after_header last_header_ni.next(mf);
                    }
                    break :after_header parent_ni.first(mf);
                };
                if (after_header_oni.unwrap()) |after_header_ni| {
                    break :limit after_header_ni.location(mf).resolve(mf)[0];
                } else {
                    break :limit parent_size;
                }
            };
            if (alignment.forward(headers_end) + new_size <= limit) {
                // There's space here!
                break :new_loc .{
                    // Put ourselves at the *end* of this range, so that the free space remains at the start of the parent.
                    .offset = alignment.backward(limit - new_size),
                    .prev = last_header_oni,
                };
            }
        }

        // Otherwise, use space at the end of the parent, or make space there if necessary.

        const first_footer_oni = parent_ni.firstFooter(mf);

        // We know there is a node before the footer[s], because `ni` itself is such a node.
        const prev_ni: Node.Index = if (first_footer_oni.unwrap()) |first_footer_ni| prev: {
            break :prev first_footer_ni.prev(mf).unwrap().?;
        } else prev: {
            break :prev parent_ni.last(mf).unwrap().?;
        };

        const result_offset: u64 = result_offset: {
            if (prev_ni == ni and alignment.check(old_offset)) {
                // We're already at the end of the parent, and our offset is already well-aligned.
                // The only reason we didn't simply grow in place earlier is that the parent wasn't
                // big enough---but now we're resizing the parent anyway, so growing in-place stops
                // us from unnecessarily moving!
                break :result_offset old_offset;
            }
            // Otherwise, just move after the last node.
            const prev_offset, const prev_size = prev_ni.location(mf).resolve(mf);
            break :result_offset alignment.forward(prev_offset + prev_size);
        };

        const footers_size: u64 = if (first_footer_oni.unwrap()) |first_footer_ni| footers_size: {
            const first_footer_offset, _ = first_footer_ni.location(mf).resolve(mf);
            break :footers_size parent_size - first_footer_offset;
        } else 0;

        const min_parent_size = result_offset + new_size + footers_size;
        if (parent_size < min_parent_size) {
            // Okay, at this point we're planning to expand the parent---so before we actually do
            // that, let's first try the Linux "insert range" fast path. We didn't try it before now
            // because it would have been more efficient to just move ourselves into existing space.
            //
            // If we were given a custom alignment, we need to set `GrowOptions.exact_size` for the
            // "insert range" path, because that function is unaware of `new_alignment`.
            const insert_range_grow_options: GrowOptions = .{
                .exact_size = grow_options.exact_size or new_alignment != null,
                .move_footers = grow_options.move_footers,
            };
            if (alignment.check(old_offset) and
                try mf.growNodeViaInsertRange(gpa, ni, new_size, insert_range_grow_options))
            {
                // The Linux fast path did our job for us!
                return;
            }

            // Grow the parent and move to the end of the parent.
            const new_parent_size = parent_ni.alignment(mf).forward(
                min_parent_size +| min_parent_size / growth_factor,
            );
            try mf.growNode(gpa, parent_ni, new_parent_size, .{
                .exact_size = false,
                .move_footers = true,
            });
        }

        break :new_loc .{
            .offset = result_offset,
            .prev = .wrap(prev_ni),
        };
    };

    // We've found our new location in `parent_ni`, now to actually move ourselves there.

    // Footers need to move to a different place than the rest of our content.
    const footers_size: u64, const footers_have_content: bool = footers: {
        if (!grow_options.move_footers) {
            // Pretend there are no footers so as to not move them.
            break :footers .{ 0, false };
        }
        const first_footer_ni = ni.firstFooter(mf).unwrap() orelse {
            break :footers .{ 0, false };
        };

        var cur_ni = first_footer_ni;
        var footers_have_content = false;
        while (true) {
            footers_have_content = footers_have_content or cur_ni.get(mf).flags.has_content;
            const old_footer_offset, const footer_size = cur_ni.location(mf).resolve(mf);
            // Our footers' offsets must change to be at the end of our new size.
            try cur_ni.setLocation(gpa, mf, old_footer_offset + (new_size - old_size), footer_size);
            cur_ni = cur_ni.next(mf).unwrap() orelse break;
        }

        // This is the *new* offset because we already updated the offsets above.
        const new_footers_offset, _ = first_footer_ni.location(mf).resolve(mf);
        const footers_size = new_size - new_footers_offset;

        break :footers .{ footers_size, footers_have_content };
    };

    if (ni.get(mf).flags.has_content) {
        const parent_file_off = parent_ni.fileLocation(mf, false).offset;
        try mf.moveRange(
            parent_file_off + old_offset,
            parent_file_off + new_loc.offset,
            old_size - footers_size,
        );
        if (footers_have_content) try mf.moveRange(
            parent_file_off + old_offset + old_size - footers_size,
            parent_file_off + new_loc.offset + new_size - footers_size,
            footers_size,
        );
    } else {
        assert(!footers_have_content);
    }

    try ni.setLocation(gpa, mf, new_loc.offset, new_size);

    if (new_loc.prev != ni.toOptional()) {
        // We're potentially in a different place in `parent_ni`'s child list, so remove and re-add ourselves.
        try mf.removeNodesFromChildList(gpa, ni, ni);
        try mf.addNodesToChildListAfter(gpa, new_loc.prev, ni, ni);
    }
}

/// Attempts to grow `ni` to `new_size` using `FALLOCATE_FL_INSERT_RANGE` on Linux. This strategy
/// has the advantage that it does not require manually moving any bytes in the file, but has the
/// disadvantages that it may increase the file size more than necessary, and that it changes the
/// offsets of all following nodes, recursively.
///
/// If this strategy is inapplicable or unsuitable for this operation, this function returns `false`
/// without changing any nodes' locations or invalidating any slices.
///
/// Otherwise, this function grows `ni` to `new_size` (maybe larger if `!grow_options.exact_size`),
/// updates the location of `ni` and every node whose offset has changed, and returns `true`.
fn growNodeViaInsertRange(
    mf: *MappedFile,
    gpa: Allocator,
    ni: Node.Index,
    new_size: u64,
    grow_options: GrowOptions,
) Error!bool {
    if (!is_linux or mf.flags.fallocate_insert_range_unsupported) {
        return false;
    }

    _, const old_size = ni.location(mf).resolve(mf);

    // We don't compute the size of the range yet, because depending on `grow_options` we might want
    // to bump it based on our sibling and parent nodes' alignments. However, we can do an early
    // check for cases where we should obviously exit.
    const min_range_size: u64 = s: {
        const requested_size = new_size - old_size;
        if (mf.flags.block_size.check(requested_size)) {
            break :s requested_size;
        }
        if (!grow_options.exact_size and
            requested_size >= mf.flags.block_size.toByteUnits() * 2)
        {
            // We're growing by at least a few blocks, so allow ourselves to bump the size
            // slightly to give it the needed alignment.
            break :s mf.flags.block_size.forward(requested_size);
        }
        return false;
    };
    assert(min_range_size > 0);
    assert(mf.flags.block_size.check(min_range_size));

    const range_file_offset: u64 = range_file_offset: {
        const node_file_offset = ni.fileLocation(mf, false).offset;
        const last_ni = ni.last(mf).unwrap() orelse {
            // If `ni` has no children (i.e. is a leaf node), we need to insert exactly at its end.
            const range_file_offset = node_file_offset + old_size;
            if (!mf.flags.block_size.check(range_file_offset)) {
                return false;
            }
            break :range_file_offset range_file_offset;
        };
        const pre_footer_oni: Node.Index.Optional, const footers_size: u64 = footers: {
            if (!grow_options.move_footers) {
                // Pretend there are no footers so as to not move them.
                break :footers .{ .wrap(last_ni), 0 };
            }
            const first_footer_ni = ni.firstFooter(mf).unwrap() orelse {
                break :footers .{ .wrap(last_ni), 0 };
            };
            const first_footer_offset, _ = first_footer_ni.location(mf).resolve(mf);
            break :footers .{ first_footer_ni.prev(mf), old_size - first_footer_offset };
        };
        const pre_footer_end: u64 = if (pre_footer_oni.unwrap()) |pre_footer_ni| end: {
            const pre_footer_off, const pre_footer_size = pre_footer_ni.location(mf).resolve(mf);
            break :end pre_footer_off + pre_footer_size;
        } else 0;

        const min_file_offset = node_file_offset + pre_footer_end;
        const max_file_offset = node_file_offset + old_size - footers_size;
        // We can go anywhere between `min_file_offset` and `max_file_offset`.
        const candidate_file_offset = mf.flags.block_size.forward(min_file_offset);
        if (candidate_file_offset > max_file_offset) {
            return false;
        }
        break :range_file_offset candidate_file_offset;
    };
    assert(mf.flags.block_size.check(range_file_offset));

    const range_size: u64 = range_size: {
        // For this strategy to be valid, the number of bytes we insert needs to be compatible with
        // the alignments of all nodes following us (and following our parents, their parents, etc).
        // We also probably don't want to trigger too many "node moved" events, since doing that
        // repeatedly could result in a lot of extra work. Therefore, while we traverse parents and
        // siblings to check their alignment requirements, we will also set an arbitrary limit on
        // the number of nodes we can move, and give up if we walk more than that.
        const max_moved_nodes = 32;
        var num_moved: u32 = 0;
        var cur_ni = ni;
        // Alignment required for `range_size`: initially the block size (required for the syscall),
        // then updated as we traverse based on how the operation would affect surrounding nodes.
        var need_range_align: Alignment = mf.flags.block_size.max(ni.alignment(mf));
        while (true) {
            // `cur_ni` will grow as a result of the range insertion. Its size must be well-aligned.
            need_range_align = need_range_align.max(cur_ni.alignment(mf));

            // Siblings following `cur_ni` don't get bigger, but their offsets change.
            while (cur_ni.next(mf).unwrap()) |next_ni| {
                // Only floating children need well-aligned offsets.
                if (next_ni.position(mf) == .floating) {
                    need_range_align = need_range_align.max(next_ni.alignment(mf));
                }
                num_moved += 1;
                if (num_moved > max_moved_nodes) return false;
                cur_ni = next_ni;
            }

            // Move up to the parent.
            cur_ni = cur_ni.parent(mf).unwrap() orelse break;
        }
        // Traversal done. We didn't hit `max_moved_nodes`, so now we can use the computed alignment
        // requirement to figure out whether we're actually going to insert a range.
        if (need_range_align.check(min_range_size)) {
            break :range_size min_range_size;
        }
        // Perhaps we're allowed to grow by more than `min_range_size`?
        const candidate_range_size = need_range_align.forward(min_range_size);
        if (!grow_options.exact_size and
            // Allow growing by up to 50% more than was requested.
            candidate_range_size <= min_range_size +| min_range_size / 2)
        {
            break :range_size candidate_range_size;
        }
        return false;
    };

    // This `range_size` is compatible with everyone's alignment requirements, and we won't move too
    // many nodes, so let's do it!

    mf.memory_map.write(mf.io) catch |err| {
        mf.io_err = switch (err) {
            error.Canceled => |e| return e,
            error.WouldBlock => error.Unexpected, // file was not opened as non-blocking
            error.NotOpenForWriting => error.Unexpected, // we definitely opened the file for writing
            else => |e| e,
        };
        return error.MappedFileIo;
    };

    // If we happen to be inserting at the very end of the file, we need to resize the file instead
    // of using `FALLOCATE_FL_INSERT_RANGE`.
    if (range_file_offset == Node.Index.root.location(mf).resolve(mf)[1]) {
        mf.memory_map.file.setLength(mf.io, range_file_offset + range_size) catch |err| switch (err) {
            error.Canceled => |e| return e,
            else => |e| {
                mf.io_err = e;
                return error.MappedFileIo;
            },
        };
    } else {
        while (true) switch (linux.errno(linux.fallocate(
            mf.memory_map.file.handle,
            linux.FALLOC.FL_INSERT_RANGE,
            @intCast(range_file_offset),
            @intCast(range_size),
        ))) {
            .SUCCESS => break,
            .INTR => continue,
            .NOSYS, .OPNOTSUPP => {
                // After all that setup work, it turns out the operation is actually unsupported!
                mf.flags.fallocate_insert_range_unsupported = true;
                return false;
            },
            else => |e| {
                mf.io_err = switch (e) {
                    .SUCCESS, .INTR, .NOSYS, .OPNOTSUPP => unreachable, // handled above
                    .BADF => unreachable,
                    .FBIG => unreachable,
                    .INVAL => unreachable,
                    .IO => error.InputOutput,
                    .NODEV => error.NotFile,
                    .NOSPC => error.NoSpaceLeft,
                    .PERM => error.PermissionDenied,
                    .SPIPE => error.Unseekable,
                    .TXTBSY => error.FileBusy,
                    else => std.posix.unexpectedErrno(e),
                };
                return error.MappedFileIo;
            },
        };
    }

    // We did it! Now to update all the sizes and offsets. This loop is exactly the same shape as
    // above, except we're updating locations instead of checking alignments.
    var cur_ni = ni;
    while (true) {
        const this_offset, const this_old_size = cur_ni.location(mf).resolve(mf);
        if (cur_ni == .root) {
            try mf.ensureTotalCapacityPrecise(@intCast(this_old_size + range_size));
        }
        try cur_ni.setLocation(gpa, mf, this_offset, this_old_size + range_size);

        while (cur_ni.next(mf).unwrap()) |next_ni| {
            const next_old_offset, const next_size = next_ni.location(mf).resolve(mf);
            try next_ni.setLocation(gpa, mf, next_old_offset + range_size, next_size);
            cur_ni = next_ni;
        }

        cur_ni = cur_ni.parent(mf).unwrap() orelse break;
    }

    if (grow_options.move_footers) {
        // The only thing left is to update the offsets of any footers inside of `ni`.
        if (ni.firstFooter(mf).unwrap()) |first_footer_ni| {
            var footer_ni = first_footer_ni;
            while (true) {
                const old_footer_offset, const footer_size = footer_ni.location(mf).resolve(mf);
                try footer_ni.setLocation(gpa, mf, old_footer_offset + range_size, footer_size);
                footer_ni = footer_ni.next(mf).unwrap() orelse break;
            }
        }
    }

    return true;
}

/// Ensures that `parent_ni` has at least `extra_capacity` padding bytes following its current
/// headers, so that the headers can grow into that space.
fn ensureAdditionalHeaderCapacity(
    mf: *MappedFile,
    gpa: Allocator,
    parent_ni: Node.Index,
    extra_capacity: u64,
) Error!void {
    _, const parent_size = parent_ni.location(mf).resolve(mf);

    const last_header_oni = parent_ni.lastHeader(mf);
    const first_footer_oni = parent_ni.firstFooter(mf);

    const headers_size: u64 = headers_size: {
        const last_header_ni = last_header_oni.unwrap() orelse break :headers_size 0;
        const last_header_off, const last_header_size = last_header_ni.location(mf).resolve(mf);
        break :headers_size last_header_off + last_header_size;
    };

    const footers_size: u64 = footers_size: {
        const first_footer_ni = first_footer_oni.unwrap() orelse break :footers_size 0;
        const first_footer_off, _ = first_footer_ni.location(mf).resolve(mf);
        break :footers_size parent_size - first_footer_off;
    };

    const first_floating_oni: Node.Index.Optional = if (last_header_oni.unwrap()) |last_header_ni| first_floating: {
        const after_header_ni = last_header_ni.next(mf).unwrap() orelse break :first_floating .none;
        break :first_floating switch (after_header_ni.position(mf)) {
            .header => unreachable,
            .floating => .wrap(after_header_ni),
            .footer => .none,
        };
    } else first_floating: {
        const first_ni = parent_ni.first(mf).unwrap() orelse break :first_floating .none;
        break :first_floating switch (first_ni.position(mf)) {
            .header => unreachable,
            .floating => .wrap(first_ni),
            .footer => .none,
        };
    };
    const first_floating_ni = first_floating_oni.unwrap() orelse {
        // This node has only headers and footers.
        const min_parent_size = headers_size + extra_capacity + footers_size;
        if (parent_size < min_parent_size) {
            const new_parent_size = parent_ni.alignment(mf).forward(
                min_parent_size +| min_parent_size / growth_factor,
            );
            try mf.growNode(gpa, parent_ni, new_parent_size, .{
                .exact_size = false,
                .move_footers = true,
            });
        }
        return;
    };

    const last_floating_ni = if (first_footer_oni.unwrap()) |first_footer_ni| last_floating: {
        break :last_floating first_footer_ni.prev(mf).unwrap().?;
    } else last_floating: {
        break :last_floating parent_ni.last(mf).unwrap().?;
    };
    assert(last_floating_ni.position(mf) == .floating); // we know `parent_ni` contains at least `first_floating_ni`

    // Find the first floating child, if any, which does not overlap the new header space.
    const first_good_floating_oni: Node.Index.Optional = first_good_floating: {
        var floating_ni = first_floating_ni;
        while (true) {
            const floating_offset, _ = floating_ni.location(mf).resolve(mf);
            if (floating_offset >= headers_size + extra_capacity) {
                break :first_good_floating .wrap(floating_ni);
            }
            const next_ni = floating_ni.next(mf).unwrap() orelse {
                break :first_good_floating .none;
            };
            switch (next_ni.position(mf)) {
                .header => unreachable, // after the last header
                .floating => floating_ni = next_ni,
                .footer => break :first_good_floating .none,
            }
        }
    };

    if (first_good_floating_oni == first_floating_ni.toOptional()) {
        // None of the floating children are in our way! That means there's already enough space.
        return;
    }

    const last_moving_ni = if (first_good_floating_oni.unwrap()) |first_good_floating_ni| last_moving: {
        break :last_moving first_good_floating_ni.prev(mf).unwrap().?;
    } else last_moving: {
        break :last_moving last_floating_ni;
    };

    // We are going to move all nodes between `first_floating_ni` and `last_moving_ni` to the end of
    // the parent. We'll move all the node data in one big block.

    const moving_offset: u64 = first_floating_ni.location(mf).resolve(mf)[0];
    const moving_size: u64 = size: {
        const last_moving_off, const last_moving_size = last_moving_ni.location(mf).resolve(mf);
        break :size last_moving_off + last_moving_size - moving_offset;
    };

    var moving_alignment: Alignment = .@"1";
    var moving_has_content = false; // optimization: no need to move data if it's all uninitialized
    {
        var cur_ni = first_floating_ni;
        while (true) {
            moving_alignment = moving_alignment.max(cur_ni.alignment(mf));
            moving_has_content = moving_has_content or cur_ni.get(mf).flags.has_content;
            if (cur_ni == last_moving_ni) break;
            cur_ni = cur_ni.next(mf).unwrap().?;
        }
    }

    const first_free_offset = free_offset: {
        const last_floating_off, const last_floating_size = last_floating_ni.location(mf).resolve(mf);
        break :free_offset @max(last_floating_off + last_floating_size, headers_size + extra_capacity);
    };
    // Alignment is a little tricky here. We don't necessarily want the new offset to be aligned to
    // `moving_alignment` exactly, because if (e.g.) the first floating node is align(2) and the
    // second is align(4), then the overall range we're moving may not be 4-byte aligned even though
    // one of the nodes is. Instead, the old and new offsets must be congruent modulo the alignment.
    const aligned_dest_offset = moving_alignment.forward(first_free_offset);
    const dest_offset = aligned_dest_offset + (moving_offset - moving_alignment.backward(moving_offset));
    assert(dest_offset % moving_alignment.toByteUnits() == moving_offset % moving_alignment.toByteUnits());

    // This expression is correct because `dest_offset` is after all floating nodes (except the ones
    // we're moving there of course).
    const min_parent_size = dest_offset + moving_size + footers_size;
    if (parent_size < min_parent_size) {
        const new_parent_size = parent_ni.alignment(mf).forward(
            min_parent_size +| min_parent_size / growth_factor,
        );
        try mf.growNode(gpa, parent_ni, new_parent_size, .{
            .exact_size = false,
            .move_footers = true,
        });
    }

    if (moving_has_content) {
        const parent_file_off = parent_ni.fileLocation(mf, false).offset;
        try mf.moveRange(
            parent_file_off + moving_offset,
            parent_file_off + dest_offset,
            moving_size,
        );
    }

    // Remove everything between `first_floating_ni` and `last_moving_ni` from the linked list, then
    // re-insert them in their new position.
    try mf.removeNodesFromChildList(gpa, first_floating_ni, last_moving_ni);
    try mf.addNodesToChildListBefore(gpa, first_footer_oni, first_floating_ni, last_moving_ni);

    // Finally, we need to update the locations of all of those nodes.
    var cur_ni = first_floating_ni;
    while (true) {
        assert(cur_ni.position(mf) == .floating);
        const old_offset, const old_size = cur_ni.location(mf).resolve(mf);
        const new_offset = old_offset - moving_offset + dest_offset;
        assert(cur_ni.alignment(mf).check(new_offset));
        try cur_ni.setLocation(gpa, mf, new_offset, old_size);
        if (cur_ni == last_moving_ni) break;
        cur_ni = cur_ni.next(mf).unwrap().?;
    }
}

/// Returns how many padding bytes `parent_ni` currently has directly preceding its footers, which
/// footers can therefore grow into.
fn availableFooterCapacity(mf: *const MappedFile, parent_ni: Node.Index) u64 {
    const first_footer_oni = parent_ni.firstFooter(mf);

    const before_footers_oni: Node.Index.Optional, const footers_off: u64 = footers: {
        const first_footer_ni = first_footer_oni.unwrap() orelse {
            _, const parent_size = parent_ni.location(mf).resolve(mf);
            break :footers .{ parent_ni.last(mf), parent_size };
        };
        const first_footer_off, _ = first_footer_ni.location(mf).resolve(mf);
        break :footers .{ first_footer_ni.prev(mf), first_footer_off };
    };

    const header_and_floating_end: u64 = end: {
        const before_footers_ni = before_footers_oni.unwrap() orelse break :end 0;
        const offset, const size = before_footers_ni.location(mf).resolve(mf);
        break :end offset + size;
    };

    return footers_off - header_and_floating_end;
}

fn removeNodesFromChildList(
    mf: *MappedFile,
    gpa: Allocator,
    first_remove_ni: Node.Index,
    last_remove_ni: Node.Index,
) Allocator.Error!void {
    const parent_ni = first_remove_ni.parent(mf).unwrap().?;
    assert(last_remove_ni.parent(mf).unwrap().? == parent_ni);

    const prev_oni = first_remove_ni.prev(mf);
    const next_oni = last_remove_ni.next(mf);

    if (prev_oni.unwrap()) |prev_ni| {
        assert(prev_ni.next(mf).unwrap().? == first_remove_ni);
        try prev_ni.setNext(gpa, mf, next_oni);
    } else {
        assert(parent_ni.first(mf).unwrap().? == first_remove_ni);
        parent_ni.get(mf).first = next_oni;
    }

    if (next_oni.unwrap()) |next_ni| {
        assert(next_ni.prev(mf).unwrap().? == last_remove_ni);
        next_ni.get(mf).prev = prev_oni;
    } else {
        assert(parent_ni.last(mf).unwrap().? == last_remove_ni);
        parent_ni.get(mf).last = prev_oni;
    }
}
/// Assumes `first_add_ni` and `last_add_ni` are connected, and that all nodes in between them
/// already have their `parent` field correctly populated.
///
/// To add a single node, set `first_add_ni` equal to `last_add_ni`.
fn addNodesToChildListBefore(
    mf: *MappedFile,
    gpa: Allocator,
    /// `null` means to add at the end of the parent.
    next_oni: Node.Index.Optional,
    first_add_ni: Node.Index,
    last_add_ni: Node.Index,
) Allocator.Error!void {
    const parent_ni = first_add_ni.parent(mf).unwrap().?;
    assert(last_add_ni.parent(mf).unwrap().? == parent_ni);
    if (next_oni.unwrap()) |next_ni| {
        assert(next_ni.parent(mf).unwrap().? == parent_ni);
    }

    const prev_oni: Node.Index.Optional = if (next_oni.unwrap()) |next_ni| prev: {
        break :prev next_ni.prev(mf);
    } else prev: {
        break :prev parent_ni.last(mf);
    };

    first_add_ni.get(mf).prev = prev_oni;
    try last_add_ni.setNext(gpa, mf, next_oni);

    if (prev_oni.unwrap()) |prev_ni| {
        assert(prev_ni.next(mf) == next_oni);
        try prev_ni.setNext(gpa, mf, .wrap(first_add_ni));
    } else {
        assert(parent_ni.first(mf) == next_oni);
        parent_ni.get(mf).first = .wrap(first_add_ni);
    }

    if (next_oni.unwrap()) |next_ni| {
        assert(next_ni.prev(mf) == prev_oni);
        next_ni.get(mf).prev = .wrap(last_add_ni);
    } else {
        assert(parent_ni.last(mf) == prev_oni);
        parent_ni.get(mf).last = .wrap(last_add_ni);
    }
}
fn addNodesToChildListAfter(
    mf: *MappedFile,
    gpa: Allocator,
    /// `null` means to add at the start of the parent.
    prev_oni: Node.Index.Optional,
    first_add_ni: Node.Index,
    last_add_ni: Node.Index,
) Allocator.Error!void {
    const next_oni: Node.Index.Optional = next: {
        if (prev_oni.unwrap()) |prev_ni| break :next prev_ni.next(mf);
        const parent_ni = first_add_ni.parent(mf).unwrap().?;
        break :next parent_ni.first(mf);
    };
    return mf.addNodesToChildListBefore(gpa, next_oni, first_add_ni, last_add_ni);
}

fn realignNode(
    mf: *MappedFile,
    gpa: Allocator,
    ni: Node.Index,
    new_align: Alignment,
) Error!void {
    mf.nodes_lock.assertUnlocked();

    const old_offset, const old_size = ni.location(mf).resolve(mf);

    if (ni == .root or ni.position(mf) != .floating) {
        // Only this node's size is aligned, not its offset.
        if (!new_align.check(old_size)) {
            assert(new_align.compare(.gt, ni.alignment(mf)));
            try mf.growNode(gpa, ni, new_align.forward(old_size), .{
                .exact_size = true, // because `growNode` is not aware that the size needs to match `new_align`
                .move_footers = true,
            });
        }
    } else {
        // This is a floating node, so its size and offset are both aligned.
        if (!new_align.check(old_offset) or !new_align.check(old_size)) {
            assert(new_align.compare(.gt, ni.alignment(mf)));
            try mf.growFloatingNodeWithAlignment(gpa, ni, new_align, new_align.forward(old_size), .{
                .exact_size = false,
                .move_footers = true,
            });
        }
    }

    ni.get(mf).flags.alignment = new_align;
}

fn updateWriters(mf: *MappedFile) void {
    var writers_it = mf.writers.first;
    while (writers_it) |writer_node| : (writers_it = writer_node.next) {
        const w: *Node.Writer = @fieldParentPtr("writer_node", writer_node);
        w.interface.buffer = w.ni.slice(mf);
    }
}

fn moveRange(mf: *MappedFile, old_file_offset: u64, new_file_offset: u64, size: u64) Error!void {
    if (old_file_offset == new_file_offset) return;

    if (old_file_offset >= new_file_offset + size or
        new_file_offset >= old_file_offset + size)
    {
        const n = try mf.copyFileRange(
            mf.memory_map.file,
            old_file_offset,
            new_file_offset,
            size,
        );
        @memcpy(
            mf.memory_map.memory[@intCast(new_file_offset + n)..][0..@intCast(size - n)],
            mf.memory_map.memory[@intCast(old_file_offset + n)..][0..@intCast(size - n)],
        );

        try mf.zeroRange(old_file_offset, size);

        return;
    }

    // TODO: if the non-overlapping region is greater than or equal to a filesystem block, is it
    // ever worth doing multiple `copyFileRange` calls instead of a big `@memmove`?

    @memmove(
        mf.memory_map.memory[@intCast(new_file_offset)..][0..@intCast(size)],
        mf.memory_map.memory[@intCast(old_file_offset)..][0..@intCast(size)],
    );

    if (new_file_offset > old_file_offset) {
        const clear_size = new_file_offset - old_file_offset;
        assert(clear_size < size);
        try mf.zeroRange(old_file_offset, clear_size);
    } else {
        const clear_size = old_file_offset - new_file_offset;
        assert(clear_size < size);
        try mf.zeroRange(new_file_offset + size, clear_size);
    }
}
fn zeroRange(mf: *MappedFile, file_offset: u64, size: u64) Error!void {
    if (is_linux and
        !mf.flags.fallocate_punch_hole_unsupported and
        size >= mf.flags.block_size.toByteUnits() * 2 - 1)
    {
        while (true) switch (linux.errno(linux.fallocate(
            mf.memory_map.file.handle,
            linux.FALLOC.FL_PUNCH_HOLE | linux.FALLOC.FL_KEEP_SIZE,
            @intCast(file_offset),
            @intCast(size),
        ))) {
            .SUCCESS => return,
            .INTR => continue,
            .NOSYS, .OPNOTSUPP => {
                mf.flags.fallocate_punch_hole_unsupported = true;
                break; // fall back to slow path
            },
            else => |e| {
                mf.io_err = switch (e) {
                    .SUCCESS, .INTR, .NOSYS, .OPNOTSUPP => unreachable, // handled above
                    .BADF => unreachable,
                    .FBIG => unreachable,
                    .INVAL => unreachable,
                    .IO => error.InputOutput,
                    .NODEV => error.NotFile,
                    .NOSPC => error.NoSpaceLeft,
                    .PERM => error.PermissionDenied,
                    .SPIPE => error.Unseekable,
                    .TXTBSY => error.FileBusy,
                    else => std.posix.unexpectedErrno(e),
                };
                return error.MappedFileIo;
            },
        };
    }
    @memset(mf.memory_map.memory[@intCast(file_offset)..][0..@intCast(size)], 0);
}
fn copyFileRange(
    mf: *MappedFile,
    old_file: Io.File,
    old_file_offset: u64,
    new_file_offset: u64,
    size: u64,
) Error!u64 {
    if (!is_linux or mf.flags.copy_file_range_unsupported) {
        return 0;
    }

    const min_size = mf.flags.block_size.toByteUnits() * 2 - 1;
    if (size < min_size) return 0;

    const io = mf.io;
    mf.memory_map.write(io) catch |err| {
        mf.io_err = switch (err) {
            error.Canceled => |e| return e,
            error.WouldBlock => error.Unexpected, // file was not opened as non-blocking
            error.NotOpenForWriting => error.Unexpected, // we definitely opened the file for writing
            else => |e| e,
        };
        return error.MappedFileIo;
    };
    var remaining_size = size;
    var old_file_offset_mut: i64 = @intCast(old_file_offset);
    var new_file_offset_mut: i64 = @intCast(new_file_offset);
    while (remaining_size >= min_size) {
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
            .NOSYS, .OPNOTSUPP, .XDEV => {
                mf.flags.copy_file_range_unsupported = true;
                break;
            },
            else => |e| {
                mf.io_err = switch (e) {
                    .SUCCESS, .INTR, .NOSYS, .OPNOTSUPP, .XDEV => unreachable, // handled above
                    .BADF => unreachable,
                    .FBIG => unreachable,
                    .INVAL => unreachable,
                    .OVERFLOW => unreachable,
                    .IO => error.InputOutput,
                    .ISDIR => error.IsDir,
                    .NOMEM => error.SystemResources,
                    .NOSPC => error.NoSpaceLeft,
                    .PERM => error.PermissionDenied,
                    .TXTBSY => error.FileBusy,
                    else => std.posix.unexpectedErrno(e),
                };
                return error.MappedFileIo;
            },
        }
    }
    return size - remaining_size;
}

pub fn ensureTotalCapacity(mf: *MappedFile, new_capacity: usize) Error!void {
    if (mf.memory_map.memory.len >= new_capacity) return;
    try mf.ensureTotalCapacityPrecise(new_capacity +| new_capacity / growth_factor);
}

pub fn ensureTotalCapacityPrecise(mf: *MappedFile, new_capacity: usize) Error!void {
    if (mf.memory_map.memory.len >= new_capacity) return;
    const io = mf.io;
    const aligned_capacity: usize = @intCast(
        mf.flags.block_size.forward(new_capacity),
    );

    if (mf.memory_map.memory.len > 0) {
        if (mf.memory_map.setLength(io, aligned_capacity)) |_| {
            return;
        } else |err| switch (err) {
            error.OperationUnsupported => {},
            error.OutOfMemory, error.Canceled => |e| return e,
            else => |e| {
                mf.io_err = e;
                return error.MappedFileIo;
            },
        }

        mf.memory_map.write(io) catch |err| {
            mf.io_err = switch (err) {
                error.Canceled => |e| return e,
                error.WouldBlock => error.Unexpected, // file was not opened as non-blocking
                error.NotOpenForWriting => error.Unexpected, // we definitely opened the file for writing
                else => |e| e,
            };
            return error.MappedFileIo;
        };
        unmap(mf);
    }

    const file = mf.memory_map.file;
    mf.memory_map = Io.File.MemoryMap.create(io, file, .{ .len = aligned_capacity }) catch |err| {
        mf.io_err = switch (err) {
            error.OutOfMemory, error.Canceled => |e| return e,
            error.WouldBlock => error.Unexpected, // file was not opened as non-blocking
            error.NotOpenForReading => error.Unexpected, // we definitely opened the file for writing
            else => |e| e,
        };
        return error.MappedFileIo;
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
        error.ReadOnlyFileSystem, // again, we opened the file for writing
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
    mf.verifyNode(.root);
}
fn verifyNode(mf: *MappedFile, parent_ni: Node.Index) void {
    const parent = parent_ni.get(mf);
    _, const parent_size = parent.location().resolve(mf);

    var prev_oni: Node.Index.Optional = .none;
    var prev_end: u64 = 0;
    var prev_pos: Node.Position = .header;
    var oni = parent.first;
    while (oni.unwrap()) |ni| {
        const node = ni.get(mf);
        assert(node.parent == parent_ni.toOptional());
        assert(node.prev == prev_oni);

        const offset, const size = node.location().resolve(mf);
        const end = offset + size;

        assert(node.flags.alignment.check(size));
        assert(offset >= prev_end);
        assert(end <= parent_size);

        switch (node.flags.position) {
            .header => {
                assert(prev_pos == .header);
                assert(offset == prev_end);
            },
            .floating => {
                assert(prev_pos != .footer);
                assert(node.flags.alignment.check(offset));
            },
            .footer => {
                if (prev_pos == .footer) assert(offset == prev_end);
            },
        }

        mf.verifyNode(ni);

        prev_oni = .wrap(ni);
        prev_end = end;
        prev_pos = ni.position(mf);

        oni = node.next;
    }
    assert(parent.last == prev_oni);
    if (prev_pos == .footer) {
        assert(prev_end == parent_size);
    }
}

test "fuzz node operations" {
    try std.testing.fuzz({}, fuzzOneNodeOperations, .{});
}
fn fuzzOneNodeOperations(_: void, smith: *std.testing.Smith) anyerror!void {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var tmp_file = try tmp_dir.dir.createFile(io, "test.mf", .{ .read = true });
    defer tmp_file.close(io);

    var mf: MappedFile = try .init(tmp_file, gpa, io);
    defer mf.deinit(gpa);

    var nodes: std.array_hash_map.Auto(MappedFile.Node.Index, struct {
        parent: MappedFile.Node.Index.Optional,
        position: MappedFile.Node.Position,
        num_headers: u32,
        num_footers: u32,
        /// For leaf nodes, this value is whether we have initialized the contents of the node or
        /// not. For non-leaf nodes, this value is unspecified and should be ignored.
        initialized: bool,
    }) = .empty;
    defer nodes.deinit(gpa);

    // When initializing a leaf node, we will place its 4-byte node index at the start of its range,
    // and the bitwise NOT of its node index at the end of its range (both little-endian). This is
    // just a simple way to put distinct values we can validate at all node boundaries.

    try nodes.putNoClobber(gpa, .root, .{
        .parent = .none,
        .position = .floating,
        .num_headers = 0,
        .num_footers = 0,
        .initialized = false,
    });

    // Allow a range of alignments, with most nodes having a small alignment of 1--32 bytes (most
    // commonly 1 byte), but with a small chance for some large alignments too.
    const alignment_weights: []const std.testing.Smith.Weight = comptime &.{
        .value(Alignment, .@"1", 20),
        .value(Alignment, .@"2", 5),
        .value(Alignment, .@"4", 5),
        .value(Alignment, .@"8", 5),
        .value(Alignment, .@"16", 5),
        .value(Alignment, .@"32", 5),
        .value(Alignment, .fromByteUnits(0x200), 1),
        .value(Alignment, .fromByteUnits(0x400), 1),
        .value(Alignment, .fromByteUnits(0x800), 1),
        .value(Alignment, .fromByteUnits(0x1000), 1),
        .value(Alignment, .fromByteUnits(0x2000), 1),
        .value(Alignment, .fromByteUnits(0x4000), 1),
        .value(Alignment, .fromByteUnits(0x8000), 1),
    };

    const min_nonzero_size = 2 * @sizeOf(MappedFile.Node.Index);
    const max_size = 0x10_000;
    const initial_size_weights: []const std.testing.Smith.Weight = comptime &.{
        // initially, make nodes just as likely to be empty as non-empty
        .value(u64, 0, max_size - min_nonzero_size + 1),
        .rangeAtMost(u64, min_nonzero_size, max_size, 1),
    };

    while (!smith.eos()) switch (smith.value(enum { add, resize, realign })) {
        .add => {
            const parent_ni = nodes.keys()[smith.index(nodes.count())];

            const alignment = smith.valueWeighted(Alignment, alignment_weights);
            const size = alignment.forward(smith.valueWeighted(u64, initial_size_weights));

            const position = smith.valueWeighted(Node.Position, comptime &.{
                // make floating nodes more common than header and footer nodes
                .value(Node.Position, .header, 1),
                .value(Node.Position, .footer, 1),
                .value(Node.Position, .floating, 4),
            });
            const new_ni: Node.Index = switch (position) {
                .header => new_ni: {
                    const parent_info = nodes.getPtr(parent_ni).?;
                    const prev_oni: Node.Index.Optional = prev_oni: {
                        const n = smith.valueRangeAtMost(u32, 0, parent_info.num_headers);
                        if (n == 0) break :prev_oni .none;
                        var cur_ni = parent_ni.first(&mf).unwrap().?;
                        for (1..n) |_| cur_ni = cur_ni.next(&mf).unwrap().?;
                        break :prev_oni .wrap(cur_ni);
                    };
                    const new_ni = try parent_ni.addHeaderChildAfter(gpa, &mf, prev_oni, .{
                        .size = size,
                        .alignment = alignment,
                    });
                    parent_info.num_headers += 1;
                    break :new_ni new_ni;
                },

                .floating => try parent_ni.addFloatingChild(gpa, &mf, .{
                    .size = size,
                    .alignment = alignment,
                }),

                .footer => new_ni: {
                    const parent_info = nodes.getPtr(parent_ni).?;
                    const next_oni: Node.Index.Optional = next_oni: {
                        const n = smith.valueRangeAtMost(u32, 0, parent_info.num_footers);
                        if (n == 0) break :next_oni .none;
                        var cur_ni = parent_ni.last(&mf).unwrap().?;
                        for (1..n) |_| cur_ni = cur_ni.prev(&mf).unwrap().?;
                        break :next_oni .wrap(cur_ni);
                    };
                    const new_ni = try parent_ni.addFooterChildBefore(gpa, &mf, next_oni, .{
                        .size = size,
                        .alignment = alignment,
                    });
                    parent_info.num_footers += 1;
                    break :new_ni new_ni;
                },
            };

            const initialize = size > 0 and smith.value(bool);
            if (initialize) {
                const slice = new_ni.slice(&mf);
                std.mem.writeInt(u32, slice[0..4], @backingInt(new_ni), .little);
                std.mem.writeInt(u32, slice[slice.len - 4 ..][0..4], ~@backingInt(new_ni), .little);
            }

            try nodes.putNoClobber(gpa, new_ni, .{
                .parent = .wrap(parent_ni),
                .position = position,
                .num_headers = 0,
                .num_footers = 0,
                .initialized = initialize,
            });
        },

        .resize => {
            const ni = nodes.keys()[smith.index(nodes.count())];
            const node_info = nodes.getPtr(ni).?;

            const alignment = ni.alignment(&mf);

            if (ni.first(&mf) == .none and smith.value(bool)) {
                // Since this is a leaf node, we can use `resizeLeaf`.
                const new_size = alignment.forward(smith.valueWeighted(u64, initial_size_weights));
                try ni.resizeLeaf(gpa, &mf, new_size);
                if (new_size == 0) {
                    node_info.initialized = false;
                }
            } else {
                const min_size = alignment.forward(smith.valueWeighted(u64, initial_size_weights));
                try ni.ensureMinimumSize(gpa, &mf, min_size);
            }

            if (ni.first(&mf) == .none) {
                // This is a leaf node, so it can contain data.
                if (node_info.initialized) {
                    // It's already initialized, so we'll write the expected footer at the new end.
                    const slice = ni.slice(&mf);
                    std.mem.writeInt(u32, slice[slice.len - 4 ..][0..4], ~@backingInt(ni), .little);
                } else if (ni.location(&mf).resolve(&mf)[1] > 0) {
                    // It was uninitialized, but it has a non-zero size, so maybe we'd like to
                    // initialize it now?
                    if (smith.value(bool)) {
                        node_info.initialized = true;
                        const slice = ni.slice(&mf);
                        std.mem.writeInt(u32, slice[0..4], @backingInt(ni), .little);
                        std.mem.writeInt(u32, slice[slice.len - 4 ..][0..4], ~@backingInt(ni), .little);
                    }
                }
            }
        },
        .realign => {
            const ni = nodes.keys()[smith.index(nodes.count())];
            const new_alignment = smith.valueWeighted(Alignment, alignment_weights);
            if (new_alignment.compare(.gt, ni.alignment(&mf))) {
                _, const old_size = ni.location(&mf).resolve(&mf);
                try ni.realign(gpa, &mf, new_alignment);
                if (ni.first(&mf) == .none and nodes.get(ni).?.initialized) {
                    const slice = ni.slice(&mf);
                    @memmove(slice[slice.len - 4 ..][0..4], slice[old_size - 4 ..][0..4]);
                }
            }
        },
    };

    mf.verify();

    for (nodes.keys(), nodes.values()) |ni, expected| {
        try std.testing.expectEqual(expected.parent, ni.parent(&mf));
        if (ni != .root) {
            try std.testing.expectEqual(expected.position, ni.position(&mf));
        }

        {
            var num_headers: u32 = 0;
            var header_oni = ni.lastHeader(&mf);
            while (header_oni.unwrap()) |header_ni| {
                num_headers += 1;
                header_oni = header_ni.prev(&mf);
            }
            try std.testing.expectEqual(expected.num_headers, num_headers);
        }

        {
            var num_footers: u32 = 0;
            var footer_oni = ni.firstFooter(&mf);
            while (footer_oni.unwrap()) |footer_ni| {
                num_footers += 1;
                footer_oni = footer_ni.next(&mf);
            }
            try std.testing.expectEqual(expected.num_footers, num_footers);
        }

        if (ni.first(&mf) == .none and expected.initialized) {
            const slice = ni.sliceConst(&mf);
            if (slice.len > 0) {
                try std.testing.expect(slice.len >= min_nonzero_size);
                const header = std.mem.readInt(u32, slice[0..4], .little);
                const footer = std.mem.readInt(u32, slice[slice.len - 4 ..][0..4], .little);
                try std.testing.expectEqual(@backingInt(ni), header);
                try std.testing.expectEqual(~@backingInt(ni), footer);
            }
        }
    }
}
