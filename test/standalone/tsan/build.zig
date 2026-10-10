const std = @import("std");

pub const supports_skip_non_native = true;

const targets: []const std.Target.Query = &.{
    .{ .cpu_arch = .aarch64, .os_tag = .freebsd, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .freebsd, .abi = .none },

    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .aarch64_be, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64_be, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .loongarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .loongarch64, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .mips64, .os_tag = .linux, .abi = .gnuabi64 },
    .{ .cpu_arch = .mips64, .os_tag = .linux, .abi = .muslabi64 },
    .{ .cpu_arch = .mips64el, .os_tag = .linux, .abi = .gnuabi64 },
    .{ .cpu_arch = .mips64el, .os_tag = .linux, .abi = .muslabi64 },
    .{ .cpu_arch = .powerpc64le, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .powerpc64le, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .s390x, .os_tag = .linux, .abi = .gnu },
    // .{ .cpu_arch = .s390x, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },

    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },

    // .{ .cpu_arch = .x86_64, .os_tag = .netbsd, .abi = .none },

    // .{ .cpu_arch = .aarch64, .os_tag = .windows, .abi = .gnu },
    // .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
};

pub fn build(b: *std.Build) !void {
    const skip_non_native = b.option(bool, "skip_non_native", "Skip non-native targets") orelse false;

    const test_step = b.step("test", "Test the program");
    b.default_step = test_step;

    const is_macos = b.graph.host.result.os.tag == .macos;

    for (targets) |query| {
        const target = b.resolveTargetQuery(query);

        if (skip_non_native and !std.zig.target.isNative(&target.query, &target.result, &b.graph.host.result)) continue;

        switch (target.result.os.tag) {
            .macos => {
                // compiling tsan on macos requires system headers that aren't present during cross-compilation
                if (!is_macos) continue;

                const exe = b.addExecutable(.{
                    .name = b.fmt("tsan_{s}_{s}", .{ @tagName(target.result.os.tag), @tagName(target.result.cpu.arch) }),
                    .linkage = .dynamic,
                    .root_module = b.createModule(.{
                        .root_source_file = b.path("main.zig"),
                        .target = b.graph.host,
                        .optimize = .debug,
                        .sanitize_thread = true,
                    }),
                });
                const install_exe = b.addInstallArtifact(exe, .{});
                test_step.dependOn(&install_exe.step);
            },
            else => {
                const exe = b.addExecutable(.{
                    .name = b.fmt("tsan_{s}_{s}", .{ @tagName(target.result.os.tag), @tagName(target.result.cpu.arch) }),
                    .linkage = .dynamic,
                    .root_module = b.createModule(.{
                        .root_source_file = b.path("main.zig"),
                        .target = target,
                        .optimize = .debug,
                        .sanitize_thread = true,
                    }),
                });
                const install_exe = b.addInstallArtifact(exe, .{});
                test_step.dependOn(&install_exe.step);
            },
        }
    }
}
