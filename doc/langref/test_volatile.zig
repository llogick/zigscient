const expectEqual = @import("std").testing.expectEqual;

test "volatile" {
    const mmio_ptr: *volatile u8 = @ptrFromInt(0x12345678);
    try expectEqual(*volatile u8, @TypeOf(mmio_ptr));
}

// test
