const builtin = @import("builtin");
const std = @import("std");

const native_arch = builtin.target.cpu.arch;

const aarch64 = struct {
    inline fn mrs(comptime feat_reg: []const u8) u64 {
        return asm ("mrs %[ret], " ++ feat_reg
            : [ret] "=r" (-> u64),
        );
    }
};

pub fn detectNativeCpuAndFeatures() ?std.Target.Cpu {
    return switch (native_arch) {
        .aarch64, .aarch64_be => b: {
            const registers = [12]u64{
                aarch64.mrs("MIDR_EL1"),
                aarch64.mrs("ID_AA64PFR0_EL1"),
                aarch64.mrs("ID_AA64PFR1_EL1"),
                aarch64.mrs("ID_AA64DFR0_EL1"),
                aarch64.mrs("ID_AA64DFR1_EL1"),
                aarch64.mrs("ID_AA64AFR0_EL1"),
                aarch64.mrs("ID_AA64AFR1_EL1"),
                aarch64.mrs("ID_AA64ISAR0_EL1"),
                aarch64.mrs("ID_AA64ISAR1_EL1"),
                aarch64.mrs("ID_AA64MMFR0_EL1"),
                aarch64.mrs("ID_AA64MMFR1_EL1"),
                aarch64.mrs("ID_AA64MMFR2_EL1"),
            };

            break :b @import("arm.zig").aarch64.detectNativeCpuAndFeatures(native_arch, registers);
        },
        else => null,
    };
}
