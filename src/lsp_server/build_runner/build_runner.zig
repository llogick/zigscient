//! PLEASE READ THE FOLLOWING MESSAGE BEFORE EDITING THIS FILE:
//!
//! This build runner is targeting compatibility with the following Zig versions:
//!   - 0.15.1 or later
//!
//! Handling multiple Zig versions can be achieved with one of the following strategies:
//!   - use `@hasDecl` or `@hasField` (recommended)
//!   - use `builtin.zig_version`
//!
//! You can test out the build runner on ZLS's `build.zig` with the following command:
//! `zig build --build-runner src/build_runner/build_runner.zig`
//!
//! You can also test the build runner on any other `build.zig` with the following command:
//! `zig build --build-file /path/to/build.zig --build-runner /path/to/zls/src/build_runner/build_runner.zig`
//! `zig build --build-runner /path/to/zls/src/build_runner/build_runner.zig` (if the cwd contains build.zig)
//!

const root = @import("@build");
const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const mem = std.mem;
const process = std.process;
const ArrayListManaged = if (@hasDecl(std, "array_list")) std.array_list.Managed else std.ArrayList;
const ArrayList = if (@hasDecl(std, "array_list")) std.ArrayList else std.ArrayList;
const Step = std.Build.Step;
const Allocator = std.mem.Allocator;

pub const dependencies = @import("@dependencies");

pub const std_options: std.Options = .{
    .side_channels_mitigations = .none,
    .http_disable_tls = true,
    .networking = false,
};

var self_path: [:0]const u8 = undefined;
var build_root: [:0]const u8 = undefined;
var dont_create_roots_txt_file: bool = false;

///! This is a modified build runner to extract information out of build.zig
///! Modified version of lib/build_runner.zig
pub fn main(init: process.Init.Minimal) !void {
    var safe_gpa_state: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{});
    defer _ = safe_gpa_state.deinit();
    const dgpa = safe_gpa_state.allocator();

    var threaded: std.Io.Threaded = .init(dgpa, .{
        .environ = init.environ,
        .argv0 = .init(init.args),
    });
    defer threaded.deinit();
    const io = threaded.io();

    var arena_instance: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const args = try init.args.toSlice(arena);

    var arg_idx: usize = 0;

    self_path = nextArg(args, &arg_idx) orelse unreachable;
    const zig_exe = nextArg(args, &arg_idx) orelse fatal("missing zig compiler path", .{});
    const zig_lib_dir = nextArg(args, &arg_idx) orelse fatal("missing zig lib directory path", .{});
    build_root = nextArg(args, &arg_idx) orelse fatal("missing build root directory path", .{});
    const cache_root = nextArg(args, &arg_idx) orelse fatal("missing cache root directory path", .{});
    const global_cache_root = nextArg(args, &arg_idx) orelse fatal("missing global cache root directory path", .{});

    const cwd: std.Io.Dir = .cwd();

    const zig_lib_directory: std.Build.Cache.Directory = .{
        .path = zig_lib_dir,
        .handle = try cwd.openDir(io, zig_lib_dir, .{}),
    };

    const build_root_directory: std.Build.Cache.Directory = .{
        .path = build_root,
        .handle = try cwd.openDir(io, build_root, .{}),
    };

    const local_cache_directory: std.Build.Cache.Directory = .{
        .path = cache_root,
        .handle = try cwd.createDirPathOpen(io, cache_root, .{}),
    };

    const global_cache_directory: std.Build.Cache.Directory = .{
        .path = global_cache_root,
        .handle = try cwd.createDirPathOpen(io, global_cache_root, .{}),
    };

    var graph: std.Build.Graph = .{
        .io = io,
        .arena = arena,
        .cache = .{
            .io = io,
            .gpa = arena,
            .manifest_dir = try local_cache_directory.handle.createDirPathOpen(io, "h", .{}),
            .cwd = try process.currentPathAlloc(io, arena),
        },
        .zig_exe = zig_exe,
        .environ_map = try init.environ.createMap(arena),
        .global_cache_root = global_cache_directory,
        .zig_lib_directory = zig_lib_directory,
        .host = .{
            .query = .{},
            .result = try std.zig.system.resolveTargetQuery(io, .{}),
        },
        .time_report = false,
    };

    graph.cache.addPrefix(.{ .path = null, .handle = cwd });
    graph.cache.addPrefix(build_root_directory);
    graph.cache.addPrefix(local_cache_directory);
    graph.cache.addPrefix(global_cache_directory);
    graph.cache.hash.addBytes(builtin.zig_version_string);

    const builder = try std.Build.create(
        &graph,
        build_root_directory,
        local_cache_directory,
        dependencies.root_deps,
    );

    var targets = ArrayListManaged([]const u8).init(arena);
    var debug_log_scopes = ArrayListManaged([]const u8).init(arena);

    var install_prefix: ?[]const u8 = null;
    var dir_list: std.Build.DirList = .{};
    var max_rss: u64 = 0;
    var skip_oom_steps = false;
    var seed: u32 = 0;
    var output_tmp_nonce: ?[16]u8 = null;
    var debounce_interval_ms: u16 = 50;
    var watch = false;
    var check_step_only = false;

    while (nextArg(args, &arg_idx)) |arg| {
        if (mem.startsWith(u8, arg, "-Z")) {
            if (arg.len != 18) fatal("bad argument: '{s}'", .{arg});
            output_tmp_nonce = arg[2..18].*;
        } else if (mem.startsWith(u8, arg, "-D")) {
            const option_contents = arg[2..];
            if (option_contents.len == 0)
                fatal("expected option name after '-D'", .{});
            if (mem.indexOfScalar(u8, option_contents, '=')) |name_end| {
                const option_name = option_contents[0..name_end];
                const option_value = option_contents[name_end + 1 ..];
                if (try builder.addUserInputOption(option_name, option_value))
                    fatal("  access the help menu with 'zig build -h'", .{});
            } else {
                if (try builder.addUserInputFlag(option_contents))
                    fatal("  access the help menu with 'zig build -h'", .{});
            }
        } else if (mem.startsWith(u8, arg, "-")) {
            if (mem.eql(u8, arg, "--verbose")) {
                builder.verbose = true;
            } else if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
                fatal("argument '{s}' is not available", .{arg});
            } else if (mem.eql(u8, arg, "-p") or mem.eql(u8, arg, "--prefix")) {
                install_prefix = nextArgOrFatal(args, &arg_idx);
            } else if (mem.eql(u8, arg, "-l") or mem.eql(u8, arg, "--list-steps")) {
                fatal("argument '{s}' is not available", .{arg});
            } else if (mem.startsWith(u8, arg, "-fsys=")) {
                const name = arg["-fsys=".len..];
                graph.system_library_options.put(arena, name, .user_enabled) catch @panic("OOM");
            } else if (mem.startsWith(u8, arg, "-fno-sys=")) {
                const name = arg["-fno-sys=".len..];
                graph.system_library_options.put(arena, name, .user_disabled) catch @panic("OOM");
            } else if (mem.eql(u8, arg, "--release")) {
                builder.release_mode = .any;
            } else if (mem.startsWith(u8, arg, "--release=")) {
                const text = arg["--release=".len..];
                builder.release_mode = std.meta.stringToEnum(std.Build.ReleaseMode, text) orelse {
                    fatal("expected [off|any|fast|safe|small] in '{s}', found '{s}'", .{
                        arg, text,
                    });
                };
            } else if (mem.eql(u8, arg, "--prefix-lib-dir")) {
                dir_list.lib_dir = nextArgOrFatal(args, &arg_idx);
            } else if (mem.eql(u8, arg, "--prefix-exe-dir")) {
                dir_list.exe_dir = nextArgOrFatal(args, &arg_idx);
            } else if (mem.eql(u8, arg, "--prefix-include-dir")) {
                dir_list.include_dir = nextArgOrFatal(args, &arg_idx);
            } else if (mem.eql(u8, arg, "--sysroot")) {
                builder.sysroot = nextArgOrFatal(args, &arg_idx);
            } else if (mem.eql(u8, arg, "--maxrss")) {
                const max_rss_text = nextArgOrFatal(args, &arg_idx);
                max_rss = std.fmt.parseIntSizeSuffix(max_rss_text, 10) catch |err| {
                    std.debug.print("invalid byte size: '{s}': {s}\n", .{
                        max_rss_text, @errorName(err),
                    });
                    process.exit(1);
                };
            } else if (mem.eql(u8, arg, "--skip-oom-steps")) {
                skip_oom_steps = true;
            } else if (mem.eql(u8, arg, "--search-prefix")) {
                const search_prefix = nextArgOrFatal(args, &arg_idx);
                builder.addSearchPrefix(search_prefix);
            } else if (mem.eql(u8, arg, "--libc")) {
                builder.libc_file = nextArgOrFatal(args, &arg_idx);
            } else if (mem.eql(u8, arg, "--color")) {
                const next_arg = nextArg(args, &arg_idx) orelse
                    fatal("expected [auto|on|off] after '{s}'", .{arg});
                _ = next_arg;
            } else if (mem.eql(u8, arg, "--summary")) {
                const next_arg = nextArg(args, &arg_idx) orelse
                    fatal("expected [all|new|failures|none] after '{s}'", .{arg});
                _ = next_arg;
            } else if (mem.eql(u8, arg, "--seed")) {
                const next_arg = nextArg(args, &arg_idx) orelse
                    fatal("expected u32 after '{s}'", .{arg});
                seed = std.fmt.parseUnsigned(u32, next_arg, 0) catch |err| {
                    fatal("unable to parse seed '{s}' as unsigned 32-bit integer: {s}\n", .{
                        next_arg, @errorName(err),
                    });
                };
            } else if (mem.eql(u8, arg, "--debounce")) {
                const next_arg = nextArg(args, &arg_idx) orelse
                    fatal("expected u16 after '{s}'", .{arg});
                debounce_interval_ms = std.fmt.parseUnsigned(u16, next_arg, 0) catch |err| {
                    fatal("unable to parse debounce interval '{s}' as unsigned 16-bit integer: {s}\n", .{
                        next_arg, @errorName(err),
                    });
                };
            } else if (mem.eql(u8, arg, "--debug-log")) {
                const next_arg = nextArgOrFatal(args, &arg_idx);
                try debug_log_scopes.append(next_arg);
            } else if (mem.eql(u8, arg, "--debug-pkg-config")) {
                builder.debug_pkg_config = true;
            } else if (mem.eql(u8, arg, "--debug-compile-errors")) {
                builder.debug_compile_errors = true;
            } else if (mem.eql(u8, arg, "--system")) {
                // The usage text shows another argument after this parameter
                // but it is handled by the parent process. The build runner
                // only sees this flag.
                graph.system_package_mode = true;
            } else if (mem.eql(u8, arg, "--libc-runtimes") or mem.eql(u8, arg, "--glibc-runtimes")) {
                if (@hasField(std.Build, "glibc_runtimes_dir")) {
                    builder.glibc_runtimes_dir = nextArgOrFatal(args, &arg_idx);
                } else {
                    builder.libc_runtimes_dir = nextArgOrFatal(args, &arg_idx);
                }
            } else if (mem.eql(u8, arg, "--verbose-link")) {
                builder.verbose_link = true;
            } else if (mem.eql(u8, arg, "--verbose-air")) {
                builder.verbose_air = true;
            } else if (mem.eql(u8, arg, "--verbose-llvm-ir")) {
                builder.verbose_llvm_ir = "-";
            } else if (mem.startsWith(u8, arg, "--verbose-llvm-ir=")) {
                builder.verbose_llvm_ir = arg["--verbose-llvm-ir=".len..];
            } else if (mem.eql(u8, arg, "--verbose-llvm-bc=")) {
                builder.verbose_llvm_bc = arg["--verbose-llvm-bc=".len..];
            } else if (mem.eql(u8, arg, "--verbose-cc")) {
                builder.verbose_cc = true;
            } else if (mem.eql(u8, arg, "--verbose-llvm-cpu-features")) {
                builder.verbose_llvm_cpu_features = true;
            } else if (mem.eql(u8, arg, "--prominent-compile-errors")) {
                // prominent_compile_errors = true;
            } else if (mem.eql(u8, arg, "--watch")) {
                watch = true;
            } else if (mem.eql(u8, arg, "--check-only")) { // ZLS only
                check_step_only = true;
            } else if (mem.eql(u8, arg, "--dont-create-roots-txt-file")) {
                dont_create_roots_txt_file = true;
            } else if (mem.eql(u8, arg, "-fincremental")) {
                graph.incremental = true;
            } else if (mem.eql(u8, arg, "-fno-incremental")) {
                graph.incremental = false;
            } else if (mem.eql(u8, arg, "-fwine")) {
                builder.enable_wine = true;
            } else if (mem.eql(u8, arg, "-fno-wine")) {
                builder.enable_wine = false;
            } else if (mem.eql(u8, arg, "-fqemu")) {
                builder.enable_qemu = true;
            } else if (mem.eql(u8, arg, "-fno-qemu")) {
                builder.enable_qemu = false;
            } else if (mem.eql(u8, arg, "-fwasmtime")) {
                builder.enable_wasmtime = true;
            } else if (mem.eql(u8, arg, "-fno-wasmtime")) {
                builder.enable_wasmtime = false;
            } else if (mem.eql(u8, arg, "-frosetta")) {
                builder.enable_rosetta = true;
            } else if (mem.eql(u8, arg, "-fno-rosetta")) {
                builder.enable_rosetta = false;
            } else if (mem.eql(u8, arg, "-fdarling")) {
                builder.enable_darling = true;
            } else if (mem.eql(u8, arg, "-fno-darling")) {
                builder.enable_darling = false;
            } else if (mem.eql(u8, arg, "-freference-trace")) {
                builder.reference_trace = 256;
            } else if (mem.startsWith(u8, arg, "-freference-trace=")) {
                const num = arg["-freference-trace=".len..];
                builder.reference_trace = std.fmt.parseUnsigned(u32, num, 10) catch |err| {
                    std.debug.print("unable to parse reference_trace count '{s}': {s}", .{ num, @errorName(err) });
                    process.exit(1);
                };
            } else if (mem.eql(u8, arg, "-fno-reference-trace")) {
                builder.reference_trace = null;
            } else if (mem.startsWith(u8, arg, "-j")) {
                const num = arg["-j".len..];
                const n_jobs = std.fmt.parseUnsigned(u32, num, 10) catch |err| {
                    std.debug.print("unable to parse jobs count '{s}': {s}", .{
                        num, @errorName(err),
                    });
                    process.exit(1);
                };
                if (n_jobs < 1) {
                    std.debug.print("number of jobs must be at least 1\n", .{});
                    process.exit(1);
                }
                threaded.setAsyncLimit(.limited(n_jobs));
            } else if (mem.eql(u8, arg, "--")) {
                builder.args = argsRest(args, arg_idx);
                break;
            } else {
                fatal("unrecognized argument: '{s}'", .{arg});
            }
        } else {
            try targets.append(arg);
        }
    }

    const main_progress_node = std.Progress.start(io, .{
        .disable_printing = true,
    });
    defer main_progress_node.end();

    builder.debug_log_scopes = debug_log_scopes.items;
    builder.resolveInstallPrefix(install_prefix, dir_list);
    {
        var prog_node = main_progress_node.start("Configure", 0);
        defer prog_node.end();
        try builder.runBuild(root);
        createModuleDependencies(builder) catch @panic("OOM");
    }

    if (graph.needed_lazy_dependencies.entries.len != 0) {
        var buffer: ArrayList(u8) = .empty;
        for (graph.needed_lazy_dependencies.keys()) |k| {
            try buffer.appendSlice(arena, k);
            try buffer.append(arena, '\n');
        }
        const s = std.fs.path.sep_str;
        const tmp_sub_path = "tmp" ++ s ++ (output_tmp_nonce orelse fatal("missing -Z arg", .{}));

        local_cache_directory.handle.writeFile(io, .{
            .sub_path = tmp_sub_path,
            .data = buffer.items,
            .flags = .{ .exclusive = true },
        }) catch |err| {
            fatal("unable to write configuration results to '{f}{s}': {}", .{
                local_cache_directory, tmp_sub_path, err,
            });
        };

        process.exit(3); // Indicate configure phase failed with meaningful stdout.
    }

    if (builder.validateUserInputDidItFail()) {
        fatal("  access the help menu with 'zig build -h'", .{});
    }

    validateSystemLibraryOptions(builder);

    var run: Run = .{
        .gpa = arena,
        .available_rss = max_rss,
        .max_rss_is_default = false,
        .max_rss_mutex = .init,
        .skip_oom_steps = skip_oom_steps,
        .memory_blocked_steps = .init(arena),

        .watch = watch,
        .cycle = 0,
    };

    if (run.available_rss == 0) {
        run.available_rss = process.totalSystemMemory() catch std.math.maxInt(u64);
        run.max_rss_is_default = true;
    }

    if (!watch) {
        try extractBuildInformation(
            arena,
            builder,
            arena,
            main_progress_node,
            &run,
            seed,
        );
        return;
    }

    var w = try Watch.init(io, graph.cache.cwd);

    const message_thread = try std.Thread.spawn(.{}, struct {
        fn do(ww: *Watch) void {
            while (true) {
                var buffer: [1]u8 = undefined;
                var stdin_reader = std.Io.File.stdin().reader(ww.io, &buffer);
                const byte = stdin_reader.interface.takeByte() catch |err| switch (err) {
                    error.ReadFailed => process.exit(1),
                    error.EndOfStream => process.exit(0),
                };
                switch (byte) {
                    '\x00' => ww.trigger(),
                    else => process.exit(1),
                }
            }
        }
    }.do, .{&w});
    message_thread.detach();

    const gpa = arena;

    var step_stack = try stepNamesToStepStack(gpa, builder, targets.items, check_step_only);
    if (step_stack.count() == 0) {
        // This means that `enable_build_on_save == null` and the project contains no "check" step.
        return;
    }

    prepare(gpa, builder, &step_stack, &run, seed) catch |err| switch (err) {
        error.UncleanExit => process.exit(1),
        else => return err,
    };

    rebuild: while (true) : (run.cycle += 1) {
        runSteps(
            gpa,
            builder,
            &step_stack,
            main_progress_node,
            &run,
        ) catch |err| switch (err) {
            error.UncleanExit => process.exit(1),
            else => return err,
        };

        try w.update(gpa, step_stack.keys());

        // Wait until a file system notification arrives. Read all such events
        // until the buffer is empty. Then wait for a debounce interval, resetting
        // if any more events come in. After the debounce interval has passed,
        // trigger a rebuild on all steps with modified inputs, as well as their
        // recursive dependants.
        var debounce_timeout: std.Io.Timeout = .none;
        while (true) switch (try w.wait(gpa, debounce_timeout)) {
            .timeout => {
                markFailedStepsDirty(gpa, step_stack.keys());
                continue :rebuild;
            },
            .dirty => if (debounce_timeout == .none) {
                debounce_timeout = .{ .duration = .{ .raw = .fromMilliseconds(debounce_interval_ms), .clock = .real } };
            },
            .clean => {},
        };
    }
}

