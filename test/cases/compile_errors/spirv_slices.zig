export fn a() void {
    var x: [3]f32 = .{ 1, 2, 3 };
    takesSlice(&x);
}

fn takesSlice(buf: []f32) void {
    _ = buf;
}

export fn b() void {
    const x: [3]f32 = .{ 1, 2, 3 };
    for (comptime x[0..3]) |_| {}
    for (&x) |_| {}
    for (x[0..3]) |_| {}
}

// error
// backend=selfhosted
// target=spirv32-opengl,spirv32-vulkan
// cpu_features=baseline+variable_pointers
//
// :3:16: error: cannot construct slice from address space 'generic'
// :3:16: note: only 'shared' and 'storage_buffer' address spaces support slicing on SPIR-V
// :14:11: error: cannot construct slice from address space 'generic'
// :14:11: note: only 'shared' and 'storage_buffer' address spaces support slicing on SPIR-V
