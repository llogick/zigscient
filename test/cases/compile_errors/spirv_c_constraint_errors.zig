export fn not_comptime() callconv(.kernel) void {
    var runtime: u32 = 42;
    _ = &runtime;
    _ = asm ("%ret = OpSpecConstant %ty $default"
        : [ret] "" (-> u32),
        : [ty] "t" (u32),
          [default] "c" (runtime),
    );
}

export fn undef_input() callconv(.kernel) void {
    const x: u32 = undefined;
    _ = asm ("%ret = OpDummy $x"
        : [ret] "" (-> u32),
        : [x] "c" (x),
    );
}

export fn unsupported_type() callconv(.kernel) void {
    const s = "hi";
    _ = asm ("%ret = OpDummy $x"
        : [ret] "" (-> u32),
        : [x] "c" (s),
    );
}

// error
// backend=selfhosted
// target=spirv32-vulkan
//
// :7:26: error: assembly input with 'c' constraint must be compile-time known
// :15:20: error: assembly input with 'c' constraint cannot be undefined
// :23:20: error: unsupported type '*const [2:0]u8' for 'c' constraint
