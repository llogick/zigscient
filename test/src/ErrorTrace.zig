const ErrorTrace = @This();

const builtin = @import("builtin");

const std = @import("std");
const Step = std.Build.Step;
const OptimizeMode = std.lang.Optimize;
const mem = std.mem;

const tests = @import("../tests.zig");
const error_traces_cases = @import("../error_traces.zig");

b: *std.Build,
step: *Step,
options: Options,
convert_exe: *std.Build.Step.Compile,

pub const Options = struct {
    test_filters: []const []const u8,
    test_target_filters: []const []const u8,
    test_extra_targets: bool,
    optimize_modes: []const OptimizeMode,
    skip_non_native: bool,
    skip_freebsd: bool,
    skip_netbsd: bool,
    skip_openbsd: bool,
    skip_windows: bool,
    skip_darwin: bool,
    skip_linux: bool,
    skip_llvm: bool,
    skip_libc: bool,
};

pub const CaseParameters = struct {
    target: std.Target.Query = .{},
    optimize: OptimizeMode = .debug,
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    use_new_linker: ?bool = null,

    // This is intended for targets that, for any reason, shouldn't be run as part of a normal test
    // invocation. This could be because of a slow backend, requiring a newer LLVM version, being
    // too niche, etc.
    extra_target: bool = false,
};

/// See the comment in `StackTrace.zig`.
pub const param_sets = [_]CaseParameters{
    .{},

    // FreeBSD Targets

    .{
        .target = .{
            .cpu_arch = .arm,
            .os_tag = .freebsd,
            .abi = .eabihf,
        },
    },

    .{
        .target = .{
            .cpu_arch = .x86,
            .os_tag = .freebsd,
            .abi = .none,
        },
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
            .cpu_arch = .aarch64_be,
            .os_tag = .linux,
            .abi = .none,
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
            .cpu_arch = .armeb,
            .os_tag = .linux,
            .abi = .eabihf,
        },
    },

    .{
        .target = .{
            .cpu_arch = .hexagon,
            .os_tag = .linux,
            .abi = .none,
        },
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
            .cpu_arch = .mips,
            .os_tag = .linux,
            .abi = .eabihf,
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
            .cpu_arch = .powerpc64,
            .os_tag = .linux,
            .abi = .none,
        },
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
            .cpu_arch = .riscv32,
            .os_tag = .linux,
            .abi = .none,
        },
    },

    .{
        .target = .{
            .cpu_arch = .riscv64,
            .os_tag = .linux,
            .abi = .none,
        },
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
            .cpu_arch = .sparc64,
            .os_tag = .linux,
            .abi = .none,
        },
    },

    .{
        .target = .{
            .cpu_arch = .thumb,
            .os_tag = .linux,
            .abi = .eabihf,
        },
    },

    .{
        .target = .{
            .cpu_arch = .thumbeb,
            .os_tag = .linux,
            .abi = .eabihf,
        },
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
            .cpu_arch = .x86_64,
            .os_tag = .linux,
            .abi = .none,
        },
    },
    .{
        .target = .{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
            .abi = .none,
        },
        .use_new_linker = true,
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
            .abi = .none,
        },
        .use_llvm = true,
        .use_new_linker = true,
    },
    .{
        .target = .{
            .cpu_arch = .x86_64,
            .os_tag = .linux,
            .abi = .x32,
        },
    },

    // NetBSD Targets

    .{
        .target = .{
            .cpu_arch = .riscv32,
            .os_tag = .netbsd,
            .abi = .none,
        },
    },

    .{
        .target = .{
            .cpu_arch = .x86,
            .os_tag = .netbsd,
            .abi = .none,
        },
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
            .abi = .gnu,
        },
    },

    .{
        .target = .{
            .cpu_arch = .thumb,
            .os_tag = .windows,
            .abi = .msvc,
        },
    },
    .{
        .target = .{
            .cpu_arch = .thumb,
            .os_tag = .windows,
            .abi = .gnu,
        },
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
            .abi = .gnu,
        },
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
            .abi = .gnu,
        },
    },
};

pub const Case = struct {
    params: *const CaseParameters,
    target: *const std.Target,
    name: []const u8,
    source: []const u8,
    expect_error: []const u8,
    expect_trace: []const u8,
    /// On these arch/OS pairs we will not test the error trace on optimized LLVM builds because the
    /// optimizations break the error trace. We will test the binary with error tracing disabled,
    /// just to ensure that the expected error is still returned from `main`.
    ///
    /// LLVM ReleaseSmall builds always have the trace disabled regardless of this field, because it
    /// seems that LLVM is particularly good at optimizing traces away in those.
    disable_trace_optimized: []const DisableConfig = &.{},

    pub const DisableConfig = struct { std.Target.Cpu.Arch, std.Target.Os.Tag };
    pub const Backend = enum { llvm, selfhosted };
};

