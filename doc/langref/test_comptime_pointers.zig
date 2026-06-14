const expectEqual = @import("std").testing.expectEqual;

test "comptime pointers" {
    comptime {
        var x: i32 = 1;
        const ptr = &x;
        ptr.* += 1;
        x += 1;
        try expectEqual(3, ptr.*);
    }
}

// test
