const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const mem = std.mem;
const OptimizeMode = std.builtin.OptimizeMode;
const Step = std.Build.Step;

// Cases
const error_traces = @import("error_traces.zig");
const stack_traces = @import("stack_traces.zig");
const llvm_ir = @import("llvm_ir.zig");
const libc = @import("libc.zig");

// Implementations
pub const ErrorTracesContext = @import("src/ErrorTrace.zig");
pub const StackTracesContext = @import("src/StackTrace.zig");
pub const DebuggerContext = @import("src/Debugger.zig");
pub const LlvmIrContext = @import("src/LlvmIr.zig");
pub const LibcContext = @import("src/Libc.zig");

const ModuleTestTarget = struct {
    linkage: ?std.builtin.LinkMode = null,
    target: std.Target.Query = .{},
    optimize_mode: std.builtin.OptimizeMode = .Debug,
    link_libc: ?bool = null,
    single_threaded: ?bool = null,
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    pic: ?bool = null,
    strip: ?bool = null,
    function_sections: ?bool = null,
    data_sections: ?bool = null,
    skip_modules: []const []const u8 = &.{},

    // This is intended for targets that, for any reason, shouldn't be run as part of a normal test
    // invocation. This could be because of a slow backend, requiring a newer LLVM version, being
    // too niche, etc.
    extra_target: bool = false,
};

