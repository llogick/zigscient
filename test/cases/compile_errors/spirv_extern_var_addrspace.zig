const Block = extern struct { x: u32 };
const RuntimeArray = @SpirvType(.{ .runtime_array = u32 });

extern var implicit_addrspace: u32;

const many = @extern([*]addrspace(.storage_buffer) u32, .{
    .name = "many",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 0 } },
});
const push_array = @extern(*addrspace(.push_constant) const [4]Block, .{ .name = "push_array" });
const plain_constant = @extern(*addrspace(.constant) const Block, .{
    .name = "plain_constant",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 1 } },
});
const runtime_array = @extern(*addrspace(.storage_buffer) RuntimeArray, .{
    .name = "runtime_array",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 2 } },
});

comptime {
    _ = implicit_addrspace;
}
comptime {
    _ = many;
}
comptime {
    _ = push_array;
}
comptime {
    _ = plain_constant;
}
comptime {
    _ = runtime_array;
}

// error
// backend=selfhosted
// target=spirv32-vulkan
//
// :4:32: error: SPIR-V extern variables require an explicit address space
// :6:22: error: extern in 'storage_buffer' address space must be a single-item pointer to a struct
// :10:28: error: extern in 'push_constant' address space must be a single-item pointer to a struct
// :11:32: error: extern in 'constant' address space must point to an opaque SPIR-V type, or to an array of one
// :15:31: error: extern symbol cannot have type '*addrspace(.storage_buffer) @SpirvType(.runtime_array, u32)'
// :15:31: note: pointer element type '@SpirvType(.runtime_array, u32)' is not extern compatible
// :15:31: note: SPIR-V runtime arrays must be the last field of an extern struct
// :15:31: note: consider enabling the 'runtime_descriptor_array' feature to use the runtime array as the extern pointee
