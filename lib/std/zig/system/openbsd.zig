const builtin = @import("builtin");
const std = @import("std");

const native_arch = builtin.target.cpu.arch;

const aarch64 = struct {
    fn sysctlReg(key: c_int) u64 {
        const mib: [2]c_int = [_]c_int{
            std.c.CTL.MACHDEP,
            key,
        };
        var value: u64 = undefined;
        var len: usize = @sizeOf(@TypeOf(value));

        std.posix.sysctl(&mib, &value, &len, null, 0) catch |err| switch (err) {
            error.NameTooLong => unreachable,
            error.PermissionDenied => unreachable,
            error.SystemResources => unreachable,
            error.UnknownName => unreachable,
            error.Unexpected => return 0,
        };

        return value;
    }
};

pub fn detectNativeCpuAndFeatures() ?std.Target.Cpu {
    return switch (native_arch) {
        .aarch64, .aarch64_be => b: {
            const registers = [12]u64{
                0, // MIDR_EL1
                aarch64.sysctlReg(std.c.CPU.AA64PFR0),
                aarch64.sysctlReg(std.c.CPU.AA64PFR1),
                0, // ID_AA64DFR0_EL1
                0, // ID_AA64DFR1_EL1
                0, // ID_AA64AFR0_EL1
                0, // ID_AA64AFR1_EL1
                aarch64.sysctlReg(std.c.CPU.ID_AA64ISAR0),
                aarch64.sysctlReg(std.c.CPU.ID_AA64ISAR1),
                aarch64.sysctlReg(std.c.CPU.ID_AA64MMFR0),
                aarch64.sysctlReg(std.c.CPU.ID_AA64MMFR1),
                aarch64.sysctlReg(std.c.CPU.ID_AA64MMFR2),
            };

            break :b @import("arm.zig").aarch64.detectNativeCpuAndFeatures(native_arch, registers);
        },
        else => null,
    };
}
