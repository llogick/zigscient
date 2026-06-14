//! The *mutable* state that `Maker` needs in order to process one node from
//! the build graph.
const Step = @This();

const builtin = @import("builtin");

const std = @import("std");
const Allocator = std.mem.Allocator;
const Cache = std.Build.Cache;
const Io = std.Io;
const Dir = std.Io.Dir;
const LazyPath = std.Build.Configuration.LazyPath;
const Package = std.Build.Configuration.Package;
const Path = std.Build.Cache.Path;
const Configuration = std.Build.Configuration;
const assert = std.debug.assert;

const WebServer = @import("WebServer.zig");
const Maker = @import("../Maker.zig");

pub const CheckFile = @import("Step/CheckFile.zig");
pub const Compile = @import("Step/Compile.zig");
pub const ConfigHeader = @import("Step/ConfigHeader.zig");
pub const FindProgram = @import("Step/FindProgram.zig");
pub const Fmt = @import("Step/Fmt.zig");
pub const InstallArtifact = @import("Step/InstallArtifact.zig");
pub const InstallDir = @import("Step/InstallDir.zig");
pub const InstallFile = @import("Step/InstallFile.zig");
pub const ObjCopy = @import("Step/ObjCopy.zig");
pub const Options = @import("Step/Options.zig");
pub const Run = @import("Step/Run.zig");
pub const TranslateC = @import("Step/TranslateC.zig");
pub const UpdateSourceFiles = @import("Step/UpdateSourceFiles.zig");
pub const WriteFile = @import("Step/WriteFile.zig");

/// Avoid false sharing.
_: void align(std.atomic.cache_line) = {},

/// Extra data for specific types of steps.
extended: Extended,

/// This field is atomically accessed multi-threaded.
state: State = .precheck_unstarted,

dependants: std.ArrayList(Configuration.Step.Index) = .empty,
/// Collects the set of files that retrigger this step to run.
///
/// This is used by the build system's implementation of `--watch` but it can
/// also be potentially useful for IDEs to know what effects editing a
/// particular file has.
///
/// Populated within `make`. Implementation may choose to clear and repopulate,
/// retain previous value, or update.
inputs: Inputs = .init,
pending_deps: u32 = undefined,

/// Array list and internal memory owned by process arena.
result_error_msgs: std.ArrayList([]const u8) = .empty,
result_error_bundle: std.zig.ErrorBundle = .empty,
/// Owned by `Maker.gpa`.
result_stderr: []const u8 = "",
result_cached: bool = false,
/// Indicates error information is missing due to allocation failure.
result_oom: bool = false,
result_duration_ns: ?u64 = null,
/// 0 means unavailable or not reported.
result_peak_rss: usize = 0,
/// If the step is failed and this field is populated, this is the command which failed.
/// This field may be populated even if the step succeeded.
/// Memory owned by `Maker.gpa`.
result_failed_command: ?[]const u8 = null,
test_results: TestResults = .{},

comptime {
    // Common cache line size is 128. This check prevents accidentally crossing
    // an additional cache line. In the future it might be nice to try to fit
    // this struct in 128 bytes or less.
    if (std.atomic.cache_line <= 128) assert(@sizeOf(@This()) <= 128 * 3);
}

