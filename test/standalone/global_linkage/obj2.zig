var obj2_integer: usize = 422;

comptime {
    @export(&obj2_integer, .{ .name = "obj2_integer", .linkage = .strong });
}
