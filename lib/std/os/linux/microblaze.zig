const builtin = @import("builtin");
const std = @import("../../std.zig");
const SYS = std.os.linux.SYS;

pub const syscall_arg_t = u32;

pub fn syscall0(
    number: SYS,
) u32 {
    return asm volatile ("brki r14, 0x8"
        : [ret] "={r3}" (-> u32),
        : [number] "{r12}" (@intFromEnum(number)),
        : .{ .r4 = true, .memory = true });
}

pub fn syscall1(
    number: SYS,
    arg1: syscall_arg_t,
) u32 {
    return asm volatile ("brki r14, 0x8"
        : [ret] "={r3}" (-> u32),
        : [number] "{r12}" (@intFromEnum(number)),
          [arg1] "{r5}" (arg1),
        : .{ .r4 = true, .memory = true });
}

pub fn syscall2(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
) u32 {
    return asm volatile ("brki r14, 0x8"
        : [ret] "={r3}" (-> u32),
        : [number] "{r12}" (@intFromEnum(number)),
          [arg1] "{r5}" (arg1),
          [arg2] "{r6}" (arg2),
        : .{ .r4 = true, .memory = true });
}

pub fn syscall3(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
    arg3: syscall_arg_t,
) u32 {
    return asm volatile ("brki r14, 0x8"
        : [ret] "={r3}" (-> u32),
        : [number] "{r12}" (@intFromEnum(number)),
          [arg1] "{r5}" (arg1),
          [arg2] "{r6}" (arg2),
          [arg3] "{r7}" (arg3),
        : .{ .r4 = true, .memory = true });
}

pub fn syscall4(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
    arg3: syscall_arg_t,
    arg4: syscall_arg_t,
) u32 {
    return asm volatile ("brki r14, 0x8"
        : [ret] "={r3}" (-> u32),
        : [number] "{r12}" (@intFromEnum(number)),
          [arg1] "{r5}" (arg1),
          [arg2] "{r6}" (arg2),
          [arg3] "{r7}" (arg3),
          [arg4] "{r8}" (arg4),
        : .{ .r4 = true, .memory = true });
}

pub fn syscall5(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
    arg3: syscall_arg_t,
    arg4: syscall_arg_t,
    arg5: syscall_arg_t,
) u32 {
    return asm volatile ("brki r14, 0x8"
        : [ret] "={r3}" (-> u32),
        : [number] "{r12}" (@intFromEnum(number)),
          [arg1] "{r5}" (arg1),
          [arg2] "{r6}" (arg2),
          [arg3] "{r7}" (arg3),
          [arg4] "{r8}" (arg4),
          [arg5] "{r9}" (arg5),
        : .{ .r4 = true, .memory = true });
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
    return asm volatile ("brki r14, 0x8"
        : [ret] "={r3}" (-> u32),
        : [number] "{r12}" (@intFromEnum(number)),
          [arg1] "{r5}" (arg1),
          [arg2] "{r6}" (arg2),
          [arg3] "{r7}" (arg3),
          [arg4] "{r8}" (arg4),
          [arg5] "{r9}" (arg5),
          [arg6] "{r10}" (arg6),
        : .{ .r4 = true, .memory = true });
}

pub fn clone() callconv(.naked) u32 {
    // __clone(func, stack, flags, arg, ptid, tls, ctid)
    //         r5,   r6,    r7,    r8,  r9,   r10, +28
    //
    // syscall(SYS_clone, flags, stack, ptid, ctid, tls)
    //         r12        r5,    r6,    r8,   r9,   r10
    asm volatile (
        \\ andi r6, r6, -4
        \\
        \\ addi r6, r6, -8
        \\ swi r5, r6, 0
        \\ swi r8, r6, 4
        \\
        \\ ori r12, r0, 120 # SYS_clone
        \\ ori r5, r7, 0
        \\ ori r7, r0, 0 # stack size
        \\ ori r8, r9, 0
        \\ lwi r9, r1, 28
        \\ brki r14, 0x8
        \\ beqi r3, 1f
        \\
        \\ // parent
        \\ rtsd r15, 8
        \\  nop
        \\
        \\ // child
        \\1:
        \\ ori r15, r0, 0
        \\ ori r19, r0, 0
        \\
        \\ lwi r3, r1, 0
        \\ lwi r5, r1, 4
        \\ brald r15, r3
        \\  nop
        \\
        \\ ori r12, r0, 1 # SYS_exit
        \\ brki r14, 0x8
    );
}

pub fn restore() callconv(.naked) noreturn {
    asm volatile (
        \\ brki r14, 0x8
        :
        : [number] "{r7}" (@intFromEnum(SYS.sigreturn)),
    );
}

pub fn restore_rt() callconv(.naked) noreturn {
    asm volatile (
        \\ brki r14, 0x8
        :
        : [number] "{r7}" (@intFromEnum(SYS.rt_sigreturn)),
    );
}

pub const time_t = i32;

pub const VDSO = void;
