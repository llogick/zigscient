const Options = @This();

const builtin = @import("builtin");

const std = @import("std");
const Io = std.Io;
const fs = std.fs;
const Step = std.Build.Step;
const LazyPath = std.Build.LazyPath;
const Configuration = std.Build.Configuration;

step: Step,
generated_file: Configuration.GeneratedFileIndex,
contents: std.ArrayList(u8) = .empty,
args: std.ArrayList(Arg) = .empty,
encountered_types: std.StringHashMapUnmanaged(void),

pub const base_tag: Step.Tag = .options;

pub const Arg = struct {
    name: Configuration.String,
    path: LazyPath,
};

pub fn create(owner: *std.Build) *Options {
    const graph = owner.graph;
    const arena = graph.arena;

    const options = arena.create(Options) catch @panic("OOM");
    options.* = .{
        .step = .init(.{
            .tag = base_tag,
            .name = "options",
            .owner = owner,
        }),
        .generated_file = graph.addGeneratedFile(&options.step),
        .encountered_types = .empty,
    };

    return options;
}

pub fn addOption(options: *Options, comptime T: type, name: []const u8, value: T) void {
    return addOptionFallible(options, T, name, value) catch @panic("unhandled error");
}

fn addOptionFallible(options: *Options, comptime T: type, name: []const u8, value: T) !void {
    try printType(options, &options.contents, T, value, 0, name);
}

