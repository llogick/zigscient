const root0 = @import("root");
const root1 = root0.root1;
const mod0 = @This();
pub const mod1 = @import("mod1.zig");
pub fn m0pf(m0pa: u32) void {
    root0.r0cf(m0pa ^ 1);
    root0.r0cfi(m0pa ^ 2);
    root1.r1cf(m0pa ^ 3);
    root1.r1cfi(m0pa ^ 4);
    mod0.m0cf(m0pa ^ 5);
    mod0.m0cfi(m0pa ^ 6);
    mod1.m1cf(m0pa ^ 7);
    mod1.m1cfi(m0pa ^ 8);
}
pub inline fn m0pfi(m0pai: u32) void {
    root0.r0cf(m0pai ^ 1);
    root0.r0cfi(m0pai ^ 2);
    root1.r1cf(m0pai ^ 3);
    root1.r1cfi(m0pai ^ 4);
    mod0.m0cf(m0pai ^ 5);
    mod0.m0cfi(m0pai ^ 6);
    mod1.m1cf(m0pai ^ 7);
    mod1.m1cfi(m0pai ^ 8);
}
pub fn m0cf(m0ca: u32) void {
    var discard = m0ca;
    _ = &discard;
}
pub inline fn m0cfi(m0cai: u32) void {
    var discard = m0cai;
    _ = &discard;
}
