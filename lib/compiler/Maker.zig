const Maker = @This();
const builtin = @import("builtin");

const std = @import("std");
const Allocator = std.mem.Allocator;
const Cache = std.Build.Cache;
const Configuration = std.Build.Configuration;
const File = std.Io.File;
const Io = std.Io;
const Dir = std.Io.Dir;
const Path = std.Build.Cache.Path;
const Writer = std.Io.Writer;
const assert = std.debug.assert;
const fatal = std.process.fatal;
const fmt = std.fmt;
const log = std.log;
const mem = std.mem;
const process = std.process;
const Color = std.zig.Color;

const Fuzz = @import("Maker/Fuzz.zig");
const Graph = @import("Maker/Graph.zig");
const Step = @import("Maker/Step.zig");
const Watch = @import("Maker/Watch.zig");
const WebServer = @import("Maker/WebServer.zig");
const ScannedConfig = @import("Maker/ScannedConfig.zig");
const PkgConfig = @import("Maker/PkgConfig.zig");

pub const std_options: std.Options = .{
    .side_channels_mitigations = .none,
    .http_disable_tls = true,
};

gpa: Allocator,
graph: *Graph,
install_paths: InstallPaths,
scanned_config: *const ScannedConfig,
steps: []Step,
generated_files: []Path,
run_args: ?[]const []const u8,

available_rss: u64,
max_rss_is_default: bool,
max_rss_mutex: Io.Mutex,
skip_oom_steps: bool,
unit_test_timeout_ns: ?u64,
watch: bool,
web_server: if (!builtin.single_threaded) ?WebServer else ?noreturn,
/// Allocated into `gpa`.
memory_blocked_steps: std.ArrayList(Configuration.Step.Index),
/// Allocated into `gpa`.
step_stack: std.array_hash_map.Auto(Configuration.Step.Index, void),
pkg_config: PkgConfig,

error_style: ErrorStyle,
multiline_errors: MultilineErrors,
summary: Summary,

dump_compile_step_info: bool,
compile_steps_info: std.AutoArrayHashMapUnmanaged(Configuration.Step.Index, Step.Compile.Info) = .empty,
compile_steps_info_mutex: std.Io.Mutex = .init,

pub const CompileStepsInfo = struct {
    compile_steps_info: []CompileStepInfo,

    pub const CompileStepInfo = struct {
        index: Configuration.Step.Index,
        args: []const []const u8,
        mods: []Step.Compile.Info.NamePathPair,
    };
};

var safe_allocator_instance: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{});
var stdio_buffer_allocation: [256]u8 = undefined;
var stdout_writer_allocation: Io.File.Writer = undefined;
var debug_maker_leaks: bool = false;

const is_debug_mode = builtin.mode == .Debug;
const use_safe_allocator = switch (builtin.mode) {
    .Debug, .ReleaseSafe => true,
    .ReleaseFast, .ReleaseSmall => false,
};

const InstallPaths = struct {
    prefix: Path,
    lib: Path,
    bin: Path,
    include: Path,
};

const PrintNode = struct {
    parent: ?*PrintNode,
    last: bool = false,
};

const ErrorStyle = enum {
    verbose,
    minimal,
    verbose_clear,
    minimal_clear,
    fn verboseContext(s: ErrorStyle) bool {
        return switch (s) {
            .verbose, .verbose_clear => true,
            .minimal, .minimal_clear => false,
        };
    }
    fn clearOnUpdate(s: ErrorStyle) bool {
        return switch (s) {
            .verbose, .minimal => false,
            .verbose_clear, .minimal_clear => true,
        };
    }
};
const MultilineErrors = enum { indent, newline, none };
const Summary = enum { all, new, failures, line, none };

const Override = enum { inactive, active, print_configuration, watch };
var override: Override = .inactive;

