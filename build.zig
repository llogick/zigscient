const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const assert = std.debug.assert;
const Io = std.Io;

const tests = @import("test/tests.zig");
const DevEnv = @import("src/dev.zig").Env;

const zig_version: std.SemanticVersion = .{ .major = 0, .minor = 17, .patch = 0 };
const stack_size = 46 * 1024 * 1024;

const IoMode = enum { threaded, evented };
const ValueInterpretMode = enum { direct, by_name };

pub fn build(b: *std.Build) !void {
    const arena = b.graph.arena;

    const only_c = b.option(bool, "only-c", "Translate the Zig compiler to C code, with only the C backend enabled") orelse false;
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .ofmt = if (only_c) .c else null,
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    const dev_env: DevEnv = b.option(DevEnv, "dev", "Build a compiler with a reduced feature set for development of specific features") orelse if (only_c) .bootstrap else .lsp_server;

    const flat = b.option(bool, "flat", "Put files into the installation prefix in a manner suited for upstream distribution rather than a posix file system hierarchy standard") orelse false;
    const single_threaded = false; //b.option(bool, "single-threaded", "Build artifacts that run in single threaded mode");
    const use_zig_libcxx = b.option(bool, "use-zig-libcxx", "If libc++ is needed, use zig's bundled version, don't try to integrate with the system") orelse false;

    const test_step = b.step("test-compiler", "Run all compiler tests");
    const skip_install_lib_files = b.option(bool, "no-lib", "skip copying of lib/ files and langref to installation prefix. Useful for development") orelse only_c or dev_env != .full;
    const skip_install_langref = b.option(bool, "no-langref", "skip copying of langref to the installation prefix") orelse skip_install_lib_files;
    const std_docs = b.option(bool, "std-docs", "include standard library autodocs") orelse false;
    const no_bin = b.option(bool, "no-bin", "skip emitting compiler binary") orelse false;
    const enable_superhtml = b.option(bool, "enable-superhtml", "Check langref output HTML validity") orelse false;

    const langref_file = try generateLangRef(b);
    const install_langref = b.addInstallFileWithDir(langref_file, .prefix, "doc/langref.html");
    const check_langref = superHtmlCheck(b, langref_file);
    if (enable_superhtml) install_langref.step.dependOn(check_langref);

    const check_autodocs = superHtmlCheck(b, b.path("lib/docs/index.html"));
    if (enable_superhtml) {
        test_step.dependOn(check_langref);
        test_step.dependOn(check_autodocs);
    }
    if (!skip_install_langref) {
        b.getInstallStep().dependOn(&install_langref.step);
    }

    const autodoc_test = b.addObject(.{
        .name = "std",
        .zig_lib_dir = b.path("lib"),
        .root_module = b.createModule(.{
            .root_source_file = b.path("lib/std/std.zig"),
            .target = target,
            .optimize = .Debug,
        }),
    });
    const install_std_docs = b.addInstallDirectory(.{
        .source_dir = autodoc_test.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "doc/std",
    });
    //if (enable_tidy) install_std_docs.step.dependOn(check_autodocs);
    if (std_docs) {
        b.getInstallStep().dependOn(&install_std_docs.step);
    }

    if (flat) {
        b.installFile("LICENSE", "LICENSE");
        b.installFile("README.md", "README.md");
    }

    const langref_step = b.step("langref", "Build and install the language reference");
    langref_step.dependOn(&install_langref.step);

    const std_docs_step = b.step("std-docs", "Build and install the standard library documentation");
    std_docs_step.dependOn(&install_std_docs.step);

    const docs_step = b.step("docs", "Build and install documentation");
    docs_step.dependOn(langref_step);
    docs_step.dependOn(std_docs_step);

    const no_matrix = b.option(bool, "no-matrix", "Limit test matrix to exactly one target configuration") orelse false;
    const fuzz_only = b.option(bool, "fuzz-only", "Limit test matrix to one target suitable for fuzzing") orelse false;
    const skip_debug = b.option(bool, "skip-debug", "Main test suite skips debug builds") orelse false;
    const skip_release = b.option(bool, "skip-release", "Main test suite skips release builds") orelse no_matrix;
    const skip_release_small = b.option(bool, "skip-release-small", "Main test suite skips release-small builds") orelse skip_release;
    const skip_release_fast = b.option(bool, "skip-release-fast", "Main test suite skips release-fast builds") orelse skip_release;
    const skip_release_safe = b.option(bool, "skip-release-safe", "Main test suite skips release-safe builds") orelse skip_release;
    const skip_non_native = b.option(bool, "skip-non-native", "Main test suite skips non-native builds") orelse no_matrix;
    const skip_libc = b.option(bool, "skip-libc", "Main test suite skips tests that link libc") orelse false;
    const skip_single_threaded = b.option(bool, "skip-single-threaded", "Main test suite skips tests that are single-threaded") orelse false;
    const skip_compile_errors = b.option(bool, "skip-compile-errors", "Main test suite skips compile error tests") orelse false;
    const skip_spirv = b.option(bool, "skip-spirv", "Main test suite skips targets with spirv32/spirv64 architecture") orelse false;
    const skip_wasm = b.option(bool, "skip-wasm", "Main test suite skips targets with wasm32/wasm64 architecture") orelse false;
    const skip_freebsd = b.option(bool, "skip-freebsd", "Main test suite skips targets with freebsd OS") orelse false;
    const skip_netbsd = b.option(bool, "skip-netbsd", "Main test suite skips targets with netbsd OS") orelse false;
    const skip_openbsd = b.option(bool, "skip-openbsd", "Main test suite skips targets with openbsd OS") orelse false;
    const skip_windows = b.option(bool, "skip-windows", "Main test suite skips targets with windows OS") orelse false;
    const skip_darwin = b.option(bool, "skip-darwin", "Main test suite skips targets with darwin OSs") orelse false;
    const skip_linux = b.option(bool, "skip-linux", "Main test suite skips targets with linux OS") orelse false;
    const skip_llvm = b.option(bool, "skip-llvm", "Main test suite skips targets that use LLVM backend") orelse false;
    const skip_test_incremental = b.option(bool, "skip-test-incremental", "Main test step omits dependency on test-incremental step") orelse false;

    const only_install_lib_files = b.option(bool, "lib-files-only", "Only install library files") orelse false;

    const static_llvm = b.option(bool, "static-llvm", "Disable integration with system-installed LLVM, Clang, LLD, and libc++") orelse false;
    const enable_llvm = b.option(bool, "enable-llvm", "Build self-hosted compiler with LLVM backend enabled") orelse static_llvm;
    const llvm_has_m68k = b.option(
        bool,
        "llvm-has-m68k",
        "Whether LLVM has the experimental target m68k enabled",
    ) orelse false;
    const llvm_has_csky = b.option(
        bool,
        "llvm-has-csky",
        "Whether LLVM has the experimental target csky enabled",
    ) orelse false;
    const llvm_has_arc = b.option(
        bool,
        "llvm-has-arc",
        "Whether LLVM has the experimental target arc enabled",
    ) orelse false;
    const llvm_has_xtensa = b.option(
        bool,
        "llvm-has-xtensa",
        "Whether LLVM has the experimental target xtensa enabled",
    ) orelse false;
    const enable_ios_sdk = b.option(bool, "enable-ios-sdk", "Run tests requiring presence of iOS SDK and frameworks") orelse false;
    const enable_macos_sdk = b.option(bool, "enable-macos-sdk", "Run tests requiring presence of macOS SDK and frameworks") orelse enable_ios_sdk;
    const enable_symlinks_windows = b.option(bool, "enable-symlinks-windows", "Run tests requiring presence of symlinks on Windows") orelse false;
    const config_h_path_option = b.option([]const u8, "config_h", "Path to the generated config.h");

    if (!skip_install_lib_files) {
        b.installDirectory(.{
            .source_dir = b.path("lib"),
            .install_dir = if (flat) .prefix else .lib,
            .install_subdir = if (flat) "lib" else "zigscient",
            .exclude_extensions = &[_][]const u8{
                // exclude files from lib/std/compress/flate/testdata
                ".expect",
                ".input",
                // exclude files from lib/std/compress/lzma/testdata
                ".lzma",
                // exclude files from lib/std/compress/xz/testdata
                ".xz",
                // exclude files from lib/std/tz/
                ".tzif",
                // exclude files from lib/std/tar/testdata
                ".tar",
                // others
                "README.md",
            },
            .blank_extensions = &[_][]const u8{
                "test.zig",
            },
        });
    }

    if (only_install_lib_files)
        return;

    const entitlements = b.option([]const u8, "entitlements", "Path to entitlements file for hot-code swapping without sudo on macOS");
    const tracy = b.option(std.Build.LazyPath, "tracy", "Enable Tracy integration. Supply path to Tracy source");
    const tracy_callstack = b.option(bool, "tracy-callstack", "Include callstack information with Tracy data. Does nothing if -Dtracy is not provided. Has a significant performance impact in some cases. Default: false") orelse false;
    const tracy_allocation = b.option(bool, "tracy-allocation", "Include allocation information with Tracy data. Does nothing if -Dtracy is not provided. Default: true") orelse (tracy != null);
    const tracy_callstack_depth: u32 = b.option(u32, "tracy-callstack-depth", "Declare callstack depth for Tracy data. Does nothing if -Dtracy-callstack is not provided") orelse 6;
    const debug_gpa = b.option(bool, "debug-allocator", "Force the compiler to use SafeAllocator") orelse false;
    const link_libc = b.option(bool, "force-link-libc", "Force self-hosted compiler to link libc") orelse (enable_llvm or only_c);
    const sanitize_thread = b.option(bool, "sanitize-thread", "Enable thread-sanitization") orelse false;
    const strip = b.option(bool, "strip", "Omit debug information");
    const valgrind = b.option(bool, "valgrind", "Enable valgrind integration");
    const pie = b.option(bool, "pie", "Produce a Position Independent Executable");
    const io_mode = b.option(IoMode, "io-mode", "How the compiler performs IO") orelse .threaded;
    const value_interpret_mode = b.option(ValueInterpretMode, "value-interpret-mode", "How the compiler translates between 'std.lang' types and its internal datastructures") orelse .direct;
    const value_tracing = b.option(bool, "value-tracing", "Enable extra state tracking to help troubleshoot bugs in the compiler (using the std.debug.Trace API)") orelse false;

    const mem_leak_frames: u32 = b.option(u32, "mem-leak-frames", "How many stack frames to print when a memory leak occurs. Tests get 2x this amount.") orelse blk: {
        if (strip == true) break :blk @as(u32, 0);
        if (optimize != .Debug) break :blk 0;
        break :blk 12;
    };

    const exe_options = b.addOptions();
    const exe_options_mod = exe_options.createModule();

    const exe = addCompilerStep(b, .{
        .optimize = optimize,
        .target = target,
        .strip = strip,
        .valgrind = valgrind,
        .sanitize_thread = sanitize_thread,
        .single_threaded = single_threaded,
        .exe_options_mod = exe_options_mod,
    });
    exe.pie = pie;
    // https://codeberg.org/ziglang/zig/issues/32173
    exe.entitlements = if (entitlements) |p| .{ .cwd_relative = p } else null;
    exe.use_new_linker = b.option(bool, "new-linker", "Use the new linker");

    const use_llvm = b.option(bool, "use-llvm", "Use the llvm backend");
    exe.use_llvm = use_llvm;
    exe.use_lld = use_llvm;

    const check = b.step("check", "Check if the project compiles");
    check.dependOn(&exe.step);

    if (no_bin) {
        b.getInstallStep().dependOn(&exe.step);
    } else {
        const install_exe = b.addInstallArtifact(exe, .{
            .dest_dir = if (flat) .{ .override = .prefix } else .default,
        });
        b.getInstallStep().dependOn(&install_exe.step);
    }

    test_step.dependOn(&exe.step);

    exe_options.addOption(u32, "mem_leak_frames", mem_leak_frames);
    exe_options.addOption(bool, "have_llvm", enable_llvm);
    exe_options.addOption(bool, "llvm_has_m68k", llvm_has_m68k);
    exe_options.addOption(bool, "llvm_has_csky", llvm_has_csky);
    exe_options.addOption(bool, "llvm_has_arc", llvm_has_arc);
    exe_options.addOption(bool, "llvm_has_xtensa", llvm_has_xtensa);
    exe_options.addOption(bool, "debug_gpa", debug_gpa);
    exe_options.addOption(DevEnv, "dev", dev_env);
    exe_options.addOption(IoMode, "io_mode", io_mode);
    exe_options.addOption(ValueInterpretMode, "value_interpret_mode", value_interpret_mode);

    exe_options.addOption(bool, "enable_failing_allocator", b.option(bool, "enable-failing-allocator", "Whether to use a randomly failing allocator.") orelse false);
    exe_options.addOption(u32, "enable_failing_allocator_likelihood", b.option(u32, "enable-failing-allocator-likelihood", "The chance that an allocation will fail is `1/likelihood`") orelse 256);

    if (link_libc) {
        exe.root_module.link_libc = true;
    }

    const is_debug = optimize == .Debug;
    const enable_debug_extensions = b.option(bool, "debug-extensions", "Enable commands and options useful for debugging the compiler") orelse is_debug;
    const enable_logging = b.option(bool, "log", "Enable debug logging with --debug-log") orelse is_debug;
    const enable_link_snapshots = b.option(bool, "link-snapshot", "Whether to enable linker state snapshots") orelse false;

    const opt_version_string = b.option([]const u8, "version-string", "Override Zig version string. Default is to find out with git.");
    const version_slice = bzz.compiler_internals_version;
    const version = try arena.dupeSentinel(u8, version_slice, 0);
    exe_options.addOption([:0]const u8, "version", version);

    const resolved_proj_version = getVersion(b, opt_version_string);
    exe_options.addOption(std.SemanticVersion, "semantic_version", resolved_proj_version);
    exe_options.addOption([]const u8, "version_string", b.fmt("{f}", .{resolved_proj_version}));
    exe_options.addOption([]const u8, "minimum_runtime_zig_version_string", minimum_runtime_zig_version);

    if (enable_llvm) {
        const cmake_cfg = if (static_llvm) null else blk: {
            const io = b.graph.io;
            const cwd: Io.Dir = .cwd();
            if (findConfigH(b, config_h_path_option)) |config_h_path| {
                const file_contents = cwd.readFileAlloc(io, config_h_path, arena, .limited(max_config_h_bytes)) catch unreachable;
                break :blk parseConfigH(b, file_contents);
            } else {
                std.log.warn("config.h could not be located automatically. Consider providing it explicitly via \"-Dconfig_h\"", .{});
                break :blk null;
            }
        };

        if (cmake_cfg) |cfg| {
            // Inside this code path, we have to coordinate with system packaged LLVM, Clang, and LLD.
            // That means we also have to rely on stage1 compiled c++ files. We parse config.h to find
            // the information passed on to us from cmake.
            if (cfg.cmake_prefix_path.len > 0) {
                var it = mem.tokenizeScalar(u8, cfg.cmake_prefix_path, ';');
                while (it.next()) |path| {
                    b.addSearchPrefix(path);
                }
            }

            try addCmakeCfgOptionsToExe(b, cfg, exe, use_zig_libcxx);
        } else {
            // Here we are -Denable-llvm but no cmake integration.
            try addStaticLlvmOptionsToModule(exe.root_module, .{
                .llvm_has_m68k = llvm_has_m68k,
                .llvm_has_csky = llvm_has_csky,
                .llvm_has_arc = llvm_has_arc,
                .llvm_has_xtensa = llvm_has_xtensa,
            });
        }
        if (target.result.os.tag == .windows) {
            // LLVM depends on networking as of version 18.
            exe.root_module.linkSystemLibrary("ws2_32", .{});

            exe.root_module.linkSystemLibrary("version", .{});
            exe.root_module.linkSystemLibrary("uuid", .{});
            exe.root_module.linkSystemLibrary("ole32", .{});
        }
    }

    const semver = try std.SemanticVersion.parse(version);
    exe_options.addOption(std.SemanticVersion, "semver", semver);

    exe_options.addOption(bool, "enable_debug_extensions", enable_debug_extensions);
    exe_options.addOption(bool, "enable_logging", enable_logging);
    exe_options.addOption(bool, "enable_link_snapshots", enable_link_snapshots);
    exe_options.addOption(bool, "enable_tracy", tracy != null);
    exe_options.addOption(bool, "enable_tracy_callstack", tracy_callstack);
    exe_options.addOption(bool, "enable_tracy_allocation", tracy_allocation);
    exe_options.addOption(u32, "tracy_callstack_depth", tracy_callstack_depth);
    exe_options.addOption(bool, "value_tracing", value_tracing);
    if (tracy) |tracy_dir| {
        const tracy_mod = b.createModule(.{
            .target = target,
            // Always build Tracy in ReleaseFast so that it doesn't make Debug compiler builds unusable.
            .optimize = .ReleaseFast,
            .root_source_file = null,
            .link_libc = true,
            .link_libcpp = true,
        });

        tracy_mod.addCMacro("TRACY_ENABLE", "1");

        if (!tracy_callstack) {
            tracy_mod.addCMacro("TRACY_NO_CALLSTACK", "1");
        }

        tracy_mod.addIncludePath(tracy_dir);
        tracy_mod.addCSourceFile(.{ .file = tracy_dir.path(b, "public/TracyClient.cpp") });

        if (target.result.os.tag == .windows) {
            tracy_mod.linkSystemLibrary("dbghelp", .{});
            tracy_mod.linkSystemLibrary("ws2_32", .{});
        }

        exe.root_module.addImport("tracy", tracy_mod);
    }

    const test_filters = b.option([]const []const u8, "test-filter", "Skip tests that do not match any filter") orelse &[0][]const u8{};
    const test_target_filters = b.option([]const []const u8, "test-target-filter", "Skip tests whose target triple do not match any filter") orelse &[0][]const u8{};
    const test_extra_targets = b.option(bool, "test-extra-targets", "Enable running module tests for additional targets") orelse false;

    cfgLspServer(
        b,
        exe,
        target,
        optimize,
        test_filters,
        single_threaded,
        exe_options_mod,
        use_llvm,
        pie,
    );

    var chosen_opt_modes_buf: [4]std.lang.OptimizeMode = undefined;
    var chosen_mode_index: usize = 0;
    if (!skip_debug) {
        chosen_opt_modes_buf[chosen_mode_index] = .Debug;
        chosen_mode_index += 1;
    }
    if (!skip_release_safe) {
        chosen_opt_modes_buf[chosen_mode_index] = .ReleaseSafe;
        chosen_mode_index += 1;
    }
    if (!skip_release_fast) {
        chosen_opt_modes_buf[chosen_mode_index] = .ReleaseFast;
        chosen_mode_index += 1;
    }
    if (!skip_release_small) {
        chosen_opt_modes_buf[chosen_mode_index] = .ReleaseSmall;
        chosen_mode_index += 1;
    }
    const optimize_modes = chosen_opt_modes_buf[0..chosen_mode_index];

    const test_only: ?tests.ModuleTestOptions.TestOnly = if (no_matrix)
        .default
    else if (fuzz_only)
        .{ .fuzz = optimize }
    else
        null;

    const fmt_include_paths = b.pathList(&.{ "lib", "src", "test", "tools", "build.zig", "build.zig.zon" });
    const fmt_exclude_paths = b.pathList(&.{ "test/cases", "test/behavior/zon" });
    const do_fmt = b.addFmt(.{
        .paths = fmt_include_paths,
        .exclude_paths = fmt_exclude_paths,
    });
    b.step("fmt", "Modify source files in place to have conforming formatting").dependOn(&do_fmt.step);

    const check_fmt = b.step("test-fmt", "Check source files having conforming formatting");
    check_fmt.dependOn(&b.addFmt(.{
        .paths = fmt_include_paths,
        .exclude_paths = fmt_exclude_paths,
        .check = true,
    }).step);
    test_step.dependOn(check_fmt);

    const test_cases_step = b.step("test-cases", "Run the main compiler test cases");
    try tests.addCases(b, test_cases_step, .{
        .test_filters = test_filters,
        .test_target_filters = test_target_filters,
        .skip_compile_errors = skip_compile_errors,
        .skip_non_native = skip_non_native,
        .skip_spirv = skip_spirv,
        .skip_wasm = skip_wasm,
        .skip_freebsd = skip_freebsd,
        .skip_netbsd = skip_netbsd,
        .skip_openbsd = skip_openbsd,
        .skip_windows = skip_windows,
        .skip_darwin = skip_darwin,
        .skip_linux = skip_linux,
        .skip_llvm = skip_llvm,
        .skip_libc = skip_libc,
    }, .{
        .enable_llvm = enable_llvm,
        .llvm_has_m68k = llvm_has_m68k,
        .llvm_has_csky = llvm_has_csky,
        .llvm_has_arc = llvm_has_arc,
        .llvm_has_xtensa = llvm_has_xtensa,
    });
    test_step.dependOn(test_cases_step);

    const test_modules_step = b.step("test-modules", "Run the per-target module tests");
    test_step.dependOn(test_modules_step);

    test_modules_step.dependOn(tests.addModuleTests(b, .{
        .test_filters = test_filters,
        .test_target_filters = test_target_filters,
        .test_extra_targets = test_extra_targets,
        .root_src = "test/behavior.zig",
        .name = "behavior",
        .desc = "Run the behavior tests",
        .optimize_modes = optimize_modes,
        .include_paths = &.{},
        .sanitize_thread = sanitize_thread,
        .skip_single_threaded = skip_single_threaded,
        .skip_non_native = skip_non_native,
        .test_only = test_only,
        .skip_spirv = skip_spirv,
        .skip_wasm = skip_wasm,
        .skip_freebsd = skip_freebsd,
        .skip_netbsd = skip_netbsd,
        .skip_openbsd = skip_openbsd,
        .skip_windows = skip_windows,
        .skip_darwin = skip_darwin,
        .skip_linux = skip_linux,
        .skip_llvm = skip_llvm,
        .skip_libc = skip_libc,
        .max_rss = 4_000_000_000,
    }));

    test_modules_step.dependOn(tests.addModuleTests(b, .{
        .test_filters = test_filters,
        .test_target_filters = test_target_filters,
        .test_extra_targets = test_extra_targets,
        .root_src = "lib/compiler_rt.zig",
        .name = "compiler-rt",
        .desc = "Run the compiler_rt tests",
        .optimize_modes = optimize_modes,
        .include_paths = &.{},
        .sanitize_thread = sanitize_thread,
        .skip_single_threaded = true,
        .skip_non_native = skip_non_native,
        .test_only = test_only,
        .skip_spirv = skip_spirv,
        .skip_wasm = skip_wasm,
        .skip_freebsd = skip_freebsd,
        .skip_netbsd = skip_netbsd,
        .skip_openbsd = skip_openbsd,
        .skip_windows = skip_windows,
        .skip_darwin = skip_darwin,
        .skip_linux = skip_linux,
        .skip_llvm = skip_llvm,
        .skip_libc = true,
        .no_builtin = true,
        .max_rss = 4_000_000_000,
    }));

    test_modules_step.dependOn(tests.addModuleTests(b, .{
        .test_filters = test_filters,
        .test_target_filters = test_target_filters,
        .test_extra_targets = test_extra_targets,
        .root_src = "lib/std/std.zig",
        .name = "std",
        .desc = "Run the standard library tests",
        .optimize_modes = optimize_modes,
        .include_paths = &.{},
        .sanitize_thread = sanitize_thread,
        .skip_single_threaded = skip_single_threaded,
        .skip_non_native = skip_non_native,
        .test_only = test_only,
        .skip_spirv = true,
        .skip_wasm = skip_wasm,
        .skip_freebsd = skip_freebsd,
        .skip_netbsd = skip_netbsd,
        .skip_openbsd = skip_openbsd,
        .skip_windows = skip_windows,
        .skip_darwin = skip_darwin,
        .skip_linux = skip_linux,
        .skip_llvm = skip_llvm,
        .skip_libc = skip_libc,
        .max_rss = 9_300_000_000,
    }));

    test_modules_step.dependOn(tests.addModuleTests(b, .{
        .test_filters = test_filters,
        .test_target_filters = test_target_filters,
        .test_extra_targets = test_extra_targets,
        .root_src = "test/c.zig",
        .name = "libc",
        .desc = "Run the libc API tests",
        .optimize_modes = optimize_modes,
        .include_paths = &.{},
        .sanitize_thread = sanitize_thread,
        .skip_single_threaded = true,
        .skip_non_native = skip_non_native,
        .test_only = test_only,
        .skip_spirv = true,
        .skip_wasm = skip_wasm,
        .skip_freebsd = skip_freebsd,
        .skip_netbsd = skip_netbsd,
        .skip_openbsd = skip_openbsd,
        .skip_windows = skip_windows,
        .skip_darwin = skip_darwin,
        .skip_linux = skip_linux,
        .skip_llvm = skip_llvm,
        .skip_libc = skip_libc,
        .no_builtin = true,
        .max_rss = 4_000_000_000,
    }));

    const unit_tests_step = b.step("test-unit", "Run the compiler source unit tests");
    test_step.dependOn(unit_tests_step);

    const unit_tests = b.addTest(.{
        .root_module = addCompilerMod(b, .{
            .optimize = optimize,
            .target = target,
            .sanitize_thread = sanitize_thread,
            .single_threaded = single_threaded,
            .exe_options_mod = exe_options_mod,
        }),
        .filters = test_filters,
        .use_llvm = use_llvm,
        .use_lld = use_llvm,
        .zig_lib_dir = b.path("lib"),
        .max_rss = 2_700_000_000,
    });
    if (link_libc) {
        unit_tests.root_module.link_libc = true;
    }
    unit_tests.root_module.addOptions("build_options", exe_options);
    unit_tests_step.dependOn(&b.addRunArtifact(unit_tests).step);

    test_step.dependOn(tests.addStandaloneTests(
        b,
        optimize_modes,
        enable_macos_sdk,
        enable_ios_sdk,
        enable_symlinks_windows,
    ));
    test_step.dependOn(tests.addCAbiTests(b, .{
        .test_target_filters = test_target_filters,
        .optimize_modes = optimize_modes,
        .skip_non_native = skip_non_native,
        .skip_wasm = skip_wasm,
        .skip_freebsd = skip_freebsd,
        .skip_netbsd = skip_netbsd,
        .skip_openbsd = skip_openbsd,
        .skip_windows = skip_windows,
        .skip_darwin = skip_darwin,
        .skip_linux = skip_linux,
        .skip_llvm = skip_llvm,
        .max_rss = 3_300_000_000,
    }));
    test_step.dependOn(tests.addStackTraceTests(b, test_filters, skip_non_native));
    test_step.dependOn(tests.addErrorTraceTests(b, test_filters, optimize_modes, skip_non_native));
    test_step.dependOn(tests.addCliTests(b));
    if (tests.addDebuggerTests(b, .{
        .test_filters = test_filters,
        .test_target_filters = test_target_filters,
        .gdb = b.option([]const u8, "gdb", "path to gdb binary"),
        .lldb = b.option([]const u8, "lldb", "path to lldb binary"),
        .optimize_modes = optimize_modes,
        .skip_single_threaded = skip_single_threaded,
        .skip_libc = skip_libc,
    })) |test_debugger_step| test_step.dependOn(test_debugger_step);
    if (tests.addLlvmIrTests(b, .{
        .enable_llvm = enable_llvm,
        .test_filters = test_filters,
        .test_target_filters = test_target_filters,
    })) |test_llvm_ir_step| test_step.dependOn(test_llvm_ir_step);

    try addWasiUpdateStep(b, version);

    const update_mingw_step = b.step("update-mingw", "Update zig's bundled mingw");
    const opt_mingw_src_path = b.option([]const u8, "mingw-src", "path to mingw-w64 source directory");
    if (opt_mingw_src_path) |mingw_src_path| {
        const update_mingw_exe = b.addExecutable(.{
            .name = "update_mingw",
            .root_module = b.createModule(.{
                .target = b.graph.host,
                .root_source_file = b.path("tools/update_mingw.zig"),
            }),
        });
        const update_mingw_run = b.addRunArtifact(update_mingw_exe);
        update_mingw_run.addDirectoryArg(b.path("lib"));
        update_mingw_run.addDirectoryArg(.{ .cwd_relative = mingw_src_path });

        update_mingw_step.dependOn(&update_mingw_run.step);
    } else {
        update_mingw_step.dependOn(&b.addFail("The -Dmingw-src=... option is required for this step").step);
    }

    const test_incremental_step = b.step("test-incremental", "Run the incremental compilation test cases");
    try tests.addIncrementalTests(b, test_incremental_step, test_filters);
    if (!skip_test_incremental) test_step.dependOn(test_incremental_step);

    if (tests.addLibcTestNszTests(b, .{
        .optimize_modes = optimize_modes,
        .test_filters = test_filters,
        .test_target_filters = test_target_filters,
        .skip_wasm = skip_wasm,
        .max_rss = 3_500_000_000,
    })) |test_libc_nsz_step| test_step.dependOn(test_libc_nsz_step);

    // Remove steps not relevant to the core of the project
    // Can always comment out to enable
    for (&[_][]const u8{
        "uninstall",
        "test-compiler",
        "test-docs",
        "langref",
        "std-docs",
        "docs",
        "fmt",
        // "test-fmt",
        "test-cases",
        "test-modules",
        "test-behavior",
        "test-compiler-rt",
        "test-std",
        "test-libc",
        "test-unit",
        "test-standalone",
        "test-c-abi",
        "test-stack-traces",
        "test-error-traces",
        "test-cli",
        "test-debugger",
        "test-llvm-ir",
        "update-zig1",
        "update-mingw",
        "test-incremental",
        "test-libc-nsz",
    }) |tls_name| _ = b.top_level_steps.orderedRemove(tls_name);
}

