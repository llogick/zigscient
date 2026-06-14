const InstallDir = @This();

const std = @import("std");
const Io = std.Io;
const log = std.log;
const Configuration = std.Build.Configuration;
const endsWith = std.mem.endsWith;

const Step = @import("../Step.zig");
const Maker = @import("../../Maker.zig");

pub fn make(
    install_dir: *InstallDir,
    step_index: Configuration.Step.Index,
    maker: *Maker,
    progress_node: std.Progress.Node,
) Step.ExtendedMakeError!void {
    _ = install_dir;
    const graph = maker.graph;
    const gpa = maker.gpa;
    const arena = maker.graph.arena; // TODO don't leak into process arena
    const io = graph.io;
    const step = maker.stepByIndex(step_index);
    const conf = &maker.scanned_config.configuration;
    const conf_step = step_index.ptr(conf);
    const conf_id = conf_step.extended.get(conf.extra).install_dir;

    step.clearWatchInputs(maker);

    const dest_parent_path = try maker.resolveInstallDir(arena, conf_id.dest_dir);
    const dest_prefix = if (conf_id.dest_sub_path.value) |s|
        try dest_parent_path.join(arena, s.slice(conf))
    else
        dest_parent_path;
    const src_dir_lazy_path = conf_id.source_dir.get(conf);
    const src_dir_path = try maker.resolveLazyPath(arena, src_dir_lazy_path, step_index);
    const need_derived_inputs = try step.addDirectoryWatchInput(maker, src_dir_lazy_path);

    var src_dir = src_dir_path.root_dir.handle.openDir(
        io,
        src_dir_path.subPathOrDot(),
        .{ .iterate = true },
    ) catch |err| return step.fail(maker, "failed opening source directory {f}: {t}", .{ src_dir_path, err });
    defer src_dir.close(io);

    const exclude_extensions = conf_id.exclude_extensions.slice;
    const include_extensions: ?[]const Configuration.String = if (conf_id.flags.include_extensions_active)
        conf_id.include_extensions.slice
    else
        null;
    const blank_extensions = conf_id.blank_extensions.slice;

    var all_cached = true;
    var it = try src_dir.walk(gpa);
    defer it.deinit();
    next_entry: while (it.next(io) catch |err| switch (err) {
        error.Canceled, error.OutOfMemory => |e| return e,
        else => |e| return step.fail(maker, "failed iterating dir {f}: {t}", .{ src_dir_path, e }),
    }) |entry| {
        for (exclude_extensions) |ext| {
            if (endsWith(u8, entry.path, ext.slice(conf))) continue :next_entry;
        }
        if (include_extensions) |includes| {
            for (includes) |inc| {
                if (endsWith(u8, entry.path, inc.slice(conf))) break;
            } else {
                continue :next_entry;
            }
        }

        const dest_path = try dest_prefix.join(arena, entry.path);
        switch (entry.kind) {
            .directory => {
                if (need_derived_inputs) {
                    const entry_path = try src_dir_path.join(arena, entry.path);
                    try step.addDirectoryWatchInputFromPath(maker, entry_path);
                }
                const p = try maker.installDir(arena, dest_path, step_index);
                all_cached = all_cached and p == .existed;
            },
            .file => {
                for (blank_extensions) |ext| {
                    if (endsWith(u8, entry.path, ext.slice(conf))) {
                        try maker.truncatePath(arena, dest_path, step_index);
                        continue :next_entry;
                    }
                }

                const entry_path = try src_dir_path.join(arena, entry.path);
                const p = try maker.installPath(arena, entry_path, dest_path, step_index);
                all_cached = all_cached and p == .fresh;
                progress_node.completeOne();
            },
            else => continue,
        }
    }

    step.result_cached = all_cached;
}
