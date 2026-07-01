const x = @extern(*addrspace(.push_constant) u32, .{
    .name = "x",
    .decoration = .{ .flat = 0 },
});
comptime {
    _ = x;
}

// error
// backend=selfhosted
// target=spirv32-vulkan
//
// :1:45: error: "flat" decoration requires "input" or "output" address space
