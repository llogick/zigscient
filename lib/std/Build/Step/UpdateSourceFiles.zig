const UpdateSourceFiles = @This();

const std = @import("std");
const Step = std.Build.Step;
const Configuration = std.Build.Configuration;

step: Step,
embeds: std.ArrayList(Embed) = .empty,
copies: std.ArrayList(Copy) = .empty,

pub const base_tag: Step.Tag = .update_source_files;

pub const Embed = Step.WriteFile.Embed;
pub const Copy = Step.WriteFile.Copy;

pub fn create(owner: *std.Build) *UpdateSourceFiles {
    const graph = owner.graph;
    const usf = graph.create(UpdateSourceFiles);
    usf.* = .{
        .step = .init(.{
            .tag = base_tag,
            .name = "UpdateSourceFiles",
            .owner = owner,
        }),
    };
    return usf;
}

/// Overwrites a path relative to the build root with the contents of another file.
///
/// Because it updates source files, this should not be used as part of the
/// normal build process, but as a utility occasionally run by a developer with
/// intent to modify source files and then commit those changes to version
/// control.
pub fn addCopyFileToSource(usf: *UpdateSourceFiles, src_file: std.Build.LazyPath, sub_path: []const u8) void {
    const graph = usf.step.owner.graph;
    const wc = &graph.wip_configuration;
    const arena = graph.arena;

    usf.copies.append(arena, .{
        .sub_path = wc.addString(sub_path) catch @panic("OOM"),
        .src_file = src_file.dupe(graph),
    }) catch @panic("OOM");

    src_file.addStepDependencies(&usf.step);
}

/// Overwrites a path relative to the package root with the provided bytes.
///
/// Because it updates source files, this should not be used as part of the
/// normal build process, but as a utility occasionally run by a developer with
/// intent to modify source files and then commit those changes to version
/// control.
pub fn addBytesToSource(usf: *UpdateSourceFiles, contents: []const u8, sub_path: []const u8) void {
    const graph = usf.step.owner.graph;
    const wc = &graph.wip_configuration;
    const arena = graph.arena;

    usf.embeds.append(arena, .{
        .sub_path = wc.addString(sub_path) catch @panic("OOM"),
        .contents = wc.addBytes(contents) catch @panic("OOM"),
    }) catch @panic("OOM");
}