fn addWasiUpdateStep(b: *std.Build, version: [:0]const u8) !void {
    const semver = try std.SemanticVersion.parse(version);

    const exe_options = b.addOptions();
    const exe_options_mod = exe_options.createModule();

    const exe = addCompilerStep(b, .{
        .optimize = .ReleaseSmall,
        .target = b.resolveTargetQuery(std.Target.Query.parse(.{
            .arch_os_abi = "wasm32-wasi",
            // * `extended_const` is not supported by the `wasm-opt` version in CI.
            // * `nontrapping_bulk_memory_len0` is supported by `wasm2c`.
            .cpu_features = "baseline-extended_const+nontrapping_bulk_memory_len0",
        }) catch unreachable),
        .exe_options_mod = exe_options_mod,
    });

    exe_options.addOption(u32, "mem_leak_frames", 0);
    exe_options.addOption(bool, "have_llvm", false);
    exe_options.addOption(bool, "debug_gpa", false);
    exe_options.addOption([:0]const u8, "version", version);
    exe_options.addOption(std.SemanticVersion, "semver", semver);
    exe_options.addOption(bool, "enable_debug_extensions", false);
    exe_options.addOption(bool, "enable_logging", false);
    exe_options.addOption(bool, "enable_link_snapshots", false);
    exe_options.addOption(bool, "enable_tracy", false);
    exe_options.addOption(bool, "enable_tracy_callstack", false);
    exe_options.addOption(bool, "enable_tracy_allocation", false);
    exe_options.addOption(u32, "tracy_callstack_depth", 0);
    exe_options.addOption(bool, "value_tracing", false);
    exe_options.addOption(DevEnv, "dev", .bootstrap);
    exe_options.addOption(IoMode, "io_mode", .threaded);

    // zig1 chooses to interpret values by name. The tradeoff is as follows:
    //
    // * We lose a small amount of performance. This is essentially irrelevant for zig1.
    //
    // * We lose the ability to perform trivial renames on certain `std.lang` types without
    //   zig1.wasm updates. For instance, we cannot rename an enum from PascalCase fields to
    //   snake_case fields without an update.
    //
    // * We gain the ability to add and remove fields to and from `std.lang` types without
    //   zig1.wasm updates. For instance, we can add a new tag to `CallingConvention` without
    //   an update.
    //
    // Because field renames only happen when we apply a breaking change to the language (which
    // is becoming progressively rarer), but tags may be added to or removed from target-dependent
    // types over time in response to new targets coming into use, we gain more than we lose here.
    exe_options.addOption(ValueInterpretMode, "value_interpret_mode", .by_name);

    const run_opt = b.addSystemCommand(&.{
        "wasm-opt",
        "-Oz",
        "--enable-bulk-memory",
        "--enable-mutable-globals",
        "--enable-nontrapping-float-to-int",
        "--enable-sign-ext",
    });
    run_opt.addArtifactArg(exe);
    run_opt.addArg("-o");
    const optimized_wasm = run_opt.addOutputFileArg("zig1.wasm");

    const update_zig1 = b.addUpdateSourceFiles();
    update_zig1.addCopyFileToSource(optimized_wasm, "stage1/zig1.wasm");
    update_zig1.addCopyFileToSource(b.path("lib/zig.h"), "stage1/zig.h");

    const update_zig1_step = b.step("update-zig1", "Update stage1/zig1.wasm");
    update_zig1_step.dependOn(&update_zig1.step);
}

