const std = @import("std");
const builtin = @import("builtin");

/// Must match the `version` in `build.zig.zon`.
/// Remove `.pre` when tagging a new release and add it back on the next development cycle.
const proj_version: std.SemanticVersion = .{
    .major = 0,
    .minor = 14,
    .patch = 0,
    .pre = "dev",
};

/// Specify the minimum Zig version that is required to compile and test the project:
/// Must match the `minimum_zig_version` in `build.zig.zon`.
/// Breaking change summary: std.ArrayList: popOrNull() -> pop() [v2] (#22720)
const minimum_build_zig_version = "0.14.0-dev.3181+914248237";

/// Specify the minimum Zig version that is required to run the project:
/// Release 0.12.0
///
/// Examples of reasons that would cause the minimum runtime version to be bumped are:
///   - breaking change to the Zig Syntax
///   - breaking change to AstGen (i.e `zig ast-check`)
///
/// A breaking change to the Zig Build System should be handled by updating the build runner (see src\build_runner)
const minimum_runtime_zig_version = "0.12.0";

const release_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .windows },
    .{ .cpu_arch = .x86_64, .os_tag = .linux },
    .{ .cpu_arch = .x86_64, .os_tag = .macos },
    .{ .cpu_arch = .x86, .os_tag = .windows },
    .{ .cpu_arch = .x86, .os_tag = .linux },
    .{ .cpu_arch = .aarch64, .os_tag = .linux },
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

