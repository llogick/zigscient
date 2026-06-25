export fn vert() callconv(.spirv_vertex) void {}
export fn frag() callconv(.{ .spirv_fragment = .{ .depth_assumption = .greater } }) void {}
export fn comp() callconv(.{ .spirv_kernel = .{ .x = 8, .y = 8, .z = 1 } }) void {}
export fn task() callconv(.{ .spirv_task = .{ .x = 1, .y = 1, .z = 1 } }) void {}
export fn mesh() callconv(.{ .spirv_mesh = .{ .stage_output = .output_lines, .max_primitives = 1, .max_vertices = 2 } }) void {}

// compile
// output_mode=Obj
// backend=selfhosted
// target=spirv32-vulkan
// cpu_features=vulkan_v1_2+mesh_shading_ext
// emit_bin=true
