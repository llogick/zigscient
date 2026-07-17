const Maker = @This();

const builtin = @import("builtin");
const native_os = builtin.os.tag;

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
const EnvVar = std.zig.EnvVar;
const default_local_zig_cache_basename = std.zig.default_local_zig_cache_basename;
const stringToEnum = std.meta.stringToEnum;

const Fuzz = @import("Maker/Fuzz.zig");
const Graph = @import("Maker/Graph.zig");
const Step = @import("Maker/Step.zig");
const Watch = @import("Maker/Watch.zig");
const WebServer = @import("Maker/WebServer.zig");
const ScannedConfig = @import("Maker/ScannedConfig.zig");
const PkgConfig = @import("Maker/PkgConfig.zig");
const Fetch = @import("Maker/Fetch.zig");
const Package = @import("Maker/Package.zig");

pub const std_options: std.Options = .{
    .side_channels_mitigations = .none,
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
web_server: ?*AvoidableWebServer,
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

const AvoidableWebServer = if (builtin.single_threaded) void else WebServer;

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
const PrintConfiguration = enum { none, zon, path };

/// Used to build the -M flags to pass to build-exe.
pub const CliModule = struct {
    name: []const u8,
    root_path: []const u8,
    deps: Deps = .empty,

    const Deps = std.array_hash_map.String(*CliModule);

    fn lower(cm: *const CliModule, arena: Allocator, gpa: Allocator, argv: *std.ArrayList([]const u8)) !void {
        try argv.ensureUnusedCapacity(gpa, 2 * cm.deps.count() + 1);
        for (cm.deps.keys(), cm.deps.values()) |name, dep| {
            argv.appendAssumeCapacity("--dep");
            if (mem.eql(u8, name, dep.name)) {
                argv.appendAssumeCapacity(dep.name);
            } else {
                argv.appendAssumeCapacity(try arena.print("{s}={s}", .{ name, dep.name }));
            }
        }
        argv.appendAssumeCapacity(try arena.print("-M{s}={s}", .{ cm.name, cm.root_path }));
    }
};

const Override = enum { inactive, active, print_configuration, watch };
var override: Override = .inactive;
pub const step_index_arg_prefix = "#$!:";

pub fn main(init: process.Init.Minimal) !void {
    // The build runner is long-lived in the following use cases:
    // * `--watch` mode
    // * `--webui` mode
    // * `--fuzz` mode
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

    var arena_instance: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_instance.deinit();
    defer if (debugMakerLeaks()) log.debug("used {Bi} of arena", .{arena_instance.queryCapacity()});
    const arena = arena_instance.allocator();

    const args = try init.args.toSlice(arena);
    var arg_i: usize = 1;
    if (args.len > 1 and std.mem.eql(u8, args[1], "maker")) arg_i += 1; // Handle Zigscient spawning itself with the `maker` subcmd
    const cmd_name = nextArgOrFatal(args, &arg_i);
    const zig_lib_arg = prefixedArgOrFatal(args, &arg_i, "--zig-lib=");
    const zig_exe_arg = prefixedArgOrFatal(args, &arg_i, "--zig=");
    const global_cache_arg = prefixedArgOrFatal(args, &arg_i, "--global-cache=");
    const seed_arg = prefixedArgOrFatal(args, &arg_i, "--seed=");

    const cwd: Dir = .cwd();

    const zig_lib_directory: Cache.Directory = if (std.mem.eql(u8, zig_lib_arg, ".")) .cwd() else .{
        .path = zig_lib_arg,
        .handle = try cwd.openDir(io, zig_lib_arg, .{}),
    };

    const global_cache_directory: Cache.Directory = if (std.mem.eql(u8, global_cache_arg, ".")) .cwd() else .{
        .path = global_cache_arg,
        .handle = try cwd.createDirPathOpen(io, global_cache_arg, .{}),
    };

    var graph: Graph = .{
        .io = io,
        .arena = arena,
        .cache = undefined,
        .zig_exe = zig_exe_arg,
        .environ_map = try init.environ.createMap(arena),
        .global_cache_root = global_cache_directory,
        .local_cache_root = undefined,
        .zig_lib_directory = zig_lib_directory,
        .build_root_directory = undefined,
        .random_seed = parseRandomSeed(seed_arg),
    };

    const cmd = stringToEnum(enum { libc, init, fetch, build }, cmd_name) orelse
        fatal("bad command name: {q}", .{cmd_name});
    switch (cmd) {
        else => fatal("Zigscient's Maker doesn't support: {q}", .{cmd_name}),
        // .libc => return cmdLibC(gpa, &graph, args[arg_i..]),
        // .init => return cmdInit(gpa, &graph, args[arg_i..]),
        // .fetch => return cmdFetch(gpa, &graph, args[arg_i..]),
        .build => {},
    }

    var step_names: std.ArrayList([]const u8) = .empty;
    var help_menu = false;
    var steps_menu = false;
    var print_configuration: PrintConfiguration = .none;
    var override_install_prefix: ?[]const u8 = null;
    var override_lib_dir: ?[]const u8 = null;
    var override_bin_dir: ?[]const u8 = null;
    var override_include_dir: ?[]const u8 = null;
    var override_local_cache_dir: ?[]const u8 = EnvVar.ZIG_LOCAL_CACHE_DIR.get(&graph.environ_map);
    var override_pkg_dir: ?[]const u8 = EnvVar.ZIG_LOCAL_PKG_DIR.get(&graph.environ_map);
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
    var build_file: ?[]const u8 = null;

    var configure_argv: std.ArrayList([]const u8) = .empty;
    var cached_passthru_configure: std.ArrayList(u32) = .empty;
    var forks: std.ArrayList(Fork) = .empty;
    var system_pkg_dir_path: ?[]const u8 = null;
    var fetch_only = false;
    var fetch_mode: Fetch.JobQueue.Mode = .needed;
    var debug_target: ?[]const u8 = null;
    var cache_poison: std.Build.Graph.CachePoison = .pure;

    if (EnvVar.ZIG_BUILD_ERROR_STYLE.get(&graph.environ_map)) |str| {
        if (stringToEnum(ErrorStyle, str)) |style| {
            error_style = style;
        }
    }

    if (EnvVar.ZIG_BUILD_MULTILINE_ERRORS.get(&graph.environ_map)) |str| {
        if (stringToEnum(MultilineErrors, str)) |style| {
            multiline_errors = style;
        }
    }

    try configure_argv.ensureUnusedCapacity(arena, 16);
    try cached_passthru_configure.ensureUnusedCapacity(arena, 16);

    _ = configure_argv.addOneAssumeCapacity(); // configurer executable
    configure_argv.addManyAsArrayAssumeCapacity(2).* = .{ "--zig", graph.zig_exe };
    configure_argv.addManyAsArrayAssumeCapacity(2).* = .{ "--build-root", undefined };
    const conf_argv_index_build_root = configure_argv.items.len - 1;

    while (nextArg(args, &arg_i)) |arg| {
        if (mem.startsWith(u8, arg, "-")) {
            try configure_argv.ensureUnusedCapacity(arena, 2);
            if (mem.startsWith(u8, arg, "-D") or
                mem.startsWith(u8, arg, "-fsys=") or
                mem.startsWith(u8, arg, "-fno-sys=") or
                mem.startsWith(u8, arg, "--release=") or
                mem.eql(u8, arg, "--release"))
            {
                try cached_passthru_configure.append(arena, @intCast(configure_argv.items.len));
                configure_argv.appendAssumeCapacity(arg);
            } else if (mem.eql(u8, arg, "--system")) {
                system_pkg_dir_path = nextArgOrFatal(args, &arg_i);

                try cached_passthru_configure.append(arena, @intCast(configure_argv.items.len));
                configure_argv.appendAssumeCapacity(arg); // Intentionally "--system" only; not the path.
            } else if (mem.cutPrefix(u8, arg, "--color=")) |rest| {
                color = stringToEnum(Color, rest) orelse
                    fatalWithHint("expected --color=[auto|on|off]; found {q}", .{arg});

                try cached_passthru_configure.append(arena, @intCast(configure_argv.items.len));
                configure_argv.appendAssumeCapacity(arg);
            } else if (mem.eql(u8, arg, "--color")) {
                const next_arg = nextArgOrFatal(args, &arg_i);
                color = stringToEnum(Color, next_arg) orelse
                    fatalWithHint("expected [auto|on|off] found {q}", .{next_arg});

                try cached_passthru_configure.append(arena, @intCast(configure_argv.items.len));
                configure_argv.appendAssumeCapacity(try arena.print("--color={t}", .{color}));
            } else if (mem.eql(u8, arg, "--cache-poison")) {
                cache_poison = .poisoned;
                configure_argv.appendAssumeCapacity("--cache-poison=poisoned");
            } else if (mem.cutPrefix(u8, arg, "--cache-poison=")) |rest| {
                // We have to report parse failure here otherwise we would
                // potentially get false positive cache hits for misspellings.
                cache_poison = stringToEnum(std.Build.Graph.CachePoison, rest) orelse
                    fatalWithHint("expected --cache-poison=[pure|poisoned|disallowed|ignored]; found: {s}", .{arg});
                if (cache_poison != .pure) configure_argv.appendAssumeCapacity(arg);
            } else if (mem.eql(u8, arg, "--verbose")) {
                // Intentionally is added both to make and configure but
                // does not go into the cache hash.
                configure_argv.appendAssumeCapacity(arg);
                graph.verbose = true;
            } else if (mem.eql(u8, arg, "--search-prefix")) {
                const prefix = nextArgOrFatal(args, &arg_i);

                // This argument is cache poisonous: it does not go into
                // the cache and configurer must set the poison bit when
                // choosing to observe it.
                configure_argv.addManyAsArrayAssumeCapacity(2).* = .{ arg, prefix };

                try graph.search_prefixes.append(arena, prefix);
            } else if (mem.eql(u8, arg, "--cache-dir")) {
                override_local_cache_dir = nextArgOrFatal(args, &arg_i);
            } else if (mem.eql(u8, arg, "--pkg-dir")) {
                override_pkg_dir = nextArgOrFatal(args, &arg_i);
            } else if (mem.eql(u8, arg, "--fetch")) {
                fetch_only = true;
            } else if (mem.cutPrefix(u8, arg, "--fetch=")) |rest| {
                fetch_only = true;
                fetch_mode = stringToEnum(Fetch.JobQueue.Mode, rest) orelse
                    fatal("expected [needed|all] after \"--fetch=\", found {q}", .{rest});
            } else if (mem.cutPrefix(u8, arg, "--fork=")) |rest| {
                try forks.append(arena, .init(rest));
            } else if (mem.eql(u8, arg, "--fork")) {
                try forks.append(arena, .init(nextArgOrFatal(args, &arg_i)));
            } else if (mem.startsWith(u8, arg, "--zig-lib=")) {
                fatal("--zig-lib= argument is special and must be first", .{});
            } else if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
                help_menu = true;
            } else if (mem.eql(u8, arg, "-l") or mem.eql(u8, arg, "--list-steps")) {
                steps_menu = true;
            } else if (mem.eql(u8, arg, "--zigscient")) { // custom
                override = .active;
            } else if (mem.eql(u8, arg, "--print-configuration")) {
                print_configuration = .zon;
            } else if (mem.eql(u8, arg, "--print-configuration-path")) {
                print_configuration = .path;
            } else if (mem.eql(u8, arg, "-p") or mem.eql(u8, arg, "--prefix")) {
                override_install_prefix = nextArgOrFatal(args, &arg_i);
            } else if (mem.eql(u8, arg, "--build-file")) {
                build_file = nextArgOrFatal(args, &arg_i);
            } else if (mem.eql(u8, arg, "--prefix-lib-dir")) {
                override_lib_dir = nextArgOrFatal(args, &arg_i);
            } else if (mem.eql(u8, arg, "--prefix-exe-dir")) {
                override_bin_dir = nextArgOrFatal(args, &arg_i);
            } else if (mem.eql(u8, arg, "--prefix-include-dir")) {
                override_include_dir = nextArgOrFatal(args, &arg_i);
            } else if (mem.eql(u8, arg, "--sysroot")) {
                graph.sysroot = nextArgOrFatal(args, &arg_i);
            } else if (mem.eql(u8, arg, "--maxrss")) {
                const max_rss_text = nextArgOrFatal(args, &arg_i);
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
                const timeout_str = nextArgOrFatal(args, &arg_i);
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
            } else if (mem.eql(u8, arg, "--libc")) {
                graph.libc_file = nextArgOrFatal(args, &arg_i);
            } else if (mem.eql(u8, arg, "--error-style")) {
                const next_arg = nextArg(args, &arg_i) orelse
                    fatalWithHint("expected style after {q}", .{arg});
                error_style = stringToEnum(ErrorStyle, next_arg) orelse {
                    fatalWithHint("expected style after {q}, found {q}", .{ arg, next_arg });
                };
            } else if (mem.eql(u8, arg, "--multiline-errors")) {
                const next_arg = nextArg(args, &arg_i) orelse
                    fatalWithHint("expected style after {q}", .{arg});
                multiline_errors = stringToEnum(MultilineErrors, next_arg) orelse {
                    fatalWithHint("expected style after {q}, found {q}", .{ arg, next_arg });
                };
            } else if (mem.eql(u8, arg, "--summary")) {
                const next_arg = nextArg(args, &arg_i) orelse
                    fatalWithHint("expected [all|new|failures|line|none] after {q}", .{arg});
                summary = stringToEnum(Summary, next_arg) orelse {
                    fatalWithHint("expected [all|new|failures|line|none] after {q}, found {q}", .{
                        arg, next_arg,
                    });
                };
            } else if (mem.cutPrefix(u8, arg, "--seed=")) |rest| {
                graph.random_seed = parseRandomSeed(rest);
            } else if (mem.eql(u8, arg, "--build-id")) {
                graph.build_id = .fast;
            } else if (mem.cutPrefix(u8, arg, "--build-id=")) |style| {
                graph.build_id = std.zig.BuildId.parse(style) catch |err|
                    fatal("unable to parse --build-id style {q}: {t}", .{ style, err });
            } else if (mem.eql(u8, arg, "--debounce")) {
                const next_arg = nextArg(args, &arg_i) orelse
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
            } else if (mem.eql(u8, arg, "--debug-target")) {
                debug_target = nextArgOrFatal(args, &arg_i);
            } else if (mem.eql(u8, arg, "--debug-log")) {
                try graph.debug_log_scopes.append(arena, nextArgOrFatal(args, &arg_i));
            } else if (mem.eql(u8, arg, "--debug-compile-errors")) {
                graph.debug_compile_errors = true;
            } else if (mem.eql(u8, arg, "--debug-incremental")) {
                graph.debug_incremental = true;
            } else if (mem.eql(u8, arg, "--debug-pkg-config")) {
                debug_pkg_config = true;
            } else if (mem.eql(u8, arg, "--debug-rt")) {
                graph.debug_compiler_runtime_libs = .Debug;
            } else if (mem.cutPrefix(u8, arg, "--debug-rt=")) |rest| {
                graph.debug_compiler_runtime_libs = stringToEnum(std.lang.OptimizeMode, rest) orelse
                    fatal("unrecognized optimization mode: {s}", .{rest});
            } else if (is_debug_mode and mem.eql(u8, arg, "--debug-maker-leaks")) {
                debug_maker_leaks = true;
            } else if (mem.eql(u8, arg, "--libc-runtimes") or mem.eql(u8, arg, "--glibc-runtimes")) {
                // --glibc-runtimes was the old name of the flag; kept for compatibility for now.
                graph.libc_runtimes_dir = nextArgOrFatal(args, &arg_i);
            } else if (mem.eql(u8, arg, "--verbose-air")) {
                graph.verbose_air = true;
            } else if (mem.eql(u8, arg, "--verbose-cc")) {
                graph.verbose_cc = true;
            } else if (mem.eql(u8, arg, "--verbose-link")) {
                graph.verbose_link = true;
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
                const next_arg = nextArgOrFatal(args, &arg_i);
                graph.error_limit = std.fmt.parseUnsigned(u32, next_arg, 0) catch |err|
                    fatal("unable to parse error limit {q}: {t}", .{ next_arg, err });
            } else if (mem.cutPrefix(u8, arg, "-j")) |text| {
                const n = std.fmt.parseUnsigned(u32, text, 10) catch |err|
                    fatal("unable to parse jobs count {q}: {t}", .{ text, err });
                if (n < 1) fatal("number of jobs must be at least 1", .{});
                threaded.setAsyncLimit(.limited(n));
                graph.max_jobs = n;
            } else if (mem.eql(u8, arg, "--")) {
                run_args = argsRest(args, arg_i);
                break;
            } else {
                fatalWithHint("unrecognized argument: {s}", .{arg});
            }
        } else {
            try step_names.append(arena, arg);
        }
    }

    const early_exit_mode = fetch_only or help_menu or steps_menu or print_configuration != .none;
    const server_mode = !early_exit_mode and (watch or webui_listen != null or fuzz != null);

    process.raiseFileDescriptorLimit();

    const cwd_path = std.zig.getResolvedCwd(io, arena) catch |err|
        fatal("resolving current directory path failed: {t}", .{err});

    var build_root = try findBuildRoot(arena, io, .{
        .cwd_path = cwd_path,
        .build_file = build_file,
    });
    defer build_root.deinit(io);

    graph.build_root_directory = build_root.directory;
    graph.local_cache_root = if (override_local_cache_dir) |unresolved_path| std.zig.Directories.openUnresolved(
        arena,
        io,
        cwd_path,
        unresolved_path,
        .@"local cache",
    ) else .{
        .path = try build_root.directory.join(arena, &.{default_local_zig_cache_basename}),
        .handle = try build_root.directory.handle.createDirPathOpen(io, default_local_zig_cache_basename, .{}),
    };
    graph.cache = .{
        .io = io,
        .gpa = gpa,
        .manifest_dir = try graph.local_cache_root.handle.createDirPathOpen(io, "h", .{}),
        .cwd = cwd_path,
    };

    graph.cache.addPrefix(.{ .path = null, .handle = cwd });
    graph.cache.addPrefix(zig_lib_directory);
    graph.cache.addPrefix(graph.local_cache_root);
    graph.cache.addPrefix(global_cache_directory);
    graph.cache.addPrefix(graph.build_root_directory);
    comptime assert(0 == @backingInt(std.zig.Server.Message.PathPrefix.cwd));
    comptime assert(1 == @backingInt(std.zig.Server.Message.PathPrefix.zig_lib));
    comptime assert(2 == @backingInt(std.zig.Server.Message.PathPrefix.local_cache));
    comptime assert(3 == @backingInt(std.zig.Server.Message.PathPrefix.global_cache));

    graph.cache.hash.addBytes(builtin.zig_version_string);

    const NO_COLOR = EnvVar.NO_COLOR.isSet(&graph.environ_map);
    const CLICOLOR_FORCE = EnvVar.CLICOLOR_FORCE.isSet(&graph.environ_map);

    graph.stderr_mode = switch (color) {
        .auto => try .detect(io, .stderr(), NO_COLOR, CLICOLOR_FORCE),
        .on => .escape_codes,
        .off => .no_color,
    };

    const pkg_root: Path = if (override_pkg_dir) |p|
        .initCwd(p)
    else if (system_pkg_dir_path) |p|
        .initCwd(p)
    else
        .{
            .root_dir = build_root.directory,
            .sub_path = "zig-pkg",
        };

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
        .root_dir = graph.build_root_directory,
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

    const now = Io.Clock.Timestamp.now(io, .awake);

    var web_server_allocation: AvoidableWebServer = undefined;
    const web_server: ?*AvoidableWebServer = if (webui_listen) |listen_address| ws: {
        if (builtin.single_threaded) fatal("--webui is not yet supported on single-threaded hosts", .{});
        web_server_allocation = .init(.{
            .graph = &graph,
            .root_prog_node = main_progress_node,
            .listen_address = listen_address,
            .base_timestamp = now,
        });
        web_server_allocation.start() catch |err| fatal("failed to start web server: {t}", .{err});
        break :ws &web_server_allocation;
    } else null;

    while (true) {
        // If this fails, we can still start the server and wait for user
        // to request a rebuild. If it returns error.FailedButCacheIntact
        // we can even still do file system watching and automatically
        // rebuild on source changes.
        if (configure(&graph, .{
            .configure_argv = configure_argv.items,
            .conf_argv_index_build_root = conf_argv_index_build_root,
            .cached_passthru_configure = cached_passthru_configure.items,

            .cache_poison = cache_poison,
            .pkg_root = pkg_root,
            .build_root = build_root,
            .cwd_path = cwd_path,
            .color = color,
            .debug_target = debug_target,
            .parent_progress_node = main_progress_node,
            .fetch_mode = fetch_mode,
            .system_pkg_dir_path = system_pkg_dir_path,
            .fetch_only = fetch_only,
            .print_configuration = print_configuration,
            .forks = forks.items,
        })) |scanned_config| {
            if (help_menu) {
                scanned_config.printUsage(&graph, initStdoutWriter(io)) catch |err| switch (err) {
                    error.WriteFailed => return stdout_writer_allocation.err.?,
                    else => |e| return e,
                };
                try stdout_writer_allocation.flush();
                return cleanExit(io, &scanned_config);
            } else if (steps_menu) {
                scanned_config.printSteps(&graph, initStdoutWriter(io)) catch |err| switch (err) {
                    error.WriteFailed => return stdout_writer_allocation.err.?,
                    else => |e| return e,
                };
                try stdout_writer_allocation.flush();
                return cleanExit(io, &scanned_config);
            } else switch (print_configuration) {
                .none => {},
                .zon => {
                    scanned_config.print(initStdoutWriter(io)) catch return stdout_writer_allocation.err.?;
                    try stdout_writer_allocation.flush();
                    return cleanExit(io, &scanned_config);
                },
                .path => unreachable,
            }

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
                .web_server = web_server,
                .memory_blocked_steps = .empty,
                .step_stack = .empty,
                .pkg_config = .{ .debug = debug_pkg_config },

                .error_style = error_style,
                .multiline_errors = multiline_errors,
                .summary = summary orelse if (watch or webui_listen != null) .new else .failures,
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
                    // TODO handle DependencyLoopDetected as error.FailedButCacheIntact
                    // and handle InsufficientMemory as error.AlreadyReported
                    _ = io.lockStderr(&.{}, graph.stderr_mode) catch {};
                    process.exit(1);
                },
                else => |e| return e,
            };

            var w: Watch = w: {
                if (!watch) break :w undefined;
                if (!Watch.have_impl) fatal("--watch not yet implemented for {t}", .{native_os});
                break :w try .init(&maker);
            };

            if (web_server) |ws| try ws.updateConfiguration(&maker);

            rebuild: while (true) : (if (maker.error_style.clearOnUpdate()) {
                const stderr = try io.lockStderr(&stdio_buffer_allocation, graph.stderr_mode);
                defer io.unlockStderr();
                stderr.file_writer.interface.writeAll("\x1B[2J\x1B[3J\x1B[H") catch |err| switch (err) {
                    error.WriteFailed => return stderr.file_writer.err.?,
                };
            }) {
                if (web_server) |ws| ws.startBuild();

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

                if (web_server) |ws| {
                    if (fuzz) |mode| if (mode != .forever) fatal(
                        "error: limited fuzzing is not implemented yet for --webui",
                        .{},
                    );

                    ws.finishBuild(.{ .fuzz = fuzz != null });
                }

                if (web_server) |ws| {
                    const c = &scanned_config.configuration;
                    assert(!watch); // fatal error after CLI parsing
                    while (true) switch (try ws.wait()) {
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
        } else |err| {
            const can_fs_watch = switch (err) {
                error.AlreadyReported => false,
                error.FailedButCacheIntact => true,
                else => |e| w: {
                    log.err("configuration failed: {t}", .{e});
                    break :w false;
                },
            };
            if (!server_mode) {
                _ = io.lockStderr(&.{}, graph.stderr_mode) catch {};
                process.exit(1);
            }
            if (watch and can_fs_watch) {
                fatal("(zig build system) TODO set up fs watching even when build.zig compilation fails", .{});
            } else {
                fatal("(zig build system) TODO stay running and wait for user to request rebuild even when build.zig compilation fails", .{});
            }
        }
    }
}

const ConfigureOptions = struct {
    configure_argv: [][]const u8,
    conf_argv_index_build_root: usize,
    cached_passthru_configure: []const u32,

    cache_poison: std.Build.Graph.CachePoison,
    pkg_root: Path,
    build_root: BuildRoot,
    cwd_path: []const u8,
    color: Color,
    debug_target: ?[]const u8,
    parent_progress_node: std.Progress.Node,
    fetch_mode: Fetch.JobQueue.Mode,
    system_pkg_dir_path: ?[]const u8,
    fetch_only: bool,
    print_configuration: PrintConfiguration,
    forks: []Fork,
};

fn configure(graph: *Graph, options: ConfigureOptions) !ScannedConfig {
    const configure_argv = options.configure_argv;
    const gpa = graph.cache.gpa;
    const io = graph.io;
    const arena = graph.arena;

    configure_argv[options.conf_argv_index_build_root] = options.build_root.directory.path orelse options.cwd_path;

    var http_client: std.http.Client = .{ .allocator = gpa, .io = io };
    defer http_client.deinit();

    var unlazy_set: Package.Fetch.JobQueue.UnlazySet = .{};
    var fork_set: Package.Fetch.JobQueue.ForkSet = .{};

    {
        // Populate fork_set.
        var group: Io.Group = .init;
        defer group.cancel(io);

        for (options.forks) |*fork|
            group.async(io, Fork.load, .{ io, gpa, fork, options.color });

        try group.await(io);

        for (options.forks) |*fork| {
            if (fork.failed) return error.AlreadyReported;
            try fork_set.put(arena, .{
                .path = fork.path,
                .manifest_ast = fork.manifest_ast,
                .manifest = fork.manifest,
                .uses = 0,
            }, {});
        }
    }
    defer Fork.deinitList(options.forks);

    var build_configurer_argv: std.ArrayList([]const u8) = .empty;
    defer build_configurer_argv.deinit(gpa);

    var dependencies_source: std.ArrayList(u8) = .empty;
    defer dependencies_source.deinit(gpa);

    const configurer_root_src_path: Cache.Path = .{
        .root_dir = graph.zig_lib_directory,
        .sub_path = "compiler/configurer.zig",
    };

    const root_build_src_path: Cache.Path = .{
        .root_dir = options.build_root.directory,
        .sub_path = options.build_root.build_zig_basename,
    };

    const configurer_exe_name = "configurer";

    try build_configurer_argv.appendSlice(gpa, &.{
        graph.zig_exe, "build-exe", //
        "--cache-dir", graph.local_cache_root.path orelse ".", //
        "--global-cache-dir", graph.global_cache_root.path orelse ".", //
        "--zig-lib-dir", graph.zig_lib_directory.path orelse ".", //
        "--name", configurer_exe_name, //
        "-fsingle-threaded", //
    });

    // Normally the build runner is compiled for the host target but here is
    // some code to help when debugging edits to the build runner so that you
    // can make sure it compiles successfully on other targets.
    const target_arch_os_abi: ?[]const u8 = if (options.debug_target) |triple| t: {
        try build_configurer_argv.appendSlice(gpa, &.{ "-target", triple });
        break :t triple;
    } else null;

    if (graph.libc_file) |libc_file| {
        try build_configurer_argv.appendSlice(gpa, &.{ "--libc", libc_file });
    }
    if (graph.reference_trace) |n| {
        try build_configurer_argv.append(gpa, try arena.print("-freference-trace={d}", .{n}));
    }
    if (graph.debug_compile_errors) {
        try build_configurer_argv.append(gpa, "--debug-compile-errors");
    }
    try build_configurer_argv.appendSlice(gpa, &.{
        "--dep", "@build", //
        "--dep", "@dependencies", //
        try arena.print("-Mroot={f}", .{configurer_root_src_path}), //
    });

    // In the loop below, after doing the fetch operation, the argv will be
    // truncated at this point, dependencies added, and then the
    // "--listen=-" arg appended at the end.
    const argv_deps_index = build_configurer_argv.items.len;

    const build_mod = try arena.create(CliModule);
    build_mod.* = .{
        .name = "@build",
        .root_path = try root_build_src_path.toString(arena),
    };

    const deps_mod = try arena.create(CliModule);
    deps_mod.* = .{
        .name = "@dependencies",
        .root_path = undefined,
    };

    // This loop is re-evaluated when the build script exits with an indication that it
    // could not continue due to missing lazy dependencies.
    const configuration_path: Path, var configuration_lock: ?Cache.Lock = cp: while (true) {
        build_mod.deps.clearRetainingCapacity();
        deps_mod.deps.clearRetainingCapacity();

        // Cache lookup for configure options. If we get a match, we can skip
        // execution of the configure script. If not, we get the file path to pass
        // to the configure process.
        //
        // In the hot path, we only check this cache, which means that also
        // configure source files need to go in here.
        var config_man_allocation: Cache.Manifest = undefined;
        const config_man: ?*Cache.Manifest = switch (options.cache_poison) {
            .pure, .disallowed, .ignored => m: {
                config_man_allocation = graph.cache.obtain();

                for (options.cached_passthru_configure) |i|
                    config_man_allocation.hash.addBytes(configure_argv[i]);

                if (target_arch_os_abi) |triple|
                    config_man_allocation.hash.addBytes(triple);

                // Prevents a `zig build` from getting a false positive cache hit following
                // a `zig build --cache-poison=ignored`.
                config_man_allocation.hash.add(options.cache_poison == .ignored);

                break :m &config_man_allocation;
            },
            .poisoned => null,
        };
        defer if (config_man) |man| man.deinit();

        // We want to release all the locks before executing the child process, so we make a nice
        // big block here to ensure the cleanup gets run when we extract out our argv.
        {
            {
                const fetch_prog_node = options.parent_progress_node.start("Fetch Packages", 0);
                defer fetch_prog_node.end();

                // Reset fork match counts.
                for (fork_set.keys()) |*fork| fork.uses = 0;

                var job_queue: Package.Fetch.JobQueue = .{
                    .io = io,
                    .http_client = &http_client,
                    .global_cache = graph.global_cache_root,
                    .local_storage = &.{
                        .cache_root = .{ .root_dir = graph.local_cache_root },
                        .pkg_root = options.pkg_root,
                    },
                    .recursive = true,
                    .debug_hash = false,
                    .unlazy_set = unlazy_set,
                    .fork_set = fork_set,
                    .mode = options.fetch_mode,
                    .prog_node = fetch_prog_node,
                    .read_only = options.system_pkg_dir_path != null,
                };
                defer job_queue.deinit();

                if (options.system_pkg_dir_path == null) {
                    try http_client.initDefaultProxies(arena, &graph.environ_map);
                }

                try job_queue.all_fetches.ensureUnusedCapacity(gpa, 1);
                try job_queue.table.ensureUnusedCapacity(gpa, 1);

                const phantom_package_root: Cache.Path = .{ .root_dir = options.build_root.directory };

                var fetch: Package.Fetch = .{
                    .arena = std.heap.ArenaAllocator.init(gpa),
                    .location = .{ .relative_path = phantom_package_root },
                    .location_tok = 0,
                    .hash_tok = .none,
                    .name_tok = 0,
                    .lazy_status = .eager,
                    .remote_package_root = phantom_package_root,
                    .parent_package_root = phantom_package_root,
                    .parent_manifest_ast = null,
                    .prog_node = fetch_prog_node,
                    .job_queue = &job_queue,
                    .omit_missing_hash_error = true,
                    .allow_missing_paths_field = false,
                    .use_latest_commit = false,

                    .package_root = undefined,
                    .error_bundle = undefined,
                    .manifest = undefined,
                    .manifest_ast = undefined,
                    .have_manifest = false,
                    .computed_hash = undefined,
                    .has_build_zig = true,
                    .oom_flag = false,
                    .latest_commit = null,

                    .cli_module = build_mod,
                };

                job_queue.all_fetches.appendAssumeCapacity(&fetch);

                job_queue.table.putAssumeCapacityNoClobber(
                    Package.Fetch.relativePathDigest(phantom_package_root, graph.global_cache_root),
                    &fetch,
                );

                job_queue.group.async(io, Package.Fetch.workerRun, .{ &fetch, "root" });
                try job_queue.group.await(io);

                {
                    // Ensure that forks were actually used. This is done
                    // before printing manifest errors because using a fork can
                    // prevent them.
                    var any_unused = false;
                    for (fork_set.keys()) |*fork| {
                        if (fork.uses == 0) {
                            log.err("fork {f} matched no {s} packages", .{
                                fork.path, fork.manifest.name,
                            });
                            any_unused = true;
                        } else {
                            log.info("fork {f} matched {d} {s} packages", .{
                                fork.path, fork.uses, fork.manifest.name,
                            });
                        }
                    }
                    if (any_unused) return error.FailedButCacheIntact;
                }

                try job_queue.consolidateErrors();

                if (fetch.error_bundle.root_list.items.len > 0) {
                    var errors = try fetch.error_bundle.toOwnedBundle("");
                    errors.renderToStderr(io, .{}, options.color) catch process.exit(1);
                    return error.FailedButCacheIntact;
                }

                if (options.fetch_only) {
                    _ = io.lockStderr(&.{}, .no_color) catch {};
                    process.exit(0);
                }

                // Create the dependencies.zig file for configurer to
                // obtain via `@import("@dependencies")`.
                {
                    {
                        dependencies_source.clearRetainingCapacity();
                        var source_writer: Io.Writer.Allocating = .fromArrayList(gpa, &dependencies_source);
                        defer dependencies_source = source_writer.toArrayList();
                        job_queue.createDependenciesSource(&source_writer.writer) catch |err| switch (err) {
                            error.WriteFailed => return error.OutOfMemory,
                        };
                    }
                    // Atomically create the file in a directory named after the hash of its contents.
                    var hh: Cache.HashHelper = .{};
                    hh.addBytes(builtin.zig_version_string);
                    hh.addBytes(dependencies_source.items);
                    const hex_digest = hh.final();
                    const dependencies_zig_path: Path = .{
                        .root_dir = graph.local_cache_root,
                        .sub_path = try arena.print("o/{s}/dependencies.zig", .{&hex_digest}),
                    };
                    var atomic_file = try dependencies_zig_path.root_dir.handle.createFileAtomic(
                        io,
                        dependencies_zig_path.sub_path,
                        .{ .make_path = true, .replace = true },
                    );
                    defer atomic_file.deinit(io);
                    atomic_file.file.writeStreamingAll(io, dependencies_source.items) catch |err|
                        fatal("writing dependencies.zig contents: {t}", .{err});
                    atomic_file.replace(io) catch |err|
                        fatal("replacing {f}: {t}", .{ dependencies_zig_path, err });

                    deps_mod.root_path = try dependencies_zig_path.toString(arena);
                }

                {
                    // Add a CliModule for each package's build.zig.
                    const hashes = job_queue.table.keys();
                    const fetches = job_queue.table.values();
                    try deps_mod.deps.ensureUnusedCapacity(arena, @intCast(hashes.len));
                    for (hashes, fetches) |*hash, f| {
                        if (f == &fetch) {
                            // The first one is a dummy package for the current project.
                            continue;
                        }
                        if (!f.has_build_zig)
                            continue;
                        const hash_slice = try arena.dupe(u8, hash.toSlice());

                        const m = try arena.create(CliModule);
                        m.* = .{
                            .root_path = try f.package_root.toString(arena),
                            .name = hash_slice,
                        };
                        deps_mod.deps.putAssumeCapacityNoClobber(hash_slice, m);
                        f.cli_module = m;
                    }

                    // Each build.zig module needs access to each of its
                    // dependencies' build.zig modules by name.
                    for (fetches) |f| {
                        const mod = f.cli_module orelse continue;
                        if (!f.have_manifest) continue;
                        const man = &f.manifest;
                        const dep_names = man.dependencies.keys();
                        try mod.deps.ensureUnusedCapacity(arena, @intCast(dep_names.len));
                        for (dep_names, man.dependencies.values()) |name, dep| {
                            const dep_digest = Package.Fetch.depDigest(
                                f.package_root,
                                graph.global_cache_root,
                                dep,
                            ) orelse continue;
                            const dep_mod = job_queue.table.get(dep_digest).?.cli_module orelse continue;
                            const name_cloned = try arena.dupe(u8, name);
                            mod.deps.putAssumeCapacityNoClobber(name_cloned, dep_mod);
                        }
                    }
                }

                // Lower module dependencies to CLI argv.
                build_configurer_argv.shrinkRetainingCapacity(argv_deps_index);
                for (deps_mod.deps.values()) |dep| {
                    try build_configurer_argv.ensureUnusedCapacity(gpa, 2 * dep.deps.count() + 1);
                    for (dep.deps.keys(), dep.deps.values()) |name, sub| {
                        build_configurer_argv.appendAssumeCapacity("--dep");
                        if (mem.eql(u8, name, sub.name)) {
                            build_configurer_argv.appendAssumeCapacity(sub.name);
                        } else {
                            build_configurer_argv.appendAssumeCapacity(try arena.print("{s}={s}", .{
                                name, sub.name,
                            }));
                        }
                    }
                    build_configurer_argv.appendAssumeCapacity(try arena.print("-M{s}={s}/{s}", .{
                        dep.name, dep.root_path, std.zig.build_zig_basename,
                    }));
                }
                try deps_mod.lower(arena, gpa, &build_configurer_argv);
                try build_mod.lower(arena, gpa, &build_configurer_argv);

                try build_configurer_argv.append(gpa, "--listen=-");
            }

            const compile_prog_node = options.parent_progress_node.start("Compile Configure Script", 0);
            defer compile_prog_node.end();

            if (config_man) |man| {
                if (try man.hit(compile_prog_node)) {
                    const digest = man.final();
                    break :cp .{
                        .{
                            .root_dir = graph.local_cache_root,
                            .sub_path = try arena.print("c/{s}", .{&digest}),
                        },
                        man.toOwnedLock(),
                    };
                }
            }
            const configure_exe_path: Path = if (std.zig.buildExeSubprocess(gpa, io, .{
                .argv = build_configurer_argv.items,
                .cache_root = graph.local_cache_root,
                .root_name = configurer_exe_name,
                .environ_map = &graph.environ_map,
                .cache_manifest = config_man,
                .arch_os_abi = target_arch_os_abi,
                .progress_node = compile_prog_node,
                .skip_log_cmdline_on_compile_errors = !graph.verbose,
                .skip_zig_protocol_version_check = true,
            })) |r| r.path else |err| return err;
            defer gpa.free(configure_exe_path.sub_path);

            configure_argv[0] = try configure_exe_path.toString(arena);
        }

        if (!process.can_spawn) {
            fatal("cannot spawn command on {t}: {f}", .{ native_os, @as(std.zig.SubprocessCommand, .{
                .argv = configure_argv,
            }) });
        }

        const config_tmp_path: Path = .{
            .root_dir = graph.local_cache_root,
            .sub_path = try arena.print("tmp" ++ Dir.path.sep_str ++ "{x}", .{randInt(io, u64)}),
        };
        const config_tmp_file: Io.File = try config_tmp_path.root_dir.handle.createFile(
            io,
            config_tmp_path.sub_path,
            .{ .read = true, .exclusive = true },
        );
        defer config_tmp_file.close(io);

        const term = term: {
            const child_node = options.parent_progress_node.start("Run Configure Script", 0);
            defer child_node.end();
            var child = process.spawn(io, .{
                .argv = configure_argv,
                .stdout = .{ .file = config_tmp_file },
                .progress_node = child_node,
            }) catch |err| fatal("failed to spawn configure script {q}: {t}", .{ configure_argv[0], err });
            defer child.kill(io);
            break :term child.wait(io) catch |err|
                fatal("failed to wait configure script {q}: {t}", .{ configure_argv[0], err });
        };
        if (!term.success()) {
            // Failure to produce the configuration file.
            fatal("configure command {f}: {f}", .{ term, @as(std.zig.SubprocessCommand, .{
                .argv = configure_argv,
            }) });
        }
        // Even though the file is designed to be sent directly to make
        // runner, we must load it now because:
        // * If it contains additional file dependencies, we need to
        //   add them to `config_man` before obtaining the final digest.
        // * If it contains a set of lazy packages that need to be
        //   fetched, we need to fetch those now and re-run configure.
        var configuration = Configuration.loadFile(arena, io, config_tmp_file) catch |err|
            fatal("failed to load configuration file {f}: {t}", .{ config_tmp_path, err });

        if (configuration.unlazy_deps.len != 0) {
            var any_errors = false;
            for (configuration.unlazy_deps) |hash_string| {
                const hash = hash_string.slice(&configuration);
                assert(hash.len != 0);
                if (hash.len > Package.Hash.max_len) {
                    log.err("invalid digest (length {d} exceeds maximum): {q}", .{ hash.len, hash });
                    any_errors = true;
                    continue;
                }
                log.info("fetching lazy dependency {s}", .{hash});
                try unlazy_set.put(arena, .fromSlice(hash), {});
            }
            if (any_errors) return error.FailedButCacheIntact;
            if (options.system_pkg_dir_path) |p| {
                // In this mode, the system needs to provide these packages; they
                // cannot be fetched by Zig.
                const s = Dir.path.sep_str;
                for (unlazy_set.keys()) |*hash| {
                    log.err("lazy dependency package not found: {s}" ++ s ++ "{s}", .{ p, hash.toSlice() });
                }
                log.info("remote package fetching disabled due to --system mode", .{});
                log.info("dependencies might be avoidable depending on build configuration", .{});
                return error.FailedButCacheIntact;
            }
            continue :cp;
        }

        if (config_man) |man| for (configuration.path_deps) |path_dep| {
            switch (path_dep.flags.mode) {
                .directory => {}, // TODO
                .contents => try man.addPathPost(confPathDepToCachePath(graph, &configuration, path_dep)),
                .metadata => {}, // TODO
            }
        };

        // If it is poisoned, there is no point in moving it to cached
        // location. Just leave it in the tmp directory.
        if (configuration.poisoned) {
            break :cp .{ config_tmp_path, null };
        } else {
            const man = config_man.?;
            const digest = man.final();
            const final_path: Path = .{
                .root_dir = graph.local_cache_root,
                .sub_path = try arena.print("c/{s}", .{&digest}),
            };
            Io.Dir.rename(
                config_tmp_path.root_dir.handle,
                config_tmp_path.sub_path,
                final_path.root_dir.handle,
                final_path.sub_path,
                io,
            ) catch |err| retry: {
                const e = switch (err) {
                    error.FileNotFound => e: {
                        const dir_path = final_path.dirname().?;
                        dir_path.root_dir.handle.createDirPath(io, dir_path.sub_path) catch |e|
                            fatal("failed to create directory {f}: {t}", .{ dir_path, e });
                        if (Io.Dir.rename(
                            config_tmp_path.root_dir.handle,
                            config_tmp_path.sub_path,
                            final_path.root_dir.handle,
                            final_path.sub_path,
                            io,
                        )) |_| break :retry else |e| break :e e;
                    },
                    else => |e| e,
                };
                fatal("failed to rename configuration file from {f} into {f}: {t}", .{
                    config_tmp_path, final_path, e,
                });
            };
            man.writeManifest() catch |err| log.warn("failed to write cache manifest: {t}", .{err});
            break :cp .{ final_path, man.toOwnedLock() };
        }
    };
    // Hang on to the configuration file lock until we finish loading the configuration file.
    defer if (configuration_lock) |*l| l.release(io);

    switch (options.print_configuration) {
        .path => {
            initStdoutWriter(io).print("{f}\n", .{configuration_path}) catch
                fatal("failed printing cache file path: {t}", .{stdout_writer_allocation.err.?});
            stdout_writer_allocation.flush() catch |err|
                fatal("failed printing cache file path: {t}", .{err});
            _ = io.lockStderr(&.{}, .no_color) catch {};
            process.exit(0);
        },
        .none, .zon => {},
    }

    const configuration = c: {
        var file = configuration_path.root_dir.handle.openFile(io, configuration_path.sub_path, .{}) catch |err|
            fatal("failed to open configuration file {f}: {t}", .{ configuration_path, err });
        defer file.close(io);
        break :c Configuration.loadFile(arena, io, file) catch |err|
            fatal("failed to load configuration file {f}: {t}", .{ configuration_path, err });
    };
    // Technically if the configuration is marked as poisoned, we could
    // already delete the file now, but we leave it around in case the
    // maker process fails or crashes and it's helpful to be able to repeat
    // execution of the command line or otherwise inspect the configuration file.
    const c = &configuration;
    var top_level_steps: std.array_hash_map.String(Configuration.Step.Index) = .empty;
    for (configuration.steps, 0..) |*conf_step, step_index_usize| {
        if (conf_step.owner != .root) continue;
        const step_index: Configuration.Step.Index = @fromBackingInt(@intCast(step_index_usize));
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
    return .{
        .configuration = configuration,
        .top_level_steps = top_level_steps,
        .path = configuration_path,
    };
}

fn cmdFetch(gpa: Allocator, graph: *Graph, args: []const []const u8) !void {
    const environ_map = &graph.environ_map;
    const io = graph.io;
    const arena = graph.arena;

    const color: Color = Color.settingFromEnvironment(environ_map);
    var opt_path_or_url: ?[]const u8 = null;
    var override_global_cache_dir: ?[]const u8 = EnvVar.ZIG_GLOBAL_CACHE_DIR.get(environ_map);
    var override_local_cache_dir: ?[]const u8 = EnvVar.ZIG_LOCAL_CACHE_DIR.get(environ_map);
    var override_pkg_dir: ?[]const u8 = EnvVar.ZIG_LOCAL_PKG_DIR.get(environ_map);
    var debug_hash: bool = false;
    var save: union(enum) {
        no,
        yes: ?[]const u8,
        exact: ?[]const u8,
    } = .no;

    var arg_i: usize = 0;
    while (nextArg(args, &arg_i)) |arg| {
        if (mem.startsWith(u8, arg, "-")) {
            if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
                try Io.File.stdout().writeStreamingAll(io, usage_fetch);
                return process.cleanExit(io);
            } else if (mem.eql(u8, arg, "--global-cache-dir")) {
                override_global_cache_dir = nextArgOrFatal(args, &arg_i);
            } else if (mem.eql(u8, arg, "--cache-dir")) {
                override_local_cache_dir = nextArgOrFatal(args, &arg_i);
            } else if (mem.eql(u8, arg, "--pkg-dir")) {
                override_pkg_dir = nextArgOrFatal(args, &arg_i);
            } else if (mem.eql(u8, arg, "--debug-hash")) {
                debug_hash = true;
            } else if (mem.eql(u8, arg, "--debug-log")) {
                try graph.debug_log_scopes.append(arena, nextArgOrFatal(args, &arg_i));
            } else if (mem.eql(u8, arg, "--save")) {
                save = .{ .yes = null };
            } else if (mem.cutPrefix(u8, arg, "--save=")) |rest| {
                save = .{ .yes = rest };
            } else if (mem.eql(u8, arg, "--save-exact")) {
                save = .{ .exact = null };
            } else if (mem.cutPrefix(u8, arg, "--save-exact=")) |rest| {
                save = .{ .exact = rest };
            } else {
                fatal("unrecognized parameter: {q}", .{arg});
            }
        } else if (opt_path_or_url != null) {
            fatal("unexpected extra parameter: {q}", .{arg});
        } else {
            opt_path_or_url = arg;
        }
    }

    const path_or_url = opt_path_or_url orelse fatal("missing url or path parameter", .{});

    var http_client: std.http.Client = .{ .allocator = gpa, .io = io };
    defer http_client.deinit();

    try http_client.initDefaultProxies(arena, environ_map);

    var root_prog_node = std.Progress.start(io, .{
        .root_name = "Fetch",
    });
    defer root_prog_node.end();

    var local_storage: Fetch.LocalStorage = undefined;
    var build_root: BuildRoot = undefined;
    var build_root_initialized = false;
    defer if (build_root_initialized) build_root.deinit(io);

    const cwd_path = try std.zig.getResolvedCwd(io, arena);

    const local_storage_ptr = switch (save) {
        .no => null,
        .yes, .exact => ls: {
            build_root = try findBuildRoot(arena, io, .{ .cwd_path = cwd_path });
            build_root_initialized = true;

            local_storage = .{
                .cache_root = if (override_local_cache_dir) |p| .initCwd(p) else .{
                    .root_dir = build_root.directory,
                    .sub_path = ".zig-cache",
                },
                .pkg_root = if (override_pkg_dir) |p| .initCwd(p) else .{
                    .root_dir = build_root.directory,
                    .sub_path = "zig-pkg",
                },
            };

            break :ls &local_storage;
        },
    };

    var job_queue: Fetch.JobQueue = .{
        .io = io,
        .http_client = &http_client,
        .global_cache = graph.global_cache_root,
        .local_storage = local_storage_ptr,
        .recursive = false,
        .read_only = false,
        .debug_hash = debug_hash,
        .mode = .all,
        .prog_node = root_prog_node,
    };
    defer job_queue.deinit();

    var fetch: Fetch = .{
        .arena = std.heap.ArenaAllocator.init(gpa),
        .location = .{ .path_or_url = path_or_url },
        .location_tok = 0,
        .hash_tok = .none,
        .name_tok = 0,
        .lazy_status = .eager,
        .remote_package_root = undefined,
        .parent_package_root = undefined,
        .parent_manifest_ast = null,
        .prog_node = root_prog_node,
        .job_queue = &job_queue,
        .omit_missing_hash_error = true,
        .allow_missing_paths_field = false,
        .use_latest_commit = true,

        .package_root = undefined,
        .error_bundle = undefined,
        .manifest = undefined,
        .manifest_ast = undefined,
        .have_manifest = false,
        .computed_hash = undefined,
        .has_build_zig = false,
        .oom_flag = false,
        .latest_commit = null,

        .cli_module = null,
    };
    defer fetch.deinit();

    fetch.run() catch |err| switch (err) {
        error.OutOfMemory, error.Canceled => |e| return e,
        error.FetchFailed => {}, // error bundle checked below
    };

    try job_queue.group.await(io);

    if (fetch.error_bundle.root_list.items.len > 0) {
        var errors = try fetch.error_bundle.toOwnedBundle("");
        errors.renderToStderr(io, .{}, color) catch {};
        process.exit(1);
    }

    const package_hash = fetch.computedPackageHash();
    const package_hash_slice = package_hash.toSlice();

    root_prog_node.end();
    root_prog_node = .{ .index = .none };

    const name = switch (save) {
        .no => {
            var data: [2][]const u8 = .{ package_hash_slice, "\n" };
            const w = initStdoutWriter(io);
            w.writeVecAll(&data) catch return stdout_writer_allocation.err.?;
            try stdout_writer_allocation.flush();
            return process.cleanExit(io);
        },
        .yes, .exact => |name| name: {
            if (name) |n| break :name n;
            if (!fetch.have_manifest)
                fatal("unable to determine name; fetched package has no build.zig.zon file", .{});
            break :name fetch.manifest.name;
        },
    };

    // The name to use in case the manifest file needs to be created now.
    const init_root_name = Dir.path.basename(build_root.directory.path orelse cwd_path);
    var manifest, var ast = try loadManifest(gpa, arena, io, .{
        .root_name = try sanitizeExampleName(arena, init_root_name),
        .dir = build_root.directory.handle,
        .color = color,
    });
    defer {
        manifest.deinit(gpa);
        ast.deinit(gpa);
    }

    var fixups: std.zig.Ast.Render.Fixups = .{};
    defer fixups.deinit(gpa);

    var saved_path_or_url = path_or_url;

    if (fetch.latest_commit) |latest_commit| resolved: {
        const latest_commit_hex = try arena.print("{f}", .{latest_commit});

        var uri = try std.Uri.parse(path_or_url);

        if (uri.fragment) |fragment| {
            const target_ref = try fragment.toRawMaybeAlloc(arena);

            // the refspec may already be fully resolved
            if (std.mem.eql(u8, target_ref, latest_commit_hex)) break :resolved;

            log.info("resolved ref {q} to commit {s}", .{ target_ref, latest_commit_hex });

            // include the original refspec in a query parameter, could be used to check for updates
            uri.query = .{ .percent_encoded = try arena.print("ref={f}", .{
                std.fmt.alt(fragment, .formatEscaped),
            }) };
        } else {
            log.info("resolved to commit {s}", .{latest_commit_hex});
        }

        // replace the refspec with the resolved commit SHA
        uri.fragment = .{ .raw = latest_commit_hex };

        switch (save) {
            .yes => saved_path_or_url = try arena.print("{f}", .{uri}),
            .no, .exact => {}, // keep the original URL
        }
    }

    const new_node_init = try arena.print(
        \\.{{
        \\            .url = "{f}",
        \\            .hash = "{f}",
        \\        }}
    , .{
        std.zig.fmtString(saved_path_or_url),
        std.zig.fmtString(package_hash_slice),
    });

    const new_node_text = try arena.print(".{f} = {s},\n", .{
        std.zig.fmtIdPU(name), new_node_init,
    });

    const dependencies_init = try arena.print(".{{\n        {s}    }}", .{
        new_node_text,
    });

    const dependencies_text = try arena.print(".dependencies = {s},\n", .{
        dependencies_init,
    });

    if (manifest.dependencies.get(name)) |dep| {
        if (dep.hash) |h| {
            switch (dep.location) {
                .url => |u| {
                    if (mem.eql(u8, h, package_hash_slice) and mem.eql(u8, u, saved_path_or_url)) {
                        log.info("existing dependency named {q} is up-to-date", .{name});
                        process.exit(0);
                    }
                },
                .path => {},
            }
        }

        const location_replace = try arena.print("{q}", .{saved_path_or_url});
        const hash_replace = try arena.print("{q}", .{package_hash_slice});

        log.warn("overwriting existing dependency named {q}", .{name});
        try fixups.replace_nodes_with_string.put(gpa, dep.location_node, location_replace);
        if (dep.hash_node.unwrap()) |hash_node| {
            try fixups.replace_nodes_with_string.put(gpa, hash_node, hash_replace);
        } else {
            // https://github.com/ziglang/zig/issues/21690
        }
    } else if (manifest.dependencies.count() > 0) {
        // Add fixup for adding another dependency.
        const deps = manifest.dependencies.values();
        const last_dep_node = deps[deps.len - 1].node;
        try fixups.append_string_after_node.put(gpa, last_dep_node, new_node_text);
    } else if (manifest.dependencies_node.unwrap()) |dependencies_node| {
        // Add fixup for replacing the entire dependencies struct.
        try fixups.replace_nodes_with_string.put(gpa, dependencies_node, dependencies_init);
    } else {
        // Add fixup for adding dependencies struct.
        try fixups.append_string_after_node.put(gpa, manifest.version_node, dependencies_text);
    }

    var aw: Io.Writer.Allocating = .init(gpa);
    defer aw.deinit();
    try ast.render(gpa, &aw.writer, fixups);
    const rendered = aw.written();

    build_root.directory.handle.writeFile(io, .{ .sub_path = Package.Manifest.basename, .data = rendered }) catch |err| {
        fatal("unable to write {s} file: {t}", .{ Package.Manifest.basename, err });
    };

    return process.cleanExit(io);
}

const usage_fetch =
    \\Usage: zig fetch [options] <url>
    \\Usage: zig fetch [options] <path>
    \\
    \\    Copy a package into the global cache and print its hash.
    \\    <url> must point to one of the following:
    \\      - A git+http / git+https server for the package
    \\      - A tarball file (with or without compression) containing
    \\        package source
    \\      - A git bundle file containing package source
    \\
    \\Examples:
    \\
    \\  zig fetch --save git+https://example.com/andrewrk/fun-example-tool.git
    \\  zig fetch --save https://example.com/andrewrk/fun-example-tool/archive/refs/heads/master.tar.gz
    \\
    \\Options:
    \\  -h, --help                    Print this help and exit
    \\  --global-cache-dir [path]     Override path to global Zig cache directory
    \\  --cache-dir [path]            Override path to local cache directory
    \\  --pkg-dir [path]              Override path to local package directory
    \\  --debug-hash                  Print verbose hash information to stdout
    \\  --debug-log [scope]           Enable printing debug/info log messages for scope
    \\  --save                        Add the fetched package to build.zig.zon
    \\  --save=[name]                 Add the fetched package to build.zig.zon as name
    \\  --save-exact                  Add the fetched package to build.zig.zon, storing the URL verbatim
    \\  --save-exact=[name]           Add the fetched package to build.zig.zon as name, storing the URL verbatim
    \\
;

const usage_init =
    \\Usage: zig init
    \\
    \\   Initializes a `zig build` project in the current working
    \\   directory.
    \\
    \\Options:
    \\  -m, --minimal          Use minimal init template
    \\  -h, --help             Print this help and exit
    \\
    \\
;

const usage_libc =
    \\Usage: zig libc
    \\
    \\    Detect the native libc installation and print the resulting
    \\    paths to stdout. You can save this into a file and then edit
    \\    the paths to create a cross compilation libc kit. Then you
    \\    can pass `--libc [file]` for Zig to use it.
    \\
    \\Usage: zig libc [paths_file]
    \\
    \\    Parse a libc installation text file and validate it.
    \\
    \\Options:
    \\  -h, --help             Print this help and exit
    \\  -target [name]         <arch><sub>-<os>-<abi> see the targets command
    \\  -includes              Print the libc include directories for the target
    \\
;

fn cmdInit(gpa: Allocator, graph: *Graph, args: []const []const u8) !void {
    const arena = graph.arena;
    const io = graph.io;
    const default_build_zig_basename = std.zig.build_zig_basename;

    var template: enum { example, minimal } = .example;
    {
        var i: usize = 0;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (mem.startsWith(u8, arg, "-")) {
                if (mem.eql(u8, arg, "-m") or mem.eql(u8, arg, "--minimal")) {
                    template = .minimal;
                } else if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
                    try Io.File.stdout().writeStreamingAll(io, usage_init);
                    return process.cleanExit(io);
                } else {
                    fatal("unrecognized parameter: {q}", .{arg});
                }
            } else {
                fatal("unexpected extra parameter: {q}", .{arg});
            }
        }
    }

    const cwd_path = try std.zig.getResolvedCwd(io, arena);
    const cwd_basename = Dir.path.basename(cwd_path);
    const sanitized_root_name = try sanitizeExampleName(arena, cwd_basename);

    const rng: std.Random.IoSource = .{ .io = io };
    const fingerprint: Package.Fingerprint = .generate(rng.interface(), sanitized_root_name);

    switch (template) {
        .example => {
            var templates = Templates.find(gpa, io, graph.zig_lib_directory);
            defer templates.deinit(io);

            const s = Dir.path.sep_str;
            const template_paths = [_][]const u8{
                default_build_zig_basename,
                Package.Manifest.basename,
                "src" ++ s ++ "main.zig",
                "src" ++ s ++ "root.zig",
            };
            var ok_count: usize = 0;

            for (template_paths) |template_path| {
                if (templates.write(arena, io, Io.Dir.cwd(), sanitized_root_name, template_path, fingerprint)) |_| {
                    log.info("created {s}", .{template_path});
                    ok_count += 1;
                } else |err| switch (err) {
                    error.PathAlreadyExists => log.info("preserving already existing file: {s}", .{
                        template_path,
                    }),
                    else => log.err("unable to write {s}: {t}", .{ template_path, err }),
                }
            }

            if (ok_count == template_paths.len) {
                log.info("see `zig build --help` for a menu of options", .{});
            }
            return process.cleanExit(io);
        },
        .minimal => {
            Templates.writeSimpleFile(io, Package.Manifest.basename,
                \\.{{
                \\    .name = .{s},
                \\    .version = "0.0.1",
                \\    .minimum_zig_version = "{s}",
                \\    .paths = .{{""}},
                \\    .fingerprint = 0x{x},
                \\}}
                \\
            , .{
                sanitized_root_name,
                builtin.zig_version_string,
                fingerprint.int(),
            }) catch |err| switch (err) {
                else => fatal("failed to create {q}: {t}", .{ Package.Manifest.basename, err }),
                error.PathAlreadyExists => fatal("refusing to overwrite {q}", .{Package.Manifest.basename}),
            };
            Templates.writeSimpleFile(io, default_build_zig_basename,
                \\const std = @import("std");
                \\
                \\pub fn build(b: *std.Build) void {{
                \\    _ = b; // stub
                \\}}
                \\
            , .{}) catch |err| switch (err) {
                else => fatal("failed to create {q}: {t}", .{ default_build_zig_basename, err }),
                // `build.zig` already existing is okay: the user has just used `zig init` to set up
                // their `build.zig.zon` *after* writing their `build.zig`. So this one isn't fatal.
                error.PathAlreadyExists => {
                    log.info("successfully populated {q}, preserving existing {q}", .{
                        Package.Manifest.basename, default_build_zig_basename,
                    });
                    return process.cleanExit(io);
                },
            };
            log.info("successfully populated {q} and {q}", .{ Package.Manifest.basename, default_build_zig_basename });
            return process.cleanExit(io);
        },
    }
}