pub const Extended = union(enum) {
    check_file: CheckFile,
    compile: Compile,
    config_header: ConfigHeader,
    fail: Fail,
    find_program: FindProgram,
    fmt: Fmt,
    install_artifact: InstallArtifact,
    install_dir: InstallDir,
    install_file: InstallFile,
    obj_copy: ObjCopy,
    options: Options,
    run: Run,
    top_level: TopLevel,
    translate_c: TranslateC,
    update_source_files: UpdateSourceFiles,
    write_file: WriteFile,

    pub fn init(tag: Configuration.Step.Tag) Extended {
        return switch (tag) {
            .check_file => .{ .check_file = .{} },
            .compile => .{ .compile = .{} },
            .config_header => .{ .config_header = .{} },
            .fail => .{ .fail = .{} },
            .find_program => .{ .find_program = .{} },
            .fmt => .{ .fmt = .{} },
            .install_artifact => .{ .install_artifact = .{} },
            .install_dir => .{ .install_dir = .{} },
            .install_file => .{ .install_file = .{} },
            .obj_copy => .{ .obj_copy = .{} },
            .options => .{ .options = .{} },
            .run => .{ .run = .{} },
            .top_level => .{ .top_level = .{} },
            .translate_c => .{ .translate_c = .{} },
            .update_source_files => .{ .update_source_files = .{} },
            .write_file => .{ .write_file = .{} },
        };
    }

    pub const TopLevel = struct {
        pub fn make(
            top_level: *TopLevel,
            step_index: Configuration.Step.Index,
            maker: *Maker,
            progress_node: std.Progress.Node,
        ) Step.ExtendedMakeError!void {
            _ = top_level;
            _ = step_index;
            _ = maker;
            _ = progress_node;
        }
    };

    pub const Fail = struct {
        pub fn make(
            this: *@This(),
            step_index: Configuration.Step.Index,
            maker: *Maker,
            progress_node: std.Progress.Node,
        ) Step.ExtendedMakeError!void {
            _ = this;
            _ = progress_node;
            const graph = maker.graph;
            const arena = graph.arena; // TODO don't leak into the process arena
            const conf = &maker.scanned_config.configuration;
            const step = maker.stepByIndex(step_index);
            const conf_step = step_index.ptr(conf);
            const conf_fail = conf_step.extended.get(conf.extra).fail;

            try step.result_error_msgs.append(arena, conf_fail.msg.slice(conf));
            return error.MakeFailed;
        }
    };
};

pub const State = enum {
    precheck_unstarted,
    precheck_started,
    /// This is also used to indicate "dirty" steps that have been modified
    /// after a previous build completed, in which case, the step may or may
    /// not have been completed before. Either way, one or more of its direct
    /// file system inputs have been modified, meaning that the step needs to
    /// be re-evaluated.
    precheck_done,
    dependency_failure,
    success,
    failure,
    /// This state indicates that the step did not complete, however, it also did not fail,
    /// and it is safe to continue executing its dependencies.
    skipped,
    /// This step was skipped because it specified a max_rss that exceeded the runner's maximum.
    /// It is not safe to run its dependencies.
    skipped_oom,
};

pub const Inputs = struct {
    table: Table,

    pub const init: Inputs = .{
        .table = .{},
    };

    pub const Table = std.array_hash_map.Custom(Path, Files, Path.TableAdapter, false);
    /// The special file name "." means any changes inside the directory.
    pub const Files = std.ArrayList([]const u8);

    pub fn populated(inputs: *Inputs) bool {
        return inputs.table.count() != 0;
    }

    pub fn clear(inputs: *Inputs, gpa: Allocator) void {
        for (inputs.table.values()) |*files| files.deinit(gpa);
        inputs.table.clearRetainingCapacity();
    }

    pub fn deinit(inputs: *Inputs, gpa: Allocator) void {
        clear(inputs, gpa);
        inputs.table.deinit(gpa);
    }
};

pub const TestResults = struct {
    /// The total number of tests in the step. Every test has a "status" from the following:
    /// * passed
    /// * skipped
    /// * failed cleanly
    /// * crashed
    /// * timed out
    test_count: u32 = 0,

    /// The number of tests which were skipped (`error.SkipZigTest`).
    skip_count: u32 = 0,
    /// The number of tests which failed cleanly.
    fail_count: u32 = 0,
    /// The number of tests which terminated unexpectedly, i.e. crashed.
    crash_count: u32 = 0,
    /// The number of tests which timed out.
    timeout_count: u32 = 0,

    /// The number of detected memory leaks. The associated test may still have passed; indeed, *all*
    /// individual tests may have passed. However, the step as a whole fails if any test has leaks.
    leak_count: u32 = 0,
    /// The number of detected error logs. The associated test may still have passed; indeed, *all*
    /// individual tests may have passed. However, the step as a whole fails if any test logs errors.
    log_err_count: u32 = 0,

    pub fn isSuccess(tr: TestResults) bool {
        // all steps are success or skip
        return tr.fail_count == 0 and
            tr.crash_count == 0 and
            tr.timeout_count == 0 and
            // no (otherwise successful) step leaked memory or logged errors
            tr.leak_count == 0 and
            tr.log_err_count == 0;
    }

    /// Computes the number of tests which passed from the other values.
    pub fn passCount(tr: TestResults) u32 {
        return tr.test_count - tr.skip_count - tr.fail_count - tr.crash_count - tr.timeout_count;
    }
};