const AddCompilerModOptions = struct {
    optimize: std.lang.OptimizeMode,
    target: std.Build.ResolvedTarget,
    strip: ?bool = null,
    valgrind: ?bool = null,
    sanitize_thread: ?bool = null,
    single_threaded: ?bool = null,
    exe_options_mod: *std.Build.Module,
};

fn addCompilerMod(b: *std.Build, options: AddCompilerModOptions) *std.Build.Module {
    const main_lsp_server_mod = b.createModule(.{
        .root_source_file = b.path("src/lsp_server_main.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .strip = options.strip,
        .sanitize_thread = options.sanitize_thread,
        .single_threaded = options.single_threaded,
        .valgrind = options.valgrind,
    });
    main_lsp_server_mod.addImport("build_options", options.exe_options_mod);

    const compiler_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .strip = options.strip,
        .sanitize_thread = options.sanitize_thread,
        .single_threaded = options.single_threaded,
        .valgrind = options.valgrind,
    });
    compiler_mod.addImport("build_options", options.exe_options_mod);

    main_lsp_server_mod.addImport("compiler", compiler_mod);

    const aro_mod = b.createModule(.{
        .root_source_file = b.path("lib/compiler/aro/aro.zig"),
    });

    compiler_mod.addImport("aro", aro_mod);

    const aro_compiler_util_mod = b.createModule(.{
        .root_source_file = b.path("lib/compiler/util.zig"),
    });
    aro_compiler_util_mod.addImport("aro", aro_mod);
    const translate_c_mod = b.createModule(.{
        .root_source_file = b.path("lib/compiler/translate-c/main.zig"),
    });
    translate_c_mod.addImport("aro", aro_mod);
    translate_c_mod.addImport("aro-compiler-util", aro_compiler_util_mod);
    compiler_mod.addImport("translate-c", translate_c_mod);

    return main_lsp_server_mod;
}

