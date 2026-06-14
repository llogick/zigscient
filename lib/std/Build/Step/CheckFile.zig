//! Fail the build step if a file does not match certain checks.
const CheckFile = @This();

const std = @import("std");
const Io = std.Io;
const Step = std.Build.Step;
const fs = std.fs;
const mem = std.mem;
const Configuration = std.Build.Configuration;

step: Step,
file: std.Build.LazyPath,
expected_matches: []const Configuration.Bytes,
expected_exact: ?Configuration.Bytes,
max_bytes: ?u32,

pub const base_tag: Step.Tag = .check_file;

pub const Options = struct {
    expected_matches: []const []const u8 = &.{},
    expected_exact: ?[]const u8 = null,
    max_bytes: ?u32 = null,
};

pub fn create(owner: *std.Build, file: std.Build.LazyPath, options: Options) *CheckFile {
    const graph = owner.graph;
    const check_file = graph.create(CheckFile);
    check_file.* = .{
        .step = .init(.{
            .tag = base_tag,
            .name = "CheckFile",
            .owner = owner,
        }),
        .file = file.dupe(graph),
        .expected_matches = graph.addBytesList(options.expected_matches),
        .expected_exact = if (options.expected_exact) |b| graph.addBytes(b) else null,
        .max_bytes = options.max_bytes,
    };
    file.addStepDependencies(&check_file.step);
    return check_file;
}

pub fn setName(check_file: *CheckFile, name: []const u8) void {
    check_file.step.name = name;
}
