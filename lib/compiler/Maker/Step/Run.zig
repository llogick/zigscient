const Run = @This();

const builtin = @import("builtin");

const std = @import("std");
const Cache = std.Build.Cache;
const Configuration = std.Build.Configuration;
const Dir = std.Io.Dir;
const EnvMap = std.process.Environ.Map;
const Io = std.Io;
const Path = std.Build.Cache.Path;
const assert = std.debug.assert;
const mem = std.mem;
const process = std.process;
const Allocator = std.mem.Allocator;

const Step = @import("../Step.zig");
const Maker = @import("../../Maker.zig");
const Fuzz = @import("../../Maker/Fuzz.zig");

/// If this is a Zig unit test binary, this tracks the names of the unit
/// tests that are also fuzz tests. Indexes cannot be used as they may
/// change between reruns.
fuzz_tests: std.ArrayList([]const u8) = .empty,
cached_test_metadata: ?CachedTestMetadata = null,

/// Populated during the fuzz phase if this run step corresponds to a unit test
/// executable that contains fuzz tests.
rebuilt_executable: ?Path = null,

pub fn make(
    run: *Run,
    run_index: Configuration.Step.Index,
    maker: *Maker,
    progress_node: std.Progress.Node,
) Step.ExtendedMakeError!void {
    const graph = maker.graph;
    const gpa = maker.gpa;
    const step = maker.stepByIndex(run_index);
    const io = graph.io;
    const conf = &maker.scanned_config.configuration;
    const conf_step = run_index.ptr(conf);
    const conf_run = conf_step.extended.get(conf.extra).run;
    const cache_root = graph.local_cache_root;

    var arena_allocator: std.heap.ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    var argv_list: std.ArrayList([]const u8) = .empty;
    defer argv_list.deinit(gpa);

    var output_placeholders: std.ArrayList(IndexedOutput) = .empty;
    defer output_placeholders.deinit(gpa);

    var man = graph.cache.obtain();
    defer man.deinit();

    if (conf_run.environ_map.value) |environ_map_index| {
        const environ_map = environ_map_index.get(conf);
        for (environ_map.keys.slice(conf), environ_map.values.slice(conf)) |key, value| {
            man.hash.addBytesZ(key.slice(conf));
            man.hash.addBytesZ(value.slice(conf));
        }
    }

    for (conf_run.preopen_names.slice, conf_run.preopen_paths.slice) |name, path| {
        man.hash.addBytesZ(name.slice(conf));
        const cwd_path = try maker.resolveLazyPathIndex(arena, path, run_index);
        man.hash.addBytes(try cwd_path.toString(arena));
    }

    man.hash.add(graph.fuzzing);
    man.hash.add(conf_run.flags.color);
    man.hash.add(conf_run.flags.disable_zig_progress);

    var any_dep_files = false;
    var any_output_args = false;
    var any_cli_positionals = false;

    for (conf_run.args.slice) |arg_index| {
        const arg = arg_index.get(conf);
        try argv_list.ensureUnusedCapacity(gpa, 1);
        switch (arg.flags.tag) {
            .string => {
                const prefix = arg.prefix.value.?.slice(conf);
                argv_list.appendAssumeCapacity(prefix);
                man.hash.addBytesZ(prefix);
            },
            .path_file => {
                const prefix = if (arg.prefix.value) |p| p.slice(conf) else "";
                const suffix = if (arg.suffix.value) |p| p.slice(conf) else "";
                const file_path = try maker.resolveLazyPathIndex(arena, arg.path.value.?, run_index);
                argv_list.appendAssumeCapacity(try mem.concat(arena, u8, &.{
                    prefix, try convertPathArg(arena, run_index, maker, file_path, arg.flags.make_absolute), suffix,
                }));
                man.hash.add(arg.flags.make_absolute);
                man.hash.addBytesZ(prefix);
                man.hash.addBytesZ(suffix);
                _ = try man.addFilePath(file_path, null);
            },
            .path_directory => {
                const prefix = if (arg.prefix.value) |p| p.slice(conf) else "";
                const suffix = if (arg.suffix.value) |p| p.slice(conf) else "";
                const file_path = try maker.resolveLazyPathIndex(arena, arg.path.value.?, run_index);
                const resolved_arg = try mem.concat(arena, u8, &.{
                    prefix, try convertPathArg(arena, run_index, maker, file_path, arg.flags.make_absolute), suffix,
                });
                argv_list.appendAssumeCapacity(resolved_arg);
                man.hash.add(arg.flags.make_absolute);
                man.hash.addBytes(resolved_arg);
            },
            .file_content => {
                const prefix = if (arg.prefix.value) |p| p.slice(conf) else "";
                const suffix = if (arg.suffix.value) |p| p.slice(conf) else "";
                const file_path = try maker.resolveLazyPathIndex(arena, arg.path.value.?, run_index);

                var result: std.Io.Writer.Allocating = .init(arena);
                result.writer.writeAll(prefix) catch return error.OutOfMemory;

                const file = file_path.root_dir.handle.openFile(io, file_path.sub_path, .{}) catch |err|
                    return step.fail(maker, "unable to open input file {f}: {t}", .{ file_path, err });
                defer file.close(io);

                var file_reader = file.reader(io, &.{});
                _ = file_reader.interface.streamRemaining(&result.writer) catch |err| switch (err) {
                    error.ReadFailed => switch (file_reader.err.?) {
                        error.Canceled => |e| return e,
                        else => |e| return step.fail(maker, "failed to read from {f}: {t}", .{ file_path, e }),
                    },
                    error.WriteFailed => return error.OutOfMemory,
                };
                result.writer.writeAll(suffix) catch return error.OutOfMemory;

                argv_list.appendAssumeCapacity(result.written());
                man.hash.addBytesZ(prefix);
                man.hash.addBytesZ(suffix);
                _ = try man.addFilePath(file_path, null);
            },
            .artifact => {
                const prefix = if (arg.prefix.value) |p| p.slice(conf) else "";
                const suffix = if (arg.suffix.value) |p| p.slice(conf) else "";
                const producer_index = arg.producer.value.?;
                const producer_step = producer_index.ptr(conf);
                const producer = producer_step.extended.get(conf.extra).compile;
                const producer_make_comp_step = maker.stepByIndex(producer_index);
                const producer_make_comp = &producer_make_comp_step.extended.compile;

                const file_path = producer_make_comp.installed_path orelse maker.generatedPath(producer.generated_bin.value.?).*;

                argv_list.appendAssumeCapacity(try mem.concat(arena, u8, &.{
                    prefix, try convertPathArg(arena, run_index, maker, file_path, arg.flags.make_absolute), suffix,
                }));

                man.hash.add(arg.flags.make_absolute);
                man.hash.addBytesZ(prefix);
                man.hash.addBytesZ(suffix);
                _ = try man.addFilePath(file_path, null);
            },
            .output_file, .output_directory => {
                const prefix = if (arg.prefix.value) |p| p.slice(conf) else "";
                const suffix = if (arg.suffix.value) |p| p.slice(conf) else "";
                const basename = arg.basename.value.?.slice(conf);

                man.hash.add(arg.flags.make_absolute);
                man.hash.addBytesZ(prefix);
                man.hash.addBytesZ(basename);
                man.hash.addBytesZ(suffix);
                man.hash.add(arg.flags.dep_file);

                any_dep_files = any_dep_files or arg.flags.dep_file;
                any_output_args = true;

                // Add a placeholder into the argument list because we need the
                // manifest hash to be updated with all arguments before the
                // object directory is computed.
                try output_placeholders.append(gpa, .{
                    .index = @intCast(argv_list.items.len),
                    .arg_index = arg_index,
                });
                argv_list.items.len += 1;
            },
            .passthru => {
                any_cli_positionals = true;
                if (maker.run_args) |run_args| {
                    try argv_list.appendSlice(gpa, run_args);
                    man.hash.addListOfBytes(run_args);
                }
            },
        }
    }

    man.hash.add(conf_run.flags.test_runner_mode);
    if (conf_run.flags.test_runner_mode) {
        const cache_dir_string = try convertPathArg(arena, run_index, maker, .{ .root_dir = cache_root }, false);

        try argv_list.ensureUnusedCapacity(gpa, 3);
        argv_list.appendAssumeCapacity(try arena.print("--cache-dir={s}", .{cache_dir_string}));
        argv_list.appendAssumeCapacity(try arena.print("--seed=0x{x}", .{graph.random_seed}));
        argv_list.appendAssumeCapacity("--listen=-");
    }

    switch (conf_run.stdin.u) {
        .bytes => |bytes| {
            man.hash.addBytes(bytes.slice(conf));
        },
        .lazy_path => |lazy_path| {
            const file_path = try maker.resolveLazyPathIndex(arena, lazy_path, run_index);
            _ = try man.addFilePath(file_path, null);
        },
        .none => {},
    }

    if (conf_run.captured_stdout.value) |captured| {
        man.hash.addBytes(captured.basename.slice(conf));
        man.hash.add(conf_run.flags.stdout_trim_whitespace);
    }

    if (conf_run.captured_stderr.value) |captured| {
        man.hash.addBytes(captured.basename.slice(conf));
        man.hash.add(conf_run.flags.stderr_trim_whitespace);
    }

    switch (conf_run.flags.stdio) {
        .infer_from_args, .inherit, .zig_test => {},
        .check => {
            man.hash.addBytes(if (conf_run.expect_stderr_exact.value) |bytes| bytes.slice(conf) else "");
            man.hash.addBytes(if (conf_run.expect_stdout_exact.value) |bytes| bytes.slice(conf) else "");
            for (conf_run.expect_stderr_match.slice) |bytes| man.hash.addBytes(bytes.slice(conf));
            for (conf_run.expect_stdout_match.slice) |bytes| man.hash.addBytes(bytes.slice(conf));
            man.hash.add(conf_run.flags2.expect_term_status);
            man.hash.addOptional(conf_run.expect_term_value.value);
        },
    }

    for (conf_run.file_inputs.slice) |lazy_path| {
        const file_path = try maker.resolveLazyPathIndex(arena, lazy_path, run_index);
        _ = try man.addFilePath(file_path, null);
    }

    if (conf_run.cwd.value) |lazy_path| {
        const cwd_path = try maker.resolveLazyPathIndex(arena, lazy_path, run_index);
        _ = man.hash.addBytes(try cwd_path.toString(arena));
    }

    // Whether the Run step has side effects *other than* updating the output arguments.
    // When fuzzing we need to always run the test runner to populate fuzz_tests.
    const has_side_effects = graph.fuzzing or conf_run.flags.has_side_effects or any_cli_positionals or
        switch (conf_run.flags.stdio) {
            .infer_from_args => !any_output_args and
                conf_run.captured_stdout.value == null and
                conf_run.captured_stderr.value == null,
            .inherit => true,
            .check, .zig_test => false,
        };

    if (!has_side_effects and try step.cacheHitAndWatch(maker, &man)) {
        // Cache hit; skip running command.
        const digest = man.final();
        try populateGeneratedStdIo(maker, &conf_run, cache_root, &digest);
        try populateGeneratedPaths(maker, output_placeholders.items, cache_root, &digest);
        step.result_cached = true;
        return;
    }

    if (!any_dep_files) {
        // We already know the final output paths; use them directly.
        const digest = if (has_side_effects) man.hash.final() else man.final();
        const output_dir_path = "o" ++ Dir.path.sep_str ++ &digest;
        try populateGeneratedStdIo(maker, &conf_run, cache_root, &digest);
        try populateGeneratedPathsCreateDirs(arena, run_index, maker, output_dir_path, output_placeholders.items, argv_list.items);
        try runCommand(arena, run, run_index, maker, progress_node, argv_list.items, has_side_effects, output_dir_path, null);
        if (!has_side_effects) try step.writeManifestAndWatch(maker, &man);
        return;
    }

    // We do not know the final output paths yet; use temporary directory to run the command.
    var rand_int: u64 = undefined;
    io.random(@ptrCast(&rand_int));
    const tmp_dir_path = "tmp" ++ Dir.path.sep_str ++ std.fmt.hex(rand_int);

    try populateGeneratedPathsCreateDirs(arena, run_index, maker, tmp_dir_path, output_placeholders.items, argv_list.items);
    try runCommand(arena, run, run_index, maker, progress_node, argv_list.items, has_side_effects, tmp_dir_path, null);

    for (output_placeholders.items) |placeholder| {
        const arg = placeholder.arg_index.get(conf);
        switch (arg.flags.tag) {
            .output_file => if (arg.flags.dep_file) {
                const generated_path = maker.generatedPath(arg.generated.value.?).*;
                const result = if (has_side_effects)
                    man.addDepFile(generated_path.root_dir.handle, generated_path.sub_path)
                else
                    man.addDepFilePost(generated_path.root_dir.handle, generated_path.sub_path);
                result catch |err| switch (err) {
                    error.OutOfMemory, error.Canceled => |e| return e,
                    else => |e| return step.fail(maker, "failed adding to cache the file {f}: {t}", .{
                        generated_path, e,
                    }),
                };
            },
            .output_directory => continue,
            else => unreachable,
        }
    }

    const digest = if (has_side_effects) man.hash.final() else man.final();

    const any_output = output_placeholders.items.len > 0 or
        conf_run.captured_stdout.value != null or conf_run.captured_stderr.value != null;

    if (any_output) {
        // Rename into place.
        const tmp_path: Path = .{ .root_dir = cache_root, .sub_path = tmp_dir_path };
        const dst_path: Path = .{ .root_dir = cache_root, .sub_path = "o" ++ Dir.path.sep_str ++ &digest };
        Dir.rename(
            tmp_path.root_dir.handle,
            tmp_path.sub_path,
            dst_path.root_dir.handle,
            dst_path.sub_path,
            io,
        ) catch |err| switch (err) {
            error.DirNotEmpty => {
                dst_path.root_dir.handle.deleteTree(io, dst_path.sub_path) catch |del_err|
                    return step.fail(maker, "failed to remove tree {f}: {t}", .{ dst_path, del_err });

                Dir.rename(
                    tmp_path.root_dir.handle,
                    tmp_path.sub_path,
                    dst_path.root_dir.handle,
                    dst_path.sub_path,
                    io,
                ) catch |retry_err| return step.fail(maker, "failed to rename directory {f} to {f}: {t}", .{
                    tmp_path, dst_path, retry_err,
                });
            },
            else => return step.fail(maker, "failed to rename directory {f} to {f}: {t}", .{
                tmp_path, dst_path, err,
            }),
        };
    }

    if (!has_side_effects) try step.writeManifestAndWatch(maker, &man);

    try populateGeneratedStdIo(maker, &conf_run, cache_root, &digest);
    try populateGeneratedPaths(maker, output_placeholders.items, cache_root, &digest);

    // The utility functions that spawn the child process must unconditionally allocate
    // the failed command because at that point it is not known whether the step will
    // pass or fail based on the process termination. Here we free the memory since
    // the step has succeeded.
    step.clearFailedCommand(gpa);
}