fn addCompilerStep(b: *std.Build, options: AddCompilerModOptions) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = "zigscient",
        // .max_rss = 8_700_000_000,
        .root_module = addCompilerMod(b, options),
    });
    exe.stack_size = stack_size;

    // Must match the condition in CMakeLists.txt.
    const function_data_sections = switch (options.target.result.cpu.arch) {
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

    exe.link_function_sections = function_data_sections;
    exe.link_data_sections = function_data_sections;

    return exe;
}

const exe_cflags = [_][]const u8{
    "-std=c++17",
    "-D__STDC_CONSTANT_MACROS",
    "-D__STDC_FORMAT_MACROS",
    "-D__STDC_LIMIT_MACROS",
    "-D_GNU_SOURCE",
    "-fno-exceptions",
    "-fno-rtti",
    "-fno-stack-protector",
    "-fvisibility-inlines-hidden",
    "-Wno-type-limits",
    "-Wno-missing-braces",
    "-Wno-comment",
    // `exe_cflags` is only used for static linking.
    "-DLLVM_BUILD_STATIC",
    "-DCLANG_BUILD_STATIC",
};

fn addCmakeCfgOptionsToExe(
    b: *std.Build,
    cfg: CMakeConfig,
    exe: *std.Build.Step.Compile,
    use_zig_libcxx: bool,
) !void {
    const mod = exe.root_module;
    const target = &mod.resolved_target.?.result;

    if (target.os.tag.isDarwin()) {
        // useful for package maintainers
        exe.headerpad_max_install_names = true;
    }

    mod.addObjectFile(.{ .cwd_relative = b.pathJoin(&.{
        cfg.cmake_binary_dir,
        "zigcpp",
        b.fmt("{s}{s}{s}", .{
            cfg.cmake_static_library_prefix,
            "zigcpp",
            cfg.cmake_static_library_suffix,
        }),
    }) });
    assert(cfg.lld_include_dir.len != 0);
    mod.addIncludePath(.{ .cwd_relative = cfg.lld_include_dir });
    mod.addIncludePath(.{ .cwd_relative = cfg.llvm_include_dir });
    mod.addLibraryPath(.{ .cwd_relative = cfg.llvm_lib_dir });
    addCMakeLibraryList(mod, cfg.clang_libraries);
    addCMakeLibraryList(mod, cfg.lld_libraries);
    addCMakeLibraryList(mod, cfg.llvm_libraries);

    if (use_zig_libcxx) {
        mod.link_libcpp = true;
    } else {
        // System -lc++ must be used because in this code path we are attempting to link
        // against system-provided LLVM, Clang, LLD.
        const need_cpp_includes = true;
        const static = cfg.llvm_linkage == .static;
        const lib_suffix = if (static) target.staticLibSuffix()[1..] else target.dynamicLibSuffix()[1..];
        switch (target.os.tag) {
            .linux => {
                // First we try to link against the detected libcxx name. If that doesn't work, we fall
                // back to -lc++ and cross our fingers.
                addCxxKnownPath(b, cfg, exe, b.fmt("lib{s}.{s}", .{ cfg.system_libcxx, lib_suffix }), "", need_cpp_includes) catch |err| switch (err) {
                    error.RequiredLibraryNotFound => {
                        mod.link_libcpp = true;
                    },
                    else => |e| return e,
                };
                mod.linkSystemLibrary("unwind", .{});
            },
            .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos => {
                mod.link_libcpp = true;
            },
            .windows => {
                if (target.abi != .msvc) mod.link_libcpp = true;
            },
            .freebsd => {
                try addCxxKnownPath(b, cfg, exe, b.fmt("libc++.{s}", .{lib_suffix}), null, need_cpp_includes);
                if (static) try addCxxKnownPath(b, cfg, exe, b.fmt("libgcc_eh.{s}", .{lib_suffix}), null, need_cpp_includes);
            },
            .openbsd => {
                // - llvm requires libexecinfo which has conflicting symbols with libc++abi
                // - only an issue with .a linking
                // - workaround is to link c++abi dynamically
                try addCxxKnownPath(b, cfg, exe, b.fmt("libc++.{s}", .{target.dynamicLibSuffix()[1..]}), null, need_cpp_includes);
                try addCxxKnownPath(b, cfg, exe, b.fmt("libc++abi.{s}", .{target.dynamicLibSuffix()[1..]}), null, need_cpp_includes);
            },
            .netbsd, .dragonfly => {
                try addCxxKnownPath(b, cfg, exe, b.fmt("libstdc++.{s}", .{lib_suffix}), null, need_cpp_includes);
                if (static) try addCxxKnownPath(b, cfg, exe, b.fmt("libgcc_eh.{s}", .{lib_suffix}), null, need_cpp_includes);
            },
            .illumos => {
                try addCxxKnownPath(b, cfg, exe, b.fmt("libstdc++.{s}", .{lib_suffix}), null, need_cpp_includes);
                try addCxxKnownPath(b, cfg, exe, b.fmt("libgcc_eh.{s}", .{lib_suffix}), null, need_cpp_includes);
            },
            .haiku => {
                try addCxxKnownPath(b, cfg, exe, b.fmt("libstdc++.{s}", .{lib_suffix}), null, need_cpp_includes);
            },
            else => {},
        }
    }

    if (cfg.dia_guids_lib.len != 0) {
        mod.addObjectFile(.{ .cwd_relative = cfg.dia_guids_lib });
    }
}

