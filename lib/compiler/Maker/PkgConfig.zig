const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const Maker = @import("../Maker.zig");
const Step = @import("Step.zig");
const Graph = @import("Graph.zig");

mutex: Io.Mutex = .init,
pkgs: ?std.zig.PkgConfig = null,
debug: bool = false,

pub const RunError = error{
    PackageNotFound,
    PkgConfigUnavailable,
} || Step.ExtendedMakeError;

pub const Result = std.zig.PkgConfig.Parsed;

/// Run pkg-config for the given library name and parse the output, returning the arguments
/// that should be passed to zig to link the given library.
pub fn run(
    maker: *Maker,
    step: *Step,
    arena: Allocator,
    progress_node: std.Progress.Node,
    lib_name: []const u8,
    /// If true, reports failure error messages on step rather than returning
    /// error.PackageNotFound or error.PkgConfigUnavailable,
    force: bool,
) RunError!Result {
    const pc = &maker.pkg_config;
    const graph = maker.graph;

    const pkg_config_exe = getExe(graph);
    const pkgs = try getPkgs(maker, step, progress_node, force);
    const found_index = pkgs.find(lib_name) orelse {
        if (force) return step.fail(maker, "{s}: package not found: {s}", .{ pkg_config_exe, lib_name });
        return error.PackageNotFound;
    };
    const pkg = pkgs.all[found_index];

    const stdout = try captureChildProcess(maker, step, arena, .{
        .argv = &.{ pkg_config_exe, pkg.name, "--cflags", "--libs" },
        .progress_node = progress_node,
        .allow_failure = !force,
    });

    const parsed = std.zig.PkgConfig.parse(arena, stdout) catch |err| switch (err) {
        error.InvalidPkgConfigOutput => {
            if (force) return step.fail(maker, "{s} package {s} invalid output: {s}", .{
                pkg_config_exe, lib_name, stdout,
            });
            return error.PkgConfigUnavailable;
        },
        else => |e| return e,
    };
    if (force or pc.debug) {
        for (parsed.unknown_flags) |unknown_flag| {
            return step.fail(maker, "{s} package {s} unknown flag: {s}", .{ pkg_config_exe, lib_name, unknown_flag });
        }
    }

    return parsed;
}

fn getExe(graph: *const Graph) []const u8 {
    return std.zig.PkgConfig.exe(&graph.environ_map);
}

fn getPkgs(
    maker: *Maker,
    step: *Step,
    progress_node: std.Progress.Node,
    force: bool,
) RunError!std.zig.PkgConfig {
    const graph = maker.graph;
    const io = graph.io;
    const pc = &maker.pkg_config;
    const arena = graph.arena;

    try pc.mutex.lock(io);
    defer pc.mutex.unlock(io);

    if (pc.pkgs) |pkgs| return pkgs;

    const pkg_config_exe = getExe(graph);
    const stdout = try captureChildProcess(maker, step, arena, .{
        .argv = &.{ pkg_config_exe, "--list-all" },
        .progress_node = progress_node,
        .allow_failure = !force,
    });

    var diagnostic: std.zig.PkgConfig.Diagnostic = undefined;
    const result = std.zig.PkgConfig.init(arena, stdout, &diagnostic) catch |err| switch (err) {
        error.InvalidPkgConfigOutput => {
            if (force) return step.fail(maker, "{s}: invalid line({d}): {s}", .{
                pkg_config_exe, diagnostic.invalid_line_index + 1, diagnostic.invalid_line,
            });
            return error.PkgConfigUnavailable;
        },
        else => |e| return e,
    };

    step.clearFailedCommand(maker.gpa);
    pc.pkgs = result;
    return result;
}

fn captureChildProcess(maker: *Maker, step: *Step, arena: Allocator, options: Step.CaptureChildProcessOptions) ![]const u8 {
    const captured = step.captureChildProcess(maker, arena, options) catch |err| switch (err) {
        error.FileNotFound => return error.PkgConfigUnavailable,
        else => |e| return e,
    };
    if (captured.stderr.len != 0) try step.setResultStderr(maker.gpa, captured.stderr);
    assert(step.result_failed_command != null);
    if (captured.term.success()) return captured.stdout;
    if (!options.allow_failure) return step.fail(maker, "{s} {f}", .{ options.argv[0], captured.term });
    return error.PkgConfigUnavailable;
}
