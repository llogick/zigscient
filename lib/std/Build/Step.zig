const Step = @This();

const std = @import("../std.zig");
const Build = std.Build;
const assert = std.debug.assert;
const Configuration = std.Build.Configuration;

tag: Configuration.Step.Tag,
name: []const u8,
owner: *Build,

dependencies: std.ArrayList(*Step),

/// Set this field to declare an upper bound on the amount of bytes of memory it will
/// take to run the step. Zero means no limit.
///
/// The idea to annotate steps that might use a high amount of RAM with an
/// upper bound. For example, perhaps a particular set of unit tests require 4
/// GiB of RAM, and those tests will be run under 4 different build
/// configurations at once. This would potentially require 16 GiB of memory on
/// the system if all 4 steps executed simultaneously, which could easily be
/// greater than what is actually available, potentially causing the system to
/// crash when using `zig build` at the default concurrency level.
///
/// This field causes the build runner to do two things:
/// 1. ulimit child processes, so that they will fail if it would exceed this
/// memory limit. This serves to enforce that this upper bound value is
/// correct.
/// 2. Ensure that the set of concurrent steps at any given time have a total
/// max_rss value that does not exceed the `max_total_rss` value of the build
/// runner. This value is configurable on the command line, and defaults to the
/// total system memory available.
max_rss: u64,

/// The return address associated with creation of this step that can be useful
/// to print along with debugging messages.
debug_stack_trace: std.debug.StackTrace,

pub const Tag = Configuration.Step.Tag;

pub fn Type(comptime tag: Tag) type {
    return switch (tag) {
        .check_file => CheckFile,
        .compile => Compile,
        .config_header => ConfigHeader,
        .fail => Fail,
        .find_program => FindProgram,
        .fmt => Fmt,
        .install_artifact => InstallArtifact,
        .install_dir => InstallDir,
        .install_file => InstallFile,
        .obj_copy => ObjCopy,
        .options => Options,
        .run => Run,
        .top_level => TopLevel,
        .translate_c => TranslateC,
        .update_source_files => UpdateSourceFiles,
        .write_file => WriteFile,
    };
}

pub const CheckFile = @import("Step/CheckFile.zig");
pub const Compile = @import("Step/Compile.zig");
pub const ConfigHeader = @import("Step/ConfigHeader.zig");
pub const Fail = @import("Step/Fail.zig");
pub const FindProgram = @import("Step/FindProgram.zig");
pub const Fmt = @import("Step/Fmt.zig");
pub const InstallArtifact = @import("Step/InstallArtifact.zig");
pub const InstallDir = @import("Step/InstallDir.zig");
pub const InstallFile = @import("Step/InstallFile.zig");
pub const ObjCopy = @import("Step/ObjCopy.zig");
pub const Options = @import("Step/Options.zig");
pub const Run = @import("Step/Run.zig");
pub const TranslateC = @import("Step/TranslateC.zig");
pub const UpdateSourceFiles = @import("Step/UpdateSourceFiles.zig");
pub const WriteFile = @import("Step/WriteFile.zig");

pub const TopLevel = struct {
    pub const base_tag: Step.Tag = .top_level;

    step: Step,
    description: []const u8,
};

pub const StepOptions = struct {
    tag: Tag,
    name: []const u8,
    owner: *Build,
    first_ret_addr: ?usize = null,
    max_rss: u64 = 0,
};

pub fn init(options: StepOptions) Step {
    const arena = options.owner.allocator;

    return .{
        .tag = options.tag,
        .name = arena.dupe(u8, options.name) catch @panic("OOM"),
        .owner = options.owner,
        .dependencies = .empty,
        .max_rss = options.max_rss,
        .debug_stack_trace = blk: {
            const addr_buf = arena.alloc(usize, options.owner.debug_stack_frames_count) catch @panic("OOM");
            const first_ret_addr = options.first_ret_addr orelse @returnAddress();
            break :blk std.debug.captureCurrentStackTrace(.{ .first_address = first_ret_addr }, addr_buf);
        },
    };
}

pub fn dependOn(step: *Step, other: *Step) void {
    const arena = step.owner.allocator;
    step.dependencies.append(arena, other) catch @panic("OOM");
}

pub fn cast(step: *Step, comptime T: type) ?*T {
    if (step.tag == T.base_tag) return @fieldParentPtr("step", step);
    return null;
}

/// For debugging purposes, prints identifying information about this Step.
pub fn dump(step: *Step, t: std.Io.Terminal) void {
    const w = t.writer;
    if (step.debug_stack_trace.return_addresses.len > 0) {
        w.print("name: '{s}'. creation stack trace:\n", .{step.name}) catch {};
        std.debug.writeStackTrace(&step.debug_stack_trace, t) catch {};
    } else {
        const field = "debug_stack_frames_count";
        comptime assert(@hasField(Build, field));
        t.setColor(.yellow) catch {};
        w.print("name: '{s}'. no stack trace collected for this step, see std.Build." ++ field ++ "\n", .{step.name}) catch {};
        t.setColor(.reset) catch {};
    }
}

test {
    _ = CheckFile;
    _ = Compile;
    _ = ConfigHeader;
    _ = Fail;
    _ = FindProgram;
    _ = Fmt;
    _ = InstallArtifact;
    _ = InstallDir;
    _ = InstallFile;
    _ = ObjCopy;
    _ = Options;
    _ = Run;
    _ = TranslateC;
    _ = UpdateSourceFiles;
    _ = WriteFile;
}
