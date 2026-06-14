const std = @import("std");
const builtin = @import("builtin");

// To run executables linked against a specific glibc version, the
// run-time glibc version needs to be new enough.  Check the host's glibc
// version.  Note that this does not allow for translation/vm/emulation
// services to run these tests.
const running_glibc_ver = builtin.os.versionRange().gnuLibCVersion();

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Test");
    b.default_step = test_step;

    for ([_][]const u8{ "aarch64-linux-gnu.2.27", "aarch64-linux-gnu.2.34" }) |t| {
        const exe = b.addExecutable(.{
            .name = t,
            .root_module = b.createModule(.{
                .root_source_file = null,
                .target = b.resolveTargetQuery(std.Target.Query.parse(
                    .{ .arch_os_abi = t },
                ) catch unreachable),
                .link_libc = true,
            }),
        });
        // We disable UBSAN for these tests as the libc being tested here is
        // so old, it doesn't even support compiling our UBSAN implementation.
        exe.bundle_ubsan_rt = false;
        exe.root_module.sanitize_c = .off;
        exe.root_module.addCSourceFile(.{ .file = b.path("main.c") });
        // TODO: actually test the output
        _ = exe.getEmittedBin();
        test_step.dependOn(&exe.step);
    }

    // Build & run a C test case against a sampling of supported glibc versions
    versions: for ([_][]const u8{
        // "native-linux-gnu.2.0", // fails with a pile of missing symbols.
        "native-linux-gnu.2.2.5",
        "native-linux-gnu.2.4",
        "native-linux-gnu.2.12",
        "native-linux-gnu.2.16",
        "native-linux-gnu.2.22",
        "native-linux-gnu.2.28",
        "native-linux-gnu.2.33",
        "native-linux-gnu.2.38",
        "native-linux-gnu",
    }) |t| {
        const target = b.resolveTargetQuery(std.Target.Query.parse(
            .{ .arch_os_abi = t },
        ) catch unreachable);

        const glibc_ver = target.result.os.version_range.linux.glibc;

        // only build test if glibc version supports the architecture
        for (std.zig.target.available_libcs) |libc| {
            if (libc.arch != target.result.cpu.arch or
                libc.os != target.result.os.tag or
                libc.abi != target.result.abi)
                continue;

            if (libc.glibc_min) |min| {
                if (glibc_ver.order(min) == .lt) continue :versions;
            }
        }

        const exe = b.addExecutable(.{
            .name = t,
            .root_module = b.createModule(.{
                .root_source_file = null,
                .target = target,
                .link_libc = true,
            }),
        });
        // We disable UBSAN for these tests as the libc being tested here is
        // so old, it doesn't even support compiling our UBSAN implementation.
        exe.bundle_ubsan_rt = false;
        exe.root_module.sanitize_c = .off;
        exe.root_module.addCSourceFile(.{ .file = b.path("glibc_runtime_check.c") });

        // Only try running the test if the host glibc is known to be good enough.  Ideally, the Zig
        // test runner would be able to check this, but see https://github.com/ziglang/zig/pull/17702#issuecomment-1831310453
        if (running_glibc_ver) |running_ver| {
            if (glibc_ver.order(running_ver) == .lt) {
                const run_cmd = b.addRunArtifact(exe);
                run_cmd.skip_foreign_checks = true;
                run_cmd.expectExitCode(0);

                test_step.dependOn(&run_cmd.step);
            }
        }
    }

    // Build & run a Zig test case against a sampling of supported glibc versions
    versions: for ([_][]const u8{
        "native-linux-gnu.2.17", // Currently oldest supported, see #17769
        "native-linux-gnu.2.23",
        "native-linux-gnu.2.28",
        "native-linux-gnu.2.33",
        "native-linux-gnu.2.38",
        "native-linux-gnu",
    }) |t| {
        const target = b.resolveTargetQuery(std.Target.Query.parse(
            .{ .arch_os_abi = t },
        ) catch unreachable);

        const glibc_ver = target.result.os.version_range.linux.glibc;

        // only build test if glibc version supports the architecture
        for (std.zig.target.available_libcs) |libc| {
            if (libc.arch != target.result.cpu.arch or
                libc.os != target.result.os.tag or
                libc.abi != target.result.abi)
                continue;

            if (libc.glibc_min) |min| {
                if (glibc_ver.order(min) == .lt) continue :versions;
            }
        }

        const malloc_translation = b.addTranslateC(.{
            .root_source_file = b.path("include_malloc.h"),
            .target = target,
            .optimize = .Debug,
            .link_libc = true,
        });
        const stdlib_translation = b.addTranslateC(.{
            .root_source_file = b.path("include_stdlib.h"),
            .target = target,
            .optimize = .Debug,
            .link_libc = true,
        });
        const string_translation = b.addTranslateC(.{
            .root_source_file = b.path("include_string.h"),
            .target = target,
            .optimize = .Debug,
            .link_libc = true,
        });
        const exe = b.addExecutable(.{
            .name = t,
            .root_module = b.createModule(.{
                .root_source_file = b.path("glibc_runtime_check.zig"),
                .target = target,
                .link_libc = true,
                .imports = &.{
                    .{
                        .name = "malloc.h",
                        .module = malloc_translation.createModule(),
                    },
                    .{
                        .name = "stdlib.h",
                        .module = stdlib_translation.createModule(),
                    },
                    .{
                        .name = "string.h",
                        .module = string_translation.createModule(),
                    },
                },
            }),
        });
        // We disable UBSAN for these tests as the libc being tested here is
        // so old, it doesn't even support compiling our UBSAN implementation.
        exe.bundle_ubsan_rt = false;
        exe.root_module.sanitize_c = .off;

        // Only try running the test if the host glibc is known to be good enough.  Ideally, the Zig
        // test runner would be able to check this, but see https://github.com/ziglang/zig/pull/17702#issuecomment-1831310453
        if (running_glibc_ver) |running_ver| {
            if (glibc_ver.order(running_ver) == .lt) {
                const run_cmd = b.addRunArtifact(exe);
                run_cmd.skip_foreign_checks = true;
                run_cmd.expectExitCode(0);

                test_step.dependOn(&run_cmd.step);
            }
        }
    }
}
