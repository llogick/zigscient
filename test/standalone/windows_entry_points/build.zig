const std = @import("std");

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Test it");
    b.default_step = test_step;

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .windows,
        .abi = .gnu,
    });

    {
        const exe = b.addExecutable(.{
            .name = "main",
            .root_module = b.createModule(.{
                .root_source_file = null,
                .target = target,
                .optimize = .Debug,
                .link_libc = true,
            }),
        });
        exe.root_module.addCSourceFile(.{ .file = b.path("main.c") });

        _ = exe.getEmittedBin();
        test_step.dependOn(&exe.step);
    }

    {
        const exe = b.addExecutable(.{
            .name = "wmain",
            .root_module = b.createModule(.{
                .root_source_file = null,
                .target = target,
                .optimize = .Debug,
                .link_libc = true,
            }),
        });
        exe.mingw_unicode_entry_point = true;
        exe.root_module.addCSourceFile(.{ .file = b.path("wmain.c") });

        _ = exe.getEmittedBin();
        test_step.dependOn(&exe.step);
    }

    {
        const exe = b.addExecutable(.{
            .name = "winmain",
            .root_module = b.createModule(.{
                .root_source_file = null,
                .target = target,
                .optimize = .Debug,
                .link_libc = true,
            }),
        });
        // Note: `exe.subsystem = .windows;` is not necessary
        exe.root_module.addCSourceFile(.{ .file = b.path("winmain.c") });

        _ = exe.getEmittedBin();
        test_step.dependOn(&exe.step);
    }

    {
        const exe = b.addExecutable(.{
            .name = "wwinmain",
            .root_module = b.createModule(.{
                .root_source_file = null,
                .target = target,
                .optimize = .Debug,
                .link_libc = true,
            }),
        });
        exe.mingw_unicode_entry_point = true;
        // Note: `exe.subsystem = .windows;` is not necessary
        exe.root_module.addCSourceFile(.{ .file = b.path("wwinmain.c") });

        _ = exe.getEmittedBin();
        test_step.dependOn(&exe.step);
    }

    {
        const exe = b.addExecutable(.{
            .name = "zig_main",
            .root_module = b.createModule(.{
                .root_source_file = b.path("main.zig"),
                .target = target,
                .optimize = .Debug,
            }),
        });

        _ = exe.getEmittedBin();
        test_step.dependOn(&exe.step);
    }

    {
        const exe = b.addExecutable(.{
            .name = "zig_main_link_libc",
            .root_module = b.createModule(.{
                .root_source_file = b.path("main.zig"),
                .target = target,
                .optimize = .Debug,
                .link_libc = true,
            }),
        });

        _ = exe.getEmittedBin();
        test_step.dependOn(&exe.step);
    }

    {
        const exe = b.addExecutable(.{
            .name = "zig_wwinmain",
            .root_module = b.createModule(.{
                .root_source_file = b.path("wwinmain.zig"),
                .target = target,
                .optimize = .Debug,
            }),
        });
        exe.mingw_unicode_entry_point = true;
        // Note: `exe.subsystem = .windows;` is not necessary

        _ = exe.getEmittedBin();
        test_step.dependOn(&exe.step);
    }

    {
        const exe = b.addExecutable(.{
            .name = "zig_wwinmain_link_libc",
            .root_module = b.createModule(.{
                .root_source_file = b.path("wwinmain.zig"),
                .target = target,
                .optimize = .Debug,
                .link_libc = true,
            }),
        });
        exe.mingw_unicode_entry_point = true;
        // Note: `exe.subsystem = .windows;` is not necessary

        _ = exe.getEmittedBin();
        test_step.dependOn(&exe.step);
    }

    const load_dll_exe = b.addExecutable(.{ .name = "load_dll", .root_module = b.createModule(.{
        .root_source_file = b.path("loaddll.zig"),
        .target = target,
        .optimize = .Debug,
    }) });

    {
        const dll = b.addLibrary(.{
            .name = "zig_dllmain",
            .linkage = .dynamic,
            .root_module = b.createModule(.{
                .root_source_file = b.path("dllmain.zig"),
                .target = target,
                .optimize = .Debug,
            }),
        });

        const run = b.addRunArtifact(load_dll_exe);
        run.addArtifactArg(dll);
        run.expectStdErrEqual("hello from DllMain");
        run.expectStdOutEqual("");
        run.expectExitCode(0);
        run.skip_foreign_checks = true;

        test_step.dependOn(&run.step);
    }

    {
        const dll = b.addLibrary(.{
            .name = "zig_dllmain_link_libc",
            .linkage = .dynamic,
            .root_module = b.createModule(.{
                .root_source_file = b.path("dllmain.zig"),
                .target = target,
                .optimize = .Debug,
                .link_libc = true,
            }),
        });

        const run = b.addRunArtifact(load_dll_exe);
        run.addArtifactArg(dll);
        run.expectStdErrEqual("hello from DllMain");
        run.expectStdOutEqual("");
        run.expectExitCode(0);
        run.skip_foreign_checks = true;

        test_step.dependOn(&run.step);
    }

    {
        const dll = b.addLibrary(.{
            .name = "c_dllmain",
            .linkage = .dynamic,
            .root_module = b.createModule(.{
                .target = target,
                .optimize = .Debug,
                .link_libc = true,
            }),
        });
        dll.root_module.addCSourceFile(.{ .file = b.path("dllmain.c") });

        const run = b.addRunArtifact(load_dll_exe);
        run.addArtifactArg(dll);
        run.expectStdErrEqual("hello from DllMain");
        run.expectStdOutEqual("");
        run.expectExitCode(0);
        run.skip_foreign_checks = true;

        test_step.dependOn(&run.step);
    }
}
