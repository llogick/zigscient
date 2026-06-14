//! The more reusable pieces of the build system's pkg-config integration logic.
const PkgConfig = @This();

const std = @import("../std.zig");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

all: []const Pkg,

pub const Pkg = struct {
    name: []const u8,
    desc: []const u8,
};

pub const InitError = Allocator.Error || error{InvalidPkgConfigOutput};

pub const Diagnostic = struct {
    invalid_line_index: usize,
    invalid_line: []const u8,
};

/// Parses the output of `pkg-config --list-all`.
pub fn init(arena: Allocator, stdout: []const u8, diagnostic: ?*Diagnostic) InitError!PkgConfig {
    var list: std.ArrayList(Pkg) = .empty;
    var line_it = mem.tokenizeAny(u8, stdout, "\r\n");
    var line_index: usize = 0;
    while (line_it.next()) |line| : (line_index += 1) {
        if (mem.trim(u8, line, " \t").len == 0) continue;
        var tok_it = mem.tokenizeAny(u8, line, " \t");
        try list.append(arena, .{
            .name = tok_it.next() orelse {
                if (diagnostic) |d| d.* = .{
                    .invalid_line_index = line_index,
                    .invalid_line = line,
                };
                return error.InvalidPkgConfigOutput;
            },
            .desc = tok_it.rest(),
        });
    }
    try list.shrinkToLen(arena);
    return .{ .all = list.toOwnedSliceAssert() };
}

// Maps the library name to pkg config name. Unfortunately, there are several
// examples where this is not straightforward:
// * -lSDL2 -> pkg-config sdl2
// * -lgdk-3 -> pkg-config gdk-3.0
// * -latk-1.0 -> pkg-config atk
// * -lpulse -> pkg-config libpulse
pub fn find(pc: *const PkgConfig, lib_name: []const u8) ?usize {
    const all = pc.all;

    // Exact match means instant winner.
    for (all, 0..) |pkg, i| {
        if (mem.eql(u8, pkg.name, lib_name))
            return i;
    }

    // Next we'll try ignoring case.
    for (all, 0..) |pkg, i| {
        if (std.ascii.eqlIgnoreCase(pkg.name, lib_name))
            return i;
    }

    // Prefixed "lib" or suffixed ".0".
    for (all, 0..) |pkg, i| {
        if (std.ascii.findIgnoreCase(pkg.name, lib_name)) |pos| {
            const prefix = pkg.name[0..pos];
            const suffix = pkg.name[pos + lib_name.len ..];
            if (prefix.len > 0 and !mem.eql(u8, prefix, "lib")) continue;
            if (suffix.len > 0 and !mem.eql(u8, suffix, ".0")) continue;
            return i;
        }
    }

    // Trimming "-1.0".
    if (mem.cutSuffix(u8, lib_name, "-1.0")) |trimmed| {
        for (all, 0..) |pkg, i| {
            if (std.ascii.eqlIgnoreCase(pkg.name, trimmed)) {
                return i;
            }
        }
    }

    return null;
}

pub fn exe(environ_map: *const std.process.Environ.Map) []const u8 {
    return std.zig.EnvVar.PKG_CONFIG.get(environ_map) orelse "pkg-config";
}

pub const Parsed = struct {
    cflags: []const []const u8,
    libs: []const []const u8,
    unknown_flags: []const []const u8,
    pthread: bool,
};

pub const ParseError = Allocator.Error || error{InvalidPkgConfigOutput};

/// Parses the output of `pkg-config [name] --cflags --libs`.
pub fn parse(arena: Allocator, stdout: []const u8) ParseError!Parsed {
    var zig_cflags: std.ArrayList([]const u8) = .empty;
    var zig_libs: std.ArrayList([]const u8) = .empty;
    var unknown_flags: std.ArrayList([]const u8) = .empty;
    var arg_it = mem.tokenizeAny(u8, stdout, " \r\n\t");
    var pthread = false;

    while (arg_it.next()) |arg| {
        if (mem.eql(u8, arg, "-I")) {
            const dir = arg_it.next() orelse return error.InvalidPkgConfigOutput;
            try zig_cflags.appendSlice(arena, &.{ "-I", dir });
        } else if (mem.startsWith(u8, arg, "-I")) {
            try zig_cflags.append(arena, arg);
        } else if (mem.eql(u8, arg, "-L")) {
            const dir = arg_it.next() orelse return error.InvalidPkgConfigOutput;
            try zig_libs.appendSlice(arena, &.{ "-L", dir });
        } else if (mem.startsWith(u8, arg, "-L")) {
            try zig_libs.append(arena, arg);
        } else if (mem.eql(u8, arg, "-l")) {
            const lib = arg_it.next() orelse return error.InvalidPkgConfigOutput;
            try zig_libs.appendSlice(arena, &.{ "-l", lib });
        } else if (mem.startsWith(u8, arg, "-l")) {
            try zig_libs.append(arena, arg);
        } else if (mem.eql(u8, arg, "-D")) {
            const macro = arg_it.next() orelse return error.InvalidPkgConfigOutput;
            try zig_cflags.appendSlice(arena, &.{ "-D", macro });
        } else if (mem.startsWith(u8, arg, "-D")) {
            try zig_cflags.append(arena, arg);
        } else if (mem.cutPrefix(u8, arg, "-Wl,-rpath,")) |rest| {
            try zig_cflags.appendSlice(arena, &.{ "-rpath", rest });
        } else if (mem.eql(u8, arg, "-pthread")) {
            pthread = true;
        } else {
            try unknown_flags.append(arena, arg);
        }
    }

    try zig_cflags.shrinkToLen(arena);
    try zig_libs.shrinkToLen(arena);
    try unknown_flags.shrinkToLen(arena);

    return .{
        .cflags = zig_cflags.toOwnedSliceAssert(),
        .libs = zig_libs.toOwnedSliceAssert(),
        .unknown_flags = unknown_flags.toOwnedSliceAssert(),
        .pthread = pthread,
    };
}
