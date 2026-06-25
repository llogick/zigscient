const F1 = fn () callconv(.{ .spirv_kernel = .{ .x = 0, .y = 1, .z = 1 } }) void;
const F2 = fn () callconv(.{ .spirv_task = .{ .x = 1, .y = 0, .z = 1 } }) void;
const F3 = fn () callconv(.{ .spirv_mesh = .{ .max_vertices = 0 } }) void;
const F4 = fn () callconv(.{ .spirv_fragment = .{ .pixel_centered_integer = true } }) void;
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
// target=spirv32-vulkan
//
// :1:28: error: kernel workgroup dimensions must be at least 1
// :2:28: error: kernel workgroup dimensions must be at least 1
// :3:28: error: mesh shader 'max_vertices' and 'max_primitives' must be at least 1
// :4:28: error: 'pixel_centered_integer' is not supported on this target
