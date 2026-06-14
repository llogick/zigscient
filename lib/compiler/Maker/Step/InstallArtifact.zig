const InstallArtifact = @This();

const std = @import("std");
const Io = std.Io;
const Configuration = std.Build.Configuration;
const assert = std.debug.assert;

const Step = @import("../Step.zig");
const Maker = @import("../../Maker.zig");

pub fn make(
    install_artifact: *InstallArtifact,
    step_index: Configuration.Step.Index,
    maker: *Maker,
    progress_node: std.Progress.Node,
) Step.ExtendedMakeError!void {
    _ = install_artifact;
    _ = progress_node;
    const step = maker.stepByIndex(step_index);
    const conf = &maker.scanned_config.configuration;
    const graph = maker.graph;
    const gpa = maker.gpa;
    const arena = graph.arena; // TODO don't leak into process arena
    const io = graph.io;
    const conf_step = step_index.ptr(conf);
    const conf_ia = conf_step.extended.get(conf.extra).install_artifact;
    const compile_step_index = conf_step.deps.get(conf).steps.slice[0];
    const conf_comp_step = compile_step_index.ptr(conf);
    const conf_comp = conf_comp_step.extended.get(conf.extra).compile;
    const root_module = conf_comp.root_module.get(conf);
    const target = root_module.resolved_target.get(conf).?.result.get(conf);

    var all_cached = true;

    if (conf_ia.bin_dir.value) |bin_dir| {
        if (conf_comp.generated_bin.value) |generated_bin| {
            const bin_sub_path = if (conf_ia.bin_sub_path.value) |s| s.slice(conf) else try std.zig.binNameAlloc(arena, .{
                .root_name = conf_comp.root_name.slice(conf),
                .cpu_arch = target.flags.cpu_arch.unwrap().?,
                .os_tag = target.flags.os_tag.unwrap().?,
                .ofmt = target.flags.object_format.unwrap().?,
                .abi = target.flags.abi.unwrap().?,
                .output_mode = conf_comp.flags3.kind.toOutputMode(),
                .link_mode = conf_comp.flags2.linkage.unwrap(),
                .version = v: {
                    const string = conf_comp.version.value orelse break :v null;
                    const slice = string.slice(conf);
                    break :v std.SemanticVersion.parse(slice) catch @panic("bad semver string");
                },
            });
            const dest_dir = try maker.resolveInstallDir(arena, bin_dir);
            const dest_path = try dest_dir.join(arena, bin_sub_path);
            const src_path = maker.generatedPath(generated_bin).*;
            const p = try maker.installPath(arena, src_path, dest_path, step_index);
            all_cached = all_cached and p == .fresh;

            if (conf_ia.flags.dylib_symlinks)
                try maker.installSymLinks(arena, dest_path, compile_step_index, step_index);

            const make_comp_step = maker.stepByIndex(compile_step_index);
            const make_comp = &make_comp_step.extended.compile;
            make_comp.installed_path = dest_path;
        }
    }

    if (conf_ia.implib_dir.value) |implib_dir| {
        if (conf_comp.generated_implib.value) |generated_implib| {
            const p = try maker.installGenerated(arena, generated_implib, implib_dir, step_index);
            all_cached = all_cached and p == .fresh;
        }
    }

    if (conf_ia.pdb_dir.value) |pdb_dir| {
        if (conf_comp.generated_pdb.value) |generated_pdb| {
            const p = try maker.installGenerated(arena, generated_pdb, pdb_dir, step_index);
            all_cached = all_cached and p == .fresh;
        }
    }

    if (conf_ia.h_dir.value) |h_dir| {
        const h_prefix = try maker.resolveInstallDir(arena, h_dir);

        if (conf_comp.generated_h.value) |generated_h| {
            const p = try maker.installGenerated(arena, generated_h, h_dir, step_index);
            all_cached = all_cached and p == .fresh;
        }

        for (conf_comp.installed_headers.slice) |installation| switch (installation.get(conf.extra)) {
            .file => |file| {
                const src_path = try maker.resolveLazyPathIndex(arena, file.source, step_index);
                const dest_path = try h_prefix.join(arena, file.dest_sub_path.slice(conf));
                const p = try maker.installPath(arena, src_path, dest_path, step_index);
                all_cached = all_cached and p == .fresh;
            },
            .directory => |dir| {
                const src_dir_path = try maker.resolveLazyPathIndex(arena, dir.source, step_index);
                const full_h_prefix = try h_prefix.join(arena, dir.dest_sub_path.slice(conf));

                var src_dir = src_dir_path.root_dir.handle.openDir(io, src_dir_path.subPathOrDot(), .{ .iterate = true }) catch |err| {
                    return step.fail(maker, "unable to open source directory {f}: {t}", .{ src_dir_path, err });
                };
                defer src_dir.close(io);

                var it = try src_dir.walk(gpa);
                defer it.deinit();
                next_entry: while (it.next(io) catch |err| switch (err) {
                    error.Canceled, error.OutOfMemory => |e| return e,
                    else => |e| return step.fail(maker, "failed to iterate directory {f}: {t}", .{ src_dir_path, e }),
                }) |entry| {
                    for (dir.exclude_extensions.slice) |ext| {
                        if (std.mem.endsWith(u8, entry.path, ext.slice(conf))) continue :next_entry;
                    }
                    if (dir.flags.include_extensions) {
                        for (dir.include_extensions.slice) |inc| {
                            if (std.mem.endsWith(u8, entry.path, inc.slice(conf))) break;
                        } else {
                            continue :next_entry;
                        }
                    }

                    const full_dest_path = try full_h_prefix.join(arena, entry.path);
                    switch (entry.kind) {
                        .directory => {
                            const p = try maker.installDir(arena, full_dest_path, step_index);
                            all_cached = all_cached and p == .existed;
                        },
                        .file => {
                            const entry_dir_path = try maker.resolveLazyPathIndex(arena, dir.source, step_index);
                            const entry_path = try entry_dir_path.join(arena, entry.path);
                            const p = try maker.installPath(arena, entry_path, full_dest_path, step_index);
                            all_cached = all_cached and p == .fresh;
                        },
                        else => continue,
                    }
                }
            },
        };
    }

    step.result_cached = all_cached;
}
