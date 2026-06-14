const WriteFile = @This();

const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const Path = std.Build.Cache.Path;
const allocPrint = std.fmt.allocPrint;
const Configuration = std.Build.Configuration;

const Step = @import("../Step.zig");
const Maker = @import("../../Maker.zig");

pub fn make(
    wf: *WriteFile,
    step_index: Configuration.Step.Index,
    maker: *Maker,
    progress_node: std.Progress.Node,
) Step.ExtendedMakeError!void {
    _ = wf;
    const graph = maker.graph;
    const gpa = maker.gpa;
    const arena = maker.graph.arena; // TODO don't leak into process arena
    const io = graph.io;
    const step = maker.stepByIndex(step_index);
    const conf = &maker.scanned_config.configuration;
    const conf_step = step_index.ptr(conf);
    const conf_wf = conf_step.extended.get(conf.extra).write_file;
    const cache_root = graph.local_cache_root;
    const directories = conf_wf.directories.slice;

    const open_dir_cache = try arena.alloc(Io.Dir, directories.len);
    var open_dirs_count: u32 = 0;
    defer Io.Dir.closeMany(io, open_dir_cache[0..open_dirs_count]);

    // Doesn't yet include contents of directories.
    var total_items: usize = conf_wf.embeds.slice.len + conf_wf.copies.slice.len + conf_wf.directories.slice.len;
    progress_node.setEstimatedTotalItems(total_items);

    switch (conf_wf.flags.mode) {
        .whole_cached => {
            step.clearWatchInputs(maker);

            // The cache is used here primarily as a way to find a canonical
            // location to put build artifacts without parallel step execution
            // clobbering each other.

            var man = graph.cache.obtain();
            defer man.deinit();

            for (conf_wf.embeds.slice) |*embed| {
                man.hash.addBytes(embed.sub_path.slice(conf));
                man.hash.addBytes(embed.contents.slice(conf));
            }

            for (conf_wf.copies.slice) |*copy| {
                man.hash.addBytes(copy.sub_path.slice(conf));
                const src_lazy_path = copy.src_file.get(conf);
                const source_path = try maker.resolveLazyPath(arena, src_lazy_path, step_index);
                _ = try man.addFilePath(source_path, null);
                try step.addWatchInput(maker, arena, src_lazy_path);
            }

            for (directories, open_dir_cache) |conf_dir, *opened_dir| {
                const exclude_extensions = conf_dir.exclude_extensions.slice(conf) orelse &.{};
                const include_extensions = conf_dir.include_extensions.slice(conf);

                man.hash.addBytes(conf_dir.sub_path.slice(conf));
                for (exclude_extensions) |ext| man.hash.addBytes(ext.slice(conf));
                if (include_extensions) |includes| for (includes) |inc| {
                    man.hash.addBytes(inc.slice(conf));
                };

                const src_lazy_path = conf_dir.src_path.get(conf);
                const need_derived_inputs = try step.addDirectoryWatchInput(maker, src_lazy_path);
                const src_dir_path = try maker.resolveLazyPath(arena, src_lazy_path, step_index);

                var src_dir = src_dir_path.root_dir.handle.openDir(io, src_dir_path.subPathOrDot(), .{ .iterate = true }) catch |err| {
                    return step.fail(maker, "failed opening source directory {f}: {t}", .{ src_dir_path, err });
                };
                opened_dir.* = src_dir;
                open_dirs_count += 1;

                var it = try src_dir.walk(gpa);
                defer it.deinit();
                while (it.next(io) catch |err| switch (err) {
                    error.Canceled, error.OutOfMemory => |e| return e,
                    else => |e| return step.fail(maker, "failed iterating dir {f}: {t}", .{ src_dir_path, e }),
                }) |entry| {
                    if (!pathIncluded(conf, exclude_extensions, include_extensions, entry.path)) continue;

                    switch (entry.kind) {
                        .directory => {
                            if (need_derived_inputs) {
                                const entry_path = try src_dir_path.join(arena, entry.path);
                                try step.addDirectoryWatchInputFromPath(maker, entry_path);
                            }
                        },
                        .file => {
                            const entry_path = try src_dir_path.join(arena, entry.path);
                            _ = try man.addFilePath(entry_path, null);
                            total_items += 1;
                        },
                        else => continue,
                    }
                }
            }

            if (try step.cacheHit(maker, &man)) {
                const digest = man.final();
                maker.generatedPath(conf_wf.generated_directory).* = .{
                    .root_dir = cache_root,
                    .sub_path = try Io.Dir.path.join(arena, &.{ "o", &digest }),
                };
                assert(step.result_cached);
                return;
            }

            const digest = man.final();
            const out_path: Path = .{
                .root_dir = cache_root,
                .sub_path = try Io.Dir.path.join(arena, &.{ "o", &digest }),
            };

            progress_node.setEstimatedTotalItems(total_items);
            try operate(maker, step_index, open_dir_cache, out_path, progress_node);
            try step.writeManifest(maker, &man);

            maker.generatedPath(conf_wf.generated_directory).* = out_path;
        },
        .tmp => {
            step.result_cached = false;

            var rand_int: u64 = undefined;
            io.random(@ptrCast(&rand_int));
            const hex_digest = std.fmt.hex(rand_int);

            const out_path: Path = .{
                .root_dir = cache_root,
                .sub_path = try Io.Dir.path.join(arena, &.{ "tmp", &hex_digest }),
            };

            try operate(maker, step_index, open_dir_cache, out_path, progress_node);

            maker.generatedPath(conf_wf.generated_directory).* = out_path;
        },
        .mutate => {
            step.result_cached = false;
            const root_path = try maker.resolveLazyPathIndex(arena, conf_wf.mutate_path.value.?, step_index);
            try operate(maker, step_index, open_dir_cache, root_path, progress_node);
            maker.generatedPath(conf_wf.generated_directory).* = root_path;
        },
    }
}

