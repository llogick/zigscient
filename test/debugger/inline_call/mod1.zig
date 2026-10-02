const root0 = @import("root");
const root1 = root0.root1;
const mod0 = @import("mod0.zig");
const mod1 = @This();
pub fn m1pf(m1pa: u32) void {
    root0.r0cf(m1pa ^ 1);
    root0.r0cfi(m1pa ^ 2);
    root1.r1cf(m1pa ^ 3);
    root1.r1cfi(m1pa ^ 4);
    mod0.m0cf(m1pa ^ 5);
    mod0.m0cfi(m1pa ^ 6);
    mod1.m1cf(m1pa ^ 7);
    mod1.m1cfi(m1pa ^ 8);
}
pub inline fn m1pfi(m1pai: u32) void {
    root0.r0cf(m1pai ^ 1);
    root0.r0cfi(m1pai ^ 2);
    root1.r1cf(m1pai ^ 3);
    root1.r1cfi(m1pai ^ 4);
    mod0.m0cf(m1pai ^ 5);
    mod0.m0cfi(m1pai ^ 6);
    mod1.m1cf(m1pai ^ 7);
    mod1.m1cfi(m1pai ^ 8);
}
pub fn m1cf(m1ca: u32) void {
    var discard = m1ca;
    _ = &discard;
}
pub inline fn m1cfi(m1cai: u32) void {
    var discard = m1cai;
    _ = &discard;
}