fn printType(
    options: *Options,
    out: *std.ArrayList(u8),
    comptime T: type,
    value: T,
    indent: u8,
    name: ?[]const u8,
) !void {
    const gpa = options.step.owner.allocator;
    switch (T) {
        []const []const u8 => {
            if (name) |payload| {
                try out.print(gpa, "pub const {f}: []const []const u8 = ", .{std.zig.fmtId(payload)});
            }

            try out.appendSlice(gpa, "&[_][]const u8{\n");

            for (value) |slice| {
                try out.appendNTimes(gpa, ' ', indent);
                try out.print(gpa, "    \"{f}\",\n", .{std.zig.fmtString(slice)});
            }

            if (name != null) {
                try out.appendSlice(gpa, "};\n");
            } else {
                try out.appendSlice(gpa, "},\n");
            }

            return;
        },
        []const u8 => {
            if (name) |some| {
                try out.print(gpa, "pub const {f}: []const u8 = \"{f}\";", .{
                    std.zig.fmtId(some), std.zig.fmtString(value),
                });
            } else {
                try out.print(gpa, "\"{f}\",", .{std.zig.fmtString(value)});
            }
            return out.appendSlice(gpa, "\n");
        },
        [:0]const u8 => {
            if (name) |some| {
                try out.print(gpa, "pub const {f}: [:0]const u8 = \"{f}\";", .{ std.zig.fmtId(some), std.zig.fmtString(value) });
            } else {
                try out.print(gpa, "\"{f}\",", .{std.zig.fmtString(value)});
            }
            return out.appendSlice(gpa, "\n");
        },
        ?[]const u8 => {
            if (name) |some| {
                try out.print(gpa, "pub const {f}: ?[]const u8 = ", .{std.zig.fmtId(some)});
            }

            if (value) |payload| {
                try out.print(gpa, "\"{f}\"", .{std.zig.fmtString(payload)});
            } else {
                try out.appendSlice(gpa, "null");
            }

            if (name != null) {
                try out.appendSlice(gpa, ";\n");
            } else {
                try out.appendSlice(gpa, ",\n");
            }
            return;
        },
        ?[:0]const u8 => {
            if (name) |some| {
                try out.print(gpa, "pub const {f}: ?[:0]const u8 = ", .{std.zig.fmtId(some)});
            }

            if (value) |payload| {
                try out.print(gpa, "\"{f}\"", .{std.zig.fmtString(payload)});
            } else {
                try out.appendSlice(gpa, "null");
            }

            if (name != null) {
                try out.appendSlice(gpa, ";\n");
            } else {
                try out.appendSlice(gpa, ",\n");
            }
            return;
        },
        std.SemanticVersion => {
            if (name) |some| {
                try out.print(gpa, "pub const {f}: @import(\"std\").SemanticVersion = ", .{std.zig.fmtId(some)});
            }

            try out.appendSlice(gpa, ".{\n");
            try out.appendNTimes(gpa, ' ', indent);
            try out.print(gpa, "    .major = {d},\n", .{value.major});
            try out.appendNTimes(gpa, ' ', indent);
            try out.print(gpa, "    .minor = {d},\n", .{value.minor});
            try out.appendNTimes(gpa, ' ', indent);
            try out.print(gpa, "    .patch = {d},\n", .{value.patch});

            if (value.pre) |some| {
                try out.appendNTimes(gpa, ' ', indent);
                try out.print(gpa, "    .pre = \"{f}\",\n", .{std.zig.fmtString(some)});
            }
            if (value.build) |some| {
                try out.appendNTimes(gpa, ' ', indent);
                try out.print(gpa, "    .build = \"{f}\",\n", .{std.zig.fmtString(some)});
            }

            if (name != null) {
                try out.appendSlice(gpa, "};\n");
            } else {
                try out.appendSlice(gpa, "},\n");
            }
            return;
        },
        else => {},
    }

    switch (@typeInfo(T)) {
        .array => {
            if (name) |some| {
                try out.print(gpa, "pub const {f}: {s} = ", .{ std.zig.fmtId(some), @typeName(T) });
            }

            try out.print(gpa, "{s} {{\n", .{@typeName(T)});
            for (value) |item| {
                try out.appendNTimes(gpa, ' ', indent + 4);
                try printType(options, out, @TypeOf(item), item, indent + 4, null);
            }
            try out.appendNTimes(gpa, ' ', indent);
            try out.appendSlice(gpa, "}");

            if (name != null) {
                try out.appendSlice(gpa, ";\n");
            } else {
                try out.appendSlice(gpa, ",\n");
            }
            return;
        },
        .pointer => |p| {
            if (p.size != .slice) {
                @compileError("Non-slice pointers are not yet supported in build options");
            }

            if (name) |some| {
                try out.print(gpa, "pub const {f}: {s} = ", .{ std.zig.fmtId(some), @typeName(T) });
            }

            try out.print(gpa, "&[_]{s} {{\n", .{@typeName(p.child)});
            for (value) |item| {
                try out.appendNTimes(gpa, ' ', indent + 4);
                try printType(options, out, @TypeOf(item), item, indent + 4, null);
            }
            try out.appendNTimes(gpa, ' ', indent);
            try out.appendSlice(gpa, "}");

            if (name != null) {
                try out.appendSlice(gpa, ";\n");
            } else {
                try out.appendSlice(gpa, ",\n");
            }
            return;
        },
        .optional => {
            if (name) |some| {
                try out.print(gpa, "pub const {f}: {s} = ", .{ std.zig.fmtId(some), @typeName(T) });
            }

            if (value) |inner| {
                try printType(options, out, @TypeOf(inner), inner, indent + 4, null);
                // Pop the '\n' and ',' chars
                _ = options.contents.pop();
                _ = options.contents.pop();
            } else {
                try out.appendSlice(gpa, "null");
            }

            if (name != null) {
                try out.appendSlice(gpa, ";\n");
            } else {
                try out.appendSlice(gpa, ",\n");
            }
            return;
        },
        .void,
        .bool,
        .int,
        .comptime_int,
        .float,
        .comptime_float,
        .null,
        => {
            if (name) |some| {
                try out.print(gpa, "pub const {f}: {s} = {any};\n", .{ std.zig.fmtId(some), @typeName(T), value });
            } else {
                try out.print(gpa, "{any},\n", .{value});
            }
            return;
        },
        .@"enum" => |info| {
            try printEnum(options, out, T, info, indent);

            if (name) |some| {
                try out.print(gpa, "pub const {f}: {f} = .{f};\n", .{
                    std.zig.fmtId(some),
                    std.zig.fmtId(@typeName(T)),
                    std.zig.fmtIdFlags(@tagName(value), .{ .allow_underscore = true, .allow_primitive = true }),
                });
            }
            return;
        },
        .@"struct" => |info| {
            try printStruct(options, out, T, info, indent);

            if (name) |some| {
                try out.print(gpa, "pub const {f}: {f} = ", .{
                    std.zig.fmtId(some),
                    std.zig.fmtId(@typeName(T)),
                });
                try printStructValue(options, out, info, value, indent);
            }
            return;
        },
        else => @compileError(std.fmt.comptimePrint("`{s}` are not yet supported as build options", .{@tagName(@typeInfo(T))})),
    }
}

fn printUserDefinedType(options: *Options, out: *std.ArrayList(u8), comptime T: type, indent: u8) !void {
    switch (@typeInfo(T)) {
        .@"enum" => |info| {
            return try printEnum(options, out, T, info, indent);
        },
        .@"struct" => |info| {
            return try printStruct(options, out, T, info, indent);
        },
        else => {},
    }
}

fn printEnum(
    options: *Options,
    out: *std.ArrayList(u8),
    comptime T: type,
    comptime val: std.builtin.Type.Enum,
    indent: u8,
) !void {
    const gpa = options.step.owner.allocator;
    const gop = try options.encountered_types.getOrPut(gpa, @typeName(T));
    if (gop.found_existing) return;

    try out.appendNTimes(gpa, ' ', indent);
    try out.print(gpa, "pub const {f} = enum ({s}) {{\n", .{ std.zig.fmtId(@typeName(T)), @typeName(val.tag_type) });

    inline for (val.field_names, val.field_values) |field_name, field_value| {
        try out.appendNTimes(gpa, ' ', indent);
        try out.print(gpa, "    {f} = {d},\n", .{
            std.zig.fmtIdFlags(field_name, .{ .allow_primitive = true }), field_value,
        });
    }

    if (val.mode == .nonexhaustive) {
        try out.appendNTimes(gpa, ' ', indent);
        try out.appendSlice(gpa, "    _,\n");
    }

    try out.appendNTimes(gpa, ' ', indent);
    try out.appendSlice(gpa, "};\n");
}