fn markFailedStepsDirty(gpa: Allocator, all_steps: []const *Step) void {
    for (all_steps) |step| switch (step.state) {
        .dependency_failure, .failure, .skipped => _ = step.invalidateResult(gpa),
        else => continue,
    };
    // Now that all dirty steps have been found, the remaining steps that
    // succeeded from last run shall be marked "cached".
    for (all_steps) |step| switch (step.state) {
        .success => step.result_cached = true,
        else => continue,
    };
}

/// A wrapper around `std.Build.Watch` that supports manually triggering recompilations.
const Watch = struct {
    io: std.Io,
    fs_watch: std.Build.Watch,
    supports_fs_watch: bool,
    manual_event: std.Io.Event,
    steps: []const *Step,

    fn init(io: std.Io, cwd_path: []const u8) !Watch {
        return .{
            .io = io,
            .fs_watch = if (@TypeOf(std.Build.Watch) != void) try std.Build.Watch.init(cwd_path) else {},
            .supports_fs_watch = @TypeOf(std.Build.Watch) != void and shared.BuildOnSaveSupport.isSupportedRuntime(builtin.zig_version) == .supported,
            .manual_event = .unset,
            .steps = &.{},
        };
    }

    fn update(w: *Watch, gpa: Allocator, steps: []const *Step) !void {
        if (@TypeOf(std.Build.Watch) != void and w.supports_fs_watch) {
            return try w.fs_watch.update(gpa, steps);
        }
        w.steps = steps;
    }

    fn trigger(w: *Watch) void {
        if (w.supports_fs_watch) {
            @panic("received manualy filesystem event even though std.Build.Watch is supported");
        }
        w.manual_event.set(w.io);
    }

    fn wait(w: *Watch, gpa: Allocator, timeout: std.Io.Timeout) !std.Build.Watch.WaitResult {
        if (@TypeOf(std.Build.Watch) != void and w.supports_fs_watch) {
            return try w.fs_watch.wait(gpa, w.io, switch (timeout) {
                .none => .none,
                .duration => |d| .{ .ms = @intCast(d.raw.toMilliseconds()) },
                .deadline => unreachable,
            });
        }
        w.manual_event.waitTimeout(w.io, timeout) catch |err| switch (err) {
            error.Canceled => unreachable,
            error.Timeout => return .timeout,
        };
        w.manual_event.reset();
        markStepsDirty(gpa, w.steps);
        return .dirty;
    }

    fn markStepsDirty(gpa: Allocator, all_steps: []const *Step) void {
        for (all_steps) |step| switch (step.state) {
            .precheck_done => continue,
            else => _ = step.invalidateResult(gpa),
        };
    }
};

const Run = struct {
    gpa: Allocator,
    available_rss: usize,
    max_rss_is_default: bool,
    max_rss_mutex: std.Io.Mutex,
    skip_oom_steps: bool,
    memory_blocked_steps: ArrayListManaged(*Step),

    watch: bool,
    cycle: u32,
};

fn stepNamesToStepStack(
    gpa: Allocator,
    b: *std.Build,
    step_names: []const []const u8,
    check_step_only: bool,
) !std.AutoArrayHashMapUnmanaged(*Step, void) {
    var step_stack: std.AutoArrayHashMapUnmanaged(*Step, void) = .{};
    errdefer step_stack.deinit(gpa);

    if (step_names.len == 0) {
        if (b.top_level_steps.get("check")) |tls| {
            try step_stack.put(gpa, &tls.step, {});
        } else if (!check_step_only) {
            try step_stack.put(gpa, b.default_step, {});
        }
    } else {
        try step_stack.ensureUnusedCapacity(gpa, step_names.len);
        for (0..step_names.len) |i| {
            const step_name = step_names[step_names.len - i - 1];
            const s = b.top_level_steps.get(step_name) orelse {
                std.debug.print("no step named '{s}'\n  access the help menu with 'zig build -h'\n", .{step_name});
                process.exit(1);
            };
            step_stack.putAssumeCapacity(&s.step, {});
        }
    }

    return step_stack;
}

fn prepare(
    gpa: Allocator,
    b: *std.Build,
    step_stack: *std.AutoArrayHashMapUnmanaged(*Step, void),
    run: *Run,
    seed: u32,
) error{ OutOfMemory, UncleanExit }!void {
    const starting_steps = try gpa.dupe(*Step, step_stack.keys());
    defer gpa.free(starting_steps);

    var rng = std.Random.DefaultPrng.init(seed);
    const rand = rng.random();
    rand.shuffle(*Step, starting_steps);

    for (starting_steps) |s| {
        constructGraphAndCheckForDependencyLoop(b, s, step_stack, rand) catch |err| switch (err) {
            error.DependencyLoopDetected => {
                _ = b.graph.io.lockStderr(&.{}, b.graph.stderr_mode) catch {};
                process.exit(1);
            },
            else => |e| return e,
        };
    }

    {
        // Check that we have enough memory to complete the build.
        var any_problems = false;
        for (step_stack.keys()) |s| {
            if (s.max_rss == 0) continue;
            if (s.max_rss > run.available_rss) {
                if (run.skip_oom_steps) {
                    s.state = .skipped_oom;
                    for (s.dependants.items) |dependant| {
                        dependant.pending_deps -= 1;
                    }
                } else {
                    std.debug.print("{s}{s}: this step declares an upper bound of {d} bytes of memory, exceeding the available {d} bytes of memory\n", .{
                        s.owner.dep_prefix, s.name, s.max_rss, run.available_rss,
                    });
                    any_problems = true;
                }
            }
        }
        if (any_problems) {
            if (run.max_rss_is_default) {
                std.debug.print("note: use --maxrss to override the default", .{});
            }
        }
    }
}

