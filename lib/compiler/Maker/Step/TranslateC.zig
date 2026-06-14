const TranslateC = @This();

const std = @import("std");
const Io = std.Io;
const Configuration = std.Build.Configuration;
const allocPrint = std.fmt.allocPrint;
const assert = std.debug.assert;
const OptimizeMode = std.lang.OptimizeMode;

const Step = @import("../Step.zig");
const Maker = @import("../../Maker.zig");
const PkgConfig = @import("../PkgConfig.zig");

pub fn make(
    translate_c: *TranslateC,
    step_index: Configuration.Step.Index,
    maker: *Maker,
    progress_node: std.Progress.Node,
) Step.ExtendedMakeError!void {
    _ = translate_c;
    const graph = maker.graph;
    const arena = graph.arena; // TODO don't leak into the process arena
    const step = maker.stepByIndex(step_index);
    const conf = &maker.scanned_config.configuration;
    const conf_step = step_index.ptr(conf);
    const conf_tc = conf_step.extended.get(conf.extra).translate_c;
    const cache_root = graph.local_cache_root;

    var argv: std.ArrayList([]const u8) = .empty;

    try argv.ensureUnusedCapacity(arena, 10);
    argv.appendAssumeCapacity(graph.zig_exe);
    argv.appendAssumeCapacity("translate-c");
    if (conf_tc.flags.link_libc) {
        argv.appendAssumeCapacity("-lc");
    }

    argv.appendAssumeCapacity("--cache-dir");
    argv.appendAssumeCapacity(cache_root.path orelse ".");

    argv.appendAssumeCapacity("--global-cache-dir");
    argv.appendAssumeCapacity(graph.global_cache_root.path orelse ".");

    if (conf_tc.target.get(conf)) |resolved_target| {
        if (resolved_target.unwrapQuery(conf)) |query| {
            argv.appendAssumeCapacity("-target");
            argv.appendAssumeCapacity(try query.zigTriple(arena));
        }
    }

    const opt: ?OptimizeMode = switch (conf_tc.flags.optimize) {
        .debug, .default => null, // Skip since it's the default
        .safe => .ReleaseSafe,
        .fast => .ReleaseFast,
        .small => .ReleaseSmall,
    };
    if (opt) |o| argv.appendAssumeCapacity(try allocPrint(arena, "-O{t}", .{o}));

    try argv.ensureUnusedCapacity(arena, conf_tc.include_dirs.len * 2);
    for (0..conf_tc.include_dirs.len) |i|
        try Step.Compile.appendIncludeDirFlags(arena, conf_tc.include_dirs.get(conf.extra, i), &argv, step_index, maker);

    for (conf_tc.c_macros.slice) |c_macro| {
        (try argv.addManyAsArray(arena, 2)).* = .{ "-D", c_macro.slice(conf) };
    }

    var prev_search_strategy: std.Build.Module.SystemLib.SearchStrategy = .paths_first;
    var prev_preferred_link_mode: std.builtin.LinkMode = .dynamic;
    var seen_system_libs: std.array_hash_map.Auto(Configuration.String, []const []const u8) = .empty;

    for (conf_tc.system_libs.slice) |system_lib_index| {
        const system_lib = system_lib_index.get(conf);
        const system_lib_name = system_lib.name.slice(conf);
        const system_lib_gop = try seen_system_libs.getOrPut(arena, system_lib.name);
        if (system_lib_gop.found_existing) {
            try argv.appendSlice(arena, system_lib_gop.value_ptr.*);
            continue;
        } else {
            system_lib_gop.value_ptr.* = &.{};
        }

        if ((system_lib.flags.search_strategy != prev_search_strategy or
            system_lib.flags.preferred_link_mode != prev_preferred_link_mode))
        {
            try argv.ensureUnusedCapacity(arena, 1);
            switch (system_lib.flags.search_strategy) {
                .no_fallback => switch (system_lib.flags.preferred_link_mode) {
                    .dynamic => argv.appendAssumeCapacity("-search_dylibs_only"),
                    .static => argv.appendAssumeCapacity("-search_static_only"),
                },
                .paths_first => switch (system_lib.flags.preferred_link_mode) {
                    .dynamic => argv.appendAssumeCapacity("-search_paths_first"),
                    .static => argv.appendAssumeCapacity("-search_paths_first_static"),
                },
                .mode_first => switch (system_lib.flags.preferred_link_mode) {
                    .dynamic => argv.appendAssumeCapacity("-search_dylibs_first"),
                    .static => argv.appendAssumeCapacity("-search_static_first"),
                },
            }
            prev_search_strategy = system_lib.flags.search_strategy;
            prev_preferred_link_mode = system_lib.flags.preferred_link_mode;
        }

        const prefix: []const u8 = prefix: {
            if (system_lib.flags.needed) break :prefix "-needed-l";
            if (system_lib.flags.weak) break :prefix "-weak-l";
            break :prefix "-l";
        };
        l: {
            pc: {
                const force = switch (system_lib.flags.use_pkg_config) {
                    .no => break :pc,
                    .yes => false,
                    .force => true,
                };

                const pkg_conf_node = progress_node.start("pkg-config", 0);
                defer pkg_conf_node.end();

                if (PkgConfig.run(maker, step, arena, pkg_conf_node, system_lib_name, force)) |result| {
                    try argv.appendSlice(arena, result.cflags);
                    try argv.appendSlice(arena, result.libs);
                    try seen_system_libs.put(arena, system_lib.name, result.cflags);
                    break :l;
                } else |err| switch (err) {
                    error.PkgConfigUnavailable,
                    error.PackageNotFound,
                    => {
                        // pkg-config failed, so fall back to linking the library by name directly.
                        assert(!force);
                        break :pc;
                    },
                    else => |e| return e,
                }
            }
            try argv.append(arena, try allocPrint(arena, "{s}{s}", .{
                prefix, system_lib_name,
            }));
        }
    }

    try argv.ensureUnusedCapacity(arena, 2);

    const c_source_path = try maker.resolveLazyPathIndexAbs(arena, conf_tc.src_path, step_index);
    argv.appendAssumeCapacity(c_source_path);

    argv.appendAssumeCapacity("--listen=-");
    const output_dir_path = (Step.evalZigProcess(step_index, maker, argv.items, progress_node, false) catch |err| switch (err) {
        error.NeedCompileErrorCheck => unreachable,
        else => |e| return e,
    }).?;

    const stem = Io.Dir.path.stem(Io.Dir.path.basename(c_source_path));
    const out_basename = try allocPrint(arena, "{s}.zig", .{stem});

    maker.generatedPath(conf_tc.output_file).* = try output_dir_path.join(arena, out_basename);
}
