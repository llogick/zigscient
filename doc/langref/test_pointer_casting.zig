const std = @import("std");
const native_endian = @import("builtin").target.cpu.arch.endian();
const expectEqual = std.testing.expectEqual;

test "pointer casting" {
    const bytes: [4]u8 align(@alignOf(u32)) = .{ 0x10, 0x20, 0x30, 0x40 };
    const u32_ptr: *const u32 = @ptrCast(&bytes);

    // Because we directly reinterpreted bytes of memory, the `u32` value we
    // load from `u32_ptr` depends on the target endian:
    switch (native_endian) {
        .little => try expectEqual(0x40302010, u32_ptr.*),
        .big => try expectEqual(0x10203040, u32_ptr.*),
    }

    // To instead reinterpret the logical bit representation of `bytes` with no
    // dependency on the target endian, use `@bitCast`, which always places
    // earlier array elements into less-significant bits:
    try expectEqual(0x40302010, @as(u32, @bitCast(bytes)));
}

test "pointer child type" {
    // pointer types have a `child` field which tells you the type they point to.
    try expectEqual(u32, @typeInfo(*u32).pointer.child);
}

// test
