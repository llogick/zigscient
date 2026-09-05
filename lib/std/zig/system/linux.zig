const builtin = @import("builtin");

const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const fs = std.fs;
const fmt = std.fmt;
const testing = std.testing;
const Target = std.Target;
const assert = std.debug.assert;

const SparcCpuinfoImpl = struct {
    model: ?*const Target.Cpu.Model = null,

    const cpu_names = .{
        .{ "SuperSparc", &Target.sparc.cpu.supersparc },
        .{ "HyperSparc", &Target.sparc.cpu.hypersparc },
        .{ "SpitFire", &Target.sparc.cpu.ultrasparc },
        .{ "BlackBird", &Target.sparc.cpu.ultrasparc },
        .{ "Sabre", &Target.sparc.cpu.ultrasparc },
        .{ "Hummingbird", &Target.sparc.cpu.ultrasparc },
        .{ "Cheetah", &Target.sparc.cpu.ultrasparc3 },
        .{ "Jalapeno", &Target.sparc.cpu.ultrasparc3 },
        .{ "Jaguar", &Target.sparc.cpu.ultrasparc3 },
        .{ "Panther", &Target.sparc.cpu.ultrasparc3 },
        .{ "Serrano", &Target.sparc.cpu.ultrasparc3 },
        .{ "UltraSparc T1", &Target.sparc.cpu.niagara },
        .{ "UltraSparc T2", &Target.sparc.cpu.niagara2 },
        .{ "UltraSparc T3", &Target.sparc.cpu.niagara3 },
        .{ "UltraSparc T4", &Target.sparc.cpu.niagara4 },
        .{ "UltraSparc T5", &Target.sparc.cpu.niagara4 },
        .{ "LEON", &Target.sparc.cpu.leon3 },
    };

    fn line_hook(self: *SparcCpuinfoImpl, key: []const u8, value: []const u8) !bool {
        if (mem.eql(u8, key, "cpu")) {
            inline for (cpu_names) |pair| {
                if (mem.findPos(u8, value, 0, pair[0]) != null) {
                    self.model = pair[1];
                    break;
                }
            }
        }

        return true;
    }

    fn finalize(self: *const SparcCpuinfoImpl, arch: Target.Cpu.Arch) ?Target.Cpu {
        const model = self.model orelse return null;
        return Target.Cpu{
            .arch = arch,
            .model = model,
            .features = model.features,
        };
    }
};

const SparcCpuinfoParser = CpuinfoParser(SparcCpuinfoImpl);

test "cpuinfo: SPARC" {
    try testParser(SparcCpuinfoParser, .sparc64, &Target.sparc.cpu.niagara2,
        \\cpu             : UltraSparc T2 (Niagara2)
        \\fpu             : UltraSparc T2 integrated FPU
        \\pmu             : niagara2
        \\type            : sun4v
    );
}

const RiscvCpuinfoImpl = struct {
    model: ?*const Target.Cpu.Model = null,

    const cpu_names = .{
        .{ "andestech,ax45mp", &Target.riscv.cpu.andes_ax45 },
        .{ "sifive,p550", &Target.riscv.cpu.sifive_p550 },
        .{ "sifive,u54", &Target.riscv.cpu.sifive_u54 },
        .{ "sifive,u54-mc", &Target.riscv.cpu.sifive_u54 },
        .{ "sifive,u7", &Target.riscv.cpu.sifive_7_series },
        .{ "sifive,u74", &Target.riscv.cpu.sifive_u74 },
        .{ "sifive,u74-mc", &Target.riscv.cpu.sifive_u74 },
        .{ "sifive,x280", &Target.riscv.cpu.sifive_x280 },
        .{ "spacemit,x60", &Target.riscv.cpu.spacemit_x60 },
        .{ "spacemit,x100", &Target.riscv.cpu.spacemit_x100 },
    };

    fn line_hook(self: *RiscvCpuinfoImpl, key: []const u8, value: []const u8) !bool {
        if (mem.eql(u8, key, "uarch")) {
            inline for (cpu_names) |pair| {
                if (mem.eql(u8, value, pair[0])) {
                    self.model = pair[1];
                    break;
                }
            }
            return false;
        }

        return true;
    }

    fn finalize(self: *const RiscvCpuinfoImpl, arch: Target.Cpu.Arch) ?Target.Cpu {
        const model = self.model orelse return null;
        return Target.Cpu{
            .arch = arch,
            .model = model,
            .features = model.features,
        };
    }
};