/// Reads stdout of a Zig test process until a termination condition is reached:
/// * A write fails, indicating the child unexpectedly closed stdin
/// * A test (or a response from the test runner) times out
/// * The wait fails, indicating the child closed stdout and stderr
fn waitZigTest(
    arena: Allocator,
    run: *Run,
    run_index: Configuration.Step.Index,
    maker: *Maker,
    child: *process.Child,
    progress_node: std.Progress.Node,
    multi_reader: *Io.File.MultiReader,
    opt_metadata: *?TestMetadata,
    results: *Step.TestResults,
) !union(enum) {
    write_failed: anyerror,
    no_poll: struct {
        active_test_index: ?u32,
        ns_elapsed: u64,
    },
    timeout: struct {
        active_test_index: ?u32,
        ns_elapsed: u64,
    },
} {
    const graph = maker.graph;
    const gpa = maker.gpa;
    const io = graph.io;
    const step = maker.stepByIndex(run_index);

    var sub_prog_node: ?std.Progress.Node = null;
    defer if (sub_prog_node) |n| n.end();

    if (opt_metadata.*) |*md| {
        // Previous unit test process died or was killed; we're continuing where it left off
        requestNextTest(io, child.stdin.?, md, &sub_prog_node) catch |err| return .{ .write_failed = err };
    } else {
        // Running unit tests normally
        run.fuzz_tests.clearRetainingCapacity();
        sendMessage(io, child.stdin.?, .query_test_metadata) catch |err| return .{ .write_failed = err };
    }

    var active_test_index: ?u32 = null;

    var last_update: Io.Clock.Timestamp = .now(io, .awake);

    // This timeout is used when we're waiting on the test runner itself rather than a user-specified
    // test. For instance, if the test runner leaves this much time between us requesting a test to
    // start and it acknowledging the test starting, we terminate the child and raise an error. This
    // *should* never happen, but could in theory be caused by some very unlucky IB in a test.
    const response_timeout: Io.Clock.Duration = t: {
        const ns = @max(maker.unit_test_timeout_ns orelse 0, 60 * std.time.ns_per_s);
        break :t .{ .clock = .awake, .raw = .fromNanoseconds(ns) };
    };
    const test_timeout: ?Io.Clock.Duration = if (maker.unit_test_timeout_ns) |ns| .{
        .clock = .awake,
        .raw = .fromNanoseconds(ns),
    } else null;

    const stdout = multi_reader.reader(0);
    const stderr = multi_reader.reader(1);
    const Header = std.zig.Server.Message.Header;

    while (true) {
        const timeout: Io.Timeout = t: {
            const opt_duration = if (active_test_index == null) response_timeout else test_timeout;
            const duration = opt_duration orelse break :t .none;
            break :t .{ .deadline = last_update.addDuration(duration) };
        };

        // This block is exited when `stdout` contains enough bytes for a `Header`.
        header_ready: {
            if (stdout.buffered().len >= @sizeOf(Header)) {
                // We already have one, no need to poll!
                break :header_ready;
            }

            multi_reader.fill(64, timeout) catch |err| switch (err) {
                error.Timeout => return .{ .timeout = .{
                    .active_test_index = active_test_index,
                    .ns_elapsed = @intCast(last_update.untilNow(io).raw.nanoseconds),
                } },
                error.EndOfStream => return .{ .no_poll = .{
                    .active_test_index = active_test_index,
                    .ns_elapsed = @intCast(last_update.untilNow(io).raw.nanoseconds),
                } },
                else => |e| return e,
            };

            continue;
        }
        // There is definitely a header available now -- read it.
        const header = stdout.takeStruct(Header, .little) catch unreachable;

        while (stdout.buffered().len < header.bytes_len) {
            multi_reader.fill(64, timeout) catch |err| switch (err) {
                error.Timeout => return .{ .timeout = .{
                    .active_test_index = active_test_index,
                    .ns_elapsed = @intCast(last_update.untilNow(io).raw.nanoseconds),
                } },
                error.EndOfStream => return .{ .no_poll = .{
                    .active_test_index = active_test_index,
                    .ns_elapsed = @intCast(last_update.untilNow(io).raw.nanoseconds),
                } },
                else => |e| return e,
            };
        }

        const body = stdout.take(header.bytes_len) catch unreachable;
        var body_r: std.Io.Reader = .fixed(body);
        switch (header.tag) {
            .zig_version => {
                if (!maker.dump_compile_step_info) if (!std.mem.eql(u8, builtin.zig_version_string, body)) return step.fail(
                    maker,
                    "zig version mismatch build runner vs compiler: '{s}' vs '{s}'",
                    .{ builtin.zig_version_string, body },
                );
            },
            .test_metadata => {
                // `metadata` would only be populated if we'd already seen a `test_metadata`, but we
                // only request it once (and importantly, we don't re-request it if we kill and
                // restart the test runner).
                assert(opt_metadata.* == null);

                const tm_hdr = body_r.takeStruct(std.zig.Server.Message.TestMetadata, .little) catch unreachable;
                results.test_count = tm_hdr.tests_len;

                const names = try arena.alloc(u32, results.test_count);
                for (names) |*dest| dest.* = body_r.takeInt(u32, .little) catch unreachable;

                const expected_panic_msgs = try arena.alloc(u32, results.test_count);
                for (expected_panic_msgs) |*dest| dest.* = body_r.takeInt(u32, .little) catch unreachable;

                const string_bytes = body_r.take(tm_hdr.string_bytes_len) catch unreachable;

                progress_node.setEstimatedTotalItems(names.len);
                opt_metadata.* = .{
                    .string_bytes = try arena.dupe(u8, string_bytes),
                    .ns_per_test = try arena.alloc(u64, results.test_count),
                    .names = names,
                    .expected_panic_msgs = expected_panic_msgs,
                    .next_index = 0,
                    .prog_node = progress_node,
                };
                @memset(opt_metadata.*.?.ns_per_test, std.math.maxInt(u64));

                active_test_index = null;
                last_update = .now(io, .awake);

                requestNextTest(io, child.stdin.?, &opt_metadata.*.?, &sub_prog_node) catch |err| return .{ .write_failed = err };
            },
            .test_started => {
                active_test_index = opt_metadata.*.?.next_index - 1;
                last_update = .now(io, .awake);
            },
            .test_results => {
                const md = &opt_metadata.*.?;

                const tr_hdr = body_r.takeStruct(std.zig.Server.Message.TestResults, .little) catch unreachable;
                assert(tr_hdr.index == active_test_index);

                switch (tr_hdr.flags.status) {
                    .pass => {},
                    .skip => results.skip_count +|= 1,
                    .fail => results.fail_count +|= 1,
                }
                const leak_count = tr_hdr.flags.leak_count;
                const log_err_count = tr_hdr.flags.log_err_count;
                results.leak_count +|= leak_count;
                results.log_err_count +|= log_err_count;

                if (tr_hdr.flags.fuzz) try run.fuzz_tests.append(gpa, md.testName(tr_hdr.index));

                if (tr_hdr.flags.status == .fail) {
                    const name = md.testName(tr_hdr.index);
                    const stderr_bytes = std.mem.trim(u8, stderr.buffered(), "\n");
                    stderr.tossBuffered();
                    if (stderr_bytes.len == 0) {
                        try step.addError(maker, "'{s}' failed without output", .{name});
                    } else {
                        try step.addError(maker, "'{s}' failed:\n{s}", .{ name, stderr_bytes });
                    }
                } else if (leak_count > 0) {
                    const name = md.testName(tr_hdr.index);
                    const stderr_bytes = std.mem.trim(u8, stderr.buffered(), "\n");
                    stderr.tossBuffered();
                    try step.addError(maker, "'{s}' leaked {d} allocations:\n{s}", .{ name, leak_count, stderr_bytes });
                } else if (log_err_count > 0) {
                    const name = md.testName(tr_hdr.index);
                    const stderr_bytes = std.mem.trim(u8, stderr.buffered(), "\n");
                    stderr.tossBuffered();
                    try step.addError(maker, "'{s}' logged {d} errors:\n{s}", .{ name, log_err_count, stderr_bytes });
                }

                active_test_index = null;

                const now: Io.Clock.Timestamp = .now(io, .awake);
                md.ns_per_test[tr_hdr.index] = @intCast(last_update.durationTo(now).raw.nanoseconds);
                last_update = now;

                requestNextTest(io, child.stdin.?, md, &sub_prog_node) catch |err| return .{ .write_failed = err };
            },
            else => {}, // ignore other messages
        }
    }
}