const module_test_targets = blk: {
    // getBaselineCpuFeatures calls populateDependencies which has a O(N ^ 2) algorithm
    // (where N is roughly 160, which technically makes it O(1), but it adds up to a
    // lot of branches)
    @setEvalBranchQuota(80_000);
    break :blk [_]ModuleTestTarget{
        // Native Targets

        .{}, // 0 index must be all defaults
        .{
            .link_libc = true,
        },
        .{
            .single_threaded = true,
        },

        .{
            .optimize_mode = .ReleaseFast,
        },
        .{
            .link_libc = true,
            .optimize_mode = .ReleaseFast,
        },
        .{
            .optimize_mode = .ReleaseFast,
            .single_threaded = true,
        },

        .{
            .optimize_mode = .ReleaseSafe,
        },
        .{
            .link_libc = true,
            .optimize_mode = .ReleaseSafe,
        },
        .{
            .optimize_mode = .ReleaseSafe,
            .single_threaded = true,
        },

        .{
            .optimize_mode = .ReleaseSmall,
        },
        .{
            .link_libc = true,
            .optimize_mode = .ReleaseSmall,
        },
        .{
            .optimize_mode = .ReleaseSmall,
            .single_threaded = true,
        },

        .{
            .target = .{
                .ofmt = .c,
            },
            .link_libc = true,
        },

        // FreeBSD Targets

        .{
            .target = .{
                .cpu_arch = .aarch64,
                .os_tag = .freebsd,
                .abi = .none,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .arm,
                .os_tag = .freebsd,
                .abi = .eabihf,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .powerpc64,
                .os_tag = .freebsd,
                .abi = .none,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .powerpc64le,
                .os_tag = .freebsd,
                .abi = .none,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .riscv64,
                .os_tag = .freebsd,
                .abi = .none,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .freebsd,
                .abi = .none,
            },
            .link_libc = true,
        },

        // Linux Targets

        .{
            .target = .{
                .cpu_arch = .aarch64,
                .os_tag = .linux,
                .abi = .none,
            },
        },
        .{
            .target = .{
                .cpu_arch = .aarch64,
                .os_tag = .linux,
                .abi = .musl,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .aarch64,
                .os_tag = .linux,
                .abi = .musl,
            },
            .linkage = .dynamic,
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .aarch64,
                .os_tag = .linux,
                .abi = .gnu,
            },
            .link_libc = true,
        },

        // Disabled due to https://codeberg.org/ziglang/zig/pulls/30232#issuecomment-9203351
        //.{
        //    .target = .{
        //        .cpu_arch = .aarch64,
        //        .os_tag = .linux,
        //        .abi = .none,
        //    },
        //    .use_llvm = false,
        //    .use_lld = false,
        //    .optimize_mode = .ReleaseFast,
        //    .strip = true,
        //    .skip_modules = &.{"std"}, // TODO get these passing
        //},
        //.{
        //    .target = .{
        //        .cpu_arch = .aarch64,
        //        .cpu_model = .{ .explicit = &std.Target.aarch64.cpu.neoverse_n1 },
        //        .os_tag = .linux,
        //        .abi = .none,
        //    },
        //    .use_llvm = false,
        //    .use_lld = false,
        //    .optimize_mode = .ReleaseFast,
        //    .strip = true,
        //    .skip_modules = &.{"std"}, // TODO get these passing
        //},

        .{
            .target = .{
                .cpu_arch = .aarch64_be,
                .os_tag = .linux,
                .abi = .none,
            },
        },
        .{
            .target = .{
                .cpu_arch = .aarch64_be,
                .os_tag = .linux,
                .abi = .musl,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .aarch64_be,
                .os_tag = .linux,
                .abi = .musl,
            },
            .linkage = .dynamic,
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .aarch64_be,
                .os_tag = .linux,
                .abi = .gnu,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .arm,
                .os_tag = .linux,
                .abi = .eabi,
            },
        },
        .{
            .target = .{
                .cpu_arch = .arm,
                .os_tag = .linux,
                .abi = .eabihf,
            },
        },
        .{
            .target = .{
                .cpu_arch = .arm,
                .os_tag = .linux,
                .abi = .musleabi,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .arm,
                .os_tag = .linux,
                .abi = .musleabi,
            },
            .linkage = .dynamic,
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .arm,
                .os_tag = .linux,
                .abi = .musleabihf,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .arm,
                .os_tag = .linux,
                .abi = .musleabihf,
            },
            .linkage = .dynamic,
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .arm,
                .os_tag = .linux,
                .abi = .gnueabi,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .arm,
                .os_tag = .linux,
                .abi = .gnueabihf,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .armeb,
                .os_tag = .linux,
                .abi = .eabi,
            },
        },
        .{
            .target = .{
                .cpu_arch = .armeb,
                .os_tag = .linux,
                .abi = .eabihf,
            },
        },
        .{
            .target = .{
                .cpu_arch = .armeb,
                .os_tag = .linux,
                .abi = .musleabi,
            },
            .link_libc = true,
        },
        // Crashes in weird ways when applying relocations.
        // .{
        //     .target = .{
        //         .cpu_arch = .armeb,
        //         .os_tag = .linux,
        //         .abi = .musleabi,
        //     },
        //     .linkage = .dynamic,
        //     .link_libc = true,
        //     .extra_target = true,
        // },
        .{
            .target = .{
                .cpu_arch = .armeb,
                .os_tag = .linux,
                .abi = .musleabihf,
            },
            .link_libc = true,
        },
        // Crashes in weird ways when applying relocations.
        // .{
        //     .target = .{
        //         .cpu_arch = .armeb,
        //         .os_tag = .linux,
        //         .abi = .musleabihf,
        //     },
        //     .linkage = .dynamic,
        //     .link_libc = true,
        //     .extra_target = true,
        // },
        .{
            .target = .{
                .cpu_arch = .armeb,
                .os_tag = .linux,
                .abi = .gnueabi,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .armeb,
                .os_tag = .linux,
                .abi = .gnueabihf,
            },
            .link_libc = true,
        },

        // Similar to Thumb, we need long calls on Hexagon due to relocation range issues.
        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "hexagon-linux-none",
                .cpu_features = "baseline+long_calls",
            }) catch unreachable,
        },
        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "hexagon-linux-musl",
                .cpu_features = "baseline+long_calls",
            }) catch unreachable,
            .link_libc = true,
        },
        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "hexagon-linux-musl",
                .cpu_features = "baseline+long_calls",
            }) catch unreachable,
            .linkage = .dynamic,
            .link_libc = true,
            .extra_target = true,
        },

        .{
            .target = .{
                .cpu_arch = .loongarch32,
                .os_tag = .linux,
                .abi = .none,
            },
        },

        .{
            .target = .{
                .cpu_arch = .loongarch64,
                .os_tag = .linux,
                .abi = .none,
            },
        },
        .{
            .target = .{
                .cpu_arch = .loongarch64,
                .os_tag = .linux,
                .abi = .musl,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .loongarch64,
                .os_tag = .linux,
                .abi = .musl,
            },
            .linkage = .dynamic,
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .loongarch64,
                .os_tag = .linux,
                .abi = .muslsf,
            },
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .loongarch64,
                .os_tag = .linux,
                .abi = .muslsf,
            },
            .linkage = .dynamic,
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .loongarch64,
                .os_tag = .linux,
                .abi = .gnu,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .loongarch64,
                .os_tag = .linux,
                .abi = .gnusf,
            },
            .link_libc = true,
            .extra_target = true,
        },

        .{
            .target = .{
                .cpu_arch = .mips,
                .os_tag = .linux,
                .abi = .eabi,
            },
        },
        .{
            .target = .{
                .cpu_arch = .mips,
                .os_tag = .linux,
                .abi = .eabihf,
            },
        },
        .{
            .target = .{
                .cpu_arch = .mips,
                .os_tag = .linux,
                .abi = .musleabi,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .mips,
                .os_tag = .linux,
                .abi = .musleabi,
            },
            .linkage = .dynamic,
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .mips,
                .os_tag = .linux,
                .abi = .musleabihf,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .mips,
                .os_tag = .linux,
                .abi = .musleabihf,
            },
            .linkage = .dynamic,
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .mips,
                .os_tag = .linux,
                .abi = .gnueabi,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .mips,
                .os_tag = .linux,
                .abi = .gnueabihf,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .mipsel,
                .os_tag = .linux,
                .abi = .eabi,
            },
        },
        .{
            .target = .{
                .cpu_arch = .mipsel,
                .os_tag = .linux,
                .abi = .eabihf,
            },
        },
        .{
            .target = .{
                .cpu_arch = .mipsel,
                .os_tag = .linux,
                .abi = .musleabi,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .mipsel,
                .os_tag = .linux,
                .abi = .musleabi,
            },
            .linkage = .dynamic,
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .mipsel,
                .os_tag = .linux,
                .abi = .musleabihf,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .mipsel,
                .os_tag = .linux,
                .abi = .musleabihf,
            },
            .linkage = .dynamic,
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .mipsel,
                .os_tag = .linux,
                .abi = .gnueabi,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .mipsel,
                .os_tag = .linux,
                .abi = .gnueabihf,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .mips64,
                .os_tag = .linux,
                .abi = .none,
            },
        },
        .{
            .target = .{
                .cpu_arch = .mips64,
                .os_tag = .linux,
                .abi = .abin32,
            },
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .mips64,
                .os_tag = .linux,
                .abi = .muslabi64,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .mips64,
                .os_tag = .linux,
                .abi = .muslabi64,
            },
            .linkage = .dynamic,
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .mips64,
                .os_tag = .linux,
                .abi = .muslabin32,
            },
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .mips64,
                .os_tag = .linux,
                .abi = .muslabin32,
            },
            .linkage = .dynamic,
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .mips64,
                .os_tag = .linux,
                .abi = .gnuabi64,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .mips64,
                .os_tag = .linux,
                .abi = .gnuabin32,
            },
            .link_libc = true,
            .extra_target = true,
        },

        .{
            .target = .{
                .cpu_arch = .mips64el,
                .os_tag = .linux,
                .abi = .none,
            },
        },
        .{
            .target = .{
                .cpu_arch = .mips64el,
                .os_tag = .linux,
                .abi = .abin32,
            },
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .mips64el,
                .os_tag = .linux,
                .abi = .muslabi64,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .mips64el,
                .os_tag = .linux,
                .abi = .muslabi64,
            },
            .linkage = .dynamic,
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .mips64el,
                .os_tag = .linux,
                .abi = .muslabin32,
            },
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .mips64el,
                .os_tag = .linux,
                .abi = .muslabin32,
            },
            .linkage = .dynamic,
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .mips64el,
                .os_tag = .linux,
                .abi = .gnuabi64,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .mips64el,
                .os_tag = .linux,
                .abi = .gnuabin32,
            },
            .link_libc = true,
            .extra_target = true,
        },

        .{
            .target = .{
                .cpu_arch = .powerpc,
                .os_tag = .linux,
                .abi = .eabi,
            },
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .powerpc,
                .os_tag = .linux,
                .abi = .eabihf,
            },
        },
        .{
            .target = .{
                .cpu_arch = .powerpc,
                .os_tag = .linux,
                .abi = .musleabi,
            },
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .powerpc,
                .os_tag = .linux,
                .abi = .musleabi,
            },
            .linkage = .dynamic,
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .powerpc,
                .os_tag = .linux,
                .abi = .musleabihf,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .powerpc,
                .os_tag = .linux,
                .abi = .musleabihf,
            },
            .linkage = .dynamic,
            .link_libc = true,
            // https://github.com/ziglang/zig/issues/2256
            .skip_modules = &.{"std"},
            .extra_target = true,
        },

        .{
            .target = .{
                .cpu_arch = .powerpc64,
                .os_tag = .linux,
                .abi = .none,
            },
        },
        .{
            .target = .{
                .cpu_arch = .powerpc64,
                .os_tag = .linux,
                .abi = .musl,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .powerpc64,
                .os_tag = .linux,
                .abi = .musl,
            },
            .linkage = .dynamic,
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .powerpc64le,
                .os_tag = .linux,
                .abi = .none,
            },
        },
        .{
            .target = .{
                .cpu_arch = .powerpc64le,
                .os_tag = .linux,
                .abi = .musl,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .powerpc64le,
                .os_tag = .linux,
                .abi = .musl,
            },
            .linkage = .dynamic,
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .powerpc64le,
                .os_tag = .linux,
                .abi = .gnu,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .riscv32,
                .os_tag = .linux,
                .abi = .none,
            },
        },
        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "riscv32-linux-none",
                .cpu_features = "baseline-d-f",
            }) catch unreachable,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .riscv32,
                .os_tag = .linux,
                .abi = .musl,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .riscv32,
                .os_tag = .linux,
                .abi = .musl,
            },
            .linkage = .dynamic,
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "riscv32-linux-musl",
                .cpu_features = "baseline-d-f",
            }) catch unreachable,
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .riscv32,
                .os_tag = .linux,
                .abi = .gnu,
            },
            .link_libc = true,
        },

        // TODO implement codegen airFieldParentPtr
        // TODO implement airMemmove for riscv64
        //.{
        //    .target = std.Target.Query.parse(.{
        //        .arch_os_abi = "riscv64-linux-none",
        //        .cpu_features = "baseline+v+zbb",
        //    }) catch unreachable,
        //    .use_llvm = false,
        //    .use_lld = false,
        //},
        .{
            .target = .{
                .cpu_arch = .riscv64,
                .os_tag = .linux,
                .abi = .none,
            },
        },
        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "riscv64-linux-none",
                .cpu_features = "baseline-d-f",
            }) catch unreachable,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .riscv64,
                .os_tag = .linux,
                .abi = .musl,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .riscv64,
                .os_tag = .linux,
                .abi = .musl,
            },
            .linkage = .dynamic,
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "riscv64-linux-musl",
                .cpu_features = "baseline-d-f",
            }) catch unreachable,
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .riscv64,
                .os_tag = .linux,
                .abi = .gnu,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .s390x,
                .os_tag = .linux,
                .abi = .none,
            },
        },
        .{
            .target = .{
                .cpu_arch = .s390x,
                .os_tag = .linux,
                .abi = .musl,
            },
            .link_libc = true,
        },
        // Currently hangs in qemu-s390x.
        // .{
        //     .target = .{
        //         .cpu_arch = .s390x,
        //         .os_tag = .linux,
        //         .abi = .musl,
        //     },
        //     .linkage = .dynamic,
        //     .link_libc = true,
        //     .extra_target = true,
        // },
        .{
            .target = .{
                .cpu_arch = .s390x,
                .os_tag = .linux,
                .abi = .gnu,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .sparc64,
                .os_tag = .linux,
                .abi = .none,
            },
        },
        // SPARC linking support is currently incomplete.
        // .{
        //     .target = .{
        //         .cpu_arch = .sparc64,
        //         .os_tag = .linux,
        //         .abi = .gnu,
        //     },
        //     .link_libc = true,
        // },

        // Calls are normally lowered to branch instructions that only support +/- 16 MB range when
        // targeting Thumb. This easily becomes insufficient for our test binaries, so use long
        // calls to avoid out-of-range relocations.
        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "thumb-linux-eabi",
                .cpu_features = "baseline+long_calls",
            }) catch unreachable,
            .pic = false, // Long calls don't work with PIC.
        },
        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "thumb-linux-eabihf",
                .cpu_features = "baseline+long_calls",
            }) catch unreachable,
            .pic = false, // Long calls don't work with PIC.
        },
        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "thumb-linux-musleabi",
                .cpu_features = "baseline+long_calls",
            }) catch unreachable,
            .link_libc = true,
            .pic = false, // Long calls don't work with PIC.
        },
        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "thumb-linux-musleabihf",
                .cpu_features = "baseline+long_calls",
            }) catch unreachable,
            .link_libc = true,
            .pic = false, // Long calls don't work with PIC.
        },

        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "thumbeb-linux-eabi",
                .cpu_features = "baseline+long_calls",
            }) catch unreachable,
            .pic = false, // Long calls don't work with PIC.
        },
        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "thumbeb-linux-eabihf",
                .cpu_features = "baseline+long_calls",
            }) catch unreachable,
            .pic = false, // Long calls don't work with PIC.
        },
        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "thumbeb-linux-musleabi",
                .cpu_features = "baseline+long_calls",
            }) catch unreachable,
            .link_libc = true,
            .pic = false, // Long calls don't work with PIC.
        },
        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "thumbeb-linux-musleabihf",
                .cpu_features = "baseline+long_calls",
            }) catch unreachable,
            .link_libc = true,
            .pic = false, // Long calls don't work with PIC.
        },

        .{
            .target = .{
                .cpu_arch = .x86,
                .os_tag = .linux,
                .abi = .none,
            },
        },
        .{
            .target = .{
                .cpu_arch = .x86,
                .os_tag = .linux,
                .abi = .musl,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .x86,
                .os_tag = .linux,
                .abi = .musl,
            },
            .linkage = .dynamic,
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .x86,
                .os_tag = .linux,
                .abi = .gnu,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
                .abi = .none,
            },
        },
        .{
            .target = .{
                .cpu_arch = .x86_64,
                .cpu_model = .{ .explicit = &std.Target.x86.cpu.x86_64_v2 },
                .os_tag = .linux,
                .abi = .none,
            },
            .pic = true,
        },
        .{
            .target = .{
                .cpu_arch = .x86_64,
                .cpu_model = .{ .explicit = &std.Target.x86.cpu.x86_64_v3 },
                .os_tag = .linux,
                .abi = .none,
            },
            .strip = true,
        },
        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
                .abi = .none,
            },
            .use_llvm = true,
            .use_lld = true,
        },
        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
                .abi = .x32,
            },
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
                .abi = .musl,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
                .abi = .musl,
            },
            .linkage = .dynamic,
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
                .abi = .musl,
            },
            .link_libc = true,
            .use_llvm = true,
            .use_lld = false,
        },
        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
                .abi = .muslx32,
            },
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
                .abi = .muslx32,
            },
            .linkage = .dynamic,
            .link_libc = true,
            .extra_target = true,
        },
        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
                .abi = .gnu,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
                .abi = .gnux32,
            },
            .link_libc = true,
            .extra_target = true,
        },

        // Darwin Targets

        .{
            .target = .{
                .cpu_arch = .aarch64,
                .os_tag = .maccatalyst,
                .abi = .none,
            },
        },

        .{
            .target = .{
                .cpu_arch = .aarch64,
                .os_tag = .macos,
                .abi = .none,
            },
        },

        // Disabled due to https://codeberg.org/ziglang/zig/pulls/30232#issuecomment-9203351
        //.{
        //    .target = .{
        //        .cpu_arch = .aarch64,
        //        .os_tag = .macos,
        //        .abi = .none,
        //    },
        //    .use_llvm = false,
        //    .use_lld = false,
        //    .optimize_mode = .ReleaseFast,
        //    .strip = true,
        //},

        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .maccatalyst,
                .abi = .none,
            },
        },

        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .macos,
                .abi = .none,
            },
            .use_llvm = false,
        },
        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .macos,
                .abi = .none,
            },
        },

        // NetBSD Targets

        .{
            .target = .{
                .cpu_arch = .aarch64,
                .os_tag = .netbsd,
                .abi = .none,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .aarch64_be,
                .os_tag = .netbsd,
                .abi = .none,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .arm,
                .os_tag = .netbsd,
                .abi = .eabi,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .arm,
                .os_tag = .netbsd,
                .abi = .eabihf,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .armeb,
                .os_tag = .netbsd,
                .abi = .eabi,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .armeb,
                .os_tag = .netbsd,
                .abi = .eabihf,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .mips,
                .os_tag = .netbsd,
                .abi = .eabi,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .mips,
                .os_tag = .netbsd,
                .abi = .eabihf,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .mipsel,
                .os_tag = .netbsd,
                .abi = .eabi,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .mipsel,
                .os_tag = .netbsd,
                .abi = .eabihf,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .powerpc,
                .os_tag = .netbsd,
                .abi = .eabihf,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .riscv32,
                .os_tag = .netbsd,
                .abi = .none,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .riscv64,
                .os_tag = .netbsd,
                .abi = .none,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .x86,
                .os_tag = .netbsd,
                .abi = .none,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .netbsd,
                .abi = .none,
            },
            .link_libc = true,
        },

        // OpenBSD Targets

        .{
            .target = .{
                .cpu_arch = .aarch64,
                .os_tag = .openbsd,
                .abi = .none,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .arm,
                .os_tag = .openbsd,
                .abi = .eabi,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .mips64,
                .os_tag = .openbsd,
                .abi = .none,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .mips64el,
                .os_tag = .openbsd,
                .abi = .none,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .powerpc,
                .os_tag = .openbsd,
                .abi = .eabihf,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .powerpc64,
                .os_tag = .openbsd,
                .abi = .none,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .riscv64,
                .os_tag = .openbsd,
                .abi = .none,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .x86,
                .os_tag = .openbsd,
                .abi = .none,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .openbsd,
                .abi = .none,
            },
            .link_libc = true,
        },

        // SPIR-V Targets

        // Disabled due to no active maintainer (feel free to fix the failures
        // and then re-enable at any time). The failures occur due to changing AIR
        // from the frontend, and backend being incomplete.
        //.{
        //    .target = std.Target.Query.parse(.{
        //        .arch_os_abi = "spirv64-vulkan",
        //        .cpu_features = "vulkan_v1_2+float16+float64",
        //    }) catch unreachable,
        //    .use_llvm = false,
        //    .use_lld = false,
        //},

        // WASI Targets

        .{
            .target = .{
                .cpu_arch = .wasm32,
                .os_tag = .wasi,
                .abi = .none,
            },
            .skip_modules = &.{ "compiler-rt", "std" },
            .use_llvm = false,
            .use_lld = false,
        },
        .{
            .target = .{
                .cpu_arch = .wasm32,
                .os_tag = .wasi,
                .abi = .none,
            },
        },
        .{
            .target = .{
                .cpu_arch = .wasm32,
                .os_tag = .wasi,
                .abi = .musl,
            },
            .link_libc = true,
        },

        // Windows Targets

        .{
            .target = .{
                .cpu_arch = .aarch64,
                .os_tag = .windows,
                .abi = .msvc,
            },
        },
        .{
            .target = .{
                .cpu_arch = .aarch64,
                .os_tag = .windows,
                .abi = .msvc,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .aarch64,
                .os_tag = .windows,
                .abi = .gnu,
            },
        },
        .{
            .target = .{
                .cpu_arch = .aarch64,
                .os_tag = .windows,
                .abi = .gnu,
            },
            .link_libc = true,
        },

        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "thumb-windows-msvc",
                .cpu_features = "baseline+long_calls",
            }) catch unreachable,
            .pic = false, // Long calls don't work with PIC.
            .function_sections = true,
            .data_sections = true,
        },
        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "thumb-windows-msvc",
                .cpu_features = "baseline+long_calls",
            }) catch unreachable,
            .link_libc = true,
            .pic = false, // Long calls don't work with PIC.
            .function_sections = true,
            .data_sections = true,
        },
        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "thumb-windows-gnu",
                .cpu_features = "baseline+long_calls",
            }) catch unreachable,
            .pic = false, // Long calls don't work with PIC.
            .function_sections = true,
            .data_sections = true,
        },
        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "thumb-windows-gnu",
                .cpu_features = "baseline+long_calls",
            }) catch unreachable,
            .link_libc = true,
            .pic = false, // Long calls don't work with PIC.
            .function_sections = true,
            .data_sections = true,
        },

        .{
            .target = .{
                .cpu_arch = .x86,
                .os_tag = .windows,
                .abi = .msvc,
            },
        },
        .{
            .target = .{
                .cpu_arch = .x86,
                .os_tag = .windows,
                .abi = .msvc,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .x86,
                .os_tag = .windows,
                .abi = .gnu,
            },
        },
        .{
            .target = .{
                .cpu_arch = .x86,
                .os_tag = .windows,
                .abi = .gnu,
            },
            .link_libc = true,
        },

        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .windows,
                .abi = .msvc,
            },
            .use_llvm = false,
            .use_lld = false,
            // https://codeberg.org/ziglang/zig/issues/35537
            .skip_modules = &.{"behavior"},
        },
        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .windows,
                .abi = .msvc,
            },
        },
        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .windows,
                .abi = .msvc,
            },
            .link_libc = true,
        },
        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .windows,
                .abi = .gnu,
            },
            .use_llvm = false,
            .use_lld = false,
            // https://codeberg.org/ziglang/zig/issues/35537
            .skip_modules = &.{"behavior"},
        },
        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .windows,
                .abi = .gnu,
            },
        },
        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .windows,
                .abi = .gnu,
            },
            .link_libc = true,
        },
    };
};

