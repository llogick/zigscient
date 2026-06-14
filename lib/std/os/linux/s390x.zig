const builtin = @import("builtin");
const std = @import("../../std.zig");
const SYS = std.os.linux.SYS;

pub const syscall_arg_t = u64;

pub fn syscall0(
    number: SYS,
) u64 {
    return asm volatile ("svc 0"
        : [ret] "={r2}" (-> u64),
        : [number] "{r1}" (@intFromEnum(number)),
        : .{ .memory = true });
}

pub fn syscall1(
    number: SYS,
    arg1: syscall_arg_t,
) u64 {
    return asm volatile ("svc 0"
        : [ret] "={r2}" (-> u64),
        : [number] "{r1}" (@intFromEnum(number)),
          [arg1] "{r2}" (arg1),
        : .{ .memory = true });
}

pub fn syscall2(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
) u64 {
    return asm volatile ("svc 0"
        : [ret] "={r2}" (-> u64),
        : [number] "{r1}" (@intFromEnum(number)),
          [arg1] "{r2}" (arg1),
          [arg2] "{r3}" (arg2),
        : .{ .memory = true });
}

pub fn syscall3(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
    arg3: syscall_arg_t,
) u64 {
    return asm volatile ("svc 0"
        : [ret] "={r2}" (-> u64),
        : [number] "{r1}" (@intFromEnum(number)),
          [arg1] "{r2}" (arg1),
          [arg2] "{r3}" (arg2),
          [arg3] "{r4}" (arg3),
        : .{ .memory = true });
}

pub fn syscall4(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
    arg3: syscall_arg_t,
    arg4: syscall_arg_t,
) u64 {
    return asm volatile ("svc 0"
        : [ret] "={r2}" (-> u64),
        : [number] "{r1}" (@intFromEnum(number)),
          [arg1] "{r2}" (arg1),
          [arg2] "{r3}" (arg2),
          [arg3] "{r4}" (arg3),
          [arg4] "{r5}" (arg4),
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
    return asm volatile ("svc 0"
        : [ret] "={r2}" (-> u64),
        : [number] "{r1}" (@intFromEnum(number)),
          [arg1] "{r2}" (arg1),
          [arg2] "{r3}" (arg2),
          [arg3] "{r4}" (arg3),
          [arg4] "{r5}" (arg4),
          [arg5] "{r6}" (arg5),
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
    return asm volatile ("svc 0"
        : [ret] "={r2}" (-> u64),
        : [number] "{r1}" (@intFromEnum(number)),
          [arg1] "{r2}" (arg1),
          [arg2] "{r3}" (arg2),
          [arg3] "{r4}" (arg3),
          [arg4] "{r5}" (arg4),
          [arg5] "{r6}" (arg5),
          [arg6] "{r7}" (arg6),
        : .{ .memory = true });
}

pub fn clone() callconv(.naked) u64 {
    asm volatile (
        \\# int clone(
        \\#    fn,      a = r2
        \\#    stack,   b = r3
        \\#    flags,   c = r4
        \\#    arg,     d = r5
        \\#    ptid,    e = r6
        \\#    tls,     f = *(r15+160)
        \\#    ctid)    g = *(r15+168)
        \\#
        \\# pseudo C code:
        \\# tid = syscall(SYS_clone,b,c,e,g,f);
        \\# if (!tid) syscall(SYS_exit, a(d));
        \\# return tid;
        \\
        \\# preserve call-saved register used as syscall arg
        \\stg  %%r6, 48(%%r15)
        \\
        \\# create initial stack frame for new thread
        \\nill %%r3, 0xfff8
        \\aghi %%r3, -160
        \\lghi %%r0, 0
        \\stg  %%r0, 0(%%r3)
        \\
        \\# save fn and arg to child stack
        \\stg  %%r2,  8(%%r3)
        \\stg  %%r5, 16(%%r3)
        \\
        \\# shuffle args into correct registers and call SYS_clone
        \\lgr  %%r2, %%r3
        \\lgr  %%r3, %%r4
        \\lgr  %%r4, %%r6
        \\lg   %%r5, 168(%%r15)
        \\lg   %%r6, 160(%%r15)
        \\svc  120
        \\
        \\# restore call-saved register
        \\lg   %%r6, 48(%%r15)
        \\
        \\# if error or if we're the parent, return
        \\ltgr %%r2, %%r2
        \\bnzr %%r14
        \\
        \\# we're the child
    );
    if (builtin.unwind_tables != .none or !builtin.strip_debug_info) asm volatile (
        \\.cfi_undefined %%r14
    );
    asm volatile (
        \\lghi %%r11, 0
        \\lghi %%r14, 0
        \\
        \\# call fn(arg)
        \\lg   %%r1,  8(%%r15)
        \\lg   %%r2, 16(%%r15)
        \\basr %%r14, %%r1
        \\
        \\# call SYS_exit. exit code is already in r2 from fn return value
        \\svc  1
        \\
    );
}

pub fn restore() callconv(.naked) noreturn {
    asm volatile (
        \\svc 0
        :
        : [number] "{r1}" (@intFromEnum(SYS.sigreturn)),
    );
}

pub fn restore_rt() callconv(.naked) noreturn {
    asm volatile (
        \\svc 0
        :
        : [number] "{r1}" (@intFromEnum(SYS.rt_sigreturn)),
    );
}

pub const time_t = i64;

pub const VDSO = struct {
    pub const CGT_SYM = "__kernel_clock_gettime";
    pub const CGT_VER = "LINUX_2.6.29";
};
