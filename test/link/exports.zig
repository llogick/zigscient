export fn foo_fn() void {}
var foo_var: u32 = 1234;
comptime {
    @export(&foo_var, .{ .name = "foo_var", .linkage = .strong });
}
const foo_const: u64 = 5678;
comptime {
    @export(&foo_const, .{ .name = "foo_const", .linkage = .strong });
}
