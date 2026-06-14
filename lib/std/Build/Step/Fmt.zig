//! This step has two modes:
//! * Modify mode: directly modify source files, formatting them in place.
//! * Check mode: fail the step if a non-conforming file is found.
const Fmt = @This();

const std = @import("std");
const Step = std.Build.Step;
const LazyPath = std.Build.LazyPath;
const Configuration = std.Build.Configuration;

step: Step,
/// Intended to be read-only after the `Fmt` step is created.
paths: []const LazyPath,
/// Intended to be read-only after the `Fmt` step is created.
exclude_paths: []const LazyPath,
check: bool,

pub const base_tag: Step.Tag = .fmt;

pub const Options = struct {
    paths: []const LazyPath = &.{},
    exclude_paths: []const LazyPath = &.{},
    /// If true, fails the build step when any non-conforming files are encountered.
    check: bool = false,
};

pub fn create(owner: *std.Build, options: Options) *Fmt {
    const graph = owner.graph;
    const fmt = graph.create(Fmt);

    fmt.* = .{
        .step = .init(.{
            .tag = base_tag,
            .name = if (options.check) "zig fmt --check" else "zig fmt",
            .owner = owner,
        }),
        .paths = LazyPath.dupeList(options.paths, graph),
        .exclude_paths = LazyPath.dupeList(options.exclude_paths, graph),
        .check = options.check,
    };

    for (options.paths) |lp| lp.addStepDependencies(&fmt.step);
    for (options.exclude_paths) |lp| lp.addStepDependencies(&fmt.step);

    return fmt;
}
