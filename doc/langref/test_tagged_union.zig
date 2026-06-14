const std = @import("std");
const expectEqual = std.testing.expectEqual;

const ComplexTypeTag = enum {
    ok,
    not_ok,
};
const ComplexType = union(ComplexTypeTag) {
    ok: u8,
    not_ok: void,
};

test "switch on tagged union" {
    const c = ComplexType{ .ok = 42 };
    try expectEqual(ComplexTypeTag.ok, @as(ComplexTypeTag, c));

    switch (c) {
        .ok => |value| try expectEqual(42, value),
        .not_ok => unreachable,
    }

    switch (c) {
        .ok => |_, tag| {
            // Because we're in the '.ok' prong, 'tag' is compile-time known to be '.ok':
            comptime std.debug.assert(tag == .ok);
        },
        .not_ok => unreachable,
    }
}

test "get tag type" {
    try expectEqual(ComplexTypeTag, std.meta.Tag(ComplexType));
}

// test
