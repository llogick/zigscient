const builtin = @import("builtin");

const std = @import("std");
const log = std.log.scoped(.lspc_zig_info);

pub const ZigEnv = struct {
    zig_exe: []const u8,
    lib_dir: ?[]const u8,
    std_dir: []const u8,
    global_cache_dir: []const u8,
    version: []const u8,
    target: ?[]const u8 = null,
};

pub fn getZigEnv(
    io: std.Io,
    allocator: std.mem.Allocator,
    result_arena: std.mem.Allocator,
    zig_exe_path: []const u8,
) error{ Canceled, OutOfMemory }!?ZigEnv {
    const zig_env_result = std.process.run(
        allocator,
        io,
        .{ .argv = &.{ zig_exe_path, "env" } },
    ) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        else => {
            log.err("Failed to run 'zig env': {}", .{err});
            return null;
        },
    };

    defer {
        allocator.free(zig_env_result.stdout);
        allocator.free(zig_env_result.stderr);
    }

    switch (zig_env_result.term) {
        .exited => |code| {
            if (code != 0) {
                log.err("zig env command exited with error code {d}.", .{code});
                if (zig_env_result.stderr.len != 0) {
                    log.err("stderr: {s}", .{zig_env_result.stderr});
                }
                return null;
            }
        },
        .signal, .stopped, .unknown => {
            log.err("zig env command terminated unexpectedly.", .{});
            if (zig_env_result.stderr.len != 0) {
                log.err("stderr: {s}", .{zig_env_result.stderr});
            }
            return null;
        },
    }

    if (std.mem.startsWith(u8, zig_env_result.stdout, "{")) {
        return std.json.parseFromSliceLeaky(
            ZigEnv,
            result_arena,
            zig_env_result.stdout,
            .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                log.err("Failed to parse 'zig env' output as JSON: {}", .{err});
                return null;
            },
        };
    } else {
        const source = try allocator.dupeSentinel(u8, zig_env_result.stdout, 0);
        defer allocator.free(source);

        return std.zon.parse.fromSliceAlloc(
            ZigEnv,
            result_arena,
            source,
            null,
            .{ .ignore_unknown_fields = true },
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                log.err("Failed to parse 'zig env' output as Zon: {}", .{err});
                return null;
            },
        };
    }
}

pub fn findZig(
    io: std.Io,
    allocator: std.mem.Allocator,
    environ_map: *const std.process.Environ.Map,
) error{ Canceled, OutOfMemory }!?[]const u8 {
    const is_windows = builtin.target.os.tag == .windows;

    const env_path = environ_map.get("PATH") orelse return null;
    const env_path_ext = if (is_windows) environ_map.get("PATHEXT") orelse return null;

    var filename_buffer: std.ArrayList(u8) = .empty;
    defer filename_buffer.deinit(allocator);

    var path_it = std.mem.tokenizeScalar(u8, env_path, std.fs.path.delimiter);
    var ext_it = if (is_windows) std.mem.tokenizeScalar(u8, env_path_ext, std.fs.path.delimiter);

    while (path_it.next()) |path| : (if (is_windows) ext_it.reset()) {
        var dir = std.Io.Dir.cwd().openDir(io, path, .{}) catch |err| switch (err) {
            error.Canceled => return error.Canceled,
            error.FileNotFound => continue,
            else => |e| {
                log.warn("failed to open entry in PATH '{s}': {}", .{ path, e });
                continue;
            },
        };
        defer dir.close(io);

        var cont = true;
        while (cont) : (cont = is_windows) {
            const filename = if (!is_windows) "zig" else filename: {
                const ext = ext_it.next() orelse break;

                filename_buffer.clearRetainingCapacity();
                try filename_buffer.ensureTotalCapacity(allocator, "zig".len + ext.len);
                filename_buffer.appendSliceAssumeCapacity("zig");
                filename_buffer.appendSliceAssumeCapacity(ext);

                break :filename filename_buffer.items;
            };

            const stat = dir.statFile(io, filename, .{}) catch |err| switch (err) {
                error.Canceled => return error.Canceled,
                error.FileNotFound => continue,
                else => |e| {
                    log.warn("failed to access entry in PATH '{f}': {}", .{ std.fs.path.fmtJoin(&.{ path, filename }), e });
                    continue;
                },
            };

            if (stat.kind == .directory) {
                log.warn("ignoring entry in PATH '{f}' because it is a directory", .{std.fs.path.fmtJoin(&.{ path, filename })});
                continue;
            }

            return try std.fs.path.join(allocator, &.{ path, filename });
        }
    }
    return null;
}
