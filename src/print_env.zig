const builtin = @import("builtin");

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const EnvVar = std.zig.EnvVar;
const fatal = std.process.fatal;

const build_options = @import("build_options");
const Compilation = @import("Compilation.zig");

pub fn cmdEnv(
    arena: Allocator,
    out: *std.Io.Writer,
    host: *const std.Target,
    environ_map: *std.process.Environ.Map,
    dirs: *const std.zig.Directories,
    self_exe_path: []const u8,
) !void {
    const zig_lib_dir = dirs.zig_lib.path orelse "";
    const zig_std_dir = try dirs.zig_lib.join(arena, &.{"std"});
    const global_cache_dir = dirs.global_cache.path orelse "";
    const triple = try host.zigTriple(arena);

    var serializer: std.zon.Serializer = .{ .writer = out };
    var root = try serializer.beginStruct(.{});

    try root.field("zig_exe", self_exe_path, .{});
    try root.field("lib_dir", zig_lib_dir, .{});
    try root.field("std_dir", zig_std_dir, .{});
    try root.field("global_cache_dir", global_cache_dir, .{});
    try root.field("version", build_options.version, .{});
    try root.field("target", triple, .{});
    var env = try root.beginStructField("env", .{});
    inline for (@typeInfo(EnvVar).@"enum".field_names) |field_name| {
        try env.field(field_name, @field(EnvVar, field_name).get(environ_map), .{});
    }
    try env.end();
    try root.end();

    try out.writeByte('\n');
}
