const Sampler = @SpirvType(.sampler);
const RuntimeArray = @SpirvType(.{ .runtime_array = u32 });
const Foo = struct {
    s: Sampler,
};
const Baz = struct {
    a: RuntimeArray,
};
const Qux = extern struct {
    a: RuntimeArray,
    b: u32,
};
export fn a() void {
    var foo: Foo = undefined;
    _ = &foo;
}
export fn c() void {
    var baz: Baz = undefined;
    _ = &baz;
}
export fn d() void {
    var qux: Qux = undefined;
    _ = &qux;
}

// error
// backend=selfhosted
// target=spirv64-vulkan
//
// :4:8: error: cannot directly embed SPIR-V type 'tmp.Sampler__SpirvType_4' in struct
// :4:8: note: opaque types have unknown size
// :6:13: error: non-extern struct cannot contain fields of type 'tmp.RuntimeArray__SpirvType_11'
// :7:5: note: while checking this field
// :9:20: error: struct field of type 'tmp.RuntimeArray__SpirvType_11' must be the last field
// :10:5: note: while checking this field
