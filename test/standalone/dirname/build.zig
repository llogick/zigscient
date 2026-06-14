const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const test_step = b.step("test", "Test it");
    b.default_step = test_step;

    const touch_src = b.path("touch.zig");

    const touch = b.addExecutable(.{
        .name = "touch",
        .root_module = b.createModule(.{
            .root_source_file = touch_src,
            .optimize = .Debug,
            .target = target,
        }),
    });
    const generated = b.addRunArtifact(touch).addOutputFileArg("subdir" ++ std.fs.path.sep_str ++ "generated.txt");

    const exists_in = b.addExecutable(.{
        .name = "exists_in",
        .root_module = b.createModule(.{
            .root_source_file = b.path("exists_in.zig"),
            .optimize = .Debug,
            .target = target,
        }),
    });

    addTestRun(test_step, exists_in, "run exists_in (known path)", touch_src.dirname(), &.{"touch.zig"});
    addTestRun(test_step, exists_in, "run exists_in (generated file)", generated.dirname(), &.{"generated.txt"});
    addTestRun(test_step, exists_in, "run exists_in (generated file multi level)", generated.dirname().dirname(), &.{
        "subdir" ++ std.fs.path.sep_str ++ "generated.txt",
    });

    const write_files = b.addWriteFiles();
    _ = write_files.add("foo.txt", "");
    const abs_path = write_files.getDirectory();
    addTestRun(test_step, exists_in, "run exists_in (absolute path)", abs_path, &.{"foo.txt"});
}

// Runs exe with the parameters [dirname, args...].
// Expects the exit code to be 0.
fn addTestRun(
    test_step: *std.Build.Step,
    exe: *std.Build.Step.Compile,
    step_name: []const u8,
    dirname: std.Build.LazyPath,
    args: []const []const u8,
) void {
    const run = test_step.owner.addRunArtifact(exe);
    run.setName(step_name);
    run.addDirectoryArg(dirname);
    run.addArgs(args);
    run.expectExitCode(0);
    test_step.dependOn(&run.step);
}
