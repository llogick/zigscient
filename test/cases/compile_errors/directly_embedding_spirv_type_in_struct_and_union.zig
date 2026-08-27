const Sampler = @SpirvType(.sampler);
const RuntimeArray = @SpirvType(.{ .runtime_array = u32 });
const Foo = struct {
    s: Sampler,
};
const Bar = struct {
    a: RuntimeArray,
};
const Baz = extern struct {
    a: RuntimeArray,
    b: u32,
};
const Qux = extern struct { _: @SpirvType(.{ .runtime_array = Sampler }) };
export fn a() void {
    var foo: Foo = undefined;
    _ = &foo;
}
export fn c() void {
    var bar: Bar = undefined;
    _ = &bar;
}
export fn d() void {
    var baz: Baz = undefined;
    _ = &baz;
}
export fn e() void {
    var qux: Qux = undefined;
    _ = &qux;
}

// error
// backend=selfhosted
// target=spirv32-vulkan
//
// :4:8: error: cannot directly embed SPIR-V type '@SpirvType(.sampler)' in struct
// :4:8: note: opaque types have unknown size
// :6:13: error: non-extern struct cannot contain fields of type '@SpirvType(.runtime_array, u32)'
// :7:5: note: while checking this field
// :9:20: error: struct field of type '@SpirvType(.runtime_array, u32)' must be the last field
// :10:5: note: while checking this field
// :13:32: error: cannot embed SPIR-V type '@SpirvType(.sampler)' in struct
// :13:32: note: opaque types have unknown size
