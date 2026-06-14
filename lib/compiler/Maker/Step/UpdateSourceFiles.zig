const UpdateSourceFiles = @This();

const std = @import("std");
const Io = std.Io;
const Path = std.Build.Cache.Path;
const allocPrint = std.fmt.allocPrint;
const Configuration = std.Build.Configuration;

const Step = @import("../Step.zig");
const Maker = @import("../../Maker.zig");

pub fn make(
    usf: *UpdateSourceFiles,
    step_index: Configuration.Step.Index,
    maker: *Maker,
    progress_node: std.Progress.Node,
) Step.ExtendedMakeError!void {
    _ = usf;
    const graph = maker.graph;
    const arena = maker.graph.arena; // TODO don't leak into process arena
    const io = graph.io;
    const step = maker.stepByIndex(step_index);
    const conf = &maker.scanned_config.configuration;
    const conf_step = step_index.ptr(conf);
    const conf_usf = conf_step.extended.get(conf.extra).update_source_files;
    const build_root = graph.build_root_directory;

    if (conf_step.owner != .root)
        return step.fail(maker, "non-root package attempted to update its source files", .{});

    var any_miss = false;

    progress_node.setEstimatedTotalItems(conf_usf.embeds.slice.len + conf_usf.copies.slice.len);

    step.clearWatchInputs(maker);

    for (conf_usf.embeds.slice) |*embed| {
        const dest_path: Path = .{
            .root_dir = build_root,
            .sub_path = embed.sub_path.slice(conf),
        };
        if (Io.Dir.path.dirname(dest_path.sub_path)) |dirname| {
            const dirname_path: Path = .{
                .root_dir = build_root,
                .sub_path = dirname,
            };
            dirname_path.root_dir.handle.createDirPath(io, dirname_path.sub_path) catch |err|
                return step.fail(maker, "failed creating path {f}: {t}", .{ dirname_path, err });
        }
        dest_path.root_dir.handle.writeFile(io, .{
            .sub_path = dest_path.sub_path,
            .data = embed.contents.slice(conf),
        }) catch |err| return step.fail(maker, "failed writing file {f}: {t}", .{ dest_path, err });
        any_miss = true;
        progress_node.completeOne();
    }

    for (conf_usf.copies.slice) |*copy| {
        const dest_path: Path = .{
            .root_dir = build_root,
            .sub_path = copy.sub_path.slice(conf),
        };
        if (Io.Dir.path.dirname(dest_path.sub_path)) |dirname| {
            const dirname_path: Path = .{
                .root_dir = build_root,
                .sub_path = dirname,
            };
            dirname_path.root_dir.handle.createDirPath(io, dirname_path.sub_path) catch |err|
                return step.fail(maker, "failed creating path {f}: {t}", .{ dirname_path, err });
        }
        const src_lazy_path = copy.src_file.get(conf);
        const source_path = try maker.resolveLazyPath(arena, src_lazy_path, step_index);
        try step.addWatchInput(maker, arena, src_lazy_path);

        const prev_status = source_path.root_dir.handle.updateFile(
            io,
            source_path.sub_path,
            dest_path.root_dir.handle,
            dest_path.sub_path,
            .{},
        ) catch |err| return step.fail(maker, "failed updating file from {f} to {f}: {t}", .{
            source_path, dest_path, err,
        });
        any_miss = any_miss or prev_status == .stale;
        progress_node.completeOne();
    }

    step.result_cached = !any_miss;
}
