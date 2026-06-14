const expectEqual = @import("std").testing.expectEqual;

test "@intFromPtr and @ptrFromInt" {
    const ptr: *i32 = @ptrFromInt(0xdeadbee0);
    const addr = @intFromPtr(ptr);
    try expectEqual(usize, @TypeOf(addr));
    try expectEqual(0xdeadbee0, addr);
}

// test