pub const MakeError = error{
    /// Indicates the error is already reported.
    MakeFailed,
    MakeSkipped,
} || Io.Cancelable;

pub const ExtendedMakeError = MakeError || Allocator.Error;

pub fn make(
    step_index: Configuration.Step.Index,
    maker: *Maker,
    progress_node: std.Progress.Node,
) MakeError!void {
    const graph = maker.graph;
    const arena = graph.arena; // TODO don't leak into the process arena
    const io = graph.io;
    const c = &maker.scanned_config.configuration;
    const conf_step = step_index.ptr(c);
    const s = maker.stepByIndex(step_index);

    var start_ts: ?Io.Timestamp = t: {
        if (!graph.time_report) break :t null;
        const flags = conf_step.flags(c);
        switch (flags.tag) {
            .compile => break :t null,
            .run => {
                const run_flags: Configuration.Step.Run.Flags = @bitCast(flags);
                if (run_flags.stdio == .zig_test) break :t null;
            },
            else => {},
        }
        break :t Io.Clock.awake.now(io);
    };
    const make_result = switch (s.extended) {
        inline else => |*extended| extended.make(step_index, maker, progress_node),
    };
    if (start_ts) |*ts| {
        const duration = ts.untilNow(io, .awake);
        maker.web_server.?.updateTimeReportGeneric(step_index, duration);
    }

    make_result catch |err| switch (err) {
        error.MakeFailed, error.MakeSkipped => |e| return e,
        error.OutOfMemory => {
            s.result_oom = true;
            return error.MakeFailed;
        },
        error.Canceled => |e| return e,
    };

    if (!s.test_results.isSuccess()) {
        return error.MakeFailed;
    }

    const max_rss = conf_step.max_rss.toBytes();
    if (max_rss != 0 and s.result_peak_rss > max_rss) {
        if (std.fmt.allocPrint(
            arena,
            "memory usage peaked at {0B:.2} ({0d} bytes), exceeding the declared upper bound of {1B:.2} ({1d} bytes)",
            .{ s.result_peak_rss, max_rss },
        )) |msg| {
            s.oomWrap(s.result_error_msgs.append(arena, msg));
        } else |_| s.result_oom = true;
    }
}

/// Prepares the step for being re-evaluated.
pub fn reset(step: *Step, maker: *Maker) void {
    assert(step.state == .precheck_done);
    const gpa = maker.gpa;

    clearFailedCommand(step, gpa);
    clearResultStderr(step, gpa);
    step.result_error_msgs.clearRetainingCapacity();
    step.result_cached = false;
    step.result_duration_ns = null;
    step.result_peak_rss = 0;
    step.test_results = .{};
    clearWatchInputs(step, maker);
    clearErrorBundle(step, gpa);
}

pub const CaptureChildProcessError = error{
    FileNotFound,
} || ExtendedMakeError;

pub const CaptureChildProcessOptions = struct {
    argv: []const []const u8,
    progress_node: std.Progress.Node = .none,
    environ_map: ?*const std.process.Environ.Map = null,
    allow_failure: bool = false,
};

/// Populates `s.result_failed_command` unconditionally.
pub fn captureChildProcess(
    s: *Step,
    maker: *Maker,
    allocator: Allocator,
    options: CaptureChildProcessOptions,
) !std.process.RunResult {
    const gpa = maker.gpa;
    const graph = maker.graph;
    const io = graph.io;

    s.setFailedCommand(gpa, options.argv, .{});

    try handleChildProcUnsupported(s, maker);
    try graph.handleVerbose(null, null, options.argv);

    const result = std.process.run(allocator, io, .{
        .argv = options.argv,
        .environ_map = options.environ_map orelse &graph.environ_map,
        .progress_node = options.progress_node,
    }) catch |err| {
        switch (err) {
            error.OutOfMemory, error.Canceled => |e| return e,
            error.FileNotFound => |e| if (options.allow_failure) return e,
            else => {},
        }
        return s.fail(maker, "failed to run {s}: {t}", .{ options.argv[0], err });
    };

    if (result.stderr.len > 0) try s.result_error_msgs.append(graph.arena, result.stderr);

    return result;
}