const RiscvCpuinfoParser = CpuinfoParser(RiscvCpuinfoImpl);

test "cpuinfo: RISC-V" {
    try testParser(RiscvCpuinfoParser, .riscv64, &Target.riscv.cpu.sifive_u74,
        \\processor : 0
        \\hart      : 1
        \\isa       : rv64imafdc
        \\mmu       : sv39
        \\isa-ext   :
        \\uarch     : sifive,u74-mc
    );
}

const PowerpcCpuinfoImpl = struct {
    model: ?*const Target.Cpu.Model = null,

    const cpu_names = .{
        .{ "604e", &Target.powerpc.cpu.@"604e" },
        .{ "604", &Target.powerpc.cpu.@"604" },
        .{ "7400", &Target.powerpc.cpu.@"7400" },
        .{ "7410", &Target.powerpc.cpu.@"7400" },
        .{ "7447", &Target.powerpc.cpu.@"7400" },
        .{ "7455", &Target.powerpc.cpu.@"7450" },
        .{ "G4", &Target.powerpc.cpu.g4 },
        .{ "POWER4", &Target.powerpc.cpu.@"970" },
        .{ "PPC970FX", &Target.powerpc.cpu.@"970" },
        .{ "PPC970MP", &Target.powerpc.cpu.@"970" },
        .{ "G5", &Target.powerpc.cpu.g5 },
        .{ "POWER5", &Target.powerpc.cpu.g5 },
        .{ "A2", &Target.powerpc.cpu.a2 },
        .{ "POWER6", &Target.powerpc.cpu.pwr6 },
        .{ "POWER7", &Target.powerpc.cpu.pwr7 },
        .{ "POWER8", &Target.powerpc.cpu.pwr8 },
        .{ "POWER8E", &Target.powerpc.cpu.pwr8 },
        .{ "POWER8NVL", &Target.powerpc.cpu.pwr8 },
        .{ "POWER9", &Target.powerpc.cpu.pwr9 },
        .{ "POWER10", &Target.powerpc.cpu.pwr10 },
        .{ "POWER11", &Target.powerpc.cpu.pwr11 },
    };

    fn line_hook(self: *PowerpcCpuinfoImpl, key: []const u8, value: []const u8) !bool {
        if (mem.eql(u8, key, "cpu")) {
            // The model name is often followed by a comma or space and extra
            // info.
            inline for (cpu_names) |pair| {
                const end_index = mem.findAny(u8, value, ", ") orelse value.len;
                if (mem.eql(u8, value[0..end_index], pair[0])) {
                    self.model = pair[1];
                    break;
                }
            }

            // Stop the detection once we've seen the first core.
            return false;
        }

        return true;
    }

    fn finalize(self: *const PowerpcCpuinfoImpl, arch: Target.Cpu.Arch) ?Target.Cpu {
        const model = self.model orelse return null;
        return Target.Cpu{
            .arch = arch,
            .model = model,
            .features = model.features,
        };
    }
};

const PowerpcCpuinfoParser = CpuinfoParser(PowerpcCpuinfoImpl);

test "cpuinfo: PowerPC" {
    try testParser(PowerpcCpuinfoParser, .powerpc, &Target.powerpc.cpu.@"970",
        \\processor : 0
        \\cpu       : PPC970MP, altivec supported
        \\clock     : 1250.000000MHz
        \\revision  : 1.1 (pvr 0044 0101)
    );
    try testParser(PowerpcCpuinfoParser, .powerpc64le, &Target.powerpc.cpu.pwr8,
        \\processor : 0
        \\cpu       : POWER8 (raw), altivec supported
        \\clock     : 2926.000000MHz
        \\revision  : 2.0 (pvr 004d 0200)
    );
}

