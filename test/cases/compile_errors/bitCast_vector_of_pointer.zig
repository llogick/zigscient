export fn foo(p: *u32) void {
    const vec: @Vector(2, *u32) = .{ p, p };
    const raw: [2]usize = @bitCast(vec);
    _ = raw;
}

// error
//
// :3:36: error: cannot @bitCast from '@Vector(2, *u32)'