pub fn main(init: process.Init.Minimal) !void {
    // The build runner is long-lived in the following use cases:
    // * `--watch` mode
    // * `--webui` mode
    // * A project that has a large, complex build graph.
    const gpa = if (use_safe_allocator) safe_allocator_instance.allocator() else std.heap.smp_allocator;
    defer if (use_safe_allocator) {
        _ = safe_allocator_instance.deinit();
    };

    var threaded: std.Io.Threaded = .init(gpa, .{
        .environ = init.environ,
        .argv0 = .init(init.args),
    });
    defer threaded.deinit();
    const io = threaded.io();

    // ...but we'll back our arena by `std.heap.page_allocator` for efficiency.
    var arena_instance: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_instance.deinit();
    defer if (debugMakerLeaks()) log.debug("used {Bi} of arena", .{arena_instance.queryCapacity()});
    const arena = arena_instance.allocator();

    const args = try init.args.toSlice(arena);

    // skip my own exe name
    var arg_idx: usize = 1;

    // Handle Zigscient spawning itself with the `tailor` subcmd
    if (args.len > 1 and std.mem.eql(u8, args[1], "tailor")) arg_idx += 1;

    const zig_exe = expectArgOrFatal(args, &arg_idx, "--zig");
    const zig_lib_dir = expectArgOrFatal(args, &arg_idx, "--zig-lib-dir");
    const build_root = expectArgOrFatal(args, &arg_idx, "--build-root");
    const local_cache_root = expectArgOrFatal(args, &arg_idx, "--local-cache");
    const global_cache_root = expectArgOrFatal(args, &arg_idx, "--global-cache");
    const configure_path = expectArgOrFatal(args, &arg_idx, "--configuration");

    const cwd: Dir = .cwd();

    const zig_lib_directory: Cache.Directory = .{
        .path = zig_lib_dir,
        .handle = try cwd.openDir(io, zig_lib_dir, .{}),
    };

    const build_root_directory: Cache.Directory = .{
        .path = build_root,
        .handle = try cwd.openDir(io, build_root, .{}),
    };

    const local_cache_directory: Cache.Directory = .{
        .path = local_cache_root,
        .handle = try cwd.createDirPathOpen(io, local_cache_root, .{}),
    };

    const global_cache_directory: Cache.Directory = .{
        .path = global_cache_root,
        .handle = try cwd.createDirPathOpen(io, global_cache_root, .{}),
    };

    var graph: Graph = .{
        .io = io,
        .arena = arena,
        .cache = .{
            .io = io,
            .gpa = gpa,
            .manifest_dir = try local_cache_directory.handle.createDirPathOpen(io, "h", .{}),
            .cwd = try process.currentPathAlloc(io, arena),
        },
        .zig_exe = zig_exe,
        .environ_map = try init.environ.createMap(arena),
        .global_cache_root = global_cache_directory,
        .local_cache_root = local_cache_directory,
        .zig_lib_directory = zig_lib_directory,
        .build_root_directory = build_root_directory,
    };

    graph.cache.addPrefix(.{ .path = null, .handle = cwd });
    graph.cache.addPrefix(build_root_directory);
    graph.cache.addPrefix(local_cache_directory);
    graph.cache.addPrefix(global_cache_directory);
    graph.cache.hash.addBytes(builtin.zig_version_string);

    var step_names: std.ArrayList([]const u8) = .empty;
    var help_menu = false;
    var steps_menu = false;
    var print_configuration = false;
    var override_install_prefix: ?[]const u8 = null;
    var override_lib_dir: ?[]const u8 = null;
    var override_bin_dir: ?[]const u8 = null;
    var override_include_dir: ?[]const u8 = null;
    var error_style: ErrorStyle = .verbose;
    var multiline_errors: MultilineErrors = .indent;
    var summary: ?Summary = null;
    var max_rss: u64 = 0;
    var skip_oom_steps = false;
    var test_timeout_ns: ?u64 = null;
    var color: Color = .settingFromEnvironment(&graph.environ_map);
    var watch = false;
    var fuzz: ?Fuzz.Mode = null;
    var debounce_interval_ms: u16 = 50;
    var webui_listen: ?Io.net.IpAddress = null;
    var debug_pkg_config = false;
    var run_args: ?[]const []const u8 = null;

    if (std.zig.EnvVar.ZIG_BUILD_ERROR_STYLE.get(&graph.environ_map)) |str| {
        if (std.meta.stringToEnum(ErrorStyle, str)) |style| {
            error_style = style;
        }
    }

    if (std.zig.EnvVar.ZIG_BUILD_MULTILINE_ERRORS.get(&graph.environ_map)) |str| {
        if (std.meta.stringToEnum(MultilineErrors, str)) |style| {
            multiline_errors = style;
        }
    }

    while (nextArg(args, &arg_idx)) |arg| {
        if (mem.startsWith(u8, arg, "-")) {
            if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
                help_menu = true;
            } else if (mem.eql(u8, arg, "-l") or mem.eql(u8, arg, "--list-steps")) {
                steps_menu = true;
            } else if (mem.eql(u8, arg, "--print-configuration")) {
                if (override != .inactive) override = .print_configuration; // custom
                print_configuration = true;
            } else if (mem.eql(u8, arg, "--zigscient")) { // custom
                override = .active;
            } else if (mem.eql(u8, arg, "-p") or mem.eql(u8, arg, "--prefix")) {
                override_install_prefix = nextArgOrFatal(args, &arg_idx);
            } else if (mem.eql(u8, arg, "--prefix-lib-dir")) {
                override_lib_dir = nextArgOrFatal(args, &arg_idx);
            } else if (mem.eql(u8, arg, "--prefix-exe-dir")) {
                override_bin_dir = nextArgOrFatal(args, &arg_idx);
            } else if (mem.eql(u8, arg, "--prefix-include-dir")) {
                override_include_dir = nextArgOrFatal(args, &arg_idx);
            } else if (mem.eql(u8, arg, "--sysroot")) {
                graph.sysroot = nextArgOrFatal(args, &arg_idx);
            } else if (mem.eql(u8, arg, "--maxrss")) {
                const max_rss_text = nextArgOrFatal(args, &arg_idx);
                max_rss = std.fmt.parseIntSizeSuffix(max_rss_text, 10) catch |err|
                    fatal("invalid byte size {q}: {t}", .{ max_rss_text, err });
            } else if (mem.eql(u8, arg, "--skip-oom-steps")) {
                skip_oom_steps = true;
            } else if (mem.eql(u8, arg, "--test-timeout")) {
                const units: []const struct { []const u8, u64 } = &.{
                    .{ "ns", 1 },
                    .{ "nanosecond", 1 },
                    .{ "us", std.time.ns_per_us },
                    .{ "microsecond", std.time.ns_per_us },
                    .{ "ms", std.time.ns_per_ms },
                    .{ "millisecond", std.time.ns_per_ms },
                    .{ "s", std.time.ns_per_s },
                    .{ "second", std.time.ns_per_s },
                    .{ "m", std.time.ns_per_min },
                    .{ "minute", std.time.ns_per_min },
                    .{ "h", std.time.ns_per_hour },
                    .{ "hour", std.time.ns_per_hour },
                };
                const timeout_str = nextArgOrFatal(args, &arg_idx);
                const num_end_idx = std.mem.findLastNone(u8, timeout_str, "abcdefghijklmnopqrstuvwxyz") orelse fatal(
                    "invalid timeout {q}: expected unit (ns, us, ms, s, m, h)",
                    .{timeout_str},
                );
                const num_str = timeout_str[0 .. num_end_idx + 1];
                const unit_str = timeout_str[num_end_idx + 1 ..];
                const unit_factor: f64 = for (units) |unit_and_factor| {
                    if (std.mem.eql(u8, unit_str, unit_and_factor[0])) {
                        break @floatFromInt(unit_and_factor[1]);
                    }
                } else fatal(
                    "invalid timeout {q}: invalid unit {q} (expected ns, us, ms, s, m, h)",
                    .{ timeout_str, unit_str },
                );
                const num_parsed = std.fmt.parseFloat(f64, num_str) catch |err| fatal(
                    "invalid timeout {q}: invalid number {q} ({t})",
                    .{ timeout_str, num_str, err },
                );
                test_timeout_ns = std.math.lossyCast(u64, unit_factor * num_parsed);
            } else if (mem.eql(u8, arg, "--search-prefix")) {
                try graph.search_prefixes.append(arena, nextArgOrFatal(args, &arg_idx));
            } else if (mem.eql(u8, arg, "--libc")) {
                graph.libc_file = nextArgOrFatal(args, &arg_idx);
            } else if (mem.eql(u8, arg, "--color")) {
                const next_arg = nextArg(args, &arg_idx) orelse
                    fatalWithHint("expected [auto|on|off] after {q}", .{arg});
                color = std.meta.stringToEnum(Color, next_arg) orelse {
                    fatalWithHint("expected [auto|on|off] after {q}, found {q}", .{
                        arg, next_arg,
                    });
                };
            } else if (mem.eql(u8, arg, "--error-style")) {
                const next_arg = nextArg(args, &arg_idx) orelse
                    fatalWithHint("expected style after {q}", .{arg});
                error_style = std.meta.stringToEnum(ErrorStyle, next_arg) orelse {
                    fatalWithHint("expected style after {q}, found {q}", .{ arg, next_arg });
                };
            } else if (mem.eql(u8, arg, "--multiline-errors")) {
                const next_arg = nextArg(args, &arg_idx) orelse
                    fatalWithHint("expected style after {q}", .{arg});
                multiline_errors = std.meta.stringToEnum(MultilineErrors, next_arg) orelse {
                    fatalWithHint("expected style after {q}, found {q}", .{ arg, next_arg });
                };
            } else if (mem.eql(u8, arg, "--summary")) {
                const next_arg = nextArg(args, &arg_idx) orelse
                    fatalWithHint("expected [all|new|failures|line|none] after {q}", .{arg});
                summary = std.meta.stringToEnum(Summary, next_arg) orelse {
                    fatalWithHint("expected [all|new|failures|line|none] after {q}, found {q}", .{
                        arg, next_arg,
                    });
                };
            } else if (mem.eql(u8, arg, "--seed")) {
                const next_arg = nextArg(args, &arg_idx) orelse
                    fatalWithHint("expected u32 after {q}", .{arg});
                graph.random_seed = std.fmt.parseUnsigned(u32, next_arg, 0) catch |err| {
                    fatal("unable to parse seed {q} as unsigned 32-bit integer: {t}", .{ next_arg, err });
                };
            } else if (mem.eql(u8, arg, "--build-id")) {
                graph.build_id = .fast;
            } else if (mem.cutPrefix(u8, arg, "--build-id=")) |style| {
                graph.build_id = std.zig.BuildId.parse(style) catch |err|
                    fatal("unable to parse --build-id style {q}: {t}", .{ style, err });
            } else if (mem.eql(u8, arg, "--debounce")) {
                const next_arg = nextArg(args, &arg_idx) orelse
                    fatalWithHint("expected u16 after {q}", .{arg});
                debounce_interval_ms = std.fmt.parseUnsigned(u16, next_arg, 0) catch |err| {
                    fatal("unable to parse debounce interval {q} as unsigned 16-bit integer: {t}", .{
                        next_arg, err,
                    });
                };
            } else if (mem.eql(u8, arg, "--webui")) {
                if (webui_listen == null) webui_listen = .{ .ip6 = .loopback(0) };
            } else if (mem.startsWith(u8, arg, "--webui=")) {
                const addr_str = arg["--webui=".len..];
                if (std.mem.eql(u8, addr_str, "-")) fatal("web interface cannot listen on stdio", .{});
                webui_listen = Io.net.IpAddress.parseLiteral(addr_str) catch |err| {
                    fatal("invalid web UI address {q}: {t}", .{ addr_str, err });
                };
            } else if (mem.eql(u8, arg, "--debug-log")) {
                const next_arg = nextArgOrFatal(args, &arg_idx);
                try graph.debug_log_scopes.append(arena, next_arg);
            } else if (mem.eql(u8, arg, "--debug-compile-errors")) {
                graph.debug_compile_errors = true;
            } else if (mem.eql(u8, arg, "--debug-incremental")) {
                graph.debug_incremental = true;
            } else if (mem.eql(u8, arg, "--debug-pkg-config")) {
                debug_pkg_config = true;
            } else if (mem.eql(u8, arg, "--debug-rt")) {
                graph.debug_compiler_runtime_libs = .Debug;
            } else if (mem.cutPrefix(u8, arg, "--debug-rt=")) |rest| {
                graph.debug_compiler_runtime_libs = std.meta.stringToEnum(std.builtin.OptimizeMode, rest) orelse
                    fatal("unrecognized optimization mode: {s}", .{rest});
            } else if (is_debug_mode and mem.eql(u8, arg, "--debug-maker-leaks")) {
                debug_maker_leaks = true;
            } else if (mem.eql(u8, arg, "--libc-runtimes") or mem.eql(u8, arg, "--glibc-runtimes")) {
                // --glibc-runtimes was the old name of the flag; kept for compatibility for now.
                graph.libc_runtimes_dir = nextArgOrFatal(args, &arg_idx);
            } else if (mem.eql(u8, arg, "--verbose")) {
                graph.verbose = true;
            } else if (mem.eql(u8, arg, "--verbose-air")) {
                graph.verbose_air = true;
            } else if (mem.eql(u8, arg, "--verbose-cc")) {
                graph.verbose_cc = true;
            } else if (mem.eql(u8, arg, "--verbose-llvm-ir")) {
                graph.verbose_llvm_ir = true;
            } else if (mem.eql(u8, arg, "--watch")) {
                if (override != .inactive) override = .watch; // custom
                watch = true;
            } else if (mem.eql(u8, arg, "--time-report")) {
                graph.time_report = true;
                if (webui_listen == null) webui_listen = .{ .ip6 = .loopback(0) };
            } else if (mem.eql(u8, arg, "--fuzz")) {
                fuzz = .{ .forever = undefined };
                graph.fuzzing = true;
                if (webui_listen == null) webui_listen = .{ .ip6 = .loopback(0) };
            } else if (mem.startsWith(u8, arg, "--fuzz=")) {
                const value = arg["--fuzz=".len..];
                if (value.len == 0) fatal("missing argument to --fuzz", .{});

                const unit: u8 = value[value.len - 1];
                const digits = switch (unit) {
                    '0'...'9' => value,
                    'K', 'M', 'G' => value[0 .. value.len - 1],
                    else => fatal(
                        "invalid argument to --fuzz, expected a positive number optionally suffixed by one of: [KMG]",
                        .{},
                    ),
                };

                const amount = std.fmt.parseInt(u64, digits, 10) catch {
                    fatal(
                        "invalid argument to --fuzz, expected a positive number optionally suffixed by one of: [KMG]",
                        .{},
                    );
                };

                const normalized_amount = std.math.mul(u64, amount, switch (unit) {
                    else => unreachable,
                    '0'...'9' => 1,
                    'K' => 1000,
                    'M' => 1_000_000,
                    'G' => 1_000_000_000,
                }) catch fatal("fuzzing limit amount overflows u64", .{});

                fuzz = .{
                    .limit = .{
                        .amount = normalized_amount,
                    },
                };
                graph.fuzzing = true;
            } else if (mem.eql(u8, arg, "-fincremental")) {
                graph.incremental = true;
            } else if (mem.eql(u8, arg, "-fno-incremental")) {
                graph.incremental = false;
            } else if (mem.eql(u8, arg, "-fwine")) {
                graph.enable_wine = true;
            } else if (mem.eql(u8, arg, "-fno-wine")) {
                graph.enable_wine = false;
            } else if (mem.eql(u8, arg, "-fqemu")) {
                graph.enable_qemu = true;
            } else if (mem.eql(u8, arg, "-fno-qemu")) {
                graph.enable_qemu = false;
            } else if (mem.eql(u8, arg, "-fwasmtime")) {
                graph.enable_wasmtime = true;
            } else if (mem.eql(u8, arg, "-fno-wasmtime")) {
                graph.enable_wasmtime = false;
            } else if (mem.eql(u8, arg, "-frosetta")) {
                graph.enable_rosetta = true;
            } else if (mem.eql(u8, arg, "-fno-rosetta")) {
                graph.enable_rosetta = false;
            } else if (mem.eql(u8, arg, "-fdarling")) {
                graph.enable_darling = true;
            } else if (mem.eql(u8, arg, "-fno-darling")) {
                graph.enable_darling = false;
            } else if (mem.eql(u8, arg, "-fallow-so-scripts")) {
                graph.allow_so_scripts = true;
            } else if (mem.eql(u8, arg, "-fno-allow-so-scripts")) {
                graph.allow_so_scripts = false;
            } else if (mem.eql(u8, arg, "-freference-trace")) {
                graph.reference_trace = 256;
            } else if (mem.cutPrefix(u8, arg, "-freference-trace=")) |num| {
                graph.reference_trace = std.fmt.parseUnsigned(u32, num, 10) catch |err|
                    fatal("unable to parse reference_trace count {q}: {t}", .{ num, err });
            } else if (mem.eql(u8, arg, "-fno-reference-trace")) {
                graph.reference_trace = null;
            } else if (mem.eql(u8, arg, "--error-limit")) {
                const next_arg = nextArgOrFatal(args, &arg_idx);
                graph.error_limit = std.fmt.parseUnsigned(u32, next_arg, 0) catch |err|
                    fatal("unable to parse error limit {q}: {t}", .{ next_arg, err });
            } else if (mem.cutPrefix(u8, arg, "-j")) |text| {
                const n = std.fmt.parseUnsigned(u32, text, 10) catch |err|
                    fatal("unable to parse jobs count {q}: {t}", .{ text, err });
                if (n < 1) fatal("number of jobs must be at least 1", .{});
                threaded.setAsyncLimit(.limited(n));
                graph.max_jobs = n;
            } else if (mem.eql(u8, arg, "--")) {
                run_args = argsRest(args, arg_idx);
                break;
            } else {
                fatalWithHint("unrecognized argument: {s}", .{arg});
            }
        } else {
            try step_names.append(arena, arg);
        }
    }

    const NO_COLOR = std.zig.EnvVar.NO_COLOR.isSet(&graph.environ_map);
    const CLICOLOR_FORCE = std.zig.EnvVar.CLICOLOR_FORCE.isSet(&graph.environ_map);

    graph.stderr_mode = switch (color) {
        .auto => try .detect(io, .stderr(), NO_COLOR, CLICOLOR_FORCE),
        .on => .escape_codes,
        .off => .no_color,
    };

    const scanned_config: ScannedConfig = sc: {
        const configuration = c: {
            var file = cwd.openFile(io, configure_path, .{}) catch |err|
                fatal("failed to open configuration file {s}: {t}", .{ configure_path, err });
            defer file.close(io);
            break :c Configuration.loadFile(arena, io, file) catch |err|
                fatal("failed to load configuration file {s}: {t}", .{ configure_path, err });
        };
        // Technically if the configuration is marked as poisoned, we could
        // already delete the file now, but we leave it around in case the
        // maker process fails or crashes and it's helpful to be able to repeat
        // execution of the command line or otherwise inspect the configuration file.
        const c = &configuration;
        var top_level_steps: std.array_hash_map.String(Configuration.Step.Index) = .empty;
        for (configuration.steps, 0..) |*conf_step, step_index_usize| {
            if (conf_step.owner != .root) continue;
            const step_index: Configuration.Step.Index = @enumFromInt(step_index_usize);
            const flags = conf_step.flags(c);
            switch (flags.tag) {
                .top_level => {
                    const name = step_index.ptr(c).name.slice(c);
                    try top_level_steps.put(arena, name, step_index);
                },
                else => {},
            }
        }
        for (c.search_prefixes) |search_prefix| {
            try graph.search_prefixes.append(arena, search_prefix.slice(c));
        }
        break :sc .{
            .configuration = configuration,
            .top_level_steps = top_level_steps,
            .path = configure_path,
        };
    };

    if (help_menu) {
        var w = initStdoutWriter(io);
        scanned_config.printUsage(&graph, w) catch |err| switch (err) {
            error.WriteFailed => return stdout_writer_allocation.err.?,
            else => |e| return e,
        };
        w.flush() catch return stdout_writer_allocation.err.?;
        return cleanExit(io, &scanned_config);
    } else if (steps_menu) {
        var w = initStdoutWriter(io);
        scanned_config.printSteps(&graph, w) catch |err| switch (err) {
            error.WriteFailed => return stdout_writer_allocation.err.?,
            else => |e| return e,
        };
        w.flush() catch return stdout_writer_allocation.err.?;
        return cleanExit(io, &scanned_config);
    } else if (override == .inactive and print_configuration) {
        var w = initStdoutWriter(io);
        scanned_config.print(w) catch return stdout_writer_allocation.err.?;
        w.flush() catch return stdout_writer_allocation.err.?;
        return cleanExit(io, &scanned_config);
    }

    if (webui_listen != null) {
        if (watch) fatal("using '--webui' and '--watch' together is not yet supported; consider omitting '--watch' in favour of the web UI \"Rebuild\" button", .{});
        if (builtin.single_threaded) fatal("'--webui' is not yet supported on single-threaded hosts", .{});
    }

    const main_progress_node = std.Progress.start(io, .{
        .disable_printing = (graph.stderr_mode.? == .no_color or override == .active),
    });
    defer main_progress_node.end();

    const install_prefix_path: Path = if (graph.environ_map.get("DESTDIR")) |dest_dir| .{
        .root_dir = .cwd(),
        .sub_path = try Dir.path.join(arena, &.{ dest_dir, override_install_prefix orelse "/usr" }),
    } else if (override_install_prefix) |cwd_relative| .{
        .root_dir = .cwd(),
        .sub_path = cwd_relative,
    } else .{
        .root_dir = build_root_directory,
        .sub_path = "zig-out",
    };

    const install_lib_path: Path = if (override_lib_dir) |cwd_relative| .{
        .root_dir = .cwd(),
        .sub_path = cwd_relative,
    } else try install_prefix_path.join(arena, "lib");

    const install_bin_path: Path = if (override_bin_dir) |cwd_relative| .{
        .root_dir = .cwd(),
        .sub_path = cwd_relative,
    } else try install_prefix_path.join(arena, "bin");

    const install_include_path: Path = if (override_include_dir) |cwd_relative| .{
        .root_dir = .cwd(),
        .sub_path = cwd_relative,
    } else try install_prefix_path.join(arena, "include");

    if (graph.reference_trace == null and override == .active) graph.reference_trace = 12;

    var maker: Maker = .{
        .gpa = gpa,
        .graph = &graph,
        .scanned_config = &scanned_config,
        .install_paths = .{
            .prefix = install_prefix_path,
            .lib = install_lib_path,
            .bin = install_bin_path,
            .include = install_include_path,
        },

        .steps = try arena.alloc(Step, scanned_config.configuration.steps.len),
        .generated_files = try arena.alloc(Path, scanned_config.configuration.generated_files_len),
        .run_args = run_args,

        .available_rss = max_rss,
        .max_rss_is_default = false,
        .max_rss_mutex = .init,
        .skip_oom_steps = skip_oom_steps,
        .unit_test_timeout_ns = test_timeout_ns,

        .watch = watch,
        .web_server = undefined, // set after `prepare`
        .memory_blocked_steps = .empty,
        .step_stack = .empty,
        .pkg_config = .{ .debug = debug_pkg_config },

        .error_style = error_style,
        .multiline_errors = multiline_errors,
        .summary = summary orelse if (watch or webui_listen != null) .line else .failures,
        .dump_compile_step_info = override == .active,
    };
    defer {
        maker.memory_blocked_steps.deinit(gpa);
        maker.step_stack.deinit(gpa);
    }

    if (maker.available_rss == 0) {
        maker.available_rss = process.totalSystemMemory() catch std.math.maxInt(u64);
        maker.max_rss_is_default = true;
    }

    maker.prepare(step_names.items) catch |err| switch (err) {
        error.DependencyLoopDetected, error.InsufficientMemory => {
            _ = io.lockStderr(&.{}, graph.stderr_mode) catch {};
            process.exit(1);
        },
        else => |e| return e,
    };

    var w: Watch = w: {
        if (!watch) break :w undefined;
        if (!Watch.have_impl) fatal("--watch not yet implemented for {t}", .{builtin.os.tag});
        break :w try .init(&maker);
    };

    const now = Io.Clock.Timestamp.now(io, .awake);

    maker.web_server = if (webui_listen) |listen_address| ws: {
        if (builtin.single_threaded) unreachable; // `fatal` above
        break :ws .init(.{
            .maker = &maker,
            .root_prog_node = main_progress_node,
            .listen_address = listen_address,
            .base_timestamp = now,
        });
    } else null;

    if (maker.web_server) |*ws| {
        ws.start() catch |err| fatal("failed to start web server: {t}", .{err});
    }

    rebuild: while (true) : (if (maker.error_style.clearOnUpdate()) {
        const stderr = try io.lockStderr(&stdio_buffer_allocation, graph.stderr_mode);
        defer io.unlockStderr();
        stderr.file_writer.interface.writeAll("\x1B[2J\x1B[3J\x1B[H") catch |err| switch (err) {
            error.WriteFailed => return stderr.file_writer.err.?,
        };
    }) {
        if (maker.web_server) |*ws| ws.startBuild();

        try maker.makeStepNames(step_names.items, main_progress_node, fuzz);

        if (maker.dump_compile_step_info) {
            var agg: std.ArrayList(CompileStepsInfo.CompileStepInfo) = .empty;

            for (maker.compile_steps_info.keys(), maker.compile_steps_info.values()) |cs_idx, *cs_xtra| {
                try agg.append(arena, .{ .index = cs_idx, .args = cs_xtra.args.items, .mods = cs_xtra.mods.items });
            }

            const stringified_build_config = try std.json.Stringify.valueAlloc(
                gpa,
                CompileStepsInfo{
                    .compile_steps_info = agg.items,
                },
                .{ .whitespace = .indent_2 },
            );

            var file_writer = std.Io.File.stdout().writer(io, &.{});
            file_writer.interface.writeAll(stringified_build_config) catch return file_writer.err.?;
            std.process.exit(0);
        }

        if (maker.web_server) |*web_server| {
            if (fuzz) |mode| if (mode != .forever) fatal(
                "error: limited fuzzing is not implemented yet for --webui",
                .{},
            );

            web_server.finishBuild(.{ .fuzz = fuzz != null });
        }

        if (maker.web_server) |*web_server| {
            const c = &scanned_config.configuration;
            assert(!watch); // fatal error after CLI parsing
            while (true) switch (try web_server.wait()) {
                .rebuild => {
                    for (maker.step_stack.keys()) |step_index| {
                        const step = maker.stepByIndex(step_index);
                        step.state = .precheck_done;
                        const deps = step_index.ptr(c).deps.slice(c);
                        step.pending_deps = @intCast(deps.len);
                        step.reset(&maker);
                    }
                    continue :rebuild;
                },
            };
        }

        if (!maker.watch) return;

        // Comptime-known guard to prevent including the logic below when `!Watch.have_impl`.
        if (!Watch.have_impl) unreachable;

        try w.update(maker.step_stack.keys());

        // Wait until a file system notification arrives. Read all such events
        // until the buffer is empty. Then wait for a debounce interval, resetting
        // if any more events come in. After the debounce interval has passed,
        // trigger a rebuild on all steps with modified inputs, as well as their
        // recursive dependants.
        var caption_buf: [std.Progress.Node.max_name_len]u8 = undefined;
        const caption = std.fmt.bufPrint(&caption_buf, "watching {d} directories, {d} processes", .{
            w.dir_count, countSubProcesses(&maker),
        }) catch &caption_buf;
        var debouncing_node = main_progress_node.start(caption, 0);
        var in_debounce = false;
        while (true) switch (try w.wait(if (in_debounce) .{ .ms = debounce_interval_ms } else .none)) {
            .timeout => {
                assert(in_debounce);
                debouncing_node.end();
                markFailedStepsDirty(&maker);
                continue :rebuild;
            },
            .dirty => if (!in_debounce) {
                in_debounce = true;
                debouncing_node.end();
                debouncing_node = main_progress_node.start("Debouncing (Change Detected)", 0);
            },
            .clean => {},
        };
    }
}