const S390xCpuinfoImpl = struct {
    model: ?*const Target.Cpu.Model = null,

    const cpu_names = .{
        // z900: 2064, 2066
        // z990: 2084, 2086
        // z9: 2094, 2096

        .{ "2097", &Target.s390x.cpu.z10 },
        .{ "2098", &Target.s390x.cpu.z10 },
        .{ "2817", &Target.s390x.cpu.z196 },
        .{ "2818", &Target.s390x.cpu.z196 },
        .{ "2827", &Target.s390x.cpu.zEC12 },
        .{ "2828", &Target.s390x.cpu.zEC12 },
        .{ "2964", &Target.s390x.cpu.z13 },
        .{ "2965", &Target.s390x.cpu.z13 },
        .{ "3906", &Target.s390x.cpu.z14 },
        .{ "3907", &Target.s390x.cpu.z14 },
        .{ "8561", &Target.s390x.cpu.z15 },
        .{ "8562", &Target.s390x.cpu.z15 },
        .{ "3931", &Target.s390x.cpu.z16 },
        .{ "3932", &Target.s390x.cpu.z16 },
        .{ "9175", &Target.s390x.cpu.z17 },
        .{ "9176", &Target.s390x.cpu.z17 },
    };

    fn line_hook(self: *S390xCpuinfoImpl, key: []const u8, value: []const u8) !bool {
        if (mem.eql(u8, key, "machine")) {
            inline for (cpu_names) |pair| {
                if (mem.eql(u8, value, pair[0])) {
                    self.model = pair[1];
                    break;
                }
            }

            return false;
        }

        return true;
    }

    fn finalize(self: *const S390xCpuinfoImpl, arch: Target.Cpu.Arch) ?Target.Cpu {
        const model = self.model orelse return null;
        return Target.Cpu{
            .arch = arch,
            .model = model,
            .features = model.features,
        };
    }
};

const S390xCpuinfoParser = CpuinfoParser(S390xCpuinfoImpl);

test "cpuinfo: S390x" {
    try testParser(S390xCpuinfoParser, .s390x, &Target.s390x.cpu.z15,
        \\physical id     : 5
        \\core id         : 5
        \\book id         : 5
        \\drawer id       : 5
        \\dedicated       : 0
        \\address         : 5
        \\siblings        : 1
        \\cpu cores       : 1
        \\version         : FF
        \\identification  : 09DD98
        \\machine         : 8561
        \\cpu MHz dynamic : 5200
        \\cpu MHz static  : 5200
    );
}

