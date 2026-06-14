export fn foo() void {
    const bytes: [16]u8 align(@alignOf([]const u8)) = @splat(0xFA);
    _ = @as(*const []const u8, @ptrCast(&bytes)).*;
}

// error
//
// :3:49: error: comptime dereference requires '[]const u8' to have a well-defined layout