fn markFailedStepsDirty(maker: *Maker) void {
    const all_steps = maker.step_stack.keys();

    for (all_steps) |step_index| {
        const step = maker.stepByIndex(step_index);
        switch (step.state) {
            .dependency_failure, .failure, .skipped => _ = maker.invalidateResult(step),
            else => continue,
        }
    }
    // Now that all dirty steps have been found, the remaining steps that
    // succeeded from last run shall be marked "cached".
    for (all_steps) |step_index| {
        const step = maker.stepByIndex(step_index);
        switch (step.state) {
            .success => step.result_cached = true,
            else => continue,
        }
    }
}

fn countSubProcesses(maker: *Maker) usize {
    const all_steps = maker.step_stack.keys();
    var count: usize = 0;
    for (all_steps) |step_index| {
        const s = maker.stepByIndex(step_index);
        count += @intFromBool(s.getZigProcess() != null);
    }
    return count;
}

pub fn stepByIndex(maker: *const Maker, i: Configuration.Step.Index) *Step {
    return &maker.steps[@intFromEnum(i)];
}

fn prepare(maker: *Maker, step_names: []const []const u8) !void {
    const gpa = maker.gpa;
    const graph = maker.graph;
    const arena = graph.arena;
    const seed: u32 = graph.random_seed;
    const step_stack = &maker.step_stack;
    const c = &maker.scanned_config.configuration;

    for (maker.steps, 0..) |*step, step_index_usize| {
        const step_index: Configuration.Step.Index = @enumFromInt(step_index_usize);
        step.* = .{ .extended = .init(step_index.ptr(c).flags(c).tag) };
    }

    if (step_names.len == 0) {
        try step_stack.put(gpa, c.default_step, {});
    } else {
        try step_stack.ensureUnusedCapacity(gpa, step_names.len);
        for (0..step_names.len) |i| {
            const step_name = step_names[step_names.len - i - 1];
            const s: std.Build.Configuration.Step.Index = if (override == .active) cs: {
                const cs_idx = std.fmt.parseInt(u32, step_name, 10) catch {
                    fatal("step: {s} in not a valid Index", .{step_name});
                };
                if (!(cs_idx < maker.scanned_config.configuration.steps.len))
                    fatal("step index: {s} in not a valid Index. OutOfBounds {}", .{ step_name, maker.scanned_config.configuration.steps.len });
                break :cs @enumFromInt(cs_idx);
            } else maker.scanned_config.top_level_steps.get(step_name) orelse {
                log.info("to list available steps: zig build -l", .{});
                fatal("no such step: {s}", .{step_name});
            };

            step_stack.putAssumeCapacity(s, {});
        }
    }

    const starting_steps = try arena.dupe(Configuration.Step.Index, step_stack.keys());

    var rng = std.Random.DefaultPrng.init(seed);
    const rand = rng.random();
    rand.shuffle(Configuration.Step.Index, starting_steps);

    for (starting_steps) |s| {
        try constructGraphAndCheckForDependencyLoop(maker, s, &maker.step_stack, rand);
    }

    {
        // Check that we have enough memory to complete the build.
        var any_problems = false;
        var max_needed: u64 = 0;
        for (step_stack.keys()) |step_index| {
            const make_step = maker.stepByIndex(step_index);
            const conf_step = step_index.ptr(c);
            const max_rss = conf_step.max_rss.toBytes();
            if (max_rss == 0) continue;
            max_needed = @max(max_needed, max_rss);
            if (max_rss > maker.available_rss) {
                if (maker.skip_oom_steps) {
                    make_step.state = .skipped_oom;
                    for (make_step.dependants.items) |dependant| {
                        maker.stepByIndex(dependant).pending_deps -= 1;
                    }
                } else {
                    log.err("{s}{s}: this step declares an upper bound of {d} bytes of memory, exceeding the available {d} bytes of memory", .{
                        conf_step.owner.depPrefixSlice(c),
                        conf_step.name.slice(c),
                        max_rss,
                        maker.available_rss,
                    });
                    any_problems = true;
                }
            }
        }
        if (any_problems) {
            if (maker.max_rss_is_default) {
                std.log.info("use --maxrss {d} to proceed, risking system memory exhaustion", .{
                    max_needed,
                });
            }
            return error.InsufficientMemory;
        }
    }
}

