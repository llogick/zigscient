const builtin = @import("builtin");
const std = @import("../../std.zig");
const SYS = std.os.linux.SYS;

pub const syscall_arg_t = u64;

pub fn syscall0(
    number: SYS,
) u64 {
    return asm volatile ("ecall"
        : [ret] "={x10}" (-> u64),
        : [number] "{x17}" (@intFromEnum(number)),
        : .{ .memory = true });
}

pub fn syscall1(
    number: SYS,
    arg1: syscall_arg_t,
) u64 {
    return asm volatile ("ecall"
        : [ret] "={x10}" (-> u64),
        : [number] "{x17}" (@intFromEnum(number)),
          [arg1] "{x10}" (arg1),
        : .{ .memory = true });
}

pub fn syscall2(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
) u64 {
    return asm volatile ("ecall"
        : [ret] "={x10}" (-> u64),
        : [number] "{x17}" (@intFromEnum(number)),
          [arg1] "{x10}" (arg1),
          [arg2] "{x11}" (arg2),
        : .{ .memory = true });
}

pub fn syscall3(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
    arg3: syscall_arg_t,
) u64 {
    return asm volatile ("ecall"
        : [ret] "={x10}" (-> u64),
        : [number] "{x17}" (@intFromEnum(number)),
          [arg1] "{x10}" (arg1),
          [arg2] "{x11}" (arg2),
          [arg3] "{x12}" (arg3),
        : .{ .memory = true });
}

pub fn syscall4(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
    arg3: syscall_arg_t,
    arg4: syscall_arg_t,
) u64 {
    return asm volatile ("ecall"
        : [ret] "={x10}" (-> u64),
        : [number] "{x17}" (@intFromEnum(number)),
          [arg1] "{x10}" (arg1),
          [arg2] "{x11}" (arg2),
          [arg3] "{x12}" (arg3),
          [arg4] "{x13}" (arg4),
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
    return asm volatile ("ecall"
        : [ret] "={x10}" (-> u64),
        : [number] "{x17}" (@intFromEnum(number)),
          [arg1] "{x10}" (arg1),
          [arg2] "{x11}" (arg2),
          [arg3] "{x12}" (arg3),
          [arg4] "{x13}" (arg4),
          [arg5] "{x14}" (arg5),
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
    return asm volatile ("ecall"
        : [ret] "={x10}" (-> u64),
        : [number] "{x17}" (@intFromEnum(number)),
          [arg1] "{x10}" (arg1),
          [arg2] "{x11}" (arg2),
          [arg3] "{x12}" (arg3),
          [arg4] "{x13}" (arg4),
          [arg5] "{x14}" (arg5),
          [arg6] "{x15}" (arg6),
        : .{ .memory = true });
}

pub fn clone() callconv(.naked) u64 {
    // __clone(func, stack, flags, arg, ptid, tls, ctid)
    //         a0,   a1,    a2,    a3,  a4,   a5,  a6
    //
    // syscall(SYS_clone, flags, stack, ptid, tls, ctid)
    //         a7         a0,    a1,    a2,   a3,  a4
    asm volatile (
        \\    # Save func and arg to stack
        \\    addi a1, a1, -16
        \\    sd a0, 0(a1)
        \\    sd a3, 8(a1)
        \\
        \\    # Call SYS_clone
        \\    mv a0, a2
        \\    mv a2, a4
        \\    mv a3, a5
        \\    mv a4, a6
        \\    li a7, 220 # SYS_clone
        \\    ecall
        \\
        \\    beqz a0, 1f
        \\    # Parent
        \\    ret
        \\
        \\    # Child
        \\1:
    );
    if (builtin.unwind_tables != .none or !builtin.strip_debug_info) asm volatile (
        \\    .cfi_undefined ra
    );
    asm volatile (
        \\    mv fp, zero
        \\    mv ra, zero
        \\
        \\    ld a1, 0(sp)
        \\    ld a0, 8(sp)
        \\    jalr a1
        \\
        \\    # Exit
        \\    li a7, 93 # SYS_exit
        \\    ecall
    );
}

pub const time_t = i64;

pub const VDSO = struct {
    pub const CGT_SYM = "__vdso_clock_gettime";
    pub const CGT_VER = "LINUX_4.15";
};