const MemAllocatorOption = enum { debug, binned, smp, c };

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const single_threaded = b.option(
        bool,
        "single-threaded",
        "Build a single threaded Executable",
    );
    const pie = b.option(
        bool,
        "pie",
        "Build a Position Independent Executable",
    );
    const enable_tracy = b.option(
        bool,
        "enable_tracy",
        "Whether tracy should be enabled.",
    ) orelse false;
    const enable_tracy_allocation = b.option(
        bool,
        "enable_tracy_allocation",
        "Enable using TracyAllocator to monitor allocations.",
    ) orelse enable_tracy;
    const enable_tracy_callstack = b.option(
        bool,
        "enable_tracy_callstack",
        "Enable callstack graphs.",
    ) orelse enable_tracy;
    const test_filters = b.option(
        []const []const u8,
        "test-filter",
        "Skip tests that do not match filter",
    ) orelse &[0][]const u8{};
    const use_llvm = b.option(
        bool,
        "use-llvm",
        "Use Zig's llvm code backend",
    );
    const mem_allocator_opt: MemAllocatorOption = b.option(
        MemAllocatorOption,
        "allocator",
        "Memory allocator to use",
    ) orelse switch (optimize) {
        .Debug => .debug,
        .ReleaseSmall,
        .ReleaseSafe,
        => .binned,
        .ReleaseFast => .smp,
    };
    const coverage_opt = b.option(
        bool,
        "coverage",
        "Generate a coverage report with kcov",
    ) orelse false;

    const resolved_proj_version = getVersion(b);
    const resolved_proj_version_string = b.fmt(
        "{}",
        .{resolved_proj_version},
    );

    const build_options_module = blk: {
        const build_options = b.addOptions();
        build_options.step.name = "Build Options";

        build_options.addOption(
            std.SemanticVersion,
            "version",
            resolved_proj_version,
        );
        build_options.addOption(
            []const u8,
            "version_string",
            resolved_proj_version_string,
        );
        build_options.addOption(
            []const u8,
            "minimum_runtime_zig_version_string",
            minimum_runtime_zig_version,
        );

        break :blk build_options.createModule();
    };

    const exe_options_module = blk: {
        const exe_options = b.addOptions();
        exe_options.step.name = "Exe Options";

        exe_options.addOption(
            bool,
            "enable_failing_allocator",
            b.option(
                bool,
                "enable_failing_allocator",
                "Whether to use a randomly failing allocator.",
            ) orelse false,
        );
        exe_options.addOption(
            u32,
            "enable_failing_allocator_likelihood",
            b.option(
                u32,
                "enable_failing_allocator_likelihood",
                "The chance that an allocation will fail is `1/likelihood`",
            ) orelse 256,
        );
        exe_options.addOption(
            MemAllocatorOption,
            "mema",
            mem_allocator_opt,
        );

        break :blk exe_options.createModule();
    };

    const test_options_module = blk: {
        const test_options = b.addOptions();
        test_options.step.name = "Tests Options";

        test_options.addOption(
            []const u8,
            "zig_exe_path",
            b.graph.zig_exe,
        );
        test_options.addOption(
            []const u8,
            "zig_lib_path",
            b.graph.zig_lib_directory.path.?,
        );
        test_options.addOption(
            []const u8,
            "global_cache_path",
            b.graph.global_cache_root.join(
                b.allocator,
                &.{"zigscient"},
            ) catch @panic("OOM"),
        );

        break :blk test_options.createModule();
    };

    const known_folders_module = b.dependency(
        "known_folders",
        .{
            .target = target,
            .optimize = optimize,
        },
    ).module("known-folders");

    const diffz_module = b.dependency(
        "diffz",
        .{
            .target = target,
            .optimize = optimize,
        },
    ).module("diffz");

    const lsp_module = b.dependency(
        "lsp-codegen",
        .{
            .target = target,
            .optimize = optimize,
        },
    ).module("lsp");

    const tracy_module = getTracyModule(b, .{
        .target = target,
        .optimize = optimize,
        .enable = enable_tracy,
        .enable_allocation = enable_tracy_allocation,
        .enable_callstack = enable_tracy_callstack,
    });

    const gen_exe = b.addExecutable(.{
        .name = "cfg_gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tools/config_gen.zig"),
            .target = b.graph.host,
            .single_threaded = true,
        }),
    });

    const version_data_module = blk: {
        const gen_version_data_cmd = b.addRunArtifact(gen_exe);
        const version = if (proj_version.pre == null and proj_version.build == null) b.fmt("{}", .{proj_version}) else "master";
        gen_version_data_cmd.addArgs(&.{ "--langref-version", version });

        gen_version_data_cmd.addArg("--langref-path");
        gen_version_data_cmd.addFileArg(b.path(b.fmt("src/tools/langref_{s}.html.in", .{version})));

        gen_version_data_cmd.addArg("--generate-version-data");
        const version_data_path = gen_version_data_cmd.addOutputFileArg("version_data.zig");

        break :blk b.addModule("version_data", .{ .root_source_file = version_data_path });
    };

    { // zig build gen
        const gen_step = b.step("gen", "Regenerate config files");

        const gen_cmd = b.addRunArtifact(gen_exe);
        if (b.args) |args| {
            gen_cmd.addArgs(args);
            gen_step.dependOn(&gen_cmd.step);
        } else {
            const update_source = b.addUpdateSourceFiles();
            gen_cmd.addArg("--generate-config");
            update_source.addCopyFileToSource(gen_cmd.addOutputFileArg("Config.zig"), "src/Config.zig");
            gen_cmd.addArg("--generate-schema");
            update_source.addCopyFileToSource(gen_cmd.addOutputFileArg("schema.json"), "schema.json");
            gen_step.dependOn(&update_source.step);
        }
    }

    const zls_module = b.addModule("zls", .{
        .root_source_file = b.path("src/zls.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = single_threaded,
        .pic = pie,
        .imports = &.{
            .{ .name = "known-folders", .module = known_folders_module },
            .{ .name = "diffz", .module = diffz_module },
            .{ .name = "lsp", .module = lsp_module },
            .{ .name = "tracy", .module = tracy_module },
            .{ .name = "build_options", .module = build_options_module },
            .{ .name = "version_data", .module = version_data_module },
        },
    });

    const exe_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = single_threaded,
        .pic = pie,
        .imports = &.{
            .{ .name = "exe_options", .module = exe_options_module },
            .{ .name = "known-folders", .module = known_folders_module },
            .{ .name = "tracy", .module = tracy_module },
            .{ .name = "zls", .module = zls_module },
        },
    });

    { // zig build check
        const exe_check = b.addExecutable(.{
            .name = "check",
            .root_module = exe_module,
        });

        const check = b.step("check", "Check if the project compiles");
        check.dependOn(&exe_check.step);
    }

    { // zig build
        const exe = b.addExecutable(.{
            .name = "zigscient",
            .root_module = exe_module,
            .use_llvm = use_llvm,
            .use_lld = use_llvm,
        });
        if (mem_allocator_opt == .c) exe.linkLibC();
        b.installArtifact(exe);
    }

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/tests.zig"),
            .target = target,
            .optimize = optimize,
            .single_threaded = single_threaded,
            .pic = pie,
            .imports = &.{
                .{ .name = "zls", .module = zls_module },
                .{ .name = "test_options", .module = test_options_module },
            },
        }),
        .filters = test_filters,
        .use_llvm = use_llvm,
        .use_lld = use_llvm,
    });

    const src_tests = b.addTest(.{
        .name = "src test",
        .root_module = zls_module,
        .filters = test_filters,
        .use_llvm = use_llvm,
        .use_lld = use_llvm,
    });

    blk: { // zig build test, zig build test-build-runner, zig build test-analysis
        const test_step = b.step("test", "Run all the tests");
        // const test_build_runner_step = b.step("test-build-runner", "Run all the build runner tests");
        const test_analysis_step = b.step("test-analysis", "Run all the analysis tests");

        // Create run steps
        // @import("tests/add_build_runner_cases.zig").addCases(b, test_build_runner_step, test_filters);
        @import("tests/add_analysis_cases.zig").addCases(b, test_analysis_step, test_filters);

        const run_tests = b.addRunArtifact(tests);
        const run_src_tests = b.addRunArtifact(src_tests);

        // Setup dependencies of `zig build test`
        test_step.dependOn(&run_tests.step);
        test_step.dependOn(&run_src_tests.step);
        // test_step.dependOn(test_build_runner_step);
        test_step.dependOn(test_analysis_step);

        if (!coverage_opt) break :blk;

        // Collect all run steps into one ArrayList
        var run_test_steps: std.ArrayListUnmanaged(*std.Build.Step.Run) = .empty;
        run_test_steps.append(b.allocator, run_tests) catch @panic("OOM");
        run_test_steps.append(b.allocator, run_src_tests) catch @panic("OOM");
        // for (test_build_runner_step.dependencies.items) |step| {
        //     run_test_steps.append(b.allocator, step.cast(std.Build.Step.Run).?) catch @panic("OOM");
        // }
        for (test_analysis_step.dependencies.items) |step| {
            run_test_steps.append(b.allocator, step.cast(std.Build.Step.Run).?) catch @panic("OOM");
        }

        const kcov_bin = b.findProgram(&.{"kcov"}, &.{}) catch "kcov";

        const merge_step = std.Build.Step.Run.create(b, "merge coverage");
        merge_step.addArgs(&.{ kcov_bin, "--merge" });
        merge_step.rename_step_with_output_arg = false;
        const merged_coverage_output = merge_step.addOutputFileArg(".");

        for (run_test_steps.items) |run_step| {
            run_step.setName(b.fmt("{s} (collect coverage)", .{run_step.step.name}));

            // prepend the kcov exec args
            const argv = run_step.argv.toOwnedSlice(b.allocator) catch @panic("OOM");
            run_step.addArgs(&.{ kcov_bin, "--collect-only" });
            run_step.addPrefixedDirectoryArg("--include-pattern=", b.path("src"));
            merge_step.addDirectoryArg(run_step.addOutputFileArg(run_step.producer.?.name));
            run_step.argv.appendSlice(b.allocator, argv) catch @panic("OOM");
        }

        const install_coverage = b.addInstallDirectory(.{
            .source_dir = merged_coverage_output,
            .install_dir = .{ .custom = "coverage" },
            .install_subdir = "",
        });
        test_step.dependOn(&install_coverage.step);
    }
}

