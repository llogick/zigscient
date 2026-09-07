const builtin = @import("builtin");

const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const fs = std.fs;
const fmt = std.fmt;
const testing = std.testing;
const Target = std.Target;
const assert = std.debug.assert;

// The generic implementation of a /proc/cpuinfo parser.
// For every line it invokes the lineHook method with the key and value strings
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
                if (!try obj.lineHook(key, value)) break;
            }
            return obj.finalize(arch);
        }
    };
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

const aarch64 = struct {
    inline fn mrs(comptime feat_reg: []const u8) u64 {
        return asm ("mrs %[ret], " ++ feat_reg
            : [ret] "=r" (-> u64),
        );
    }

    pub fn detectNativeCpuAndFeatures(arch: Target.Cpu.Arch) ?Target.Cpu {
        const registers = [12]u64{
            mrs("MIDR_EL1"),
            mrs("ID_AA64PFR0_EL1"),
            mrs("ID_AA64PFR1_EL1"),
            mrs("ID_AA64DFR0_EL1"),
            mrs("ID_AA64DFR1_EL1"),
            mrs("ID_AA64AFR0_EL1"),
            mrs("ID_AA64AFR1_EL1"),
            mrs("ID_AA64ISAR0_EL1"),
            mrs("ID_AA64ISAR1_EL1"),
            mrs("ID_AA64MMFR0_EL1"),
            mrs("ID_AA64MMFR1_EL1"),
            mrs("ID_AA64MMFR2_EL1"),
        };

        return @import("arm.zig").aarch64.detectNativeCpuAndFeatures(arch, registers);
    }
};