pub fn clearErrorBundle(s: *Step, gpa: Allocator) void {
    s.result_error_bundle.deinit(gpa);
    s.result_error_bundle = .empty;
}

pub fn clearFailedCommand(s: *Step, gpa: Allocator) void {
    if (s.result_failed_command) |cmd| {
        gpa.free(cmd);
        s.result_failed_command = null;
    }
}

pub fn setFailedCommand(
    s: *Step,
    gpa: Allocator,
    argv: []const []const u8,
    options: std.zig.AllocPrintCmdOptions,
) void {
    s.clearFailedCommand(gpa);
    s.result_failed_command = std.zig.allocPrintCmd(gpa, argv, options) catch |err| switch (err) {
        error.OutOfMemory => {
            s.result_oom = true;
            return;
        },
    };
}

pub const FailError = error{ OutOfMemory, MakeFailed };

pub fn fail(step: *Step, maker: *const Maker, comptime fmt: []const u8, args: anytype) FailError {
    try step.addError(maker, fmt, args);
    return error.MakeFailed;
}

pub fn addError(step: *Step, maker: *const Maker, comptime fmt: []const u8, args: anytype) error{OutOfMemory}!void {
    const graph = maker.graph;
    const arena = graph.arena; // TODO don't leak into the process_arena
    const msg = try std.fmt.allocPrint(arena, fmt, args);
    try step.result_error_msgs.append(arena, msg);
}

pub const ZigProcess = struct {
    child: std.process.Child,
    multi_reader_buffer: Io.File.MultiReader.Buffer(2),
    multi_reader: Io.File.MultiReader,
    progress_ipc_index: ?if (std.Progress.have_ipc) std.Progress.Ipc.Index else noreturn,

    pub const StreamEnum = enum { stdout, stderr };

    pub fn saveState(zp: *ZigProcess, prog_node: std.Progress.Node) void {
        zp.progress_ipc_index = if (std.Progress.have_ipc) prog_node.takeIpcIndex() else null;
    }

    pub fn deinit(zp: *ZigProcess, io: Io) void {
        zp.child.kill(io);
        zp.multi_reader.deinit();
        zp.* = undefined;
    }
};