fn addStaticLlvmOptionsToModule(mod: *std.Build.Module, options: struct {
    llvm_has_m68k: bool,
    llvm_has_csky: bool,
    llvm_has_arc: bool,
    llvm_has_xtensa: bool,
}) !void {
    // Adds the Zig C++ sources which both stage1 and stage2 need.
    //
    // We need this because otherwise zig_clang_cc1_main.cpp ends up pulling
    // in a dependency on llvm::cfg::Update<llvm::BasicBlock*>::dump() which is
    // unavailable when LLVM is compiled in Release mode.
    const zig_cpp_cflags = exe_cflags ++ [_][]const u8{"-DNDEBUG=1"};
    mod.addCSourceFiles(.{
        .files = &zig_cpp_sources,
        .flags = &zig_cpp_cflags,
    });

    const lsl_options: std.Build.Module.LinkSystemLibraryOptions = .{ .use_pkg_config = .no };

    for (clang_libs) |lib_name| {
        mod.linkSystemLibrary(lib_name, lsl_options);
    }

    for (lld_libs) |lib_name| {
        mod.linkSystemLibrary(lib_name, lsl_options);
    }

    for (llvm_libs) |lib_name| {
        mod.linkSystemLibrary(lib_name, lsl_options);
    }

    if (options.llvm_has_m68k) for (llvm_libs_m68k) |lib_name| {
        mod.linkSystemLibrary(lib_name, lsl_options);
    };

    if (options.llvm_has_csky) for (llvm_libs_csky) |lib_name| {
        mod.linkSystemLibrary(lib_name, lsl_options);
    };

    if (options.llvm_has_arc) for (llvm_libs_arc) |lib_name| {
        mod.linkSystemLibrary(lib_name, lsl_options);
    };

    if (options.llvm_has_xtensa) for (llvm_libs_xtensa) |lib_name| {
        mod.linkSystemLibrary(lib_name, lsl_options);
    };

    mod.linkSystemLibrary("z", lsl_options);
    mod.linkSystemLibrary("zstd", lsl_options);

    if (mod.resolved_target.?.result.os.tag != .windows or mod.resolved_target.?.result.abi != .msvc) {
        // This means we rely on clang-or-zig-built LLVM, Clang, LLD libraries.
        mod.linkSystemLibrary("c++", lsl_options);
    }

    if (mod.resolved_target.?.result.os.tag == .windows) {
        mod.linkSystemLibrary("version", lsl_options);
        mod.linkSystemLibrary("uuid", lsl_options);
        mod.linkSystemLibrary("ole32", lsl_options);
    }
}

fn addCxxKnownPath(
    b: *std.Build,
    ctx: CMakeConfig,
    exe: *std.Build.Step.Compile,
    objname: []const u8,
    errtxt: ?[]const u8,
    need_cpp_includes: bool,
) !void {
    if (!std.process.can_spawn) return error.RequiredLibraryNotFound;

    const arena = b.graph.arena;

    const path_padded = run: {
        var args = std.array_list.Managed([]const u8).init(arena);
        try args.append(ctx.cxx_compiler);
        var it = std.mem.tokenizeAny(u8, ctx.cxx_compiler_arg1, &std.ascii.whitespace);
        while (it.next()) |arg| try args.append(arg);
        try args.append(b.fmt("-print-file-name={s}", .{objname}));
        break :run b.run(args.items);
    };
    var tokenizer = mem.tokenizeAny(u8, path_padded, "\r\n");
    const path_unpadded = tokenizer.next().?;
    if (mem.eql(u8, path_unpadded, objname)) {
        if (errtxt) |msg| {
            std.debug.print("{s}", .{msg});
        } else {
            std.debug.print("Unable to determine path to {s}\n", .{objname});
        }
        return error.RequiredLibraryNotFound;
    }
    // By default, explicit library paths are not checked for being linker scripts,
    // but libc++ may very well be one, so force all inputs to be checked when passing
    // an explicit path to libc++.
    exe.allow_so_scripts = true;
    exe.root_module.addObjectFile(.{ .cwd_relative = path_unpadded });

    // TODO a way to integrate with system c++ include files here
    // c++ -E -Wp,-v -xc++ /dev/null
    if (need_cpp_includes) {
        // I used these temporarily for testing something but we obviously need a
        // more general purpose solution here.
        //exe.root_module.addIncludePath("/nix/store/2lr0fc0ak8rwj0k8n3shcyz1hz63wzma-gcc-11.3.0/include/c++/11.3.0");
        //exe.root_module.addIncludePath("/nix/store/2lr0fc0ak8rwj0k8n3shcyz1hz63wzma-gcc-11.3.0/include/c++/11.3.0/x86_64-unknown-linux-gnu");
    }
}

fn addCMakeLibraryList(mod: *std.Build.Module, list: []const u8) void {
    var it = mem.tokenizeScalar(u8, list, ';');
    while (it.next()) |lib| {
        if (mem.startsWith(u8, lib, "-l")) {
            mod.linkSystemLibrary(lib["-l".len..], .{});
        } else if (mod.resolved_target.?.result.os.tag == .windows and
            mem.endsWith(u8, lib, ".lib") and !fs.path.isAbsolute(lib))
        {
            mod.linkSystemLibrary(lib[0 .. lib.len - ".lib".len], .{});
        } else {
            mod.addObjectFile(.{ .cwd_relative = lib });
        }
    }
}

const CMakeConfig = struct {
    llvm_linkage: std.lang.LinkMode,
    cmake_binary_dir: []const u8,
    cmake_prefix_path: []const u8,
    cmake_static_library_prefix: []const u8,
    cmake_static_library_suffix: []const u8,
    cxx_compiler: []const u8,
    cxx_compiler_arg1: []const u8,
    lld_include_dir: []const u8,
    lld_libraries: []const u8,
    clang_libraries: []const u8,
    llvm_lib_dir: []const u8,
    llvm_include_dir: []const u8,
    llvm_libraries: []const u8,
    dia_guids_lib: []const u8,
    system_libcxx: []const u8,
};

const max_config_h_bytes = 1 * 1024 * 1024;

fn findConfigH(b: *std.Build, config_h_path_option: ?[]const u8) ?[]const u8 {
    const arena = b.graph.arena;
    const io = b.graph.io;
    const cwd: Io.Dir = .cwd();

    if (config_h_path_option) |path| {
        var config_h_or_err = cwd.openFile(io, path, .{});
        if (config_h_or_err) |*file| {
            file.close(io);
            return path;
        } else |_| {
            std.log.err("Could not open provided config.h: \"{s}\"", .{path});
            std.process.exit(1);
        }
    }

    var check_dir = fs.path.dirname(b.graph.zig_exe).?;
    while (true) {
        var dir = cwd.openDir(io, check_dir, .{}) catch unreachable;
        defer dir.close(io);

        // Check if config.h is present in dir
        var config_h_or_err = dir.openFile(io, "config.h", .{});
        if (config_h_or_err) |*file| {
            file.close(io);
            return fs.path.join(
                arena,
                &[_][]const u8{ check_dir, "config.h" },
            ) catch unreachable;
        } else |e| switch (e) {
            error.FileNotFound => {},
            else => unreachable,
        }

        // Check if we reached the source root by looking for .git, and bail if so
        var git_dir_or_err = dir.openDir(io, ".git", .{});
        if (git_dir_or_err) |*git_dir| {
            git_dir.close(io);
            return null;
        } else |_| {}

        // Otherwise, continue search in the parent directory
        const new_check_dir = fs.path.dirname(check_dir);
        if (new_check_dir == null or mem.eql(u8, new_check_dir.?, check_dir)) {
            return null;
        }
        check_dir = new_check_dir.?;
    }
}

