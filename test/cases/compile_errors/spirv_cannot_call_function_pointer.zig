fn foo() void {}

export fn main() callconv(.kernel) void {
    var fp = &foo;
    fp = &foo;
    fp();
}

// error
// backend=selfhosted
// target=spirv32-vulkan
//
// :6:5: error: SPIR-V does not support calling function pointers
