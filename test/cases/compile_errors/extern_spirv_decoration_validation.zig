const flat = @extern(*addrspace(.push_constant) u32, .{
    .name = "flat",
    .decoration = .{ .flat = 0 },
});
const location = @extern(*addrspace(.uniform) u32, .{
    .name = "location",
    .decoration = .{ .location = 0 },
});
const descriptor = @extern(*addrspace(.input) u32, .{
    .name = "descriptor",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 0 } },
});

comptime {
    _ = flat;
}
comptime {
    _ = location;
}
comptime {
    _ = descriptor;
}

// error
// backend=selfhosted
// target=spirv32-vulkan
//
// :1:55: error: 'flat' decoration requires 'input' or 'output' address space
// :5:53: error: 'location' decoration requires 'input' or 'output' address space
// :9:53: error: 'descriptor' decoration requires 'storage_buffer', 'uniform', 'constant' or 'global' address space
