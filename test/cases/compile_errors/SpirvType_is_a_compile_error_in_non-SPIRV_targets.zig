comptime {
    _ = @SpirvType(.{ .runtime_array = u32 });
}

// error
// backend=selfhosted
// target=x86_64-native
//
// :2:9: error: builtin @SpirvType is only available when targeting SPIR-V; targeted CPU architecture is x86_64
