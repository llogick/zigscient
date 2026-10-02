const root0 = @import("root0.zig");
const root1 = @This();
const mod0 = @import("module");
const mod1 = mod0.mod1;
pub fn r1pf(r1pa: u32) void {
    root0.r0cf(r1pa ^ 1);
    root0.r0cfi(r1pa ^ 2);
    root1.r1cf(r1pa ^ 3);
    root1.r1cfi(r1pa ^ 4);
    mod0.m0cf(r1pa ^ 5);
    mod0.m0cfi(r1pa ^ 6);
    mod1.m1cf(r1pa ^ 7);
    mod1.m1cfi(r1pa ^ 8);
}
pub inline fn r1pfi(r1pai: u32) void {
    root0.r0cf(r1pai ^ 1);
    root0.r0cfi(r1pai ^ 2);
    root1.r1cf(r1pai ^ 3);
    root1.r1cfi(r1pai ^ 4);
    mod0.m0cf(r1pai ^ 5);
    mod0.m0cfi(r1pai ^ 6);
    mod1.m1cf(r1pai ^ 7);
    mod1.m1cfi(r1pai ^ 8);
}
pub fn r1cf(r1ca: u32) void {
    var discard = r1ca;
    _ = &discard;
}
pub inline fn r1cfi(r1cai: u32) void {
    var discard = r1cai;
    _ = &discard;
}
