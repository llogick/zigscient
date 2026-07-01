const Options = @This();

const std = @import("std");
const Io = std.Io;
const Configuration = std.Build.Configuration;
const Cache = std.Build.Cache;

const Step = @import("../Step.zig");
const Maker = @import("../../Maker.zig");

pub fn make(
    options: *Options,
    step_index: Configuration.Step.Index,
    maker: *Maker,
    progress_node: std.Progress.Node,
) Step.ExtendedMakeError!void {
    _ = options;

    const graph = maker.graph;
    const step = maker.stepByIndex(step_index);
    const io = graph.io;
    const cache_root = graph.local_cache_root;
    const arena = graph.arena; // TODO don't leak into the process arena
    const conf = &maker.scanned_config.configuration;
    const conf_step = step_index.ptr(conf);
    const conf_options = conf_step.extended.get(conf.extra).options;
    const contents = conf_options.contents.slice(conf);

    // This step operates under the assumption that all contents of the
    // generated zig file are observable by dependant steps, as well as the
    // contents of files added via Options.Arg.

    step.clearWatchInputs(maker);

    var man = graph.cache.obtain();
    defer man.deinit();

    var args_bytes: std.ArrayList(u8) = .empty;

    for (conf_options.args.slice) |arg| {
        const name = arg.name.slice(conf);
        const lazy_path = arg.path.get(conf);
        try step.addWatchInput(maker, arena, lazy_path);
        const arg_path = try maker.resolveLazyPath(arena, lazy_path, step_index);
        // _ = try man.addFilePath(arg_path, null);
        try args_bytes.print(arena, "pub const {f}: []const u8 = \"{f}\";\n", .{
            std.zig.fmtId(name), arg_path.fmtEscapeString(),
        });
    }

    man.hash.addBytes(contents);
    man.hash.addBytes(args_bytes.items);

    const basename = "options.zig";

    if (try step.cacheHitWatched(maker, &man, progress_node)) {
        const digest = man.final();
        maker.generatedPath(conf_options.generated_file).* = .{
            .root_dir = cache_root,
            .sub_path = try Io.Dir.path.join(arena, &.{ "o", &digest, basename }),
        };
        step.result_cached = true;
        return;
    }

    const digest = man.final();
    const out_path: Cache.Path = .{
        .root_dir = cache_root,
        .sub_path = try Io.Dir.path.join(arena, &.{ "o", &digest, basename }),
    };

    var file: Io.File = out_path.root_dir.handle.createFile(io, out_path.sub_path, .{}) catch |err| switch (err) {
        error.Canceled => |e| return e,
        error.FileNotFound => f: {
            out_path.root_dir.handle.createDirPath(io, Io.Dir.path.dirname(out_path.sub_path).?) catch |inner| switch (inner) {
                error.Canceled => |e| return e,
                else => |e| return step.fail(maker, "failed to create {f}: {t}", .{ out_path, e }),
            };
            break :f out_path.root_dir.handle.createFile(io, out_path.sub_path, .{}) catch |inner| switch (inner) {
                error.Canceled => |e| return e,
                else => |e| return step.fail(maker, "failed to create {f}: {t}", .{ out_path, e }),
            };
        },
        else => |e| return step.fail(maker, "failed to create {f}: {t}", .{ out_path, e }),
    };
    defer file.close(io);

    // No buffer because we already have all contents buffered.
    var file_writer = file.writer(io, &.{});
    var data: [2][]const u8 = .{ contents, args_bytes.items };
    file_writer.interface.writeVecAll(&data) catch |write_err| switch (write_err) {
        error.WriteFailed => switch (file_writer.err.?) {
            error.Canceled => |e| return e,
            else => |e| return step.fail(maker, "failed to write to {f}: {t}", .{ out_path, e }),
        },
    };

    try step.writeManifestAndWatch(maker, &man);

    maker.generatedPath(conf_options.generated_file).* = out_path;
}
