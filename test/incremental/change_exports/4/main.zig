export fn foo() void {}
const bar: u32 = 123;
const other: u32 = 456;
const does_exports = {
    @export(&bar, .{ .name = "bar" });
    @export(&other, .{ .name = "other" });
};
comptime {
    //_ = does_exports;
}
pub fn main() !void {
    const S = struct {
        extern fn foo() void;
    };
    S.foo();
}
const std = @import("std");