const arm = struct {
    const cpuinfo = struct {
        const Impl = struct {
            implementer: u8 = 0,
            variant: u8 = 0,
            part: u16 = 0,

            have_fields: u8 = 0,

            const cpu_models = @import("arm.zig").cpu_models;

            fn lineHook(self: *Impl, key: []const u8, value: []const u8) !bool {
                if (mem.eql(u8, key, "CPU implementer")) {
                    self.implementer = try fmt.parseInt(u8, value, 0);
                    self.have_fields += 1;
                } else if (mem.eql(u8, key, "CPU variant")) {
                    self.variant = try fmt.parseInt(u8, value, 0);
                    self.have_fields += 1;
                } else if (mem.eql(u8, key, "CPU part")) {
                    self.part = try fmt.parseInt(u16, value, 0);
                    self.have_fields += 1;
                } else if (mem.eql(u8, key, "CPU revision")) {
                    // This field is always the last one for each CPU section.
                    return false;
                }

                return true;
            }

            fn finalize(self: *Impl, arch: Target.Cpu.Arch) ?Target.Cpu {
                if (self.have_fields != 3) return null;

                const model = cpu_models.isKnown(.{
                    .architecture = undefined, // unused for the lookup
                    .implementer = self.implementer,
                    .variant = self.variant,
                    .part = self.part,
                }, false) orelse return null;

                // We pick the first core on big.LITTLE systems, hopefully the LITTLE one.
                return .{
                    .arch = arch,
                    .model = model,
                    .features = model.features,
                };
            }
        };

        const Parser = CpuinfoParser(Impl);
    };

    test cpuinfo {
        try testParser(cpuinfo.Parser, .arm, &Target.arm.cpu.arm1176jz_s,
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
        try testParser(cpuinfo.Parser, .arm, &Target.arm.cpu.cortex_a7,
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
        try testParser(cpuinfo.Parser, .arm, &Target.arm.cpu.cortex_a72,
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

    pub fn detectNativeCpu(io: Io, arch: Target.Cpu.Arch) ?Target.Cpu {
        var file = Io.Dir.openFileAbsolute(io, "/proc/cpuinfo", .{}) catch return null;
        defer file.close(io);

        var buffer: [4096]u8 = undefined;
        var file_reader = file.reader(io, &buffer);

        var cpu = (cpuinfo.Parser.parse(arch, &file_reader.interface) catch null) orelse return null;

        cpu.features.populateDependencies(cpu.arch.allFeaturesList());

        return cpu;
    }
};

const csky = struct {
    const cpuinfo = struct {
        const Impl = struct {
            model: ?*const Target.Cpu.Model = null,

            const cpu_names = .{
                .{ "ck807", &Target.csky.cpu.ck807 },
                .{ "ck807f", &Target.csky.cpu.ck807f },
                .{ "ck810", &Target.csky.cpu.ck810 },
                .{ "ck810f", &Target.csky.cpu.ck810f },
                .{ "ck810t", &Target.csky.cpu.ck810t },
                .{ "ck810ft", &Target.csky.cpu.ck810ft },
                .{ "ck860", &Target.csky.cpu.ck860 },
                .{ "ck860f", &Target.csky.cpu.ck860f },
                .{ "ck860fv", &Target.csky.cpu.ck860fv },
            };

            fn lineHook(self: *Impl, key: []const u8, value: []const u8) !bool {
                if (mem.eql(u8, key, "C-SKY CPU model")) {
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

            fn finalize(self: *const Impl, arch: Target.Cpu.Arch) ?Target.Cpu {
                const model = self.model orelse return null;
                return .{
                    .arch = arch,
                    .model = model,
                    .features = model.features,
                };
            }
        };

        const Parser = CpuinfoParser(Impl);
    };

    pub fn detectNativeCpu(io: Io, arch: Target.Cpu.Arch) ?Target.Cpu {
        var file = Io.Dir.openFileAbsolute(io, "/proc/cpuinfo", .{}) catch return null;
        defer file.close(io);

        var buffer: [4096]u8 = undefined;
        var file_reader = file.reader(io, &buffer);

        var cpu = (cpuinfo.Parser.parse(arch, &file_reader.interface) catch null) orelse return null;

        cpu.features.populateDependencies(cpu.arch.allFeaturesList());

        return cpu;
    }
};

const m68k = struct {
    const cpuinfo = struct {
        const Impl = struct {
            model: ?*const Target.Cpu.Model = null,

            const cpu_names = .{
                .{ "68020", &Target.m68k.cpu.M68020 },
                .{ "68030", &Target.m68k.cpu.M68030 },
                .{ "68040", &Target.m68k.cpu.M68040 },
                .{ "68060", &Target.m68k.cpu.M68060 },
            };

            fn lineHook(self: *Impl, key: []const u8, value: []const u8) !bool {
                if (mem.eql(u8, key, "CPU")) {
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

            fn finalize(self: *const Impl, arch: Target.Cpu.Arch) ?Target.Cpu {
                const model = self.model orelse return null;
                return .{
                    .arch = arch,
                    .model = model,
                    .features = model.features,
                };
            }
        };

        const Parser = CpuinfoParser(Impl);
    };

    pub fn detectNativeCpu(io: Io, arch: Target.Cpu.Arch) ?Target.Cpu {
        var file = Io.Dir.openFileAbsolute(io, "/proc/cpuinfo", .{}) catch return null;
        defer file.close(io);

        var buffer: [4096]u8 = undefined;
        var file_reader = file.reader(io, &buffer);

        var cpu = (cpuinfo.Parser.parse(arch, &file_reader.interface) catch null) orelse return null;

        cpu.features.populateDependencies(cpu.arch.allFeaturesList());

        return cpu;
    }
};

const mips = struct {
    const cpuinfo = struct {
        const Impl = struct {
            model: ?*const Target.Cpu.Model = null,

            const cpu_names = .{
                .{ "Cavium Octeon III", &Target.mips.cpu.@"octeon+" },
                .{ "Cavium Octeon II", &Target.mips.cpu.@"octeon+" },
                .{ "Cavium Octeon+", &Target.mips.cpu.@"octeon+" },
                .{ "Cavium Octeon", &Target.mips.cpu.octeon },
                .{ "MIPS I6400", &Target.mips.cpu.i6400 },
                .{ "MIPS I6500", &Target.mips.cpu.i6500 },
                .{ "MIPS P5600", &Target.mips.cpu.p5600 },
                .{ "R3000A", &Target.mips.cpu.r3000a },
            };

            const isa_names = .{
                .{ "mips64r6", &Target.mips.cpu.mips64r6 },
                .{ "mips64r5", &Target.mips.cpu.mips64r5 },
                .{ "mips64r2", &Target.mips.cpu.mips64r2 },
                .{ "mips64r1", &Target.mips.cpu.mips64 },
                .{ "mips32r6", &Target.mips.cpu.mips32r6 },
                .{ "mips32r5", &Target.mips.cpu.mips32r5 },
                .{ "mips32r2", &Target.mips.cpu.mips32r2 },
                .{ "mips32r1", &Target.mips.cpu.mips32 },
                .{ "mips5", &Target.mips.cpu.mips5 },
                .{ "mips4", &Target.mips.cpu.mips4 },
                .{ "mips3", &Target.mips.cpu.mips3 },
                .{ "mips2", &Target.mips.cpu.mips2 },
                .{ "mips1", &Target.mips.cpu.mips1 },
            };

            fn lineHook(self: *Impl, key: []const u8, value: []const u8) !bool {
                // The `cpu model` line always comes before `isa`, which is perfect for us since we
                // want the explicit model to take precedence over the generic ISA identifier.
                if (mem.eql(u8, key, "cpu model")) {
                    inline for (cpu_names) |pair| {
                        if (mem.find(u8, value, pair[0]) != null) {
                            self.model = pair[1];
                            return false;
                        }
                    }
                } else if (mem.eql(u8, key, "isa")) {
                    inline for (isa_names) |pair| {
                        if (mem.find(u8, value, pair[0]) != null) {
                            self.model = pair[1];
                            break;
                        }
                    }

                    // If we haven't found anything useful by here, we we may as well stop.
                    return false;
                }

                return true;
            }

            fn finalize(self: *const Impl, arch: Target.Cpu.Arch) ?Target.Cpu {
                const model = self.model orelse return null;
                return .{
                    .arch = arch,
                    .model = model,
                    .features = model.features,
                };
            }
        };

        const Parser = CpuinfoParser(Impl);
    };

    test cpuinfo {
        try testParser(cpuinfo.Parser, .mips64, &Target.mips.cpu.@"octeon+",
            \\system type             : UBNT_E300
            \\machine                 : Unknown
            \\processor               : 0
            \\cpu model               : Cavium Octeon III V0.2  FPU V0.0
            \\BogoMIPS                : 2000.00
            \\wait instruction        : yes
            \\microsecond timers      : yes
            \\tlb_entries             : 256
            \\extra interrupt vector  : yes
            \\hardware watchpoint     : yes, count: 2, address/irw mask: [0x0ffc, 0x0ffb]
            \\isa                     : mips1 mips2 mips3 mips4 mips5 mips64r2
            \\ASEs implemented        : vz
            \\shadow register sets    : 1
            \\kscratch registers      : 4
            \\package                 : 0
            \\core                    : 0
            \\VCED exceptions         : not available
            \\VCEI exceptions         : not available
        );
    }

    pub fn detectNativeCpu(io: Io, arch: Target.Cpu.Arch) ?Target.Cpu {
        var file = Io.Dir.openFileAbsolute(io, "/proc/cpuinfo", .{}) catch return null;
        defer file.close(io);

        var buffer: [4096]u8 = undefined;
        var file_reader = file.reader(io, &buffer);

        var cpu = (cpuinfo.Parser.parse(arch, &file_reader.interface) catch null) orelse return null;

        cpu.features.populateDependencies(cpu.arch.allFeaturesList());

        return cpu;
    }
};

const powerpc = struct {
    const cpuinfo = struct {
        const Impl = struct {
            model: ?*const Target.Cpu.Model = null,

            const cpu_names = .{
                .{ "440EPX", &Target.powerpc.cpu.@"440" },
                .{ "440EP", &Target.powerpc.cpu.@"440" },
                .{ "460EX", &Target.powerpc.cpu.@"440" },
                .{ "440GP", &Target.powerpc.cpu.@"440" },
                .{ "440GRX", &Target.powerpc.cpu.@"440" },
                .{ "440GR", &Target.powerpc.cpu.@"440" },
                .{ "460GT", &Target.powerpc.cpu.@"440" },
                .{ "440GX", &Target.powerpc.cpu.@"440" },
                .{ "440SPe", &Target.powerpc.cpu.@"440" },
                .{ "440SP", &Target.powerpc.cpu.@"440" },
                .{ "460SX", &Target.powerpc.cpu.@"440" },
                .{ "603ev", &Target.powerpc.cpu.@"603ev" },
                .{ "603e", &Target.powerpc.cpu.@"603e" },
                .{ "603", &Target.powerpc.cpu.@"603" },
                .{ "604ev", &Target.powerpc.cpu.@"604e" },
                .{ "604e", &Target.powerpc.cpu.@"604e" },
                .{ "604r", &Target.powerpc.cpu.@"603e" },
                .{ "604", &Target.powerpc.cpu.@"604" },
                .{ "7400", &Target.powerpc.cpu.@"7400" },
                .{ "7410", &Target.powerpc.cpu.@"7400" },
                .{ "7447/7457", &Target.powerpc.cpu.@"7450" },
                .{ "7447A", &Target.powerpc.cpu.@"7450" },
                .{ "7448", &Target.powerpc.cpu.@"7450" },
                .{ "7450", &Target.powerpc.cpu.@"7450" },
                .{ "7455", &Target.powerpc.cpu.@"7450" },
                .{ "740/750", &Target.powerpc.cpu.@"750" },
                .{ "745/755", &Target.powerpc.cpu.@"750" },
                .{ "750CL", &Target.powerpc.cpu.@"750" },
                .{ "750CXe", &Target.powerpc.cpu.@"750" },
                .{ "750CX", &Target.powerpc.cpu.@"750" },
                .{ "750FX", &Target.powerpc.cpu.@"750" },
                .{ "750GX", &Target.powerpc.cpu.@"750" },
                .{ "82xx", &Target.powerpc.cpu.@"603e" },
                .{ "APM821XX", &Target.powerpc.cpu.@"440" },
                .{ "Cell", &Target.powerpc.cpu.ppc64 }, // TODO: Change with LLVM 23.
                .{ "e300c1", &Target.powerpc.cpu.@"603e" },
                .{ "e300c2", &Target.powerpc.cpu.@"603e" },
                .{ "e300c3", &Target.powerpc.cpu.@"603e" },
                .{ "e300c4", &Target.powerpc.cpu.@"603e" },
                .{ "e500mc", &Target.powerpc.cpu.e500mc },
                .{ "e500v2", &Target.powerpc.cpu.e500 }, // TODO: Change with LLVM 23.
                .{ "e500", &Target.powerpc.cpu.e500 },
                .{ "e5500", &Target.powerpc.cpu.e5500 },
                .{ "e6500", &Target.powerpc.cpu.e5500 }, // TODO: Change with LLVM 23.
                .{ "G2_LE", &Target.powerpc.cpu.@"603e" },
                .{ "HX-C2000", &Target.powerpc.cpu.pwr8 },
                .{ "POWER5+", &Target.powerpc.cpu.pwr5x },
                .{ "POWER5", &Target.powerpc.cpu.pwr5 },
                .{ "POWER6", &Target.powerpc.cpu.pwr6 },
                .{ "POWER7+", &Target.powerpc.cpu.pwr7 },
                .{ "POWER7", &Target.powerpc.cpu.pwr7 },
                .{ "POWER8E", &Target.powerpc.cpu.pwr8 },
                .{ "POWER8NVL", &Target.powerpc.cpu.pwr8 },
                .{ "POWER8", &Target.powerpc.cpu.pwr8 },
                .{ "POWER9P", &Target.powerpc.cpu.pwr9 },
                .{ "POWER9", &Target.powerpc.cpu.pwr9 },
                .{ "POWER10", &Target.powerpc.cpu.pwr10 },
                .{ "Power11", &Target.powerpc.cpu.pwr11 },
                .{ "PPC970FX", &Target.powerpc.cpu.@"970" },
                .{ "PPC970GX", &Target.powerpc.cpu.@"970" },
                .{ "PPC970MP", &Target.powerpc.cpu.@"970" },
                .{ "PPC970", &Target.powerpc.cpu.@"970" },
            };

            fn lineHook(self: *Impl, key: []const u8, value: []const u8) !bool {
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

            fn finalize(self: *const Impl, arch: Target.Cpu.Arch) ?Target.Cpu {
                const model = self.model orelse return null;
                return Target.Cpu{
                    .arch = arch,
                    .model = model,
                    .features = model.features,
                };
            }
        };

        const Parser = CpuinfoParser(Impl);
    };

    test cpuinfo {
        try testParser(cpuinfo.Parser, .powerpc, &Target.powerpc.cpu.@"970",
            \\processor : 0
            \\cpu       : PPC970MP, altivec supported
            \\clock     : 1250.000000MHz
            \\revision  : 1.1 (pvr 0044 0101)
        );
        try testParser(cpuinfo.Parser, .powerpc64le, &Target.powerpc.cpu.pwr8,
            \\processor : 0
            \\cpu       : POWER8 (raw), altivec supported
            \\clock     : 2926.000000MHz
            \\revision  : 2.0 (pvr 004d 0200)
        );
    }

    pub fn detectNativeCpu(io: Io, arch: Target.Cpu.Arch) ?Target.Cpu {
        var file = Io.Dir.openFileAbsolute(io, "/proc/cpuinfo", .{}) catch return null;
        defer file.close(io);

        var buffer: [4096]u8 = undefined;
        var file_reader = file.reader(io, &buffer);

        var cpu = (cpuinfo.Parser.parse(arch, &file_reader.interface) catch null) orelse return null;

        cpu.features.populateDependencies(cpu.arch.allFeaturesList());

        return cpu;
    }
};

const riscv = struct {
    const cpuinfo = struct {
        const Impl = struct {
            model: ?*const Target.Cpu.Model = null,

            const cpu_names = .{
                .{ "andestech,ax45mp", &Target.riscv.cpu.andes_ax45 },
                .{ "sifive,bullet0", &Target.riscv.cpu.sifive_u74 },
                .{ "sifive,p550", &Target.riscv.cpu.sifive_p550 },
                .{ "sifive,u54", &Target.riscv.cpu.sifive_u54 },
                .{ "sifive,u54-mc", &Target.riscv.cpu.sifive_u54 },
                .{ "sifive,u7", &Target.riscv.cpu.sifive_u74 },
                .{ "sifive,u74", &Target.riscv.cpu.sifive_u74 },
                .{ "sifive,u74-mc", &Target.riscv.cpu.sifive_u74 },
                .{ "sifive,x280", &Target.riscv.cpu.sifive_x280 },
                .{ "spacemit,x60", &Target.riscv.cpu.spacemit_x60 },
                .{ "spacemit,x100", &Target.riscv.cpu.spacemit_x100 },
            };

            fn lineHook(self: *Impl, key: []const u8, value: []const u8) !bool {
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

            fn finalize(self: *const Impl, arch: Target.Cpu.Arch) ?Target.Cpu {
                const model = self.model orelse return null;
                return Target.Cpu{
                    .arch = arch,
                    .model = model,
                    .features = model.features,
                };
            }
        };

        const Parser = CpuinfoParser(Impl);
    };

    test cpuinfo {
        try testParser(cpuinfo.Parser, .riscv64, &Target.riscv.cpu.sifive_u74,
            \\processor : 0
            \\hart      : 1
            \\isa       : rv64imafdc
            \\mmu       : sv39
            \\isa-ext   :
            \\uarch     : sifive,u74-mc
        );
    }

    fn setFeature(cpu: *Target.Cpu, feature: Target.riscv.Feature, enabled: bool) void {
        const idx = @as(Target.Cpu.Feature.Set.Index, @backingInt(feature));

        if (enabled) cpu.features.addFeature(idx) else cpu.features.removeFeature(idx);
    }

    inline fn set(value: u64, mask: u64) bool {
        return (value & mask) == mask;
    }

    pub fn detectNativeCpuAndFeatures(io: Io, arch: Target.Cpu.Arch) ?Target.Cpu {
        var file = Io.Dir.openFileAbsolute(io, "/proc/cpuinfo", .{}) catch return null;
        defer file.close(io);

        var buffer: [4096]u8 = undefined;
        var file_reader = file.reader(io, &buffer);

        const maybe_cpu = cpuinfo.Parser.parse(arch, &file_reader.interface) catch null;

        const RISCV_HWPROBE = std.os.linux.RISCV_HWPROBE;

        var probes = [_]std.os.linux.riscv_hwprobe{
            .{ .key = RISCV_HWPROBE.KEY.BASE_BEHAVIOR, .value = 0 },
            .{ .key = RISCV_HWPROBE.KEY.IMA_EXT_0, .value = 0 },
            .{ .key = RISCV_HWPROBE.KEY.MISALIGNED_SCALAR_PERF, .value = 0 },
            .{ .key = RISCV_HWPROBE.KEY.MISALIGNED_VECTOR_PERF, .value = 0 },
            .{ .key = RISCV_HWPROBE.KEY.VENDOR_EXT_MIPS_0, .value = 0 },
            .{ .key = RISCV_HWPROBE.KEY.VENDOR_EXT_SIFIVE_0, .value = 0 },
            .{ .key = RISCV_HWPROBE.KEY.IMA_EXT_1, .value = 0 },
        };

        const rc = std.os.linux.sys_riscv_hwprobe(&probes, probes.len, 0, null, 0);
        if (std.os.linux.errno(rc) == .NOSYS) {
            // Even if SYS_riscv_hwprobe is unavailable, we should still return
            // the model if we managed to detect it.
            var cpu = maybe_cpu orelse return null;

            cpu.features.populateDependencies(cpu.arch.allFeaturesList());

            return cpu;
        }

        var cpu: Target.Cpu = maybe_cpu orelse cpu: {
            const model = Target.Cpu.Model.generic(arch);
            break :cpu .{
                .arch = arch,
                .model = model,
                .features = model.features,
            };
        };

        var ima_support = false;
        for (probes) |probe| {
            const value = probe.value;

            switch (probe.key) {
                -1 => continue, // The running kernel doesn't know this key.
                RISCV_HWPROBE.KEY.BASE_BEHAVIOR => {
                    ima_support = set(value, RISCV_HWPROBE.BASE_BEHAVIOR_IMA);
                    setFeature(&cpu, Target.riscv.Feature.i, ima_support);
                    setFeature(&cpu, Target.riscv.Feature.m, ima_support);
                    setFeature(&cpu, Target.riscv.Feature.a, ima_support);
                },
                RISCV_HWPROBE.KEY.IMA_EXT_0 => {
                    // https://bugzilla.kernel.org/show_bug.cgi?id=221874
                    const fd_support = set(value, RISCV_HWPROBE.IMA_EXT_0.IMA_FD);
                    setFeature(&cpu, .f, ima_support and fd_support);
                    setFeature(&cpu, .d, ima_support and fd_support);
                    setFeature(&cpu, .c, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.IMA_C));
                    setFeature(&cpu, .v, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.IMA_V));
                    setFeature(&cpu, .zba, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZBA));
                    setFeature(&cpu, .zbb, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZBB));
                    setFeature(&cpu, .zbs, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZBS));
                    setFeature(&cpu, .zicboz, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZICBOZ));
                    setFeature(&cpu, .zbc, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZBC));
                    setFeature(&cpu, .zbkb, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZBKB));
                    setFeature(&cpu, .zbkc, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZBKC));
                    setFeature(&cpu, .zbkx, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZBKX));
                    setFeature(&cpu, .zknd, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZKND));
                    setFeature(&cpu, .zkne, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZKNE));
                    setFeature(&cpu, .zknh, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZKNH));
                    setFeature(&cpu, .zksed, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZKSED));
                    setFeature(&cpu, .zksh, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZKSH));
                    setFeature(&cpu, .zkt, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZKT));
                    setFeature(&cpu, .zvbb, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVBB));
                    setFeature(&cpu, .zvbc, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVBC));
                    setFeature(&cpu, .zvkb, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVKB));
                    setFeature(&cpu, .zvkg, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVKG));
                    setFeature(&cpu, .zvkned, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVKNED));
                    setFeature(&cpu, .zvknha, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVKNHA));
                    setFeature(&cpu, .zvknhb, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVKNHB));
                    setFeature(&cpu, .zvksed, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVKSED));
                    setFeature(&cpu, .zvksh, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVKSH));
                    setFeature(&cpu, .zvkt, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVKT));
                    setFeature(&cpu, .zfh, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZFH));
                    setFeature(&cpu, .zfhmin, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZFHMIN));
                    setFeature(&cpu, .zihintntl, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZIHINTNTL));
                    setFeature(&cpu, .zvfh, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVFH));
                    setFeature(&cpu, .zvfhmin, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVFHMIN));
                    setFeature(&cpu, .zfa, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZFA));
                    setFeature(&cpu, .ztso, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZTSO));
                    setFeature(&cpu, .zacas, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZACAS));
                    setFeature(&cpu, .zicntr, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZICNTR));
                    setFeature(&cpu, .zicond, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZICOND));
                    setFeature(&cpu, .zihintpause, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZIHINTPAUSE));
                    setFeature(&cpu, .zihpm, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZIHPM));
                    setFeature(&cpu, .zve32x, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVE32X));
                    setFeature(&cpu, .zve32f, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVE32F));
                    setFeature(&cpu, .zve64x, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVE64X));
                    setFeature(&cpu, .zve64f, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVE64F));
                    setFeature(&cpu, .zve64d, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVE64D));
                    setFeature(&cpu, .zimop, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZIMOP));
                    setFeature(&cpu, .zca, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZCA));
                    setFeature(&cpu, .zcb, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZCB));
                    setFeature(&cpu, .zcd, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZCD));
                    setFeature(&cpu, .zcf, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZCF));
                    setFeature(&cpu, .zcmop, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZCMOP));
                    setFeature(&cpu, .zawrs, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZAWRS));
                    setFeature(&cpu, .supm, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_SUPM));
                    setFeature(&cpu, .zicntr, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZICNTR));
                    setFeature(&cpu, .zihpm, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZIHPM));
                    setFeature(&cpu, .zfbfmin, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZFBFMIN));
                    setFeature(&cpu, .zvfbfmin, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVFBFMIN));
                    setFeature(&cpu, .zvfbfwma, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZVFBFWMA));
                    setFeature(&cpu, .zicbom, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZICBOM));
                    setFeature(&cpu, .zaamo, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZAAMO));
                    setFeature(&cpu, .zalrsc, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZALRSC));
                    setFeature(&cpu, .zabha, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZABHA));
                    setFeature(&cpu, .zalasr, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZALASR));
                    setFeature(&cpu, .zicbop, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZICBOP));
                    setFeature(&cpu, .zilsd, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZILSD));
                    setFeature(&cpu, .zclsd, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZCLSD));
                    setFeature(&cpu, .experimental_zicfilp, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_0.EXT_ZICFILP));
                },
                RISCV_HWPROBE.KEY.MISALIGNED_SCALAR_PERF => {
                    setFeature(&cpu, .unaligned_scalar_mem, value == RISCV_HWPROBE.MISALIGNED_SCALAR.FAST);
                },
                RISCV_HWPROBE.KEY.MISALIGNED_VECTOR_PERF => {
                    setFeature(&cpu, .unaligned_vector_mem, value == RISCV_HWPROBE.MISALIGNED_VECTOR.FAST);
                },
                RISCV_HWPROBE.KEY.VENDOR_EXT_MIPS_0 => {
                    setFeature(&cpu, .xmipsexectl, ima_support and set(value, RISCV_HWPROBE.MIPS_VENDOR_EXT_XMIPSEXECTL));
                },
                RISCV_HWPROBE.KEY.VENDOR_EXT_SIFIVE_0 => {
                    setFeature(&cpu, .xsfvqmaccdod, ima_support and set(value, RISCV_HWPROBE.SIFIVE_VENDOR_EXT.XSFVQMACCDOD));
                    setFeature(&cpu, .xsfvqmaccqoq, ima_support and set(value, RISCV_HWPROBE.SIFIVE_VENDOR_EXT.XSFVQMACCQOQ));
                    setFeature(&cpu, .xsfvfnrclipxfqf, ima_support and set(value, RISCV_HWPROBE.SIFIVE_VENDOR_EXT.XSFVFNRCLIPXFQF));
                    setFeature(&cpu, .xsfvfwmaccqqq, ima_support and set(value, RISCV_HWPROBE.SIFIVE_VENDOR_EXT.XSFVFWMACCQQQ));
                },
                RISCV_HWPROBE.KEY.IMA_EXT_1 => {
                    setFeature(&cpu, .experimental_zicfiss, ima_support and set(value, RISCV_HWPROBE.IMA_EXT_1_EXT_ZICFISS));
                },
                else => unreachable,
            }
        }

        cpu.features.populateDependencies(cpu.arch.allFeaturesList());

        return cpu;
    }
};