fn runSteps(
    gpa: std.mem.Allocator,
    b: *std.Build,
    steps_stack: *const std.AutoArrayHashMapUnmanaged(*Step, void),
    parent_prog_node: std.Progress.Node,
    run: *Run,
) error{ OutOfMemory, UncleanExit, Canceled }!void {
    const io = b.graph.io;
    const steps = steps_stack.keys();

    {
        // Collect the initial set of tasks (those with no outstanding dependencies) into a buffer,
        // then spawn them. The buffer is so that we don't race with `makeStep` and end up thinking
        // a step is initial when it actually became ready due to an earlier initial step.
        var initial_set: std.ArrayList(*Step) = .empty;
        defer initial_set.deinit(gpa);
        try initial_set.ensureUnusedCapacity(gpa, steps_stack.count());
        for (steps_stack.keys()) |s| {
            if (s.state == .precheck_done and s.pending_deps == 0) {
                initial_set.appendAssumeCapacity(s);
            }
        }

        var step_prog = parent_prog_node.start("steps", steps.len);
        defer step_prog.end();

        var group: std.Io.Group = .init;
        defer group.cancel(io);

        // Start working on all of the initial steps...
        for (initial_set.items) |s| try stepReady(&group, b, steps_stack, s, step_prog, run);
        // ...and `makeStep` will trigger every other step when their last dependency finishes.    }

        try group.await(io);
    }
}

/// Traverse the dependency graph depth-first and make it undirected by having
/// steps know their dependants (they only know dependencies at start).
/// Along the way, check that there is no dependency loop, and record the steps
/// in traversal order in `step_stack`.
/// Each step has its dependencies traversed in random order, this accomplishes
/// two things:
/// - `step_stack` will be in randomized-depth-first order, so the build runner
///   spawns steps in a random (but optimized) order
/// - each step's `dependants` list is also filled in a random order, so that
///   when it finishes executing in `workerMakeOneStep`, it spawns next steps
///   to run in random order
fn constructGraphAndCheckForDependencyLoop(
    b: *std.Build,
    s: *Step,
    step_stack: *std.AutoArrayHashMapUnmanaged(*Step, void),
    rand: std.Random,
) error{ OutOfMemory, DependencyLoopDetected }!void {
    switch (s.state) {
        .precheck_started => return error.DependencyLoopDetected,
        .precheck_unstarted => {
            s.state = .precheck_started;

            try step_stack.ensureUnusedCapacity(b.allocator, s.dependencies.items.len);

            // We dupe to avoid shuffling the steps in the summary, it depends
            // on s.dependencies' order.
            const deps = b.allocator.dupe(*Step, s.dependencies.items) catch @panic("OOM");
            rand.shuffle(*Step, deps);

            for (deps) |dep| {
                try step_stack.put(b.allocator, dep, {});
                try dep.dependants.append(b.allocator, s);
                try constructGraphAndCheckForDependencyLoop(b, dep, step_stack, rand);
            }

            s.state = .precheck_done;
            s.pending_deps = @intCast(s.dependencies.items.len);
        },
        .precheck_done => {},

        // These don't happen until we actually run the step graph.
        .dependency_failure,
        .success,
        .failure,
        .skipped,
        .skipped_oom,
        => {},
    }
}

/// Runs the "make" function of the single step `s`, updates its state, and then spawns newly-ready
/// dependant steps in `group`. If `s` makes an RSS claim (i.e. `s.max_rss != 0`), the caller must
/// have already subtracted this value from `run.available_rss`. This function will release the RSS
/// claim (i.e. add `s.max_rss` back into `run.available_rss`) and queue any viable memory-blocked
/// steps after "make" completes for `s`.
fn makeStep(
    group: *std.Io.Group,
    b: *std.Build,
    steps_stack: *const std.AutoArrayHashMapUnmanaged(*Step, void),
    s: *Step,
    root_prog_node: std.Progress.Node,
    run: *Run,
) std.Io.Cancelable!void {
    const io = b.graph.io;
    const gpa = run.gpa;

    {
        const step_prog_node = root_prog_node.start(s.name, 0);
        defer step_prog_node.end();

        const new_state: Step.State = for (s.dependencies.items) |dep| {
            switch (@atomicLoad(Step.State, &dep.state, .monotonic)) {
                .precheck_unstarted => unreachable,
                .precheck_started => unreachable,
                .precheck_done => unreachable,

                .failure,
                .dependency_failure,
                .skipped_oom,
                => break .dependency_failure,

                .success, .skipped => {},
            }
        } else if (s.make(.{
            .progress_node = step_prog_node,
            .watch = run.watch,
            .web_server = null,
            .unit_test_timeout_ns = null,
            .gpa = gpa,
        })) state: {
            break :state .success;
        } else |err| switch (err) {
            error.MakeFailed => .failure,
            error.MakeSkipped => .skipped,
        };

        @atomicStore(Step.State, &s.state, new_state, .monotonic);

        switch (new_state) {
            .precheck_unstarted => unreachable,
            .precheck_started => unreachable,
            .precheck_done => unreachable,

            .failure,
            .dependency_failure,
            .skipped_oom,
            => {
                std.Progress.setStatus(.failure_working);
            },

            .success,
            .skipped,
            => {},
        }
    }

    if (run.watch) {
        const step_id: u32 = @intCast(steps_stack.getIndex(s).?);
        // missing fields:
        // - result_error_msgs
        // - result_stderr
        serveWatchErrorBundle(b.graph.io, step_id, run.cycle, s.result_error_bundle) catch @panic("failed to send watch errors");
    }

    if (s.max_rss != 0) {
        var dispatch_set: std.ArrayList(*Step) = .empty;
        defer dispatch_set.deinit(gpa);

        // Release our RSS claim and kick off some blocked steps if possible. We use `dispatch_set`
        // as a staging buffer to avoid recursing into `makeStep` while `run.max_rss_mutex` is held.
        {
            try run.max_rss_mutex.lock(io);
            defer run.max_rss_mutex.unlock(io);
            run.available_rss += s.max_rss;
            dispatch_set.ensureUnusedCapacity(gpa, run.memory_blocked_steps.items.len) catch @panic("OOM");
            while (run.memory_blocked_steps.getLastOrNull()) |candidate| {
                if (run.available_rss < candidate.max_rss) break;
                assert(run.memory_blocked_steps.pop() == candidate);
                dispatch_set.appendAssumeCapacity(candidate);
            }
        }
        for (dispatch_set.items) |candidate| {
            group.async(io, makeStep, .{ group, b, steps_stack, candidate, root_prog_node, run });
        }
    }

    for (s.dependants.items) |dependant| {
        // `.acq_rel` synchronizes with itself to ensure all dependencies' final states are visible when this hits 0.
        if (@atomicRmw(u32, &dependant.pending_deps, .Sub, 1, .acq_rel) == 1) {
            try stepReady(group, b, steps_stack, dependant, root_prog_node, run);
        }
    }
}

fn stepReady(
    group: *std.Io.Group,
    b: *std.Build,
    steps_stack: *const std.AutoArrayHashMapUnmanaged(*Step, void),
    s: *Step,
    root_prog_node: std.Progress.Node,
    run: *Run,
) !void {
    const io = b.graph.io;
    if (s.max_rss != 0) {
        try run.max_rss_mutex.lock(io);
        defer run.max_rss_mutex.unlock(io);
        if (run.available_rss < s.max_rss) {
            // Running this step right now could possibly exceed the allotted RSS.
            run.memory_blocked_steps.append(s) catch @panic("OOM");
            return;
        }
        run.available_rss -= s.max_rss;
    }
    group.async(io, makeStep, .{ group, b, steps_stack, s, root_prog_node, run });
}

fn nextArg(args: []const [:0]const u8, idx: *usize) ?[:0]const u8 {
    if (idx.* >= args.len) return null;
    defer idx.* += 1;
    return args[idx.*];
}

fn nextArgOrFatal(args: []const [:0]const u8, idx: *usize) [:0]const u8 {
    return nextArg(args, idx) orelse {
        std.debug.print("expected argument after '{s}'\n  access the help menu with 'zig build -h'\n", .{args[idx.* - 1]});
        process.exit(1);
    };
}

fn argsRest(args: []const [:0]const u8, idx: usize) ?[]const [:0]const u8 {
    if (idx >= args.len) return null;
    return args[idx..];
}

/// Perhaps in the future there could be an Advanced Options flag such as
/// --debug-build-runner-leaks which would make this function return instead of
/// calling exit.
fn cleanExit() void {
    std.debug.lockStdErr();
    process.exit(0);
}

fn fatal(comptime f: []const u8, args: anytype) noreturn {
    std.debug.print(f ++ "\n", args);
    process.exit(1);
}

fn validateSystemLibraryOptions(b: *std.Build) void {
    var bad = false;
    for (b.graph.system_library_options.keys(), b.graph.system_library_options.values()) |k, v| {
        switch (v) {
            .user_disabled, .user_enabled => {
                // The user tried to enable or disable a system library integration, but
                // the build script did not recognize that option.
                std.debug.print("system library name not recognized by build script: '{s}'\n", .{k});
                bad = true;
            },
            .declared_disabled, .declared_enabled => {},
        }
    }
    if (bad) {
        std.debug.print("  access the help menu with 'zig build -h'\n", .{});
        process.exit(1);
    }
}

/// Starting from all top-level steps in `b`, traverses the entire step graph
/// and adds all step dependencies implied by module graphs.
fn createModuleDependencies(b: *std.Build) Allocator.Error!void {
    const arena = b.graph.arena;

    var all_steps: std.AutoArrayHashMapUnmanaged(*Step, void) = .empty;
    var next_step_idx: usize = 0;

    try all_steps.ensureUnusedCapacity(arena, b.top_level_steps.count());
    for (b.top_level_steps.values()) |tls| {
        all_steps.putAssumeCapacityNoClobber(&tls.step, {});
    }

    while (next_step_idx < all_steps.count()) {
        const step = all_steps.keys()[next_step_idx];
        next_step_idx += 1;

        // Set up any implied dependencies for this step. It's important that we do this first, so
        // that the loop below discovers steps implied by the module graph.
        try createModuleDependenciesForStep(step);

        try all_steps.ensureUnusedCapacity(arena, step.dependencies.items.len);
        for (step.dependencies.items) |other_step| {
            all_steps.putAssumeCapacity(other_step, {});
        }
    }
}

/// If the given `Step` is a `Step.Compile`, adds any dependencies for that step which
/// are implied by the module graph rooted at `step.cast(Step.Compile).?.root_module`.
fn createModuleDependenciesForStep(step: *Step) Allocator.Error!void {
    const root_module = if (step.cast(Step.Compile)) |cs| root: {
        break :root cs.root_module;
    } else return; // not a compile step so no module dependencies

    // Starting from `root_module`, discover all modules in this graph.
    const modules = root_module.getGraph().modules;

    // For each of those modules, set up the implied step dependencies.
    for (modules) |mod| {
        if (mod.root_source_file) |lp| lp.addStepDependencies(step);
        for (mod.include_dirs.items) |include_dir| switch (include_dir) {
            .path,
            .path_system,
            .path_after,
            .framework_path,
            .framework_path_system,
            .embed_path,
            => |lp| lp.addStepDependencies(step),

            .other_step => |other| {
                other.getEmittedIncludeTree().addStepDependencies(step);
                step.dependOn(&other.step);
            },

            .config_header_step => |config_header| step.dependOn(&config_header.step),
        };
        for (mod.lib_paths.items) |lp| lp.addStepDependencies(step);
        for (mod.rpaths.items) |rpath| switch (rpath) {
            .lazy_path => |lp| lp.addStepDependencies(step),
            .special => {},
        };
        for (mod.link_objects.items) |link_object| switch (link_object) {
            .static_path,
            .assembly_file,
            => |lp| lp.addStepDependencies(step),
            .other_step => |other| step.dependOn(&other.step),
            .system_lib => {},
            .c_source_file => |source| source.file.addStepDependencies(step),
            .c_source_files => |source_files| source_files.root.addStepDependencies(step),
            .win32_resource_file => |rc_source| {
                rc_source.file.addStepDependencies(step);
                for (rc_source.include_paths) |lp| lp.addStepDependencies(step);
            },
        };
    }
}

//
//
// ZLS code
//
//

const shared = @import("shared.zig");
const Transport = shared.Transport;
const BuildConfig = shared.BuildConfig;

const Packages = struct {
    allocator: std.mem.Allocator,

    /// Outer key is the package name, inner key is the file path.
    packages: std.StringArrayHashMapUnmanaged(std.StringArrayHashMapUnmanaged(void)) = .{},

    /// Returns true if the package was already present.
    pub fn addPackage(self: *Packages, name: []const u8, path: []const u8) !bool {
        const name_gop_result = try self.packages.getOrPutValue(self.allocator, name, .{});
        const path_gop_result = try name_gop_result.value_ptr.getOrPut(self.allocator, path);
        return path_gop_result.found_existing;
    }

    pub fn toPackageList(self: *Packages) ![]BuildConfig.NamePathPair {
        var result: ArrayList(BuildConfig.NamePathPair) = .empty;
        errdefer result.deinit(self.allocator);

        const Context = struct {
            keys: [][]const u8,

            pub fn lessThan(ctx: @This(), a_index: usize, b_index: usize) bool {
                return std.mem.lessThan(u8, ctx.keys[a_index], ctx.keys[b_index]);
            }
        };

        self.packages.sort(Context{ .keys = self.packages.keys() });

        for (self.packages.keys(), self.packages.values()) |name, path_hashmap| {
            for (path_hashmap.keys()) |path| {
                try result.append(self.allocator, .{ .name = name, .path = path });
            }
        }

        return try result.toOwnedSlice(self.allocator);
    }

    pub fn deinit(self: *Packages) void {
        for (self.packages.values()) |*path_hashmap| {
            path_hashmap.deinit(self.allocator);
        }
        self.packages.deinit(self.allocator);
    }
};