fn cmdLibC(gpa: Allocator, graph: *Graph, args: []const []const u8) !void {
    const environ_map = &graph.environ_map;
    const io = graph.io;
    const arena = graph.arena;
    const LibCInstallation = std.zig.LibCInstallation;

    var input_file: ?[]const u8 = null;
    var target_arch_os_abi: []const u8 = "native";
    var print_includes: bool = false;
    const stdout = initStdoutWriter(io);
    {
        var i: usize = 0;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (mem.startsWith(u8, arg, "-")) {
                if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
                    try stdout.writeAll(usage_libc);
                    try stdout.flush();
                    return std.process.cleanExit(io);
                } else if (mem.eql(u8, arg, "-target")) {
                    if (i + 1 >= args.len) fatal("expected parameter after {s}", .{arg});
                    i += 1;
                    target_arch_os_abi = args[i];
                } else if (mem.eql(u8, arg, "-includes")) {
                    print_includes = true;
                } else {
                    fatal("unrecognized parameter: '{s}'", .{arg});
                }
            } else if (input_file != null) {
                fatal("unexpected extra parameter: '{s}'", .{arg});
            } else {
                input_file = arg;
            }
        }
    }

    const target_query = std.zig.parseTargetQueryOrReportFatalError(gpa, .{
        .arch_os_abi = target_arch_os_abi,
    });
    const target = std.zig.resolveTargetQueryOrFatal(io, target_query);

    if (print_includes) {
        const libc_installation: ?*LibCInstallation = libc: {
            if (input_file) |libc_file| {
                const libc = try arena.create(LibCInstallation);
                libc.* = LibCInstallation.parse(arena, io, libc_file, &target) catch |err| {
                    fatal("unable to parse libc file at path {s}: {t}", .{ libc_file, err });
                };
                break :libc libc;
            } else {
                break :libc null;
            }
        };

        const is_native_abi = target_query.isNativeAbi();

        const libc_dirs = std.zig.LibCDirs.detect(
            arena,
            io,
            .{ .root_dir = graph.zig_lib_directory },
            &target,
            is_native_abi,
            true,
            libc_installation,
            environ_map,
        ) catch |err| {
            const zig_target = try target.zigTriple(arena);
            fatal("unable to detect libc for target {s}: {t}", .{ zig_target, err });
        };

        if (libc_dirs.libc_include_dir_list.len == 0) {
            const zig_target = try target.zigTriple(arena);
            fatal("no include dirs detected for target {s}", .{zig_target});
        }

        for (libc_dirs.libc_include_dir_list) |include_dir| {
            try stdout.writeAll(include_dir);
            try stdout.writeByte('\n');
        }
        try stdout.flush();
        return std.process.cleanExit(io);
    }

    if (input_file) |libc_file| {
        var libc = LibCInstallation.parse(gpa, io, libc_file, &target) catch |err| {
            fatal("unable to parse libc file at path {s}: {t}", .{ libc_file, err });
        };
        defer libc.deinit(gpa);
    } else {
        if (!target_query.canDetectLibC()) {
            fatal("unable to detect libc for non-native target", .{});
        }
        var libc = LibCInstallation.findNative(gpa, io, .{
            .verbose = true,
            .target = &target,
            .environ_map = environ_map,
        }) catch |err| {
            fatal("unable to detect native libc: {t}", .{err});
        };
        defer libc.deinit(gpa);

        try libc.render(stdout);
        try stdout.flush();
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
    return &maker.steps[@backingInt(i)];
}

