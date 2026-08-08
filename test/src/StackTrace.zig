const StackTrace = @This();

const builtin = @import("builtin");

const std = @import("std");
const Step = std.Build.Step;
const OptimizeMode = std.lang.Optimize;
const mem = std.mem;

const stack_traces_cases = @import("../stack_traces.zig");

b: *std.Build,
step: *Step,
test_filters: []const []const u8,
skip_non_native: bool,
convert_exe: *std.Build.Step.Compile,

pub const CaseParameters = struct {
    target: std.Target.Query = .{},
    optimize: std.builtin.OptimizeMode = .debug,
    link_libc: ?bool = null,
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    pie: ?bool = null,
    /// To enable this coverage, one of two things needs to happen:
    /// * The compiler needs to gain the ability to strip only debug info (not symbols)
    /// * `std.Build.Step.ObjCopy` needs to be un-regressed
    strip: ?bool = false,
};

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

const Config = struct {
    params: *const CaseParameters,
    target: *const std.Target,
    name: []const u8,
    source: []const u8,
    /// Whether this test case expects to have unwind tables / frame pointers.
    unwind: enum {
        /// This case assumes that some unwind strategy, safe or unsafe, is available.
        any,
        /// This case assumes that no unwinding strategy is available.
        none,
        /// This case assumes that a safe unwind strategy, like DWARF unwinding, is available.
        safe,
        /// This case assumes that at most, unsafe FP unwinding is available.
        no_safe,
    },
    /// If `true`, the expected exit code is that of the default panic handler, rather than 0.
    expect_panic: bool,
    /// When debug info is not stripped, stdout is expected to **contain** (not equal!) this string.
    expect: []const u8,
    /// When debug info *is* stripped, stdout is expected to **contain** (not equal!) this string.
    expect_strip: []const u8,
};

pub fn addCases(self: *StackTrace) void {
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

        stack_traces_cases.addCases(self, params, &resolved_target.result);
    }
}

/// Called from test/stack_traces.zig
pub fn addCase(self: *StackTrace, config: Config) void {
    const params = config.params;
    const target = config.target;
    const target_query = config.params.target;

    const triple: ?[]const u8 = if (target_query.isNative()) null else t: {
        break :t target_query.zigTriple(self.b.graph.arena) catch @panic("OOM");
    };

    // See `std.debug.StackIterator.fp_usability` logic.
    const fp_usability: enum { useless, unsafe, safe, ideal } = switch (target.cpu.arch) {
        .alpha,
        .csky,
        .microblaze,
        .microblazeel,
        .mips,
        .mipsel,
        .mips64,
        .mips64el,
        .sh,
        .sheb,
        .xtensa,
        .xtensaeb,
        => .useless,
        .hexagon,
        .powerpc,
        .powerpcle,
        .powerpc64,
        .powerpc64le,
        .sparc,
        .sparc64,
        => .ideal,
        .aarch64 => if (target.os.tag.isDarwin()) .safe else .unsafe,
        else => .unsafe,
    };
    const supports_unwind_tables = switch (target.os.tag) {
        // x86-windows just has no way to do stack unwinding other then using frame pointers.
        .windows => target.cpu.arch != .x86,
        else => true,
    };

    const UnwindInfo = packed struct(u2) {
        tables: bool,
        fp: bool,
        const none: @This() = .{ .tables = false, .fp = false };
        const both: @This() = .{ .tables = true, .fp = true };
        const only_tables: @This() = .{ .tables = true, .fp = false };
        const only_fp: @This() = .{ .tables = false, .fp = true };
    };
    const unwind_info_vals: []const UnwindInfo = switch (config.unwind) {
        .none => switch (fp_usability) {
            .useless => &.{ .none, .only_fp },
            .unsafe, .safe => &.{.none},
            .ideal => &.{},
        },
        .any => switch (fp_usability) {
            .useless => &.{ .only_tables, .both },
            .unsafe, .safe, .ideal => &.{ .only_tables, .only_fp, .both },
        },
        .safe => switch (fp_usability) {
            .useless, .unsafe => &.{ .only_tables, .both },
            .safe, .ideal => &.{ .only_tables, .only_fp, .both },
        },
        .no_safe => switch (fp_usability) {
            .useless, .unsafe => &.{ .none, .only_fp },
            .safe => &.{.none},
            .ideal => &.{},
        },
    };

    for (unwind_info_vals) |unwind_info| {
        if (unwind_info.tables and !supports_unwind_tables) continue;
        const strip = params.strip orelse switch (params.optimize) {
            .debug, .fast, .safe => false,
            .small => true,
        };
        self.addCaseInstance(
            .{ .result = target.*, .query = target_query },
            triple,
            config.name,
            config.source,
            params,
            !unwind_info.tables and supports_unwind_tables,
            !unwind_info.fp,
            config.expect_panic,
            if (strip) config.expect_strip else config.expect,
        );
    }
}

