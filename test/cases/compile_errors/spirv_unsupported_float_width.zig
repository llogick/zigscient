export fn use_f80() callconv(.kernel) void {
    var x: f80 = 1.5;
    _ = &x;
}

export fn use_f16() callconv(.kernel) void {
    var x: f16 = 1.5;
    _ = &x;
}

// error
// backend=selfhosted
// target=spirv32-vulkan
//
// :2:5: error: 'f80' is not supported on the current SPIR-V feature set
// :7:5: error: 'f16' is not supported on the current SPIR-V feature set
