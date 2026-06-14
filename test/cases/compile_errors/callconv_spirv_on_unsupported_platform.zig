const F1 = fn () callconv(.{ .spirv_fragment = .{} }) void;
const F2 = fn () callconv(.spirv_vertex) void;
const F3 = fn () callconv(.{ .spirv_task = .{ .x = 1, .y = 1, .z = 1 } }) void;
const F4 = fn () callconv(.{ .spirv_mesh = .{} }) void;
export fn entry1() void {
    const a: F1 = undefined;
    _ = a;
}
export fn entry2() void {
    const a: F2 = undefined;
    _ = a;
}
export fn entry3() void {
    const a: F3 = undefined;
    _ = a;
}
export fn entry4() void {
    const a: F4 = undefined;
    _ = a;
}

// error
// backend=selfhosted
// target=spirv64-opencl
//
// :1:28: error: calling convention 'spirv_fragment' not supported by compiler backend 'stage2_spirv'
// :2:28: error: calling convention 'spirv_vertex' not supported by compiler backend 'stage2_spirv'
// :3:28: error: calling convention 'spirv_task' not supported by compiler backend 'stage2_spirv'
// :4:28: error: calling convention 'spirv_mesh' not supported by compiler backend 'stage2_spirv'
