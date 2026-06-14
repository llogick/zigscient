const ConfigHeader = @This();

const std = @import("std");
const Io = std.Io;
const Step = std.Build.Step;
const Allocator = std.mem.Allocator;
const Configuration = std.Build.Configuration;
const allocPrint = std.fmt.allocPrint;

step: Step,
values: std.array_hash_map.String(Value) = .empty,
/// This directory contains the generated file under the name `include_path`.
generated_dir: Configuration.GeneratedFileIndex,

style: Style,
input_size_limit: ?u64,
include_path: []const u8,
include_guard: Configuration.OptionalString,

pub const base_tag: Step.Tag = .config_header;

pub const Style = union(enum) {
    /// A configure format supported by autotools that uses `#undef foo` to
    /// mark lines that can be substituted with different values.
    autoconf_undef: std.Build.LazyPath,
    /// A configure format supported by autotools that uses `@FOO@` output variables.
    autoconf_at: std.Build.LazyPath,
    /// The configure format supported by CMake. It uses `@FOO@`, `${}` and
    /// `#cmakedefine` for template substitution.
    cmake: std.Build.LazyPath,
    /// Instead of starting with an input file, start with nothing.
    blank,
    /// Start with nothing, like blank, and output a nasm .asm file.
    nasm,

    pub fn getPath(style: Style) ?std.Build.LazyPath {
        switch (style) {
            .autoconf_undef, .autoconf_at, .cmake => |s| return s,
            .blank, .nasm => return null,
        }
    }
};

pub const Value = union(enum) {
    undef,
    defined,
    boolean: bool,
    int: i64,
    ident: []const u8,
    string: []const u8,
};

pub const Options = struct {
    style: Style = .blank,
    max_bytes: ?u64 = null,
    include_path: ?[]const u8 = null,
    include_guard: ?[]const u8 = null,
    first_ret_addr: ?usize = null,
};

pub fn create(owner: *std.Build, options: Options) *ConfigHeader {
    const graph = owner.graph;
    const arena = graph.arena;
    const wc = &graph.wip_configuration;
    const config_header = graph.create(ConfigHeader);

    const include_path: []const u8 = p: {
        if (options.include_path) |p|
            break :p graph.dupeString(p);

        if (options.style.getPath()) |s| default: {
            const sub_path = switch (s) {
                .src_path => |sp| sp.sub_path,
                .generated => break :default,
                .cwd_relative => |sub_path| sub_path,
                .relative => |r| r.sub_path,
                .dependency => |dependency| dependency.sub_path,
            };
            const basename = Io.Dir.path.basename(sub_path);
            if (std.mem.endsWith(u8, basename, ".h.in"))
                break :p graph.dupeString(basename[0 .. basename.len - 3]);
        }
        break :p "config.h";
    };

    const name = if (options.style.getPath()) |s|
        allocPrint(arena, "configure {t} header {f} to {s}", .{
            options.style, s, include_path,
        }) catch @panic("OOM")
    else
        allocPrint(arena, "configure {t} header to {s}", .{
            options.style, include_path,
        }) catch @panic("OOM");

    config_header.* = .{
        .step = .init(.{
            .tag = base_tag,
            .name = name,
            .owner = owner,
            .first_ret_addr = options.first_ret_addr orelse @returnAddress(),
        }),
        .style = options.style,
        .input_size_limit = options.max_bytes,
        .include_path = include_path,
        .include_guard = if (options.include_guard) |s| .init(wc.addString(s) catch @panic("OOM")) else .none,
        .generated_dir = graph.addGeneratedFile(&config_header.step),
    };

    if (options.style.getPath()) |s| {
        s.addStepDependencies(&config_header.step);
    }
    return config_header;
}

pub fn addIdent(config_header: *ConfigHeader, name: []const u8, value: []const u8) void {
    const arena = config_header.step.owner.allocator;
    config_header.values.put(arena, name, .{ .ident = value }) catch @panic("OOM");
}

pub fn addValue(config_header: *ConfigHeader, name: []const u8, comptime T: type, value: T) void {
    return addValueInner(config_header, name, T, value) catch @panic("OOM");
}

fn addValueInner(config_header: *ConfigHeader, name: []const u8, comptime T: type, value: T) !void {
    const arena = config_header.step.owner.allocator;
    switch (@typeInfo(T)) {
        .null => {
            try config_header.values.put(arena, name, .undef);
        },
        .void => {
            try config_header.values.put(arena, name, .defined);
        },
        .bool => {
            try config_header.values.put(arena, name, .{ .boolean = value });
        },
        .int => {
            try config_header.values.put(arena, name, .{ .int = value });
        },
        .comptime_int => {
            try config_header.values.put(arena, name, .{ .int = value });
        },
        .@"enum", .enum_literal => {
            try config_header.values.put(arena, name, .{ .ident = @tagName(value) });
        },
        .optional => {
            if (value) |x| {
                return addValueInner(config_header, name, @TypeOf(x), x);
            } else {
                try config_header.values.put(arena, name, .undef);
            }
        },
        .pointer => |ptr| {
            switch (@typeInfo(ptr.child)) {
                .array => |array| {
                    if (ptr.size == .one and array.child == u8) {
                        try config_header.values.put(arena, name, .{ .string = value });
                        return;
                    }
                },
                .int => {
                    if (ptr.size == .slice and ptr.child == u8) {
                        try config_header.values.put(arena, name, .{ .string = value });
                        return;
                    }
                },
                else => {},
            }

            @compileError("unsupported ConfigHeader value type: " ++ @typeName(T));
        },
        else => @compileError("unsupported ConfigHeader value type: " ++ @typeName(T)),
    }
}

pub fn addValues(config_header: *ConfigHeader, values: anytype) void {
    const info = @typeInfo(@TypeOf(values)).@"struct";
    inline for (info.field_names, info.field_types) |field_name, field_type| {
        addValue(config_header, field_name, field_type, @field(values, field_name));
    }
}

pub fn getOutputDir(ch: *ConfigHeader) std.Build.LazyPath {
    return .{ .generated = .{ .index = ch.generated_dir } };
}

pub fn getOutputFile(ch: *ConfigHeader) std.Build.LazyPath {
    return ch.getOutputDir().path(ch.step.owner, ch.include_path);
}