/// Assumes that argv contains `--listen=-` and that the process being spawned
/// is the zig compiler - the same version that compiled the build runner.
///
/// Populates `s.result_failed_command` on failure.
pub fn evalZigProcess(
    step_index: Configuration.Step.Index,
    maker: *Maker,
    argv: []const []const u8,
    prog_node: std.Progress.Node,
    watch: bool,
) (Step.ExtendedMakeError || error{NeedCompileErrorCheck})!?Path {
    const s = maker.stepByIndex(step_index);
    const gpa = maker.gpa;
    const graph = maker.graph;
    const io = graph.io;

    // If an error occurs, it's happened in this command:
    errdefer s.setFailedCommand(gpa, argv, .{});

    if (s.getZigProcess()) |zp| update: {
        assert(watch);
        if (zp.progress_ipc_index) |ipc_index| prog_node.setIpcIndex(ipc_index);
        zp.progress_ipc_index = null;
        var exited = false;
        defer if (exited) {
            s.extended.compile.zig_process = null;
            zp.deinit(io);
            gpa.destroy(zp);
        } else zp.saveState(prog_node);
        const result = zigProcessUpdate(step_index, maker, zp, watch) catch |err| switch (err) {
            error.BrokenPipe, error.EndOfStream => |reason| {
                // Process restart required.
                std.log.info("{s} restart required: {t}", .{ argv[0], reason });
                _ = zp.child.wait(io) catch |e| return s.fail(maker, "unable to wait for {s}: {t}", .{ argv[0], e });
                exited = true;
                break :update;
            },
            error.OutOfMemory, error.Canceled, error.MakeFailed => |e| return e,
            else => |e| return s.fail(maker, "zig child process monitoring failed: {t}", .{e}),
        };

        if (s.result_error_bundle.errorMessageCount() > 0)
            return s.fail(maker, "{d} compilation errors", .{s.result_error_bundle.errorMessageCount()});

        if (s.result_error_msgs.items.len > 0 and result == null) {
            // Crash detected.
            const term = zp.child.wait(io) catch |e| {
                return s.fail(maker, "unable to wait for {s}: {t}", .{ argv[0], e });
            };
            s.result_peak_rss = zp.child.resource_usage_statistics.getMaxRss() orelse 0;
            exited = true;
            try handleChildProcessTerm(s, maker, term);
            return error.MakeFailed;
        }

        return result;
    }
    assert(argv.len != 0);

    try handleChildProcUnsupported(s, maker);
    try graph.handleVerbose(null, null, argv);

    const zp = try gpa.create(ZigProcess);
    defer if (!watch) gpa.destroy(zp);

    zp.child = std.process.spawn(io, .{
        .argv = argv,
        .environ_map = &graph.environ_map,
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
        .request_resource_usage_statistics = true,
        .progress_node = prog_node,
    }) catch |err| return s.fail(maker, "failed to spawn zig compiler {s}: {t}", .{ argv[0], err });

    zp.multi_reader.init(gpa, io, zp.multi_reader_buffer.toStreams(), &.{
        zp.child.stdout.?, zp.child.stderr.?,
    });
    if (watch) s.extended.compile.zig_process = zp;
    defer if (!watch) zp.deinit(io);

    const result = result: {
        defer if (watch) zp.saveState(prog_node);
        break :result zigProcessUpdate(step_index, maker, zp, watch) catch |err| switch (err) {
            error.OutOfMemory, error.Canceled, error.MakeFailed => |e| return e,
            else => |e| return s.fail(maker, "zig child process monitoring failed: {t}", .{e}),
        };
    };

    if (!watch) {
        // Send EOF to stdin.
        zp.child.stdin.?.close(io);
        zp.child.stdin = null;

        const term = zp.child.wait(io) catch |err| {
            return s.fail(maker, "unable to wait for {s}: {t}", .{ argv[0], err });
        };
        s.result_peak_rss = zp.child.resource_usage_statistics.getMaxRss() orelse 0;

        // Special handling for compile step that is expecting compile errors.
        const conf = &maker.scanned_config.configuration;
        if (term == .exited) switch (step_index.ptr(conf).extended.get(conf.extra)) {
            .compile => |compile| if (compile.flags4.expect_errors != .none) {
                // Note that the exit code may be 0 in this case due to the
                // compiler server protocol.
                return error.NeedCompileErrorCheck;
            },
            else => {},
        };
        try handleChildProcessTerm(s, maker, term);
    }

    if (s.result_error_bundle.errorMessageCount() > 0) {
        return s.fail(maker, "{d} compilation errors", .{s.result_error_bundle.errorMessageCount()});
    }

    return result;
}

