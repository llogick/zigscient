const builtin = @import("builtin");
const std = @import("std");

const native_arch = builtin.target.cpu.arch;

fn hwModelName(buf: [:0]u8) ?[:0]const u8 {
    const mib: [2]c_int = [_]c_int{
        std.c.CTL.HW,
        std.c.HW.MODEL,
    };
    var len: usize = buf.len + 1;

    std.posix.sysctl(&mib, buf.ptr, &len, null, 0) catch |err| switch (err) {
        error.NameTooLong => unreachable,
        error.PermissionDenied => unreachable,
        error.SystemResources => unreachable,
        error.UnknownName => unreachable,
        error.Unexpected => return null,
    };

    return buf[0 .. len - 1 :0];
}

const aarch64 = struct {
    inline fn mrs(comptime feat_reg: []const u8) u64 {
        return asm ("mrs %[ret], " ++ feat_reg
            : [ret] "=r" (-> u64),
        );
    }

    fn detectNativeCpuAndFeatures(arch: std.Target.Cpu.Arch) std.Target.Cpu {
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

        return @import("arm.zig").aarch64.detectNativeCpuAndFeatures(arch, registers);
    }
};

const arm = struct {
    const models = .{
        .{ "ARM ARM1176", &std.Target.arm.cpu.arm1176jzf_s },
        .{ "ARM Cortex-A12", &std.Target.arm.cpu.cortex_a12 },
        .{ "ARM Cortex-A15", &std.Target.arm.cpu.cortex_a15 },
        .{ "ARM Cortex-A17", &std.Target.arm.cpu.cortex_a17 },
        .{ "ARM Cortex-A53", &std.Target.arm.cpu.cortex_a53 },
        .{ "ARM Cortex-A57", &std.Target.arm.cpu.cortex_a57 },
        .{ "ARM Cortex-A5", &std.Target.arm.cpu.cortex_a5 },
        .{ "ARM Cortex-A72", &std.Target.arm.cpu.cortex_a72 },
        .{ "ARM Cortex-A73", &std.Target.arm.cpu.cortex_a73 },
        .{ "ARM Cortex-A7", &std.Target.arm.cpu.cortex_a7 },
        .{ "ARM Cortex-A8", &std.Target.arm.cpu.cortex_a8 },
        .{ "ARM Cortex-A9", &std.Target.arm.cpu.cortex_a9 },
        .{ "Qualcomm Krait 300", &std.Target.arm.cpu.krait },
    };

    fn detectNativeCpu(arch: std.Target.Cpu.Arch) ?std.Target.Cpu {
        var buf: [64:0]u8 = undefined;
        const name = hwModelName(&buf) orelse return null;

        inline for (models) |pair| {
            if (std.mem.startsWith(u8, name, pair[0])) return pair[1].toCpu(arch);
        }

        return null;
    }
};

const powerpc = struct {
    const models = .{
        .{ "Freescale e500v1 core", &std.Target.powerpc.cpu.e500 },
        .{ "Freescale e500v2 core", &std.Target.powerpc.cpu.e500v2 },
        .{ "Freescale e500mc core", &std.Target.powerpc.cpu.e500mc },
        .{ "Freescale e5500 core", &std.Target.powerpc.cpu.e5500 },
        .{ "Freescale e6500 core", &std.Target.powerpc.cpu.e6500 },
        .{ "IBM Cell Broadband Engine", &std.Target.powerpc.cpu.cell },
        .{ "IBM PowerPC 750FX", &std.Target.powerpc.cpu.@"750" },
        .{ "IBM PowerPC 970", &std.Target.powerpc.cpu.@"970" },
        .{ "IBM PowerPC 970FX", &std.Target.powerpc.cpu.@"970" },
        .{ "IBM PowerPC 970GX", &std.Target.powerpc.cpu.@"970" },
        .{ "IBM PowerPC 970MP", &std.Target.powerpc.cpu.@"970" },
        .{ "IBM POWER4", &std.Target.powerpc.cpu.pwr4 },
        .{ "IBM POWER4+", &std.Target.powerpc.cpu.pwr4 },
        .{ "IBM POWER5", &std.Target.powerpc.cpu.pwr5 },
        .{ "IBM POWER5+", &std.Target.powerpc.cpu.pwr5x },
        .{ "IBM POWER6", &std.Target.powerpc.cpu.pwr6 },
        .{ "IBM POWER7", &std.Target.powerpc.cpu.pwr7 },
        .{ "IBM POWER7+", &std.Target.powerpc.cpu.pwr7 },
        .{ "IBM POWER8E", &std.Target.powerpc.cpu.pwr8 },
        .{ "IBM POWER8NVL", &std.Target.powerpc.cpu.pwr8 },
        .{ "IBM POWER8", &std.Target.powerpc.cpu.pwr8 },
        .{ "IBM POWER9", &std.Target.powerpc.cpu.pwr9 },
        .{ "IBM POWER10", &std.Target.powerpc.cpu.pwr10 },
        .{ "IBM POWER11", &std.Target.powerpc.cpu.pwr11 },
        .{ "Motorola PowerPC 601", &std.Target.powerpc.cpu.@"601" },
        .{ "Motorola PowerPC 602", &std.Target.powerpc.cpu.@"602" },
        .{ "Motorola PowerPC 603", &std.Target.powerpc.cpu.@"603" },
        .{ "Motorola PowerPC 603e", &std.Target.powerpc.cpu.@"603e" },
        .{ "Motorola PowerPC 603ev", &std.Target.powerpc.cpu.@"603ev" },
        .{ "Motorola PowerPC 604", &std.Target.powerpc.cpu.@"604" },
        .{ "Motorola PowerPC 604ev", &std.Target.powerpc.cpu.@"604e" },
        .{ "Motorola PowerPC 620", &std.Target.powerpc.cpu.@"620" },
        .{ "Motorola PowerPC 750", &std.Target.powerpc.cpu.@"750" },
        .{ "Motorola PowerPC 7400", &std.Target.powerpc.cpu.@"7400" },
        .{ "Motorola PowerPC 7410", &std.Target.powerpc.cpu.@"7400" },
        .{ "Motorola PowerPC 7450", &std.Target.powerpc.cpu.@"7450" },
        .{ "Motorola PowerPC 7455", &std.Target.powerpc.cpu.@"7450" },
        .{ "Motorola PowerPC 7457", &std.Target.powerpc.cpu.@"7450" },
        .{ "Motorola PowerPC 7457", &std.Target.powerpc.cpu.@"7450" },
        .{ "Motorola PowerPC 7447A", &std.Target.powerpc.cpu.@"7450" },
        .{ "Motorola PowerPC 7448", &std.Target.powerpc.cpu.@"7450" },
        .{ "Motorola PowerPC 8240", &std.Target.powerpc.cpu.@"603e" },
        .{ "Motorola PowerPC 8245", &std.Target.powerpc.cpu.@"603e" },
    };

    fn detectNativeCpu(arch: std.Target.Cpu.Arch) ?std.Target.Cpu {
        var buf: [64:0]u8 = undefined;
        const name = hwModelName(&buf) orelse return null;

        inline for (models) |pair| {
            if (std.mem.eql(u8, name, pair[0])) return pair[1].toCpu(arch);
        }

        return null;
    }
};

pub fn detectNativeCpuAndFeatures() ?std.Target.Cpu {
    return switch (native_arch) {
        .aarch64 => aarch64.detectNativeCpuAndFeatures(native_arch),
        .arm => arm.detectNativeCpu(native_arch),
        .powerpc64, .powerpc64le => powerpc.detectNativeCpu(native_arch),
        else => null,
    };
}
