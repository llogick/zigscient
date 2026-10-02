const root0 = @This();
pub const root1 = @import("root1.zig");
const mod0 = @import("module");
const mod1 = mod0.mod1;
pub fn r0pf(r0pa: u32) void {
    root0.r0cf(r0pa ^ 1);
    root0.r0cfi(r0pa ^ 2);
    root1.r1cf(r0pa ^ 3);
    root1.r1cfi(r0pa ^ 4);
    mod0.m0cf(r0pa ^ 5);
    mod0.m0cfi(r0pa ^ 6);
    mod1.m1cf(r0pa ^ 7);
    mod1.m1cfi(r0pa ^ 8);
}
pub inline fn r0pfi(r0pai: u32) void {
    root0.r0cf(r0pai ^ 1);
    root0.r0cfi(r0pai ^ 2);
    root1.r1cf(r0pai ^ 3);
    root1.r1cfi(r0pai ^ 4);
    mod0.m0cf(r0pai ^ 5);
    mod0.m0cfi(r0pai ^ 6);
    mod1.m1cf(r0pai ^ 7);
    mod1.m1cfi(r0pai ^ 8);
}
pub fn r0cf(r0ca: u32) void {
    var discard = r0ca;
    _ = &discard;
}
pub inline fn r0cfi(r0cai: u32) void {
    var discard = r0cai;
    _ = &discard;
}
pub fn main() void {
    root0.r0pf(12);
    root0.r0pfi(23);
    root1.r1pf(34);
    root1.r1pfi(45);
    mod0.m0pf(56);
    mod0.m0pfi(67);
    mod1.m1pf(78);
    mod1.m1pfi(89);
}
