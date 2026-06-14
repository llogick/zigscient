const ObjCopy = @This();

const std = @import("std");
const Step = std.Build.Step;
const Configuration = std.Build.Configuration;

step: Step,
input_file: std.Build.LazyPath,
basename: Configuration.OptionalString,
output_file: Configuration.GeneratedFileIndex,
debug_file: ?DebugFile,

format: ?Format,
only_section: Configuration.OptionalString,
pad_to: ?u64,
strip: Strip,
compress_debug: bool,

add_sections: std.ArrayList(AddSection) = .empty,
update_sections: std.ArrayList(Configuration.Step.ObjCopy.UpdateSection) = .empty,

pub const base_tag: Step.Tag = .obj_copy;

pub const Format = enum { binary, hex, elf };
pub const Strip = Configuration.Step.ObjCopy.Strip;
pub const SectionFlags = Configuration.Step.ObjCopy.SectionFlags;

pub const AddSection = struct {
    section_name: Configuration.String,
    file_path: std.Build.LazyPath,
};

pub const DebugFile = struct {
    basename: Configuration.OptionalString,
    output_file: Configuration.GeneratedFileIndex,
};

pub const Options = struct {
    basename: ?[]const u8 = null,
    format: ?Format = null,
    only_section: ?[]const u8 = null,
    pad_to: ?u64 = null,

    compress_debug: bool = false,
    strip: Strip = .none,

    /// Put the stripped out debug sections in a separate file.
    /// note: the `basename` is baked into the elf file to specify the link to the separate debug file.
    /// see https://sourceware.org/gdb/onlinedocs/gdb/Separate-Debug-Files.html
    ///
    /// Makes `getOutputSeparatedDebug` return non-null.
    separate_debug_file: ?SeparateDebugFile = null,

    pub const SeparateDebugFile = struct {
        basename: ?[]const u8,
    };
};

pub fn create(owner: *std.Build, input_file: std.Build.LazyPath, options: Options) *ObjCopy {
    const graph = owner.graph;
    const wc = &graph.wip_configuration;
    const oc = graph.create(ObjCopy);
    oc.* = .{
        .step = .init(.{
            .tag = base_tag,
            .name = owner.fmt("objcopy {f}", .{input_file}),
            .owner = owner,
        }),
        .input_file = input_file,
        .basename = if (options.basename) |s| .init(wc.addString(s) catch @panic("OOM")) else .none,
        .output_file = graph.addGeneratedFile(&oc.step),
        .debug_file = if (options.separate_debug_file) |df| .{
            .basename = if (df.basename) |s| .init(wc.addString(s) catch @panic("OOM")) else .none,
            .output_file = graph.addGeneratedFile(&oc.step),
        } else null,
        .format = options.format,
        .only_section = if (options.only_section) |s| .init(wc.addString(s) catch @panic("OOM")) else .none,
        .pad_to = options.pad_to,
        .strip = options.strip,
        .compress_debug = options.compress_debug,
    };
    input_file.addStepDependencies(&oc.step);
    return oc;
}

pub const UpdateSectionOptions = struct {
    alignment: ?std.mem.Alignment = null,
    flags: SectionFlags = .default,
};

pub fn updateSection(oc: *ObjCopy, section_name: []const u8, options: UpdateSectionOptions) void {
    const graph = oc.step.owner.graph;
    const arena = graph.arena;
    const wc = &graph.wip_configuration;
    oc.update_sections.append(arena, .{
        .flags = .{
            .section_flags = options.flags,
            .alignment = .init(options.alignment),
        },
        .section_name = wc.addString(section_name) catch @panic("OOM"),
    }) catch @panic("OOM");
}

pub const AddSectionOptions = struct {
    file_path: std.Build.LazyPath,
};

pub fn addSection(oc: *ObjCopy, section_name: []const u8, options: AddSectionOptions) void {
    const graph = oc.step.owner.graph;
    const arena = graph.arena;
    const wc = &graph.wip_configuration;
    oc.add_sections.append(arena, .{
        .section_name = wc.addString(section_name) catch @panic("OOM"),
        .file_path = options.file_path,
    }) catch @panic("OOM");
    options.file_path.addStepDependencies(&oc.step);
}

pub fn getOutput(oc: *const ObjCopy) std.Build.LazyPath {
    return .{ .generated = .{ .index = oc.output_file } };
}

pub fn getOutputSeparatedDebug(oc: *const ObjCopy) ?std.Build.LazyPath {
    const df = oc.debug_file orelse return null;
    return .{ .generated = .{ .index = df.output_file } };
}
