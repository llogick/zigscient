const x = @extern(*addrspace(.output) u32, .{
    .name = "x",
    .decoration = .{ .flat = 0 },
});
comptime {
    _ = x;
}

// error
// backend=selfhosted
// target=spirv64-vulkan
//
// :1:45: error: 'flat' decoration requires 'input' address space
