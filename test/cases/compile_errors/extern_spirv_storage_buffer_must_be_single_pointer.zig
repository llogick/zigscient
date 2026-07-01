const a = @extern([*]addrspace(.storage_buffer) u32, .{
    .name = "a",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 0 } },
});
const b = @extern([]addrspace(.uniform) u32, .{
    .name = "b",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 1 } },
});
const c = @extern([*c]addrspace(.push_constant) u32, .{ .name = "c" });
comptime {
    _ = a;
    _ = b;
    _ = c;
}

// error
// backend=selfhosted
// target=spirv32-vulkan
//
// :1:19: error: extern in 'storage_buffer' address space must be a single-item pointer to a struct
// :1:19: note: wrap the element type in a struct containing a runtime-sized array
// :5:19: error: extern in 'uniform' address space must be a single-item pointer to a struct
// :5:19: note: wrap the element type in a struct containing a runtime-sized array
// :9:19: error: extern in 'push_constant' address space must be a single-item pointer to a struct
// :9:19: note: wrap the element type in a struct containing a runtime-sized array