fn printStruct(
    options: *Options,
    out: *std.ArrayList(u8),
    comptime T: type,
    comptime val: std.builtin.Type.Struct,
    indent: u8,
) !void {
    const gpa = options.step.owner.allocator;
    const gop = try options.encountered_types.getOrPut(gpa, @typeName(T));
    if (gop.found_existing) return;

    try out.appendNTimes(gpa, ' ', indent);
    try out.print(gpa, "pub const {f} = ", .{std.zig.fmtId(@typeName(T))});

    switch (val.layout) {
        .@"extern" => try out.appendSlice(gpa, "extern struct"),
        .@"packed" => try out.appendSlice(gpa, "packed struct"),
        else => try out.appendSlice(gpa, "struct"),
    }

    try out.appendSlice(gpa, " {\n");

    inline for (val.field_names, val.field_types, val.field_attrs) |field_name, field_type, field_attrs| {
        try out.appendNTimes(gpa, ' ', indent);

        const type_name = @typeName(field_type);

        // If the type name doesn't contains a '.' the type is from zig builtins.
        if (std.mem.containsAtLeast(u8, type_name, 1, ".")) {
            try out.print(gpa, "    {f}: {f}", .{
                std.zig.fmtIdFlags(field_name, .{ .allow_underscore = true, .allow_primitive = true }),
                std.zig.fmtId(type_name),
            });
        } else {
            try out.print(gpa, "    {f}: {s}", .{
                std.zig.fmtIdFlags(field_name, .{ .allow_underscore = true, .allow_primitive = true }),
                type_name,
            });
        }

        if (field_attrs.defaultValue(field_type)) |default_value| {
            try out.appendSlice(gpa, " = ");
            switch (@typeInfo(field_type)) {
                .@"enum" => try out.print(gpa, ".{s},\n", .{@tagName(default_value)}),
                .@"struct" => |info| {
                    try printStructValue(options, out, info, default_value, indent + 4);
                },
                else => try printType(options, out, field_type, default_value, indent, null),
            }
        } else {
            try out.appendSlice(gpa, ",\n");
        }
    }

    // TODO: write declarations

    try out.appendNTimes(gpa, ' ', indent);
    try out.appendSlice(gpa, "};\n");

    inline for (val.field_types) |field_type| {
        try printUserDefinedType(options, out, field_type, 0);
    }
}

fn printStructValue(
    options: *Options,
    out: *std.ArrayList(u8),
    comptime struct_val: std.builtin.Type.Struct,
    val: anytype,
    indent: u8,
) !void {
    const gpa = options.step.owner.allocator;
    try out.appendSlice(gpa, ".{\n");

    if (struct_val.is_tuple) {
        inline for (struct_val.field_names) |field_name| {
            try out.appendNTimes(gpa, ' ', indent);
            try printType(options, out, @TypeOf(@field(val, field_name)), @field(val, field_name), indent, null);
        }
    } else {
        inline for (struct_val.field_names) |field_name| {
            try out.appendNTimes(gpa, ' ', indent);
            try out.print(gpa, "    .{f} = ", .{
                std.zig.fmtIdFlags(field_name, .{ .allow_primitive = true, .allow_underscore = true }),
            });

            const field_val = @field(val, field_name);
            switch (@typeInfo(@TypeOf(field_val))) {
                .@"enum" => try out.print(gpa, ".{s},\n", .{@tagName(field_val)}),
                .@"struct" => |struct_info| {
                    try printStructValue(options, out, struct_info, field_val, indent + 4);
                },
                else => try printType(options, out, @TypeOf(field_val), field_val, indent, null),
            }
        }
    }

    if (indent == 0) {
        try out.appendSlice(gpa, "};\n");
    } else {
        try out.appendNTimes(gpa, ' ', indent);
        try out.appendSlice(gpa, "},\n");
    }
}

/// The added option has type `[]const u8` and value of the provided path.
pub fn addOptionPath(options: *Options, name: []const u8, path: LazyPath) void {
    const graph = options.step.owner.graph;
    const arena = graph.arena;
    const wc = &graph.wip_configuration;

    options.args.append(arena, .{
        .name = wc.addString(name) catch @panic("OOM"),
        .path = path.dupe(options.step.owner.graph),
    }) catch @panic("OOM");
    path.addStepDependencies(&options.step);
}

pub fn createModule(options: *Options) *std.Build.Module {
    return options.step.owner.createModule(.{
        .root_source_file = options.getOutput(),
    });
}

/// Returns the main artifact of this Build Step which is a Zig source file
/// generated from the key-value pairs of the Options.
pub fn getOutput(options: *Options) LazyPath {
    return .{ .generated = .{ .index = options.generated_file } };
}