fn zigProcessUpdate(step_index: Configuration.Step.Index, maker: *Maker, zp: *ZigProcess, watch: bool) !?Path {
    const s = maker.stepByIndex(step_index);
    const gpa = maker.gpa;
    const graph = maker.graph;
    const arena = graph.arena; // TODO don't leak into the process arena
    const io = graph.io;

    const start_ts = Io.Clock.awake.now(io);

    try sendMessage(io, zp.child.stdin.?, .update);
    if (!watch) try sendMessage(io, zp.child.stdin.?, .exit);

    var result: ?Path = null;
    var eos_err: error{EndOfStream}!void = {};

    const stdout = zp.multi_reader.fileReader(0);

    while (true) {
        const Header = std.zig.Server.Message.Header;
        const header = stdout.interface.takeStruct(Header, .little) catch |err| switch (err) {
            error.EndOfStream => break,
            error.ReadFailed => return stdout.err.?,
        };
        const body = stdout.interface.take(header.bytes_len) catch |err| switch (err) {
            error.EndOfStream => |e| {
                // Better to report the crash with stderr below, but we set
                // this in case the child exits successfully while violating
                // this protocol.
                eos_err = e;
                break;
            },
            error.ReadFailed => return stdout.err.?,
        };
        switch (header.tag) {
            .zig_version => {
                if (!maker.dump_compile_step_info) if (!std.mem.eql(u8, builtin.zig_version_string, body)) {
                    return s.fail(
                        maker,
                        "zig version mismatch build runner vs compiler: '{s}' vs '{s}'",
                        .{ builtin.zig_version_string, body },
                    );
                };
            },
            .error_bundle => {
                s.result_error_bundle = try std.zig.Server.allocErrorBundle(gpa, body);
                // This message indicates the end of the update.
                if (watch) break;
            },
            .emit_digest => {
                const EmitDigest = std.zig.Server.Message.EmitDigest;
                const emit_digest: *align(1) const EmitDigest = @ptrCast(body);
                s.result_cached = emit_digest.flags.cache_hit;
                const digest = body[@sizeOf(EmitDigest)..][0..Cache.bin_digest_len];
                result = .{
                    .root_dir = graph.local_cache_root,
                    .sub_path = try arena.dupe(u8, "o" ++ Dir.path.sep_str ++ Cache.binToHex(digest.*)),
                };
            },
            .file_system_inputs => {
                clearWatchInputs(s, maker);
                const conf = &maker.scanned_config.configuration;
                const conf_step = step_index.ptr(conf);
                var it = std.mem.splitScalar(u8, body, 0);
                while (it.next()) |prefixed_path| {
                    const prefix_index: std.zig.Server.Message.PathPrefix = @enumFromInt(prefixed_path[0] - 1);
                    const sub_path = try arena.dupe(u8, prefixed_path[1..]);
                    const sub_path_dirname = Dir.path.dirname(sub_path) orelse "";
                    switch (prefix_index) {
                        .cwd => {
                            const path: Path = .{
                                .root_dir = .cwd(),
                                .sub_path = sub_path_dirname,
                            };
                            try addWatchInputFromPath(s, maker, path, Dir.path.basename(sub_path));
                        },
                        .zig_lib => zl: {
                            switch (conf_step.extended.get(conf.extra)) {
                                .compile => |compile| if (compile.zig_lib_dir.value) |zig_lib_dir| {
                                    const resolved = try maker.resolveLazyPathIndex(arena, zig_lib_dir, step_index);
                                    const appended = try resolved.join(arena, sub_path);
                                    try addWatchInputPath(s, maker, appended);
                                    break :zl;
                                },
                                else => {},
                            }
                            const path: Path = .{
                                .root_dir = graph.zig_lib_directory,
                                .sub_path = sub_path_dirname,
                            };
                            try addWatchInputFromPath(s, maker, path, Dir.path.basename(sub_path));
                        },
                        .local_cache => {
                            const path: Path = .{
                                .root_dir = graph.local_cache_root,
                                .sub_path = sub_path_dirname,
                            };
                            try addWatchInputFromPath(s, maker, path, Dir.path.basename(sub_path));
                        },
                        .global_cache => {
                            const path: Path = .{
                                .root_dir = graph.global_cache_root,
                                .sub_path = sub_path_dirname,
                            };
                            try addWatchInputFromPath(s, maker, path, Dir.path.basename(sub_path));
                        },
                    }
                }
            },
            .time_report => if (maker.web_server) |*ws| {
                const TimeReport = std.zig.Server.Message.TimeReport;
                const tr: *align(1) const TimeReport = @ptrCast(body[0..@sizeOf(TimeReport)]);
                ws.updateTimeReportCompile(.{
                    .compile_step = step_index,
                    .use_llvm = tr.flags.use_llvm,
                    .stats = tr.stats,
                    .ns_total = @intCast(start_ts.untilNow(io, .awake).toNanoseconds()),
                    .llvm_pass_timings_len = tr.llvm_pass_timings_len,
                    .files_len = tr.files_len,
                    .decls_len = tr.decls_len,
                    .trailing = body[@sizeOf(TimeReport)..],
                });
            },
            else => {}, // ignore other messages
        }
    }

    s.result_duration_ns = @intCast(start_ts.untilNow(io, .awake).toNanoseconds());

    const stderr_contents = zp.multi_reader.reader(1).buffered();
    if (stderr_contents.len > 0) {
        try s.result_error_msgs.append(arena, try arena.dupe(u8, stderr_contents));
    }

    try eos_err;

    return result;
}

pub fn getZigProcess(s: *Step) ?*ZigProcess {
    return switch (s.extended) {
        .compile => |*compile| compile.zig_process,
        else => null,
    };
}

fn sendMessage(io: Io, file: Io.File, tag: std.zig.Client.Message.Tag) !void {
    const header: std.zig.Client.Message.Header = .{
        .tag = tag,
        .bytes_len = 0,
    };
    var w = file.writer(io, &.{});
    w.interface.writeStruct(header, .little) catch |err| switch (err) {
        error.WriteFailed => return w.err.?,
    };
}

