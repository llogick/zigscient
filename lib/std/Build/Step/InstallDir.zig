const InstallDir = @This();

const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const Step = std.Build.Step;
const LazyPath = std.Build.LazyPath;

step: Step,
options: Options,

pub const base_tag: Step.Tag = .install_dir;

pub const Options = struct {
    source_dir: LazyPath,
    install_dir: std.Build.InstallDir,
    install_subdir: []const u8,
    /// File paths which end in any of these suffixes will be excluded
    /// from being installed.
    exclude_extensions: []const []const u8 = &.{},
    /// Only file paths which end in any of these suffixes will be included
    /// in installation. `null` means all suffixes are valid for this option.
    /// `exclude_extensions` take precedence over `include_extensions`
    include_extensions: ?[]const []const u8 = null,
    /// File paths which end in any of these suffixes will result in
    /// empty files being installed. This is mainly intended for large
    /// test.zig files in order to prevent needless installation bloat.
    /// However if the files were not present at all, then
    /// `@import("test.zig")` would be a compile error.
    blank_extensions: []const []const u8 = &.{},

    fn dupe(opts: Options, graph: *const std.Build.Graph) Options {
        return .{
            .source_dir = opts.source_dir.dupe(graph),
            .install_dir = opts.install_dir.dupe(graph),
            .install_subdir = graph.dupeString(opts.install_subdir),
            .exclude_extensions = graph.dupeStrings(opts.exclude_extensions),
            .include_extensions = if (opts.include_extensions) |incs| graph.dupeStrings(incs) else null,
            .blank_extensions = graph.dupeStrings(opts.blank_extensions),
        };
    }
};

pub fn create(owner: *std.Build, options: Options) *InstallDir {
    const install_dir = owner.allocator.create(InstallDir) catch @panic("OOM");
    const graph = owner.graph;
    install_dir.* = .{
        .step = Step.init(.{
            .tag = base_tag,
            .name = owner.fmt("install {f}/", .{options.source_dir}),
            .owner = owner,
        }),
        .options = options.dupe(graph),
    };
    options.source_dir.addStepDependencies(&install_dir.step);
    return install_dir;
}