const roots_info = struct {
    pub const RootEntry = struct {
        step: *Step.Compile,
        mods: []BuildConfig.NamePathPair,
    };

    pub fn collect(
        gpa: std.mem.Allocator,
        step: *Step,
        visited_steps: *std.AutoArrayHashMapUnmanaged(*Step, void),
        unsorted_roots: *std.ArrayListUnmanaged(RootEntry),
        build_root_path: [:0]const u8,
    ) !void {
        const gop_result = try visited_steps.getOrPut(gpa, step);
        if (gop_result.found_existing) return;
        if (step.cast(Step.Compile)) |compile| {
            // if (compile.kind.isTest()) return;
            var root_imports: std.ArrayListUnmanaged(BuildConfig.NamePathPair) = .empty;

            var cli_named_modules = try copied_from_zig.CliNamedModules.init(gpa, compile.root_module);
            for (compile.getCompileDependencies(false)) |dep_compile| {
                for (dep_compile.root_module.getGraph().modules) |mod| {
                    if (!(dep_compile == compile)) continue; // !my_responsibility
                    if (cli_named_modules.modules.getIndex(mod)) |module_cli_index| {
                        const module_cli_name = cli_named_modules.names.keys()[module_cli_index];
                        if (mod.root_source_file) |lp| {
                            var src = lp.getPath2(mod.owner, step);
                            if (!std.fs.path.isAbsolute(src)) src = try std.fs.path.join(gpa, &.{ build_root_path, src });
                            // std.log.debug("-M{s}={s}\n", .{ module_cli_name, src });
                            try root_imports.append(gpa, .{ .name = module_cli_name, .path = src });
                        }
                    }
                }
            }
            try unsorted_roots.append(
                gpa,
                .{
                    .step = compile,
                    .mods = try root_imports.toOwnedSlice(gpa),
                },
            );
            root_imports.items.len = 0; // clearRetainingCapacity();
        }
        for (step.dependencies.items) |dep_step| try collect(
            gpa,
            dep_step,
            visited_steps,
            unsorted_roots,
            build_root_path,
        );
    }

    pub const hasPrecedenceContext = struct {
        build_root_path: []const u8,
        zig_pkg_path: []const u8,
    };

    pub fn hasPrecedence(ctx: hasPrecedenceContext, lhs: RootEntry, rhs: RootEntry) bool {
        if (lhs.mods.len == 0) return false; // C compile steps should be last
        if (rhs.mods.len == 0) return true; //  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
        const lhs_dir_name = std.fs.path.dirname(lhs.mods[0].path).?; // [0] should be 'root'
        const rhs_dir_name = std.fs.path.dirname(rhs.mods[0].path).?; // [0] should be 'root'
        if (std.mem.startsWith(u8, lhs_dir_name, ctx.zig_pkg_path) and !std.mem.startsWith(u8, rhs_dir_name, ctx.zig_pkg_path)) return false;
        if (std.mem.startsWith(u8, rhs_dir_name, ctx.zig_pkg_path) and !std.mem.startsWith(u8, lhs_dir_name, ctx.zig_pkg_path)) return true;
        if (std.mem.startsWith(u8, lhs_dir_name, ctx.build_root_path) and !std.mem.startsWith(u8, rhs_dir_name, ctx.build_root_path)) return true;
        if (std.mem.startsWith(u8, rhs_dir_name, ctx.build_root_path) and !std.mem.startsWith(u8, lhs_dir_name, ctx.build_root_path)) return false;
        if (@intFromEnum(lhs.step.kind) < @intFromEnum(rhs.step.kind)) return true;
        if (@intFromEnum(rhs.step.kind) < @intFromEnum(lhs.step.kind)) return false;
        return (lhs_dir_name.len < rhs_dir_name.len);
    }

    pub fn print(
        gpa: std.mem.Allocator,
        roots_info_slc: *std.ArrayList(u8),
        idx: *u32,
        compile: *Step.Compile,
        zig_args: *const [][]const u8,
    ) !void {
        if (compile.root_module.root_source_file) |root_source_file| {
            try roots_info_slc.print(
                gpa,
                "#{}: \"{s}\" : [\"root\" : '{s}']",
                .{
                    idx.*,
                    compile.name,
                    root_source_file.getPath(compile.root_module.owner),
                },
            );
            if (compile.root_module.resolved_target) |target| {
                if (!target.query.isNative()) {
                    try roots_info_slc.print(gpa, " ~ {s} {s}", .{
                        try target.query.zigTriple(gpa),
                        try target.query.serializeCpuAlloc(gpa),
                    });
                }
            }
            try roots_info_slc.print(gpa, "\n", .{});
        }
        try printIt(
            gpa,
            roots_info_slc,
            compile.root_module.import_table,
        );
        try roots_info_slc.print(gpa, "    CMD:", .{});
        for (zig_args.*) |arg| try roots_info_slc.print(gpa, " {s}", .{arg});
        try roots_info_slc.print(gpa, "\n    ----\n", .{});
        idx.* += 1;
    }

    pub fn printIt(
        gpa: std.mem.Allocator,
        roots_info_slc: *std.ArrayList(u8),
        it: std.StringArrayHashMapUnmanaged(*std.Build.Module),
    ) !void {
        for (it.keys(), it.values()) |name, import| {
            if (import.root_source_file) |root_source_file| {
                try roots_info_slc.print(
                    gpa,
                    "    [\"{s}\" : '{s}']\n",
                    .{ name, root_source_file.getPath(import.owner) },
                );
            }
            for (import.import_table.keys(), import.import_table.values()) |name2, import2| {
                if (import2.root_source_file) |root_source_file2| {
                    try roots_info_slc.print(
                        gpa,
                        "        [\"{s}\" : '{s}']\n",
                        .{ name2, root_source_file2.getPath(import.owner) },
                    );
                }
                for (import2.import_table.keys(), import2.import_table.values()) |name3, import3| {
                    if (import3.root_source_file) |root_source_file3| {
                        try roots_info_slc.print(
                            gpa,
                            "            [\"{s}\" : '{s}']\n",
                            .{ name3, root_source_file3.getPath(import.owner) },
                        );
                    }
                }
            }
        }
    }
};

