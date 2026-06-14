const ObjCopy = @This();

const std = @import("std");
const Io = std.Io;
const Path = std.Build.Cache.Path;
const allocPrint = std.fmt.allocPrint;
const Configuration = std.Build.Configuration;

const Step = @import("../Step.zig");
const Maker = @import("../../Maker.zig");

pub fn make(
    obj_copy: *ObjCopy,
    step_index: Configuration.Step.Index,
    maker: *Maker,
    progress_node: std.Progress.Node,
) Step.ExtendedMakeError!void {
    _ = obj_copy;
    const graph = maker.graph;
    const arena = maker.graph.arena; // TODO don't leak into process arena
    const io = graph.io;
    const step = maker.stepByIndex(step_index);
    const conf = &maker.scanned_config.configuration;
    const conf_step = step_index.ptr(conf);
    const conf_oc = conf_step.extended.get(conf.extra).obj_copy;
    const cache_root = graph.local_cache_root;
    const input_lazy_path = conf_oc.input_file.get(conf);
    const only_section: ?[]const u8 = if (conf_oc.only_section.value) |s| s.slice(conf) else null;
    const opt_basename: ?[]const u8 = if (conf_oc.basename.value) |s| s.slice(conf) else null;
    const opt_debug_basename: ?[]const u8 = if (conf_oc.debug_basename.value) |s| s.slice(conf) else null;

    try step.singleUnchangingWatchInput(maker, arena, input_lazy_path);

    var man = graph.cache.obtain();
    defer man.deinit();

    const input_path = try maker.resolveLazyPath(arena, input_lazy_path, step_index);
    _ = try man.addFilePath(input_path, null);
    man.hash.addOptionalBytes(only_section);
    man.hash.addOptionalBytes(opt_basename);
    man.hash.addOptionalBytes(opt_debug_basename);
    man.hash.addOptional(conf_oc.pad_to.value);
    man.hash.add(conf_oc.flags.format);
    man.hash.add(conf_oc.flags.compress_debug);
    man.hash.add(conf_oc.flags.strip);
    man.hash.add(conf_oc.debug_file.value != null);

    const basename = opt_basename orelse Io.Dir.path.basename(input_path.sub_path);

    if (try step.cacheHit(maker, &man)) {
        // Cache hit, skip subprocess execution.
        const digest = man.final();
        maker.generatedPath(conf_oc.output_file).* = .{
            .root_dir = cache_root,
            .sub_path = try Io.Dir.path.join(arena, &.{ "o", &digest, basename }),
        };
        if (conf_oc.debug_file.value) |debug_file| {
            const debug_basename = opt_debug_basename orelse try allocPrint(arena, "{s}.debug", .{
                Io.Dir.path.basename(input_path.sub_path),
            });
            maker.generatedPath(debug_file).* = .{
                .root_dir = cache_root,
                .sub_path = try Io.Dir.path.join(arena, &.{ "o", &digest, debug_basename }),
            };
        }
        return;
    }

    // We don't find out more input files while executing objcopy so we can
    // already obtain the digest and use it directly as the output path.
    const digest = man.final();
    const dest_path: Path = .{
        .root_dir = cache_root,
        .sub_path = try Io.Dir.path.join(arena, &.{ "o", &digest, basename }),
    };
    const dest_dirname = dest_path.dirname().?;
    dest_dirname.root_dir.handle.createDirPath(io, dest_dirname.sub_path) catch |err|
        return step.fail(maker, "failed to create path {f}: {t}", .{ dest_dirname, err });

    var argv: std.ArrayList([]const u8) = .empty;
    try argv.ensureUnusedCapacity(arena, 11);

    argv.addManyAsArrayAssumeCapacity(2).* = .{ graph.zig_exe, "objcopy" };

    if (only_section) |s| argv.addManyAsArrayAssumeCapacity(2).* = .{ "-j", s };

    switch (conf_oc.flags.strip) {
        .none => {},
        .debug => argv.appendAssumeCapacity("--strip-debug"),
        .debug_and_symbols => argv.appendAssumeCapacity("--strip-all"),
    }

    if (conf_oc.pad_to.value) |pad_to| {
        argv.addManyAsArrayAssumeCapacity(2).* = .{
            "--pad-to", try allocPrint(arena, "{d}", .{pad_to}),
        };
    }

    switch (conf_oc.flags.format) {
        .default => {},
        else => |t| argv.addManyAsArrayAssumeCapacity(2).* = .{ "-O", @tagName(t) },
    }

    if (conf_oc.flags.compress_debug)
        argv.appendAssumeCapacity("--compress-debug-sections");

    if (conf_oc.debug_file.value) |debug_file| {
        const debug_basename = opt_debug_basename orelse try allocPrint(arena, "{s}.debug", .{
            Io.Dir.path.basename(input_path.sub_path),
        });
        const debug_dest_path: Path = .{
            .root_dir = cache_root,
            .sub_path = try Io.Dir.path.join(arena, &.{ "o", &digest, debug_basename }),
        };
        argv.appendAssumeCapacity(try allocPrint(arena, "--extract-to={f}", .{debug_dest_path}));
        maker.generatedPath(debug_file).* = debug_dest_path;
    }

    try argv.ensureUnusedCapacity(arena, conf_oc.add_section.slice.len * 2);

    for (conf_oc.add_section.slice) |section| {
        argv.appendAssumeCapacity("--add-section");
        argv.appendAssumeCapacity(try allocPrint(arena, "{s}={f}", .{
            section.section_name.slice(conf),
            try maker.resolveLazyPathIndex(arena, section.file_path, step_index),
        }));
    }

    for (conf_oc.update_section.slice) |update| {
        const name = update.section_name.slice(conf);

        try argv.ensureUnusedCapacity(arena, 4);

        if (update.flags.alignment.toBytes()) |a| {
            argv.appendAssumeCapacity("--set-section-alignment");
            argv.appendAssumeCapacity(try allocPrint(arena, "{s}={d}", .{ name, a }));
        }

        const f = update.flags.section_flags;
        if (f != Configuration.Step.ObjCopy.SectionFlags.default) {
            // trailing comma is allowed
            argv.appendAssumeCapacity("--set-section-flags");
            argv.appendAssumeCapacity(try allocPrint(arena, "{s}={s}{s}{s}{s}{s}{s}{s}{s}{s}", .{
                name,
                if (f.alloc) "alloc," else "",
                if (f.contents) "contents," else "",
                if (f.load) "load," else "",
                if (f.readonly) "readonly," else "",
                if (f.code) "code," else "",
                if (f.exclude) "exclude," else "",
                if (f.large) "large," else "",
                if (f.merge) "merge," else "",
                if (f.strings) "strings," else "",
            }));
        }
    }

    argv.appendAssumeCapacity(try allocPrint(arena, "{f}", .{input_path}));
    argv.appendAssumeCapacity(try allocPrint(arena, "{f}", .{dest_path}));

    argv.appendAssumeCapacity("--listen=-");
    _ = Step.evalZigProcess(step_index, maker, argv.items, progress_node, false) catch |err| switch (err) {
        error.NeedCompileErrorCheck => unreachable,
        else => |e| return e,
    };

    maker.generatedPath(conf_oc.output_file).* = dest_path;

    step.writeManifest(maker, &man) catch |err| switch (err) {
        error.Canceled => |e| return e,
        else => |e| try step.addError(maker, "failed writing cache manifest: {t}", .{e}),
    };
}