fn makeStepNames(
    maker: *Maker,
    step_names: []const []const u8,
    parent_prog_node: std.Progress.Node,
    fuzz: ?Fuzz.Mode,
) !void {
    const graph = maker.graph;
    const gpa = maker.gpa;
    const io = graph.io;
    const step_stack = &maker.step_stack;
    const top_level_steps = &maker.scanned_config.top_level_steps;
    const c = &maker.scanned_config.configuration;

    {
        // Collect the initial set of tasks (those with no outstanding dependencies) into a buffer,
        // then spawn them. The buffer is so that we don't race with `makeStep` and end up thinking
        // a step is initial when it actually became ready due to an earlier initial step.
        var initial_set: std.ArrayList(Configuration.Step.Index) = .empty;
        defer initial_set.deinit(gpa);
        try initial_set.ensureUnusedCapacity(gpa, step_stack.count());
        for (step_stack.keys()) |step_index| {
            const s = maker.stepByIndex(step_index);
            if (s.state == .precheck_done and s.pending_deps == 0) {
                initial_set.appendAssumeCapacity(step_index);
            }
        }

        const step_prog = parent_prog_node.start("steps", step_stack.count());
        defer step_prog.end();

        var group: Io.Group = .init;
        defer group.cancel(io);
        // Start working on all of the initial steps...
        for (initial_set.items) |step_index| try stepReady(maker, &group, step_index, step_prog);
        // ...and `makeStep` will trigger every other step when their last dependency finishes.
        try group.await(io);
    }

    assert(maker.memory_blocked_steps.items.len == 0);

    var test_pass_count: usize = 0;
    var test_skip_count: usize = 0;
    var test_fail_count: usize = 0;
    var test_crash_count: usize = 0;
    var test_timeout_count: usize = 0;

    var test_count: usize = 0;

    var success_count: usize = 0;
    var skipped_count: usize = 0;
    var failure_count: usize = 0;
    var pending_count: usize = 0;
    var total_compile_errors: usize = 0;

    var cleanup_task = io.async(cleanTmpFiles, .{ maker, step_stack.keys() });
    defer cleanup_task.await(io);

    for (step_stack.keys()) |step_index| {
        const make_step = maker.stepByIndex(step_index);
        test_pass_count += make_step.test_results.passCount();
        test_skip_count += make_step.test_results.skip_count;
        test_fail_count += make_step.test_results.fail_count;
        test_crash_count += make_step.test_results.crash_count;
        test_timeout_count += make_step.test_results.timeout_count;

        test_count += make_step.test_results.test_count;

        switch (make_step.state) {
            .precheck_unstarted => unreachable,
            .precheck_started => unreachable,
            .precheck_done => unreachable,
            .dependency_failure => pending_count += 1,
            .success => success_count += 1,
            .skipped, .skipped_oom => skipped_count += 1,
            .failure => {
                failure_count += 1;
                const compile_errors_len = make_step.result_error_bundle.errorMessageCount();
                if (compile_errors_len > 0) {
                    total_compile_errors += compile_errors_len;
                }
            },
        }
    }

    if (failure_count == 0 and maker.dump_compile_step_info) return;

    if (fuzz) |mode| blk: {
        switch (builtin.os.tag) {
            // Current implementation depends on two things that need to be ported to Windows:
            // * Memory-mapping to share data between the fuzzer and build runner.
            // * COFF/PE support added to `std.debug.Info` (it needs a batching API for resolving
            //   many addresses to source locations).
            .windows => fatal("--fuzz not yet implemented for {t}", .{builtin.os.tag}),
            else => {},
        }
        if (@bitSizeOf(usize) != 64) {
            // Current implementation depends on posix.mmap()'s second parameter, `length: usize`,
            // being compatible with file system's u64 return value. This is not the case
            // on 32-bit platforms.
            // Affects or affected by issues #5185, #22523, and #22464.
            fatal("--fuzz not yet implemented on {d}-bit platforms", .{@bitSizeOf(usize)});
        }

        switch (mode) {
            .forever => break :blk,
            .limit => {},
        }

        assert(mode == .limit);
        var f = Fuzz.init(maker, step_stack.keys(), parent_prog_node, mode) catch |err|
            fatal("failed to start fuzzer: {t}", .{err});
        defer f.deinit();

        f.start();
        try f.waitAndPrintReport();
    }

    // Every test has a state
    assert(test_pass_count + test_skip_count + test_fail_count + test_crash_count + test_timeout_count == test_count);

    if (failure_count == 0) {
        std.Progress.setStatus(.success);
    } else {
        std.Progress.setStatus(.failure);
    }

    summary: {
        switch (maker.summary) {
            .all, .new, .line => {},
            .failures => if (failure_count == 0) break :summary,
            .none => break :summary,
        }

        const stderr = try io.lockStderr(&stdio_buffer_allocation, graph.stderr_mode);
        defer io.unlockStderr();
        const t = stderr.terminal();
        const w = &stderr.file_writer.interface;

        const total_count = success_count + failure_count + pending_count + skipped_count;
        t.setColor(.cyan) catch {};
        t.setColor(.bold) catch {};
        w.writeAll("Build Summary: ") catch {};
        t.setColor(.reset) catch {};
        w.print("{d}/{d} steps succeeded", .{ success_count, total_count }) catch {};
        {
            t.setColor(.dim) catch {};
            var first = true;
            if (skipped_count > 0) {
                w.print("{s}{d} skipped", .{ if (first) " (" else ", ", skipped_count }) catch {};
                first = false;
            }
            if (failure_count > 0) {
                w.print("{s}{d} failed", .{ if (first) " (" else ", ", failure_count }) catch {};
                first = false;
            }
            if (!first) w.writeByte(')') catch {};
            t.setColor(.reset) catch {};
        }

        if (test_count > 0) {
            w.print("; {d}/{d} tests passed", .{ test_pass_count, test_count }) catch {};
            t.setColor(.dim) catch {};
            var first = true;
            if (test_skip_count > 0) {
                w.print("{s}{d} skipped", .{ if (first) " (" else ", ", test_skip_count }) catch {};
                first = false;
            }
            if (test_fail_count > 0) {
                w.print("{s}{d} failed", .{ if (first) " (" else ", ", test_fail_count }) catch {};
                first = false;
            }
            if (test_crash_count > 0) {
                w.print("{s}{d} crashed", .{ if (first) " (" else ", ", test_crash_count }) catch {};
                first = false;
            }
            if (test_timeout_count > 0) {
                w.print("{s}{d} timed out", .{ if (first) " (" else ", ", test_timeout_count }) catch {};
                first = false;
            }
            if (!first) w.writeByte(')') catch {};
            t.setColor(.reset) catch {};
        }

        w.writeAll("\n") catch {};

        if (maker.summary == .line) break :summary;

        // Print a fancy tree with build results.
        var step_stack_copy = try step_stack.clone(gpa);
        defer step_stack_copy.deinit(gpa);

        var print_node: PrintNode = .{ .parent = null };
        if (step_names.len == 0) {
            print_node.last = true;
            printTreeStep(maker, c.default_step, t, &print_node, &step_stack_copy) catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => {},
            };
        } else if (override != .active) {
            const last_index = if (maker.summary == .all) top_level_steps.count() else blk: {
                var i: usize = step_names.len;
                while (i > 0) {
                    i -= 1;
                    const step_index = top_level_steps.get(step_names[i]).?;
                    const step = maker.stepByIndex(step_index);
                    const found = switch (maker.summary) {
                        .all, .line, .none => unreachable,
                        .failures => step.state != .success,
                        .new => !step.result_cached,
                    };
                    if (found) break :blk i;
                }
                break :blk top_level_steps.count();
            };
            for (step_names, 0..) |step_name, i| {
                const step_index = top_level_steps.get(step_name).?;
                print_node.last = i + 1 == last_index;
                printTreeStep(maker, step_index, t, &print_node, &step_stack_copy) catch |err| switch (err) {
                    error.Canceled => |e| return e,
                    else => {},
                };
            }
        }
        w.writeByte('\n') catch {};
    }

    if (maker.watch or maker.web_server != null) return;

    const code: u8 = code: {
        if (failure_count == 0) break :code 0; // success
        if (maker.error_style.verboseContext()) break :code 1; // failure; print build command
        break :code 2; // failure; do not print build command
    };
    if (code == 0) {
        removePoisonedConfiguration(io, maker.scanned_config);
        if (debugMakerLeaks()) return deinit(maker);
    }
    cleanup_task.await(io); // There is a defer above but an exit below.
    _ = io.lockStderr(&.{}, graph.stderr_mode) catch {};
    process.exit(code);
}