const CAbiTarget = struct {
    target: std.Target.Query = .{},
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    pic: ?bool = null,
    strip: ?bool = null,
    c_defines: []const []const u8 = &.{},
};

const c_abi_targets = blk: {
    @setEvalBranchQuota(30000);
    break :blk [_]CAbiTarget{
        // Native Targets

        .{
            .use_llvm = true,
        },

        // Linux Targets

        .{
            .target = .{
                .cpu_arch = .aarch64,
                .os_tag = .linux,
                .abi = .musl,
            },
        },

        .{
            .target = .{
                .cpu_arch = .aarch64_be,
                .os_tag = .linux,
                .abi = .musl,
            },
        },

        .{
            .target = .{
                .cpu_arch = .arm,
                .os_tag = .linux,
                .abi = .musleabi,
            },
        },
        .{
            .target = .{
                .cpu_arch = .arm,
                .os_tag = .linux,
                .abi = .musleabihf,
            },
        },

        .{
            .target = .{
                .cpu_arch = .armeb,
                .os_tag = .linux,
                .abi = .musleabi,
            },
        },
        .{
            .target = .{
                .cpu_arch = .armeb,
                .os_tag = .linux,
                .abi = .musleabihf,
            },
        },

        .{
            .target = .{
                .cpu_arch = .hexagon,
                .os_tag = .linux,
                .abi = .musl,
            },
        },

        .{
            .target = .{
                .cpu_arch = .loongarch64,
                .os_tag = .linux,
                .abi = .musl,
            },
        },
        .{
            .target = .{
                .cpu_arch = .loongarch64,
                .os_tag = .linux,
                .abi = .muslsf,
            },
        },

        .{
            .target = .{
                .cpu_arch = .mips,
                .os_tag = .linux,
                .abi = .musleabi,
            },
        },
        .{
            .target = .{
                .cpu_arch = .mips,
                .os_tag = .linux,
                .abi = .musleabihf,
            },
        },

        .{
            .target = .{
                .cpu_arch = .mipsel,
                .os_tag = .linux,
                .abi = .musleabi,
            },
        },
        .{
            .target = .{
                .cpu_arch = .mipsel,
                .os_tag = .linux,
                .abi = .musleabihf,
            },
        },

        .{
            .target = .{
                .cpu_arch = .mips64,
                .os_tag = .linux,
                .abi = .muslabi64,
            },
        },
        .{
            .target = .{
                .cpu_arch = .mips64,
                .os_tag = .linux,
                .abi = .muslabin32,
            },
        },

        .{
            .target = .{
                .cpu_arch = .mips64el,
                .os_tag = .linux,
                .abi = .muslabi64,
            },
        },
        .{
            .target = .{
                .cpu_arch = .mips64el,
                .os_tag = .linux,
                .abi = .muslabin32,
            },
        },

        .{
            .target = .{
                .cpu_arch = .powerpc,
                .os_tag = .linux,
                .abi = .musleabi,
            },
        },
        .{
            .target = .{
                .cpu_arch = .powerpc,
                .os_tag = .linux,
                .abi = .musleabihf,
            },
        },

        .{
            .target = .{
                .cpu_arch = .powerpc64,
                .os_tag = .linux,
                .abi = .musl,
            },
        },
        .{
            .target = .{
                .cpu_arch = .powerpc64le,
                .os_tag = .linux,
                .abi = .musl,
            },
        },

        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "riscv32-linux-musl",
                .cpu_features = "baseline-d-f",
            }) catch unreachable,
        },
        .{
            .target = .{
                .cpu_arch = .riscv32,
                .os_tag = .linux,
                .abi = .musl,
            },
        },

        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "riscv64-linux-musl",
                .cpu_features = "baseline-d-f",
            }) catch unreachable,
        },
        .{
            .target = .{
                .cpu_arch = .riscv64,
                .os_tag = .linux,
                .abi = .musl,
            },
        },

        .{
            .target = .{
                .cpu_arch = .s390x,
                .os_tag = .linux,
                .abi = .musl,
            },
        },

        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "thumb-linux-musleabi",
                .cpu_features = "baseline+long_calls",
            }) catch unreachable,
            .pic = false, // Long calls don't work with PIC.
        },
        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "thumb-linux-musleabihf",
                .cpu_features = "baseline+long_calls",
            }) catch unreachable,
            .pic = false, // Long calls don't work with PIC.
        },

        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "thumbeb-linux-musleabi",
                .cpu_features = "baseline+long_calls",
            }) catch unreachable,
            .pic = false, // Long calls don't work with PIC.
        },
        .{
            .target = std.Target.Query.parse(.{
                .arch_os_abi = "thumbeb-linux-musleabihf",
                .cpu_features = "baseline+long_calls",
            }) catch unreachable,
            .pic = false, // Long calls don't work with PIC.
        },

        .{
            .target = .{
                .cpu_arch = .x86,
                .os_tag = .linux,
                .abi = .musl,
            },
        },

        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
                .abi = .musl,
            },
            .use_llvm = false,
            .c_defines = &.{"ZIG_BACKEND_STAGE2_X86_64"},
        },
        .{
            .target = .{
                .cpu_arch = .x86_64,
                .cpu_model = .{ .explicit = &std.Target.x86.cpu.x86_64_v2 },
                .os_tag = .linux,
                .abi = .musl,
            },
            .use_llvm = false,
            .strip = true,
            .c_defines = &.{"ZIG_BACKEND_STAGE2_X86_64"},
        },
        .{
            .target = .{
                .cpu_arch = .x86_64,
                .cpu_model = .{ .explicit = &std.Target.x86.cpu.x86_64_v3 },
                .os_tag = .linux,
                .abi = .musl,
            },
            .use_llvm = false,
            .pic = true,
            .c_defines = &.{"ZIG_BACKEND_STAGE2_X86_64"},
        },
        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
                .abi = .musl,
            },
            .use_llvm = true,
        },
        // .{
        //     .target = .{
        //         .cpu_arch = .x86_64,
        //         .os_tag = .linux,
        //         .abi = .muslx32,
        //     },
        // },

        // WASI Targets

        .{
            .target = .{
                .cpu_arch = .wasm32,
                .os_tag = .wasi,
                .abi = .musl,
            },
        },

        // Windows Targets

        .{
            .target = .{
                .cpu_arch = .x86,
                .os_tag = .windows,
                .abi = .gnu,
            },
        },
        .{
            .target = .{
                .cpu_arch = .x86_64,
                .os_tag = .windows,
                .abi = .gnu,
            },
        },
    };
};