const ArmCpuinfoImpl = struct {
    const num_cores = 4;

    cores: [num_cores]CoreInfo = undefined,
    core_no: usize = 0,
    have_fields: usize = 0,

    const CoreInfo = struct {
        architecture: u8 = 0,
        implementer: u8 = 0,
        variant: u8 = 0,
        part: u16 = 0,
        is_really_v6: bool = false,
    };

    const cpu_models = @import("arm.zig").cpu_models;

    fn addOne(self: *ArmCpuinfoImpl) void {
        if (self.have_fields == 4 and self.core_no < num_cores) {
            if (self.core_no > 0) {
                // Deduplicate the core info.
                for (self.cores[0..self.core_no]) |it| {
                    if (std.meta.eql(it, self.cores[self.core_no]))
                        return;
                }
            }
            self.core_no += 1;
        }
    }

    fn line_hook(self: *ArmCpuinfoImpl, key: []const u8, value: []const u8) !bool {
        const info = &self.cores[self.core_no];

        if (mem.eql(u8, key, "processor")) {
            // Handle both old-style and new-style cpuinfo formats.
            // The former prints a sequence of "processor: N" lines for each
            // core and then the info for the core that's executing this code(!)
            // while the latter prints the infos for each core right after the
            // "processor" key.
            self.have_fields = 0;
            self.cores[self.core_no] = .{};
        } else if (mem.eql(u8, key, "CPU implementer")) {
            info.implementer = try fmt.parseInt(u8, value, 0);
            self.have_fields += 1;
        } else if (mem.eql(u8, key, "CPU architecture")) {
            // "AArch64" on older kernels.
            info.architecture = if (mem.startsWith(u8, value, "AArch64"))
                8
            else
                try fmt.parseInt(u8, value, 0);
            self.have_fields += 1;
        } else if (mem.eql(u8, key, "CPU variant")) {
            info.variant = try fmt.parseInt(u8, value, 0);
            self.have_fields += 1;
        } else if (mem.eql(u8, key, "CPU part")) {
            info.part = try fmt.parseInt(u16, value, 0);
            self.have_fields += 1;
        } else if (mem.eql(u8, key, "model name")) {
            // ARMv6 cores report "CPU architecture" equal to 7.
            if (mem.find(u8, value, "(v6l)")) |_| {
                info.is_really_v6 = true;
            }
        } else if (mem.eql(u8, key, "CPU revision")) {
            // This field is always the last one for each CPU section.
            _ = self.addOne();
        }

        return true;
    }

    fn finalize(self: *ArmCpuinfoImpl, arch: Target.Cpu.Arch) ?Target.Cpu {
        if (self.core_no == 0) return null;

        const is_64bit = switch (arch) {
            .aarch64, .aarch64_be => true,
            else => false,
        };

        var known_models: [num_cores]?*const Target.Cpu.Model = undefined;
        for (self.cores[0..self.core_no], 0..) |core, i| {
            known_models[i] = cpu_models.isKnown(.{
                .architecture = core.architecture,
                .implementer = core.implementer,
                .variant = core.variant,
                .part = core.part,
            }, is_64bit);
        }

        // XXX We pick the first core on big.LITTLE systems, hopefully the
        // LITTLE one.
        const model = known_models[0] orelse return null;
        return Target.Cpu{
            .arch = arch,
            .model = model,
            .features = model.features,
        };
    }
};

const ArmCpuinfoParser = CpuinfoParser(ArmCpuinfoImpl);

test "cpuinfo: ARM" {
    try testParser(ArmCpuinfoParser, .arm, &Target.arm.cpu.arm1176jz_s,
        \\processor       : 0
        \\model name      : ARMv6-compatible processor rev 7 (v6l)
        \\BogoMIPS        : 997.08
        \\Features        : half thumb fastmult vfp edsp java tls
        \\CPU implementer : 0x41
        \\CPU architecture: 7
        \\CPU variant     : 0x0
        \\CPU part        : 0xb76
        \\CPU revision    : 7
    );
    try testParser(ArmCpuinfoParser, .arm, &Target.arm.cpu.cortex_a7,
        \\processor : 0
        \\model name : ARMv7 Processor rev 3 (v7l)
        \\BogoMIPS : 18.00
        \\Features : half thumb fastmult vfp edsp neon vfpv3 tls vfpv4 idiva idivt vfpd32 lpae
        \\CPU implementer : 0x41
        \\CPU architecture: 7
        \\CPU variant : 0x0
        \\CPU part : 0xc07
        \\CPU revision : 3
        \\
        \\processor : 4
        \\model name : ARMv7 Processor rev 3 (v7l)
        \\BogoMIPS : 90.00
        \\Features : half thumb fastmult vfp edsp neon vfpv3 tls vfpv4 idiva idivt vfpd32 lpae
        \\CPU implementer : 0x41
        \\CPU architecture: 7
        \\CPU variant : 0x2
        \\CPU part : 0xc0f
        \\CPU revision : 3
    );
    try testParser(ArmCpuinfoParser, .aarch64, &Target.aarch64.cpu.cortex_a72,
        \\processor       : 0
        \\BogoMIPS        : 108.00
        \\Features        : fp asimd evtstrm crc32 cpuid
        \\CPU implementer : 0x41
        \\CPU architecture: 8
        \\CPU variant     : 0x0
        \\CPU part        : 0xd08
        \\CPU revision    : 3
    );
}