fn deinit(maker: *Maker) void {
    const gpa = maker.gpa;
    for (maker.steps) |*step| {
        step.clearResultStderr(gpa);
        step.clearFailedCommand(gpa);
        step.clearErrorBundle(gpa);
        step.inputs.deinit(gpa);
    }
}

fn stepReady(
    maker: *Maker,
    group: *Io.Group,
    step_index: Configuration.Step.Index,
    root_prog_node: std.Progress.Node,
) Io.Cancelable!void {
    const graph = maker.graph;
    const io = graph.io;
    const c = &maker.scanned_config.configuration;
    const max_rss = step_index.ptr(c).max_rss.toBytes();
    if (max_rss != 0) {
        try maker.max_rss_mutex.lock(io);
        defer maker.max_rss_mutex.unlock(io);
        if (maker.available_rss < max_rss) {
            // Running this step right now could possibly exceed the allotted RSS.
            maker.memory_blocked_steps.append(maker.gpa, step_index) catch
                @panic("TODO eliminate memory allocation here");
            return;
        }
        maker.available_rss -= max_rss;
    }
    group.async(io, makeStep, .{ maker, group, step_index, root_prog_node });
}

/// Runs the "make" function of the single step `s`, updates its state, and then spawns newly-ready
/// dependant steps in `group`. If `s` makes an RSS claim (i.e. `s.max_rss != 0`), the caller must
/// have already subtracted this value from `maker.available_rss`. This function will release the RSS
/// claim (i.e. add `s.max_rss` back into `maker.available_rss`) and queue any viable memory-blocked
/// steps after "make" completes for `s`.
fn makeStep(
    maker: *Maker,
    group: *Io.Group,
    step_index: Configuration.Step.Index,
    root_prog_node: std.Progress.Node,
) Io.Cancelable!void {
    const graph = maker.graph;
    const io = graph.io;
    const gpa = maker.gpa;
    const c = &maker.scanned_config.configuration;
    const conf_step = step_index.ptr(c);
    const step_name = conf_step.name.slice(c);
    const deps = conf_step.deps.slice(c);
    const make_step = maker.stepByIndex(step_index);

    {
        const step_prog_node = root_prog_node.start(step_name, 0);
        defer step_prog_node.end();

        if (maker.web_server) |*ws| ws.updateStepStatus(step_index, .wip);

        const new_state: Step.State = for (deps) |dep_index| {
            const dep_make_step = maker.stepByIndex(dep_index);
            switch (@atomicLoad(Step.State, &dep_make_step.state, .monotonic)) {
                .precheck_unstarted => unreachable,
                .precheck_started => unreachable,
                .precheck_done => unreachable,

                .failure,
                .dependency_failure,
                .skipped_oom,
                => break .dependency_failure,

                .success, .skipped => {},
            }
        } else if (Step.make(step_index, maker, step_prog_node)) state: {
            break :state .success;
        } else |err| switch (err) {
            error.MakeFailed => .failure,
            error.MakeSkipped => .skipped,
            error.Canceled => |e| return e,
        };

        @atomicStore(Step.State, &make_step.state, new_state, .monotonic);

        switch (new_state) {
            .precheck_unstarted => unreachable,
            .precheck_started => unreachable,
            .precheck_done => unreachable,

            .failure,
            .dependency_failure,
            .skipped_oom,
            => {
                if (maker.web_server) |*ws| ws.updateStepStatus(step_index, .failure);
                std.Progress.setStatus(.failure_working);
            },

            .success,
            .skipped,
            => {
                if (maker.web_server) |*ws| ws.updateStepStatus(step_index, .success);
            },
        }
    }

    // No matter the result, we want to display error/warning messages.
    if (make_step.result_error_bundle.errorMessageCount() > 0 or
        make_step.result_error_msgs.items.len > 0 or
        make_step.result_stderr.len > 0)
    {
        const stderr = try io.lockStderr(&stdio_buffer_allocation, graph.stderr_mode);
        defer io.unlockStderr();
        printErrorMessages(maker, step_index, .{}, stderr.terminal(), maker.error_style, maker.multiline_errors) catch |err| switch (err) {
            error.Canceled => |e| return e,
            error.WriteFailed => switch (stderr.file_writer.err.?) {
                error.Canceled => |e| return e,
                else => {},
            },
            else => {},
        };
    }

    const max_rss = conf_step.max_rss.toBytes();
    if (max_rss != 0) {
        var dispatch_set: std.ArrayList(Configuration.Step.Index) = .empty;
        defer dispatch_set.deinit(gpa);

        // Release our RSS claim and kick off some blocked steps if possible. We use `dispatch_set`
        // as a staging buffer to avoid recursing into `makeStep` while `maker.max_rss_mutex` is held.
        {
            try maker.max_rss_mutex.lock(io);
            defer maker.max_rss_mutex.unlock(io);
            maker.available_rss += max_rss;
            dispatch_set.ensureUnusedCapacity(gpa, maker.memory_blocked_steps.items.len) catch
                @panic("TODO eliminate memory allocation here");
            while (maker.memory_blocked_steps.getLast()) |candidate_index| {
                const candidate_max_rss = candidate_index.ptr(c).max_rss.toBytes();
                if (maker.available_rss < candidate_max_rss) break;
                assert(maker.memory_blocked_steps.pop() == candidate_index);
                dispatch_set.appendAssumeCapacity(candidate_index);
            }
        }
        for (dispatch_set.items) |candidate| {
            group.async(io, makeStep, .{ maker, group, candidate, root_prog_node });
        }
    }

    for (make_step.dependants.items) |dependant_index| {
        const dependant = maker.stepByIndex(dependant_index);
        // `.acq_rel` synchronizes with itself to ensure all dependencies' final states are visible when this hits 0.
        if (@atomicRmw(u32, &dependant.pending_deps, .Sub, 1, .acq_rel) == 1) {
            try stepReady(maker, group, dependant_index, root_prog_node);
        }
    }
}