/// Unlike `test_targets` and `c_abi_targets`, these targets are just simple strings which we pass
/// directly to `incr-check`. They include the target triple and the compiler backend.
///
/// If only one specific test is failing on a target, instead of entirely disabling the target here,
/// you can skip the target for that specific test only by adding a line like this to the manifest:
///   #skip_target=x86_64-linux-selfhosted
const incremental_targets: []const []const u8 = &.{
    // Avoid adding more CBE or LLVM targets without good reason: they're a lot slower than others
    // to run due to the output (C source code or LLVM IR) being built non-incrementally (by Clang
    // or LLVM). We just have a couple here to make sure that it works.
    "x86_64-linux-cbe",
    "x86_64-linux-llvm",

    "x86_64-linux-selfhosted",
    // https://codeberg.org/ziglang/zig/issues/31773
    //"x86_64-windows-selfhosted",
    // https://codeberg.org/ziglang/zig/issues/31810
    //"wasm32-wasi-selfhosted",
};

fn compatible32bitArch(host: *const std.Target) ?std.Target.Cpu.Arch {
    return switch (host.os.tag) {
        .freebsd => switch (host.cpu.arch) {
            .aarch64 => .arm,
            .powerpc64 => .powerpc,
            else => null,
        },
        .illumos => switch (host.cpu.arch) {
            .x86_64 => .x86,
            else => null,
        },
        .linux => switch (host.cpu.arch) {
            .aarch64 => .arm,
            .aarch64_be => .armeb,
            .mips64 => .mips,
            .mips64el => .mipsel,
            .powerpc64 => .powerpc,
            .sparc64 => .sparc,
            .x86_64 => .x86,
            else => null,
        },
        .netbsd => switch (host.cpu.arch) {
            .riscv64 => .riscv32,
            .sparc64 => .sparc,
            .x86_64 => .x86,
            else => null,
        },
        .windows => switch (host.cpu.arch) {
            .x86_64 => .x86,
            else => null,
        },
        else => null,
    };
}

pub fn isNative(actual_target: *const std.Build.ResolvedTarget, host: *const std.Target) bool {
    if (actual_target.query.isNative()) return true;
    const actual = &actual_target.result;

    if (actual.cpu.arch != host.cpu.arch and
        actual.cpu.arch != compatible32bitArch(host))
    {
        return false;
    }

    if (actual.os.tag != host.os.tag)
        return false;

    // Remove features that don't actually affect compatibility.
    const irrelevant: std.Target.Cpu.Feature.Set = switch (host.cpu.arch) {
        .x86_64 => std.Target.x86.featureSet(&.{
            .@"16bit_mode",
            .@"32bit_mode",
            .@"64bit",
            .false_deps_getmant,
            .false_deps_lzcnt_tzcnt,
            .false_deps_mulc,
            .false_deps_mullq,
            .false_deps_perm,
            .false_deps_popcnt,
            .false_deps_range,
            .fast_11bytenop,
            .fast_15bytenop,
            .fast_7bytenop,
            .fast_bextr,
            .fast_dpwssd,
            .fast_gather,
            .fast_hops,
            .fast_imm16,
            .fast_lzcnt,
            .fast_movbe,
            .fast_scalar_fsqrt,
            .fast_scalar_shift_masks,
            .fast_shld_rotate,
            .fast_variable_crosslane_shuffle,
            .fast_variable_perlane_shuffle,
            .fast_vector_fsqrt,
            .fast_vector_shift_masks,
            .faster_shift_than_shuffle,
            .no_bypass_delay,
            .no_bypass_delay_blend,
            .no_bypass_delay_mov,
            .no_bypass_delay_shuffle,
            .prefer_128_bit,
            .prefer_256_bit,
            .prefer_legacy_setcc,
            .prefer_mask_registers,
            .prefer_movmsk_over_vtest,
            .prefer_no_gather,
            .prefer_no_scatter,
            .slow_3ops_lea,
            .slow_incdec,
            .slow_lea,
            .slow_pmaddwd,
            .slow_pmulld,
            .slow_pmullq,
            .slow_shld,
            .slow_two_mem_ops,
            .slow_unaligned_mem_16,
            .slow_unaligned_mem_32,
        }),
        .aarch64, .aarch64_be => std.Target.aarch64.featureSet(&.{
            .addr_lsl_slow_14,
            .alu_lsl_fast,
            .avoid_ldapur,
            .disable_fast_inc_vl,
            .exynos_cheap_as_move,
            .fuse_address,
            .fuse_addsub_2reg_const1,
            .fuse_adrp_add,
            .fuse_aes,
            .fuse_arith_logic,
            .fuse_crypto_eor,
            .fuse_csel,
            .fuse_cset,
            .fuse_literals,
            .predictable_select_expensive,
            .slow_misaligned_128store,
            .slow_paired_128,
            .slow_strqro_store,
            .use_experimental_zeroing_pseudos,
            .use_fixed_over_scalable_if_equal_cost,
            .use_postra_scheduler,
            .use_reciprocal_square_root,
            .use_wzr_to_vec_move,
        }),
        else => .empty,
    };
    var set = actual.cpu.features;
    set.removeFeatureSet(irrelevant);

    if (!host.cpu.features.isSuperSetOf(set))
        return false;

    return true;
}

/// For stack trace tests, we only test native by default, because external executors are pretty
/// unreliable at stack tracing. However, if there's a 32-bit equivalent target which the host can
/// trivially run, we may as well at least test that!
fn nativeAndCompatible32bit(b: *std.Build, skip_non_native: bool) []const std.Build.ResolvedTarget {
    const host = b.graph.host.result;
    const only_native = (&b.graph.host)[0..1];
    if (skip_non_native) return only_native;
    const arch32 = compatible32bitArch(&b.graph.host.result) orelse return only_native;
    return b.graph.arena.dupe(std.Build.ResolvedTarget, &.{
        b.graph.host,
        b.resolveTargetQuery(.{ .cpu_arch = arch32, .os_tag = host.os.tag }),
    }) catch @panic("OOM");
}

fn wineAndCompatible32bit(b: *std.Build, skip_non_native: bool) []const std.Build.ResolvedTarget {
    var targets: std.ArrayList(std.Build.ResolvedTarget) = .empty;

    const host = b.graph.host.result;

    targets.append(b.graph.arena, b.resolveTargetQuery(.{
        .cpu_arch = host.cpu.arch,
        .os_tag = .windows,
    })) catch @panic("OOM");
    if (!skip_non_native) {
        if (compatible32bitArch(&b.graph.host.result)) |arch| {
            targets.append(b.graph.arena, b.resolveTargetQuery(.{
                .cpu_arch = arch,
                .os_tag = .windows,
            })) catch @panic("OOM");
        }
    }

    return targets.toOwnedSlice(b.graph.arena) catch @panic("OOM");
}