fn testParser(
    parser: anytype,
    arch: Target.Cpu.Arch,
    expected_model: *const Target.Cpu.Model,
    input: []const u8,
) !void {
    var r: Io.Reader = .fixed(input);
    const result = try parser.parse(arch, &r);
    try testing.expectEqual(expected_model, result.?.model);
    try testing.expect(expected_model.features.eql(result.?.features));
}

// The generic implementation of a /proc/cpuinfo parser.
// For every line it invokes the line_hook method with the key and value strings
// as first and second parameters. Returning false from the hook function stops
// the iteration without raising an error.
// When all the lines have been analyzed the finalize method is called.
fn CpuinfoParser(comptime impl: anytype) type {
    return struct {
        fn parse(arch: Target.Cpu.Arch, reader: *Io.Reader) !?Target.Cpu {
            var obj: impl = .{};
            while (try reader.takeDelimiter('\n')) |line| {
                const colon_pos = mem.findScalar(u8, line, ':') orelse continue;
                const key = mem.trimEnd(u8, line[0..colon_pos], " \t");
                const value = mem.trimStart(u8, line[colon_pos + 1 ..], " \t");
                if (!try obj.line_hook(key, value)) break;
            }
            return obj.finalize(arch);
        }
    };
}

const aarch64 = struct {
    inline fn mrs(comptime feat_reg: []const u8) u64 {
        return asm ("mrs %[ret], " ++ feat_reg
            : [ret] "=r" (-> u64),
        );
    }
};