pub inline fn handleChildProcUnsupported(s: *Step, maker: *Maker) FailError!void {
    if (!std.process.can_spawn)
        return s.fail(maker, "unable to spawn process: host cannot spawn child processes", .{});
}

pub fn handleChildProcessTerm(s: *Step, maker: *Maker, term: std.process.Child.Term) FailError!void {
    if (!term.success()) return s.fail(maker, "process {f}", .{term});
}

/// Prefer `cacheHitAndWatch` unless you already added watch inputs
/// separately from using the cache system.
pub fn cacheHit(s: *Step, maker: *Maker, man: *Cache.Manifest) !bool {
    s.result_cached = man.hit() catch |err| return failWithCacheError(s, maker, man, err);
    return s.result_cached;
}

/// Clears previous watch inputs, if any, and then populates watch inputs from
/// the full set of files picked up by the cache manifest.
///
/// Must be accompanied with `writeManifestAndWatch`.
pub fn cacheHitAndWatch(s: *Step, maker: *Maker, man: *Cache.Manifest) !bool {
    const is_hit = man.hit() catch |err| return failWithCacheError(s, maker, man, err);
    s.result_cached = is_hit;
    // The above call to hit() populates the manifest with files, so in case of
    // a hit, we need to populate watch inputs.
    if (is_hit) try setWatchInputsFromManifest(s, maker, man);
    return is_hit;
}

fn failWithCacheError(
    s: *Step,
    maker: *Maker,
    man: *const Cache.Manifest,
    err: Cache.Manifest.HitError,
) error{ OutOfMemory, Canceled, MakeFailed } {
    switch (err) {
        error.CacheCheckFailed => switch (man.diagnostic) {
            .none => unreachable,
            .manifest_create, .manifest_read, .manifest_lock => |e| return s.fail(maker, "failed checking cache: {t} {t}", .{
                man.diagnostic, e,
            }),
            .file_open, .file_stat, .file_read, .file_hash => |op| {
                const pp = man.files.keys()[op.file_index].prefixed_path;
                const prefix = man.cache.prefixes()[pp.prefix].path orelse "";
                return s.fail(maker, "failed checking cache: {s}{c}{s} {t} {t}", .{
                    prefix, Dir.path.sep, pp.sub_path, man.diagnostic, op.err,
                });
            },
        },
        error.OutOfMemory, error.Canceled => |e| return e,
        error.InvalidFormat => return s.fail(maker, "failed checking cache: invalid manifest file format", .{}),
    }
}

/// Prefer `writeManifestAndWatch` unless you already added watch inputs
/// separately from using the cache system.
pub fn writeManifest(s: *Step, maker: *Maker, man: *Cache.Manifest) !void {
    if (s.test_results.isSuccess()) {
        man.writeManifest() catch |err| switch (err) {
            error.Canceled => |e| return e,
            else => |e| try s.addError(maker, "failed writing cache manifest: {t}", .{e}),
        };
    }
}

/// Clears previous watch inputs, if any, and then populates watch inputs from
/// the full set of files picked up by the cache manifest.
///
/// Must be accompanied with `cacheHitAndWatch`.
pub fn writeManifestAndWatch(s: *Step, maker: *Maker, man: *Cache.Manifest) !void {
    try writeManifest(s, maker, man);
    try setWatchInputsFromManifest(s, maker, man);
}

fn setWatchInputsFromManifest(s: *Step, maker: *Maker, man: *Cache.Manifest) !void {
    const graph = maker.graph;
    const arena = graph.arena; // TODO don't leak into process arena
    const prefixes = man.cache.prefixes();
    clearWatchInputs(s, maker);
    for (man.files.keys()) |file| {
        // The file path data is freed when the cache manifest is cleaned up at the end of `make`.
        const sub_path = try arena.dupe(u8, file.prefixed_path.sub_path);
        try addWatchInputFromPath(s, maker, .{
            .root_dir = prefixes[file.prefixed_path.prefix],
            .sub_path = Dir.path.dirname(sub_path) orelse "",
        }, Dir.path.basename(sub_path));
    }
}

