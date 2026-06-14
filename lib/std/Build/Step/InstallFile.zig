const InstallFile = @This();

const std = @import("std");
const Step = std.Build.Step;
const LazyPath = std.Build.LazyPath;
const InstallDir = std.Build.InstallDir;
const assert = std.debug.assert;

step: Step,
source: LazyPath,
dir: InstallDir,
dest_rel_path: []const u8,

pub const base_tag: Step.Tag = .install_file;

pub fn create(
    owner: *std.Build,
    source: LazyPath,
    dir: InstallDir,
    dest_rel_path: []const u8,
) *InstallFile {
    assert(dest_rel_path.len != 0);
    const graph = owner.graph;
    const arena = graph.arena;
    const install_file = arena.create(InstallFile) catch @panic("OOM");
    install_file.* = .{
        .step = Step.init(.{
            .tag = base_tag,
            .name = owner.fmt("install {f} to {s}", .{ source, dest_rel_path }),
            .owner = owner,
        }),
        .source = source.dupe(graph),
        .dir = dir.dupe(graph),
        .dest_rel_path = graph.dupePath(dest_rel_path),
    };
    source.addStepDependencies(&install_file.step);
    return install_file;
}