const riscv = struct {
    const linux = std.os.linux;
    const RISCV_HWPROBE = linux.RISCV_HWPROBE;

    fn setFeature(cpu: *Target.Cpu, feature: Target.riscv.Feature, enabled: bool) void {
        const idx = @as(Target.Cpu.Feature.Set.Index, @backingInt(feature));

        if (enabled) cpu.features.addFeature(idx) else cpu.features.removeFeature(idx);
    }

    inline fn set(value: u64, mask: u64) bool {
        return (value & mask) == mask;
    }

    pub fn detectCpuFeatures(cpu: *Target.Cpu) void {
        var probes = [_]linux.riscv_hwprobe{
            .{ .key = RISCV_HWPROBE.KEY.BASE_BEHAVIOR, .value = 0 },
            .{ .key = RISCV_HWPROBE.KEY.IMA_EXT_0, .value = 0 },
            .{ .key = RISCV_HWPROBE.KEY.MISALIGNED_SCALAR_PERF, .value = 0 },
            .{ .key = RISCV_HWPROBE.KEY.MISALIGNED_VECTOR_PERF, .value = 0 },
            .{ .key = RISCV_HWPROBE.KEY.VENDOR_EXT_MIPS_0, .value = 0 },
            .{ .key = RISCV_HWPROBE.KEY.VENDOR_EXT_SIFIVE_0, .value = 0 },
            .{ .key = RISCV_HWPROBE.KEY.IMA_EXT_1, .value = 0 },
        };

        const rc = linux.sys_riscv_hwprobe(&probes, probes.len, 0, null, 0);
        if (linux.errno(rc) == .NOSYS)
            return;

        var ima_support = false;
        for (probes) |probe| {
            const value = probe.value;

            switch (probe.key) {
                -1 => continue, // The running kernel doesn't know this key.
                RISCV_HWPROBE.KEY.BASE_BEHAVIOR => {
                    ima_support = set(value, RISCV_HWPROBE.BASE_BEHAVIOR_IMA);
                    setFeature(cpu, Target.riscv.Feature.i, ima_support);
                    setFeature(cpu, Target.riscv.Feature.m, ima_support);
                    setFeature(cpu, Target.riscv.Feature.a, ima_support);
                },
                RISCV_HWPROBE.KEY.IMA_EXT_0 => {
                    // https://bugzilla.kernel.org/show_bug.cgi?id=221874
                    const fd_support = set(value, RISCV_HWPROBE.IMA_EXT_0.IMA_FD);
                    setFeature(cpu, .f, ima_support and fd_support);
                    setFeature(cpu, .d, ima_support and fd_support);
                    setFeature(cpu, .c, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.IMA_C));
                    setFeature(cpu, .v, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.IMA_V));
                    setFeature(cpu, .zba, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZBA));
                    setFeature(cpu, .zbb, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZBB));
                    setFeature(cpu, .zbs, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZBS));
                    setFeature(cpu, .zicboz, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZICBOZ));
                    setFeature(cpu, .zbc, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZBC));
                    setFeature(cpu, .zbkb, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZBKB));
                    setFeature(cpu, .zbkc, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZBKC));
                    setFeature(cpu, .zbkx, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZBKX));
                    setFeature(cpu, .zknd, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZKND));
                    setFeature(cpu, .zkne, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZKNE));
                    setFeature(cpu, .zknh, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZKNH));
                    setFeature(cpu, .zksed, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZKSED));
                    setFeature(cpu, .zksh, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZKSH));
                    setFeature(cpu, .zkt, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZKT));
                    setFeature(cpu, .zvbb, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVBB));
                    setFeature(cpu, .zvbc, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVBC));
                    setFeature(cpu, .zvkb, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVKB));
                    setFeature(cpu, .zvkg, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVKG));
                    setFeature(cpu, .zvkned, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVKNED));
                    setFeature(cpu, .zvknha, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVKNHA));
                    setFeature(cpu, .zvknhb, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVKNHB));
                    setFeature(cpu, .zvksed, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVKSED));
                    setFeature(cpu, .zvksh, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVKSH));
                    setFeature(cpu, .zvkt, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVKT));
                    setFeature(cpu, .zfh, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZFH));
                    setFeature(cpu, .zfhmin, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZFHMIN));
                    setFeature(cpu, .zihintntl, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZIHINTNTL));
                    setFeature(cpu, .zvfh, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVFH));
                    setFeature(cpu, .zvfhmin, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVFHMIN));
                    setFeature(cpu, .zfa, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZFA));
                    setFeature(cpu, .ztso, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZTSO));
                    setFeature(cpu, .zacas, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZACAS));
                    setFeature(cpu, .zicntr, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZICNTR));
                    setFeature(cpu, .zicond, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZICOND));
                    setFeature(cpu, .zihintpause, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZIHINTPAUSE));
                    setFeature(cpu, .zihpm, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZIHPM));
                    setFeature(cpu, .zve32x, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVE32X));
                    setFeature(cpu, .zve32f, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVE32F));
                    setFeature(cpu, .zve64x, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVE64X));
                    setFeature(cpu, .zve64f, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVE64F));
                    setFeature(cpu, .zve64d, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVE64D));
                    setFeature(cpu, .zimop, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZIMOP));
                    setFeature(cpu, .zca, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZCA));
                    setFeature(cpu, .zcb, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZCB));
                    setFeature(cpu, .zcd, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZCD));
                    setFeature(cpu, .zcf, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZCF));
                    setFeature(cpu, .zcmop, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZCMOP));
                    setFeature(cpu, .zawrs, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZAWRS));
                    setFeature(cpu, .supm, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_SUPM));
                    setFeature(cpu, .zicntr, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZICNTR));
                    setFeature(cpu, .zihpm, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZIHPM));
                    setFeature(cpu, .zfbfmin, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZFBFMIN));
                    setFeature(cpu, .zvfbfmin, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVFBFMIN));
                    setFeature(cpu, .zvfbfwma, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVFBFWMA));
                    setFeature(cpu, .zicbom, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZICBOM));
                    setFeature(cpu, .zaamo, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZAAMO));
                    setFeature(cpu, .zalrsc, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZALRSC));
                    setFeature(cpu, .zabha, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZABHA));
                    setFeature(cpu, .zalasr, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZALASR));
                    setFeature(cpu, .zicbop, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZICBOP));
                    setFeature(cpu, .zilsd, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZILSD));
                    setFeature(cpu, .zclsd, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZCLSD));
                    setFeature(cpu, .experimental_zicfilp, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZICFILP));
                },
                RISCV_HWPROBE.KEY.MISALIGNED_SCALAR_PERF => {
                    setFeature(cpu, .unaligned_scalar_mem, value == RISCV_HWPROBE.MISALIGNED_SCALAR.FAST);
                },
                RISCV_HWPROBE.KEY.MISALIGNED_VECTOR_PERF => {
                    setFeature(cpu, .unaligned_vector_mem, value == RISCV_HWPROBE.MISALIGNED_VECTOR.FAST);
                },
                RISCV_HWPROBE.KEY.VENDOR_EXT_MIPS_0 => {
                    setFeature(cpu, .xmipsexectl, ima_support and set(value, RISCV_HWPROBE.MIPS_VENDOR_EXT_XMIPSEXECTL));
                },
                RISCV_HWPROBE.KEY.VENDOR_EXT_SIFIVE_0 => {
                    setFeature(cpu, .xsfvqmaccdod, ima_support and set(value, RISCV_HWPROBE.SIFIVE_VENDOR_EXT.XSFVQMACCDOD));
                    setFeature(cpu, .xsfvqmaccqoq, ima_support and set(value, RISCV_HWPROBE.SIFIVE_VENDOR_EXT.XSFVQMACCQOQ));
                    setFeature(cpu, .xsfvfnrclipxfqf, ima_support and set(value, RISCV_HWPROBE.SIFIVE_VENDOR_EXT.XSFVFNRCLIPXFQF));
                    setFeature(cpu, .xsfvfwmaccqqq, ima_support and set(value, RISCV_HWPROBE.SIFIVE_VENDOR_EXT.XSFVFWMACCQQQ));
                },
                RISCV_HWPROBE.KEY.IMA_EXT_1 => {
                    setFeature(cpu, .experimental_zicfiss, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_1_EXT_ZICFISS));
                },
                else => unreachable,
            }
        }
    }
};

