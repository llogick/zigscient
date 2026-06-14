const builtin = @import("builtin");
const std = @import("../../std.zig");
const SYS = std.os.linux.SYS;

pub const syscall_arg_t = u64;

pub fn syscall0(
    number: SYS,
) u64 {
    return asm volatile ("svc #0"
        : [ret] "={x0}" (-> u64),
        : [number] "{x8}" (@intFromEnum(number)),
        : .{ .memory = true });
}

pub fn syscall1(
    number: SYS,
    arg1: syscall_arg_t,
) u64 {
    return asm volatile ("svc #0"
        : [ret] "={x0}" (-> u64),
        : [number] "{x8}" (@intFromEnum(number)),
          [arg1] "{x0}" (arg1),
        : .{ .memory = true });
}

pub fn syscall2(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
) u64 {
    return asm volatile ("svc #0"
        : [ret] "={x0}" (-> u64),
        : [number] "{x8}" (@intFromEnum(number)),
          [arg1] "{x0}" (arg1),
          [arg2] "{x1}" (arg2),
        : .{ .memory = true });
}

pub fn syscall3(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
    arg3: syscall_arg_t,
) u64 {
    return asm volatile ("svc #0"
        : [ret] "={x0}" (-> u64),
        : [number] "{x8}" (@intFromEnum(number)),
          [arg1] "{x0}" (arg1),
          [arg2] "{x1}" (arg2),
          [arg3] "{x2}" (arg3),
        : .{ .memory = true });
}

pub fn syscall4(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
    arg3: syscall_arg_t,
    arg4: syscall_arg_t,
) u64 {
    return asm volatile ("svc #0"
        : [ret] "={x0}" (-> u64),
        : [number] "{x8}" (@intFromEnum(number)),
          [arg1] "{x0}" (arg1),
          [arg2] "{x1}" (arg2),
          [arg3] "{x2}" (arg3),
          [arg4] "{x3}" (arg4),
        : .{ .memory = true });
}

pub fn syscall5(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
    arg3: syscall_arg_t,
    arg4: syscall_arg_t,
    arg5: syscall_arg_t,
) u64 {
    return asm volatile ("svc #0"
        : [ret] "={x0}" (-> u64),
        : [number] "{x8}" (@intFromEnum(number)),
          [arg1] "{x0}" (arg1),
          [arg2] "{x1}" (arg2),
          [arg3] "{x2}" (arg3),
          [arg4] "{x3}" (arg4),
          [arg5] "{x4}" (arg5),
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
) u64 {
    return asm volatile ("svc #0"
        : [ret] "={x0}" (-> u64),
        : [number] "{x8}" (@intFromEnum(number)),
          [arg1] "{x0}" (arg1),
          [arg2] "{x1}" (arg2),
          [arg3] "{x2}" (arg3),
          [arg4] "{x3}" (arg4),
          [arg5] "{x4}" (arg5),
          [arg6] "{x5}" (arg6),
        : .{ .memory = true });
}

pub fn clone() callconv(.naked) u64 {
    // __clone(func, stack, flags, arg, ptid, tls, ctid)
    //         x0,   x1,    w2,    x3,  x4,   x5,  x6
    //
    // syscall(SYS_clone, flags, stack, ptid, tls, ctid)
    //         x8,        x0,    x1,    x2,   x3,  x4
    asm volatile (
        \\      // align stack and save func,arg
        \\      and x1,x1,#-16
        \\      stp x0,x3,[x1,#-16]!
        \\
        \\      // syscall
        \\      uxtw x0,w2
        \\      mov x2,x4
        \\      mov x3,x5
        \\      mov x4,x6
        \\      mov x8,#220 // SYS_clone
        \\      svc #0
        \\
        \\      cbz x0,1f
        \\      // parent
        \\      ret
        \\
        \\      // child
        \\1:
    );
    if (builtin.unwind_tables != .none or !builtin.strip_debug_info) asm volatile (
        \\     .cfi_undefined lr
    );
    asm volatile (
        \\      mov fp, 0
        \\      mov lr, 0
        \\
        \\      ldp x1,x0,[sp],#16
        \\      blr x1
        \\      mov x8,#93 // SYS_exit
        \\      svc #0
    );
}

pub const restore = restore_rt;

pub fn restore_rt() callconv(.naked) noreturn {
    switch (builtin.zig_backend) {
        .stage2_c => asm volatile (
            \\ mov x8, %[number]
            \\ svc #0
            :
            : [number] "i" (@intFromEnum(SYS.rt_sigreturn)),
        ),
        else => asm volatile (
            \\ svc #0
            :
            : [number] "{x8}" (@intFromEnum(SYS.rt_sigreturn)),
        ),
    }
}

pub const VDSO = struct {
    pub const CGT_SYM = "__kernel_clock_gettime";
    pub const CGT_VER = "LINUX_2.6.39";
};

pub const time_t = i64;
