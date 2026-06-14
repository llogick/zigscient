const expectEqual = @import("std").testing.expectEqual;

test "comptime @ptrFromInt" {
    comptime {
        // Zig is able to do this at compile-time, as long as
        // ptr is never dereferenced.
        const ptr: *i32 = @ptrFromInt(0xdeadbee0);
        const addr = @intFromPtr(ptr);
        try expectEqual(usize, @TypeOf(addr));
        try expectEqual(0xdeadbee0, addr);
    }
}

// test
