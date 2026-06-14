const InstallFile = @This();

const std = @import("std");
const Configuration = std.Build.Configuration;

const Step = @import("../Step.zig");
const Maker = @import("../../Maker.zig");

pub fn make(
    install_file: *InstallFile,
    step_index: Configuration.Step.Index,
    maker: *Maker,
    progress_node: std.Progress.Node,
) Step.ExtendedMakeError!void {
    _ = install_file;
    _ = progress_node;
    const arena = maker.graph.arena; // TODO don't leak into process arena
    const step = maker.stepByIndex(step_index);
    const conf = &maker.scanned_config.configuration;
    const conf_step = step_index.ptr(conf);
    const conf_if = conf_step.extended.get(conf.extra).install_file;

    try step.singleUnchangingWatchInput(maker, arena, conf_if.source.get(conf));
    const p = try maker.installLazyPathSub(arena, conf_if.source, conf_if.dest_dir, conf_if.dest_sub_path.slice(conf), step_index);
    step.result_cached = p == .fresh;
}
