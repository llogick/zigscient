export fn a() callconv(.{ .spirv_kernel = .{ .x = 0, .y = 1, .z = 1 } }) void {}
export fn b() callconv(.{ .spirv_task = .{ .x = 1, .y = 0, .z = 1 } }) void {}
export fn c() callconv(.{ .spirv_mesh = .{ .max_vertices = 0, .x = 1, .y = 1, .z = 1 } }) void {}
export fn d() callconv(.{ .spirv_mesh = .{ .x = 1, .y = 1, .z = 0 } }) void {}
export fn e() callconv(.{ .spirv_fragment = .{ .pixel_centered_integer = true } }) void {}

// error
// backend=selfhosted
// target=spirv32-vulkan
//
// :1:25: error: kernel workgroup dimensions must be at least 1
// :2:25: error: kernel workgroup dimensions must be at least 1
// :3:25: error: mesh shader 'max_vertices' and 'max_primitives' must be at least 1
// :4:25: error: mesh shader workgroup dimensions must be at least 1
// :5:25: error: 'pixel_centered_integer' is not supported on this target
