const F1 = fn () callconv(.{ .spirv_task = .{ .x = 1, .y = 1, .z = 1 } }) void;
const F2 = fn () callconv(.{ .spirv_mesh = .{} }) void;
export fn entry1() void {
    const a: F1 = undefined;
    _ = a;
}
export fn entry2() void {
    const a: F2 = undefined;
    _ = a;
}

// error
// backend=selfhosted
// target=spirv64-opengl
//
// :1:28: error: calling convention 'spirv_task' not supported by compiler backend 'stage2_spirv'
// :2:28: error: calling convention 'spirv_mesh' not supported by compiler backend 'stage2_spirv'
