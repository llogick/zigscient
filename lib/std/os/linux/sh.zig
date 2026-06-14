const builtin = @import("builtin");
const std = @import("../../std.zig");
const SYS = std.os.linux.SYS;

pub const syscall_arg_t = u32;

pub fn syscall0(
    number: SYS,
) u32 {
    return asm volatile (
        \\ trapa #31
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        : [ret] "={r0}" (-> u32),
        : [number] "{r3}" (@intFromEnum(number)),
        : .{ .memory = true });
}

pub fn syscall1(
    number: SYS,
    arg1: syscall_arg_t,
) u32 {
    return asm volatile (
        \\ trapa #31
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        : [ret] "={r0}" (-> u32),
        : [number] "{r3}" (@intFromEnum(number)),
          [arg1] "{r4}" (arg1),
        : .{ .memory = true });
}

pub fn syscall2(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
) u32 {
    return asm volatile (
        \\ trapa #31
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        : [ret] "={r0}" (-> u32),
        : [number] "{r3}" (@intFromEnum(number)),
          [arg1] "{r4}" (arg1),
          [arg2] "{r5}" (arg2),
        : .{ .memory = true });
}

pub fn syscall3(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
    arg3: syscall_arg_t,
) u32 {
    return asm volatile (
        \\ trapa #31
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        : [ret] "={r0}" (-> u32),
        : [number] "{r3}" (@intFromEnum(number)),
          [arg1] "{r4}" (arg1),
          [arg2] "{r5}" (arg2),
          [arg3] "{r6}" (arg3),
        : .{ .memory = true });
}

pub fn syscall4(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
    arg3: syscall_arg_t,
    arg4: syscall_arg_t,
) u32 {
    return asm volatile (
        \\ trapa #31
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        : [ret] "={r0}" (-> u32),
        : [number] "{r3}" (@intFromEnum(number)),
          [arg1] "{r4}" (arg1),
          [arg2] "{r5}" (arg2),
          [arg3] "{r6}" (arg3),
          [arg4] "{r7}" (arg4),
        : .{ .memory = true });
}

pub fn syscall5(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
    arg3: syscall_arg_t,
    arg4: syscall_arg_t,
    arg5: syscall_arg_t,
) u32 {
    return asm volatile (
        \\ trapa #31
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        : [ret] "={r0}" (-> u32),
        : [number] "{r3}" (@intFromEnum(number)),
          [arg1] "{r4}" (arg1),
          [arg2] "{r5}" (arg2),
          [arg3] "{r6}" (arg3),
          [arg4] "{r7}" (arg4),
          [arg5] "{r0}" (arg5),
        : .{ .memory = true });
}

pub fn syscall6(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
    arg3: syscall_arg_t,
    arg4: syscall_arg_t,
    arg5: syscall_arg_t,
    arg6: syscall_arg_t,
) u32 {
    return asm volatile (
        \\ trapa #31
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        : [ret] "={r0}" (-> u32),
        : [number] "{r3}" (@intFromEnum(number)),
          [arg1] "{r4}" (arg1),
          [arg2] "{r5}" (arg2),
          [arg3] "{r6}" (arg3),
          [arg4] "{r7}" (arg4),
          [arg5] "{r0}" (arg5),
          [arg6] "{r1}" (arg6),
        : .{ .memory = true });
}

pub fn clone() callconv(.naked) u32 {
    // __clone(func, stack, flags, arg, ptid, tls, ctid)
    //         r4,   r5,    r6,    r7,  +0,   +4,  +8
    //
    // syscall(SYS_clone, flags, stack, ptid, ctid, tls)
    //         r3         r4,    r5,    r6,   r7,   r0
    asm volatile (
        \\ mov #-4, r0
        \\ and r0, r5
        \\
        \\ mov r4, r1
        \\ mov r7, r2
        \\
        \\ mov #120, r3 ! SYS_clone
        \\ mov r6, r4
        \\ mov.l @r15, r6
        \\ mov.l @(r15, 8), r7
        \\ mov.l @(r15, 4), r0
        \\ trapa #31
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        \\
        \\ cmp/eq #0, r0
        \\ bt 1f
        \\
        \\ // parent
        \\ rts
        \\  nop
        \\
        \\ // child
        \\1:
    );
    if (builtin.unwind_tables != .none or !builtin.strip_debug_info) asm volatile (
        \\ .cfi_undefined pr
    );
    asm volatile (
        \\ mov #0, r0
        \\ lds r0, pr
        \\ mov r0, r14
        \\
        \\ mov r2, r4
        \\ jsr @r1
        \\  nop
        \\
        \\ mov #1, r3 ! SYS_exit
        \\ trapa #31
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
    );
}

pub fn restore() callconv(.naked) noreturn {
    asm volatile (
        \\ trapa #31
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        :
        : [number] "{r3}" (@intFromEnum(SYS.sigreturn)),
    );
}

pub fn restore_rt() callconv(.naked) noreturn {
    asm volatile (
        \\ trapa #31
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        \\ or r0, r0
        :
        : [number] "{r3}" (@intFromEnum(SYS.rt_sigreturn)),
    );
}

pub const time_t = i32;

pub const VDSO = void;
