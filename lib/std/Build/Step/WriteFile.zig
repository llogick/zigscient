//! WriteFile is used to create a directory in an appropriate location inside
//! the local cache which has a set of files that have either been generated
//! during the build, or are copied from the source package.
const WriteFile = @This();

const std = @import("std");
const Step = std.Build.Step;
const Configuration = std.Build.Configuration;

step: Step,
embeds: std.ArrayList(Embed) = .empty,
copies: std.ArrayList(Copy) = .empty,
directories: std.ArrayList(Directory) = .empty,
generated_directory: Configuration.GeneratedFileIndex,
mode: Mode = .whole_cached,

pub const base_tag: Step.Tag = .write_file;

pub const Mode = union(enum) {
    /// Default mode. Integrates with the cache system. The directory should be
    /// read-only during the make phase. Any different inputs result in
    /// different "o" subdirectory.
    whole_cached,
    /// In this mode, the directory will be placed inside "tmp" rather than
    /// "o", and caching will be skipped. During the `make` phase, the step
    /// will always do all the file system operations, and on successful build
    /// completion, the dir will be deleted along with all other tmp
    /// directories. The directory is therefore eligible to be used for
    /// mutations by other steps.
    tmp,
    /// The operations will not be performed against a freshly created
    /// directory, but instead act against a temporary directory.
    mutate: std.Build.LazyPath,
};

pub const Embed = Configuration.Step.WriteFile.Embed;

pub const Copy = struct {
    sub_path: Configuration.String,
    src_file: std.Build.LazyPath,
};

pub const Directory = struct {
    sub_path: Configuration.String,
    src_path: std.Build.LazyPath,
    exclude_extensions: Configuration.OptionalStringList,
    include_extensions: Configuration.OptionalStringList,
};

pub fn create(owner: *std.Build) *WriteFile {
    const graph = owner.graph;
    const wf = graph.create(WriteFile);
    wf.* = .{
        .step = .init(.{
            .tag = base_tag,
            .name = "WriteFile",
            .owner = owner,
        }),
        .generated_directory = graph.addGeneratedFile(&wf.step),
    };
    return wf;
}

/// Writes `contents` to a file at `sub_path` relative to the output
/// directory.
///
/// `sub_path` may be a basename, or it may include subdirectories, which are
/// created as needed.
pub fn add(wf: *WriteFile, sub_path: []const u8, contents: []const u8) std.Build.LazyPath {
    const graph = wf.step.owner.graph;
    const wc = &graph.wip_configuration;
    const arena = graph.arena;

    wf.embeds.append(arena, .{
        .sub_path = wc.addString(sub_path) catch @panic("OOM"),
        .contents = wc.addBytes(contents) catch @panic("OOM"),
    }) catch @panic("OOM");

    wf.maybeUpdateName();

    return .{
        .generated = .{
            .index = wf.generated_directory,
            .sub_path = graph.dupeString(sub_path),
        },
    };
}

/// Copies the provided file to `sub_path` relative to the output directory.
///
/// `sub_path` may be a basename, or it may include subdirectories, which are
/// created as needed.
pub fn addCopyFile(wf: *WriteFile, src_file: std.Build.LazyPath, sub_path: []const u8) std.Build.LazyPath {
    const graph = wf.step.owner.graph;
    const wc = &graph.wip_configuration;
    const arena = graph.arena;

    wf.copies.append(arena, .{
        .sub_path = wc.addString(sub_path) catch @panic("OOM"),
        .src_file = src_file.dupe(graph),
    }) catch @panic("OOM");

    wf.maybeUpdateName();

    src_file.addStepDependencies(&wf.step);

    return .{ .generated = .{
        .index = wf.generated_directory,
        .sub_path = graph.dupePath(sub_path),
    } };
}

pub const CopyDirectoryOptions = struct {
    /// File paths that end in any of these suffixes will be excluded from copying.
    exclude_extensions: []const []const u8 = &.{},
    /// Only file paths that end in any of these suffixes will be included in copying.
    /// `null` means that all suffixes will be included.
    /// `exclude_extensions` takes precedence over `include_extensions`.
    include_extensions: ?[]const []const u8 = null,
};

/// Copy files matching the specified exclude/include patterns to the specified
/// subdirectory relative to this step's generated directory.
///
/// The returned value is a lazy path to the generated subdirectory.
pub fn addCopyDirectory(
    wf: *WriteFile,
    src_path: std.Build.LazyPath,
    sub_path: []const u8,
    options: CopyDirectoryOptions,
) std.Build.LazyPath {
    const graph = wf.step.owner.graph;
    const wc = &graph.wip_configuration;
    const arena = graph.arena;

    wf.directories.append(arena, .{
        .sub_path = wc.addString(sub_path) catch @panic("OOM"),
        .src_path = src_path.dupe(graph),
        .exclude_extensions = if (options.exclude_extensions.len != 0)
            .init(wc.addStringList(options.exclude_extensions) catch @panic("OOM"))
        else
            .none,
        .include_extensions = if (options.include_extensions) |list|
            .init(wc.addStringList(list) catch @panic("OOM"))
        else
            .none,
    }) catch @panic("OOM");

    wf.maybeUpdateName();

    src_path.addStepDependencies(&wf.step);

    return .{
        .generated = .{
            .index = wf.generated_directory,
            .sub_path = graph.dupePath(sub_path),
        },
    };
}

/// Returns a `LazyPath` representing the base directory that contains all the
/// files from this `WriteFile`.
pub fn getDirectory(wf: *WriteFile) std.Build.LazyPath {
    return .{ .generated = .{ .index = wf.generated_directory } };
}

fn maybeUpdateName(wf: *WriteFile) void {
    const graph = wf.step.owner.graph;
    const wc = &graph.wip_configuration;
    const files_count = wf.embeds.items.len + wf.copies.items.len;
    if (files_count == 1 and wf.directories.items.len == 0) {
        // First time adding a file; update name.
        const sub_path = if (wf.embeds.items.len == 1) wf.embeds.items[0].sub_path else wf.copies.items[0].sub_path;
        if (std.mem.eql(u8, wf.step.name, "WriteFile")) {
            wf.step.name = wf.step.owner.fmt("WriteFile {s}", .{wc.stringSlice(sub_path)});
        }
    } else if (wf.directories.items.len == 1 and files_count == 0) {
        // First time adding a directory; update name.
        const dir_name = wc.stringSlice(wf.directories.items[0].sub_path);
        if (std.mem.eql(u8, wf.step.name, "WriteFile")) {
            wf.step.name = wf.step.owner.fmt("WriteFile {s}", .{dir_name});
        }
    }
}
