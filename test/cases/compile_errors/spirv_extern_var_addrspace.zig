extern var x: u32;

export fn main() callconv(.kernel) void {
    _ = x;
}

// error
// backend=selfhosted
// target=spirv64-vulkan
//
// :1:15: error: SPIR-V extern variables require an explicit address space
