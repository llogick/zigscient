const RuntimeArray = @SpirvType(.{ .runtime_array = f32 });
const Buffer = extern struct {
    data: RuntimeArray,
};
const buf = @extern(*addrspace(.storage_buffer) Buffer, .{
    .name = "buf",
    .decoration = .{ .descriptor = .{ .set = 0, .binding = 0 } },
});
export fn main() callconv(.kernel) void {
    const a = buf.data;
    _ = a;
}
export fn main2() callconv(.kernel) void {
    const p: *addrspace(.storage_buffer) const RuntimeArray = &buf.data;
    _ = p.*;
}

// error
// backend=selfhosted
// target=spirv32-vulkan
//
// :10:15: error: cannot load SPIR-V runtime array value
// :15:12: error: cannot load SPIR-V runtime array value
