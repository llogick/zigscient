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
    const models = .{
        .{ "Ampere AmpereOne AC03", &std.Target.aarch64.cpu.ampere1 },
        .{ "Ampere AmpereOne AC04", &std.Target.aarch64.cpu.ampere1a },
        .{ "Apple Icestorm Max", &std.Target.aarch64.cpu.apple_m1 },
        .{ "Apple Icestorm Pro", &std.Target.aarch64.cpu.apple_m1 },
        .{ "Apple Icestorm", &std.Target.aarch64.cpu.apple_m1 },
        .{ "Apple Firestorm Max", &std.Target.aarch64.cpu.apple_m1 },
        .{ "Apple Firestorm Pro", &std.Target.aarch64.cpu.apple_m1 },
        .{ "Apple Firestorm", &std.Target.aarch64.cpu.apple_m1 },
        .{ "Apple Blizzard Max", &std.Target.aarch64.cpu.apple_m2 },
        .{ "Apple Blizzard Pro", &std.Target.aarch64.cpu.apple_m2 },
        .{ "Apple Blizzard", &std.Target.aarch64.cpu.apple_m2 },
        .{ "Apple Avalanche Max", &std.Target.aarch64.cpu.apple_m2 },
        .{ "Apple Avalanche Pro", &std.Target.aarch64.cpu.apple_m2 },
        .{ "Apple Avalanche", &std.Target.aarch64.cpu.apple_m2 },
        .{ "Applied Micro X-Gene", &std.Target.aarch64.cpu.xgene1 },
        // TODO: Add these with LLVM 23.
        // .{ "ARM C1-Nano", &std.Target.aarch64.cpu.c1_nano },
        // .{ "ARM C1-Pro", &std.Target.aarch64.cpu.c1_pro },
        // .{ "ARM C1-Ultra", &std.Target.aarch64.cpu.c1_ultra },
        // .{ "ARM C1-Premium", &std.Target.aarch64.cpu.c1_premium },
        .{ "ARM Cortex-A320", &std.Target.aarch64.cpu.cortex_a320 },
        .{ "ARM Cortex-A34", &std.Target.aarch64.cpu.cortex_a34 },
        .{ "ARM Cortex-A35", &std.Target.aarch64.cpu.cortex_a35 },
        .{ "ARM Cortex-A510", &std.Target.aarch64.cpu.cortex_a510 },
        .{ "ARM Cortex-A520AE", &std.Target.aarch64.cpu.cortex_a520ae },
        .{ "ARM Cortex-A520", &std.Target.aarch64.cpu.cortex_a520 },
        .{ "ARM Cortex-A53", &std.Target.aarch64.cpu.cortex_a53 },
        .{ "ARM Cortex-A55", &std.Target.aarch64.cpu.cortex_a55 },
        .{ "ARM Cortex-A57", &std.Target.aarch64.cpu.cortex_a57 },
        .{ "ARM Cortex-A65AE", &std.Target.aarch64.cpu.cortex_a65ae },
        .{ "ARM Cortex-A65", &std.Target.aarch64.cpu.cortex_a65 },
        .{ "ARM Cortex-A710", &std.Target.aarch64.cpu.cortex_a710 },
        .{ "ARM Cortex-A715", &std.Target.aarch64.cpu.cortex_a715 },
        .{ "ARM Cortex-A720AE", &std.Target.aarch64.cpu.cortex_a720ae },
        .{ "ARM Cortex-A720", &std.Target.aarch64.cpu.cortex_a720 },
        .{ "ARM Cortex-A725", &std.Target.aarch64.cpu.cortex_a725 },
        .{ "ARM Cortex-A72", &std.Target.aarch64.cpu.cortex_a72 },
        .{ "ARM Cortex-A73", &std.Target.aarch64.cpu.cortex_a73 },
        .{ "ARM Cortex-A75", &std.Target.aarch64.cpu.cortex_a75 },
        .{ "ARM Cortex-A76AE", &std.Target.aarch64.cpu.cortex_a76ae },
        .{ "ARM Cortex-A76", &std.Target.aarch64.cpu.cortex_a76 },
        .{ "ARM Cortex-A77", &std.Target.aarch64.cpu.cortex_a77 },
        .{ "ARM Cortex-A78AE", &std.Target.aarch64.cpu.cortex_a78ae },
        .{ "ARM Cortex-A78C", &std.Target.aarch64.cpu.cortex_a78c },
        .{ "ARM Cortex-A78", &std.Target.aarch64.cpu.cortex_a78 },
        .{ "ARM Cortex-X1C", &std.Target.aarch64.cpu.cortex_x1c },
        .{ "ARM Cortex-X1", &std.Target.aarch64.cpu.cortex_x1 },
        .{ "ARM Cortex-X2", &std.Target.aarch64.cpu.cortex_x2 },
        .{ "ARM Cortex-X3", &std.Target.aarch64.cpu.cortex_x3 },
        .{ "ARM Cortex-X4", &std.Target.aarch64.cpu.cortex_x4 },
        .{ "ARM Cortex-X925", &std.Target.aarch64.cpu.cortex_x925 },
        .{ "ARM Neoverse E1", &std.Target.aarch64.cpu.neoverse_e1 },
        .{ "ARM Neoverse N1", &std.Target.aarch64.cpu.neoverse_n1 },
        .{ "ARM Neoverse N2", &std.Target.aarch64.cpu.neoverse_n2 },
        .{ "ARM Neoverse N3", &std.Target.aarch64.cpu.neoverse_n3 },
        .{ "ARM Neoverse V1", &std.Target.aarch64.cpu.neoverse_v1 },
        .{ "ARM Neoverse V2", &std.Target.aarch64.cpu.neoverse_v2 },
        .{ "ARM Neoverse V3AE", &std.Target.aarch64.cpu.neoverse_v3ae },
        .{ "ARM Neoverse V3", &std.Target.aarch64.cpu.neoverse_v3 },
        .{ "Cavium ThunderX T81", &std.Target.aarch64.cpu.thunderxt81 },
        .{ "Cavium ThunderX T83", &std.Target.aarch64.cpu.thunderxt83 },
        .{ "Cavium ThunderX T88", &std.Target.aarch64.cpu.thunderxt88 },
        .{ "Cavium ThunderX2 T99", &std.Target.aarch64.cpu.thunderx2t99 },
        .{ "Microsoft Azure Cobalt 100", &std.Target.aarch64.cpu.cobalt_100 },
        .{ "NVIDIA Olympus", &std.Target.aarch64.cpu.olympus },
        .{ "Qualcomm Kryo 400 Gold", &std.Target.aarch64.cpu.cortex_a76 },
        .{ "Qualcomm Kryo 400 Silver", &std.Target.aarch64.cpu.cortex_a55 },
        .{ "Qualcomm Oryon", &std.Target.aarch64.cpu.oryon_1 },
    };

    fn sysctlReg(key: c_int) ?u64 {
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
            error.Unexpected => return null,
        };

        return value;
    }

    fn detectNativeCpuAndFeatures(arch: std.Target.Cpu.Arch) ?std.Target.Cpu {
        const model: *const std.Target.Cpu.Model = blk: {
            var buf: [64:0]u8 = undefined;
            const name = hwModelName(&buf) orelse return null;

            inline for (models) |pair| {
                if (std.mem.startsWith(u8, name, pair[0])) break :blk pair[1];
            }

            break :blk .generic(arch);
        };

        const registers = [11]u64{
            sysctlReg(std.c.CPU.AA64PFR0) orelse return null,
            sysctlReg(std.c.CPU.AA64PFR1) orelse return null,
            0, // ID_AA64DFR0_EL1
            0, // ID_AA64DFR1_EL1
            0, // ID_AA64AFR0_EL1
            0, // ID_AA64AFR1_EL1
            sysctlReg(std.c.CPU.ID_AA64ISAR0) orelse return null,
            sysctlReg(std.c.CPU.ID_AA64ISAR1) orelse return null,
            sysctlReg(std.c.CPU.ID_AA64MMFR0) orelse return null,
            sysctlReg(std.c.CPU.ID_AA64MMFR1) orelse return null,
            sysctlReg(std.c.CPU.ID_AA64MMFR2) orelse return null,
        };

        return @import("arm.zig").aarch64.detectNativeFeatures(arch, model, registers);
    }
};