fn addCaseInstance(
    self: *StackTrace,
    resolved_target: std.Build.ResolvedTarget,
    triple: ?[]const u8,
    name: []const u8,
    source: []const u8,
    params: *const CaseParameters,
    strip_unwind: bool,
    omit_frame_pointer: bool,
    expect_panic: bool,
    expect_stderr: []const u8,
) void {
    const b = self.b;

    if (strip_unwind) {
        // To enable this coverage, `std.Build.Step.ObjCopy` needs to be un-regressed and gain the
        // ability to remove individual sections. `-fno-unwind-tables` is insufficient because it
        // does not prevent `.debug_frame` from being emitted. If we could, we would remove the
        // following sections:
        // * `.eh_frame`, `.eh_frame_hdr`, `.debug_frame` (Linux)
        // * `__TEXT,__eh_frame`, `__TEXT,__unwind_info` (macOS)
        return;
    }

    const backend_string = if (params.use_llvm == true)
        " llvm"
    else if (params.use_llvm == false)
        " selfhosted"
    else
        "";

    const strip_string = if (params.strip == true)
        " strip"
    else if (params.strip == false)
        " unstripped"
    else
        "";

    const annotated_case_name = b.fmt("check {s} ({s}{s}{s}{s}{s}{s}{s}{s})", .{
        name,
        triple orelse "",
        if (triple != null) " " else "",
        backend_string,
        if (params.pie == true) " pie" else "",
        if (params.link_libc == true) " libc" else "",
        strip_string,
        if (strip_unwind) " no_unwind" else "",
        if (omit_frame_pointer) " no_fp" else "",
    });
    if (self.test_filters.len > 0) {
        for (self.test_filters) |test_filter| {
            if (mem.find(u8, annotated_case_name, test_filter)) |_| break;
        } else return;
    }

    const write_files = b.addWriteFiles();
    const source_zig = write_files.add("source.zig", source);
    const exe = b.addExecutable(.{
        .name = "test",
        .root_module = b.createModule(.{
            .root_source_file = source_zig,
            .optimize = .Debug,
            .target = resolved_target,
            .omit_frame_pointer = omit_frame_pointer,
            .link_libc = params.link_libc,
            .unwind_tables = if (strip_unwind) .none else null,
            // make panics single-threaded so that they don't include a thread ID
            .single_threaded = expect_panic,
        }),
        .use_llvm = params.use_llvm,
        .use_lld = params.use_lld,
    });
    exe.pie = params.pie;
    exe.bundle_ubsan_rt = false;

    const run = b.addRunArtifact(exe);
    run.skip_foreign_checks = true;
    run.removeEnvironmentVariable("CLICOLOR_FORCE");
    run.setEnvironmentVariable("NO_COLOR", "1");
    run.addCheck(.{ .expect_term = term: {
        if (!expect_panic) break :term .{ .exited = 0 };
        if (resolved_target.result.os.tag == .windows) break :term .{ .exited = 3 };
        break :term .{ .signal = @fromBackingInt(@intCast(6)) };
    } });
    run.expectStdOutEqual("");

    const check_run = b.addRunArtifact(self.convert_exe);
    check_run.setName(annotated_case_name);
    check_run.addFileArg(run.captureStdErr(.{}));
    check_run.expectExitCode(0);
    check_run.addCheck(.{ .expect_stdout_match = expect_stderr });

    self.step.dependOn(&check_run.step);
}
