const FindProgram = @This();
const builtin = @import("builtin");

const std = @import("std");
const Io = std.Io;
const Configuration = std.Build.Configuration;
const assert = std.debug.assert;

const Step = @import("../Step.zig");
const Maker = @import("../../Maker.zig");

pub fn make(
    find_program: *FindProgram,
    step_index: Configuration.Step.Index,
    maker: *Maker,
    progress_node: std.Progress.Node,
) Step.ExtendedMakeError!void {
    _ = find_program;
    _ = progress_node;
    const graph = maker.graph;
    const step = maker.stepByIndex(step_index);
    const arena = graph.arena; // TODO don't leak into the process arena
    const conf = &maker.scanned_config.configuration;
    const conf_step = step_index.ptr(conf);
    const conf_fp = conf_step.extended.get(conf.extra).find_program;
    const found_path = conf_fp.found_path;
    const names = conf_fp.names.slice(conf);

    // In case we fail at the end.
    var err_msg: std.ArrayList(u8) = .empty;
    try err_msg.appendSlice(arena, "program not found. searched paths:\n");

    for (names) |name_index| {
        const name = name_index.slice(conf);

        if (Io.Dir.path.isAbsolute(name)) {
            if (try checkCandidate(maker, step, found_path, &err_msg, name)) return;

            continue;
        }

        for (graph.search_prefixes.items) |search_prefix| {
            const full_path = try Io.Dir.path.join(arena, &.{ search_prefix, "bin", name });

            if (try checkCandidate(maker, step, found_path, &err_msg, full_path)) return;
        }
    }

    if (graph.environ_map.get("PATH")) |PATH| {
        for (names) |name_index| {
            const name = name_index.slice(conf);

            var it = std.mem.tokenizeScalar(u8, PATH, Io.Dir.path.delimiter);
            while (it.next()) |p| {
                const full_path = try Io.Dir.path.join(arena, &.{ p, name });

                if (try checkCandidate(maker, step, found_path, &err_msg, full_path)) return;
            }
        }
    }

    assert(err_msg.items[err_msg.items.len - 1] == '\n');
    const chopped = err_msg.items[0 .. err_msg.items.len - 1];
    try step.result_error_msgs.append(arena, chopped);
    return error.MakeFailed;
}

fn checkCandidate(
    maker: *Maker,
    step: *Step,
    found_path: Configuration.GeneratedFileIndex,
    err_msg: *std.ArrayList(u8),
    full_path: []const u8,
) !bool {
    const graph = maker.graph;
    const arena = graph.arena; // TODO don't leak into process arena
    const io = graph.io;

    if (Io.Dir.cwd().access(io, full_path, .{ .execute = true })) |_| {
        maker.generatedPath(found_path).* = .initCwd(full_path);
        return true;
    } else |err| switch (err) {
        error.Canceled => |e| return e,
        error.FileNotFound, error.AccessDenied, error.PermissionDenied => |e| {
            try err_msg.print(arena, "{t} {s}\n", .{ e, full_path });
        },
        else => |e| return step.fail(maker, "failed accessing {s}: {t}", .{ full_path, e }),
    }

    if (builtin.os.tag == .windows) {
        if (graph.environ_map.get("PATHEXT")) |PATHEXT| {
            var it = std.mem.tokenizeScalar(u8, PATHEXT, Io.Dir.path.delimiter);
            while (it.next()) |ext| {
                if (!supportedWindowsProgramExtension(ext)) continue;

                const extended_path = try std.mem.concat(arena, u8, &.{ full_path, ext });

                if (Io.Dir.cwd().access(io, extended_path, .{ .execute = true })) |_| {
                    maker.generatedPath(found_path).* = .initCwd(extended_path);
                    return true;
                } else |err| switch (err) {
                    error.Canceled => |e| return e,
                    error.FileNotFound, error.AccessDenied, error.PermissionDenied => |e| {
                        try err_msg.print(arena, "{t} {s}\n", .{ e, extended_path });
                    },
                    else => |e| return step.fail(maker, "failed accessing {s}: {t}", .{ extended_path, e }),
                }
            }
        }
    }

    return false;
}

fn supportedWindowsProgramExtension(ext: []const u8) bool {
    inline for (@typeInfo(std.process.WindowsExtension).@"enum".field_names) |field_name| {
        if (std.ascii.eqlIgnoreCase(ext, "." ++ field_name)) return true;
    }
    return false;
}
