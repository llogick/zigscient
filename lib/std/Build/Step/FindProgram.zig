const FindProgram = @This();

const std = @import("std");
const Step = std.Build.Step;
const Configuration = std.Build.Configuration;

step: Step,
found_path: Configuration.GeneratedFileIndex,
names: Configuration.StringList,

pub const base_tag: Step.Tag = .find_program;

pub const Options = struct {
    names: []const []const u8,
};

pub fn create(owner: *std.Build, options: Options) *FindProgram {
    const graph = owner.graph;
    const wc = &graph.wip_configuration;
    const fp = graph.create(FindProgram);
    fp.* = .{
        .step = .init(.{
            .tag = base_tag,
            .name = owner.fmt("find program {s} ({d} candidates)", .{ options.names[0], options.names.len }),
            .owner = owner,
        }),
        .found_path = graph.addGeneratedFile(&fp.step),
        .names = wc.addStringList(options.names) catch @panic("OOM"),
    };
    return fp;
}
