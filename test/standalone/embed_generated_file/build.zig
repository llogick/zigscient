const std = @import("std");

pub const supports_skip_non_native = true;

pub fn build(b: *std.Build) void {
    const skip_non_native = b.option(bool, "skip_non_native", "Skip non-native targets") orelse false;

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
    });

    if (skip_non_native and !std.zig.target.isNative(&target.query, &target.result, &b.graph.host.result)) return;

    const test_step = b.step("test", "Test it");
    b.default_step = test_step;

    const bootloader = b.addExecutable(.{
        .name = "bootloader",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bootloader.zig"),
            .target = target,
            .optimize = .small,
        }),
    });

    const exe = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = b.graph.host,
        .optimize = .debug,
    }) });
    exe.root_module.addAnonymousImport("bootloader.elf", .{
        .root_source_file = bootloader.getEmittedBin(),
    });

    // TODO: actually check the output
    _ = exe.getEmittedBin();

    test_step.dependOn(&exe.step);
}
