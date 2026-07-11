export fn a() void {
    var buf: [3]f32 = undefined;
    takesSlice(&buf); // error
}

fn takesSlice(buf: []f32) void {
    _ = buf;
}

export fn b() void {
    var buf: [3]f32 = undefined;
    for (buf[0..3]) |_| {} // error
}

export fn c() void {
    var buf: [3]f32 = undefined;
    for (&buf) |_| {} // not an error
}

export fn d() void {
    const buf: [3]f32 = .{1, 2, 3};
    for (comptime buf[0..3]) |_| {} // not an error
}

export fn e() void {
    const buf: [3]f32 = .{1, 2, 3};
    for (comptime buf[0..3]) |_| {} // not an error
    for (buf[0..3]) |_| {} // error
}

// error
// backend=auto
// target=spirv32-opengl,spirv32-vulkan
// cpu_features=baseline+variable_pointers
//
// :3:16: error: cannot construct slice from address space 'generic'
// :3:16: note: only 'shared' and 'storage_buffer' address spaces support slicing on SPIR-V
// :12:13: error: cannot construct slice from address space 'generic'
// :12:13: note: only 'shared' and 'storage_buffer' address spaces support slicing on SPIR-V
// :28:13: error: cannot construct slice from address space 'generic'
// :28:13: note: only 'shared' and 'storage_buffer' address spaces support slicing on SPIR-V
