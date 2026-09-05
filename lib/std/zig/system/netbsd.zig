const builtin = @import("builtin");
const std = @import("std");

const native_arch = builtin.target.cpu.arch;

const aarch64 = struct {
    const sysctl_cpu_id = extern struct {
        midr: u64,
        revidr: u64,
        mpidr: u64,

        aa64dfr0: u64,
        aa64dfr1: u64,

        aa64isar0: u64,
        aa64isar1: u64,

        aa64mmfr0: u64,
        aa64mmfr1: u64,
        aa64mmfr2: u64,

        aa64pfr0: u64,
        aa64pfr1: u64,

        aa64zfr0: u64,

        mvfr0: u32,
        mvfr1: u32,
        mvfr2: u32,
        _pad: u32 = 0,

        clidr: u64,
        ctr: u64,
    };
};

pub fn detectNativeCpuAndFeatures() ?std.Target.Cpu {
    return switch (native_arch) {
        .aarch64, .aarch64_be => b: {
            var value: aarch64.sysctl_cpu_id = undefined;
            var len: usize = @sizeOf(@TypeOf(value));
            switch (std.posix.errno(std.c.sysctlbyname("machdep.cpu0.cpu_id", &value, &len, null, 0))) {
                .SUCCESS => {},
                .FAULT => unreachable,
                .INVAL => unreachable,
                .ISDIR => unreachable,
                .NOENT => unreachable, // 👻
                .NOMEM => {}, // `aarch64.sysctl_cpu_id` has grown upstream, harmless
                .NOTDIR => unreachable,
                .NOTEMPTY => unreachable,
                .OPNOTSUPP => unreachable,
                .PERM => unreachable,
                else => return null,
            }

            const registers = [12]u64{
                value.midr,
                value.aa64pfr0,
                value.aa64pfr1,
                value.aa64dfr0,
                value.aa64dfr1,
                0, // ID_AA64AFR0_EL1
                0, // ID_AA64AFR1_EL1
                value.aa64isar0,
                value.aa64isar1,
                value.aa64mmfr0,
                value.aa64mmfr1,
                value.aa64mmfr2,
            };

            break :b @import("arm.zig").aarch64.detectNativeCpuAndFeatures(native_arch, registers);
        },
        else => null,
    };
}
