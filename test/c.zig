const builtin = @import("builtin");
const std = @import("std");
const c = std.c;

test {
    _ = @import("c/inttypes.zig");
    _ = @import("c/math.zig");
    _ = @import("c/pthread.zig");
    _ = @import("c/search.zig");
    _ = @import("c/stdlib.zig");
    _ = @import("c/string.zig");
    _ = @import("c/strings.zig");
    _ = @import("c/unistd.zig");
    _ = @import("c/wchar.zig");
}

pub fn expectErrno(expected_errno: c.E) !void {
    try std.testing.expectEqual(expected_errno, @as(c.E, @enumFromInt(c._errno().*)));
    c._errno().* = @intFromEnum(c.E.SUCCESS);
}

pub fn expectErrnoAny(expected_errnos: []const c.E) !void {
    const errno = c._errno().*;
    for (expected_errnos) |expected_errno| {
        if (errno == @intFromEnum(expected_errno)) break;
    } else {
        var buffer: [64]u8 = undefined;
        const stderr = std.debug.lockStderr(&buffer);
        defer std.debug.unlockStderr();
        try stderr.file_writer.interface.print("expected one of {t}", .{expected_errnos[0]});
        for (expected_errnos[1..]) |expected_errno| {
            try stderr.file_writer.interface.print(", {t}", .{expected_errno});
        }
        try stderr.file_writer.interface.print(", found {t}\n", .{@as(c.E, @enumFromInt(errno))});
        return error.TestExpectedEqual;
    }
    c._errno().* = @intFromEnum(c.E.SUCCESS);
}