/// Returns `MAJOR.MINOR.PATCH-dev` when `git describe` failed.
fn getVersion(b: *Build) std.SemanticVersion {
    if (proj_version.pre == null and proj_version.build == null) return proj_version;

    var code: u8 = undefined;
    const git_describe_untrimmed = b.runAllowFail(
        &.{ "git", "-C", b.pathFromRoot("."), "describe", "--match", "*.*.0", "--tags" },
        &code,
        .Ignore,
    ) catch return proj_version;

    const git_describe = std.mem.trim(u8, git_describe_untrimmed, " \n\r");

    switch (std.mem.count(u8, git_describe, "-")) {
        0 => {
            // Tagged release version (e.g. 0.10.0).
            std.debug.assert(std.mem.eql(u8, git_describe, b.fmt("{}", .{proj_version}))); // tagged release must match version string
            return proj_version;
        },
        2 => {
            // Untagged development build (e.g. 0.10.0-dev.216+34ce200).
            var it = std.mem.splitScalar(u8, git_describe, '-');
            const tagged_ancestor = it.first();
            const commit_height = it.next().?;
            const commit_id = it.next().?;

            const ancestor_ver = std.SemanticVersion.parse(tagged_ancestor) catch unreachable;
            std.debug.assert(proj_version.order(ancestor_ver) == .gt); // version must be greater than its previous version
            std.debug.assert(std.mem.startsWith(u8, commit_id, "g")); // commit hash is prefixed with a 'g'

            return std.SemanticVersion{
                .major = proj_version.major,
                .minor = proj_version.minor,
                .patch = proj_version.patch,
                .pre = b.fmt("dev.{s}", .{commit_height}),
                .build = commit_id[1..],
            };
        },
        else => {
            std.debug.print("Unexpected 'git describe' output: '{s}'\n", .{git_describe});
            std.process.exit(1);
        },
    }
}

