const std = @import("std");
const builtin = @import("builtin");
const symbol = @import("../c.zig").symbol;

comptime {
    if (builtin.target.isMuslLibC() or builtin.target.isWasiLibC()) {
        symbol(&insque, "insque");
        symbol(&remque, "remque");
    }
}

/// Not defined in `std.c` because C headers don't either.
const Node = extern struct {
    next: ?*Node,
    prev: ?*Node,
};

fn insque(element: *anyopaque, pred: ?*anyopaque) callconv(.c) void {
    const e: *Node = @ptrCast(@alignCast(element));

    if (pred) |p_ptr| {
        const p: *Node = @ptrCast(@alignCast(p_ptr));
        e.next = p.next;
        e.prev = p;
        p.next = e;

        if (e.next) |next| {
            next.prev = e;
        }
    } else {
        e.next = null;
        e.prev = null;
    }
}

fn remque(element: *anyopaque) callconv(.c) void {
    const e: *Node = @ptrCast(@alignCast(element));

    if (e.next) |next| next.prev = e.prev;
    if (e.prev) |prev| prev.next = e.next;
}
