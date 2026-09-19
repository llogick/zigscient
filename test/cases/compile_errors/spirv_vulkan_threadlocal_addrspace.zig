threadlocal var counter: u32 addrspace(.generic) = 0;

export fn main() callconv(.kernel) void {
    counter += 1;
}

// error
// backend=selfhosted
// target=spirv32-vulkan
//
// :1:41: error: threadlocal variables with address space 'generic' are not supported on vulkan
