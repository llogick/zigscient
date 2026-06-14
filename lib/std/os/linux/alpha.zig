const builtin = @import("builtin");
const std = @import("../../std.zig");
const SYS = std.os.linux.SYS;

pub fn syscall0(number: SYS) u64 {
    return asm volatile (
        \\ callsys
        \\ beq $19, 1f
        \\ negq $0, $0
        \\1:
        : [ret] "={$0}" (-> u64),
        : [number] "{$0}" (number),
        : .{
          .r1 = true,
          .r2 = true,
          .r3 = true,
          .r4 = true,
          .r5 = true,
          .r6 = true,
          .r7 = true,
          .r8 = true,
          .r22 = true,
          .r23 = true,
          .r24 = true,
          .r25 = true,
          .r27 = true,
          .r28 = true,
          .memory = true,
          .r16 = true,
          .r17 = true,
          .r18 = true,
          .r20 = true,
          .r21 = true,
        });
}

pub fn syscall1(number: SYS, arg1: u64) u64 {
    // These registers are both inputs and clobbers.
    var r16_out: u64 = undefined;
    return asm volatile (
        \\ callsys
        \\ beq $19, 1f
        \\ negq $0, $0
        \\1:
        : [ret] "={$0}" (-> u64),
          [r16_out] "={$16}" (r16_out),
        : [number] "{$0}" (number),
          [arg1] "{$16}" (arg1),
        : .{
          .r1 = true,
          .r2 = true,
          .r3 = true,
          .r4 = true,
          .r5 = true,
          .r6 = true,
          .r7 = true,
          .r8 = true,
          .r22 = true,
          .r23 = true,
          .r24 = true,
          .r25 = true,
          .r27 = true,
          .r28 = true,
          .memory = true,
          .r17 = true,
          .r18 = true,
          .r20 = true,
          .r21 = true,
        });
}

pub fn syscall2(number: SYS, arg1: u64, arg2: u64) u64 {
    // These registers are both inputs and clobbers.
    var r16_out: u64 = undefined;
    var r17_out: u64 = undefined;
    return asm volatile (
        \\ callsys
        \\ beq $19, 1f
        \\ negq $0, $0
        \\1:
        : [ret] "={$0}" (-> u64),
          [r16_out] "={$16}" (r16_out),
          [r17_out] "={$17}" (r17_out),
        : [number] "{$0}" (number),
          [arg1] "{$16}" (arg1),
          [arg2] "{$17}" (arg2),
        : .{
          .r1 = true,
          .r2 = true,
          .r3 = true,
          .r4 = true,
          .r5 = true,
          .r6 = true,
          .r7 = true,
          .r8 = true,
          .r22 = true,
          .r23 = true,
          .r24 = true,
          .r25 = true,
          .r27 = true,
          .r28 = true,
          .memory = true,
          .r18 = true,
          .r20 = true,
          .r21 = true,
        });
}

pub fn syscall3(number: SYS, arg1: u64, arg2: u64, arg3: u64) u64 {
    // These registers are both inputs and clobbers.
    var r16_out: u64 = undefined;
    var r17_out: u64 = undefined;
    var r18_out: u64 = undefined;
    return asm volatile (
        \\ callsys
        \\ beq $19, 1f
        \\ negq $0, $0
        \\1:
        : [ret] "={$0}" (-> u64),
          [r16_out] "={$16}" (r16_out),
          [r17_out] "={$17}" (r17_out),
          [r18_out] "={$18}" (r18_out),
        : [number] "{$0}" (number),
          [arg1] "{$16}" (arg1),
          [arg2] "{$17}" (arg2),
          [arg3] "{$18}" (arg3),
        : .{
          .r1 = true,
          .r2 = true,
          .r3 = true,
          .r4 = true,
          .r5 = true,
          .r6 = true,
          .r7 = true,
          .r8 = true,
          .r22 = true,
          .r23 = true,
          .r24 = true,
          .r25 = true,
          .r27 = true,
          .r28 = true,
          .memory = true,
          .r20 = true,
          .r21 = true,
        });
}

pub fn syscall4(number: SYS, arg1: u64, arg2: u64, arg3: u64, arg4: u64) u64 {
    // These registers are both inputs and clobbers.
    var r16_out: u64 = undefined;
    var r17_out: u64 = undefined;
    var r18_out: u64 = undefined;
    var r19_out: u64 = undefined;
    return asm volatile (
        \\ callsys
        \\ beq $19, 1f
        \\ negq $0, $0
        \\1:
        : [ret] "={$0}" (-> u64),
          [r16_out] "={$16}" (r16_out),
          [r17_out] "={$17}" (r17_out),
          [r18_out] "={$18}" (r18_out),
          [r19_out] "={$19}" (r19_out),
        : [number] "{$0}" (number),
          [arg1] "{$16}" (arg1),
          [arg2] "{$17}" (arg2),
          [arg3] "{$18}" (arg3),
          [arg4] "{$19}" (arg4),
        : .{
          .r1 = true,
          .r2 = true,
          .r3 = true,
          .r4 = true,
          .r5 = true,
          .r6 = true,
          .r7 = true,
          .r8 = true,
          .r22 = true,
          .r23 = true,
          .r24 = true,
          .r25 = true,
          .r27 = true,
          .r28 = true,
          .memory = true,
          .r20 = true,
          .r21 = true,
        });
}