fn extractBuildInformation(
    gpa: Allocator,
    b: *std.Build,
    arena: Allocator,
    main_progress_node: std.Progress.Node,
    run: *Run,
    seed: u32,
) !void {
    var steps = std.AutoArrayHashMapUnmanaged(*Step, void){};
    defer steps.deinit(gpa);

    // collect the set of all steps
    {
        var stack: ArrayList(*Step) = .empty;
        defer stack.deinit(gpa);

        try stack.ensureUnusedCapacity(gpa, b.top_level_steps.count());
        for (b.top_level_steps.values()) |tls| {
            if (std.mem.eql(u8, tls.step.name, "uninstall")) continue;
            stack.appendAssumeCapacity(&tls.step);
        }

        while (stack.pop()) |step| {
            const gop = try steps.getOrPut(gpa, step);
            if (gop.found_existing) continue;

            try stack.appendSlice(gpa, step.dependencies.items);
        }
    }

    const helper = struct {
        fn addLazyPathStepDependencies(allocator: Allocator, set: *std.AutoArrayHashMapUnmanaged(*Step, void), lazy_path: std.Build.LazyPath) !void {
            switch (lazy_path) {
                .src_path, .cwd_relative, .dependency => {},
                .generated => |gen| try set.put(allocator, gen.file.step, {}),
            }
        }
        fn addIncludeDirStepDependencies(allocator: Allocator, set: *std.AutoArrayHashMapUnmanaged(*Step, void), include_dir: std.Build.Module.IncludeDir) !void {
            switch (include_dir) {
                .path,
                .path_system,
                .path_after,
                .framework_path,
                .framework_path_system,
                => |lazy_path| try addLazyPathStepDependencies(allocator, set, lazy_path),
                .other_step => |other| {
                    if (other.generated_h) |header| {
                        try set.put(allocator, header.step, {});
                    }
                    if (other.installed_headers_include_tree) |include_tree| {
                        try set.put(allocator, include_tree.generated_directory.step, {});
                    }
                },
                .embed_path => {
                    // This only affects C source files
                },
                .config_header_step => |config_header| try set.put(allocator, &config_header.step, {}),
            }
        }

        fn addModuleDependencies(allocator: Allocator, set: *std.AutoArrayHashMapUnmanaged(*Step, void), module: *std.Build.Module) !void {
            if (module.root_source_file) |root_source_file| {
                try addLazyPathStepDependencies(allocator, set, root_source_file);
            }

            for (module.import_table.values()) |import| {
                if (import.root_source_file) |root_source_file| {
                    try addLazyPathStepDependencies(allocator, set, root_source_file);
                }
            }

            for (module.include_dirs.items) |include_dir| {
                try addIncludeDirStepDependencies(allocator, set, include_dir);
            }

            for (module.lib_paths.items) |lib_path| {
                try addLazyPathStepDependencies(allocator, set, lib_path);
            }

            for (module.rpaths.items) |rpath| {
                if (rpath != .lazy_path) continue;
                try addLazyPathStepDependencies(allocator, set, rpath.lazy_path);
            }
        }

        fn processItem(
            allocator: Allocator,
            module: *std.Build.Module,
            compile: ?*std.Build.Step.Compile,
            name: []const u8,
            packages: *Packages,
            include_dirs: *std.StringArrayHashMapUnmanaged(void),
            c_macros: *std.StringArrayHashMapUnmanaged(void),
        ) !void {
            if (module.root_source_file) |root_source_file| {
                _ = try packages.addPackage(name, root_source_file.getPath(module.owner));
            }

            if (compile) |exe| {
                try processPkgConfig(allocator, include_dirs, c_macros, exe);
            }

            try c_macros.ensureUnusedCapacity(allocator, module.c_macros.items.len);
            for (module.c_macros.items) |c_macro| {
                c_macros.putAssumeCapacity(c_macro, {});
            }

            for (module.include_dirs.items) |include_dir| {
                switch (include_dir) {
                    .path,
                    .path_system,
                    .path_after,
                    .framework_path,
                    .framework_path_system,
                    => |include_path| try include_dirs.put(allocator, include_path.getPath(module.owner), {}),

                    .other_step => |other| {
                        if (other.generated_h) |header| {
                            try include_dirs.put(
                                allocator,
                                std.fs.path.dirname(header.getPath()).?,
                                {},
                            );
                        }
                        if (other.installed_headers_include_tree) |include_tree| {
                            try include_dirs.put(
                                allocator,
                                include_tree.generated_directory.getPath(),
                                {},
                            );
                        }
                    },
                    .embed_path => {
                        // This only affects C source files
                    },
                    .config_header_step => |config_header| {
                        try include_dirs.put(
                            allocator,
                            config_header.generated_dir.getPath(),
                            {},
                        );
                    },
                }
            }
        }
    };

    var step_dependencies: std.AutoArrayHashMapUnmanaged(*Step, void) = .{};
    defer step_dependencies.deinit(gpa);

    // collect step dependencies
    {
        var modules: std.AutoArrayHashMapUnmanaged(*std.Build.Module, void) = .{};
        defer modules.deinit(gpa);

        // collect root modules of `Step.Compile`
        for (steps.keys()) |step| {
            const compile = step.cast(Step.Compile) orelse continue;
            // if (compile.kind.isTest()) continue;
            const graph = compile.root_module.getGraph();
            try modules.ensureUnusedCapacity(gpa, graph.modules.len);
            for (graph.modules) |module| modules.putAssumeCapacity(module, {});
        }

        // collect public modules
        for (b.modules.values()) |root_module| {
            const graph = root_module.getGraph();
            try modules.ensureUnusedCapacity(gpa, graph.modules.len);
            for (graph.modules) |module| modules.putAssumeCapacity(module, {});
        }

        // collect all dependencies of all found modules
        for (modules.keys()) |module| {
            try helper.addModuleDependencies(gpa, &step_dependencies, module);
        }
    }

    prepare(gpa, b, &step_dependencies, run, seed) catch |err| switch (err) {
        error.UncleanExit => process.exit(1),
        else => return err,
    };

    // run all steps that are dependencies
    try runSteps(
        gpa,
        b,
        &step_dependencies,
        main_progress_node,
        run,
    );

    var include_dirs: std.StringArrayHashMapUnmanaged(void) = .{};
    defer include_dirs.deinit(gpa);

    var c_macros: std.StringArrayHashMapUnmanaged(void) = .{};
    defer c_macros.deinit(gpa);

    var packages: Packages = .{ .allocator = gpa };
    defer packages.deinit();

    // extract packages and include paths
    {
        for (steps.keys()) |step| {
            const compile = step.cast(Step.Compile) orelse continue;
            // if (compile.kind.isTest()) continue;
            const graph = compile.root_module.getGraph();
            try helper.processItem(gpa, compile.root_module, compile, "root", &packages, &include_dirs, &c_macros);
            for (graph.modules) |module| {
                for (module.import_table.keys(), module.import_table.values()) |name, import| {
                    try helper.processItem(gpa, import, null, name, &packages, &include_dirs, &c_macros);
                }
            }
        }

        for (b.modules.values()) |root_module| {
            const graph = root_module.getGraph();
            try helper.processItem(gpa, root_module, null, "root", &packages, &include_dirs, &c_macros);
            for (graph.modules) |module| {
                for (module.import_table.keys(), module.import_table.values()) |name, import| {
                    try helper.processItem(gpa, import, null, name, &packages, &include_dirs, &c_macros);
                }
            }
        }
    }

    // Sample `@dependencies` structure:
    // pub const packages = struct {
    //     pub const @"1220363c7e27b2d3f39de6ff6e90f9537a0634199860fea237a55ddb1e1717f5d6a5" = struct {
    //         pub const build_root = "/home/rad/.cache/zig/p/1220363c7e27b2d3f39de6ff6e90f9537a0634199860fea237a55ddb1e1717f5d6a5";
    //         pub const build_zig = @import("1220363c7e27b2d3f39de6ff6e90f9537a0634199860fea237a55ddb1e1717f5d6a5");
    //         pub const deps: []const struct { []const u8, []const u8 } = &.{};
    //     };
    // ...
    // };
    // pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    //     .{ "known_folders", "1220bb12c9bfe291eed1afe6a2070c7c39918ab1979f24a281bba39dfb23f5bcd544" },
    //     .{ "diffz", "122089a8247a693cad53beb161bde6c30f71376cd4298798d45b32740c3581405864" },
    // };

    var deps_build_roots: ArrayList(BuildConfig.NamePathPair) = .empty;
    for (dependencies.root_deps) |root_dep| {
        inline for (comptime std.meta.declarations(dependencies.packages)) |package| blk: {
            if (std.mem.eql(u8, package.name, root_dep[1])) {
                const package_info = @field(dependencies.packages, package.name);
                if (!@hasDecl(package_info, "build_root")) break :blk;
                if (!@hasDecl(package_info, "build_zig")) break :blk;
                try deps_build_roots.append(arena, .{
                    .name = root_dep[0],
                    .path = try std.fs.path.join(arena, &.{ package_info.build_root, "build.zig" }),
                });
            }
        }
    }

    var available_options: std.json.ArrayHashMap(BuildConfig.AvailableOption) = .{};
    try available_options.map.ensureTotalCapacity(arena, b.available_options_map.count());

    var it = b.available_options_map.iterator();
    while (it.next()) |available_option| {
        available_options.map.putAssumeCapacityNoClobber(available_option.key_ptr.*, available_option.value_ptr.*);
    }

    // roots[]
    var visited_steps: std.AutoArrayHashMapUnmanaged(*Step, void) = .empty;
    var unsorted_roots: std.ArrayListUnmanaged(roots_info.RootEntry) = .empty;
    var roots_info_slc: std.ArrayList(u8) = .empty;
    var root_idx: u32 = 0;

    for (b.top_level_steps.values()) |tls| {
        try roots_info.collect(
            gpa,
            &tls.step,
            &visited_steps,
            &unsorted_roots,
            build_root,
        );
    }

    const zig_pkg_path = try std.fs.path.join(arena, &.{ build_root, "zig-pkg" });
    std.mem.sort(
        roots_info.RootEntry,
        unsorted_roots.items,
        roots_info.hasPrecedenceContext{
            .build_root_path = build_root,
            .zig_pkg_path = zig_pkg_path,
        },
        roots_info.hasPrecedence,
    );

    if (!dont_create_roots_txt_file) try roots_info_slc.print(gpa,
        \\Project path: {s}
        \\   Generated by Zigscient's build_runner. PlainText. Structured to facilitate indent-based folding.
        \\   Entries have the following structure ($~ Target CPU$ listed only if NOT native):
        // \\   %"TopLevelStepName"
        \\       #$ROOT_ID$: "$CompileStepName$" [ "root" : '$root_module_source_file_path$'] $~ Target CPU$
        \\           ["$module_name_imported_by_root$" : '$path$']
        \\                ["$module_imported_by_the_above_module$" : '$path$']
        \\
        \\
    , .{
        build_root,
    });

    var roots = try std.ArrayListUnmanaged(BuildConfig.RootEntry).initCapacity(gpa, unsorted_roots.items.len);
    for (unsorted_roots.items) |item| {
        const args = try copied_from_zig.getZigArgs(item.step, false);
        roots.appendAssumeCapacity(.{
            .name = item.step.name,
            .args = args,
            .mods = item.mods,
        });
        if (!dont_create_roots_txt_file) try roots_info.print(gpa, &roots_info_slc, &root_idx, item.step, &args);
    }

    const io = b.graph.io;
    const roots_info_file_path = if (!dont_create_roots_txt_file) blk: {
        const dir_path = std.fs.path.dirname(self_path) orelse unreachable;
        const file_path = try std.fs.path.join(gpa, &.{ dir_path, "roots.txt" });
        // const file = try std.fs.cwd().createFile(file_path, .{});
        // try file.writeAll(roots_info_slc.items);
        const file = try std.Io.Dir.cwd().createFile(io, file_path, .{});
        var fw = file.writer(io, &.{});
        fw.interface.writeAll(roots_info_slc.items) catch return fw.err.?;
        file.close(io);
        break :blk try std.fs.path.join(gpa, &.{ build_root, file_path });
    } else "";

    const stringified_build_config = try std.json.Stringify.valueAlloc(
        gpa,
        BuildConfig{
            .roots_info_file = roots_info_file_path,
            .deps_build_roots = deps_build_roots.items,
            .roots = roots.items,
            .packages = try packages.toPackageList(),
            .include_dirs = include_dirs.keys(),
            .top_level_steps = b.top_level_steps.keys(),
            .available_options = available_options,
            .c_macros = c_macros.keys(),
        },
        .{ .whitespace = .indent_2 },
    );

    var file_writer = std.Io.File.stdout().writer(io, &.{});
    file_writer.interface.writeAll(stringified_build_config) catch return file_writer.err.?;

    std.process.exit(0);
}

fn processPkgConfig(
    allocator: std.mem.Allocator,
    include_dirs: *std.StringArrayHashMapUnmanaged(void),
    c_macros: *std.StringArrayHashMapUnmanaged(void),
    exe: *Step.Compile,
) !void {
    for (exe.root_module.link_objects.items) |link_object| {
        if (link_object != .system_lib) continue;
        const system_lib = link_object.system_lib;

        if (system_lib.use_pkg_config == .no) continue;

        const args = copied_from_zig.runPkgConfig(exe, system_lib.name) catch |err| switch (err) {
            error.PkgConfigInvalidOutput,
            error.PkgConfigCrashed,
            error.PkgConfigFailed,
            error.PkgConfigNotInstalled,
            error.PackageNotFound,
            => switch (system_lib.use_pkg_config) {
                .yes => {
                    // pkg-config failed, so zig will not add any include paths
                    continue;
                },
                .force => {
                    std.log.warn("pkg-config failed for library {s}", .{system_lib.name});
                    continue;
                },
                .no => unreachable,
            },
            else => |e| return e,
        };
        for (args.cflags) |arg| {
            if (std.mem.startsWith(u8, arg, "-I")) {
                const candidate = arg[2..];
                try include_dirs.put(allocator, candidate, {});
            } else if (std.mem.startsWith(u8, arg, "-D")) {
                try c_macros.put(allocator, arg, {});
            }
        }
    }
}