fn operate(
    maker: *Maker,
    step_index: Configuration.Step.Index,
    open_dir_cache: []const Io.Dir,
    root_path: std.Build.Cache.Path,
    progress_node: std.Progress.Node,
) !void {
    const graph = maker.graph;
    const gpa = maker.gpa;
    const arena = maker.graph.arena; // TODO don't leak into process arena
    const io = graph.io;
    const step = maker.stepByIndex(step_index);
    const conf = &maker.scanned_config.configuration;
    const conf_step = step_index.ptr(conf);
    const conf_wf = conf_step.extended.get(conf.extra).write_file;

    const root_directory: std.Build.Cache.Directory = .{
        .handle = root_path.root_dir.handle.createDirPathOpen(io, root_path.sub_path, .{}) catch |err|
            return step.fail(maker, "failed creating path {f}: {t}", .{ root_path, err }),
        .path = try root_path.toString(arena),
    };
    defer root_directory.handle.close(io);

    for (conf_wf.embeds.slice) |*embed| {
        const dest_path: Path = .{
            .root_dir = root_directory,
            .sub_path = embed.sub_path.slice(conf),
        };
        if (Io.Dir.path.dirname(dest_path.sub_path)) |dirname| {
            const dirname_path: Path = .{
                .root_dir = root_directory,
                .sub_path = dirname,
            };
            dirname_path.root_dir.handle.createDirPath(io, dirname_path.sub_path) catch |err|
                return step.fail(maker, "failed creating path {f}: {t}", .{ dirname_path, err });
        }
        dest_path.root_dir.handle.writeFile(io, .{
            .sub_path = dest_path.sub_path,
            .data = embed.contents.slice(conf),
        }) catch |err| return step.fail(maker, "failed writing contents to file {f}: {t}", .{ dest_path, err });
        progress_node.completeOne();
    }

    for (conf_wf.copies.slice) |*copy| {
        const dest_path: Path = .{
            .root_dir = root_directory,
            .sub_path = copy.sub_path.slice(conf),
        };
        // Rather than passing make_path = true below, this optimizes for the
        // more common case where the directory does not exist.
        if (Io.Dir.path.dirname(dest_path.sub_path)) |dirname| {
            const dirname_path: Path = .{
                .root_dir = root_directory,
                .sub_path = dirname,
            };
            dirname_path.root_dir.handle.createDirPath(io, dirname_path.sub_path) catch |err|
                return step.fail(maker, "failed creating path {f}: {t}", .{ dirname_path, err });
        }
        const source_path = try maker.resolveLazyPathIndex(arena, copy.src_file, step_index);
        Io.Dir.copyFile(
            source_path.root_dir.handle,
            source_path.sub_path,
            dest_path.root_dir.handle,
            dest_path.sub_path,
            io,
            .{},
        ) catch |err| return step.fail(maker, "failed copying file from {f} to {f}: {t}", .{
            source_path, dest_path, err,
        });
        progress_node.completeOne();
    }

    for (conf_wf.directories.slice, open_dir_cache) |conf_dir, already_open_dir| {
        const exclude_extensions = conf_dir.exclude_extensions.slice(conf) orelse &.{};
        const include_extensions = conf_dir.include_extensions.slice(conf);

        const src_dir_path = try maker.resolveLazyPathIndex(arena, conf_dir.src_path, step_index);
        const dest_dir_path: Path = .{
            .root_dir = root_directory,
            .sub_path = conf_dir.sub_path.slice(conf),
        };

        if (dest_dir_path.sub_path.len != 0) {
            dest_dir_path.root_dir.handle.createDirPath(io, dest_dir_path.sub_path) catch |err|
                return step.fail(maker, "failed creating path {f}: {t}", .{ dest_dir_path, err });
        }

        var it = try already_open_dir.walk(gpa);
        defer it.deinit();
        while (it.next(io) catch |err| switch (err) {
            error.Canceled, error.OutOfMemory => |e| return e,
            else => |e| return step.fail(maker, "failed iterating dir {f}: {t}", .{ src_dir_path, e }),
        }) |entry| {
            if (!pathIncluded(conf, exclude_extensions, include_extensions, entry.path)) continue;

            const src_entry_path = try src_dir_path.join(arena, entry.path);
            const dest_path = try dest_dir_path.join(arena, entry.path);
            switch (entry.kind) {
                .directory => dest_path.root_dir.handle.createDirPath(io, dest_path.sub_path) catch |err| {
                    return step.fail(maker, "failed creating path {f}: {t}", .{ dest_path, err });
                },
                .file => {
                    Io.Dir.copyFile(
                        src_entry_path.root_dir.handle,
                        src_entry_path.sub_path,
                        dest_path.root_dir.handle,
                        dest_path.sub_path,
                        io,
                        .{ .make_path = true }, // Directory entry may be filtered out above.
                    ) catch |err| return step.fail(maker, "failed copying file from {f} to {f}: {t}", .{
                        src_entry_path, dest_path, err,
                    });
                    progress_node.completeOne();
                },
                else => continue,
            }
        }
    }
}

fn pathIncluded(
    conf: *const Configuration,
    exclude_extensions: []const Configuration.String,
    include_extensions: ?[]const Configuration.String,
    path: []const u8,
) bool {
    for (exclude_extensions) |ext| {
        if (std.mem.endsWith(u8, path, ext.slice(conf)))
            return false;
    }
    if (include_extensions) |incs| {
        for (incs) |inc| {
            if (std.mem.endsWith(u8, path, inc.slice(conf)))
                return true;
        } else {
            return false;
        }
    }
    return true;
}
