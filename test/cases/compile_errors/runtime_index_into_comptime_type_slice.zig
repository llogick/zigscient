const Struct = struct {
    a: u32,
};
fn getIndex() usize {
    return 2;
}
export fn entry() void {
    const index = getIndex();
    const field = @typeInfo(Struct).@"struct".field_types[index];
    _ = field;
}

// error
//
// :9:59: error: values of type 'type' must be comptime-known, but index value is runtime-known
// : note: types are not available at runtime
