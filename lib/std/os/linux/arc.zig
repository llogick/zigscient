const builtin = @import("builtin");
const std = @import("../../std.zig");
const SYS = std.os.linux.SYS;

pub const syscall_arg_t = u32;

pub fn syscall0(
    number: SYS,
) u32 {
    return asm volatile ("trap_s 0"
        : [ret] "={r0}" (-> u32),
        : [number] "{r8}" (@intFromEnum(number)),
        : .{ .memory = true });
}

pub fn syscall1(
    number: SYS,
    arg1: syscall_arg_t,
) u32 {
    return asm volatile ("trap_s 0"
        : [ret] "={r0}" (-> u32),
        : [number] "{r8}" (@intFromEnum(number)),
          [arg1] "{r0}" (arg1),
        : .{ .memory = true });
}

pub fn syscall2(
    number: SYS,
    arg1: syscall_arg_t,
    arg2: syscall_arg_t,
) u32 {
    return asm volatile ("trap_s 0"
        : [ret] "={r0}" (-> u32),
        : [number] "{r8}" (@intFromEnum(number)),
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
    return asm volatile ("trap_s 0"
        : [ret] "={r0}" (-> u32),
        : [number] "{r8}" (@intFromEnum(number)),
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
    return asm volatile ("trap_s 0"
        : [ret] "={r0}" (-> u32),
        : [number] "{r8}" (@intFromEnum(number)),
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
    return asm volatile ("trap_s 0"
        : [ret] "={r0}" (-> u32),
        : [number] "{r8}" (@intFromEnum(number)),
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
    return asm volatile ("trap_s 0"
        : [ret] "={r0}" (-> u32),
        : [number] "{r8}" (@intFromEnum(number)),
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
    //         r0,   r1,    r2,    r3,  r4,   r5,  r6
    //
    // syscall(SYS_clone, flags, stack, ptid, tls, ctid)
    //         r8         r0,    r1,    r2,   r3,  r4
    asm volatile (
        \\    // Align stack pointer
        \\    and r1, r1, -16
        \\    mov r10, r0
        \\    mov r11, r3
        \\    // Setup the arguments
        \\    mov r0, r2
        \\    mov r2, r4
        \\    mov r3, r5
        \\    mov r4, r6
        \\    mov r8, 220 // SYS_clone
        \\    trap_s 0
        \\    cmp r0, 0
        \\    beq 1f
        \\    j [blink]
        \\    // Child
        \\ 1: 
    );
    if (builtin.unwind_tables != .none or !builtin.strip_debug_info) asm volatile (
        \\ .cfi_undefined blink
    );

    asm volatile (
        \\    mov fp, 0
        \\    mov blink, 0
        \\
        \\    mov r0, r11
        \\    jl [r10]
        \\
        \\    // Exit
        \\    mov r8, 93 // SYS_exit
        \\    trap_s 0
    );
}

pub const restore = restore_rt;

pub fn restore_rt() callconv(.naked) noreturn {
    switch (builtin.zig_backend) {
        .stage2_c => asm volatile (
            \\ mov r8, %[number]
            \\ trap_s 0
            :
            : [number] "I" (@intFromEnum(SYS.rt_sigreturn)),
        ),
        else => asm volatile (
            \\ trap_s 0
            :
            : [number] "{r8}" (@intFromEnum(SYS.rt_sigreturn)),
        ),
    }
}

pub const time_t = i64;

pub const VDSO = void;