fn getTracyModule(
    b: *Build,
    options: struct {
        target: Build.ResolvedTarget,
        optimize: std.builtin.OptimizeMode,
        enable: bool,
        enable_allocation: bool,
        enable_callstack: bool,
    },
) *Build.Module {
    const tracy_options = b.addOptions();
    tracy_options.step.name = "tracy options";
    tracy_options.addOption(bool, "enable", options.enable);
    tracy_options.addOption(bool, "enable_allocation", options.enable and options.enable_allocation);
    tracy_options.addOption(bool, "enable_callstack", options.enable and options.enable_callstack);

    const tracy_module = b.addModule("tracy", .{
        .root_source_file = b.path("src/tracy.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    tracy_module.addImport("options", tracy_options.createModule());
    if (!options.enable) return tracy_module;
    const tracy_dependency = b.lazyDependency("tracy", .{}) orelse return tracy_module;

    tracy_module.link_libc = true;
    tracy_module.link_libcpp = true;

    // On mingw, we need to opt into windows 7+ to get some features required by tracy.
    const tracy_c_flags: []const []const u8 = if (options.target.result.isMinGW())
        &[_][]const u8{ "-DTRACY_ENABLE=1", "-fno-sanitize=undefined", "-D_WIN32_WINNT=0x601" }
    else
        &[_][]const u8{ "-DTRACY_ENABLE=1", "-fno-sanitize=undefined" };

    tracy_module.addIncludePath(tracy_dependency.path(""));
    tracy_module.addCSourceFile(.{
        .file = tracy_dependency.path("public/TracyClient.cpp"),
        .flags = tracy_c_flags,
    });

    if (options.target.result.os.tag == .windows) {
        tracy_module.linkSystemLibrary("dbghelp", .{});
        tracy_module.linkSystemLibrary("ws2_32", .{});
    }

    return tracy_module;
}

const Build = blk: {
    const min_build_zig = std.SemanticVersion.parse(minimum_build_zig_version) catch unreachable;
    const min_runtime_zig = std.SemanticVersion.parse(minimum_runtime_zig_version) catch unreachable;

    std.debug.assert(proj_version.pre == null or std.mem.eql(u8, proj_version.pre.?, "dev"));
    std.debug.assert(proj_version.build == null);
    const proj_version_is_tagged = proj_version.pre == null and proj_version.build == null;

    if (min_runtime_zig.order(min_build_zig) == .gt) {
        const message = std.fmt.comptimePrint(
            \\The minimum runtime Zig version must be less or equal to the minimum build Zig version:
            \\  minimum build   Zig version: {[min_build_zig]}
            \\  minimum runtime Zig version: {[min_runtime_zig]}
            \\
            \\This is a developer error.
        , .{ .min_build_zig = min_build_zig, .min_runtime_zig = min_runtime_zig });
        @compileError(message);
    }

    // check that the project version and minimum build version make sense
    if (proj_version_is_tagged) {
        if (proj_version.order(min_build_zig) != .eq) {
            const message = std.fmt.comptimePrint(
                \\A tagged release should have the same tagged release of Zig as the minimum build requirement:
                \\          Project version: {[current_version]}
                \\  minimum Zig     version: {[minimum_version]}
                \\
                \\This is a developer error. Set `minimum_build_zig_version` in `build.zig` and `minimum_zig_version` in `build.zig.zon` to {[current_version]}.
            , .{ .current_version = proj_version, .minimum_version = min_build_zig });
            @compileError(message);
        }
    } else {
        const min_build_zig_simple = std.SemanticVersion{ .major = min_build_zig.major, .minor = min_build_zig.minor, .patch = 0 };
        const proj_version_simple = std.SemanticVersion{ .major = proj_version.major, .minor = proj_version.minor, .patch = 0 };
        const min_zig_is_tagged = min_build_zig.build == null and min_build_zig.pre == null;
        if (!min_zig_is_tagged and proj_version_simple.order(min_build_zig_simple) != .eq) {
            const message = std.fmt.comptimePrint(
                \\A development build should have a tagged release of Zig as the minimum build requirement or
                \\have a development build of Zig as the minimum build requirement with the same major and minor version.
                \\          Project version: {d}.{d}.*
                \\  minimum Zig     version: {}
                \\
                \\
                \\This is a developer error.
            , .{ proj_version.major, proj_version.minor, min_build_zig });
            @compileError(message);
        }
    }

    // check minimum build version
    const is_current_zig_tagged_release = builtin.zig_version.pre == null and builtin.zig_version.build == null;
    const is_min_build_zig_tagged_release = min_build_zig.pre == null and min_build_zig.build == null;
    const min_build_zig_simple = std.SemanticVersion{ .major = min_build_zig.major, .minor = min_build_zig.minor, .patch = 0 };
    const current_zig_simple = std.SemanticVersion{ .major = builtin.zig_version.major, .minor = builtin.zig_version.minor, .patch = 0 };
    if (switch (builtin.zig_version.order(min_build_zig)) {
        .lt => true,
        .eq => false,
        .gt => (is_current_zig_tagged_release and !is_min_build_zig_tagged_release) or
            // a tagged release of the project must be built with a tagged release of Zig that has the same major and minor version.
            (proj_version_is_tagged and (min_build_zig_simple.order(current_zig_simple) != .eq)),
    }) {
        const message = std.fmt.comptimePrint(
            \\Your Zig version does not meet the minimum build requirement:
            \\  required Zig version: {[minimum_version]} {[required_zig_version_note]s}
            \\  actual   Zig version: {[current_version]}
            \\
            \\
        ++ if (is_min_build_zig_tagged_release)
            std.fmt.comptimePrint(
                \\Please download the {[minimum_version]} release of Zig. (https://ziglang.org/download/)
            , .{
                .minimum_version = min_build_zig,
                .minimum_version_simple = min_build_zig_simple,
            })
        else if (is_current_zig_tagged_release)
            \\Please download or compile a tagged release of this project.
        else
            \\You can take one of the following actions to resolve this issue:
            \\  - Download the latest nightly of Zig (https://ziglang.org/download/)
            \\  - Compile an older version of this project that is compatible with your Zig version
        , .{
            .current_version = builtin.zig_version,
            .minimum_version = min_build_zig,
            .required_zig_version_note = if (!proj_version_is_tagged) "(or greater)" else "",
        });
        @compileError(message);
    }
    break :blk std.Build;
};
