const std = @import("std");

pub const supports_skip_non_native = true;

/// This tests the path where DWARF information is embedded in a COFF binary
pub fn build(b: *std.Build) void {
    const skip_non_native = b.option(bool, "skip_non_native", "Skip non-native targets") orelse false;

    const host = b.graph.host;

    const test_step = b.step("test", "Test it");
    b.default_step = test_step;

    const optimize: std.builtin.Optimize = .debug;
    const target = switch (host.result.os.tag) {
        .windows => host,
        else => b.resolveTargetQuery(.{ .os_tag = .windows }),
    };

    if (skip_non_native and !std.zig.target.isNative(&target.query, &target.result, &host.result)) return;

    const exe = b.addExecutable(.{
        .name = "main",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .optimize = optimize,
            .target = target,
        }),
    });

    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "shared_lib",
        .root_module = b.createModule(.{
            .root_source_file = null,
            .optimize = optimize,
            .target = target,
            .link_libc = true,
        }),
    });
    lib.root_module.addCSourceFile(.{ .file = b.path("shared_lib.c"), .flags = &.{"-gdwarf"} });
    exe.root_module.linkLibrary(lib);

    const run = b.addRunArtifact(exe);
    run.expectExitCode(0);
    run.skip_foreign_checks = true;

    test_step.dependOn(&run.step);
}
