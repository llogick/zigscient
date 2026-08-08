const ErrorTrace = @This();

const builtin = @import("builtin");

const std = @import("std");
const Step = std.Build.Step;
const OptimizeMode = std.lang.Optimize;
const mem = std.mem;

const error_traces_cases = @import("../error_traces.zig");

b: *std.Build,
step: *Step,
test_filters: []const []const u8,
skip_non_native: bool,
optimize_modes: []const OptimizeMode,
convert_exe: *std.Build.Step.Compile,

pub const CaseParameters = @import("StackTrace.zig").CaseParameters;

const param_sets = [_]CaseParameters{
    .{},
    .{
        .link_libc = true,
    },
    .{
        .use_llvm = true,
        .use_lld = true,
    },
    .{
        .pie = true,
    },
    .{
        .target = .{
            .cpu_arch = .aarch64,
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
    .{
        .target = .{
            .cpu_arch = .x86,
            .os_tag = .windows,
            .abi = .msvc,
        },
    },
    .{
        .target = .{
            .cpu_arch = .aarch64,
            .os_tag = .macos,
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
            .cpu_arch = .loongarch32,
            .os_tag = .linux,
            .abi = .none,
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

        if (self.skip_non_native and !resolved_target.query.isNative()) continue;

        // To avoid redundant testing, skip cross-compilation targets matching the host.
        if (resolved_target.result.os.tag == builtin.target.os.tag and
            resolved_target.result.cpu.arch == builtin.target.cpu.arch)
        {
            continue;
        }

        for (self.optimize_modes) |optimize| {
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
        "-llvm"
    else if (params.use_llvm == false)
        "-selfhosted"
    else
        "";

    const annotated_case_name = b.fmt("check {s} ({s}{s}{t}{s})", .{
        case.name,
        triple orelse "",
        if (triple != null) " " else "",
        params.optimize,
        backend_string,
    });
    if (self.test_filters.len > 0) {
        for (self.test_filters) |test_filter| {
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