const s390x = struct {
    const cpuinfo = struct {
        const Impl = struct {
            model: ?*const Target.Cpu.Model = null,

            const cpu_names = .{
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

            fn lineHook(self: *Impl, key: []const u8, value: []const u8) !bool {
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

            fn finalize(self: *const Impl, arch: Target.Cpu.Arch) ?Target.Cpu {
                const model = self.model orelse return null;
                return Target.Cpu{
                    .arch = arch,
                    .model = model,
                    .features = model.features,
                };
            }
        };

        const Parser = CpuinfoParser(Impl);
    };

    test cpuinfo {
        try testParser(cpuinfo.Parser, .s390x, &Target.s390x.cpu.z15,
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

    pub fn detectNativeCpu(io: Io, arch: Target.Cpu.Arch) ?Target.Cpu {
        var file = Io.Dir.openFileAbsolute(io, "/proc/cpuinfo", .{}) catch return null;
        defer file.close(io);

        var buffer: [4096]u8 = undefined;
        var file_reader = file.reader(io, &buffer);

        var cpu = (cpuinfo.Parser.parse(arch, &file_reader.interface) catch null) orelse return null;

        cpu.features.populateDependencies(cpu.arch.allFeaturesList());

        return cpu;
    }
};

const sparc = struct {
    const cpuinfo = struct {
        const Impl = struct {
            model: ?*const Target.Cpu.Model = null,

            const cpu_names = .{
                .{ "BlackBird", &Target.sparc.cpu.ultrasparc },
                .{ "Cheetah", &Target.sparc.cpu.ultrasparc3 },
                .{ "Hummingbird", &Target.sparc.cpu.ultrasparc },
                .{ "HyperSparc", &Target.sparc.cpu.hypersparc },
                .{ "Jaguar", &Target.sparc.cpu.ultrasparc3 },
                .{ "Jalapeno", &Target.sparc.cpu.ultrasparc3 },
                .{ "LEON", &Target.sparc.cpu.leon3 },
                .{ "MB86904", &Target.sparc.cpu.v8 },
                .{ "MB86907", &Target.sparc.cpu.v8 },
                .{ "MicroSparc II", &Target.sparc.cpu.v8 },
                .{ "MicroSparc", &Target.sparc.cpu.v8 },
                .{ "Panther", &Target.sparc.cpu.ultrasparc3 },
                .{ "Sabre", &Target.sparc.cpu.ultrasparc },
                .{ "Serrano", &Target.sparc.cpu.ultrasparc3 },
                .{ "SPARC-M6", &Target.sparc.cpu.niagara4 },
                .{ "SPARC-M7", &Target.sparc.cpu.niagara4 },
                .{ "SPARC-M8", &Target.sparc.cpu.niagara4 },
                .{ "SPARC-SN", &Target.sparc.cpu.niagara4 },
                .{ "SPARC64-X", &Target.sparc.cpu.ultrasparc3 },
                .{ "SpitFire", &Target.sparc.cpu.ultrasparc },
                .{ "SuperSparc", &Target.sparc.cpu.supersparc },
                .{ "UltraSparc T1", &Target.sparc.cpu.niagara },
                .{ "UltraSparc T2", &Target.sparc.cpu.niagara2 },
                .{ "UltraSparc T3", &Target.sparc.cpu.niagara3 },
                .{ "UltraSparc T4", &Target.sparc.cpu.niagara4 },
                .{ "UltraSparc T5", &Target.sparc.cpu.niagara4 },
            };

            fn lineHook(self: *Impl, key: []const u8, value: []const u8) !bool {
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

            fn finalize(self: *const Impl, arch: Target.Cpu.Arch) ?Target.Cpu {
                const model = self.model orelse return null;
                return Target.Cpu{
                    .arch = arch,
                    .model = model,
                    .features = model.features,
                };
            }
        };

        const Parser = CpuinfoParser(Impl);
    };

    test cpuinfo {
        try testParser(cpuinfo.Parser, .sparc64, &Target.sparc.cpu.niagara2,
            \\cpu             : UltraSparc T2 (Niagara2)
            \\fpu             : UltraSparc T2 integrated FPU
            \\pmu             : niagara2
            \\type            : sun4v
        );
    }

    pub fn detectNativeCpu(io: Io, arch: Target.Cpu.Arch) ?Target.Cpu {
        var file = Io.Dir.openFileAbsolute(io, "/proc/cpuinfo", .{}) catch return null;
        defer file.close(io);

        var buffer: [4096]u8 = undefined;
        var file_reader = file.reader(io, &buffer);

        var cpu = (cpuinfo.Parser.parse(arch, &file_reader.interface) catch null) orelse return null;

        cpu.features.populateDependencies(cpu.arch.allFeaturesList());

        return cpu;
    }
};

pub fn detectNativeCpuAndFeatures(io: Io) ?Target.Cpu {
    const current_arch = builtin.cpu.arch;
    return switch (current_arch) {
        .aarch64, .aarch64_be => aarch64.detectNativeCpuAndFeatures(current_arch),
        .arm, .armeb, .thumb, .thumbeb => arm.detectNativeCpu(io, current_arch),
        .csky => csky.detectNativeCpu(io, current_arch),
        .m68k => m68k.detectNativeCpu(io, current_arch),
        .mips, .mipsel, .mips64, .mips64el => mips.detectNativeCpu(io, current_arch),
        .powerpc, .powerpcle, .powerpc64, .powerpc64le => powerpc.detectNativeCpu(io, current_arch),
        .riscv64, .riscv32 => riscv.detectNativeCpuAndFeatures(io, current_arch),
        .s390x => s390x.detectNativeCpu(io, current_arch),
        .sparc, .sparc64 => sparc.detectNativeCpu(io, current_arch),
        else => null,
    };
}

test {
    _ = aarch64;
    _ = arm;
    _ = powerpc;
    _ = riscv;
    _ = s390x;
    _ = sparc;
}