fn printTreeStep(
    maker: *Maker,
    step_index: Configuration.Step.Index,
    stderr: Io.Terminal,
    parent_node: *PrintNode,
    step_stack: *std.array_hash_map.Auto(Configuration.Step.Index, void),
) !void {
    const writer = stderr.writer;
    const first = step_stack.swapRemove(step_index);
    const summary = maker.summary;
    const c = &maker.scanned_config.configuration;
    const conf_step = step_index.ptr(c);
    const make_step = maker.stepByIndex(step_index);
    const skip = switch (summary) {
        .none, .line => unreachable,
        .all => false,
        .new => make_step.result_cached,
        .failures => make_step.state == .success,
    };
    if (skip) return;
    try printPrefix(parent_node, stderr);

    if (parent_node.parent != null) {
        if (parent_node.last) {
            try printChildNodePrefix(stderr);
        } else {
            try writer.writeAll(switch (stderr.mode) {
                .escape_codes => "\x1B\x28\x30\x74\x71\x1B\x28\x42 ", // ├─
                else => "+- ",
            });
        }
    }

    if (!first) try stderr.setColor(.dim);

    // dep_prefix omitted here because it is redundant with the tree.
    try writer.writeAll(conf_step.name.slice(c));

    const deps = conf_step.deps.slice(c);

    if (first) {
        try printStepStatus(maker, step_index, stderr);

        const last_index = if (summary == .all) deps.len -| 1 else blk: {
            var i: usize = deps.len;
            while (i > 0) {
                i -= 1;

                const dep_index = deps[i];
                const dep = maker.stepByIndex(dep_index);
                const found = switch (summary) {
                    .all, .line, .none => unreachable,
                    .failures => dep.state != .success,
                    .new => !dep.result_cached,
                };
                if (found) break :blk i;
            }
            break :blk deps.len -| 1;
        };
        for (deps, 0..) |dep, i| {
            var print_node: PrintNode = .{
                .parent = parent_node,
                .last = i == last_index,
            };
            try printTreeStep(maker, dep, stderr, &print_node, step_stack);
        }
    } else {
        if (deps.len == 0) {
            try writer.writeAll(" (reused)\n");
        } else {
            try writer.print(" (+{d} more reused dependencies)\n", .{deps.len});
        }
        try stderr.setColor(.reset);
    }
}

fn printStepStatus(maker: *Maker, step_index: Configuration.Step.Index, stderr: Io.Terminal) !void {
    const s = maker.stepByIndex(step_index);
    const writer = stderr.writer;
    switch (s.state) {
        .precheck_unstarted => unreachable,
        .precheck_started => unreachable,
        .precheck_done => unreachable,

        .dependency_failure => {
            try stderr.setColor(.dim);
            try writer.writeAll(" transitive failure\n");
            try stderr.setColor(.reset);
        },

        .success => {
            try stderr.setColor(.green);
            if (s.result_cached) {
                try writer.writeAll(" cached");
            } else if (s.test_results.test_count > 0) {
                const pass_count = s.test_results.passCount();
                assert(s.test_results.test_count == pass_count + s.test_results.skip_count);
                try writer.print(" {d} pass", .{pass_count});
                if (s.test_results.skip_count > 0) {
                    try stderr.setColor(.reset);
                    try writer.writeAll(", ");
                    try stderr.setColor(.yellow);
                    try writer.print("{d} skip", .{s.test_results.skip_count});
                }
                try stderr.setColor(.reset);
                try writer.print(" ({d} total)", .{s.test_results.test_count});
            } else {
                try writer.writeAll(" success");
            }
            try stderr.setColor(.reset);
            if (s.result_duration_ns) |ns| {
                try stderr.setColor(.dim);
                if (ns >= std.time.ns_per_min) {
                    try writer.print(" {d}m", .{ns / std.time.ns_per_min});
                } else if (ns >= std.time.ns_per_s) {
                    try writer.print(" {d}s", .{ns / std.time.ns_per_s});
                } else if (ns >= std.time.ns_per_ms) {
                    try writer.print(" {d}ms", .{ns / std.time.ns_per_ms});
                } else if (ns >= std.time.ns_per_us) {
                    try writer.print(" {d}us", .{ns / std.time.ns_per_us});
                } else {
                    try writer.print(" {d}ns", .{ns});
                }
                try stderr.setColor(.reset);
            }
            if (s.result_peak_rss != 0) {
                const rss = s.result_peak_rss;
                try stderr.setColor(.dim);
                if (rss >= 1000_000_000) {
                    try writer.print(" MaxRSS:{d}G", .{rss / 1000_000_000});
                } else if (rss >= 1000_000) {
                    try writer.print(" MaxRSS:{d}M", .{rss / 1000_000});
                } else if (rss >= 1000) {
                    try writer.print(" MaxRSS:{d}K", .{rss / 1000});
                } else {
                    try writer.print(" MaxRSS:{d}B", .{rss});
                }
                try stderr.setColor(.reset);
            }
            try writer.writeAll("\n");
        },
        .skipped => {
            try stderr.setColor(.yellow);
            try writer.writeAll(" skipped\n");
            try stderr.setColor(.reset);
        },
        .skipped_oom => {
            const c = &maker.scanned_config.configuration;
            const max_rss = step_index.ptr(c).max_rss.toBytes();
            try stderr.setColor(.yellow);
            try writer.writeAll(" skipped (not enough memory)");
            try stderr.setColor(.dim);
            try writer.print(" upper bound of {d} exceeded runner limit ({d})\n", .{
                max_rss, maker.available_rss,
            });
            try stderr.setColor(.reset);
        },
        .failure => {
            try printStepFailure(maker, step_index, stderr, false);
            try stderr.setColor(.reset);
        },
    }
}

fn printStepFailure(
    maker: *Maker,
    step_index: Configuration.Step.Index,
    stderr: Io.Terminal,
    dim: bool,
) !void {
    const w = stderr.writer;
    const s = maker.stepByIndex(step_index);
    if (s.result_error_bundle.errorMessageCount() > 0) {
        try stderr.setColor(.red);
        try w.print(" {d} errors\n", .{
            s.result_error_bundle.errorMessageCount(),
        });
    } else if (!s.test_results.isSuccess()) {
        // These first values include all of the test "statuses". Every test is either passsed,
        // skipped, failed, crashed, or timed out.
        try stderr.setColor(.green);
        try w.print(" {d} pass", .{s.test_results.passCount()});
        try stderr.setColor(.reset);
        if (dim) try stderr.setColor(.dim);
        if (s.test_results.skip_count > 0) {
            try w.writeAll(", ");
            try stderr.setColor(.yellow);
            try w.print("{d} skip", .{s.test_results.skip_count});
            try stderr.setColor(.reset);
            if (dim) try stderr.setColor(.dim);
        }
        if (s.test_results.fail_count > 0) {
            try w.writeAll(", ");
            try stderr.setColor(.red);
            try w.print("{d} fail", .{s.test_results.fail_count});
            try stderr.setColor(.reset);
            if (dim) try stderr.setColor(.dim);
        }
        if (s.test_results.crash_count > 0) {
            try w.writeAll(", ");
            try stderr.setColor(.red);
            try w.print("{d} crash", .{s.test_results.crash_count});
            try stderr.setColor(.reset);
            if (dim) try stderr.setColor(.dim);
        }
        if (s.test_results.timeout_count > 0) {
            try w.writeAll(", ");
            try stderr.setColor(.red);
            try w.print("{d} timeout", .{s.test_results.timeout_count});
            try stderr.setColor(.reset);
            if (dim) try stderr.setColor(.dim);
        }
        try w.print(" ({d} total)", .{s.test_results.test_count});

        // Memory leaks are intentionally written after the total, because is isn't a test *status*,
        // but just a flag that any tests -- even passed ones -- can have. We also use a different
        // separator, so it looks like:
        //   2 pass, 1 skip, 2 fail (5 total); 2 leaks
        if (s.test_results.leak_count > 0) {
            try w.writeAll("; ");
            try stderr.setColor(.red);
            try w.print("{d} leaks", .{s.test_results.leak_count});
            try stderr.setColor(.reset);
            if (dim) try stderr.setColor(.dim);
        }

        // It's usually not helpful to know how many error logs there were because they tend to
        // just come with other errors (e.g. crashes and leaks print stack traces, and clean
        // failures print error traces). So only mention them if they're the only thing causing
        // the failure.
        const show_err_logs: bool = show: {
            var alt_results = s.test_results;
            alt_results.log_err_count = 0;
            break :show alt_results.isSuccess();
        };
        if (show_err_logs) {
            try w.writeAll("; ");
            try stderr.setColor(.red);
            try w.print("{d} error logs", .{s.test_results.log_err_count});
            try stderr.setColor(.reset);
            if (dim) try stderr.setColor(.dim);
        }

        try w.writeAll("\n");
    } else if (s.result_error_msgs.items.len > 0) {
        try stderr.setColor(.red);
        try w.writeAll(" failure\n");
    } else {
        assert(s.result_stderr.len > 0);
        try stderr.setColor(.red);
        try w.writeAll(" w\n");
    }
}

fn printPrefix(node: *PrintNode, stderr: Io.Terminal) !void {
    const parent = node.parent orelse return;
    const writer = stderr.writer;
    if (parent.parent == null) return;
    try printPrefix(parent, stderr);
    if (parent.last) {
        try writer.writeAll("   ");
    } else {
        try writer.writeAll(switch (stderr.mode) {
            .escape_codes => "\x1B\x28\x30\x78\x1B\x28\x42  ", // │
            else => "|  ",
        });
    }
}

fn printChildNodePrefix(stderr: Io.Terminal) !void {
    try stderr.writer.writeAll(switch (stderr.mode) {
        .escape_codes => "\x1B\x28\x30\x6d\x71\x1B\x28\x42 ", // └─
        else => "+- ",
    });
}

/// Traverse the dependency graph depth-first and make it undirected by having
/// steps know their dependants (they only know dependencies at start).
/// Along the way, check that there is no dependency loop, and record the steps
/// in traversal order in `step_stack`.
/// Each step has its dependencies traversed in random order, this accomplishes
/// two things:
/// - `step_stack` will be in randomized-depth-first order, so the build runner
///   spawns initial steps in a random order
/// - each step's `dependants` list is also filled in a random order, so that
///   when it finishes executing in `makeStep`, it spawns next steps to run in
///   random order
fn constructGraphAndCheckForDependencyLoop(
    maker: *Maker,
    step_index: Configuration.Step.Index,
    step_stack: *std.array_hash_map.Auto(Configuration.Step.Index, void),
    rand: std.Random,
) error{ DependencyLoopDetected, OutOfMemory }!void {
    const c = &maker.scanned_config.configuration;
    const gpa = maker.gpa;
    const arena = maker.graph.arena;
    const make_step = maker.stepByIndex(step_index);
    switch (make_step.state) {
        .precheck_started => {
            log.err("dependency loop detected: {s}", .{step_index.ptr(c).name.slice(c)});
            return error.DependencyLoopDetected;
        },
        .precheck_unstarted => {
            make_step.state = .precheck_started;

            const step = step_index.ptr(c);
            const dependencies = step.deps.slice(c);
            try step_stack.ensureUnusedCapacity(gpa, dependencies.len);

            // We dupe to avoid shuffling the steps in the summary, it depends
            // on dependencies' order.
            const deps = try gpa.dupe(Configuration.Step.Index, dependencies);
            defer gpa.free(deps);

            rand.shuffle(Configuration.Step.Index, deps);

            for (deps) |dep| {
                const dep_step = maker.stepByIndex(dep);
                try step_stack.put(gpa, dep, {});
                try dep_step.dependants.append(arena, step_index);
                constructGraphAndCheckForDependencyLoop(maker, dep, step_stack, rand) catch |err| switch (err) {
                    error.DependencyLoopDetected => {
                        log.info("needed by: {s}", .{step_index.ptr(c).name.slice(c)});
                        return err;
                    },
                    else => return err,
                };
            }

            make_step.state = .precheck_done;
            make_step.pending_deps = @intCast(dependencies.len);
        },
        .precheck_done => {},

        // These don't happen until we actually run the step graph.
        .dependency_failure => unreachable,
        .success => unreachable,
        .failure => unreachable,
        .skipped => unreachable,
        .skipped_oom => unreachable,
    }
}