fn darlingTargets(b: *std.Build) []const std.Build.ResolvedTarget {
    var targets: std.ArrayList(std.Build.ResolvedTarget) = .empty;

    const host = b.graph.host.result;

    targets.append(b.graph.arena, b.resolveTargetQuery(.{
        .cpu_arch = host.cpu.arch,
        .os_tag = .macos,
    })) catch @panic("OOM");

    return targets.toOwnedSlice(b.graph.arena) catch @panic("OOM");
}

pub fn addStackTraceTests(
    b: *std.Build,
    test_filters: []const []const u8,
    skip_non_native: bool,
) *Step {
    const step = b.step("test-stack-traces", "Run the stack trace tests");

    const convert_exe = b.addExecutable(.{
        .name = "convert-stack-trace",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/src/convert-stack-trace.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });

    const host_cases = b.allocator.create(StackTracesContext) catch @panic("OOM");
    host_cases.* = .{
        .b = b,
        .step = step,
        .test_filters = test_filters,
        .targets = nativeAndCompatible32bit(b, skip_non_native),
        .convert_exe = convert_exe,
    };
    stack_traces.addCases(host_cases, b.graph.host.result.os.tag);

    if (b.enable_wine) {
        const wine_cases = b.allocator.create(StackTracesContext) catch @panic("OOM");
        wine_cases.* = .{
            .b = b,
            .step = step,
            .test_filters = test_filters,
            .targets = wineAndCompatible32bit(b, skip_non_native),
            .convert_exe = convert_exe,
        };
        stack_traces.addCases(wine_cases, .windows);
    }

    if (b.enable_darling) {
        const darling_cases = b.allocator.create(StackTracesContext) catch @panic("OOM");
        darling_cases.* = .{
            .b = b,
            .step = step,
            .test_filters = test_filters,
            .targets = darlingTargets(b),
            .convert_exe = convert_exe,
        };
        stack_traces.addCases(darling_cases, .macos);
    }

    return step;
}

pub fn addErrorTraceTests(
    b: *std.Build,
    test_filters: []const []const u8,
    optimize_modes: []const OptimizeMode,
    skip_non_native: bool,
) *Step {
    const step = b.step("test-error-traces", "Run the error trace tests");

    const convert_exe = b.addExecutable(.{
        .name = "convert-stack-trace",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/src/convert-stack-trace.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });

    const host_cases = b.allocator.create(ErrorTracesContext) catch @panic("OOM");
    host_cases.* = .{
        .b = b,
        .step = step,
        .test_filters = test_filters,
        .targets = nativeAndCompatible32bit(b, skip_non_native),
        .optimize_modes = optimize_modes,
        .convert_exe = convert_exe,
    };
    error_traces.addCases(host_cases, b.graph.host.result.os.tag);

    if (b.enable_wine) {
        const wine_cases = b.allocator.create(ErrorTracesContext) catch @panic("OOM");
        wine_cases.* = .{
            .b = b,
            .step = step,
            .test_filters = test_filters,
            .targets = wineAndCompatible32bit(b, skip_non_native),
            .optimize_modes = optimize_modes,
            .convert_exe = convert_exe,
        };
        error_traces.addCases(wine_cases, .windows);
    }

    if (b.enable_darling) {
        const darling_cases = b.allocator.create(ErrorTracesContext) catch @panic("OOM");
        darling_cases.* = .{
            .b = b,
            .step = step,
            .test_filters = test_filters,
            .targets = darlingTargets(b),
            .optimize_modes = optimize_modes,
            .convert_exe = convert_exe,
        };
        error_traces.addCases(darling_cases, .macos);
    }

    return step;
}

fn compilerHasPackageManager(b: *std.Build) bool {
    // We can only use dependencies if the compiler was built with support for package management.
    // (zig2 doesn't support it, but we still need to construct a build graph to build stage3.)
    return b.available_deps.len != 0;
}

pub fn addStandaloneTests(
    b: *std.Build,
    optimize_modes: []const OptimizeMode,
    enable_macos_sdk: bool,
    enable_ios_sdk: bool,
    enable_symlinks_windows: bool,
) *Step {
    const step = b.step("test-standalone", "Run the standalone tests");
    if (compilerHasPackageManager(b)) {
        const test_cases_dep_name = "standalone_test_cases";
        const test_cases_dep = b.dependency(test_cases_dep_name, .{
            .enable_ios_sdk = enable_ios_sdk,
            .enable_macos_sdk = enable_macos_sdk,
            .enable_symlinks_windows = enable_symlinks_windows,
            .simple_skip_debug = mem.indexOfScalar(OptimizeMode, optimize_modes, .Debug) == null,
            .simple_skip_release_safe = mem.indexOfScalar(OptimizeMode, optimize_modes, .ReleaseSafe) == null,
            .simple_skip_release_fast = mem.indexOfScalar(OptimizeMode, optimize_modes, .ReleaseFast) == null,
            .simple_skip_release_small = mem.indexOfScalar(OptimizeMode, optimize_modes, .ReleaseSmall) == null,
        });
        const test_cases_dep_step = test_cases_dep.builder.default_step;
        test_cases_dep_step.name = b.dupe(test_cases_dep_name);
        step.dependOn(test_cases_dep.builder.default_step);
    }
    return step;
}

pub fn addCliTests(b: *std.Build) *Step {
    const step = b.step("test-cli", "Test the command line interface");
    const s = std.fs.path.sep_str;

    {
        // Test that all JIT'd commands compile.
        for (&[_][]const u8{
            "libc",
            "objcopy",
            "objdump",
            "rc",
            "reduce",
            "std",
        }) |cmd| {
            const run_help = b.addSystemCommand(&.{ b.graph.zig_exe, cmd, "--help" });
            run_help.setName(b.fmt("zig {s} --help", .{cmd}));
            run_help.expectStdErrEqual("");
            run_help.expectExitCode(0);
            step.dependOn(&run_help.step);
        }
    }

    {
        // Test `zig init`.
        const tmp_path = b.tmpPath();
        const init_exe = b.addSystemCommand(&.{ b.graph.zig_exe, "init" });
        init_exe.setCwd(tmp_path);
        init_exe.setName("zig init");
        init_exe.expectStdOutEqual("");
        init_exe.expectStdErrEqual("info: created build.zig\n" ++
            "info: created build.zig.zon\n" ++
            "info: created src" ++ s ++ "main.zig\n" ++
            "info: created src" ++ s ++ "root.zig\n" ++
            "info: see `zig build --help` for a menu of options\n");

        // Test missing output path.
        const bad_out_arg = "-femit-bin=does" ++ s ++ "not" ++ s ++ "exist" ++ s ++ "foo.exe";
        const ok_src_arg = "src" ++ s ++ "main.zig";
        const es = if (builtin.os.tag == .windows) "\\\\" else "/";
        const expected = "error: unable to open output directory \"does" ++ es ++ "not" ++ es ++ "exist\": FileNotFound\n";
        const run_bad = b.addSystemCommand(&.{ b.graph.zig_exe, "build-exe", ok_src_arg, bad_out_arg });
        run_bad.setName("zig build-exe error message for bad -femit-bin arg");
        run_bad.expectExitCode(1);
        run_bad.expectStdErrEqual(expected);
        run_bad.expectStdOutEqual("");
        run_bad.step.dependOn(&init_exe.step);

        const run_test = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "test" });
        run_test.setCwd(tmp_path);
        run_test.setName("zig build test");
        run_test.expectStdOutEqual("");
        run_test.step.dependOn(&init_exe.step);

        const run_run = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "run" });
        run_run.setCwd(tmp_path);
        run_run.setName("zig build run");
        run_run.expectStdOutEqual("Run `zig build test` to run the tests.\n");
        run_run.expectStdErrMatch("All your codebase are belong to us.\n");
        run_run.step.dependOn(&init_exe.step);

        step.dependOn(&run_test.step);
        step.dependOn(&run_run.step);
        step.dependOn(&run_bad.step);
    }

    {
        // Test `zig init -m`.
        const tmp_path = b.tmpPath();
        const init_exe = b.addSystemCommand(&.{ b.graph.zig_exe, "init", "-m" });
        init_exe.setCwd(tmp_path);
        init_exe.setName("zig init -m");
        init_exe.expectStdOutEqual("");
        init_exe.expectStdErrEqual("info: successfully populated 'build.zig.zon' and 'build.zig'\n");
    }

    // Test Godbolt API
    if (builtin.os.tag == .linux and builtin.cpu.arch == .x86_64) {
        const tmp_path = b.tmpPath();

        const example_zig = b.addWriteFiles().add("example.zig",
            \\// Type your code here, or load an example.
            \\export fn square(num: i32) i32 {
            \\    return num * num;
            \\}
            \\extern fn zig_panic() noreturn;
            \\pub fn panic(msg: []const u8, error_return_trace: ?*@import("std").builtin.StackTrace, _: ?usize) noreturn {
            \\    _ = msg;
            \\    _ = error_return_trace;
            \\    zig_panic();
            \\}
        );

        // This is intended to be the exact CLI usage used by godbolt.org.
        const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build-obj", "--cache-dir" });
        run.addDirectoryArg(tmp_path);
        run.addArgs(&.{ "--name", "example", "-fno-emit-bin", "-fno-emit-h", "-fstrip", "-OReleaseFast" });
        run.addFileArg(example_zig);
        const example_s = run.addPrefixedOutputFileArg("-femit-asm=", "example.s");

        const checkfile = b.addCheckFile(example_s, .{
            .expected_matches = &.{
                "square:",
                "mov\teax, edi",
                "imul\teax, edi",
            },
        });
        checkfile.setName("check godbolt.org CLI usage generating valid asm");

        step.dependOn(&checkfile.step);
    }

    {
        // Test `zig fmt`.
        // This test must use a temporary directory rather than a cache
        // directory because this test will be mutating the files. The cache
        // system relies on cache directories being mutated only by their
        // owners.
        const tmp_wf = b.addTempFiles();
        const unformatted_code = "    // no reason for indent";

        _ = tmp_wf.add("fmt1.zig", unformatted_code);
        _ = tmp_wf.add("fmt2.zig", unformatted_code);
        _ = tmp_wf.add("subdir/fmt3.zig", unformatted_code);

        const tmp_path = tmp_wf.getDirectory();

        // Test zig fmt affecting only the appropriate files.
        const run1 = b.addSystemCommand(&.{ b.graph.zig_exe, "fmt", "fmt1.zig" });
        run1.setName("run zig fmt one file");
        run1.setCwd(tmp_path);
        run1.has_side_effects = true;
        // stdout should be file path + \n
        run1.expectStdOutEqual("fmt1.zig\n");

        // Test excluding files and directories from a run
        const run2 = b.addSystemCommand(&.{ b.graph.zig_exe, "fmt", "--exclude", "fmt2.zig", "--exclude", "subdir", "." });
        run2.setName("run zig fmt on directory with exclusions");
        run2.setCwd(tmp_path);
        run2.has_side_effects = true;
        run2.expectStdOutEqual("");
        run2.step.dependOn(&run1.step);

        // Test excluding non-existent file
        const run3 = b.addSystemCommand(&.{ b.graph.zig_exe, "fmt", "--exclude", "fmt2.zig", "--exclude", "nonexistent.zig", "." });
        run3.setName("run zig fmt on directory with non-existent exclusion");
        run3.setCwd(tmp_path);
        run3.has_side_effects = true;
        run3.expectStdOutEqual("." ++ s ++ "subdir" ++ s ++ "fmt3.zig\n");
        run3.step.dependOn(&run2.step);

        // running it on the dir, only the new file should be changed
        const run4 = b.addSystemCommand(&.{ b.graph.zig_exe, "fmt", "." });
        run4.setName("run zig fmt the directory");
        run4.setCwd(tmp_path);
        run4.has_side_effects = true;
        run4.expectStdOutEqual("." ++ s ++ "fmt2.zig\n");
        run4.step.dependOn(&run3.step);

        // both files have been formatted, nothing should change now
        const run5 = b.addSystemCommand(&.{ b.graph.zig_exe, "fmt", "." });
        run5.setName("run zig fmt with nothing to do");
        run5.setCwd(tmp_path);
        run5.has_side_effects = true;
        run5.expectStdOutEqual("");
        run5.step.dependOn(&run4.step);

        const unformatted_code_utf16 = "\xff\xfe \x00 \x00 \x00 \x00/\x00/\x00 \x00n\x00o\x00 \x00r\x00e\x00a\x00s\x00o\x00n\x00";
        const write6 = b.addMutateFiles(tmp_path);
        const fmt6_path = write6.add("fmt6.zig", unformatted_code_utf16);
        write6.step.dependOn(&run5.step);

        // Test `zig fmt` handling UTF-16 decoding.
        const run6 = b.addSystemCommand(&.{ b.graph.zig_exe, "fmt", "." });
        run6.setName("run zig fmt convert UTF-16 to UTF-8");
        run6.setCwd(tmp_path);
        run6.has_side_effects = true;
        run6.expectStdOutEqual("." ++ s ++ "fmt6.zig\n");
        run6.step.dependOn(&write6.step);

        // TODO change this to an exact match
        const check6 = b.addCheckFile(fmt6_path, .{
            .expected_matches = &.{
                "// no reason",
            },
        });
        check6.step.dependOn(&run6.step);

        step.dependOn(&check6.step);
    }

    {
        const run_test = b.addSystemCommand(&.{
            b.graph.zig_exe,
            "build",
            "test",
            "-Dbool_true",
            "-Dbool_false=false",
            "-Dint=1234",
            "-De=two",
            "-Dstring=hello",
        });
        run_test.addArg("--build-file");
        run_test.addFileArg(b.path("test/cli/options/build.zig"));

        run_test.addArg("--cache-dir");
        run_test.addFileArg(.cache_root);

        run_test.setName("test build options");

        step.dependOn(&run_test.step);
    }

    return step;
}

