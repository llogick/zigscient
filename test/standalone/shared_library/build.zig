const std = @import("std");

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Test it");
    b.default_step = test_step;

    const optimize: std.builtin.OptimizeMode = .Debug;
    const target = b.standardTargetOptions(.{});

    const exe_names: []const []const u8 = &.{
        "test",
        "test-dync",
        "test-no-llvm",
        "test-no-llvm-dync",
        "test-exe-no-llvm",
        "test-dync-exe-no-llvm",
        "test-no-llvm-exe-no-llvm",
        "test-no-llvm-dync-exe-no-llvm",
    };
    const lib_names: []const []const u8 = &.{
        "mathtest",
        "mathtest-dync",
        "mathtest-no-llvm",
        "mathtest-no-llvm-dync",
        "mathtest-exe-no-llvm",
        "mathtest-dync-exe-no-llvm",
        "mathtest-no-llvm-exe-no-llvm",
        "mathtest-no-llvm-dync-exe-no-llvm",
    };
    const lib_link_libc: []const bool = &.{ false, true, false, true, false, true, false, true };
    const lib_use_llvm: []const bool = &.{ true, true, false, false, true, true, false, false };
    const exe_use_llvm: []const bool = &.{ true, true, true, true, false, false, false, false };

    for (
        exe_names,
        lib_names,
        lib_link_libc,
        lib_use_llvm,
        exe_use_llvm,
    ) |exe_name, lib_name, dyn_libc, lib_llvm, exe_llvm| {
        const no_llvm = !lib_llvm or !exe_llvm;
        if (no_llvm and target.result.os.tag == .macos) continue; // TODO
        if (no_llvm and target.result.os.tag == .freebsd) continue; // TODO
        if (no_llvm and target.result.os.tag == .netbsd) continue; // TODO
        if (no_llvm and target.result.os.tag == .openbsd) continue; // TODO
        if (no_llvm and target.result.cpu.arch == .aarch64) continue; // TODO
        if (no_llvm and target.result.cpu.arch == .loongarch64) continue; // TODO
        if (no_llvm and target.result.cpu.arch == .powerpc64le) continue; // TODO
        if (no_llvm and target.result.cpu.arch == .s390x) continue; // TODO

        const lib = b.addLibrary(.{
            .linkage = .dynamic,
            .name = lib_name,
            .version = .{ .major = 1, .minor = 0, .patch = 0 },
            .root_module = b.createModule(.{
                .root_source_file = b.path("mathtest.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = dyn_libc,
            }),
            .use_llvm = lib_llvm,
        });

        const exe = b.addExecutable(.{
            .name = exe_name,
            .root_module = b.createModule(.{
                .root_source_file = null,
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
            .use_llvm = exe_llvm,
        });
        exe.root_module.addCSourceFile(.{
            .file = b.path("test.c"),
            .flags = &[_][]const u8{"-std=c99"},
        });
        exe.root_module.linkLibrary(lib);

        const run_cmd = b.addRunArtifact(exe);
        test_step.dependOn(&run_cmd.step);
    }
}