/// When file watching, prepares the step for being re-evaluated. Returns
/// `true` if the step was newly invalidated, `false` if it was already
/// invalidated.
pub fn invalidateResult(maker: *Maker, step: *Step) bool {
    if (step.state == .precheck_done) return false;
    assert(step.pending_deps == 0);
    step.state = .precheck_done;
    step.reset(maker);
    for (step.dependants.items) |dependant_index| {
        const dependant = maker.stepByIndex(dependant_index);
        _ = invalidateResult(maker, dependant);
        dependant.pending_deps += 1;
    }
    return true;
}

pub fn printErrorMessages(
    maker: *Maker,
    failing_step_index: Configuration.Step.Index,
    options: std.zig.ErrorBundle.RenderOptions,
    stderr: Io.Terminal,
    error_style: ErrorStyle,
    multiline_errors: MultilineErrors,
) !void {
    const c = &maker.scanned_config.configuration;
    const gpa = maker.gpa;
    const writer = stderr.writer;
    if (error_style.verboseContext()) {
        // Provide context for where these error messages are coming from by
        // printing the corresponding Step subtree.
        var step_stack: std.ArrayList(Configuration.Step.Index) = .empty;
        defer step_stack.deinit(gpa);
        try step_stack.append(gpa, failing_step_index);
        while (true) {
            const last_step = maker.stepByIndex(step_stack.items[step_stack.items.len - 1]);
            if (last_step.dependants.items.len == 0) break;
            try step_stack.append(gpa, last_step.dependants.items[0]);
        }

        // Now, `step_stack` has the subtree that we want to print, in reverse order.
        try stderr.setColor(.dim);
        var indent: usize = 0;
        while (step_stack.pop()) |step_index| : (indent += 1) {
            if (indent > 0) {
                try writer.splatByteAll(' ', (indent - 1) * 3);
                try printChildNodePrefix(stderr);
            }

            try writer.writeAll(step_index.ptr(c).name.slice(c));

            if (step_index == failing_step_index) {
                try printStepFailure(maker, step_index, stderr, true);
            } else {
                try writer.writeAll("\n");
            }
        }
        try stderr.setColor(.reset);
    } else {
        // Just print the failing step itself.
        try stderr.setColor(.dim);
        try writer.writeAll(failing_step_index.ptr(c).name.slice(c));
        try printStepFailure(maker, failing_step_index, stderr, true);
        try stderr.setColor(.reset);
    }

    const failing_step = maker.stepByIndex(failing_step_index);

    if (failing_step.result_stderr.len > 0) {
        try writer.writeAll(failing_step.result_stderr);
        if (!mem.endsWith(u8, failing_step.result_stderr, "\n")) {
            try writer.writeAll("\n");
        }
    }

    try failing_step.result_error_bundle.renderToTerminal(options, stderr);

    for (failing_step.result_error_msgs.items) |msg| {
        try stderr.setColor(.red);
        try writer.writeAll("error:");
        try stderr.setColor(.reset);
        if (std.mem.indexOfScalar(u8, msg, '\n') == null) {
            try writer.print(" {s}\n", .{msg});
        } else switch (multiline_errors) {
            .indent => {
                var it = std.mem.splitScalar(u8, msg, '\n');
                try writer.print(" {s}\n", .{it.first()});
                while (it.next()) |line| {
                    try writer.print("       {s}\n", .{line});
                }
            },
            .newline => try writer.print("\n{s}\n", .{msg}),
            .none => try writer.print(" {s}\n", .{msg}),
        }
    }

    if (error_style.verboseContext()) {
        if (failing_step.result_failed_command) |cmd_str| {
            try stderr.setColor(.red);
            try writer.writeAll("failed command: ");
            try stderr.setColor(.reset);
            try writer.writeAll(cmd_str);
            try writer.writeByte('\n');
        }
    }

    if (failing_step.result_oom) {
        try stderr.setColor(.red);
        try writer.writeAll("error information missing due to allocation failure");
        try stderr.setColor(.reset);
        try writer.writeByte('\n');
    }

    try writer.writeByte('\n');
}

fn nextArg(args: []const [:0]const u8, idx: *usize) ?[:0]const u8 {
    if (idx.* >= args.len) return null;
    defer idx.* += 1;
    return args[idx.*];
}

fn nextArgOrFatal(args: []const [:0]const u8, idx: *usize) [:0]const u8 {
    return nextArg(args, idx) orelse {
        fatalWithHint("expected argument after {q}", .{args[idx.* - 1]});
    };
}

fn expectArgOrFatal(args: []const [:0]const u8, index_ptr: *usize, first: []const u8) []const u8 {
    const next_arg = nextArg(args, index_ptr) orelse fatal("missing {q} argument", .{first});
    if (!mem.eql(u8, first, next_arg)) fatal("expected {q} instead of {q}", .{ first, next_arg });
    const arg = nextArg(args, index_ptr) orelse fatal("expected argument after {q}", .{first});
    return arg;
}

fn argsRest(args: []const [:0]const u8, idx: usize) ?[]const [:0]const u8 {
    if (idx >= args.len) return null;
    return args[idx..];
}

fn fatalWithHint(comptime f: []const u8, args: anytype) noreturn {
    log.info("to access the help menu: zig build -h", .{});
    fatal(f, args);
}

fn cleanTmpFiles(maker: *Maker, steps: []const Configuration.Step.Index) void {
    const graph = maker.graph;
    const io = graph.io;
    const conf = &maker.scanned_config.configuration;

    for (steps) |step_index| {
        const conf_step = step_index.ptr(conf);
        const wf = conf_step.extended.cast(conf, Configuration.Step.WriteFile) orelse continue;
        if (wf.flags.mode != .tmp) continue;
        const step = maker.stepByIndex(step_index);
        if (step.state != .success) continue;
        const tmp_path = generatedPath(maker, wf.generated_directory).*;
        tmp_path.root_dir.handle.deleteTree(io, tmp_path.subPathOrDot()) catch |err|
            log.warn("failed to delete temporary path {f}: {t}", .{ tmp_path, err });
    }
}

fn initStdoutWriter(io: Io) *Writer {
    stdout_writer_allocation = Io.File.stdout().writerStreaming(io, &stdio_buffer_allocation);
    return &stdout_writer_allocation.interface;
}

/// `asking_step` is only used for debugging purposes; it's the step being run
/// that is asking for the path.
pub fn resolveLazyPath(
    maker: *const Maker,
    arena: Allocator,
    lazy_path: Configuration.LazyPath,
    asking_step_index: Configuration.Step.Index,
) error{ OutOfMemory, MakeFailed }!Path {
    const c = &maker.scanned_config.configuration;
    return switch (lazy_path) {
        .source_path => |sp| try packagePath(maker, arena, sp.owner, sp.sub_path.slice(c)),
        .relative => |relative| relativePath(maker, arena, relative),
        .generated => |gen| {
            const base = generatedPath(maker, gen.index).*;
            var file_path = base;
            for (0..gen.flags.up) |_| {
                file_path.sub_path = Dir.path.dirname(file_path.sub_path) orelse {
                    const s = stepByIndex(maker, asking_step_index);
                    return s.fail(maker, "invalid LazyPath traversal: up {d} times from {f}", .{
                        gen.flags.up, base,
                    });
                };
            }
            return file_path.join(arena, gen.sub_path.slice(c));
        },
    };
}

pub fn resolveLazyPathIndex(
    maker: *const Maker,
    arena: Allocator,
    lazy_path_index: Configuration.LazyPath.Index,
    asking_step_index: Configuration.Step.Index,
) error{ OutOfMemory, MakeFailed }!Path {
    const c = &maker.scanned_config.configuration;
    return resolveLazyPath(maker, arena, lazy_path_index.get(c), asking_step_index);
}

/// `resolveLazyPath` is preferred, but this can be necessary when passing Path
/// objects to child processes.
pub fn resolveLazyPathAbs(
    maker: *const Maker,
    arena: Allocator,
    lazy_path: Configuration.LazyPath,
    asking_step_index: Configuration.Step.Index,
) error{ OutOfMemory, MakeFailed }![]const u8 {
    const p = try resolveLazyPath(maker, arena, lazy_path, asking_step_index);
    const root_dir_path = p.root_dir.path orelse return p.subPathOrDot();
    if (p.sub_path.len == 0) return root_dir_path;
    return Dir.path.join(arena, &.{ root_dir_path, p.sub_path });
}

/// `resolveLazyPath` is preferred, but this can be necessary when passing Path
/// objects to child processes.
pub fn resolveLazyPathIndexAbs(
    maker: *const Maker,
    arena: Allocator,
    lazy_path_index: Configuration.LazyPath.Index,
    asking_step_index: Configuration.Step.Index,
) error{ OutOfMemory, MakeFailed }![]const u8 {
    const c = &maker.scanned_config.configuration;
    return resolveLazyPathAbs(maker, arena, lazy_path_index.get(c), asking_step_index);
}

pub fn generatedPath(maker: *const Maker, index: Configuration.GeneratedFileIndex) *Path {
    return &maker.generated_files[@intFromEnum(index)];
}

