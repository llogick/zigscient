const RuntimeArray = @SpirvType(.{ .runtime_array = u32 });

const a = @extern(*addrspace(.storage_buffer) RuntimeArray, .{
    .name = "a",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 0 } },
});
const b = @extern(*addrspace(.uniform) const RuntimeArray, .{
    .name = "b",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 1 } },
});

comptime {
    _ = a;
    _ = b;
}

// error
// backend=selfhosted
// target=spirv32-vulkan
//
// :3:19: error: extern symbol cannot have type '*addrspace(.storage_buffer) @SpirvType(.runtime_array, u32)'
// :3:19: note: pointer element type '@SpirvType(.runtime_array, u32)' is not extern compatible
// :3:19: note: SPIR-V runtime arrays must be the last field of an extern struct
// :7:19: error: extern symbol cannot have type '*addrspace(.uniform) const @SpirvType(.runtime_array, u32)'
// :7:19: note: pointer element type '@SpirvType(.runtime_array, u32)' is not extern compatible
// :7:19: note: SPIR-V runtime arrays must be the last field of an extern struct