const FuzzTestRunner = struct {
    run: *Run,
    run_index: Configuration.Step.Index,
    ctx: FuzzContext,
    coverage_id: ?u64,

    instances: []Instance,
    /// The indexes of this are layed out such that it is effectively an array
    /// of `[instances.len][3]Io.Operation.Storage` of stdin, stdout, stderr.
    batch: Io.Batch,
    /// LIFO. Stream of message bodies trailed by PendingBroadcastFooter.
    pending_broadcasts: std.ArrayList(u8),
    broadcast: std.ArrayList(u8),
    broadcast_undelivered: u32,

    const Instance = struct {
        child: process.Child,
        message: std.ArrayListAligned(u8, .@"4"),
        broadcast_written: usize,
        stderr: std.ArrayList(u8),
        stdin_vec: [1][]u8,
        stdout_vec: [1][]u8,
        stderr_vec: [1][]u8,
        progress_node: std.Progress.Node,

        fn messageHeader(instance: *Instance) InHeader {
            assert(instance.message.items.len >= @sizeOf(InHeader));
            const header_ptr: *InHeader = @ptrCast(instance.message.items);
            var header = header_ptr.*;
            if (std.builtin.Endian.native != .little) {
                std.mem.byteSwapAllFields(InHeader, &header);
            }
            return header;
        }
    };

    const PendingBroadcastFooter = struct {
        from_id: u32,
        body_len: u32,
    };

    const InHeader = std.zig.Server.Message.Header;
    const OutHeader = std.zig.Client.Message.Header;

    const stdin_i = 0;
    const stdout_i = 1;
    const stderr_i = 2;

    fn init(
        run: *Run,
        run_index: Configuration.Step.Index,
        ctx: FuzzContext,
        progress_node: std.Progress.Node,
        spawn_options: process.SpawnOptions,
    ) !FuzzTestRunner {
        const maker = ctx.fuzz.maker;
        const graph = maker.graph;
        const gpa = maker.gpa;
        const io = graph.io;

        const n_instances = switch (ctx.fuzz.mode) {
            .forever => graph.max_jobs orelse @min(
                std.Thread.getCpuCount() catch 1,
                (std.math.maxInt(u32) - 2) / 3,
            ),
            .limit => 1,
        };
        const instances = try gpa.alloc(Instance, n_instances);
        errdefer gpa.free(instances);
        const batch_storage = try gpa.alloc(Io.Operation.Storage, instances.len * 3);
        errdefer gpa.free(batch_storage);

        @memset(instances, .{
            .child = undefined,
            .message = .empty,
            .broadcast_written = undefined,
            .stderr = .empty,
            .stdin_vec = undefined,
            .stdout_vec = undefined,
            .stderr_vec = undefined,
            .progress_node = undefined,
        });
        for (0.., instances) |id, *instance| {
            errdefer for (instances[0..id]) |*spawned| {
                spawned.child.kill(io);
                spawned.progress_node.end();
            };
            instance.child = try process.spawn(io, spawn_options);
            instance.progress_node = progress_node.start("starting fuzzer", 0);
        }

        return .{
            .run = run,
            .run_index = run_index,
            .ctx = ctx,
            .coverage_id = null,

            .instances = instances,
            .batch = .init(batch_storage),
            .pending_broadcasts = .empty,
            .broadcast = .empty,
            .broadcast_undelivered = 0,
        };
    }

    fn deinit(f: *FuzzTestRunner) void {
        const maker = f.ctx.fuzz.maker;
        const run_index = f.run_index;

        const graph = maker.graph;
        const gpa = maker.gpa;
        const io = graph.io;
        const step = maker.stepByIndex(run_index);

        f.batch.cancel(io);
        gpa.free(f.batch.storage);
        var total_rss: usize = 0;
        for (f.instances) |*instance| {
            instance.child.kill(io);
            instance.message.deinit(gpa);
            instance.stderr.deinit(gpa);
            instance.progress_node.end();
            total_rss += instance.child.resource_usage_statistics.getMaxRss() orelse 0;
        }
        step.result_peak_rss = @max(step.result_peak_rss, total_rss);
        gpa.free(f.instances);
    }

    fn startInstances(f: *FuzzTestRunner) !void {
        const maker = f.ctx.fuzz.maker;
        const run_index = f.run_index;
        const run = f.run;

        const graph = maker.graph;
        const io = graph.io;
        const step = maker.stepByIndex(run_index);

        for (0.., f.instances) |id, *instance| {
            const id32: u32 = @intCast(id);
            (switch (f.ctx.fuzz.mode) {
                .forever => sendRunFuzzTestMessage(
                    io,
                    instance.child.stdin.?,
                    run.fuzz_tests.items,
                    .forever,
                    id32,
                ),
                .limit => |limit| sendRunFuzzTestMessage(
                    io,
                    instance.child.stdin.?,
                    run.fuzz_tests.items,
                    .iterations,
                    limit.amount,
                ),
            }) catch |write_err| {
                // The runner unexpectedly closed stdin, which means it crashed during initialization.
                // Clean up everything and wait for the child to exit.
                instance.child.stdin.?.close(io);
                instance.child.stdin = null;
                const term = try instance.child.wait(io);
                return step.fail(
                    maker,
                    "unable to write stdin ({t}); test process unexpectedly {f}",
                    .{ write_err, fmtTerm(term) },
                );
            };

            try f.addStdoutRead(id32, @sizeOf(InHeader));
            try f.addStderrRead(id32);
        }
    }

    fn listen(f: *FuzzTestRunner) !void {
        const maker = f.ctx.fuzz.maker;
        const graph = maker.graph;
        const io = graph.io;

        while (true) {
            try f.batch.awaitConcurrent(io, .none);
            while (f.batch.next()) |completion| {
                const id = completion.index / 3;
                const result = completion.result;
                switch (completion.index % 3) {
                    0 => try f.completeStdinWrite(id, result.file_write_streaming catch |e| switch (e) {
                        // Avoid calling `instanceEos` until EndOfStream is seen with stderr so
                        // that all stderr is collected.
                        error.BrokenPipe => continue,
                        else => |write_e| return write_e,
                    }),
                    1 => try f.completeStdoutRead(id, result.file_read_streaming catch |e| switch (e) {
                        // Avoid calling `instanceEos` until EndOfStream is seen with stderr so
                        // that all stderr is collected.
                        error.EndOfStream => continue,
                        else => |read_e| return read_e,
                    }),
                    2 => try f.completeStderrRead(id, result.file_read_streaming catch |e| switch (e) {
                        error.EndOfStream => return f.instanceEos(id),
                        else => |read_e| return read_e,
                    }),
                    else => unreachable,
                }
            }
        }
    }

    fn completeStdoutRead(f: *FuzzTestRunner, id: u32, n: usize) !void {
        const maker = f.ctx.fuzz.maker;
        const instance = &f.instances[id];
        const run_index = f.run_index;
        const run = f.run;

        const graph = maker.graph;
        const gpa = maker.gpa;
        const io = graph.io;
        const step = maker.stepByIndex(run_index);

        instance.message.items.len += n;
        const total_read = instance.message.items.len;
        if (total_read < @sizeOf(InHeader)) {
            try f.addStdoutRead(id, @sizeOf(InHeader));
            return;
        }

        const header = instance.messageHeader();
        const body = instance.message.items[@sizeOf(InHeader)..];
        if (body.len != header.bytes_len) {
            try f.addStdoutRead(id, @sizeOf(InHeader) + header.bytes_len);
            return;
        }

        switch (header.tag) {
            .zig_version => {
                if (!maker.dump_compile_step_info) if (!std.mem.eql(u8, builtin.zig_version_string, body)) return step.fail(
                    maker,
                    "zig version mismatch build runner vs compiler: '{s}' vs '{s}'",
                    .{ builtin.zig_version_string, body },
                );
            },
            .coverage_id => {
                var body_r: Io.Reader = .fixed(body);
                f.coverage_id = body_r.takeInt(u64, .little) catch unreachable;
                const cumulative_runs = body_r.takeInt(u64, .little) catch unreachable;
                const cumulative_unique = body_r.takeInt(u64, .little) catch unreachable;
                const cumulative_coverage = body_r.takeInt(u64, .little) catch unreachable;

                const fuzz = f.ctx.fuzz;
                fuzz.queue_mutex.lockUncancelable(io);
                defer fuzz.queue_mutex.unlock(io);
                try fuzz.msg_queue.append(gpa, .{ .coverage = .{
                    .id = f.coverage_id.?,
                    .cumulative = .{
                        .runs = cumulative_runs,
                        .unique = cumulative_unique,
                        .coverage = cumulative_coverage,
                    },
                    .run = run_index,
                } });
                fuzz.queue_cond.signal(io);
            },
            .fuzz_start_addr => {
                var body_r: Io.Reader = .fixed(body);
                const fuzz = f.ctx.fuzz;
                const addr = body_r.takeInt(u64, .little) catch unreachable;

                fuzz.queue_mutex.lockUncancelable(io);
                defer fuzz.queue_mutex.unlock(io);
                try fuzz.msg_queue.append(gpa, .{ .entry_point = .{
                    .addr = addr,
                    .coverage_id = f.coverage_id.?,
                } });
                fuzz.queue_cond.signal(io);
            },
            .fuzz_test_change => {
                const test_i = std.mem.readInt(u32, body[0..4], .little);
                instance.progress_node.setName(run.fuzz_tests.items[test_i]);
            },
            .broadcast_fuzz_input => {
                if (f.instances.len == 1) {
                    // No other processes to broadcast to.
                } else if (f.broadcast_undelivered == 0) {
                    try f.instanceBroadcast(id, body);
                } else {
                    const footer: PendingBroadcastFooter = .{
                        .from_id = id,
                        .body_len = @intCast(body.len),
                    };
                    // There is another broadcast in progress so add this one to the queue.
                    const size = @sizeOf(PendingBroadcastFooter) + body.len;
                    try f.pending_broadcasts.ensureUnusedCapacity(gpa, size);
                    f.pending_broadcasts.appendSliceAssumeCapacity(body);
                    f.pending_broadcasts.appendSliceAssumeCapacity(@ptrCast(&footer));
                }
            },
            else => {}, // ignore other messages
        }

        instance.message.clearRetainingCapacity();
        try f.addStdoutRead(id, @sizeOf(InHeader));
    }

    fn completeStderrRead(f: *FuzzTestRunner, id: u32, n: usize) !void {
        const instance = &f.instances[id];
        instance.stderr.items.len += n;
        try f.addStderrRead(id);
    }

    fn completeStdinWrite(f: *FuzzTestRunner, id: u32, n: usize) !void {
        const instance = &f.instances[id];

        instance.broadcast_written += n;
        if (instance.broadcast_written == f.broadcast.items.len) {
            f.broadcast_undelivered -= 1;
            if (f.broadcast_undelivered == 0) {
                try f.broadcastComplete();
            }
        } else {
            f.addStdinWrite(id);
        }
    }

    fn addStdoutRead(f: *FuzzTestRunner, id: u32, end: usize) !void {
        const maker = f.ctx.fuzz.maker;
        const gpa = maker.gpa;
        const instance = &f.instances[id];

        try instance.message.ensureTotalCapacity(gpa, end);
        const start = instance.message.items.len;
        instance.stdout_vec = .{instance.message.allocatedSlice()[start..end]};
        f.batch.addAt(id * 3 + stdout_i, .{ .file_read_streaming = .{
            .file = instance.child.stdout.?,
            .data = &instance.stdout_vec,
        } });
    }

    fn addStderrRead(f: *FuzzTestRunner, id: u32) !void {
        const maker = f.ctx.fuzz.maker;
        const gpa = maker.gpa;
        const instance = &f.instances[id];

        try instance.stderr.ensureUnusedCapacity(gpa, 1);
        instance.stderr_vec = .{instance.stderr.unusedCapacitySlice()};
        f.batch.addAt(id * 3 + stderr_i, .{ .file_read_streaming = .{
            .file = instance.child.stderr.?,
            .data = &instance.stderr_vec,
        } });
    }

    fn addStdinWrite(f: *FuzzTestRunner, id: u32) void {
        const instance = &f.instances[id];

        assert(f.broadcast.items.len != instance.broadcast_written);
        instance.stdin_vec = .{f.broadcast.items[instance.broadcast_written..]};
        f.batch.addAt(id * 3 + stdin_i, .{ .file_write_streaming = .{
            .file = instance.child.stdin.?,
            .data = &instance.stdin_vec,
        } });
    }

    fn instanceEos(f: *FuzzTestRunner, id: u32) !void {
        const maker = f.ctx.fuzz.maker;
        const gpa = maker.gpa;
        const instance = &f.instances[id];
        const run_index = f.run_index;

        const graph = maker.graph;
        const io = graph.io;
        const step = maker.stepByIndex(run_index);

        instance.child.stdin.?.close(io);
        instance.child.stdin = null;
        const term = try instance.child.wait(io);
        if (!termMatches(.{ .exited = 0 }, term)) {
            step.takeResultStderr(gpa, try f.mergedStderr(gpa));
            try f.saveCrash(id, term);
            return step.fail(maker, "test process unexpectedly {f}", .{fmtTerm(term)});
        }
    }

    fn saveCrash(f: *FuzzTestRunner, id: u32, term: process.Child.Term) !void {
        const fuzz = f.ctx.fuzz;
        const run_index = f.run_index;
        const run = f.run;

        const maker = fuzz.maker;
        const step = maker.stepByIndex(run_index);
        const graph = maker.graph;
        const io = graph.io;
        const cache_root = graph.local_cache_root;

        if (f.coverage_id == null) return;

        // Search for the input file corresponding to the instance
        const InputHeader = std.Build.abi.fuzz.MmapInputHeader;
        var in_r_buf: [@sizeOf(InputHeader)]u8 = undefined;
        var in_r: Io.File.Reader = undefined;
        var in_f: Io.File = undefined;
        var in_name_buf: [12]u8 = undefined;
        var in_name: []const u8 = undefined;
        var i: u32 = 0;
        const header: InputHeader = while (true) : ({
            if (i == std.math.maxInt(u32)) return;
            i += 1;
        }) {
            const name_prefix = "f" ++ Dir.path.sep_str ++ "in";
            in_name = std.fmt.bufPrint(&in_name_buf, name_prefix ++ "{x}", .{i}) catch unreachable;
            in_f = cache_root.handle.openFile(io, in_name, .{
                .lock = .exclusive,
                .lock_nonblocking = true,
            }) catch |e| switch (e) {
                error.FileNotFound => return,
                error.WouldBlock => continue, // Can not be from
                // the crashed instance since it is still locked.
                else => return step.fail(maker, "failed to open file '{f}{s}': {t}", .{
                    cache_root, in_name, e,
                }),
            };

            in_r = in_f.readerStreaming(io, &in_r_buf);
            const header = in_r.interface.takeStruct(InputHeader, .little) catch |e| {
                in_f.close(io);
                switch (e) {
                    error.ReadFailed => return step.fail(maker, "failed to read file '{f}{s}': {t}", .{
                        cache_root, in_name, in_r.err.?,
                    }),
                    error.EndOfStream => continue,
                }
            };

            if (header.pc_digest == f.coverage_id.? and
                header.instance_id == id and
                header.test_i < run.fuzz_tests.items.len)
            {
                break header;
            }

            in_f.close(io);
        };
        defer in_f.close(io);

        // Save it to a seperate file
        const crash_name = "f" ++ Dir.path.sep_str ++ "crash";
        const out = cache_root.handle.createFile(io, crash_name, .{
            .lock = .exclusive, // Multiple run steps could have found a crash at the same time
        }) catch |e| return step.fail(maker, "failed to create file '{f}{s}': {t}", .{
            cache_root, crash_name, e,
        });
        defer out.close(io);

        var out_w_buf: [512]u8 = undefined;
        var out_w = out.writerStreaming(io, &out_w_buf);
        _ = out_w.interface.sendFileAll(&in_r, .limited(header.len)) catch |e| switch (e) {
            error.ReadFailed => return step.fail(maker, "failed to read file '{f}{s}': {t}", .{
                cache_root, in_name, in_r.err.?,
            }),
            error.WriteFailed => return step.fail(maker, "failed to write file '{f}{s}': {t}", .{
                cache_root, crash_name, out_w.err.?,
            }),
        };

        return step.fail(maker, "test '{s}' {f}; input saved to '{f}{s}'", .{
            run.fuzz_tests.items[header.test_i],
            fmtTerm(term),
            cache_root,
            crash_name,
        });
    }

    fn instanceBroadcast(f: *FuzzTestRunner, from_id: u32, bytes: []const u8) !void {
        assert(f.instances.len > 1);
        assert(f.broadcast_undelivered == 0); // no other broadcast is progress
        assert(f.broadcast.items.len == 0);
        assert(from_id < f.instances.len);

        const maker = f.ctx.fuzz.maker;
        const gpa = maker.gpa;

        var out_header: OutHeader = .{
            .tag = .new_fuzz_input,
            .bytes_len = @intCast(bytes.len),
        };
        if (std.builtin.Endian.native != .little) {
            std.mem.byteSwapAllFields(OutHeader, &out_header);
        }
        try f.broadcast.ensureTotalCapacity(gpa, @sizeOf(OutHeader) + bytes.len);
        f.broadcast.appendSliceAssumeCapacity(@ptrCast(&out_header));
        f.broadcast.appendSliceAssumeCapacity(bytes);

        f.broadcast_undelivered = @intCast(f.instances.len - 1);
        for (0.., f.instances) |to_id, *instance| {
            if (to_id == from_id) continue;
            instance.broadcast_written = 0;
            f.addStdinWrite(@intCast(to_id));
        }
    }

    fn broadcastComplete(f: *FuzzTestRunner) !void {
        assert(f.instances.len > 1);
        assert(f.broadcast_undelivered == 0);
        f.broadcast.clearRetainingCapacity();

        const pending = &f.pending_broadcasts;
        if (pending.items.len != 0) {
            // Another broadcast is pending; copy it over to `broadcast`

            const footer_len = @sizeOf(PendingBroadcastFooter);
            const footer_bytes = pending.items[pending.items.len - footer_len ..];
            const footer: *align(1) PendingBroadcastFooter = @ptrCast(footer_bytes);
            pending.items.len -= footer_len;

            const body = pending.items[pending.items.len - footer.body_len ..];
            try f.instanceBroadcast(footer.from_id, body);
            pending.items.len -= body.len;
        }
    }

    fn mergedStderr(f: *FuzzTestRunner, gpa: Allocator) Allocator.Error![]const u8 {
        // Collect any available stderr
        while (f.batch.next()) |completion| {
            if (completion.index % 3 != 2) continue;
            const len = completion.result.file_read_streaming catch continue;
            f.instances[completion.index / 3].stderr.items.len += len;
        }

        var stderr_len: usize = 0;
        for (f.instances) |*instance| stderr_len += instance.stderr.items.len;
        const stderr = try gpa.alloc(u8, stderr_len);

        stderr_len = 0;
        for (f.instances) |*instance| {
            @memcpy(stderr[stderr_len..][0..instance.stderr.items.len], instance.stderr.items);
            stderr_len += instance.stderr.items.len;
        }
        return stderr;
    }
};