// TODO: Having a copy of this is not very nice
const copied_from_zig = struct {
    const Module = std.Build.Module;
    const Compile = std.Build.Step.Compile;
    const GeneratedFile = std.Build.GeneratedFile;

    const PkgConfigResult = struct {
        cflags: []const []const u8,
        libs: []const []const u8,
    };

    /// Run pkg-config for the given library name and parse the output, returning the arguments
    /// that should be passed to zig to link the given library.
    fn runPkgConfig(compile: *Compile, lib_name: []const u8) !PkgConfigResult {
        const wl_rpath_prefix = "-Wl,-rpath,";

        const b = compile.step.owner;
        const pkg_name = match: {
            // First we have to map the library name to pkg config name. Unfortunately,
            // there are several examples where this is not straightforward:
            // -lSDL2 -> pkg-config sdl2
            // -lgdk-3 -> pkg-config gdk-3.0
            // -latk-1.0 -> pkg-config atk
            // -lpulse -> pkg-config libpulse
            const pkgs = try getPkgConfigList(b);

            // Exact match means instant winner.
            for (pkgs) |pkg| {
                if (mem.eql(u8, pkg.name, lib_name)) {
                    break :match pkg.name;
                }
            }

            // Next we'll try ignoring case.
            for (pkgs) |pkg| {
                if (std.ascii.eqlIgnoreCase(pkg.name, lib_name)) {
                    break :match pkg.name;
                }
            }

            // Prefixed "lib" or suffixed ".0".
            for (pkgs) |pkg| {
                if (std.ascii.findIgnoreCase(pkg.name, lib_name)) |pos| {
                    const prefix = pkg.name[0..pos];
                    const suffix = pkg.name[pos + lib_name.len ..];
                    if (prefix.len > 0 and !mem.eql(u8, prefix, "lib")) continue;
                    if (suffix.len > 0 and !mem.eql(u8, suffix, ".0")) continue;
                    break :match pkg.name;
                }
            }

            // Trimming "-1.0".
            if (mem.endsWith(u8, lib_name, "-1.0")) {
                const trimmed_lib_name = lib_name[0 .. lib_name.len - "-1.0".len];
                for (pkgs) |pkg| {
                    if (std.ascii.eqlIgnoreCase(pkg.name, trimmed_lib_name)) {
                        break :match pkg.name;
                    }
                }
            }

            return error.PackageNotFound;
        };

        var code: u8 = undefined;
        const pkg_config_exe = b.graph.environ_map.get("PKG_CONFIG") orelse "pkg-config";
        const stdout = if (b.runAllowFail(&[_][]const u8{
            pkg_config_exe,
            pkg_name,
            "--cflags",
            "--libs",
        }, &code, .ignore)) |stdout| stdout else |err| switch (err) {
            error.ProcessTerminated => return error.PkgConfigCrashed,
            error.ExecNotSupported => return error.PkgConfigFailed,
            error.ExitCodeFailure => return error.PkgConfigFailed,
            error.FileNotFound => return error.PkgConfigNotInstalled,
            else => return err,
        };

        var zig_cflags = std.array_list.Managed([]const u8).init(b.allocator);
        defer zig_cflags.deinit();
        var zig_libs = std.array_list.Managed([]const u8).init(b.allocator);
        defer zig_libs.deinit();

        var arg_it = mem.tokenizeAny(u8, stdout, " \r\n\t");
        while (arg_it.next()) |arg| {
            if (mem.eql(u8, arg, "-I")) {
                const dir = arg_it.next() orelse return error.PkgConfigInvalidOutput;
                try zig_cflags.appendSlice(&[_][]const u8{ "-I", dir });
            } else if (mem.startsWith(u8, arg, "-I")) {
                try zig_cflags.append(arg);
            } else if (mem.eql(u8, arg, "-L")) {
                const dir = arg_it.next() orelse return error.PkgConfigInvalidOutput;
                try zig_libs.appendSlice(&[_][]const u8{ "-L", dir });
            } else if (mem.startsWith(u8, arg, "-L")) {
                try zig_libs.append(arg);
            } else if (mem.eql(u8, arg, "-l")) {
                const lib = arg_it.next() orelse return error.PkgConfigInvalidOutput;
                try zig_libs.appendSlice(&[_][]const u8{ "-l", lib });
            } else if (mem.startsWith(u8, arg, "-l")) {
                try zig_libs.append(arg);
            } else if (mem.eql(u8, arg, "-D")) {
                const macro = arg_it.next() orelse return error.PkgConfigInvalidOutput;
                try zig_cflags.appendSlice(&[_][]const u8{ "-D", macro });
            } else if (mem.startsWith(u8, arg, "-D")) {
                try zig_cflags.append(arg);
            } else if (mem.startsWith(u8, arg, wl_rpath_prefix)) {
                try zig_cflags.appendSlice(&[_][]const u8{ "-rpath", arg[wl_rpath_prefix.len..] });
            } else if (b.debug_pkg_config) {
                return compile.step.fail("unknown pkg-config flag '{s}'", .{arg});
            }
        }

        return .{
            .cflags = try zig_cflags.toOwnedSlice(),
            .libs = try zig_libs.toOwnedSlice(),
        };
    }

    fn execPkgConfigList(self: *std.Build, out_code: *u8) (std.Build.PkgConfigError || std.Build.RunError)![]const std.Build.PkgConfigPkg {
        const stdout = try self.runAllowFail(&.{ "pkg-config", "--list-all" }, out_code, .ignore);
        var list = ArrayListManaged(std.Build.PkgConfigPkg).init(self.allocator);
        errdefer list.deinit();
        var line_it = mem.tokenizeAny(u8, stdout, "\r\n");
        while (line_it.next()) |line| {
            if (mem.trim(u8, line, " \t").len == 0) continue;
            var tok_it = mem.tokenizeAny(u8, line, " \t");
            try list.append(.{
                .name = tok_it.next() orelse return error.PkgConfigInvalidOutput,
                .desc = tok_it.rest(),
            });
        }
        return list.toOwnedSlice();
    }

    fn getPkgConfigList(self: *std.Build) ![]const std.Build.PkgConfigPkg {
        if (self.pkg_config_pkg_list) |res| {
            return res;
        }
        var code: u8 = undefined;
        if (execPkgConfigList(self, &code)) |list| {
            self.pkg_config_pkg_list = list;
            return list;
        } else |err| {
            const result = switch (err) {
                error.ProcessTerminated => error.PkgConfigCrashed,
                error.ExecNotSupported => error.PkgConfigFailed,
                error.ExitCodeFailure => error.PkgConfigFailed,
                error.FileNotFound => error.PkgConfigNotInstalled,
                error.InvalidName => error.PkgConfigNotInstalled,
                error.PkgConfigInvalidOutput => error.PkgConfigInvalidOutput,
                else => return err,
            };
            self.pkg_config_pkg_list = result;
            return result;
        }
    }

    const CliNamedModules = struct {
        modules: std.AutoArrayHashMapUnmanaged(*Module, void),
        names: std.StringArrayHashMapUnmanaged(void),

        /// Traverse the whole dependency graph and give every module a unique
        /// name, ideally one named after what it's called somewhere in the graph.
        /// It will help here to have both a mapping from module to name and a set
        /// of all the currently-used names.
        fn init(arena: Allocator, root_module: *Module) Allocator.Error!CliNamedModules {
            var compile: CliNamedModules = .{
                .modules = .{},
                .names = .{},
            };
            const graph = root_module.getGraph();
            {
                assert(graph.modules[0] == root_module);
                try compile.modules.put(arena, root_module, {});
                try compile.names.put(arena, "root", {});
            }
            for (graph.modules[1..], graph.names[1..]) |mod, orig_name| {
                var name = orig_name;
                var n: usize = 0;
                while (true) {
                    const gop = try compile.names.getOrPut(arena, name);
                    if (!gop.found_existing) {
                        try compile.modules.putNoClobber(arena, mod, {});
                        break;
                    }
                    name = try std.fmt.allocPrint(arena, "{s}{d}", .{ orig_name, n });
                    n += 1;
                }
            }
            return compile;
        }
    };

    fn addFlag(args: *std.array_list.Managed([]const u8), comptime name: []const u8, opt: ?bool) !void {
        const cond = opt orelse return;
        try args.ensureUnusedCapacity(1);
        if (cond) {
            args.appendAssumeCapacity("-f" ++ name);
        } else {
            args.appendAssumeCapacity("-fno-" ++ name);
        }
    }

    fn moduleNeedsCliArg(mod: *const Module) bool {
        return for (mod.link_objects.items) |o| switch (o) {
            .c_source_file, .c_source_files, .assembly_file, .win32_resource_file => break true,
            else => continue,
        } else false;
    }

    fn getGeneratedFilePath(compile: *Compile, comptime tag_name: []const u8, asking_step: ?*Step) ![]const u8 {
        const step = &compile.step;
        const b = step.owner;
        const graph = b.graph;
        const io = graph.io;
        const maybe_path: ?*GeneratedFile = @field(compile, tag_name);

        const generated_file = maybe_path orelse {
            const stderr = try io.lockStderr(&.{}, graph.stderr_mode);
            std.Build.dumpBadGetPathHelp(&compile.step, stderr.terminal(), compile.step.owner, asking_step) catch {};
            io.unlockStderr();
            @panic("missing emit option for " ++ tag_name);
        };

        const path = generated_file.path orelse {
            const stderr = try io.lockStderr(&.{}, graph.stderr_mode);
            std.Build.dumpBadGetPathHelp(&compile.step, stderr.terminal(), compile.step.owner, asking_step) catch {};
            io.unlockStderr();
            @panic(tag_name ++ " is null. Is there a missing step dependency?");
        };

        return path;
    }

    const fs = std.fs;
    const Io = std.Io;
    const panic = std.debug.panic;
    const Sha256 = std.crypto.hash.sha2.Sha256;
    fn getZigArgs(compile: *Compile, fuzz: bool) ![][]const u8 {
        const step = &compile.step;
        const b = step.owner;
        const arena = b.allocator;

        var zig_args = std.array_list.Managed([]const u8).init(arena);
        defer zig_args.deinit();

        try zig_args.append(b.graph.zig_exe);

        const cmd = switch (compile.kind) {
            .lib => "build-lib",
            .exe => "build-exe",
            .obj => "build-obj",
            .@"test" => "test",
            .test_obj => "test-obj",
        };
        try zig_args.append(cmd);

        if (b.reference_trace) |some| {
            try zig_args.append(try std.fmt.allocPrint(arena, "-freference-trace={d}", .{some}));
        } else try zig_args.append(try std.fmt.allocPrint(arena, "-freference-trace=12", .{}));

        try addFlag(&zig_args, "allow-so-scripts", compile.allow_so_scripts orelse b.graph.allow_so_scripts);

        try addFlag(&zig_args, "llvm", compile.use_llvm);
        try addFlag(&zig_args, "lld", compile.use_lld);
        try addFlag(&zig_args, "new-linker", compile.use_new_linker);

        if (compile.root_module.resolved_target.?.query.ofmt) |ofmt| {
            try zig_args.append(try std.fmt.allocPrint(arena, "-ofmt={s}", .{@tagName(ofmt)}));
        }

        switch (compile.entry) {
            .default => {},
            .disabled => try zig_args.append("-fno-entry"),
            .enabled => try zig_args.append("-fentry"),
            .symbol_name => |entry_name| {
                try zig_args.append(try std.fmt.allocPrint(arena, "-fentry={s}", .{entry_name}));
            },
        }

        {
            var symbol_it = compile.force_undefined_symbols.keyIterator();
            while (symbol_it.next()) |symbol_name| {
                try zig_args.append("--force_undefined");
                try zig_args.append(symbol_name.*);
            }
        }

        if (compile.stack_size) |stack_size| {
            try zig_args.append("--stack");
            try zig_args.append(try std.fmt.allocPrint(arena, "{}", .{stack_size}));
        }

        if (fuzz) {
            try zig_args.append("-ffuzz");
        }

        {
            // Stores system libraries that have already been seen for at least one
            // module, along with any arguments that need to be passed to the
            // compiler for each module individually.
            var seen_system_libs: std.StringHashMapUnmanaged([]const []const u8) = .empty;
            var frameworks: std.StringArrayHashMapUnmanaged(Module.LinkFrameworkOptions) = .empty;

            var prev_has_cflags = false;
            var prev_has_rcflags = false;
            var prev_search_strategy: Module.SystemLib.SearchStrategy = .paths_first;
            var prev_preferred_link_mode: std.lang.LinkMode = .dynamic;
            // Track the number of positional arguments so that a nice error can be
            // emitted if there is nothing to link.
            var total_linker_objects: usize = @intFromBool(compile.root_module.root_source_file != null);

            // Fully recursive iteration including dynamic libraries to detect
            // libc and libc++ linkage.
            for (compile.getCompileDependencies(true)) |some_compile| {
                for (some_compile.root_module.getGraph().modules) |mod| {
                    if (mod.link_libc == true) compile.is_linking_libc = true;
                    if (mod.link_libcpp == true) compile.is_linking_libcpp = true;
                }
            }

            var cli_named_modules = try CliNamedModules.init(arena, compile.root_module);

            // For this loop, don't chase dynamic libraries because their link
            // objects are already linked.
            for (compile.getCompileDependencies(false)) |dep_compile| {
                for (dep_compile.root_module.getGraph().modules) |mod| {
                    // While walking transitive dependencies, if a given link object is
                    // already included in a library, it should not redundantly be
                    // placed on the linker line of the dependee.
                    const my_responsibility = dep_compile == compile;
                    const already_linked = !my_responsibility and dep_compile.isDynamicLibrary();

                    // Inherit dependencies on darwin frameworks.
                    if (!already_linked) {
                        for (mod.frameworks.keys(), mod.frameworks.values()) |name, info| {
                            try frameworks.put(arena, name, info);
                        }
                    }

                    // Inherit dependencies on system libraries and static libraries.
                    for (mod.link_objects.items) |link_object| {
                        switch (link_object) {
                            .static_path => { //|static_path| {
                                if (my_responsibility) {
                                    try zig_args.append("<generated>"); //static_path.getPath2(mod.owner, step));
                                    total_linker_objects += 1;
                                }
                            },
                            .system_lib => |system_lib| {
                                const system_lib_gop = try seen_system_libs.getOrPut(arena, system_lib.name);
                                if (system_lib_gop.found_existing) {
                                    try zig_args.appendSlice(system_lib_gop.value_ptr.*);
                                    continue;
                                } else {
                                    system_lib_gop.value_ptr.* = &.{};
                                }

                                if (already_linked)
                                    continue;

                                if ((system_lib.search_strategy != prev_search_strategy or
                                    system_lib.preferred_link_mode != prev_preferred_link_mode) and
                                    compile.linkage != .static)
                                {
                                    switch (system_lib.search_strategy) {
                                        .no_fallback => switch (system_lib.preferred_link_mode) {
                                            .dynamic => try zig_args.append("-search_dylibs_only"),
                                            .static => try zig_args.append("-search_static_only"),
                                        },
                                        .paths_first => switch (system_lib.preferred_link_mode) {
                                            .dynamic => try zig_args.append("-search_paths_first"),
                                            .static => try zig_args.append("-search_paths_first_static"),
                                        },
                                        .mode_first => switch (system_lib.preferred_link_mode) {
                                            .dynamic => try zig_args.append("-search_dylibs_first"),
                                            .static => try zig_args.append("-search_static_first"),
                                        },
                                    }
                                    prev_search_strategy = system_lib.search_strategy;
                                    prev_preferred_link_mode = system_lib.preferred_link_mode;
                                }

                                const prefix: []const u8 = prefix: {
                                    if (system_lib.needed) break :prefix "-needed-l";
                                    if (system_lib.weak) break :prefix "-weak-l";
                                    break :prefix "-l";
                                };
                                switch (system_lib.use_pkg_config) {
                                    .no => try zig_args.append(b.fmt("{s}{s}", .{ prefix, system_lib.name })),
                                    .yes, .force => {
                                        if (runPkgConfig(compile, system_lib.name)) |result| {
                                            try zig_args.appendSlice(result.cflags);
                                            try zig_args.appendSlice(result.libs);
                                            try seen_system_libs.put(arena, system_lib.name, result.cflags);
                                        } else |err| switch (err) {
                                            error.PkgConfigInvalidOutput,
                                            error.PkgConfigCrashed,
                                            error.PkgConfigFailed,
                                            error.PkgConfigNotInstalled,
                                            error.PackageNotFound,
                                            => switch (system_lib.use_pkg_config) {
                                                .yes => {
                                                    // pkg-config failed, so fall back to linking the library
                                                    // by name directly.
                                                    try zig_args.append(b.fmt("{s}{s}", .{
                                                        prefix,
                                                        system_lib.name,
                                                    }));
                                                },
                                                .force => {
                                                    panic("pkg-config failed for library {s}", .{system_lib.name});
                                                },
                                                .no => unreachable,
                                            },

                                            else => |e| return e,
                                        }
                                    },
                                }
                            },
                            .other_step => |other| {
                                switch (other.kind) {
                                    .exe => return step.fail("cannot link with an executable build artifact", .{}),
                                    .@"test" => return step.fail("cannot link with a test", .{}),
                                    .obj, .test_obj => {
                                        const included_in_lib_or_obj = !my_responsibility and
                                            (dep_compile.kind == .lib or dep_compile.kind == .obj or dep_compile.kind == .test_obj);
                                        if (!already_linked and !included_in_lib_or_obj) {
                                            try zig_args.append("<generated>"); //other.getEmittedBin().getPath2(b, step));
                                            total_linker_objects += 1;
                                        }
                                    },
                                    .lib => l: {
                                        const other_produces_implib = other.producesImplib();
                                        const other_is_static = other_produces_implib or other.isStaticLibrary();

                                        if (compile.isStaticLibrary() and other_is_static) {
                                            // Avoid putting a static library inside a static library.
                                            break :l;
                                        }

                                        // For DLLs, we must link against the implib.
                                        // For everything else, we directly link
                                        // against the library file.
                                        const full_path_lib = if (other_produces_implib)
                                            "<generated_implib>"
                                            // try getGeneratedFilePath(other, "generated_implib", &compile.step)
                                        else
                                            // try getGeneratedFilePath(other, "generated_bin", &compile.step);
                                            "<generated_bin>";

                                        try zig_args.append(full_path_lib);
                                        total_linker_objects += 1;

                                        if (other.linkage == .dynamic and
                                            compile.rootModuleTarget().os.tag != .windows)
                                        {
                                            if (fs.path.dirname(full_path_lib)) |dirname| {
                                                try zig_args.append("-rpath");
                                                try zig_args.append(dirname);
                                            }
                                        }
                                    },
                                }
                            },
                            .assembly_file => l: {
                                if (!my_responsibility) break :l;

                                if (prev_has_cflags) {
                                    try zig_args.append("-cflags");
                                    try zig_args.append("--");
                                    prev_has_cflags = false;
                                }
                                try zig_args.append("<generated>"); //asm_file.getPath2(mod.owner, step));
                                total_linker_objects += 1;
                            },

                            .c_source_file => |c_source_file| l: {
                                if (!my_responsibility) break :l;

                                if (prev_has_cflags or c_source_file.flags.len != 0) {
                                    try zig_args.append("-cflags");
                                    for (c_source_file.flags) |arg| {
                                        try zig_args.append(arg);
                                    }
                                    try zig_args.append("--");
                                }
                                prev_has_cflags = (c_source_file.flags.len != 0);

                                if (c_source_file.language) |lang| {
                                    try zig_args.append("-x");
                                    try zig_args.append(lang.internalIdentifier());
                                }

                                try zig_args.append("<generated>"); //c_source_file.file.getPath2(mod.owner, step));

                                if (c_source_file.language != null) {
                                    try zig_args.append("-x");
                                    try zig_args.append("none");
                                }
                                total_linker_objects += 1;
                            },

                            .c_source_files => |c_source_files| l: {
                                if (!my_responsibility) break :l;

                                if (prev_has_cflags or c_source_files.flags.len != 0) {
                                    try zig_args.append("-cflags");
                                    for (c_source_files.flags) |arg| {
                                        try zig_args.append(arg);
                                    }
                                    try zig_args.append("--");
                                }
                                prev_has_cflags = (c_source_files.flags.len != 0);

                                if (c_source_files.language) |lang| {
                                    try zig_args.append("-x");
                                    try zig_args.append(lang.internalIdentifier());
                                }

                                const root_path = "<generated>"; //c_source_files.root.getPath2(mod.owner, step);
                                for (c_source_files.files) |file| {
                                    try zig_args.append(b.pathJoin(&.{ root_path, file }));
                                }

                                if (c_source_files.language != null) {
                                    try zig_args.append("-x");
                                    try zig_args.append("none");
                                }

                                total_linker_objects += c_source_files.files.len;
                            },

                            .win32_resource_file => |rc_source_file| l: {
                                if (!my_responsibility) break :l;

                                if (rc_source_file.flags.len == 0 and rc_source_file.include_paths.len == 0) {
                                    if (prev_has_rcflags) {
                                        try zig_args.append("-rcflags");
                                        try zig_args.append("--");
                                        prev_has_rcflags = false;
                                    }
                                } else {
                                    try zig_args.append("-rcflags");
                                    for (rc_source_file.flags) |arg| {
                                        try zig_args.append(arg);
                                    }
                                    for (rc_source_file.include_paths) |_| { //|include_path| {
                                        try zig_args.append("/I");
                                        try zig_args.append("<generated>"); //include_path.getPath2(mod.owner, step));
                                    }
                                    try zig_args.append("--");
                                    prev_has_rcflags = true;
                                }
                                try zig_args.append("<generated>"); //rc_source_file.file.getPath2(mod.owner, step));
                                total_linker_objects += 1;
                            },
                        }
                    }

                    // We need to emit the --mod argument here so that the above link objects
                    // have the correct parent module, but only if the module is part of
                    // this compilation.
                    if (!my_responsibility) continue;
                    if (cli_named_modules.modules.getIndex(mod)) |module_cli_index| {
                        const module_cli_name = cli_named_modules.names.keys()[module_cli_index];
                        try mod.appendZigProcessFlags(&zig_args, step);

                        // --dep arguments
                        try zig_args.ensureUnusedCapacity(mod.import_table.count() * 2);
                        for (mod.import_table.keys(), mod.import_table.values()) |name, import| {
                            const import_index = cli_named_modules.modules.getIndex(import).?;
                            const import_cli_name = cli_named_modules.names.keys()[import_index];
                            zig_args.appendAssumeCapacity("--dep");
                            if (std.mem.eql(u8, import_cli_name, name)) {
                                zig_args.appendAssumeCapacity(import_cli_name);
                            } else {
                                zig_args.appendAssumeCapacity(b.fmt("{s}={s}", .{ name, import_cli_name }));
                            }
                        }

                        // When the CLI sees a -M argument, it determines whether it
                        // implies the existence of a Zig compilation unit based on
                        // whether there is a root source file. If there is no root
                        // source file, then this is not a zig compilation unit - it is
                        // perhaps a set of linker objects, or C source files instead.
                        // Linker objects are added to the CLI globally, while C source
                        // files must have a module parent.
                        if (mod.root_source_file) |lp| {
                            const src = lp.getPath2(mod.owner, step);
                            try zig_args.append(b.fmt("-M{s}={s}", .{ module_cli_name, src }));
                        } else if (moduleNeedsCliArg(mod)) {
                            try zig_args.append(b.fmt("-M{s}", .{module_cli_name}));
                        }
                    }
                }
            }

            if (total_linker_objects == 0) {
                return step.fail("the linker needs one or more objects to link", .{});
            }

            for (frameworks.keys(), frameworks.values()) |name, info| {
                if (info.needed) {
                    try zig_args.append("-needed_framework");
                } else if (info.weak) {
                    try zig_args.append("-weak_framework");
                } else {
                    try zig_args.append("-framework");
                }
                try zig_args.append(name);
            }

            if (compile.is_linking_libcpp) {
                try zig_args.append("-lc++");
            }

            if (compile.is_linking_libc) {
                try zig_args.append("-lc");
            }
        }

        if (compile.win32_manifest) |_| {
            try zig_args.append("<generated>"); //manifest_file.getPath2(b, step));
        }

        if (compile.image_base) |image_base| {
            try zig_args.append("--image-base");
            try zig_args.append(b.fmt("0x{x}", .{image_base}));
        }

        for (compile.filters) |filter| {
            try zig_args.append("--test-filter");
            try zig_args.append(filter);
        }

        if (compile.test_runner) |_| {
            try zig_args.append("--test-runner");
            try zig_args.append("<generated>"); //test_runner.path.getPath2(b, step));
        }

        for (b.debug_log_scopes) |log_scope| {
            try zig_args.append("--debug-log");
            try zig_args.append(log_scope);
        }

        if (b.debug_compile_errors) {
            try zig_args.append("--debug-compile-errors");
        }

        if (b.debug_incremental) {
            try zig_args.append("--debug-incremental");
        }

        if (b.verbose_air) try zig_args.append("--verbose-air");
        if (b.verbose_llvm_ir) |path| try zig_args.append(b.fmt("--verbose-llvm-ir={s}", .{path}));
        if (b.verbose_llvm_bc) |path| try zig_args.append(b.fmt("--verbose-llvm-bc={s}", .{path}));
        if (b.verbose_link or compile.verbose_link) try zig_args.append("--verbose-link");
        if (b.verbose_cc or compile.verbose_cc) try zig_args.append("--verbose-cc");
        if (b.verbose_llvm_cpu_features) try zig_args.append("--verbose-llvm-cpu-features");
        if (b.graph.time_report) try zig_args.append("--time-report");

        if (compile.generated_asm != null) try zig_args.append("-femit-asm");
        if (compile.generated_bin == null) try zig_args.append("-fno-emit-bin");
        if (compile.generated_docs != null) try zig_args.append("-femit-docs");
        if (compile.generated_implib != null) try zig_args.append("-femit-implib");
        if (compile.generated_llvm_bc != null) try zig_args.append("-femit-llvm-bc");
        if (compile.generated_llvm_ir != null) try zig_args.append("-femit-llvm-ir");
        if (compile.generated_h != null) try zig_args.append("-femit-h");

        try addFlag(&zig_args, "formatted-panics", compile.formatted_panics);

        switch (compile.compress_debug_sections) {
            .none => {},
            .zlib => try zig_args.append("--compress-debug-sections=zlib"),
            .zstd => try zig_args.append("--compress-debug-sections=zstd"),
        }

        if (compile.link_eh_frame_hdr) {
            try zig_args.append("--eh-frame-hdr");
        }
        if (compile.link_emit_relocs) {
            try zig_args.append("--emit-relocs");
        }
        if (compile.link_function_sections) {
            try zig_args.append("-ffunction-sections");
        }
        if (compile.link_data_sections) {
            try zig_args.append("-fdata-sections");
        }
        if (compile.link_gc_sections) |x| {
            try zig_args.append(if (x) "--gc-sections" else "--no-gc-sections");
        }
        if (!compile.linker_dynamicbase) {
            try zig_args.append("--no-dynamicbase");
        }
        if (compile.linker_allow_shlib_undefined) |x| {
            try zig_args.append(if (x) "-fallow-shlib-undefined" else "-fno-allow-shlib-undefined");
        }
        if (compile.link_z_notext) {
            try zig_args.append("-z");
            try zig_args.append("notext");
        }
        if (!compile.link_z_relro) {
            try zig_args.append("-z");
            try zig_args.append("norelro");
        }
        if (compile.link_z_lazy) {
            try zig_args.append("-z");
            try zig_args.append("lazy");
        }
        if (compile.link_z_common_page_size) |size| {
            try zig_args.append("-z");
            try zig_args.append(b.fmt("common-page-size={d}", .{size}));
        }
        if (compile.link_z_max_page_size) |size| {
            try zig_args.append("-z");
            try zig_args.append(b.fmt("max-page-size={d}", .{size}));
        }
        if (compile.link_z_defs) {
            try zig_args.append("-z");
            try zig_args.append("defs");
        }

        if (compile.libc_file) |libc_file| {
            try zig_args.append("--libc");
            try zig_args.append(libc_file.getPath2(b, step));
        } else if (b.libc_file) |libc_file| {
            try zig_args.append("--libc");
            try zig_args.append(libc_file);
        }

        try zig_args.append("--cache-dir");
        try zig_args.append(b.cache_root.path orelse ".");

        try zig_args.append("--global-cache-dir");
        try zig_args.append(b.graph.global_cache_root.path orelse ".");

        if (b.graph.debug_compiler_runtime_libs) |mode|
            try zig_args.append(b.fmt("--debug-rt={t}", .{mode}));

        try zig_args.append("--name");
        try zig_args.append(compile.name);

        if (compile.linkage) |some| switch (some) {
            .dynamic => try zig_args.append("-dynamic"),
            .static => try zig_args.append("-static"),
        };
        if (compile.kind == .lib and compile.linkage != null and compile.linkage.? == .dynamic) {
            if (compile.version) |version| {
                try zig_args.append("--version");
                try zig_args.append(b.fmt("{f}", .{version}));
            }

            if (compile.rootModuleTarget().os.tag.isDarwin()) {
                const install_name = compile.install_name orelse b.fmt("@rpath/{s}{s}{s}", .{
                    compile.rootModuleTarget().libPrefix(),
                    compile.name,
                    compile.rootModuleTarget().dynamicLibSuffix(),
                });
                try zig_args.append("-install_name");
                try zig_args.append(install_name);
            }
        }

        if (compile.entitlements) |entitlements| {
            try zig_args.appendSlice(&[_][]const u8{ "--entitlements", entitlements });
        }
        if (compile.pagezero_size) |pagezero_size| {
            const size = try std.fmt.allocPrint(arena, "{x}", .{pagezero_size});
            try zig_args.appendSlice(&[_][]const u8{ "-pagezero_size", size });
        }
        if (compile.headerpad_size) |headerpad_size| {
            const size = try std.fmt.allocPrint(arena, "{x}", .{headerpad_size});
            try zig_args.appendSlice(&[_][]const u8{ "-headerpad", size });
        }
        if (compile.headerpad_max_install_names) {
            try zig_args.append("-headerpad_max_install_names");
        }
        if (compile.dead_strip_dylibs) {
            try zig_args.append("-dead_strip_dylibs");
        }
        if (compile.force_load_objc) {
            try zig_args.append("-ObjC");
        }
        if (compile.discard_local_symbols) {
            try zig_args.append("--discard-all");
        }

        try addFlag(&zig_args, "compiler-rt", compile.bundle_compiler_rt);
        try addFlag(&zig_args, "ubsan-rt", compile.bundle_ubsan_rt);
        try addFlag(&zig_args, "dll-export-fns", compile.dll_export_fns);
        if (compile.rdynamic) {
            try zig_args.append("-rdynamic");
        }
        if (compile.import_memory) {
            try zig_args.append("--import-memory");
        }
        if (compile.export_memory) {
            try zig_args.append("--export-memory");
        }
        if (compile.import_symbols) {
            try zig_args.append("--import-symbols");
        }
        if (compile.import_table) {
            try zig_args.append("--import-table");
        }
        if (compile.export_table) {
            try zig_args.append("--export-table");
        }
        if (compile.initial_memory) |initial_memory| {
            try zig_args.append(b.fmt("--initial-memory={d}", .{initial_memory}));
        }
        if (compile.max_memory) |max_memory| {
            try zig_args.append(b.fmt("--max-memory={d}", .{max_memory}));
        }
        if (compile.shared_memory) {
            try zig_args.append("--shared-memory");
        }
        if (compile.global_base) |global_base| {
            try zig_args.append(b.fmt("--global-base={d}", .{global_base}));
        }

        if (compile.wasi_exec_model) |model| {
            try zig_args.append(b.fmt("-mexec-model={s}", .{@tagName(model)}));
        }
        if (compile.linker_script) |_| { //|linker_script| {
            try zig_args.append("--script");
            try zig_args.append("<generated>"); //linker_script.getPath2(b, step));
        }

        if (compile.version_script) |version_script| {
            try zig_args.append("--version-script");
            try zig_args.append(version_script.getPath2(b, step));
        }
        if (compile.linker_allow_undefined_version) |x| {
            try zig_args.append(if (x) "--undefined-version" else "--no-undefined-version");
        }

        if (compile.linker_enable_new_dtags) |enabled| {
            try zig_args.append(if (enabled) "--enable-new-dtags" else "--disable-new-dtags");
        }

        if (compile.kind == .@"test") {
            if (compile.exec_cmd_args) |exec_cmd_args| {
                for (exec_cmd_args) |cmd_arg| {
                    if (cmd_arg) |arg| {
                        try zig_args.append("--test-cmd");
                        try zig_args.append(arg);
                    } else {
                        try zig_args.append("--test-cmd-bin");
                    }
                }
            }
        }

        if (b.sysroot) |sysroot| {
            try zig_args.appendSlice(&[_][]const u8{ "--sysroot", sysroot });
        }

        // -I and -L arguments that appear after the last --mod argument apply to all modules.
        const cwd: Io.Dir = .cwd();
        const io = b.graph.io;

        for (b.search_prefixes.items) |search_prefix| {
            var prefix_dir = cwd.openDir(io, search_prefix, .{}) catch |err| {
                return step.fail("unable to open prefix directory '{s}': {s}", .{
                    search_prefix, @errorName(err),
                });
            };
            defer prefix_dir.close(io);

            // Avoid passing -L and -I flags for nonexistent directories.
            // This prevents a warning, that should probably be upgraded to an error in Zig's
            // CLI parsing code, when the linker sees an -L directory that does not exist.

            if (prefix_dir.access(io, "lib", .{})) |_| {
                try zig_args.appendSlice(&.{
                    "-L", b.pathJoin(&.{ search_prefix, "lib" }),
                });
            } else |err| switch (err) {
                error.FileNotFound => {},
                else => |e| return step.fail("unable to access '{s}/lib' directory: {s}", .{
                    search_prefix, @errorName(e),
                }),
            }

            if (prefix_dir.access(io, "include", .{})) |_| {
                try zig_args.appendSlice(&.{
                    "-I", b.pathJoin(&.{ search_prefix, "include" }),
                });
            } else |err| switch (err) {
                error.FileNotFound => {},
                else => |e| return step.fail("unable to access '{s}/include' directory: {s}", .{
                    search_prefix, @errorName(e),
                }),
            }
        }

        if (compile.rc_includes != .any) {
            try zig_args.append("-rcincludes");
            try zig_args.append(@tagName(compile.rc_includes));
        }

        try addFlag(&zig_args, "each-lib-rpath", compile.each_lib_rpath);

        if (compile.build_id orelse b.build_id) |build_id| {
            try zig_args.append(switch (build_id) {
                .hexstring => |hs| b.fmt("--build-id=0x{x}", .{hs.toSlice()}),
                .none, .fast, .uuid, .sha1, .md5 => b.fmt("--build-id={s}", .{@tagName(build_id)}),
            });
        }

        const opt_zig_lib_dir = if (compile.zig_lib_dir) |dir|
            dir.getPath2(b, step)
        else if (b.graph.zig_lib_directory.path) |_|
            b.fmt("{f}", .{b.graph.zig_lib_directory})
        else
            null;

        if (opt_zig_lib_dir) |zig_lib_dir| {
            try zig_args.append("--zig-lib-dir");
            try zig_args.append(zig_lib_dir);
        }

        try addFlag(&zig_args, "PIE", compile.pie);

        if (compile.lto) |lto| {
            try zig_args.append(switch (lto) {
                .full => "-flto=full",
                .thin => "-flto=thin",
                .none => "-fno-lto",
            });
        }

        try addFlag(&zig_args, "sanitize-coverage-trace-pc-guard", compile.sanitize_coverage_trace_pc_guard);

        if (compile.subsystem) |subsystem| {
            try zig_args.append("--subsystem");
            try zig_args.append(@tagName(subsystem));
        }

        if (compile.mingw_unicode_entry_point) {
            try zig_args.append("-municode");
        }

        if (compile.error_limit) |err_limit| try zig_args.appendSlice(&.{
            "--error-limit", b.fmt("{d}", .{err_limit}),
        });

        // try addFlag(&zig_args, "incremental", b.graph.incremental);

        // try zig_args.append("--listen=-");

        // Windows has an argument length limit of 32,766 characters, macOS 262,144 and Linux
        // 2,097,152. If our args exceed 30 KiB, we instead write them to a "response file" and
        // pass that to zig, e.g. via 'zig build-lib @args.rsp'
        // See @file syntax here: https://gcc.gnu.org/onlinedocs/gcc/Overall-Options.html
        var args_length: usize = 0;
        for (zig_args.items) |arg| {
            args_length += arg.len + 1; // +1 to account for null terminator
        }
        if (args_length >= 30 * 1024) {
            try b.cache_root.handle.createDirPath(io, "args");

            const args_to_escape = zig_args.items[2..];
            var escaped_args = try std.array_list.Managed([]const u8).initCapacity(arena, args_to_escape.len);
            arg_blk: for (args_to_escape) |arg| {
                for (arg, 0..) |c, arg_idx| {
                    if (c == '\\' or c == '"') {
                        // Slow path for arguments that need to be escaped. We'll need to allocate and copy
                        var escaped: std.ArrayList(u8) = .empty;
                        try escaped.ensureTotalCapacityPrecise(arena, arg.len + 1);
                        try escaped.appendSlice(arena, arg[0..arg_idx]);
                        for (arg[arg_idx..]) |to_escape| {
                            if (to_escape == '\\' or to_escape == '"') try escaped.append(arena, '\\');
                            try escaped.append(arena, to_escape);
                        }
                        escaped_args.appendAssumeCapacity(escaped.items);
                        continue :arg_blk;
                    }
                }
                escaped_args.appendAssumeCapacity(arg); // no escaping needed so just use original argument
            }

            // Write the args to zig-cache/args/<SHA256 hash of args> to avoid conflicts with
            // other zig build commands running in parallel.
            const partially_quoted = try std.mem.join(arena, "\" \"", escaped_args.items);
            const args = try std.mem.concat(arena, u8, &[_][]const u8{ "\"", partially_quoted, "\"" });

            var args_hash: [Sha256.digest_length]u8 = undefined;
            Sha256.hash(args, &args_hash, .{});
            var args_hex_hash: [Sha256.digest_length * 2]u8 = undefined;
            _ = try std.fmt.bufPrint(&args_hex_hash, "{x}", .{&args_hash});

            const args_file = "args" ++ fs.path.sep_str ++ args_hex_hash;
            if (b.cache_root.handle.access(io, args_file, .{})) |_| {
                // The args file is already present from a previous run.
            } else |err| switch (err) {
                error.FileNotFound => {
                    var af = b.cache_root.handle.createFileAtomic(io, args_file, .{
                        .replace = false,
                        .make_path = true,
                    }) catch |e| return step.fail("failed creating tmp args file {f}{s}: {t}", .{
                        b.cache_root, args_file, e,
                    });
                    defer af.deinit(io);

                    af.file.writeStreamingAll(io, args) catch |e| {
                        return step.fail("failed writing args data to tmp file {f}{s}: {t}", .{
                            b.cache_root, args_file, e,
                        });
                    };
                    // Note we can't clean up this file, not even after build
                    // success, because that might interfere with another build
                    // process that needs the same file.
                    af.link(io) catch |e| switch (e) {
                        error.PathAlreadyExists => {
                            // The args file was created by another concurrent build process.
                        },
                        else => |other_err| return step.fail("failed linking tmp file {f}{s}: {t}", .{
                            b.cache_root, args_file, other_err,
                        }),
                    };
                },
                else => |other_err| return other_err,
            }

            const resolved_args_file = try mem.concat(arena, u8, &.{
                "@",
                try b.cache_root.join(arena, &.{args_file}),
            });

            zig_args.shrinkRetainingCapacity(2);
            try zig_args.append(resolved_args_file);
        }

        try zig_args.appendSlice(&.{
            // "-fllvm",
            "-fincremental",
            "-fno-emit-bin",
            "-fno-emit-asm",
            "-fno-emit-llvm-ir",
            "-fno-emit-llvm-bc",
            "-fno-emit-h",
            "-fno-emit-docs",
            "-fno-emit-implib",
            "--proj-path",
            b.fmt("{s}", .{build_root}),
        });

        return try zig_args.toOwnedSlice();
    }
};