pub fn addCases(self: *ErrorTrace) void {
    const b = self.b;

    for (&param_sets) |*params| {
        const resolved_target = b.resolveTargetQuery(params.target);
        const target = &resolved_target.result;

        if (!self.options.test_extra_targets and params.extra_target) continue;

        if (self.options.skip_non_native and !tests.isNative(&resolved_target, &b.graph.host.result)) continue;

        if (self.options.skip_freebsd and target.os.tag == .freebsd) continue;
        if (self.options.skip_netbsd and target.os.tag == .netbsd) continue;
        if (self.options.skip_openbsd and target.os.tag == .openbsd) continue;
        if (self.options.skip_windows and target.os.tag == .windows) continue;
        if (self.options.skip_darwin and target.os.tag.isDarwin()) continue;
        if (self.options.skip_linux and target.os.tag == .linux) continue;

        const would_use_llvm = tests.wouldUseLlvm(params.use_llvm, params.target, params.optimize);
        if (self.options.skip_llvm and would_use_llvm) continue;

        const triple_txt = resolved_target.query.zigTriple(b.allocator) catch @panic("OOM");

        if (self.options.test_target_filters.len > 0) {
            for (self.options.test_target_filters) |filter| {
                if (std.mem.find(u8, triple_txt, filter) != null) break;
            } else continue;
        }

        if (self.options.skip_libc and std.os.targetRequiresLibC(target))
            continue;

        for (self.options.optimize_modes) |optimize| {
            if (optimize == params.optimize) break;
        } else return;

        error_traces_cases.addCases(self, params, &resolved_target.result);
    }
}

/// Called from test/error_traces.zig
pub fn addCase(self: *ErrorTrace, case: Case) void {
    const b = self.b;
    const params = case.params;
    const target = case.target;
    const target_query = params.target;

    const triple: ?[]const u8 = if (target_query.isNative()) null else t: {
        break :t target_query.zigTriple(self.b.graph.arena) catch @panic("OOM");
    };

    const error_tracing: bool = tracing: {
        if (params.optimize == .debug) break :tracing true;
        if (params.use_llvm == false) break :tracing true;
        if (params.optimize == .small) break :tracing false;
        for (case.disable_trace_optimized) |disable| {
            const d_arch, const d_os = disable;
            if (target.cpu.arch == d_arch and target.os.tag == d_os) {
                // This particular configuration cannot do error tracing in optimized LLVM builds.
                break :tracing false;
            }
        }
        break :tracing true;
    };

    const backend_string = if (params.use_llvm == true)
        " llvm"
    else if (params.use_llvm == false)
        " selfhosted"
    else
        "";

    const annotated_case_name = b.fmt("check {s} ({s} {t}{s}{s})", .{
        case.name,
        triple orelse "native",
        params.optimize,
        backend_string,
        if (params.use_new_linker == true)
            " new_linker"
        else if (params.use_lld == true)
            " lld"
        else
            "",
    });
    if (self.options.test_filters.len > 0) {
        for (self.options.test_filters) |test_filter| {
            if (mem.find(u8, annotated_case_name, test_filter)) |_| break;
        } else return;
    }

    const write_files = b.addWriteFiles();
    const source_zig = write_files.add("source.zig", case.source);
    const exe = b.addExecutable(.{
        .name = "test",
        .root_module = b.createModule(.{
            .root_source_file = source_zig,
            .optimize = params.optimize,
            .target = .{ .result = target.*, .query = target_query },
            .error_tracing = error_tracing,
            .strip = false,
        }),
        .use_llvm = params.use_llvm,
        .use_lld = params.use_lld,
    });
    exe.use_new_linker = params.use_new_linker;
    exe.bundle_ubsan_rt = false;

    const run = b.addRunArtifact(exe);
    run.skip_foreign_checks = true;
    run.removeEnvironmentVariable("CLICOLOR_FORCE");
    run.setEnvironmentVariable("NO_COLOR", "1");
    run.expectExitCode(1);
    run.expectStdOutEqual("");

    const expected_stderr = switch (error_tracing) {
        true => b.fmt("error: {s}\n{s}\n", .{ case.expect_error, case.expect_trace }),
        false => b.fmt("error: {s}\n", .{case.expect_error}),
    };

    const check_run = b.addRunArtifact(self.convert_exe);
    check_run.skip_foreign_checks = true;
    check_run.setName(annotated_case_name);
    check_run.addFileArg(run.captureStdErr(.{}));
    check_run.expectStdOutEqual(expected_stderr);

    self.step.dependOn(&check_run.step);
}