fn evalFuzzTest(
    run: *Run,
    run_index: Configuration.Step.Index,
    progress_node: std.Progress.Node,
    spawn_options: process.SpawnOptions,
    fuzz_context: FuzzContext,
) !void {
    var f: FuzzTestRunner = try .init(run, run_index, fuzz_context, progress_node, spawn_options);
    defer f.deinit();
    try f.startInstances();
    try f.listen();
}

const StdioPollEnum = enum { stdout, stderr };

fn evalZigTest(
    run: *Run,
    run_index: Configuration.Step.Index,
    maker: *Maker,
    progress_node: std.Progress.Node,
    spawn_options: process.SpawnOptions,
    fuzz_context: ?FuzzContext,
) !void {
    if (fuzz_context != null) {
        try evalFuzzTest(run, run_index, progress_node, spawn_options, fuzz_context.?);
        return;
    }

    const graph = maker.graph;
    const gpa = maker.gpa;
    const io = graph.io;
    const step = maker.stepByIndex(run_index);

    // We will update this every time a child runs.
    step.result_peak_rss = 0;

    var test_results: Step.TestResults = .{
        .test_count = 0,
        .skip_count = 0,
        .fail_count = 0,
        .crash_count = 0,
        .timeout_count = 0,
        .leak_count = 0,
        .log_err_count = 0,
    };
    var test_metadata: ?TestMetadata = null;

    while (true) {
        var child = try process.spawn(io, spawn_options);
        var multi_reader_buffer: Io.File.MultiReader.Buffer(2) = undefined;
        var multi_reader: Io.File.MultiReader = undefined;
        multi_reader.init(gpa, io, multi_reader_buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
        var child_killed = false;
        defer if (!child_killed) {
            child.kill(io);
            multi_reader.deinit();
            step.result_peak_rss = @max(
                step.result_peak_rss,
                child.resource_usage_statistics.getMaxRss() orelse 0,
            );
        };

        switch (try waitZigTest(
            graph.arena,
            run,
            run_index,
            maker,
            &child,
            progress_node,
            &multi_reader,
            &test_metadata,
            &test_results,
        )) {
            .write_failed => |err| {
                // The runner unexpectedly closed a stdio pipe, which means a crash. Make sure we've captured
                // all available stderr to make our error output as useful as possible.
                const stderr_fr = multi_reader.fileReader(1);
                while (stderr_fr.interface.fillMore()) |_| {} else |e| switch (e) {
                    error.ReadFailed => return stderr_fr.err.?,
                    error.EndOfStream => {},
                }
                step.takeResultStderr(gpa, try multi_reader.toOwnedSlice(1));

                // Clean up everything and wait for the child to exit.
                child.stdin.?.close(io);
                child.stdin = null;
                multi_reader.deinit();
                child_killed = true;
                const term = try child.wait(io);
                step.result_peak_rss = @max(
                    step.result_peak_rss,
                    child.resource_usage_statistics.getMaxRss() orelse 0,
                );

                // The individual unit test results are irrelevant: the test runner itself broke!
                // Fail immediately without populating `s.test_results`.
                return step.fail(maker, "unable to write stdin ({t}); test process unexpectedly {f}", .{
                    err, fmtTerm(term),
                });
            },
            .no_poll => |no_poll| {
                // This might be a success (we requested exit and the child dutifully closed stdout) or
                // a crash of some kind. Either way, the child will terminate by itself -- wait for it.
                const stderr_owned = try multi_reader.toOwnedSlice(1);
                var keep_stderr_owned = false;
                defer if (!keep_stderr_owned) gpa.free(stderr_owned);

                // Clean up everything and wait for the child to exit.
                child.stdin.?.close(io);
                child.stdin = null;
                multi_reader.deinit();
                child_killed = true;
                const term = try child.wait(io);
                step.result_peak_rss = @max(
                    step.result_peak_rss,
                    child.resource_usage_statistics.getMaxRss() orelse 0,
                );

                if (no_poll.active_test_index) |test_index| {
                    // A test was running, so this is definitely a crash. Report it against that
                    // test, and continue to the next test.
                    test_metadata.?.ns_per_test[test_index] = no_poll.ns_elapsed;
                    test_results.crash_count += 1;
                    try step.addError(maker, "'{s}' {f}{s}{s}", .{
                        test_metadata.?.testName(test_index),
                        fmtTerm(term),
                        if (stderr_owned.len != 0) " with stderr:\n" else "",
                        std.mem.trim(u8, stderr_owned, "\n"),
                    });
                    continue;
                }

                // Report an error if the child terminated uncleanly or if we were still trying to run more tests.
                step.takeResultStderr(gpa, stderr_owned);
                keep_stderr_owned = true;

                const tests_done = test_metadata != null and test_metadata.?.next_index == std.math.maxInt(u32);
                if (!tests_done or !termMatches(.{ .exited = 0 }, term)) {
                    // The individual unit test results are irrelevant: the test runner itself broke!
                    // Fail immediately without populating `s.test_results`.
                    return step.fail(maker, "test process unexpectedly {f}", .{fmtTerm(term)});
                }

                // We're done with all of the tests! Commit the test results and return.
                step.test_results = test_results;
                if (test_metadata) |tm| {
                    run.cached_test_metadata = tm.toCachedTestMetadata();
                    if (maker.web_server) |ws| {
                        if (graph.time_report) {
                            ws.updateTimeReportRunTest(
                                run_index,
                                &run.cached_test_metadata.?,
                                tm.ns_per_test,
                            );
                        }
                    }
                }
                return;
            },
            .timeout => |timeout| {
                const stderr_owned = try multi_reader.toOwnedSlice(1);
                var keep_stderr_owned = false;
                defer if (!keep_stderr_owned) gpa.free(stderr_owned);

                if (timeout.active_test_index) |test_index| {
                    // A test was running. Report the timeout against that test, and continue on to
                    // the next test.
                    test_metadata.?.ns_per_test[test_index] = timeout.ns_elapsed;
                    test_results.timeout_count += 1;
                    try step.addError(maker, "'{s}' timed out after {f}{s}{s}", .{
                        test_metadata.?.testName(test_index),
                        Io.Duration{ .nanoseconds = timeout.ns_elapsed },
                        if (stderr_owned.len != 0) " with stderr:\n" else "",
                        std.mem.trim(u8, stderr_owned, "\n"),
                    });
                    continue;
                }
                // Just log an error and let the child be killed.
                step.takeResultStderr(gpa, stderr_owned);
                keep_stderr_owned = true;

                // The individual unit test results in `results` are irrelevant: the test runner
                // is broken! Fail immediately without populating `s.test_results`.
                return step.fail(maker, "test runner failed to respond for {f}", .{
                    Io.Duration{ .nanoseconds = timeout.ns_elapsed },
                });
            },
        }
        comptime unreachable;
    }
}

const TestMetadata = struct {
    names: []const u32,
    ns_per_test: []u64,
    expected_panic_msgs: []const u32,
    string_bytes: []const u8,
    next_index: u32,
    prog_node: std.Progress.Node,

    fn toCachedTestMetadata(tm: TestMetadata) CachedTestMetadata {
        return .{
            .names = tm.names,
            .string_bytes = tm.string_bytes,
        };
    }

    fn testName(tm: TestMetadata, index: u32) []const u8 {
        return tm.toCachedTestMetadata().testName(index);
    }
};

pub const CachedTestMetadata = struct {
    names: []const u32,
    string_bytes: []const u8,

    pub fn testName(tm: CachedTestMetadata, index: u32) []const u8 {
        return std.mem.sliceTo(tm.string_bytes[tm.names[index]..], 0);
    }
};

fn requestNextTest(io: Io, in: Io.File, metadata: *TestMetadata, sub_prog_node: *?std.Progress.Node) !void {
    while (metadata.next_index < metadata.names.len) {
        const i = metadata.next_index;
        metadata.next_index += 1;

        if (metadata.expected_panic_msgs[i] != 0) continue;

        const name = metadata.testName(i);
        if (sub_prog_node.*) |n| n.end();
        sub_prog_node.* = metadata.prog_node.start(name, 0);

        try sendRunTestMessage(io, in, .run_test, i);
        return;
    } else {
        metadata.next_index = std.math.maxInt(u32); // indicate that all tests are done
        try sendMessage(io, in, .exit);
    }
}

fn sendMessage(io: Io, file: Io.File, tag: std.zig.Client.Message.Tag) !void {
    const header: std.zig.Client.Message.Header = .{
        .tag = tag,
        .bytes_len = 0,
    };
    var w = file.writerStreaming(io, &.{});
    w.interface.writeStruct(header, .little) catch |err| switch (err) {
        error.WriteFailed => return w.err.?,
    };
}

fn sendRunTestMessage(io: Io, file: Io.File, tag: std.zig.Client.Message.Tag, index: u32) !void {
    const header: std.zig.Client.Message.Header = .{
        .tag = tag,
        .bytes_len = 4,
    };
    var w = file.writerStreaming(io, &.{});
    w.interface.writeStruct(header, .little) catch |err| switch (err) {
        error.WriteFailed => return w.err.?,
    };
    w.interface.writeInt(u32, index, .little) catch |err| switch (err) {
        error.WriteFailed => return w.err.?,
    };
}

fn sendRunFuzzTestMessage(
    io: Io,
    file: Io.File,
    test_names: []const []const u8,
    kind: std.Build.abi.fuzz.LimitKind,
    amount_or_instance: u64,
) !void {
    const header: std.zig.Client.Message.Header = .{
        .tag = .start_fuzzing,
        .bytes_len = 1 + 8 + 4 + count: {
            var c: u32 = @intCast(test_names.len * 4);
            for (test_names) |name| {
                c += @intCast(name.len);
            }
            break :count c;
        },
    };
    var w = file.writerStreaming(io, &.{});
    w.interface.writeStruct(header, .little) catch |err| switch (err) {
        error.WriteFailed => return w.err.?,
    };
    w.interface.writeByte(@intFromEnum(kind)) catch |err| switch (err) {
        error.WriteFailed => return w.err.?,
    };
    w.interface.writeInt(u64, amount_or_instance, .little) catch |err| switch (err) {
        error.WriteFailed => return w.err.?,
    };
    w.interface.writeInt(u32, @intCast(test_names.len), .little) catch |err| switch (err) {
        error.WriteFailed => return w.err.?,
    };
    for (test_names) |test_name| {
        w.interface.writeInt(u32, @intCast(test_name.len), .little) catch |err| switch (err) {
            error.WriteFailed => return w.err.?,
        };
        w.interface.writeAll(test_name) catch |err| switch (err) {
            error.WriteFailed => return w.err.?,
        };
    }
}

/// Uses `arena` to allocate the result.
fn evalGeneric(
    arena: Allocator,
    run_index: Configuration.Step.Index,
    maker: *Maker,
    spawn_options: process.SpawnOptions,
) !EvalGenericResult {
    const graph = maker.graph;
    const io = graph.io;
    const conf = &maker.scanned_config.configuration;
    const conf_step = run_index.ptr(conf);
    const conf_run = conf_step.extended.get(conf.extra).run;
    const step = maker.stepByIndex(run_index);

    var child = try process.spawn(io, spawn_options);
    defer child.kill(io);

    switch (conf_run.stdin.u) {
        .bytes => |bytes| {
            child.stdin.?.writeStreamingAll(io, bytes.slice(conf)) catch |err| {
                return step.fail(maker, "failed to write stdin: {t}", .{err});
            };
            child.stdin.?.close(io);
            child.stdin = null;
        },
        .lazy_path => |lazy_path| {
            const path = try maker.resolveLazyPathIndex(arena, lazy_path, run_index);
            const file = path.root_dir.handle.openFile(io, path.subPathOrDot(), .{}) catch |err| {
                return step.fail(maker, "failed to open stdin file: {t}", .{err});
            };
            defer file.close(io);
            // TODO https://github.com/ziglang/zig/issues/23955
            var read_buffer: [1024]u8 = undefined;
            var file_reader = file.reader(io, &read_buffer);
            var write_buffer: [1024]u8 = undefined;
            var stdin_writer = child.stdin.?.writerStreaming(io, &write_buffer);
            _ = stdin_writer.interface.sendFileAll(&file_reader, .unlimited) catch |err| switch (err) {
                error.ReadFailed => return step.fail(maker, "failed to read from {f}: {t}", .{
                    path, file_reader.err.?,
                }),
                error.WriteFailed => return step.fail(maker, "failed to write to stdin: {t}", .{
                    stdin_writer.err.?,
                }),
            };
            stdin_writer.interface.flush() catch |err| switch (err) {
                error.WriteFailed => return step.fail(maker, "failed to write to stdin: {t}", .{
                    stdin_writer.err.?,
                }),
            };
            child.stdin.?.close(io);
            child.stdin = null;
        },
        .none => {},
    }

    var stdout_bytes: ?[]const u8 = null;
    var stderr_bytes: ?[]const u8 = null;

    if (child.stdout) |stdout| {
        if (child.stderr) |stderr| {
            var multi_reader_buffer: Io.File.MultiReader.Buffer(2) = undefined;
            var multi_reader: Io.File.MultiReader = undefined;
            multi_reader.init(arena, io, multi_reader_buffer.toStreams(), &.{ stdout, stderr });

            const stdout_reader = multi_reader.reader(0);
            const stderr_reader = multi_reader.reader(1);

            while (multi_reader.fill(64, .none)) |_| {
                if (conf_run.stdio_limit.value) |limit| {
                    if (stdout_reader.buffered().len > limit)
                        return error.StdoutStreamTooLong;
                    if (stderr_reader.buffered().len > limit)
                        return error.StderrStreamTooLong;
                }
            } else |err| switch (err) {
                error.Timeout => unreachable,
                error.EndOfStream => {},
                else => |e| return e,
            }

            try multi_reader.checkAnyError();

            stdout_bytes = multi_reader.reader(0).buffered();
            stderr_bytes = multi_reader.reader(1).buffered();
        } else {
            var stdout_reader = stdout.readerStreaming(io, &.{});
            const stdio_limit: Io.Limit = if (conf_run.stdio_limit.value) |x| .limited64(x) else .unlimited;
            stdout_bytes = stdout_reader.interface.allocRemaining(arena, stdio_limit) catch |err| switch (err) {
                error.OutOfMemory => |e| return e,
                error.ReadFailed => return stdout_reader.err.?,
                error.StreamTooLong => return error.StdoutStreamTooLong,
            };
        }
    } else if (child.stderr) |stderr| {
        var stderr_reader = stderr.readerStreaming(io, &.{});
        const stdio_limit: Io.Limit = if (conf_run.stdio_limit.value) |x| .limited64(x) else .unlimited;
        stderr_bytes = stderr_reader.interface.allocRemaining(arena, stdio_limit) catch |err| switch (err) {
            error.OutOfMemory => |e| return e,
            error.ReadFailed => return stderr_reader.err.?,
            error.StreamTooLong => return error.StderrStreamTooLong,
        };
    }

    if (stderr_bytes) |bytes| if (bytes.len > 0) {
        // Treat stderr as an error message.
        const stderr_is_diagnostic = conf_run.captured_stderr.value == null and switch (conf_run.flags.stdio) {
            .check => !checksContainStderr(&conf_run),
            else => true,
        };
        if (stderr_is_diagnostic) {
            try step.setResultStderr(maker.gpa, bytes);
        }
    };

    step.result_peak_rss = child.resource_usage_statistics.getMaxRss() orelse 0;

    return .{
        .term = try child.wait(io),
        .stdout = stdout_bytes,
        .stderr = stderr_bytes,
    };
}

const IndexedOutput = struct {
    index: u32,
    arg_index: Configuration.Step.Run.Arg.Index,
};

pub fn rerunInFuzzMode(
    run: *Run,
    run_index: Configuration.Step.Index,
    fuzz: *Fuzz,
    prog_node: std.Progress.Node,
) !void {
    const maker = fuzz.maker;
    const graph = maker.graph;
    const step = maker.stepByIndex(run_index);
    const io = graph.io;
    const gpa = maker.gpa;
    const conf = &maker.scanned_config.configuration;
    const conf_step = run_index.ptr(conf);
    const conf_run = conf_step.extended.get(conf.extra).run;
    const cache_root = graph.local_cache_root;

    var arena_allocator: std.heap.ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    var argv_list: std.ArrayList([]const u8) = .empty;
    defer argv_list.deinit(gpa);

    for (conf_run.args.slice) |arg_index| {
        const arg = arg_index.get(conf);
        try argv_list.ensureUnusedCapacity(gpa, 1);
        switch (arg.flags.tag) {
            .string => {
                const prefix = arg.prefix.value.?.slice(conf);
                argv_list.appendAssumeCapacity(prefix);
            },
            .path_file => {
                const prefix = if (arg.prefix.value) |p| p.slice(conf) else "";
                const suffix = if (arg.suffix.value) |p| p.slice(conf) else "";
                const file_path = try maker.resolveLazyPathIndex(arena, arg.path.value.?, run_index);
                argv_list.appendAssumeCapacity(try mem.concat(arena, u8, &.{
                    prefix, try convertPathArg(arena, run_index, maker, file_path, arg.flags.make_absolute), suffix,
                }));
            },
            .path_directory => {
                const prefix = if (arg.prefix.value) |p| p.slice(conf) else "";
                const suffix = if (arg.suffix.value) |p| p.slice(conf) else "";
                const file_path = try maker.resolveLazyPathIndex(arena, arg.path.value.?, run_index);
                const resolved_arg = try mem.concat(arena, u8, &.{
                    prefix, try convertPathArg(arena, run_index, maker, file_path, arg.flags.make_absolute), suffix,
                });
                argv_list.appendAssumeCapacity(resolved_arg);
            },
            .file_content => {
                const prefix = if (arg.prefix.value) |p| p.slice(conf) else "";
                const suffix = if (arg.suffix.value) |p| p.slice(conf) else "";
                const file_path = try maker.resolveLazyPathIndex(arena, arg.path.value.?, run_index);

                var result: std.Io.Writer.Allocating = .init(arena);
                result.writer.writeAll(prefix) catch return error.OutOfMemory;

                const file = file_path.root_dir.handle.openFile(io, file_path.sub_path, .{}) catch |err|
                    return step.fail(maker, "unable to open input file {f}: {t}", .{ file_path, err });
                defer file.close(io);

                var file_reader = file.reader(io, &.{});
                _ = file_reader.interface.streamRemaining(&result.writer) catch |err| switch (err) {
                    error.ReadFailed => switch (file_reader.err.?) {
                        error.Canceled => |e| return e,
                        else => |e| return step.fail(maker, "failed to read from {f}: {t}", .{ file_path, e }),
                    },
                    error.WriteFailed => return error.OutOfMemory,
                };
                result.writer.writeAll(suffix) catch return error.OutOfMemory;

                argv_list.appendAssumeCapacity(result.written());
            },
            .artifact => {
                const prefix = if (arg.prefix.value) |p| p.slice(conf) else "";
                const suffix = if (arg.suffix.value) |p| p.slice(conf) else "";
                const producer_index = arg.producer.value.?;
                const producer_step = producer_index.ptr(conf);
                const producer = producer_step.extended.get(conf.extra).compile;
                const producer_make_comp_step = maker.stepByIndex(producer_index);
                const producer_make_comp = &producer_make_comp_step.extended.compile;
                const file_path: Path = if (producer_index == conf_run.producer.value.?)
                    run.rebuilt_executable.?
                else
                    producer_make_comp.installed_path orelse
                        maker.generatedPath(producer.generated_bin.value.?).*;
                argv_list.appendAssumeCapacity(try mem.concat(arena, u8, &.{
                    prefix, try convertPathArg(arena, run_index, maker, file_path, arg.flags.make_absolute), suffix,
                }));
            },
            .output_file => unreachable,
            .output_directory => unreachable,
            .passthru => unreachable,
        }
    }

    if (conf_run.flags.test_runner_mode) {
        const cache_dir_string = try convertPathArg(arena, run_index, maker, .{ .root_dir = cache_root }, false);

        try argv_list.ensureUnusedCapacity(gpa, 3);
        argv_list.appendAssumeCapacity(try arena.print("--cache-dir={s}", .{cache_dir_string}));
        argv_list.appendAssumeCapacity(try arena.print("--seed=0x{x}", .{graph.random_seed}));
        argv_list.appendAssumeCapacity("--listen=-");
    }

    step.clearFailedCommand(gpa);

    const has_side_effects = false;
    var rand_int: u64 = undefined;
    io.random(@ptrCast(&rand_int));
    const tmp_dir_path = "tmp" ++ Dir.path.sep_str ++ std.fmt.hex(rand_int);
    try runCommand(arena, run, run_index, maker, prog_node, argv_list.items, has_side_effects, tmp_dir_path, .{
        .fuzz = fuzz,
    });
}

fn populateGeneratedPaths(
    maker: *Maker,
    output_placeholders: []const IndexedOutput,
    cache_root: Cache.Directory,
    digest: *const Cache.HexDigest,
) !void {
    const conf = &maker.scanned_config.configuration;
    const graph = maker.graph;

    for (output_placeholders) |placeholder| {
        const arg = placeholder.arg_index.get(conf);
        maker.generatedPath(arg.generated.value.?).* = .{
            .root_dir = cache_root,
            .sub_path = try Dir.path.join(graph.arena, &.{
                "o", digest, arg.basename.value.?.slice(conf),
            }),
        };
    }
}

fn populateGeneratedPathsCreateDirs(
    arena: Allocator,
    run_index: Configuration.Step.Index,
    maker: *Maker,
    output_dir_path: []const u8,
    output_placeholders: []const IndexedOutput,
    argv: [][]const u8,
) !void {
    const step = maker.stepByIndex(run_index);
    const conf = &maker.scanned_config.configuration;
    const graph = maker.graph;
    const io = graph.io;
    const cache_root = graph.local_cache_root;

    for (output_placeholders) |placeholder| {
        const arg = placeholder.arg_index.get(conf);
        const prefix = if (arg.prefix.value) |p| p.slice(conf) else "";
        const suffix = if (arg.suffix.value) |p| p.slice(conf) else "";
        const basename = arg.basename.value.?.slice(conf);

        const generated_path: Path = .{
            .root_dir = cache_root,
            .sub_path = try Dir.path.join(graph.arena, &.{ output_dir_path, basename }),
        };
        const create_path: Path = .{
            .root_dir = cache_root,
            .sub_path = switch (arg.flags.tag) {
                .output_file => Dir.path.dirname(generated_path.sub_path).?,
                .output_directory => generated_path.sub_path,
                else => unreachable,
            },
        };
        create_path.root_dir.handle.createDirPath(io, create_path.sub_path) catch |err|
            return step.fail(maker, "unable to make path {f}: {t}", .{ create_path, err });

        maker.generatedPath(arg.generated.value.?).* = generated_path;

        const arg_output_path = try convertPathArg(arena, run_index, maker, generated_path, arg.flags.make_absolute);
        argv[placeholder.index] = try mem.concat(arena, u8, &.{ prefix, arg_output_path, suffix });
    }
}

fn populateGeneratedStdIo(
    maker: *Maker,
    conf_run: *const Configuration.Step.Run,
    cache_root: Cache.Directory,
    digest: *const Cache.HexDigest,
) !void {
    const conf = &maker.scanned_config.configuration;
    const graph = maker.graph;

    if (conf_run.captured_stdout.value) |captured| {
        maker.generatedPath(captured.generated_file).* = .{
            .root_dir = cache_root,
            .sub_path = try Dir.path.join(graph.arena, &.{
                "o", digest, captured.basename.slice(conf),
            }),
        };
    }

    if (conf_run.captured_stderr.value) |captured| {
        maker.generatedPath(captured.generated_file).* = .{
            .root_dir = cache_root,
            .sub_path = try Dir.path.join(graph.arena, &.{
                "o", digest, captured.basename.slice(conf),
            }),
        };
    }
}

fn formatTerm(term: ?process.Child.Term, w: *std.Io.Writer) std.Io.Writer.Error!void {
    if (term) |t| switch (t) {
        .exited => |code| try w.print("exited with code {d}", .{code}),
        .signal => |sig| try w.print("terminated with signal {t}", .{sig}),
        .stopped => |sig| try w.print("stopped with signal {t}", .{sig}),
        .unknown => |code| try w.print("terminated for unknown reason with code {d}", .{code}),
    } else {
        try w.writeAll("exited with any code");
    }
}
fn fmtTerm(term: ?process.Child.Term) std.fmt.Alt(?process.Child.Term, formatTerm) {
    return .{ .data = term };
}

const FuzzContext = struct {
    fuzz: *Fuzz,
};

fn runCommand(
    arena: Allocator,
    run: *Run,
    run_index: Configuration.Step.Index,
    maker: *Maker,
    progress_node: std.Progress.Node,
    argv: []const []const u8,
    has_side_effects: bool,
    output_dir_path: []const u8,
    fuzz_context: ?FuzzContext,
) Step.ExtendedMakeError!void {
    const graph = maker.graph;
    const gpa = maker.gpa;
    const step = maker.stepByIndex(run_index);
    const io = graph.io;
    const cache_root = graph.local_cache_root;
    const conf = &maker.scanned_config.configuration;
    const conf_step = run_index.ptr(conf);
    const conf_run = conf_step.extended.get(conf.extra).run;

    const cwd: process.Child.Cwd = if (conf_run.cwd.value) |lazy_cwd|
        .{ .path = try maker.resolveLazyPathIndexAbs(arena, lazy_cwd, run_index) }
    else
        .inherit;

    const allow_skip = switch (conf_run.flags.stdio) {
        .check, .zig_test => conf_run.flags.skip_foreign_checks,
        else => false,
    };

    var interp_argv: std.ArrayList([]const u8) = .empty;

    var environ_map: std.process.Environ.Map = .init(gpa);
    defer environ_map.deinit();

    // In either case we add to this mutatable data structure so that we can
    // tweak the environment below.
    if (conf_run.environ_map.value) |env_map_index| {
        const conf_env_map = env_map_index.get(conf);
        for (conf_env_map.keys.slice(conf), conf_env_map.values.slice(conf)) |k, v| {
            try environ_map.put(k.slice(conf), v.slice(conf));
        }
    } else {
        try environ_map.putAll(&graph.environ_map);
    }

    // Now that we have the environ map, we might need to mutate it to insert
    // .dll search paths because Windows doesn't have rpaths.
    const arg0 = conf_run.args.slice[0].get(conf);
    if (arg0.producer.value) |producer_index| {
        const producer_step = producer_index.ptr(conf);
        const producer = producer_step.extended.get(conf.extra).compile;
        const root_module = producer.root_module.get(conf);
        const root_module_target = root_module.resolved_target.get(conf).?.result.get(conf);
        if (root_module_target.flags.os_tag == .windows) {
            try addPathForDynLibs(maker, arena, producer_index, &environ_map, argv[0]);
        }
    }

    const cwd_string = switch (cwd) {
        .path => |p| p,
        .dir => unreachable,
        .inherit => null,
    };
    try graph.handleVerbose(cwd_string, &environ_map, argv);

    const opt_generic_result = spawnChildAndCollect(
        arena,
        run_index,
        run,
        maker,
        progress_node,
        argv,
        &environ_map,
        has_side_effects,
        fuzz_context,
    ) catch |err| term: {
        switch (err) {
            error.InvalidExe, // cpu arch mismatch
            error.FileNotFound, // can happen with a wrong dynamic linker path
            => interpret: {
                const producer_index = arg0.producer.value orelse break :interpret;
                const producer_step = producer_index.ptr(conf);
                const producer = producer_step.extended.get(conf.extra).compile;
                switch (producer.flags3.kind) {
                    .exe, .@"test" => {},
                    else => break :interpret,
                }
                const root_module = producer.root_module.get(conf);
                const root_module_target = root_module.resolved_target.get(conf).?.result.get(conf);
                const root_target = root_module_target.unwrapTarget(conf);
                const link_libc = maker.stepByIndex(producer_index).extended.compile.is_linking_libc;

                const host: std.Target = std.zig.system.resolveTargetQuery(io, .{}) catch |he| switch (he) {
                    error.Canceled => |e| return e,
                    else => builtin.target,
                };

                const need_cross_libc = link_libc and root_target.os.tag == .linux and
                    switch (producer.flags2.linkage) {
                        .static => false,
                        .dynamic => true,
                        .default => root_target.isGnuLibC(),
                    };
                switch (std.zig.system.getExternalExecutor(io, &root_target, .{
                    .host_cpu_arch = host.cpu.arch,
                    .host_os_tag = host.os.tag,
                    .qemu_fixes_dl = need_cross_libc and graph.libc_runtimes_dir != null,
                    .link_libc = link_libc,
                })) {
                    .native, .rosetta => {
                        if (allow_skip) return error.MakeSkipped;
                        break :interpret;
                    },
                    .wine => |bin_name| {
                        if (graph.enable_wine) {
                            try interp_argv.ensureUnusedCapacity(arena, 1 + argv.len);
                            interp_argv.appendAssumeCapacity(bin_name);
                            interp_argv.appendSliceAssumeCapacity(argv);

                            // Wine's excessive stderr logging is only situationally helpful. Disable it by default, but
                            // allow the user to override it (e.g. with `WINEDEBUG=err+all`) if desired.
                            if (environ_map.get("WINEDEBUG") == null) {
                                try environ_map.put("WINEDEBUG", "-all");
                            }
                        } else {
                            return failForeign(arena, &conf_run, maker, run_index, "-fwine", argv[0], &root_target, &host);
                        }
                    },
                    .qemu => |bin_name| {
                        if (graph.enable_qemu) {
                            try interp_argv.ensureUnusedCapacity(arena, 3 + argv.len);
                            interp_argv.appendAssumeCapacity(bin_name);

                            if (need_cross_libc) {
                                if (graph.libc_runtimes_dir) |dir| {
                                    interp_argv.appendAssumeCapacity("-L");
                                    interp_argv.appendAssumeCapacity(try Dir.path.join(arena, &.{
                                        dir,
                                        try if (root_target.isGnuLibC()) std.zig.target.glibcRuntimeTriple(
                                            arena,
                                            root_target.cpu.arch,
                                            root_target.os.tag,
                                            root_target.abi,
                                        ) else if (root_target.isMuslLibC()) std.zig.target.muslRuntimeTriple(
                                            arena,
                                            root_target.cpu.arch,
                                            root_target.abi,
                                        ) else unreachable,
                                    }));
                                } else return failForeign(arena, &conf_run, maker, run_index, "--libc-runtimes", argv[0], &root_target, &host);
                            }

                            interp_argv.appendSliceAssumeCapacity(argv);
                        } else return failForeign(arena, &conf_run, maker, run_index, "-fqemu", argv[0], &root_target, &host);
                    },
                    .darling => |bin_name| {
                        if (graph.enable_darling) {
                            try interp_argv.ensureUnusedCapacity(arena, 1 + argv.len);
                            interp_argv.appendAssumeCapacity(bin_name);
                            interp_argv.appendSliceAssumeCapacity(argv);
                        } else {
                            return failForeign(arena, &conf_run, maker, run_index, "-fdarling", argv[0], &root_target, &host);
                        }
                    },
                    .wasmtime => |bin_name| {
                        if (graph.enable_wasmtime) {
                            try interp_argv.ensureUnusedCapacity(arena, 3 + argv.len + conf_run.preopen_names.slice.len);
                            interp_argv.appendAssumeCapacity(bin_name);
                            interp_argv.appendAssumeCapacity("--dir=.");
                            for (conf_run.preopen_names.slice, conf_run.preopen_paths.slice) |name, lazy_path| {
                                const path = try maker.resolveLazyPath(arena, lazy_path.get(conf), run_index);
                                path.root_dir.handle.createDirPath(io, path.subPathOrDot()) catch |e|
                                    return step.fail(maker, "failed creating directory {f}: {t}", .{ path, e });
                                interp_argv.appendAssumeCapacity(try arena.print("--dir={f}::{s}", .{ path, name.slice(conf) }));
                            }
                            // Wasmtime doeesn't inherit environment variables from the parent process
                            // by default. '-S inherit-env' was added in Wasmtime version 20.
                            interp_argv.appendAssumeCapacity("-Sinherit-env");
                            interp_argv.appendSliceAssumeCapacity(argv);

                            // Enable more detailed backtraces by default, but allow the user to override this (e.g.
                            // with `WASMTIME_BACKTRACE_DETAILS=0`) if desired.
                            if (environ_map.get("WASMTIME_BACKTRACE_DETAILS") == null) {
                                try environ_map.put("WASMTIME_BACKTRACE_DETAILS", "1");
                            }
                        } else {
                            return failForeign(arena, &conf_run, maker, run_index, "-fwasmtime", argv[0], &root_target, &host);
                        }
                    },
                    .bad_dl => |foreign_dl| {
                        if (allow_skip) return error.MakeSkipped;

                        const host_dl = host.dynamic_linker.get() orelse "(none)";

                        return step.fail(maker,
                            \\the host system is unable to execute binaries from the target
                            \\  because the host dynamic linker is '{s}',
                            \\  while the target dynamic linker is '{s}'.
                            \\  consider setting the dynamic linker or enabling skip_foreign_checks in the Run step
                        , .{ host_dl, foreign_dl });
                    },
                    .bad_os_or_cpu => {
                        if (allow_skip) return error.MakeSkipped;

                        const host_name = try host.zigTriple(arena);
                        const foreign_name = try root_target.zigTriple(arena);

                        return step.fail(maker, "the host system ({s}) is unable to execute binaries from the target ({s})", .{
                            host_name, foreign_name,
                        });
                    },
                }

                step.clearFailedCommand(gpa);
                try graph.handleVerbose(cwd_string, &environ_map, interp_argv.items);

                break :term spawnChildAndCollect(
                    arena,
                    run_index,
                    run,
                    maker,
                    progress_node,
                    interp_argv.items,
                    &environ_map,
                    has_side_effects,
                    fuzz_context,
                ) catch |e| {
                    if (!conf_run.flags.failing_to_execute_foreign_is_an_error) return error.MakeSkipped;
                    if (e == error.MakeFailed) return error.MakeFailed; // error already reported
                    return step.fail(maker, "unable to spawn interpreter {s}: {t}", .{ interp_argv.items[0], e });
                };
            },
            error.MakeFailed, error.OutOfMemory, error.Canceled => |e| return e,
            else => {},
        }
        return step.fail(maker, "failed to spawn and capture stdio from {s}: {t}", .{ argv[0], err });
    };

    const generic_result = opt_generic_result orelse {
        assert(conf_run.flags.stdio == .zig_test);
        // Specific errors have already been reported, and test results are populated. All we need
        // to do is report step failure if any test failed.
        if (!step.test_results.isSuccess()) return error.MakeFailed;
        return;
    };

    assert(fuzz_context == null);
    assert(conf_run.flags.stdio != .zig_test);

    // Capture stdout and stderr to GeneratedFile objects.
    const Stream = struct {
        captured: ?Configuration.Step.Run.CapturedStream,
        bytes: ?[]const u8,
        trim_whitespace: Configuration.Step.Run.TrimWhitespace,
    };
    for (&[_]Stream{
        .{
            .captured = conf_run.captured_stdout.value,
            .bytes = generic_result.stdout,
            .trim_whitespace = conf_run.flags.stdout_trim_whitespace,
        },
        .{
            .captured = conf_run.captured_stderr.value,
            .bytes = generic_result.stderr,
            .trim_whitespace = conf_run.flags.stderr_trim_whitespace,
        },
    }) |*stream| {
        if (stream.captured) |captured| {
            const output_path: Path = .{
                .root_dir = cache_root,
                .sub_path = try Dir.path.join(graph.arena, &.{
                    output_dir_path, captured.basename.slice(conf),
                }),
            };
            maker.generatedPath(captured.generated_file).* = output_path;

            const sub_path_parent = output_path.dirname().?;
            sub_path_parent.root_dir.handle.createDirPath(io, sub_path_parent.sub_path) catch |err|
                return step.fail(maker, "unable to make path {f}: {t}", .{ sub_path_parent, err });

            const data = switch (stream.trim_whitespace) {
                .none => stream.bytes.?,
                .all => mem.trim(u8, stream.bytes.?, &std.ascii.whitespace),
                .leading => mem.trimStart(u8, stream.bytes.?, &std.ascii.whitespace),
                .trailing => mem.trimEnd(u8, stream.bytes.?, &std.ascii.whitespace),
            };
            output_path.root_dir.handle.writeFile(io, .{
                .sub_path = output_path.sub_path,
                .data = data,
            }) catch |err| return step.fail(maker, "unable to write file {f}: {t}", .{ output_path, err });
        }
    }

    switch (conf_run.flags.stdio) {
        .zig_test => unreachable,
        .check => {
            if (conf_run.expect_stderr_exact.value) |bytes| {
                const expected_bytes = bytes.slice(conf);
                if (!mem.eql(u8, expected_bytes, generic_result.stderr.?)) {
                    return step.fail(maker,
                        \\========= expected this stderr: =========
                        \\{s}
                        \\========= but found: ====================
                        \\{s}
                    , .{
                        expected_bytes,
                        generic_result.stderr.?,
                    });
                }
            }
            if (conf_run.expect_stdout_exact.value) |bytes| {
                const expected_bytes = bytes.slice(conf);
                if (!mem.eql(u8, expected_bytes, generic_result.stdout.?)) {
                    return step.fail(maker,
                        \\========= expected this stdout: =========
                        \\{s}
                        \\========= but found: ====================
                        \\{s}
                    , .{
                        expected_bytes,
                        generic_result.stdout.?,
                    });
                }
            }
            for (conf_run.expect_stderr_match.slice) |bytes| {
                const match = bytes.slice(conf);
                if (mem.find(u8, generic_result.stderr.?, match) == null) {
                    return step.fail(maker,
                        \\========= expected to find in stderr: =========
                        \\{s}
                        \\========= but stderr does not contain it: =====
                        \\{s}
                    , .{
                        match,
                        generic_result.stderr.?,
                    });
                }
            }
            for (conf_run.expect_stdout_match.slice) |bytes| {
                const match = bytes.slice(conf);
                if (mem.find(u8, generic_result.stdout.?, match) == null) {
                    return step.fail(maker,
                        \\========= expected to find in stdout: =========
                        \\{s}
                        \\========= but stdout does not contain it: =====
                        \\{s}
                    , .{
                        match,
                        generic_result.stdout.?,
                    });
                }
            }
            if (conf_run.expect_term_value.value) |expected_term_value| {
                const expected_term: process.Child.Term = switch (conf_run.flags2.expect_term_status) {
                    .exited => .{ .exited = @intCast(expected_term_value) },
                    .signal => .{ .signal = @enumFromInt(expected_term_value) },
                    .stopped => .{ .stopped = @enumFromInt(expected_term_value) },
                    .unknown => .{ .unknown = expected_term_value },
                };
                if (!termMatches(expected_term, generic_result.term)) {
                    return step.fail(maker, "process {f} (expected {f})", .{
                        fmtTerm(generic_result.term),
                        fmtTerm(expected_term),
                    });
                }
            }
            const snapshots: []const ?struct {
                path: Cache.Path,
                result: enum { stderr, stdout },
            } = &.{
                if (conf_run.expect_stderr_snapshot.value) |path| .{
                    .path = try maker.resolveLazyPathIndex(arena, path, run_index),
                    .result = .stderr,
                } else null,
                if (conf_run.expect_stdout_snapshot.value) |path| .{
                    .path = try maker.resolveLazyPathIndex(arena, path, run_index),
                    .result = .stdout,
                } else null,
            };
            for (snapshots) |opt_snapshot| {
                const snapshot = opt_snapshot orelse continue;

                const file = snapshot.path.root_dir.handle.openFile(io, snapshot.path.sub_path, .{}) catch |err|
                    return step.fail(maker, "unable to open snapshot file {f}: {t}", .{ snapshot.path, err });
                defer file.close(io);

                var file_reader = file.reader(io, &.{});
                const snapshot_contents = file_reader.interface.allocRemaining(gpa, .unlimited) catch |err|
                    return step.fail(maker, "unable to read snapshot file {f}: {t}", .{ snapshot.path, err });
                defer gpa.free(snapshot_contents);

                const result = switch (snapshot.result) {
                    .stderr => generic_result.stderr.?,
                    .stdout => generic_result.stdout.?,
                };
                if (std.mem.findDiff(u8, snapshot_contents, result)) |diff_index| {
                    var diff_line_number: usize = 1;

                    for (snapshot_contents[0..diff_index]) |value| {
                        if (value == '\n') diff_line_number += 1;
                    }

                    return step.fail(maker,
                        \\
                        \\========= snapshot file: =========
                        \\{f}
                        \\========= contained: =============
                        \\{s}
                        \\========= {t} output was: ========
                        \\{s}
                        \\==================================
                        \\first difference on line {d}:
                        \\expected:
                        \\{f}
                        \\found:
                        \\{f}
                    , .{
                        snapshot.path,
                        snapshot_contents,
                        snapshot.result,
                        result,
                        diff_line_number,
                        fmtSnapshotIndicatorLine(snapshot_contents, diff_index),
                        fmtSnapshotIndicatorLine(result, diff_index),
                    });
                }
            }
        },
        else => {
            // On failure, report captured stderr like normal standard error output.
            if (!generic_result.term.success()) {
                if (generic_result.stderr) |bytes| {
                    try step.setResultStderr(gpa, bytes);
                }
            }
            try step.handleChildProcessTerm(maker, generic_result.term);
        },
    }
}

const FmtIndicatorLine = struct {
    buf: []const u8,
    index: usize,
};

fn fmtSnapshotIndicatorLine(buf: []const u8, index: usize) std.fmt.Alt(
    FmtIndicatorLine,
    snapshotIndicatorLine,
) {
    return .{ .data = .{ .buf = buf, .index = index } };
}

fn snapshotIndicatorLine(line: FmtIndicatorLine, w: *std.Io.Writer) std.Io.Writer.Error!void {
    const line_begin_index = if (std.mem.lastIndexOfScalar(u8, line.buf[0..line.index], '\n')) |line_begin|
        line_begin + 1
    else
        0;
    const line_end_index = if (std.mem.findScalar(u8, line.buf[line.index..], '\n')) |line_end|
        (line.index + line_end)
    else
        line.buf.len;

    try w.writeAll(line.buf[line_begin_index..line_end_index]);
    try w.writeByte('\n');
    try w.splatByteAll(' ', line_end_index - line_begin_index);
    try w.writeByte('\n');
    if (line.index >= line.buf.len)
        try w.writeAll("^ (end of file)")
    else
        try w.print("^ ('\\x{x:0>2}')\n", .{line.buf[line.index]});
}

const EvalGenericResult = struct {
    term: process.Child.Term,
    stdout: ?[]const u8,
    stderr: ?[]const u8,
};

fn spawnChildAndCollect(
    arena: Allocator,
    run_index: Configuration.Step.Index,
    run: *Run,
    maker: *Maker,
    progress_node: std.Progress.Node,
    argv: []const []const u8,
    environ_map: *EnvMap,
    has_side_effects: bool,
    fuzz_context: ?FuzzContext,
) !?EvalGenericResult {
    const step = maker.stepByIndex(run_index);
    const graph = maker.graph;
    const io = graph.io;
    const gpa = maker.gpa;
    const conf = &maker.scanned_config.configuration;
    const conf_step = run_index.ptr(conf);
    const conf_run = conf_step.extended.get(conf.extra).run;

    if (fuzz_context != null) {
        assert(!has_side_effects);
        assert(conf_run.flags.stdio == .zig_test);
    }

    const child_cwd: process.Child.Cwd = if (conf_run.cwd.value) |lazy_cwd|
        .{ .path = try maker.resolveLazyPathIndexAbs(arena, lazy_cwd, run_index) }
    else
        .inherit;

    // If an error occurs, it's caused by this command:
    const cwd_string = switch (child_cwd) {
        .path => |p| p,
        .dir => unreachable,
        .inherit => null,
    };
    // We have to set the failed command here regardless of whether this
    // function returns an error because only after this function returns
    // does the logic determine whether the child process termination was
    // success or failure.
    step.setFailedCommand(gpa, argv, .{
        .cwd = cwd_string,
        .child_env = environ_map,
        .parent_env = &graph.environ_map,
    });

    try step.handleChildProcUnsupported(maker);

    var spawn_options: process.SpawnOptions = .{
        .argv = argv,
        .cwd = child_cwd,
        .environ_map = environ_map,
        .request_resource_usage_statistics = true,
        .stdin = if (conf_run.stdin.u != .none) s: {
            assert(conf_run.flags.stdio != .inherit);
            break :s .pipe;
        } else switch (conf_run.flags.stdio) {
            .infer_from_args => if (has_side_effects) .inherit else .ignore,
            .inherit => .inherit,
            .check => .ignore,
            .zig_test => .pipe,
        },
        .stdout = if (conf_run.captured_stdout.value != null) .pipe else switch (conf_run.flags.stdio) {
            .infer_from_args => if (has_side_effects) .inherit else .ignore,
            .inherit => .inherit,
            .check => if (checksContainStdout(&conf_run)) .pipe else .ignore,
            .zig_test => .pipe,
        },
        .stderr = if (conf_run.captured_stderr.value != null) .pipe else switch (conf_run.flags.stdio) {
            .infer_from_args => if (has_side_effects) .inherit else .pipe,
            .inherit => .inherit,
            .check => .pipe,
            .zig_test => .pipe,
        },
    };

    if (conf_run.flags.stdio == .zig_test) {
        try setColorEnvironmentVariables(&conf_run, environ_map, graph.stderr_mode.?);
        const started: Io.Clock.Timestamp = .now(io, .awake);
        const result = evalZigTest(run, run_index, maker, progress_node, spawn_options, fuzz_context) catch |err| switch (err) {
            error.Canceled => |e| return e,
            else => |e| e,
        };
        step.result_duration_ns = @intCast(started.untilNow(io).raw.nanoseconds);
        try result;
        return null;
    } else {
        const inherit = spawn_options.stdout == .inherit or spawn_options.stderr == .inherit;
        if (!conf_run.flags.disable_zig_progress and !inherit) {
            spawn_options.progress_node = progress_node;
        }
        const terminal_mode: Io.Terminal.Mode = if (inherit) m: {
            const stderr = try io.lockStderr(&.{}, graph.stderr_mode);
            break :m stderr.terminal_mode;
        } else .no_color;
        defer if (inherit) io.unlockStderr();
        try setColorEnvironmentVariables(&conf_run, environ_map, terminal_mode);

        const started: Io.Clock.Timestamp = .now(io, .awake);
        const result = evalGeneric(arena, run_index, maker, spawn_options) catch |err| switch (err) {
            error.Canceled => |e| return e,
            else => |e| e,
        };
        step.result_duration_ns = @intCast(started.untilNow(io).raw.nanoseconds);
        return try result;
    }
}

fn termMatches(expected: ?process.Child.Term, actual: process.Child.Term) bool {
    return if (expected) |e| switch (e) {
        .exited => |expected_code| switch (actual) {
            .exited => |actual_code| expected_code == actual_code,
            else => false,
        },
        .signal => |expected_sig| switch (actual) {
            .signal => |actual_sig| expected_sig == actual_sig,
            else => false,
        },
        .stopped => |expected_sig| switch (actual) {
            .stopped => |actual_sig| expected_sig == actual_sig,
            else => false,
        },
        .unknown => |expected_code| switch (actual) {
            .unknown => |actual_code| expected_code == actual_code,
            else => false,
        },
    } else switch (actual) {
        .exited => true,
        else => false,
    };
}

fn setColorEnvironmentVariables(
    conf_run: *const Configuration.Step.Run,
    environ_map: *EnvMap,
    terminal_mode: Io.Terminal.Mode,
) !void {
    color: switch (conf_run.flags.color) {
        .manual => {},
        .enable => {
            try environ_map.put("CLICOLOR_FORCE", "1");
            _ = environ_map.swapRemove("NO_COLOR");
        },
        .disable => {
            try environ_map.put("NO_COLOR", "1");
            _ = environ_map.swapRemove("CLICOLOR_FORCE");
        },
        .inherit => switch (terminal_mode) {
            .no_color, .windows_api => continue :color .disable,
            .escape_codes => continue :color .enable,
        },
        .auto => {
            const capture_stderr = conf_run.captured_stderr.value != null or switch (conf_run.flags.stdio) {
                .check => checksContainStderr(conf_run),
                .infer_from_args, .inherit, .zig_test => false,
            };
            if (capture_stderr) {
                continue :color .disable;
            } else {
                continue :color .inherit;
            }
        },
    }
}

fn checksContainStdout(conf_run: *const Configuration.Step.Run) bool {
    return conf_run.expect_stdout_exact.value != null or
        conf_run.expect_stdout_match.slice.len != 0 or
        conf_run.expect_stdout_snapshot.value != null;
}

fn checksContainStderr(conf_run: *const Configuration.Step.Run) bool {
    return conf_run.expect_stderr_exact.value != null or
        conf_run.expect_stderr_match.slice.len != 0 or
        conf_run.expect_stderr_snapshot.value != null;
}

/// If `path` is absolute, return it unchanged. If `make_absolute` is true, make it absolute.
/// Otherwise, make it relative to the cwd of the child.
///
/// Whenever a path is included in the argv of a child, it should be put through this function
/// first.
fn convertPathArg(
    arena: Allocator,
    run_index: Configuration.Step.Index,
    maker: *Maker,
    path: Path,
    make_absolute: bool,
) ![]const u8 {
    const conf = &maker.scanned_config.configuration;
    const conf_step = run_index.ptr(conf);
    const conf_run = conf_step.extended.get(conf.extra).run;
    const graph = maker.graph;

    const path_str = try path.toString(arena);
    if (Dir.path.isAbsolute(path_str)) {
        // Absolute paths don't need changing.
        return path_str;
    }

    if (make_absolute) {
        return Dir.path.join(arena, &.{ graph.cache.cwd, path_str });
    }

    const child_cwd_rel: []const u8 = rel: {
        const child_lazy_cwd = conf_run.cwd.value orelse break :rel path_str;
        const child_cwd = try maker.resolveLazyPathIndexAbs(arena, child_lazy_cwd, run_index);
        // Convert it from relative to *our* cwd, to relative to the *child's* cwd.
        break :rel try Dir.path.relative(arena, graph.cache.cwd, &graph.environ_map, child_cwd, path_str);
    };
    // Not every path can be made relative, e.g. if the path and the child cwd are on different
    // disk designators on Windows. In that case, `relative` will return an absolute path which we can
    // just return.
    if (Dir.path.isAbsolute(child_cwd_rel)) return child_cwd_rel;

    // We're not done yet. In some cases this path must be prefixed with './':
    // * On POSIX, the executable name cannot be a single component like 'foo'
    // * Some executables might treat a leading '-' like a flag, which we must avoid
    // There's no harm in it, so just *always* apply this prefix.
    return Dir.path.join(arena, &.{ ".", child_cwd_rel });
}

fn addPathForDynLibs(
    maker: *Maker,
    arena: Allocator,
    artifact: Configuration.Step.Index,
    environ_map: *process.Environ.Map,
    argv0: []const u8,
) !void {
    const conf = &maker.scanned_config.configuration;
    const graph = maker.graph;
    const use_wine = graph.enable_wine and builtin.os.tag != .windows and std.ascii.endsWithIgnoreCase(argv0, ".exe");
    const path_key = if (use_wine) "WINEPATH" else "PATH";
    const path_delimiter: u8 = if (builtin.os.tag == .windows or use_wine)
        Dir.path.delimiter_windows
    else
        Dir.path.delimiter;

    var module_graph: Step.Compile.ModuleGraph = .empty;
    const compile_deps = try Step.Compile.getCompileDependencies(arena, &module_graph, conf, artifact, true);

    for (compile_deps) |dep_index| {
        const conf_comp_step = dep_index.ptr(conf);
        const conf_comp = conf_comp_step.extended.get(conf.extra).compile;
        const root_module = conf_comp.root_module.get(conf);
        const target = root_module.resolved_target.get(conf).?.result.get(conf);
        if (target.flags.os_tag == .windows and conf_comp.isDynamicLibrary()) {
            const dll_path = try maker.generatedPath(conf_comp.generated_bin.value.?).toString(arena);
            const search_path = Dir.path.dirname(dll_path).?;
            if (environ_map.get(path_key)) |prev_path| {
                const new_path = try arena.print("{s}{c}{s}", .{ prev_path, path_delimiter, search_path });
                try environ_map.put(path_key, new_path);
            } else {
                try environ_map.put(path_key, search_path);
            }
        }
    }
}

fn failForeign(
    arena: Allocator,
    conf_run: *const Configuration.Step.Run,
    maker: *Maker,
    step_index: Configuration.Step.Index,
    suggested_flag: []const u8,
    argv0: []const u8,
    artifact_target: *const std.Target,
    host_target: *const std.Target,
) Step.ExtendedMakeError {
    const step = maker.stepByIndex(step_index);
    switch (conf_run.flags.stdio) {
        .check, .zig_test => {
            if (conf_run.flags.skip_foreign_checks) return error.MakeSkipped;

            const host_name = try host_target.zigTriple(arena);
            const foreign_name = try artifact_target.zigTriple(arena);

            return step.fail(maker,
                \\unable to spawn foreign binary '{s}' ({s}) on host system ({s})
                \\  consider using {s} or enabling skip_foreign_checks in the Run step
            , .{ argv0, foreign_name, host_name, suggested_flag });
        },
        else => {
            return step.fail(maker, "unable to spawn foreign binary '{s}'", .{argv0});
        },
    }
}
