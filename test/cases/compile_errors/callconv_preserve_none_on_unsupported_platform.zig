const F1 = fn () callconv(.{ .x86_64_preserve_none = .{} }) void;
const F2 = fn () callconv(.{ .aarch64_preserve_none = .{} }) void;
export fn entry1() void {
    const a: F1 = undefined;
    _ = a;
}
export fn entry2() void {
    const a: F2 = undefined;
    _ = a;
}

// error
// target=riscv64-linux-none
//
// :1:28: error: calling convention 'x86_64_preserve_none' only available on architectures 'x86_64'
// :2:28: error: calling convention 'aarch64_preserve_none' only available on architectures 'aarch64', 'aarch64_be'
