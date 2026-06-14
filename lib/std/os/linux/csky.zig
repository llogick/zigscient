const builtin = @import("builtin");
const std = @import("../../std.zig");
const SYS = std.os.linux.SYS;

pub const syscall_arg_t = u32;

pub fn syscall0(
    number: SYS,
) u32 {
    return asm volatile ("trap 0"
        : [ret] "={r0}" (-> u32),
        : [number] "{r7}" (@intFromEnum(number)),
        : .{ .memory = true });
}

pub fn syscall1(
    number: SYS,
    arg1: syscall_arg_t,
) u32 {
    return asm volatile ("trap 0"
        : [ret] "={r0}" (-> u32),
        : [number] "{r7}" (@intFromEnum(number)),
          [arg1] "{r0}" (arg1),
        : .{ .memory = true });
}

pub fn syscall2(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
) u32 {
    return asm volatile ("trap 0"
        : [ret] "={r0}" (-> u32),
        : [number] "{r7}" (@intFromEnum(number)),
          [arg1] "{r0}" (arg1),
          [arg2] "{r1}" (arg2),
        : .{ .memory = true });
}

pub fn syscall3(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
    arg3: syscall_arg_t,
) u32 {
    return asm volatile ("trap 0"
        : [ret] "={r0}" (-> u32),
        : [number] "{r7}" (@intFromEnum(number)),
          [arg1] "{r0}" (arg1),
          [arg2] "{r1}" (arg2),
          [arg3] "{r2}" (arg3),
        : .{ .memory = true });
}

pub fn syscall4(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
    arg3: syscall_arg_t,
    arg4: syscall_arg_t,
) u32 {
    return asm volatile ("trap 0"
        : [ret] "={r0}" (-> u32),
        : [number] "{r7}" (@intFromEnum(number)),
          [arg1] "{r0}" (arg1),
          [arg2] "{r1}" (arg2),
          [arg3] "{r2}" (arg3),
          [arg4] "{r3}" (arg4),
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
    return asm volatile ("trap 0"
        : [ret] "={r0}" (-> u32),
        : [number] "{r7}" (@intFromEnum(number)),
          [arg1] "{r0}" (arg1),
          [arg2] "{r1}" (arg2),
          [arg3] "{r2}" (arg3),
          [arg4] "{r3}" (arg4),
          [arg5] "{r4}" (arg5),
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
    return asm volatile ("trap 0"
        : [ret] "={r0}" (-> u32),
        : [number] "{r7}" (@intFromEnum(number)),
          [arg1] "{r0}" (arg1),
          [arg2] "{r1}" (arg2),
          [arg3] "{r2}" (arg3),
          [arg4] "{r3}" (arg4),
          [arg5] "{r4}" (arg5),
          [arg6] "{r5}" (arg6),
        : .{ .memory = true });
}

pub fn clone() callconv(.naked) u32 {
    // __clone(func, stack, flags, arg, ptid, tls, ctid)
    //         r0,   r1,    r2,    r3,  +0,   +4,  +8
    //
    // syscall(SYS_clone, flags, stack, ptid, tls, ctid)
    //         r7         r0,    r1,    r2,   r3,  r4
    asm volatile (
        \\ // Preserve callee-saved registers.
        \\ mov t0, r4
        \\ mov t1, r7
        \\
        \\ andi r1, r1, -8
        \\
        \\ subi r1, 8
        \\ stw r0, (r1, 0)
        \\ stw r3, (r1, 4)
        \\
        \\ movi r7, 220 // SYS_clone
        \\ mov r0, r2
        \\ ldw r2, (sp, 0)
        \\ ldw r3, (sp, 8)
        \\ ldw r4, (sp, 4)
        \\ trap 0
        \\
        \\ cmpnei r0, 0
        \\ jbf 1f
        \\
        \\ // parent
        \\ mov r7, t1
        \\ mov r4, t0
        \\ rts
        \\
        \\ // child
        \\1:
    );
    if (builtin.unwind_tables != .none or !builtin.strip_debug_info) asm volatile (
        \\ .cfi_undefined lr
    );
    asm volatile (
        \\ movi r8, 0
        \\ movi lr, 0
        \\
        \\ ldw r0, (sp, 4)
        \\ ldw r1, (sp, 0)
        \\ jsr r1
        \\
        \\ movi r7, 93 // SYS_exit
        \\ trap 0
    );
}

pub const time_t = i32;

pub const VDSO = void;