fn parseConfigH(b: *std.Build, config_h_text: []const u8) ?CMakeConfig {
    var ctx: CMakeConfig = .{
        .llvm_linkage = undefined,
        .cmake_binary_dir = undefined,
        .cmake_prefix_path = undefined,
        .cmake_static_library_prefix = undefined,
        .cmake_static_library_suffix = undefined,
        .cxx_compiler = undefined,
        .cxx_compiler_arg1 = "",
        .lld_include_dir = undefined,
        .lld_libraries = undefined,
        .clang_libraries = undefined,
        .llvm_lib_dir = undefined,
        .llvm_include_dir = undefined,
        .llvm_libraries = undefined,
        .dia_guids_lib = undefined,
        .system_libcxx = undefined,
    };

    const mappings = [_]struct { prefix: []const u8, field: []const u8 }{
        .{
            .prefix = "#define ZIG_CMAKE_BINARY_DIR ",
            .field = "cmake_binary_dir",
        },
        .{
            .prefix = "#define ZIG_CMAKE_PREFIX_PATH ",
            .field = "cmake_prefix_path",
        },
        .{
            .prefix = "#define ZIG_CMAKE_STATIC_LIBRARY_PREFIX ",
            .field = "cmake_static_library_prefix",
        },
        .{
            .prefix = "#define ZIG_CMAKE_STATIC_LIBRARY_SUFFIX ",
            .field = "cmake_static_library_suffix",
        },
        .{
            .prefix = "#define ZIG_CXX_COMPILER ",
            .field = "cxx_compiler",
        },
        .{
            .prefix = "#define ZIG_CXX_COMPILER_ARG1 ",
            .field = "cxx_compiler_arg1",
        },
        .{
            .prefix = "#define ZIG_LLD_INCLUDE_PATH ",
            .field = "lld_include_dir",
        },
        .{
            .prefix = "#define ZIG_LLD_LIBRARIES ",
            .field = "lld_libraries",
        },
        .{
            .prefix = "#define ZIG_CLANG_LIBRARIES ",
            .field = "clang_libraries",
        },
        .{
            .prefix = "#define ZIG_LLVM_LIBRARIES ",
            .field = "llvm_libraries",
        },
        .{
            .prefix = "#define ZIG_DIA_GUIDS_LIB ",
            .field = "dia_guids_lib",
        },
        .{
            .prefix = "#define ZIG_LLVM_INCLUDE_PATH ",
            .field = "llvm_include_dir",
        },
        .{
            .prefix = "#define ZIG_LLVM_LIB_PATH ",
            .field = "llvm_lib_dir",
        },
        .{
            .prefix = "#define ZIG_SYSTEM_LIBCXX",
            .field = "system_libcxx",
        },
        // .prefix = ZIG_LLVM_LINK_MODE parsed manually below
    };

    var lines_it = mem.tokenizeAny(u8, config_h_text, "\r\n");
    while (lines_it.next()) |line| {
        inline for (mappings) |mapping| {
            if (mem.startsWith(u8, line, mapping.prefix)) {
                var it = mem.splitScalar(u8, line, '"');
                _ = it.first(); // skip the stuff before the quote
                const quoted = it.next().?; // the stuff inside the quote
                const trimmed = mem.trim(u8, quoted, " ");
                @field(ctx, mapping.field) = toNativePathSep(b, trimmed);
            }
        }
        if (mem.startsWith(u8, line, "#define ZIG_LLVM_LINK_MODE ")) {
            var it = mem.splitScalar(u8, line, '"');
            _ = it.next().?; // skip the stuff before the quote
            const quoted = it.next().?; // the stuff inside the quote
            ctx.llvm_linkage = if (mem.eql(u8, quoted, "shared")) .dynamic else .static;
        }
    }
    return ctx;
}

fn toNativePathSep(b: *std.Build, s: []const u8) []u8 {
    const arena = b.graph.arena;
    const duplicated = arena.dupe(u8, s) catch unreachable;
    for (duplicated) |*byte| switch (byte.*) {
        '/' => byte.* = fs.path.sep,
        else => {},
    };
    return duplicated;
}

const zig_cpp_sources = [_][]const u8{
    // These are planned to stay even when we are self-hosted.
    "src/zig_llvm.cpp",
    "src/zig_llvm-ar.cpp",
    "src/zig_clang_driver.cpp",
    "src/zig_clang_cc1_main.cpp",
    "src/zig_clang_cc1as_main.cpp",
};

const clang_libs = [_][]const u8{
    "clangFrontendTool",
    "clangCodeGen",
    "clangStaticAnalyzerFrontend",
    "clangStaticAnalyzerCheckers",
    "clangStaticAnalyzerCore",
    "clangCrossTU",
    "clangFrontend",
    "clangDriver",
    "clangOptions",
    "clangSerialization",
    "clangSema",
    "clangAnalysisLifetimeSafety",
    "clangAnalysis",
    "clangASTMatchers",
    "clangAST",
    "clangParse",
    "clangSema",
    "clangAPINotes",
    "clangBasic",
    "clangEdit",
    "clangLex",
    "clangRewriteFrontend",
    "clangRewrite",
    "clangIndex",
    "clangFormat",
    "clangToolingInclusions",
    "clangToolingCore",
    "clangExtractAPI",
    "clangSupport",
    "clangInstallAPI",
    "clangAST",
};
const lld_libs = [_][]const u8{
    "lldMinGW",
    "lldELF",
    "lldCOFF",
    "lldWasm",
    "lldMachO",
    "lldCommon",
};
// This list can be re-generated with `llvm-config --libfiles` and then
// reformatting using your favorite text editor. Note we do not execute
// `llvm-config` here because we are cross compiling. Also omit LLVMTableGen
// from these libs.
const llvm_libs = [_][]const u8{
    "LLVMWindowsManifest",
    "LLVMXRay",
    "LLVMLibDriver",
    "LLVMDlltoolDriver",
    "LLVMTelemetry",
    "LLVMTextAPIBinaryReader",
    "LLVMCoverage",
    "LLVMLineEditor",
    "LLVMXCoreDisassembler",
    "LLVMXCoreCodeGen",
    "LLVMXCoreDesc",
    "LLVMXCoreInfo",
    "LLVMX86TargetMCA",
    "LLVMX86Disassembler",
    "LLVMX86AsmParser",
    "LLVMX86CodeGen",
    "LLVMX86Desc",
    "LLVMX86Info",
    "LLVMWebAssemblyDisassembler",
    "LLVMWebAssemblyAsmParser",
    "LLVMWebAssemblyCodeGen",
    "LLVMWebAssemblyUtils",
    "LLVMWebAssemblyDesc",
    "LLVMWebAssemblyInfo",
    "LLVMVEDisassembler",
    "LLVMVEAsmParser",
    "LLVMVECodeGen",
    "LLVMVEDesc",
    "LLVMVEInfo",
    "LLVMSystemZDisassembler",
    "LLVMSystemZAsmParser",
    "LLVMSystemZCodeGen",
    "LLVMSystemZDesc",
    "LLVMSystemZInfo",
    "LLVMSPIRVCodeGen",
    "LLVMSPIRVDesc",
    "LLVMSPIRVInfo",
    "LLVMSPIRVAnalysis",
    "LLVMSparcDisassembler",
    "LLVMSparcAsmParser",
    "LLVMSparcCodeGen",
    "LLVMSparcDesc",
    "LLVMSparcInfo",
    "LLVMRISCVTargetMCA",
    "LLVMRISCVDisassembler",
    "LLVMRISCVAsmParser",
    "LLVMRISCVCodeGen",
    "LLVMRISCVDesc",
    "LLVMRISCVInfo",
    "LLVMPowerPCDisassembler",
    "LLVMPowerPCAsmParser",
    "LLVMPowerPCCodeGen",
    "LLVMPowerPCDesc",
    "LLVMPowerPCInfo",
    "LLVMNVPTXCodeGen",
    "LLVMNVPTXDesc",
    "LLVMNVPTXInfo",
    "LLVMMSP430Disassembler",
    "LLVMMSP430AsmParser",
    "LLVMMSP430CodeGen",
    "LLVMMSP430Desc",
    "LLVMMSP430Info",
    "LLVMMipsDisassembler",
    "LLVMMipsAsmParser",
    "LLVMMipsCodeGen",
    "LLVMMipsDesc",
    "LLVMMipsInfo",
    "LLVMLoongArchDisassembler",
    "LLVMLoongArchAsmParser",
    "LLVMLoongArchCodeGen",
    "LLVMLoongArchDesc",
    "LLVMLoongArchInfo",
    "LLVMLanaiDisassembler",
    "LLVMLanaiCodeGen",
    "LLVMLanaiAsmParser",
    "LLVMLanaiDesc",
    "LLVMLanaiInfo",
    "LLVMHexagonDisassembler",
    "LLVMHexagonCodeGen",
    "LLVMHexagonAsmParser",
    "LLVMHexagonDesc",
    "LLVMHexagonInfo",
    "LLVMBPFDisassembler",
    "LLVMBPFAsmParser",
    "LLVMBPFCodeGen",
    "LLVMBPFDesc",
    "LLVMBPFInfo",
    "LLVMAVRDisassembler",
    "LLVMAVRAsmParser",
    "LLVMAVRCodeGen",
    "LLVMAVRDesc",
    "LLVMAVRInfo",
    "LLVMARMDisassembler",
    "LLVMARMAsmParser",
    "LLVMARMCodeGen",
    "LLVMARMDesc",
    "LLVMARMUtils",
    "LLVMARMInfo",
    "LLVMAMDGPUTargetMCA",
    "LLVMAMDGPUDisassembler",
    "LLVMAMDGPUAsmParser",
    "LLVMAMDGPUCodeGen",
    "LLVMAMDGPUDesc",
    "LLVMAMDGPUUtils",
    "LLVMAMDGPUInfo",
    "LLVMAArch64Disassembler",
    "LLVMAArch64AsmParser",
    "LLVMAArch64CodeGen",
    "LLVMAArch64Desc",
    "LLVMAArch64Utils",
    "LLVMAArch64Info",
    "LLVMOrcDebugging",
    "LLVMOrcJIT",
    "LLVMWindowsDriver",
    "LLVMMCJIT",
    "LLVMJITLink",
    "LLVMInterpreter",
    "LLVMExecutionEngine",
    "LLVMRuntimeDyld",
    "LLVMOrcTargetProcess",
    "LLVMOrcShared",
    "LLVMDWP",
    "LLVMDWARFCFIChecker",
    "LLVMDebugInfoLogicalView",
    "LLVMOption",
    "LLVMObjCopy",
    "LLVMMCA",
    "LLVMMCDisassembler",
    "LLVMDTLTO",
    "LLVMLTO",
    "LLVMFrontendOpenACC",
    "LLVMFrontendDriver",
    "LLVMExtensions",
    "LLVMPlugins",
    "LLVMPasses",
    "LLVMHipStdPar",
    "LLVMCoroutines",
    "LLVMCFGuard",
    "LLVMipo",
    "LLVMInstrumentation",
    "LLVMVectorize",
    "LLVMSandboxIR",
    "LLVMLinker",
    "LLVMFrontendOpenMP",
    "LLVMFrontendDirective",
    "LLVMFrontendAtomic",
    "LLVMFrontendOffloading",
    "LLVMObjectYAML",
    "LLVMDWARFLinkerParallel",
    "LLVMDWARFLinkerClassic",
    "LLVMDWARFLinker",
    "LLVMGlobalISel",
    "LLVMMIRParser",
    "LLVMAsmPrinter",
    "LLVMSelectionDAG",
    "LLVMCodeGen",
    "LLVMTarget",
    "LLVMObjCARCOpts",
    "LLVMCodeGenTypes",
    "LLVMCGData",
    "LLVMCAS",
    "LLVMIRPrinter",
    "LLVMInterfaceStub",
    "LLVMFileCheck",
    "LLVMFuzzMutate",
    "LLVMScalarOpts",
    "LLVMInstCombine",
    "LLVMAggressiveInstCombine",
    "LLVMTransformUtils",
    "LLVMBitWriter",
    "LLVMAnalysis",
    "LLVMProfileData",
    "LLVMSymbolize",
    "LLVMDebugInfoBTF",
    "LLVMDebugInfoPDB",
    "LLVMDebugInfoMSF",
    "LLVMDebugInfoCodeView",
    "LLVMDebugInfoGSYM",
    "LLVMDebugInfoDWARF",
    "LLVMObject",
    "LLVMTextAPI",
    "LLVMMCParser",
    "LLVMIRReader",
    "LLVMAsmParser",
    "LLVMMC",
    "LLVMDebugInfoDWARFLowLevel",
    "LLVMBitReader",
    "LLVMFrontendHLSL",
    "LLVMFuzzerCLI",
    "LLVMABI",
    "LLVMCore",
    "LLVMRemarks",
    "LLVMBitstreamReader",
    "LLVMBinaryFormat",
    "LLVMTargetParser",
    "LLVMSupport",
    "LLVMDemangle",
};
const llvm_libs_m68k = [_][]const u8{
    "LLVMM68kDisassembler",
    "LLVMM68kAsmParser",
    "LLVMM68kCodeGen",
    "LLVMM68kDesc",
    "LLVMM68kInfo",
};
const llvm_libs_csky = [_][]const u8{
    "LLVMCSKYDisassembler",
    "LLVMCSKYAsmParser",
    "LLVMCSKYCodeGen",
    "LLVMCSKYDesc",
    "LLVMCSKYInfo",
};
const llvm_libs_arc = [_][]const u8{
    "LLVMARCDisassembler",
    "LLVMARCCodeGen",
    "LLVMARCDesc",
    "LLVMARCInfo",
};
const llvm_libs_xtensa = [_][]const u8{
    "LLVMXtensaDisassembler",
    "LLVMXtensaAsmParser",
    "LLVMXtensaCodeGen",
    "LLVMXtensaDesc",
    "LLVMXtensaInfo",
};