/// For steps that have a single input that never changes when re-running `make`.
pub fn singleUnchangingWatchInput(step: *Step, maker: *Maker, arena: Allocator, lazy_path: LazyPath) Allocator.Error!void {
    if (!step.inputs.populated()) try step.addWatchInput(maker, arena, lazy_path);
}

pub fn clearWatchInputs(step: *Step, maker: *Maker) void {
    step.inputs.clear(maker.gpa);
}

/// Places a *file* dependency on the path.
pub fn addWatchInput(step: *Step, maker: *Maker, arena: Allocator, lazy_file: LazyPath) Allocator.Error!void {
    const conf = &maker.scanned_config.configuration;
    switch (lazy_file) {
        .source_path => |source_path| {
            const sub_path = source_path.sub_path.slice(conf);
            const pkg_path = try maker.packagePath(arena, source_path.owner, sub_path);
            try addWatchInputPath(step, maker, pkg_path);
        },
        .relative => |relative| {
            const resolved_path = try maker.relativePath(arena, relative);
            try addWatchInputPath(step, maker, resolved_path);
        },
        // Nothing to watch because this dependency edge is modeled instead via `dependants`.
        .generated => {},
    }
}

/// Any changes inside the directory will trigger invalidation.
///
/// See also `addDirectoryWatchInputFromPath` which takes a `Path` instead.
///
/// Paths derived from this directory should also be manually added via
/// `addDirectoryWatchInputFromPath` if and only if this function returns
/// `true`.
pub fn addDirectoryWatchInput(step: *Step, maker: *Maker, lazy_directory: LazyPath) Allocator.Error!bool {
    const graph = maker.graph;
    const arena = graph.arena; // TODO don't leak into the process arena
    switch (lazy_directory) {
        .source_path => |source_path| {
            const conf = &maker.scanned_config.configuration;
            const sub_path = source_path.sub_path.slice(conf);
            const pkg_path = try maker.packagePath(arena, source_path.owner, sub_path);
            try addDirectoryWatchInputFromPath(step, maker, pkg_path);
        },
        .relative => |relative| {
            const resolved_path = try maker.relativePath(arena, relative);
            try addDirectoryWatchInputFromPath(step, maker, resolved_path);
        },
        // Nothing to watch because this dependency edge is modeled instead via `dependants`.
        .generated => return false,
    }
    return true;
}

/// Any changes inside the directory will trigger invalidation.
///
/// See also `addDirectoryWatchInput` which takes a `LazyPath` instead.
///
/// This function should only be called when it has been verified that the
/// dependency on `path` is not already accounted for by a `Step` dependency.
/// In other words, before calling this function, first check that the
/// `LazyPath` which this `path` is derived from is not `generated`.
pub fn addDirectoryWatchInputFromPath(step: *Step, maker: *Maker, path: Path) !void {
    return addWatchInputFromPath(step, maker, path, ".");
}

fn addWatchInputPath(step: *Step, maker: *Maker, path: Path) Allocator.Error!void {
    return addWatchInputFromPath(step, maker, .{
        .root_dir = path.root_dir,
        .sub_path = Dir.path.dirname(path.sub_path) orelse "",
    }, Dir.path.basename(path.sub_path));
}

fn addWatchInputFromPath(step: *Step, maker: *Maker, directory: Path, basename: []const u8) Allocator.Error!void {
    const gpa = maker.gpa;
    const gop = try step.inputs.table.getOrPut(gpa, directory);
    if (!gop.found_existing) gop.value_ptr.* = .empty;
    try gop.value_ptr.append(gpa, basename);
}

fn oomWrap(s: *Step, result: error{OutOfMemory}!void) void {
    result catch {
        s.result_oom = true;
    };
}

pub fn clearResultStderr(step: *Step, gpa: Allocator) void {
    if (step.result_stderr.len != 0) {
        gpa.free(step.result_stderr);
        step.result_stderr = "";
    }
}

pub fn setResultStderr(step: *Step, gpa: Allocator, bytes: []const u8) Allocator.Error!void {
    takeResultStderr(step, gpa, try gpa.dupe(u8, bytes));
}

pub fn takeResultStderr(step: *Step, gpa: Allocator, owned: []const u8) void {
    clearResultStderr(step, gpa);
    step.result_stderr = owned;
}