pub fn packagePath(
    maker: *const Maker,
    arena: Allocator,
    package_index: Configuration.Package.Index,
    sub_path: []const u8,
) Allocator.Error!Path {
    const c = &maker.scanned_config.configuration;
    const graph = maker.graph;
    const package = package_index.get(c) orelse return .{
        .root_dir = graph.build_root_directory,
        .sub_path = sub_path,
    };
    // Currently, neither configurer nor Maker is aware of the standard zig
    // package path, and the root path is stored as a bare string rather than
    // relative to a known base directory. Without changing that, we must
    // construct a cwd relative path here.
    return .{
        .root_dir = .cwd(),
        .sub_path = try Dir.path.join(arena, &.{ package.root_path.slice(c), sub_path }),
    };
}

pub fn relativePath(maker: *const Maker, arena: Allocator, relative: Configuration.LazyPath.Relative) Allocator.Error!Path {
    const graph = maker.graph;
    const c = &maker.scanned_config.configuration;
    const sub_path = relative.sub_path.slice(c);
    return switch (relative.flags.base) {
        .cwd => .{
            .root_dir = .cwd(),
            .sub_path = sub_path,
        },
        .local_cache => .{
            .root_dir = graph.local_cache_root,
            .sub_path = sub_path,
        },
        .global_cache => .{
            .root_dir = graph.global_cache_root,
            .sub_path = sub_path,
        },
        .build_root => .{
            .root_dir = graph.build_root_directory,
            .sub_path = sub_path,
        },
        .zig_exe => .{
            .root_dir = .cwd(),
            .sub_path = if (sub_path.len == 0)
                graph.zig_exe
            else
                try Io.Dir.path.join(arena, &.{ graph.zig_exe, sub_path }),
        },
        .zig_lib => .{
            .root_dir = graph.zig_lib_directory,
            .sub_path = sub_path,
        },
        .install_prefix => try maker.install_paths.prefix.join(arena, sub_path),
        .install_lib => try maker.install_paths.lib.join(arena, sub_path),
        .install_bin => try maker.install_paths.bin.join(arena, sub_path),
        .install_include => try maker.install_paths.include.join(arena, sub_path),
    };
}

pub fn resolveInstallDir(
    maker: *Maker,
    arena: Allocator,
    dest_dir: Configuration.InstallDestDir,
) Allocator.Error!Path {
    const c = &maker.scanned_config.configuration;
    return switch (dest_dir.unpack().?) {
        .prefix => maker.install_paths.prefix,
        .lib => maker.install_paths.lib,
        .bin => maker.install_paths.bin,
        .header => maker.install_paths.include,
        .sub_path => |s| try maker.install_paths.prefix.join(arena, s.slice(c)),
    };
}

pub fn installLazyPathSub(
    maker: *Maker,
    arena: Allocator,
    source: Configuration.LazyPath.Index,
    dest_dir: Configuration.InstallDestDir,
    sub_path: []const u8,
    asking_step_index: Configuration.Step.Index,
) !Dir.PrevStatus {
    const src_path = try resolveLazyPathIndex(maker, arena, source, asking_step_index);
    const dest_dir_path = try resolveInstallDir(maker, arena, dest_dir);
    const dest_path = try dest_dir_path.join(arena, sub_path);
    return installPath(maker, arena, src_path, dest_path, asking_step_index);
}

pub fn installLazyPath(
    maker: *Maker,
    arena: Allocator,
    source: Configuration.LazyPath.Index,
    dest_dir: Configuration.InstallDestDir,
    asking_step_index: Configuration.Step.Index,
) !Dir.PrevStatus {
    const src_path = try resolveLazyPathIndex(maker, arena, source, asking_step_index);
    const dest_dir_path = try resolveInstallDir(maker, arena, dest_dir);
    const dest_path = try dest_dir_path.join(arena, src_path.basename());
    return installPath(maker, arena, src_path, dest_path, asking_step_index);
}

pub fn installGenerated(
    maker: *Maker,
    arena: Allocator,
    source: Configuration.GeneratedFileIndex,
    dest_dir: Configuration.InstallDestDir,
    asking_step_index: Configuration.Step.Index,
) !Dir.PrevStatus {
    const src_path = generatedPath(maker, source).*;
    const dest_dir_path = try resolveInstallDir(maker, arena, dest_dir);
    const dest_path = try dest_dir_path.join(arena, src_path.basename());
    return installPath(maker, arena, src_path, dest_path, asking_step_index);
}

pub fn truncatePath(
    maker: *Maker,
    arena: Allocator,
    dest_path: Path,
    asking_step_index: Configuration.Step.Index,
) Step.ExtendedMakeError!void {
    const graph = maker.graph;
    const io = graph.io;
    if (graph.verbose) try graph.handleVerbose(null, null, &.{
        "truncate", try dest_path.toString(arena),
    });
    const err = e: {
        var file = f: {
            break :f dest_path.root_dir.handle.createFile(io, dest_path.sub_path, .{}) catch |err| switch (err) {
                error.FileNotFound => {
                    const parent_path = dest_path.dirname() orelse break :e err;
                    parent_path.root_dir.handle.createDirPath(io, parent_path.sub_path) catch |in| switch (in) {
                        error.Canceled => |e| return e,
                        else => |e| {
                            const s = stepByIndex(maker, asking_step_index);
                            return s.fail(maker, "failed creating directory {f}: {t}", .{ parent_path, e });
                        },
                    };
                    break :f dest_path.root_dir.handle.createFile(io, dest_path.sub_path, .{}) catch |in| break :e in;
                },
                error.Canceled => |e| return e,
                else => |e| break :e e,
            };
        };
        file.close(io);
        return;
    };
    const s = stepByIndex(maker, asking_step_index);
    return s.fail(maker, "failed truncating file {f}: {t}", .{ dest_path, err });
}

pub fn installPath(
    maker: *Maker,
    arena: Allocator,
    src_path: Path,
    dest_path: Path,
    asking_step_index: Configuration.Step.Index,
) Step.ExtendedMakeError!Dir.PrevStatus {
    const graph = maker.graph;
    const io = graph.io;
    if (graph.verbose) try graph.handleVerbose(null, null, &.{
        "install", "-C", try src_path.toString(arena), try dest_path.toString(arena),
    });
    return Dir.updateFile(
        src_path.root_dir.handle,
        io,
        src_path.sub_path,
        dest_path.root_dir.handle,
        dest_path.sub_path,
        .{},
    ) catch |err| {
        const s = stepByIndex(maker, asking_step_index);
        return s.fail(maker, "failed updating file from {f} to {f}: {t}", .{ src_path, dest_path, err });
    };
}

/// Wrapper around `Dir.createDirPathStatus` that handles verbose and error output.
pub fn installDir(
    maker: *Maker,
    arena: Allocator,
    dest_path: Path,
    asking_step_index: Configuration.Step.Index,
) Step.ExtendedMakeError!Dir.CreatePathStatus {
    const graph = maker.graph;
    const io = graph.io;
    if (graph.verbose) try graph.handleVerbose(null, null, &.{
        "install", "-d", try dest_path.toString(arena),
    });
    return dest_path.root_dir.handle.createDirPathStatus(io, dest_path.sub_path, .default_dir) catch |err| {
        const s = stepByIndex(maker, asking_step_index);
        return s.fail(maker, "failed creating dir {f}: {t}", .{ dest_path, err });
    };
}

pub fn installSymLinks(
    maker: *Maker,
    arena: Allocator,
    output_path: Path,
    compile_step_index: Configuration.Step.Index,
    asking_step_index: Configuration.Step.Index,
) !void {
    const c = &maker.scanned_config.configuration;
    const conf_step = compile_step_index.ptr(c);
    const conf_comp = conf_step.extended.get(c.extra).compile;
    const root_module = conf_comp.root_module.get(c);
    const target = root_module.resolved_target.get(c).?.result.get(c);
    const os_tag = target.flags.os_tag.unwrap().?;

    assert(conf_comp.flags3.kind == .lib);
    assert(conf_comp.flags2.linkage == .dynamic);
    assert(os_tag != .windows);

    const version = std.SemanticVersion.parse(conf_comp.version.value.?.slice(c)) catch unreachable;
    const name = conf_comp.root_name.slice(c);

    const filename_major_only, const filename_name_only = if (os_tag.isDarwin()) .{
        try std.fmt.allocPrint(arena, "lib{s}.{d}.dylib", .{ name, version.major }),
        try std.fmt.allocPrint(arena, "lib{s}.dylib", .{name}),
    } else .{
        try std.fmt.allocPrint(arena, "lib{s}.so.{d}", .{ name, version.major }),
        try std.fmt.allocPrint(arena, "lib{s}.so", .{name}),
    };

    return installSymLinksInner(maker, arena, output_path, asking_step_index, filename_major_only, filename_name_only);
}

fn installSymLinksInner(
    maker: *Maker,
    arena: Allocator,
    output_path: Path,
    asking_step_index: Configuration.Step.Index,
    filename_major_only: []const u8,
    filename_name_only: []const u8,
) !void {
    const io = maker.graph.io;
    const step = stepByIndex(maker, asking_step_index);
    const out_basename = Io.Dir.path.basename(output_path.sub_path);

    const out_dir = output_path.dirname().?;
    const major_only_path = try out_dir.join(arena, filename_major_only);
    const name_only_path = try out_dir.join(arena, filename_name_only);

    // libfoo.so.1 to libfoo.so.1.2.3
    major_only_path.root_dir.handle.symLinkAtomic(io, out_basename, major_only_path.sub_path, .{}) catch |err|
        return step.fail(maker, "failed symlinking {f} to {s}: {t}", .{ output_path, out_basename, err });

    // libfoo.so to libfoo.so.1
    name_only_path.root_dir.handle.symLinkAtomic(io, filename_major_only, name_only_path.sub_path, .{}) catch |err|
        return step.fail(maker, "failed symlinking {f} to {s}: {t}", .{ name_only_path, filename_major_only, err });
}

fn cleanExit(io: Io, scanned_config: *const ScannedConfig) void {
    removePoisonedConfiguration(io, scanned_config);
    return process.cleanExit(io);
}

fn removePoisonedConfiguration(io: Io, scanned_config: *const ScannedConfig) void {
    if (scanned_config.configuration.poisoned and override != .active) {
        // This configuration file was good for only 1 invocation of the maker
        // process. Delete it to save space on disk.
        Io.Dir.cwd().deleteFile(io, scanned_config.path) catch |err|
            log.warn("failed deleting poisoned configuration file {s}: {t}", .{ scanned_config.path, err });
    }
}

inline fn debugMakerLeaks() bool {
    if (!is_debug_mode) return false;
    return debug_maker_leaks;
}
