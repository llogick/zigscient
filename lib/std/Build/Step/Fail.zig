//! Fail the build with a given message.
const Fail = @This();

const std = @import("std");
const Step = std.Build.Step;
const Configuration = std.Build.Configuration;

step: Step,
error_msg: Configuration.String,

pub const base_tag: Step.Tag = .fail;

pub fn create(owner: *std.Build, error_msg: []const u8) *Fail {
    const graph = owner.graph;
    const fail = graph.create(Fail);
    fail.* = .{
        .step = .init(.{
            .tag = base_tag,
            .name = "fail",
            .owner = owner,
        }),
        .error_msg = graph.addString(error_msg),
    };
    return fail;
}
