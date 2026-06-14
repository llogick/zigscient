const builtin = @import("builtin");
const std = @import("std");

const c = std.c;
const testing = std.testing;

/// Not defined in `std.c` because C headers don't either.
const Node = extern struct {
    next: ?*Node,
    prev: ?*Node,
};

test "insque and remque" {
    if (builtin.target.os.tag == .windows) return; // no insque/remque

    var first: Node = .{ .next = null, .prev = null };
    var second: Node = .{ .next = null, .prev = null };
    var third: Node = .{ .next = null, .prev = null };

    c.insque(&first, null);
    try testing.expectEqual(@as(?*Node, null), first.next);
    try testing.expectEqual(@as(?*Node, null), first.prev);

    c.insque(&second, &first);
    try testing.expectEqual(@as(?*Node, &second), first.next);
    try testing.expectEqual(@as(?*Node, &first), second.prev);

    c.insque(&third, &first);
    try testing.expectEqual(@as(?*Node, &third), first.next);
    try testing.expectEqual(@as(?*Node, &second), third.next);
    try testing.expectEqual(@as(?*Node, &first), third.prev);
    try testing.expectEqual(@as(?*Node, &third), second.prev);

    c.remque(&third);
    try testing.expectEqual(@as(?*Node, &second), first.next);
    try testing.expectEqual(@as(?*Node, &first), second.prev);

    c.remque(&second);
    try testing.expectEqual(@as(?*Node, null), first.next);
}