pub const ModuleTestOptions = struct {
    test_filters: []const []const u8,
    test_target_filters: []const []const u8,
    test_extra_targets: bool,
    root_src: []const u8,
    name: []const u8,
    desc: []const u8,
    optimize_modes: []const OptimizeMode,
    include_paths: []const []const u8,
    test_only: ?TestOnly,
    skip_single_threaded: bool,
    skip_non_native: bool,
    skip_spirv: bool,
    skip_wasm: bool,
    skip_freebsd: bool,
    skip_netbsd: bool,
    skip_openbsd: bool,
    skip_windows: bool,
    skip_darwin: bool,
    skip_linux: bool,
    skip_llvm: bool,
    skip_libc: bool,
    max_rss: u64 = 0,
    no_builtin: bool = false,
    sanitize_thread: ?bool = null,
    build_options: ?*Step.Options = null,

    pub const TestOnly = union(enum) {
        default: void,
        fuzz: OptimizeMode,
    };
};

pub fn addModuleTests(b: *std.Build, options: ModuleTestOptions) *Step {
    const step = b.step(b.fmt("test-{s}", .{options.name}), options.desc);

    if (options.test_only) |test_only| {
        const test_target: ModuleTestTarget = switch (test_only) {
            .default => .{
                .link_libc = if (std.mem.eql(u8, options.name, "libc")) true else null,
            },
            .fuzz => |optimize| .{
                .optimize_mode = optimize,
                .use_llvm = true,
            },
        };
        const resolved_target = b.resolveTargetQuery(test_target.target);
        const triple_txt = resolved_target.query.zigTriple(b.allocator) catch @panic("OOM");
        addOneModuleTest(b, step, test_target, &resolved_target, triple_txt, options);

        return step;
    }

    for_targets: for (module_test_targets) |test_target| {
        if (test_target.skip_modules.len > 0) {
            for (test_target.skip_modules) |skip_mod| {
                if (std.mem.eql(u8, options.name, skip_mod)) continue :for_targets;
            }
        }

        const resolved_target = b.resolveTargetQuery(test_target.target);

        if (!options.test_extra_targets and test_target.extra_target) continue;

        if (options.skip_non_native and !isNative(&resolved_target, &b.graph.host.result))
            continue;

        const target = &resolved_target.result;

        if (target.cpu.arch == .s390x and target.ofmt == .c) {
            // https://codeberg.org/ziglang/zig/issues/35523
            continue;
        }

        if (target.cpu.arch == .riscv64 and target.ofmt == .c) {
            // https://codeberg.org/ziglang/zig/issues/30930
            continue;
        }

        if (std.mem.eql(u8, options.name, "libc")) {
            // The libc API tests obviously need to link libc. So for test
            // target entries where we wouldn't link libc by default, skip the
            // libc API tests.
            if (test_target.link_libc == null and !std.os.targetRequiresLibC(target)) continue;
        }

        if (options.skip_spirv and target.cpu.arch.isSpirV()) continue;
        if (options.skip_wasm and target.cpu.arch.isWasm()) continue;

        if (options.skip_freebsd and target.os.tag == .freebsd) continue;
        if (options.skip_netbsd and target.os.tag == .netbsd) continue;
        if (options.skip_openbsd and target.os.tag == .openbsd) continue;
        if (options.skip_windows and target.os.tag == .windows) continue;
        if (options.skip_darwin and target.os.tag.isDarwin()) continue;
        if (options.skip_linux and target.os.tag == .linux) continue;

        const would_use_llvm = wouldUseLlvm(test_target.use_llvm, test_target.target, test_target.optimize_mode);
        if (options.skip_llvm and would_use_llvm) continue;

        const triple_txt = resolved_target.query.zigTriple(b.allocator) catch @panic("OOM");

        if (options.test_target_filters.len > 0) {
            for (options.test_target_filters) |filter| {
                if (std.mem.indexOf(u8, triple_txt, filter) != null) break;
            } else continue;
        }

        if (options.skip_libc and (test_target.link_libc == true or std.os.targetRequiresLibC(target)))
            continue;

        // We can't provide MSVC libc when cross-compiling.
        if (target.abi == .msvc and test_target.link_libc == true and builtin.os.tag != .windows)
            continue;

        if (options.skip_single_threaded and test_target.single_threaded == true)
            continue;

        const want_this_mode = for (options.optimize_modes) |m| {
            if (m == test_target.optimize_mode) break true;
        } else false;
        if (!want_this_mode) continue;

        addOneModuleTest(b, step, test_target, &resolved_target, triple_txt, options);
    }
    return step;
}

