var obj1_integer: usize = 421;

comptime {
    @export(&obj1_integer, .{ .name = "obj1_integer", .linkage = .strong });
}