fn prepare(maker: *Maker, step_names: []const []const u8) !void {
    const gpa = maker.gpa;
    const graph = maker.graph;
    const arena = graph.arena;
    const seed: u32 = graph.random_seed;
    const step_stack = &maker.step_stack;
    const c = &maker.scanned_config.configuration;

    for (maker.steps, 0..) |*step, step_index_usize| {
        const step_index: Configuration.Step.Index = @fromBackingInt(@intCast(step_index_usize));
        step.* = .{ .extended = .init(step_index.ptr(c).flags(c).tag) };
    }

    if (step_names.len == 0) {
        try step_stack.put(gpa, c.default_step, {});
    } else {
        try step_stack.ensureUnusedCapacity(gpa, step_names.len);
        for (0..step_names.len) |i| {
            const step_name = step_names[step_names.len - i - 1];
            const s: std.Build.Configuration.Step.Index = if (mem.startsWith(u8, step_name, step_index_arg_prefix)) cs: {
                const cs_idx = std.fmt.parseInt(u32, step_name[step_index_arg_prefix.len..], 10) catch {
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
                log.info("use --maxrss {d} to proceed, risking system memory exhaustion", .{max_needed});
            }
            return error.InsufficientMemory;
        }
    }
}

fn makeStepNames(
    maker: *Maker,
    step_names: []const []const u8,
    parent_progress_node: std.Progress.Node,
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

        const step_prog = parent_progress_node.start("steps", step_stack.count());
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
        switch (native_os) {
            // Current implementation depends on two things that need to be ported to Windows:
            // * Memory-mapping to share data between the fuzzer and build runner.
            // * COFF/PE support added to `std.debug.Info` (it needs a batching API for resolving
            //   many addresses to source locations).
            .windows => fatal("--fuzz not yet implemented for {t}", .{native_os}),
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
        var f = Fuzz.init(maker, step_stack.keys(), parent_progress_node, mode) catch |err|
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

        w.writeByte('\n') catch {};

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

        if (maker.web_server) |ws| ws.updateStepStatus(step_index, .wip);

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
                if (maker.web_server) |ws| ws.updateStepStatus(step_index, .failure);
                std.Progress.setStatus(.failure_working);
            },

            .success,
            .skipped,
            => {
                if (maker.web_server) |ws| ws.updateStepStatus(step_index, .success);
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

fn nextArg(args: []const []const u8, i: *usize) ?[]const u8 {
    if (i.* >= args.len) return null;
    defer i.* += 1;
    return args[i.*];
}

fn nextArgOrFatal(args: []const []const u8, i: *usize) []const u8 {
    return nextArg(args, i) orelse fatalWithHint("expected another argument after {q}", .{args[i.* - 1]});
}

fn prefixedArgOrFatal(args: []const []const u8, i: *usize, prefix: []const u8) []const u8 {
    const arg = nextArgOrFatal(args, i);
    if (mem.cutPrefix(u8, arg, prefix)) |rest| return rest;
    fatal("expected {q} to instead begin with {q}", .{ arg, prefix });
}

fn argsRest(args: []const []const u8, idx: usize) ?[]const []const u8 {
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
    return &maker.generated_files[@backingInt(index)];
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
        try arena.print("lib{s}.{d}.dylib", .{ name, version.major }),
        try arena.print("lib{s}.dylib", .{name}),
    } else .{
        try arena.print("lib{s}.so.{d}", .{ name, version.major }),
        try arena.print("lib{s}.so", .{name}),
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
        scanned_config.path.root_dir.handle.deleteFile(io, scanned_config.path.sub_path) catch |err|
            log.warn("failed deleting poisoned configuration file {f}: {t}", .{ scanned_config.path, err });
    }
}

inline fn debugMakerLeaks() bool {
    if (!is_debug_mode) return false;
    return debug_maker_leaks;
}

const BuildRoot = struct {
    directory: Cache.Directory,
    close_directory: bool,
    build_zig_basename: []const u8,

    fn deinit(br: *BuildRoot, io: Io) void {
        if (br.close_directory) br.directory.handle.close(io);
        br.* = undefined;
    }
};

const FindBuildRootOptions = struct {
    build_file: ?[]const u8 = null,
    cwd_path: []const u8,
};

fn findBuildRoot(arena: Allocator, io: Io, options: FindBuildRootOptions) !BuildRoot {
    const build_zig_basename = if (options.build_file) |bf|
        Dir.path.basename(bf)
    else
        std.zig.build_zig_basename;

    if (options.build_file) |bf| {
        if (Dir.path.dirname(bf)) |dirname| {
            const dir = Io.Dir.cwd().openDir(io, dirname, .{}) catch |err| {
                fatal("failed opening directory containing {q}: {t}", .{ bf, err });
            };
            return .{
                .build_zig_basename = build_zig_basename,
                .directory = .{ .path = dirname, .handle = dir },
                .close_directory = true,
            };
        }

        return .{
            .build_zig_basename = build_zig_basename,
            .directory = .cwd(),
            .close_directory = false,
        };
    }
    // Search up parent directories until we find build.zig.
    var dirname: ?[]const u8 = null;
    while (true) {
        const joined_path = if (dirname) |d|
            try Dir.path.join(arena, &.{ d, build_zig_basename })
        else
            build_zig_basename;
        if (Io.Dir.cwd().access(io, joined_path, .{})) |_| {
            const dir = if (dirname) |d|
                Io.Dir.cwd().openDir(io, d, .{}) catch |err| {
                    fatal("unable to open directory while searching for build.zig file, {q}: {t}", .{ d, err });
                }
            else
                Io.Dir.cwd();
            return .{
                .build_zig_basename = build_zig_basename,
                .directory = .{
                    .path = dirname,
                    .handle = dir,
                },
                .close_directory = dirname != null,
            };
        } else |err| switch (err) {
            error.FileNotFound => {
                dirname = Dir.path.dirname(dirname orelse options.cwd_path) orelse {
                    log.info("initialize {s} template file with \"zig init\"", .{std.zig.build_zig_basename});
                    log.info("see \"zig --help\" for more options", .{});
                    fatal("no build.zig file found, in the current directory or any parent directories", .{});
                };
                continue;
            },
            else => |e| return e,
        }
    }
}

const Fork = struct {
    path: Path,
    manifest_ast: std.zig.Ast,
    manifest: Package.Manifest,
    error_bundle: std.zig.ErrorBundle.Wip,
    failed: bool,
    arena_allocator: std.heap.ArenaAllocator,

    fn init(cwd_relative_path: []const u8) Fork {
        return .{
            .manifest_ast = undefined,
            .manifest = undefined,
            .error_bundle = undefined,
            .arena_allocator = undefined,
            .path = .{
                .root_dir = .cwd(),
                .sub_path = cwd_relative_path,
            },
            .failed = false,
        };
    }

    fn load(io: Io, gpa: Allocator, fork: *Fork, color: Color) Io.Cancelable!void {
        loadFallible(io, gpa, fork, color) catch |err| switch (err) {
            error.Canceled => |e| return e,
            error.AlreadyReported => fork.failed = true,
            else => |e| {
                log.err("failed to load fork at {f}: {t}", .{ fork.path, e });
                fork.failed = true;
            },
        };
    }

    fn loadFallible(io: Io, gpa: Allocator, fork: *Fork, color: Color) !void {
        fork.arena_allocator = .init(gpa);
        const arena = fork.arena_allocator.allocator();

        var error_bundle: std.zig.ErrorBundle.Wip = undefined;
        try error_bundle.init(gpa);
        defer error_bundle.deinit();

        const manifest_path = try fork.path.join(arena, Package.Manifest.basename);

        Package.Manifest.load(
            io,
            arena,
            manifest_path,
            &fork.manifest_ast,
            &error_bundle,
            &fork.manifest,
            true,
        ) catch |err| switch (err) {
            error.Canceled => |e| return e,
            error.ErrorsBundled => {
                assert(error_bundle.root_list.items.len > 0);
                var errors = try error_bundle.toOwnedBundle("");
                errors.renderToStderr(io, .{}, color) catch {};
                return error.AlreadyReported;
            },
            else => |e| {
                log.err("failed to load package manifest {f}: {t}", .{ manifest_path, e });
                return error.AlreadyReported;
            },
        };
    }

    fn deinitList(forks: []Fork) void {
        for (forks) |*fork| fork.arena_allocator.deinit();
    }
};

fn parseRandomSeed(arg: []const u8) u32 {
    return std.fmt.parseUnsigned(u32, arg, 0) catch |err|
        fatal("failed parsing random seed {q} as unsigned 32-bit integer: {t}", .{ arg, err });
}

fn randInt(io: Io, comptime T: type) T {
    var x: T = undefined;
    io.random(@ptrCast(&x));
    return x;
}

const LoadManifestOptions = struct {
    root_name: []const u8,
    dir: Io.Dir,
    color: Color,
};

fn loadManifest(
    gpa: Allocator,
    arena: Allocator,
    io: Io,
    options: LoadManifestOptions,
) !struct { Package.Manifest, std.zig.Ast } {
    const rng: std.Random.IoSource = .{ .io = io };

    const manifest_bytes = while (true) {
        break options.dir.readFileAllocOptions(
            io,
            Package.Manifest.basename,
            arena,
            .limited(Package.Manifest.max_bytes),
            .@"1",
            0,
        ) catch |err| switch (err) {
            error.FileNotFound => {
                Templates.writeSimpleFile(io, Package.Manifest.basename,
                    \\.{{
                    \\    .name = .{s},
                    \\    .version = "{s}",
                    \\    .paths = .{{""}},
                    \\    .fingerprint = 0x{x},
                    \\}}
                    \\
                , .{
                    options.root_name,
                    builtin.zig_version_string,
                    Package.Fingerprint.generate(rng.interface(), options.root_name).int(),
                }) catch |e| {
                    fatal("unable to write {s}: {t}", .{ Package.Manifest.basename, e });
                };
                continue;
            },
            else => |e| fatal("unable to load {s}: {t}", .{ Package.Manifest.basename, e }),
        };
    };
    var ast = try std.zig.Ast.parse(gpa, manifest_bytes, .{ .mode = .zon });
    errdefer ast.deinit(gpa);

    if (ast.errors.len > 0) {
        try std.zig.printAstErrorsToStderr(gpa, io, ast, Package.Manifest.basename, options.color);
        process.exit(2);
    }

    var manifest = try Package.Manifest.parse(gpa, &ast, rng.interface(), .{});
    errdefer manifest.deinit(gpa);

    if (manifest.errors.len > 0) {
        var wip_errors: std.zig.ErrorBundle.Wip = undefined;
        try wip_errors.init(gpa);
        defer wip_errors.deinit();

        const src_path = try wip_errors.addString(Package.Manifest.basename);
        try manifest.copyErrorsIntoBundle(ast, src_path, &wip_errors);

        var error_bundle = try wip_errors.toOwnedBundle("");
        defer error_bundle.deinit(gpa);
        error_bundle.renderToStderr(io, .{}, options.color) catch {};

        process.exit(2);
    }
    return .{ manifest, ast };
}

fn sanitizeExampleName(arena: Allocator, bytes: []const u8) error{OutOfMemory}![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    for (bytes, 0..) |byte, i| switch (byte) {
        '0'...'9' => {
            if (i == 0) try result.append(arena, '_');
            try result.append(arena, byte);
        },
        '_', 'a'...'z', 'A'...'Z' => try result.append(arena, byte),
        '-', '.', ' ' => try result.append(arena, '_'),
        else => continue,
    };
    if (!std.zig.isValidId(result.items)) return "foo";
    if (result.items.len > Package.Manifest.max_name_len)
        result.shrinkRetainingCapacity(Package.Manifest.max_name_len);

    return result.toOwnedSlice(arena);
}

test sanitizeExampleName {
    var arena_instance = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    try std.testing.expectEqualStrings("foo_bar", try sanitizeExampleName(arena, "foo bar+"));
    try std.testing.expectEqualStrings("foo", try sanitizeExampleName(arena, ""));
    try std.testing.expectEqualStrings("foo", try sanitizeExampleName(arena, "!"));
    try std.testing.expectEqualStrings("a", try sanitizeExampleName(arena, "!a"));
    try std.testing.expectEqualStrings("a_b", try sanitizeExampleName(arena, "a.b!"));
    try std.testing.expectEqualStrings("_01234", try sanitizeExampleName(arena, "01234"));
    try std.testing.expectEqualStrings("foo", try sanitizeExampleName(arena, "error"));
    try std.testing.expectEqualStrings("foo", try sanitizeExampleName(arena, "test"));
    try std.testing.expectEqualStrings("tests", try sanitizeExampleName(arena, "tests"));
    try std.testing.expectEqualStrings("test_project", try sanitizeExampleName(arena, "test project"));
}

const Templates = struct {
    zig_lib_directory: Cache.Directory,
    dir: Io.Dir,
    buffer: std.array_list.Managed(u8),

    fn deinit(templates: *Templates, io: Io) void {
        templates.zig_lib_directory.handle.close(io);
        templates.dir.close(io);
        templates.buffer.deinit();
        templates.* = undefined;
    }

    fn write(
        templates: *Templates,
        arena: Allocator,
        io: Io,
        out_dir: Io.Dir,
        root_name: []const u8,
        template_path: []const u8,
        fingerprint: Package.Fingerprint,
    ) !void {
        if (Dir.path.dirname(template_path)) |dirname| {
            out_dir.createDirPath(io, dirname) catch |err| {
                fatal("unable to make path {q}: {t}", .{ dirname, err });
            };
        }

        const max_bytes = 10 * 1024 * 1024;
        const contents = templates.dir.readFileAlloc(io, template_path, arena, .limited(max_bytes)) catch |err| {
            fatal("unable to read template file {q}: {t}", .{ template_path, err });
        };
        templates.buffer.clearRetainingCapacity();
        try templates.buffer.ensureUnusedCapacity(contents.len);
        var i: usize = 0;
        while (i < contents.len) {
            if (contents[i] == '_' or contents[i] == '.') {
                // Both '_' and '.' are allowed because depending on the context
                // one prefix will be valid, while the other might not.
                if (std.mem.startsWith(u8, contents[i + 1 ..], "NAME")) {
                    try templates.buffer.appendSlice(root_name);
                    i += "_NAME".len;
                    continue;
                } else if (std.mem.startsWith(u8, contents[i + 1 ..], "FINGERPRINT")) {
                    try templates.buffer.print("0x{x}", .{fingerprint.int()});
                    i += "_FINGERPRINT".len;
                    continue;
                } else if (std.mem.startsWith(u8, contents[i + 1 ..], "ZIGVER")) {
                    try templates.buffer.appendSlice(builtin.zig_version_string);
                    i += "_ZIGVER".len;
                    continue;
                }
            }

            try templates.buffer.append(contents[i]);
            i += 1;
        }

        return out_dir.writeFile(io, .{
            .sub_path = template_path,
            .data = templates.buffer.items,
            .flags = .{ .exclusive = true },
        });
    }

    fn find(gpa: Allocator, io: Io, zig_lib_directory: Cache.Directory) Templates {
        const template_path: Path = .{
            .root_dir = zig_lib_directory,
            .sub_path = "init",
        };
        const template_dir = template_path.root_dir.handle.openDir(io, template_path.sub_path, .{}) catch |err|
            fatal("unable to open zig project template directory {f}: {t}", .{ template_path, err });
        return .{
            .zig_lib_directory = zig_lib_directory,
            .dir = template_dir,
            .buffer = std.array_list.Managed(u8).init(gpa),
        };
    }

    fn writeSimpleFile(io: Io, file_name: []const u8, comptime format: []const u8, args: anytype) !void {
        const f = try Io.Dir.cwd().createFile(io, file_name, .{ .exclusive = true });
        defer f.close(io);
        var buf: [4096]u8 = undefined;
        var fw = f.writer(io, &buf);
        try fw.interface.print(format, args);
        try fw.interface.flush();
    }
};

fn confPathDepToCachePath(graph: *const Graph, c: *const Configuration, path_dep: Configuration.PathDep) Path {
    const sub_path = path_dep.sub.slice(c);
    return switch (path_dep.flags.base) {
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
            .root_dir = switch (path_dep.pkg.unwrap().?) {
                .root => graph.build_root_directory,
                _ => @panic("TODO"),
            },
            .sub_path = sub_path,
        },
        .zig_lib => .{
            .root_dir = graph.zig_lib_directory,
            .sub_path = sub_path,
        },
        .zig_exe => @panic("TODO"),
        .install_prefix => @panic("TODO"),
        .install_lib => @panic("TODO"),
        .install_bin => @panic("TODO"),
        .install_include => @panic("TODO"),
    };
}