fn addOneModuleTest(
    b: *std.Build,
    step: *Step,
    test_target: ModuleTestTarget,
    resolved_target: *const std.Build.ResolvedTarget,
    triple_txt: []const u8,
    options: ModuleTestOptions,
) void {
    const target = &resolved_target.result;
    const libc_suffix = if (test_target.link_libc == true) "-libc" else "";
    const model_txt = target.cpu.model.name;

    // These emulated targets need a lot more RAM for unknown reasons.
    const max_rss = if (mem.eql(u8, options.name, "std") and
        (target.cpu.arch == .hexagon or
            (target.cpu.arch.isRISCV() and !resolved_target.query.isNative()) or
            target.cpu.arch.isWasm()))
        options.max_rss * 2
    else
        options.max_rss;

    const these_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(options.root_src),
            .optimize = test_target.optimize_mode,
            .target = resolved_target.*,
            .link_libc = test_target.link_libc,
            .pic = test_target.pic,
            .strip = test_target.strip,
            .sanitize_thread = options.sanitize_thread,
            .single_threaded = test_target.single_threaded,
        }),
        .max_rss = max_rss,
        .filters = options.test_filters,
        .use_llvm = test_target.use_llvm,
        .use_lld = test_target.use_lld,
        .zig_lib_dir = b.path("lib"),
    });
    these_tests.linkage = test_target.linkage;
    // https://codeberg.org/ziglang/zig/issues/31701
    if (!(mem.eql(u8, options.name, "compiler-rt") or mem.eql(u8, options.name, "libc"))) {
        if (options.no_builtin) these_tests.root_module.no_builtin = true;
    }
    // https://codeberg.org/ziglang/zig/issues/31702
    if (mem.eql(u8, options.name, "compiler-rt") or mem.eql(u8, options.name, "libc")) {
        these_tests.root_module.stack_protector = false;
    }
    // https://github.com/llvm/llvm-project/issues/195561
    if (target.cpu.arch.isPowerPC()) {
        these_tests.root_module.stack_protector = false;
    }
    if (options.build_options) |build_options| {
        these_tests.root_module.addOptions("build_options", build_options);
    }
    if (test_target.function_sections) |fs| these_tests.link_function_sections = fs;
    if (test_target.data_sections) |ds| these_tests.link_data_sections = ds;
    const single_threaded_suffix = if (test_target.single_threaded == true) "-single" else "";
    const backend_suffix = if (test_target.use_llvm == true)
        "-llvm"
    else if (target.ofmt == .c)
        "-cbe"
    else if (test_target.use_llvm == false)
        "-selfhosted"
    else
        "";
    const use_lld = if (test_target.use_lld == false) "-no-lld" else "";
    const linkage_name = if (test_target.linkage) |linkage| switch (linkage) {
        inline else => |t| "-" ++ @tagName(t),
    } else "";
    const use_pic = if (test_target.pic == true) "-pic" else "";

    for (options.include_paths) |include_path| these_tests.root_module.addIncludePath(b.path(include_path));

    const qualified_name = b.fmt("{s}-{s}-{s}-{t}{s}{s}{s}{s}{s}{s}", .{
        options.name,
        triple_txt,
        model_txt,
        test_target.optimize_mode,
        libc_suffix,
        single_threaded_suffix,
        backend_suffix,
        use_lld,
        linkage_name,
        use_pic,
    });

    if (target.ofmt == .c) {
        var altered_query = test_target.target;
        altered_query.ofmt = null;

        const compile_c = b.createModule(.{
            .root_source_file = null,
            .link_libc = test_target.link_libc,
            .target = b.resolveTargetQuery(altered_query),
        });
        const compile_c_exe = b.addExecutable(.{
            .name = qualified_name,
            .root_module = compile_c,
            .zig_lib_dir = b.path("lib"),
        });

        compile_c.addCSourceFile(.{
            .file = these_tests.getEmittedBin(),
            .flags = blk: {
                const invariant_cflags: []const []const u8 = &.{
                    // Tracking issue for making the C backend generate C89 compatible code:
                    // https://github.com/ziglang/zig/issues/19468
                    "-std=c99",
                    "-Werror",

                    "-Wall",
                    "-Wembedded-directive",
                    "-Wempty-translation-unit",
                    "-Wextra",
                    "-Wgnu",
                    "-Winvalid-utf8",
                    "-Wkeyword-macro",
                    "-Woverlength-strings",

                    // Tracking issue for making the C backend generate code
                    // that does not trigger warnings:
                    // https://github.com/ziglang/zig/issues/19467

                    // spotted everywhere
                    "-Wno-builtin-requires-header",

                    // spotted on linux
                    "-Wno-braced-scalar-init",
                    "-Wno-excess-initializers",
                    "-Wno-incompatible-pointer-types-discards-qualifiers",
                    "-Wno-unused",
                    "-Wno-unused-parameter",

                    // spotted on darwin
                    "-Wno-incompatible-pointer-types",

                    // https://github.com/llvm/llvm-project/issues/153314
                    "-Wno-unterminated-string-initialization",

                    // In both Zig and C it is legal to return a pointer to a
                    // local. The C backend lowers such thing directly, so the
                    // corresponding warning in C must be disabled.
                    "-Wno-return-stack-address",
                };

                const function_data_sections = switch (target.cpu.arch) {
                    .arm,
                    .armeb,
                    .thumb,
                    .thumbeb,
                    .hexagon,
                    .powerpc,
                    .powerpcle,
                    .powerpc64,
                    .powerpc64le,
                    => true,
                    else => false,
                };

                break :blk if (function_data_sections) invariant_cflags ++ &[_][]const u8{
                    "-ffunction-sections",
                    "-fdata-sections",
                } else invariant_cflags;
            },
        });
        compile_c.addIncludePath(b.path("lib")); // for zig.h
        if (target.os.tag == .windows) {
            if (true) {
                // Unfortunately this requires about 8G of RAM for clang to compile
                // and our Windows CI runners do not have this much.
                // TODO This is not an appropriate way to work around this problem.
                step.dependOn(&these_tests.step);
                return;
            }
            if (test_target.link_libc == false) {
                compile_c_exe.subsystem = .Console;
                compile_c.linkSystemLibrary("kernel32", .{});
                compile_c.linkSystemLibrary("ntdll", .{});
            }
            if (mem.eql(u8, options.name, "std")) {
                if (test_target.link_libc == false) {
                    compile_c.linkSystemLibrary("shell32", .{});
                    compile_c.linkSystemLibrary("advapi32", .{});
                }
                compile_c.linkSystemLibrary("crypt32", .{});
                compile_c.linkSystemLibrary("ole32", .{});
            }
        }

        const run = b.addRunArtifact(compile_c_exe);
        run.skip_foreign_checks = true;
        run.enableTestRunnerMode();
        run.setName(b.fmt("run test {s}", .{qualified_name}));

        step.dependOn(&run.step);
    } else if (target.cpu.arch.isSpirV()) {
        // Don't run spirv binaries
        _ = these_tests.getEmittedBin();
        step.dependOn(&these_tests.step);
    } else if (target.cpu.arch == .x86_64 and target.os.tag.isDarwin()) {
        // https://codeberg.org/ziglang/zig/issues/35267
        _ = these_tests.getEmittedBin();
        step.dependOn(&these_tests.step);
    } else {
        const run = b.addRunArtifact(these_tests);
        run.skip_foreign_checks = true;
        run.setName(b.fmt("run test {s}", .{qualified_name}));

        step.dependOn(&run.step);
    }
}

pub fn wouldUseLlvm(use_llvm: ?bool, query: std.Target.Query, optimize_mode: OptimizeMode) bool {
    if (comptime builtin.cpu.arch.endian() == .big) return true; // https://github.com/ziglang/zig/issues/25961
    if (use_llvm) |x| return x;
    if (query.ofmt == .c) return false;
    switch (optimize_mode) {
        .Debug => {},
        else => return true,
    }
    const cpu_arch = query.cpu_arch orelse builtin.cpu.arch;
    const os_tag = query.os_tag orelse builtin.os.tag;
    const ofmt: std.Target.ObjectFormat = query.ofmt orelse .default(os_tag, cpu_arch);
    switch (cpu_arch) {
        .x86_64 => {
            if (std.Target.ptrBitWidth_arch_abi(cpu_arch, query.abi orelse .none) != 64) return true;
            if (os_tag.isBSD() or os_tag == .illumos) return true;
            return switch (ofmt) {
                .elf, .macho => return false,
                else => return true,
            };
        },
        .spirv32, .spirv64 => return false,
        else => return true,
    }
}

const CAbiTestOptions = struct {
    test_target_filters: []const []const u8,
    optimize_modes: []const OptimizeMode,
    skip_non_native: bool,
    skip_wasm: bool,
    skip_freebsd: bool,
    skip_netbsd: bool,
    skip_openbsd: bool,
    skip_windows: bool,
    skip_darwin: bool,
    skip_linux: bool,
    skip_llvm: bool,
    max_rss: u64 = 0,
};

pub fn addCAbiTests(b: *std.Build, options: CAbiTestOptions) *Step {
    const step = b.step("test-c-abi", "Run the C ABI tests");

    for (c_abi_targets) |c_abi_target| {
        if (options.skip_wasm and c_abi_target.target.cpu_arch != null and c_abi_target.target.cpu_arch.?.isWasm()) continue;

        if (options.skip_freebsd and c_abi_target.target.os_tag == .freebsd) continue;
        if (options.skip_netbsd and c_abi_target.target.os_tag == .netbsd) continue;
        if (options.skip_openbsd and c_abi_target.target.os_tag == .openbsd) continue;
        if (options.skip_windows and c_abi_target.target.os_tag == .windows) continue;
        if (options.skip_darwin and c_abi_target.target.os_tag != null and c_abi_target.target.os_tag.?.isDarwin()) continue;
        if (options.skip_linux and c_abi_target.target.os_tag == .linux) continue;

        const resolved_target = b.resolveTargetQuery(c_abi_target.target);
        const triple_txt = resolved_target.query.zigTriple(b.allocator) catch @panic("OOM");
        const target = &resolved_target.result;

        if (options.skip_non_native and !isNative(&resolved_target, &b.graph.host.result))
            continue;

        if (options.test_target_filters.len > 0) {
            for (options.test_target_filters) |filter| {
                if (std.mem.indexOf(u8, triple_txt, filter) != null) break;
            } else continue;
        }

        for (options.optimize_modes) |optimize_mode| {
            const would_use_llvm = wouldUseLlvm(c_abi_target.use_llvm, c_abi_target.target, optimize_mode);
            if (options.skip_llvm and would_use_llvm) continue;

            const test_mod = b.createModule(.{
                .root_source_file = b.path("test/c_abi/main.zig"),
                .target = resolved_target,
                .optimize = optimize_mode,
                .link_libc = true,
                .pic = c_abi_target.pic,
                .strip = c_abi_target.strip,
            });
            test_mod.addCSourceFile(.{
                .file = b.path("test/c_abi/cfuncs.c"),
                .flags = &.{"-std=c99"},
            });
            for (c_abi_target.c_defines) |define| test_mod.addCMacro(define, "1");

            const test_step = b.addTest(.{
                .name = b.fmt("test-c-abi-{s}-{s}-{s}{s}{s}{s}", .{
                    triple_txt,
                    target.cpu.model.name,
                    @tagName(optimize_mode),
                    if (c_abi_target.use_llvm == true)
                        "-llvm"
                    else if (target.ofmt == .c)
                        "-cbe"
                    else if (c_abi_target.use_llvm == false)
                        "-selfhosted"
                    else
                        "",
                    if (c_abi_target.use_lld == false) "-no-lld" else "",
                    if (c_abi_target.pic == true) "-pic" else "",
                }),
                .root_module = test_mod,
                .use_llvm = c_abi_target.use_llvm,
                .use_lld = c_abi_target.use_lld,
                .max_rss = options.max_rss,
            });

            // https://github.com/llvm/llvm-project/issues/195561
            if (target.cpu.arch.isPowerPC()) {
                test_step.root_module.stack_protector = false;
            }

            // This test is intentionally trying to check if the external ABI is
            // done properly. LTO would be a hindrance to this.
            test_step.lto = .none;

            const run = b.addRunArtifact(test_step);
            run.skip_foreign_checks = true;
            step.dependOn(&run.step);
        }
    }
    return step;
}