pub fn syscall5(number: SYS, arg1: u64, arg2: u64, arg3: u64, arg4: u64, arg5: u64) u64 {
    // These registers are both inputs and clobbers.
    var r16_out: u64 = undefined;
    var r17_out: u64 = undefined;
    var r18_out: u64 = undefined;
    var r19_out: u64 = undefined;
    var r20_out: u64 = undefined;
    return asm volatile (
        \\ callsys
        \\ beq $19, 1f
        \\ negq $0, $0
        \\1:
        : [ret] "={$0}" (-> u64),
          [r16_out] "={$16}" (r16_out),
          [r17_out] "={$17}" (r17_out),
          [r18_out] "={$18}" (r18_out),
          [r19_out] "={$19}" (r19_out),
          [r20_out] "={$20}" (r20_out),
        : [number] "{$0}" (number),
          [arg1] "{$16}" (arg1),
          [arg2] "{$17}" (arg2),
          [arg3] "{$18}" (arg3),
          [arg4] "{$19}" (arg4),
          [arg5] "{$20}" (arg5),
        : .{
          .r1 = true,
          .r2 = true,
          .r3 = true,
          .r4 = true,
          .r5 = true,
          .r6 = true,
          .r7 = true,
          .r8 = true,
          .r22 = true,
          .r23 = true,
          .r24 = true,
          .r25 = true,
          .r27 = true,
          .r28 = true,
          .memory = true,
          .r21 = true,
        });
}

pub fn syscall6(
    number: SYS,
    arg1: u64,
    arg2: u64,
    arg3: u64,
    arg4: u64,
    arg5: u64,
    arg6: u64,
) u64 {
    // These registers are both inputs and clobbers.
    var r16_out: u64 = undefined;
    var r17_out: u64 = undefined;
    var r18_out: u64 = undefined;
    var r19_out: u64 = undefined;
    var r20_out: u64 = undefined;
    var r21_out: u64 = undefined;
    return asm volatile (
        \\ callsys
        \\ beq $19, 1f
        \\ negq $0, $0
        \\1:
        : [ret] "={$0}" (-> u64),
          [r16_out] "={$16}" (r16_out),
          [r17_out] "={$17}" (r17_out),
          [r18_out] "={$18}" (r18_out),
          [r19_out] "={$19}" (r19_out),
          [r20_out] "={$20}" (r20_out),
          [r21_out] "={$21}" (r21_out),
        : [number] "{$0}" (number),
          [arg1] "{$16}" (arg1),
          [arg2] "{$17}" (arg2),
          [arg3] "{$18}" (arg3),
          [arg4] "{$19}" (arg4),
          [arg5] "{$20}" (arg5),
          [arg6] "{$21}" (arg6),
        : .{
          .r1 = true,
          .r2 = true,
          .r3 = true,
          .r4 = true,
          .r5 = true,
          .r6 = true,
          .r7 = true,
          .r8 = true,
          .r22 = true,
          .r23 = true,
          .r24 = true,
          .r25 = true,
          .r27 = true,
          .r28 = true,
          .memory = true,
        });
}

pub fn clone() callconv(.naked) u64 {
    // __clone(func, stack, flags, arg, ptid, tls, ctid)
    //         a0,   a1,    a2,    a3,  a4,   a5,  +0
    //
    // syscall(SYS_clone, flags, stack, ptid, ctid, tls)
    //         v0         a0,    a1,    a2,   a3,   a4
    asm volatile (
    // a0 = $16, a1 = $17, a2 = $18, a3 = $19,
    // a4 = $20, a5 = $21, sp = $30, v0 = $0
        \\ # Save function pointer and argument pointer on new thread stack
        \\ ldi $1, -8
        \\ and $17, $17, $1
        \\ lda $17, -16($17)
        \\ stq $16, 0($17)
        \\ stq $19, 8($17)
        \\
        \\ # Shuffle (fn,sp,fl,arg,ptid,tls,ctid) to (fl,sp,ptid,ctid,tls)
        \\ mov $18, $16
        \\ mov $20, $18
        \\ ldq $19, 0($30)
        \\ mov $21, $20
        \\
        \\ # Actual syscall
        \\ ldi $0, 312 # SYS_clone
        \\ callsys
        \\ beq $19, 1f
        \\ negq $0, $0
        \\ ret
        \\1:
        \\ beq $0, 2f
        \\ ret
        \\2:
    );
    if (builtin.unwind_tables != .none or !builtin.strip_debug_info) asm volatile (
    // ra = $26
        \\ .cfi_undefined $26
    );
    asm volatile (
    // v0 = $0, t9 = $23, a0 = $16, ra = $26, sp = $30, fp = $15
        \\ mov 0, $15
        \\
        \\ ldq $23, 0($30)
        \\ ldq $16, 8($30)
        \\ lda $30, 16($30)
        \\ jsr $26, ($23)
        \\
        \\ mov $0, $16
        \\ ldi $0, 1 # SYS_EXIT
        \\ callsys
    );
}

pub fn restore() noreturn {
    asm volatile (
    // v0 = $0, a0 = $16, sp = $30
        \\ mov $30, $16
        \\ ldi $0, 103 # SIGRETURN
        \\ callsys
    );
}

pub fn restore_rt() noreturn {
    asm volatile (
    // v0 = $0, a0 = $16, sp = $30
        \\ mov $30, $16
        \\ ldi $0, 351 # RT_SIGRETURN
        \\ callsys
    );
}

pub const VDSO = void;
