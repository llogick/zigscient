const std = @import("std");

/// Tests that args are passed to run steps correctly.
///
/// Note that when `make_absolute` is true we make sure the resulting path argument is absolute, but
/// when it is false we allow either absolute or relative paths. This is because the maker receives
/// absolute paths when build is run from anywhere other than the build root.
pub fn build(b: *std.Build) !void {
    const step = b.step("test", "Run artifact args standalone test cases");
    b.default_step = step;

    const exe = b.addExecutable(.{
        .name = "exe",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = b.graph.host,
        }),
    });

    // Arg
    {
        const run = b.addRunArtifact(exe);
        step.dependOn(&run.step);
        run.addArg("arg1");
        run.expectStdErrEqual("arg1\n");
    }

    // Args
    {
        const run = b.addRunArtifact(exe);
        step.dependOn(&run.step);
        run.addArgs(&.{ "arg1", "arg2" });
        run.expectStdErrEqual("arg1\narg2\n");
    }

    // Artifact Args
    {
        // Absolute
        {
            const run = b.addRunArtifact(exe);
            step.dependOn(&run.step);
            _ = run.addArtifactArg2(exe, .{ .prefix = "path^", .make_absolute = true, .suffix = "$" });
            run.expectStdErrMatch("abs exe");
        }
        // Relative
        {
            const run = b.addRunArtifact(exe);
            step.dependOn(&run.step);
            _ = run.addArtifactArg2(exe, .{ .prefix = "path^", .make_absolute = false, .suffix = "$" });
            run.expectStdErrMatch("exe\n");
        }
    }

    // File Args
    {
        const write_files = b.addWriteFiles();
        const file = write_files.add("file", "");

        // Absolute
        {
            const run = b.addRunArtifact(exe);
            step.dependOn(&run.step);
            _ = run.addFileArg2(file, .{ .prefix = "path^", .make_absolute = true, .suffix = "$" });
            run.expectStdErrEqual("abs file\n");
        }
        // Relative
        {
            const run = b.addRunArtifact(exe);
            step.dependOn(&run.step);
            _ = run.addFileArg2(file, .{ .prefix = "path^", .make_absolute = false, .suffix = "$" });
            run.expectStdErrMatch("file\n");
        }
    }

    // File Content
    {
        const write_files = b.addWriteFiles();
        const file = write_files.add("file", "foo bar baz");

        const run = b.addRunArtifact(exe);
        step.dependOn(&run.step);
        _ = run.addFileContentArg2(file, .{ .prefix = "content-prefix ", .suffix = " content-suffix" });
        run.expectStdErrEqual("content-prefix foo bar baz content-suffix\n");
    }

    // Output File Args
    {
        // Absolute
        {
            const run = b.addRunArtifact(exe);
            step.dependOn(&run.step);
            _ = run.addOutputFileArg2("output-file", .{ .prefix = "path^", .make_absolute = true, .suffix = "$" });
            run.expectStdErrEqual("abs output-file\n");
        }
        // Relative
        {
            const run = b.addRunArtifact(exe);
            step.dependOn(&run.step);
            _ = run.addOutputFileArg2("output-file", .{ .prefix = "path^", .make_absolute = false, .suffix = "$" });
            run.expectStdErrMatch("output-file\n");
        }
    }

    // Output Directory Args
    {
        // Absolute
        {
            const run = b.addRunArtifact(exe);
            step.dependOn(&run.step);
            _ = run.addOutputDirectoryArg2("output-dir", .{ .prefix = "path^", .make_absolute = true, .suffix = "$" });
            run.expectStdErrEqual("abs output-dir\n");
        }
        // Relative
        {
            const run = b.addRunArtifact(exe);
            step.dependOn(&run.step);
            _ = run.addOutputDirectoryArg2("output-dir", .{ .prefix = "path^", .make_absolute = false, .suffix = "$" });
            run.expectStdErrMatch("output-dir\n");
        }
    }

    // Directory Args
    {
        const write_files = b.addWriteFiles();
        const directory = try write_files.getDirectory().join(b.graph.arena, "dir");

        // Absolute
        {
            const run = b.addRunArtifact(exe);
            step.dependOn(&run.step);
            _ = run.addDirectoryArg2(directory, .{ .prefix = "path^", .make_absolute = true, .suffix = "$" });
            run.expectStdErrEqual("abs dir\n");
        }
        // Relative
        {
            const run = b.addRunArtifact(exe);
            step.dependOn(&run.step);
            _ = run.addDirectoryArg2(directory, .{ .prefix = "path^", .make_absolute = false, .suffix = "$" });
            run.expectStdErrMatch("dir\n");
        }
    }

    // Dep File Args
    {
        // Absolute
        {
            const run = b.addRunArtifact(exe);
            step.dependOn(&run.step);
            _ = run.addDepFileOutputArg2("deps.d", .{ .prefix = "path^", .make_absolute = true, .suffix = "$" });
            run.expectStdErrEqual("abs deps.d\n");
        }
        // Relative
        {
            const run = b.addRunArtifact(exe);
            step.dependOn(&run.step);
            _ = run.addDepFileOutputArg2("deps.d", .{ .prefix = "path^", .make_absolute = false, .suffix = "$" });
            run.expectStdErrMatch("deps.d\n");
        }
    }
}