pub fn addCases(
    b: *std.Build,
    parent_step: *Step,
    case_test_options: @import("src/Cases.zig").CaseTestOptions,
    build_options: @import("cases.zig").BuildOptions,
) !void {
    const arena = b.allocator;
    const gpa = b.allocator;
    const io = b.graph.io;

    var cases = @import("src/Cases.zig").init(gpa, arena, io);

    // Ensure changes to these files get picked up
    // https://codeberg.org/ziglang/zig/issues/35473
    b.graph.poisonCache();

    var dir = try b.root.openDir(io, "test/cases", .{ .iterate = true });
    defer dir.close(io);

    cases.addFromDir(dir, b);
    try @import("cases.zig").addCases(&cases, build_options, b);

    cases.lowerToBuildSteps(
        b,
        parent_step,
        case_test_options,
    );
}

pub fn addDebuggerTests(b: *std.Build, options: DebuggerContext.Options) ?*Step {
    const step = b.step("test-debugger", "Run the debugger tests");
    if (options.gdb == null and options.lldb == null) {
        step.dependOn(&b.addFail("test-debugger requires -Dgdb and/or -Dlldb").step);
        return null;
    }

    var context: DebuggerContext = .{
        .b = b,
        .options = options,
        .root_step = step,
    };
    context.addTestsForTarget(&.{
        .resolved = b.resolveTargetQuery(.{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
            .abi = .none,
        }),
        .pic = false,
        .test_name_suffix = "x86_64-linux",
    });
    context.addTestsForTarget(&.{
        .resolved = b.resolveTargetQuery(.{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
            .abi = .none,
        }),
        .pic = true,
        .test_name_suffix = "x86_64-linux-pic",
    });
    return step;
}

pub fn addIncrementalTests(b: *std.Build, test_step: *Step, test_filters: []const []const u8) !void {
    const io = b.graph.io;

    const incr_check = b.addExecutable(.{
        .name = "incr-check",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/incr-check.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });

    // Ensure changes to these files get picked up
    // https://codeberg.org/ziglang/zig/issues/35473
    b.graph.poisonCache();

    var dir = try b.root.openDir(io, "test/incremental", .{ .iterate = true });
    defer dir.close(io);

    var it = try dir.walk(b.graph.arena);
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (std.mem.endsWith(u8, entry.basename, ".swp")) continue;

        for (test_filters) |test_filter| {
            if (std.mem.indexOf(u8, entry.path, test_filter)) |_| break;
        } else if (test_filters.len > 0) continue;

        for (incremental_targets) |target_str| {
            const run = b.addRunArtifact(incr_check);
            run.setName(b.fmt("incr-check {s} '{s}'", .{ target_str, entry.basename }));

            run.addArg(b.graph.zig_exe);
            run.addFileArg(b.path("test/incremental/").path(b, entry.path));

            run.addArg("--zig-lib-dir");
            run.addDirectoryArg(.zig_lib);

            run.addArgs(&.{ "--target", target_str });

            run.addArg("--quiet"); // don't fill stderr telling us about skipped tests etc

            if (b.enable_qemu) run.addArg("-fqemu");
            if (b.enable_wine) run.addArg("-fwine");
            if (b.enable_wasmtime) run.addArg("-fwasmtime");
            if (b.enable_darling) run.addArg("-fdarling");

            run.addCheck(.{ .expect_term = .{ .exited = 0 } });
            test_step.dependOn(&run.step);
        }
    }
}

pub fn addLlvmIrTests(b: *std.Build, options: LlvmIrContext.Options) ?*Step {
    const step = b.step("test-llvm-ir", "Run the LLVM IR tests");

    if (!options.enable_llvm) {
        step.dependOn(&b.addFail("test-llvm-ir requires -Denable-llvm").step);
        return null;
    }

    var context: LlvmIrContext = .{
        .b = b,
        .options = options,
        .root_step = step,
    };

    llvm_ir.addCases(&context);

    return step;
}

const libc_test_nsz_targets: []const std.Target.Query = &.{
    .{
        .cpu_arch = .arm,
        .os_tag = .linux,
        .abi = .musleabi,
    },
    .{
        .cpu_arch = .arm,
        .os_tag = .linux,
        .abi = .musleabihf,
    },
    .{
        .cpu_arch = .armeb,
        .os_tag = .linux,
        .abi = .musleabi,
    },
    .{
        .cpu_arch = .armeb,
        .os_tag = .linux,
        .abi = .musleabihf,
    },
    .{
        .cpu_arch = .thumb,
        .os_tag = .linux,
        .abi = .musleabi,
    },
    .{
        .cpu_arch = .thumb,
        .os_tag = .linux,
        .abi = .musleabihf,
    },
    .{
        .cpu_arch = .thumbeb,
        .os_tag = .linux,
        .abi = .musleabi,
    },
    .{
        .cpu_arch = .thumbeb,
        .os_tag = .linux,
        .abi = .musleabihf,
    },
    .{
        .cpu_arch = .aarch64,
        .os_tag = .linux,
        .abi = .musl,
    },
    .{
        .cpu_arch = .aarch64_be,
        .os_tag = .linux,
        .abi = .musl,
    },
    // .{
    //     .cpu_arch = .hexagon,
    //     .os_tag = .linux,
    //     .abi = .musl,
    // },
    .{
        .cpu_arch = .loongarch64,
        .os_tag = .linux,
        .abi = .musl,
    },
    .{
        .cpu_arch = .loongarch64,
        .os_tag = .linux,
        .abi = .muslsf,
    },
    // .{
    //     .cpu_arch = .mips,
    //     .os_tag = .linux,
    //     .abi = .musleabi,
    // },
    // .{
    //     .cpu_arch = .mips,
    //     .os_tag = .linux,
    //     .abi = .musleabihf,
    // },
    // .{
    //     .cpu_arch = .mipsel,
    //     .os_tag = .linux,
    //     .abi = .musleabi,
    // },
    // .{
    //     .cpu_arch = .mipsel,
    //     .os_tag = .linux,
    //     .abi = .musleabihf,
    // },
    // .{
    //     .cpu_arch = .mips64,
    //     .os_tag = .linux,
    //     .abi = .muslabi64,
    // },
    // .{
    //     .cpu_arch = .mips64,
    //     .os_tag = .linux,
    //     .abi = .muslabin32,
    // },
    // .{
    //     .cpu_arch = .mips64el,
    //     .os_tag = .linux,
    //     .abi = .muslabi64,
    // },
    // .{
    //     .cpu_arch = .mips64el,
    //     .os_tag = .linux,
    //     .abi = .muslabin32,
    // },
    .{
        .cpu_arch = .powerpc,
        .os_tag = .linux,
        .abi = .musleabi,
    },
    .{
        .cpu_arch = .powerpc,
        .os_tag = .linux,
        .abi = .musleabihf,
    },
    .{
        .cpu_arch = .powerpc64,
        .os_tag = .linux,
        .abi = .musl,
    },
    .{
        .cpu_arch = .powerpc64le,
        .os_tag = .linux,
        .abi = .musl,
    },
    .{
        .cpu_arch = .riscv32,
        .os_tag = .linux,
        .abi = .musl,
    },
    .{
        .cpu_arch = .riscv64,
        .os_tag = .linux,
        .abi = .musl,
    },
    .{
        .cpu_arch = .s390x,
        .os_tag = .linux,
        .abi = .musl,
    },
    .{
        .cpu_arch = .wasm32,
        .os_tag = .wasi,
        .abi = .musl,
    },
    .{
        .cpu_arch = .x86,
        .os_tag = .linux,
        .abi = .musl,
    },
    .{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .musl,
    },
    .{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .muslx32,
    },
};

pub fn addLibcTestNszTests(b: *std.Build, options: LibcContext.Options) ?*Step {
    const step = b.step("test-libc-nsz", "Run external libc-test test cases");
    const opt_libc_test_path = b.option(std.Build.LazyPath, "libc-test-path", "path to libc-test source directory");
    if (opt_libc_test_path) |libc_test_path| {
        var context: LibcContext = .{
            .b = b,
            .options = options,
            .root_step = step,
            .libc_test_src_path = libc_test_path.path(b, "src"),
        };

        libc.addCases(&context);

        for (libc_test_nsz_targets) |target_query| {
            const target = b.resolveTargetQuery(target_query);
            context.addTarget(target);
        }

        return step;
    } else {
        step.dependOn(&b.addFail("The -Dlibc-test-path=... option is required for this step").step);
        return null;
    }
}
