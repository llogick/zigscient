var x: u32 = 0;

comptime {
    _ = x;
}

// error
// backend=selfhosted
// target=spirv32-vulkan
//
// :1:1: error: SPIR-V target does not support global variables
// :1:1: note: consider using 'threadlocal'
