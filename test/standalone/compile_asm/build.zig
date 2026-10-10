const std = @import("std");

pub const supports_skip_non_native = true;

pub fn build(b: *std.Build) !void {
    const skip_non_native = b.option(bool, "skip_non_native", "Skip non-native targets") orelse false;

    const test_step = b.step("test", "Test it");
    b.default_step = test_step;

    const optimize: std.builtin.Optimize = .debug;
    const target = b.resolveTargetQuery(.{
        .os_tag = .freestanding,
        .cpu_arch = .arm,
        .cpu_model = .{
            .explicit = &std.Target.arm.cpu.arm1176jz_s,
        },
    });

    if (skip_non_native and !std.zig.target.isNative(&target.query, &target.result, &b.graph.host.result)) return;

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_module = b.createModule(.{
            .root_source_file = b.path("./main.zig"),
            .optimize = optimize,
            .target = target,
        }),
    });
    kernel.root_module.addObjectFile(b.path("./boot.S"));
    kernel.setLinkerScript(b.path("./linker.ld"));
    b.installArtifact(kernel);

    test_step.dependOn(&kernel.step);
}
