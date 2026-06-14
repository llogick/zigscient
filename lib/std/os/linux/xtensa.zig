const builtin = @import("builtin");
const std = @import("../../std.zig");
const SYS = std.os.linux.SYS;

pub const syscall_arg_t = u32;

pub fn syscall0(
    number: SYS,
) u32 {
    return asm volatile ("syscall"
        : [ret] "={a2}" (-> u32),
        : [number] "{a2}" (@intFromEnum(number)),
        : .{ .memory = true });
}

pub fn syscall1(
    number: SYS,
    arg1: syscall_arg_t,
) u32 {
    return asm volatile ("syscall"
        : [ret] "={a2}" (-> u32),
        : [number] "{a2}" (@intFromEnum(number)),
          [arg1] "{a6}" (arg1),
        : .{ .memory = true });
}

pub fn syscall2(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
) u32 {
    return asm volatile ("syscall"
        : [ret] "={a2}" (-> u32),
        : [number] "{a2}" (@intFromEnum(number)),
          [arg1] "{a6}" (arg1),
          [arg2] "{a3}" (arg2),
        : .{ .memory = true });
}

pub fn syscall3(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
    arg3: syscall_arg_t,
) u32 {
    return asm volatile ("syscall"
        : [ret] "={a2}" (-> u32),
        : [number] "{a2}" (@intFromEnum(number)),
          [arg1] "{a6}" (arg1),
          [arg2] "{a3}" (arg2),
          [arg3] "{a4}" (arg3),
        : .{ .memory = true });
}

pub fn syscall4(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
    arg3: syscall_arg_t,
    arg4: syscall_arg_t,
) u32 {
    return asm volatile ("syscall"
        : [ret] "={a2}" (-> u32),
        : [number] "{a2}" (@intFromEnum(number)),
          [arg1] "{a6}" (arg1),
          [arg2] "{a3}" (arg2),
          [arg3] "{a4}" (arg3),
          [arg4] "{a5}" (arg4),
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
    return asm volatile ("syscall"
        : [ret] "={a2}" (-> u32),
        : [number] "{a2}" (@intFromEnum(number)),
          [arg1] "{a6}" (arg1),
          [arg2] "{a3}" (arg2),
          [arg3] "{a4}" (arg3),
          [arg4] "{a5}" (arg4),
          [arg5] "{a8}" (arg5),
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
    return asm volatile ("syscall"
        : [ret] "={a2}" (-> u32),
        : [number] "{a2}" (@intFromEnum(number)),
          [arg1] "{a6}" (arg1),
          [arg2] "{a3}" (arg2),
          [arg3] "{a4}" (arg3),
          [arg4] "{a5}" (arg4),
          [arg5] "{a8}" (arg5),
          [arg6] "{a9}" (arg6),
        : .{ .memory = true });
}

pub fn clone() callconv(.naked) u32 {
    // __clone(func, stack, flags, arg, ptid, tls, ctid)
    //         a2,   a3,    a4,    a5,  a6,   a7,  +16
    //
    // syscall(SYS_clone, flags, stack, ptid, tls, ctid)
    //         a2         a6,    a3,    a4,   a5,  a8
    if (builtin.abi != .call0) asm volatile (
        \\ entry sp, 16
    );
    asm volatile (
        \\ movi a8, -16
        \\ and a3, a3, a8
        \\
        \\ mov a9, a2
        \\ mov a10, a5
        \\
        \\ mov a5, a7
        \\ mov a8, a6
        \\ mov a6, a4
        \\ mov a4, a8
    );
    if (builtin.abi == .call0) asm volatile (
        \\ l32i a8, sp, 0
    ) else asm volatile (
        \\ l32i a8, sp, 16
    );
    asm volatile (
        \\ movi a2, 116 // SYS_clone
        \\ syscall
    );
    if (builtin.abi == .call0) asm volatile (
        \\ beqz a2, 1f
        \\ // parent
        \\ ret
        \\
        \\ // child
        \\1:
        \\ movi a15, 0
        \\ movi a0, 0
        \\
        \\ mov a2, a10
        \\ callx0 a9
    ) else asm volatile (
        \\ beqz a2, 1f
        \\ // parent
        \\ retw
        \\
        \\ // child
        \\1:
        \\ movi a7, 0
        \\ movi a0, 0
        \\
        \\ mov a6, a10
        \\ callx4 a9
    );
    asm volatile (
        \\ movi a2, 118 // SYS_exit
        \\ syscall
    );
}

pub const restore = restore_rt;

pub fn restore_rt() callconv(.naked) noreturn {
    switch (builtin.zig_backend) {
        .stage2_c => asm volatile (
            \\ movi a2, %[number]
            \\ syscall
            :
            : [number] "I" (@intFromEnum(SYS.rt_sigreturn)),
        ),
        else => asm volatile (
            \\ syscall
            :
            : [number] "{a2}" (@intFromEnum(SYS.rt_sigreturn)),
        ),
    }
}

pub const VDSO = void;

pub const time_t = i32;