const arm = struct {
    const models = .{
        .{ "ARM Cortex-A12", &std.Target.arm.cpu.cortex_a12 },
        .{ "ARM Cortex-A15", &std.Target.arm.cpu.cortex_a15 },
        .{ "ARM Cortex-A17", &std.Target.arm.cpu.cortex_a17 },
        .{ "ARM Cortex-A32", &std.Target.arm.cpu.cortex_a32 },
        .{ "ARM Cortex-A35", &std.Target.arm.cpu.cortex_a35 },
        .{ "ARM Cortex-A53", &std.Target.arm.cpu.cortex_a53 },
        .{ "ARM Cortex-A55", &std.Target.arm.cpu.cortex_a55 },
        .{ "ARM Cortex-A57", &std.Target.arm.cpu.cortex_a57 },
        .{ "ARM Cortex-A5", &std.Target.arm.cpu.cortex_a5 },
        .{ "ARM Cortex-A72", &std.Target.arm.cpu.cortex_a72 },
        .{ "ARM Cortex-A73", &std.Target.arm.cpu.cortex_a73 },
        .{ "ARM Cortex-A75", &std.Target.arm.cpu.cortex_a75 },
        .{ "ARM Cortex-A7", &std.Target.arm.cpu.cortex_a7 },
        .{ "ARM Cortex-A8", &std.Target.arm.cpu.cortex_a8 },
        .{ "ARM Cortex-A9", &std.Target.arm.cpu.cortex_a9 },
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
        .{ "601", &std.Target.powerpc.cpu.@"601" },
        .{ "603ev", &std.Target.powerpc.cpu.@"603ev" },
        .{ "603e", &std.Target.powerpc.cpu.@"603e" },
        .{ "603", &std.Target.powerpc.cpu.@"603" },
        .{ "604ev", &std.Target.powerpc.cpu.@"604e" },
        .{ "604", &std.Target.powerpc.cpu.@"604" },
        .{ "7400", &std.Target.powerpc.cpu.@"7400" },
        .{ "7410", &std.Target.powerpc.cpu.@"7400" },
        .{ "7450", &std.Target.powerpc.cpu.@"7450" },
        .{ "7451", &std.Target.powerpc.cpu.@"7450" },
        .{ "7455", &std.Target.powerpc.cpu.@"7450" },
        .{ "7457", &std.Target.powerpc.cpu.@"7450" },
        .{ "7447A", &std.Target.powerpc.cpu.@"7450" },
        .{ "7448", &std.Target.powerpc.cpu.@"7450" },
        .{ "750FX", &std.Target.powerpc.cpu.@"750" },
        .{ "750", &std.Target.powerpc.cpu.@"750" },
        .{ "970FX", &std.Target.powerpc.cpu.@"970" },
        .{ "970MP", &std.Target.powerpc.cpu.@"970" },
        .{ "970", &std.Target.powerpc.cpu.@"970" },
        .{ "IBM POWER8E", &std.Target.powerpc.cpu.pwr8 },
        .{ "IBM POWER8NVL", &std.Target.powerpc.cpu.pwr8 },
        .{ "IBM POWER8", &std.Target.powerpc.cpu.pwr8 },
        .{ "IBM POWER9P", &std.Target.powerpc.cpu.pwr9 },
        .{ "IBM POWER9", &std.Target.powerpc.cpu.pwr9 },
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

const riscv = struct {
    const models = .{
        .{ "SiFive U5", &std.Target.riscv.cpu.sifive_u54 },
        .{ "SiFive U7", &std.Target.riscv.cpu.sifive_u74 },
        .{ "SpacemiT X60", &std.Target.riscv.cpu.spacemit_x60 },
        .{ "SpacemiT X100", &std.Target.riscv.cpu.spacemit_x100 },
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

pub fn detectNativeCpuAndFeatures() ?std.Target.Cpu {
    return switch (native_arch) {
        .aarch64 => aarch64.detectNativeCpuAndFeatures(native_arch),
        .arm => arm.detectNativeCpu(native_arch),
        .powerpc, .powerpc64 => powerpc.detectNativeCpu(native_arch),
        .riscv64 => riscv.detectNativeCpu(native_arch),
        else => null,
    };
}