fn generateLangRef(b: *std.Build) !std.Build.LazyPath {
    const io = b.graph.io;
    const arena = b.graph.arena;

    const doctest_exe = b.addExecutable(.{
        .name = "doctest",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/doctest.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });

    const langref_path = try b.root.join(arena, "doc/langref");

    var dir = langref_path.root_dir.handle.openDir(io, langref_path.sub_path, .{ .iterate = true }) catch |err|
        std.debug.panic("unable to open directory {f}: {t}", .{ langref_path, err });
    defer dir.close(io);

    var wf = b.addWriteFiles();
    b.step("test-docs", "Test code snippets from the docs").dependOn(&wf.step);

    var it = dir.iterateAssumeFirstIteration();
    while (it.next(io) catch @panic("failed to read dir")) |entry| {
        if (std.mem.startsWith(u8, entry.name, ".") or entry.kind != .file)
            continue;

        const out_basename = b.fmt("{s}.out", .{std.fs.path.stem(entry.name)});
        const cmd = b.addRunArtifact(doctest_exe);

        cmd.addArg("--zig");
        cmd.addFileArg(.zig_exe);

        cmd.addArg("--cache-root");
        cmd.addDirectoryArg(.cache_root);

        cmd.addArg("--zig-lib-dir");
        cmd.addDirectoryArg(.zig_lib);

        cmd.addArg("-i");
        cmd.addFileArg(b.path(b.fmt("doc/langref/{s}", .{entry.name})));

        cmd.addArg("-o");
        _ = wf.addCopyFile(cmd.addOutputFileArg(out_basename), out_basename);
    }

    const docgen_exe = b.addExecutable(.{
        .name = "docgen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/docgen.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });

    const docgen_cmd = b.addRunArtifact(docgen_exe);
    docgen_cmd.addArgs(&.{"--code-dir"});
    docgen_cmd.addDirectoryArg(wf.getDirectory());

    docgen_cmd.addFileArg(b.path("doc/langref.html.in"));
    return docgen_cmd.addOutputFileArg("langref.html");
}

fn superHtmlCheck(b: *std.Build, html_file: std.Build.LazyPath) *std.Build.Step {
    const run_superhtml = b.addSystemCommand(&.{
        "superhtml", "check",
    });
    run_superhtml.addFileArg(html_file);
    run_superhtml.expectExitCode(0);
    return &run_superhtml.step;
}

// LSP
const bzz = @import("build.zig.zon");
const proj_version = std.SemanticVersion.parse(bzz.version) catch unreachable;
const minimum_build_zig_version = bzz.minimum_zig_version;
const minimum_runtime_zig_version = bzz.minimum_runtime_zig_version;

fn cfgLspServer(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.OptimizeMode,
    test_filters: []const []const u8,
    single_threaded: ?bool,
    exe_options_module: *std.Build.Module,
    use_llvm: ?bool,
    pie: ?bool,
) void {
    const ls_test_options = blk: {
        const ls_test_options = b.addOptions();
        ls_test_options.step.name = "test options";

        ls_test_options.addOptionPath("zig_exe_path", .zig_exe);
        ls_test_options.addOptionPath("zig_lib_path", .zig_lib);
        ls_test_options.addOptionPath("global_cache_path", .{ .relative = .{ .base = .global_cache } });

        break :blk ls_test_options.createModule();
    };

    const lsp_server_settings_util_exe = b.addExecutable(.{
        .name = "lsp_server_settings_util",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lsp_server/Settings_util.zig"),
            .target = b.graph.host,
            .single_threaded = true,
        }),
    });

    const version_data_module = blk: {
        const gen_version_data_cmd = b.addRunArtifact(lsp_server_settings_util_exe);
        gen_version_data_cmd.addArgs(&.{ "--langref-version", bzz.langref_version });

        gen_version_data_cmd.addArg("--langref-path");
        gen_version_data_cmd.addFileArg(b.path("doc/langref.html.in"));

        gen_version_data_cmd.addArg("--generate-version-data");
        const version_data_path = gen_version_data_cmd.addOutputFileArg("version_data.zig");

        break :blk b.createModule(.{ .root_source_file = version_data_path });
    };

    { // zig build gen
        const gen_step = b.step("gen", "Regenerate settings files");

        const gen_cmd = b.addRunArtifact(lsp_server_settings_util_exe);
        // if (b.args) |args| {
        //     gen_cmd.addArgs(args);
        //     gen_step.dependOn(&gen_cmd.step);
        // } else {
        const update_source = b.addUpdateSourceFiles();
        gen_cmd.addArg("--generate-config");
        update_source.addCopyFileToSource(gen_cmd.addOutputFileArg("Settings.zig"), "src/lsp_server/Settings.zig");
        gen_cmd.addArg("--generate-schema");
        update_source.addCopyFileToSource(gen_cmd.addOutputFileArg("settings.schema.json"), "src/lsp_server/settings.schema.json");
        gen_step.dependOn(&update_source.step);
        // }
    }

    const lsp_server_module = createLspServerModule(b, .{
        .target = target,
        .optimize = optimize,
        .build_options = exe_options_module,
        .version_data = version_data_module,
    });

    exe.root_module.addImport("lsp-server", lsp_server_module);
    exe.root_module.addImport("tracy", lsp_server_module.import_table.get("tracy").?);

    const compiler_mod = exe.root_module.import_table.get("compiler").?;
    lsp_server_module.addImport("compiler", compiler_mod);
    compiler_mod.addImport("lsp-server", lsp_server_module);

    const ls_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lsp_server/tests/tests.zig"),
            .target = target,
            .optimize = optimize,
            .single_threaded = single_threaded,
            .pic = pie,
            .imports = &.{
                .{ .name = "lsp-server", .module = lsp_server_module },
                .{ .name = "test_options", .module = ls_test_options },
            },
        }),
        .filters = test_filters,
        .use_llvm = use_llvm,
        .use_lld = use_llvm,
    });

    const src_tests = b.addTest(.{
        .name = "src test",
        .root_module = lsp_server_module,
        .filters = test_filters,
        .use_llvm = use_llvm,
        .use_lld = use_llvm,
    });

    // if (target.result.cpu.arch.isWasm() and b.enable_wasmtime) {
    //     // Zig's build system integration with wasmtime does not support adding custom preopen directories so it is done manually.
    //     const args: []const ?[]const u8 = &.{
    //         "wasmtime",
    //         "--dir=.",
    //         b.fmt("--dir={f}::/lib", .{b.graph.zig_lib_directory}),
    //         b.fmt("--dir={s}::/cache", .{b.cache_root.join(b.allocator, &.{"zigscient"}) catch @panic("OOM")}),
    //         "--",
    //         null,
    //     };
    //     ls_tests.setExecCmd(args);
    //     src_tests.setExecCmd(args);
    // }

    blk: { // zig build test, zig build test-build-runner, zig build test-analysis
        const test_step = b.step("test", "Run all the lsp-server tests");
        const test_build_runner_step = b.step("test-build-runner", "Run all the build runner tests");
        const test_analysis_step = b.step("test-analysis", "Run all the analysis tests");

        // Create run steps
        // @import("src/lsp_server/tests/add_build_runner_cases.zig").addCases(b, test_build_runner_step, test_filters);
        @import("src/lsp_server/tests/add_analysis_cases.zig").addCases(b, target, optimize, test_analysis_step, test_filters);

        const run_tests = b.addRunArtifact(ls_tests);
        const run_src_tests = b.addRunArtifact(src_tests);

        run_tests.skip_foreign_checks = target.result.cpu.arch.isWasm() and b.enable_wasmtime;
        run_src_tests.skip_foreign_checks = target.result.cpu.arch.isWasm() and b.enable_wasmtime;

        // Setup dependencies of `zig build test`
        test_step.dependOn(&run_tests.step);
        test_step.dependOn(&run_src_tests.step);
        test_step.dependOn(test_analysis_step);
        if (target.query.eql(b.graph.host.query)) test_step.dependOn(test_build_runner_step);

        const coverage = b.option(bool, "coverage", "Generate a coverage report with kcov") orelse false;
        if (!coverage) break :blk;

        // Collect all run steps into one ArrayList
        var run_test_steps: std.ArrayList(*std.Build.Step.Run) = .empty;
        run_test_steps.append(b.allocator, run_tests) catch @panic("OOM");
        run_test_steps.append(b.allocator, run_src_tests) catch @panic("OOM");
        for (test_build_runner_step.dependencies.items) |step| {
            run_test_steps.append(b.allocator, step.cast(std.Build.Step.Run).?) catch @panic("OOM");
        }
        for (test_analysis_step.dependencies.items) |step| {
            run_test_steps.append(b.allocator, step.cast(std.Build.Step.Run).?) catch @panic("OOM");
        }

        const kcov_bin = b.findProgram(.{ .names = &.{"kcov"} }) orelse "kcov";

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

// not ideal
/// Returns `MAJOR.MINOR.PATCH-dev` when `git describe` failed.
fn getVersion(b: *std.Build, opt_version_string: ?[]const u8) std.SemanticVersion {
    if (opt_version_string) |semver_string| {
        return std.SemanticVersion.parse(semver_string) catch |err| {
            std.debug.panic("Expected -Dversion-string={s} to be a semantic version: {}", .{ semver_string, err });
        };
    }

    if (proj_version.pre == null) return proj_version;

    const argv: []const []const u8 = &.{
        "git", "--git-dir", ".git", "describe", "--match", "*.*.*", "--tags",
    };
    var code: u8 = undefined;
    const git_describe_untrimmed = b.runAllowFail(argv, &code, .ignore) catch |err| {
        const argv_joined = std.mem.join(b.allocator, " ", argv) catch @panic("OOM");
        std.log.warn(
            \\Failed to run git describe to resolve version: {}
            \\command: {s}
            \\
            \\Consider passing the -Dversion-string flag to specify the version.
        , .{ err, argv_joined });
        return proj_version;
    };

    const git_describe = std.mem.trim(u8, git_describe_untrimmed, " \n\r");

    switch (std.mem.count(u8, git_describe, "-")) {
        0 => {
            // Tagged release version (e.g. 0.10.0).
            std.debug.assert(std.mem.eql(u8, git_describe, b.fmt("{f}", .{proj_version}))); // tagged release must match version string
            return proj_version;
        },
        2 => {
            // Untagged development build (e.g. 0.10.0-dev.216+34ce200).
            var it = std.mem.splitScalar(u8, git_describe, '-');
            // const tagged_ancestor = it.first();
            _ = it.first();
            const commit_height = it.next().?;
            const commit_id = it.next().?;

            // const ancestor_ver = std.SemanticVersion.parse(tagged_ancestor) catch unreachable;
            // std.debug.assert(proj_version.order(ancestor_ver) == .gt); // version must be greater than its previous version
            // std.debug.assert(std.mem.startsWith(u8, commit_id, "g")); // commit hash is prefixed with a 'g'

            return .{
                .major = proj_version.major,
                .minor = proj_version.minor,
                .patch = proj_version.patch,
                .pre = b.fmt("dev.{s}", .{commit_height}),
                .build = commit_id[1..],
            };
        },
        4 => { // zigscient-next-0.14.0-1-g15ffe8330
            // Untagged development build (e.g. 0.10.0-dev.2025+ecf0050a9).
            var it = std.mem.splitScalar(u8, git_describe, '-');
            // const tagged_ancestor = it.first();
            _ = it.first();
            _ = it.next().?;
            _ = it.next().?;
            const commit_height = it.next().?;
            const commit_id = it.next().?;

            // const ancestor_ver = try std.SemanticVersion.parse(tagged_ancestor);
            // if (zig_version.order(ancestor_ver) != .gt) {
            //     std.debug.print("Project's version '{f}' must be greater than tagged ancestor '{f}'\n", .{ zig_version, ancestor_ver });
            //     std.process.exit(1);
            // }

            // Check that the commit hash is prefixed with a 'g' (a Git convention).
            if (commit_id.len < 1 or commit_id[0] != 'g') {
                std.debug.print("Unexpected `git describe` output: {s}\n", .{git_describe});
                return proj_version;
            }

            return .{
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

fn createLspServerModule(
    b: *std.Build,
    options: struct {
        target: std.Build.ResolvedTarget,
        optimize: std.lang.OptimizeMode,
        // tracy_enable: bool,
        // tracy_options: *std.Build.Module,
        build_options: *std.Build.Module,
        version_data: *std.Build.Module,
    },
) *std.Build.Module {
    const known_folders_module = b.dependency("known_folders", .{
        .target = options.target,
        .optimize = options.optimize,
    }).module("known-folders");

    const diffz_module = b.dependency("diffz", .{
        .target = options.target,
        .optimize = options.optimize,
    }).module("diffz");

    const lsp_module = b.dependency("lsp_kit", .{
        .target = options.target,
        .optimize = options.optimize,
    }).module("lsp");

    const tracy_module = createTracyModule(b, .{
        .target = options.target,
        .optimize = options.optimize,
        .enable = false,
        // .tracy_options = options.tracy_options,
    });

    const extended_zccs = b.dependency("extended_zccs", .{
        .target = options.target,
        .optimize = options.optimize,
    }).module("extended-zccs");

    const maker_mod = b.createModule(.{
        .root_source_file = b.path("lib/compiler/Maker.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });

    const lsp_server_module = b.createModule(.{
        .root_source_file = b.path("src/lsp_server/components.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "diffz", .module = diffz_module },
            .{ .name = "lsp", .module = lsp_module },
            .{ .name = "tracy", .module = tracy_module },
            .{ .name = "extended-zccs", .module = extended_zccs },
            .{ .name = "known-folders", .module = known_folders_module },
            .{ .name = "build_options", .module = options.build_options },
            .{ .name = "version_data", .module = options.version_data },
            .{ .name = "Maker", .module = maker_mod },
        },
    });
    lsp_server_module.addImport("lsp-server", lsp_server_module);

    if (options.target.result.os.tag == .windows) {
        lsp_server_module.linkSystemLibrary("advapi32", .{});
    }

    b.modules.put(b.graph.arena, "lsp-server", lsp_server_module) catch @panic("OOM");

    return lsp_server_module;
}

fn createTracyModule(
    b: *std.Build,
    options: struct {
        target: std.Build.ResolvedTarget,
        optimize: std.lang.OptimizeMode,
        enable: bool,
        // tracy_options: *std.Build.Module,
    },
) *std.Build.Module {
    const enable = false;
    const tracy_module = b.createModule(.{
        .root_source_file = b.path("src/lsp_server/tracy.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "tracy options", .module = blk: {
                const tracy_options = b.addOptions();
                tracy_options.step.name = "tracy options";
                const enable_allocation = b.option(bool, "enable-tracy-allocation", "Enable using TracyAllocator to monitor allocations.") orelse enable;
                const enable_callstack = b.option(bool, "enable-tracy-callstack", "Enable callstack graphs.") orelse enable;
                if (!enable) std.debug.assert(!enable_allocation and !enable_callstack);
                tracy_options.addOption(bool, "enable", enable);
                tracy_options.addOption(bool, "enable_allocation", enable and enable_allocation);
                tracy_options.addOption(bool, "enable_callstack", enable and enable_callstack);
                break :blk tracy_options.createModule();
            } },
        },
        .link_libc = enable,
        .link_libcpp = enable,
        .sanitize_c = .off,
    });
    if (!enable) return tracy_module;

    const tracy_dependency = b.lazyDependency("tracy", .{
        .target = options.target,
        .optimize = options.optimize,
    }) orelse return tracy_module;

    tracy_module.addCMacro("TRACY_ENABLE", "1");
    tracy_module.addIncludePath(tracy_dependency.path(""));
    tracy_module.addCSourceFile(.{
        .file = tracy_dependency.path("public/TracyClient.cpp"),
    });

    if (options.target.result.os.tag == .windows) {
        tracy_module.linkSystemLibrary("dbghelp", .{});
        tracy_module.linkSystemLibrary("ws2_32", .{});
    }

    return tracy_module;
}
