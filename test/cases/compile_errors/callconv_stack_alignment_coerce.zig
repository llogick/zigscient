fn foo() callconv(.{ .x86_64_sysv = .{ .incoming_stack_alignment = 32 } }) void {}
const Bar = *const fn () callconv(.{ .x86_64_sysv = .{ .incoming_stack_alignment = 16 } }) void;
export var p: Bar = &foo;

// error
// target=x86_64-linux-none
//
// :3:21: error: expected type '*const fn () callconv(.{ .x86_64_sysv = .{ .incoming_stack_alignment = 16 } }) void', found '*const fn () callconv(.{ .x86_64_sysv = .{ .incoming_stack_alignment = 32 } }) void'
// :3:21: note: pointer type child 'fn () callconv(.{ .x86_64_sysv = .{ .incoming_stack_alignment = 32 } }) void' cannot cast into pointer type child 'fn () callconv(.{ .x86_64_sysv = .{ .incoming_stack_alignment = 16 } }) void'
// :3:21: note: calling convention 'x86_64_sysv' cannot cast into calling convention 'x86_64_sysv'
