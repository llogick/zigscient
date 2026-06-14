const Fmt = @This();

const std = @import("std");
const Configuration = std.Build.Configuration;

const Step = @import("../Step.zig");
const Maker = @import("../../Maker.zig");

/// Persisted to reuse memory on subsequent calls to `make`.
argv: std.ArrayList([]const u8) = .empty,

pub fn make(
    fmt: *Fmt,
    step_index: Configuration.Step.Index,
    maker: *Maker,
    progress_node: std.Progress.Node,
) Step.ExtendedMakeError!void {
    const graph = maker.graph;
    const step = maker.stepByIndex(step_index);
    const gpa = maker.gpa;
    const arena = graph.arena; // TODO don't leak into the process arena
    const argv = &fmt.argv;
    const conf = &maker.scanned_config.configuration;
    const conf_step = step_index.ptr(conf);
    const conf_fmt = conf_step.extended.get(conf.extra).fmt;
    const paths = conf_fmt.paths.slice;
    const exclude_paths = conf_fmt.exclude_paths.slice;

    argv.clearRetainingCapacity();
    try argv.ensureUnusedCapacity(gpa, 2 + 1 + paths.len + 2 * exclude_paths.len);

    argv.appendAssumeCapacity(graph.zig_exe);
    argv.appendAssumeCapacity("fmt");

    if (conf_fmt.flags.check)
        argv.appendAssumeCapacity("--check");

    for (paths) |lp|
        argv.appendAssumeCapacity(try maker.resolveLazyPathIndexAbs(arena, lp, step_index));

    for (exclude_paths) |lp| {
        argv.appendAssumeCapacity("--exclude");
        argv.appendAssumeCapacity(try maker.resolveLazyPathIndexAbs(arena, lp, step_index));
    }

    const run_result = step.captureChildProcess(maker, arena, .{
        .progress_node = progress_node,
        .argv = argv.items,
        .allow_failure = false,
    }) catch |err| switch (err) {
        error.FileNotFound => unreachable,
        else => |e| return e,
    };

    if (conf_fmt.flags.check) switch (run_result.term) {
        .exited => |code| if (code != 0 and run_result.stdout.len != 0) {
            var it = std.mem.tokenizeScalar(u8, run_result.stdout, '\n');
            while (it.next()) |bad_file_name| {
                try step.addError(maker, "{s}: non-conforming formatting", .{bad_file_name});
            }
        },
        else => {},
    };
    try step.handleChildProcessTerm(maker, run_result.term);
}
