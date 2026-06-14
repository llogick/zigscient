export fn zig_panic() void {
    @panic("called zig_panic");
}
pub const _start = {}; // entry point is in main.m