pub fn detectNativeCpuAndFeatures(io: Io) ?Target.Cpu {
    var file = Io.Dir.openFileAbsolute(io, "/proc/cpuinfo", .{}) catch |err| switch (err) {
        else => return null,
    };
    defer file.close(io);

    var buffer: [4096]u8 = undefined; // "flags" lines can get pretty long.
    var file_reader = file.reader(io, &buffer);

    const current_arch = builtin.cpu.arch;
    return switch (current_arch) {
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

            break :b @import("arm.zig").aarch64.detectNativeCpuAndFeatures(current_arch, registers);
        },
        .arm, .armeb, .thumb, .thumbeb => ArmCpuinfoParser.parse(current_arch, &file_reader.interface) catch null,
        .powerpc, .powerpcle, .powerpc64, .powerpc64le => PowerpcCpuinfoParser.parse(current_arch, &file_reader.interface) catch null,
        .riscv64, .riscv32 => b: {
            var cpu = (RiscvCpuinfoParser.parse(current_arch, &file_reader.interface) catch null) orelse cpu: {
                const model = Target.Cpu.Model.generic(current_arch);
                break :cpu Target.Cpu{
                    .arch = current_arch,
                    .model = model,
                    .features = model.features,
                };
            };

            riscv.detectCpuFeatures(&cpu);
            cpu.features.populateDependencies(cpu.arch.allFeaturesList());

            break :b cpu;
        },
        .s390x => S390xCpuinfoParser.parse(current_arch, &file_reader.interface) catch null,
        .sparc, .sparc64 => SparcCpuinfoParser.parse(current_arch, &file_reader.interface) catch null,
        else => null,
    };
}
