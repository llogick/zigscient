const Buffer = extern struct { value: u32 };
const Sampler = @SpirvType(.sampler);
const RuntimeArray = @SpirvType(.{ .runtime_array = u32 });
const SamplerRuntimeArray = @SpirvType(.{ .runtime_array = Sampler });
const BufferRuntimeArray = @SpirvType(.{ .runtime_array = Buffer });

const a = @extern(*addrspace(.input) const RuntimeArray, .{ .name = "a" });
const b = @extern(*addrspace(.uniform) const RuntimeArray, .{ .name = "b" });
const c = @extern(*addrspace(.storage_buffer) const RuntimeArray, .{ .name = "c" });
const d = @extern(*addrspace(.constant) const RuntimeArray, .{ .name = "d" });
const e = @extern(*addrspace(.constant) const SamplerRuntimeArray, .{
    .name = "samplers",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 0 } },
});
const f = @extern(*addrspace(.storage_buffer) [4]Buffer, .{
    .name = "sized_buffers",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 1 } },
});
const g = @extern(*addrspace(.storage_buffer) BufferRuntimeArray, .{
    .name = "buffers",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 2 } },
});

comptime {
    _ = a;
}
comptime {
    _ = b;
}
comptime {
    _ = c;
}

export fn main() callconv(.{ .spirv_fragment = .{} }) void {
    _ = &d[0];
    _ = &e[0];
    f[0].value = 1;
    g[0].value = 2;
}

// error
// backend=selfhosted
// target=spirv32-vulkan
// cpu_features=baseline+runtime_descriptor_array
//
// :7:19: error: SPIR-V runtime array is not allowed in the 'input' address space
// :8:19: error: extern in 'uniform' address space must be a single-item pointer to a struct
// :9:19: error: extern in 'storage_buffer' address space must be a single-item pointer to a struct
// :10:19: error: extern in 'constant' address space must point to an opaque SPIR-V type, or to an array of one