fn serveWatchErrorBundle(
    io: std.Io,
    step_id: u32,
    cycle: u32,
    error_bundle: std.zig.ErrorBundle,
) std.Io.File.Writer.Error!void {
    const bytes_len = @sizeOf(shared.ServerToClient.ErrorBundle) + @sizeOf(u32) * error_bundle.extra.len + error_bundle.string_bytes.len;

    var header: shared.ServerToClient.Header = .{
        .tag = .watch_error_bundle,
        .bytes_len = @intCast(bytes_len),
    };

    var error_bundle_header: shared.ServerToClient.ErrorBundle = .{
        .step_id = step_id,
        .cycle = cycle,
        .extra_len = @intCast(error_bundle.extra.len),
        .string_bytes_len = @intCast(error_bundle.string_bytes.len),
    };

    const need_bswap = builtin.target.cpu.arch.endian() != .little;

    if (need_bswap) {
        std.mem.byteSwapAllFields(shared.ServerToClient.Header, &header);
        std.mem.byteSwapAllFields(shared.ServerToClient.ErrorBundle, &error_bundle_header);
        std.mem.byteSwapAllElements(u32, @constCast(error_bundle.extra)); // trust me bro
    }

    var file_writer = std.Io.File.stdout().writer(io, &.{});
    const writer = &file_writer.interface;

    var data = [_][]const u8{
        std.mem.asBytes(&header),
        std.mem.asBytes(&error_bundle_header),
        std.mem.sliceAsBytes(error_bundle.extra),
        error_bundle.string_bytes,
    };
    writer.writeVecAll(&data) catch return file_writer.err.?;
}
