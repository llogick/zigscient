const InstallArtifact = @This();

const std = @import("std");
const Step = std.Build.Step;
const InstallDir = std.Build.InstallDir;
const LazyPath = std.Build.LazyPath;

step: Step,

dest_dir: ?InstallDir,
dest_sub_path: ?[]const u8,
emitted_bin: ?LazyPath,

implib_dir: ?InstallDir,
emitted_implib: ?LazyPath,

pdb_dir: ?InstallDir,
emitted_pdb: ?LazyPath,

h_dir: ?InstallDir,
emitted_h: ?LazyPath,

dylib_symlinks: bool,

artifact: *Step.Compile,

const DylibSymlinkInfo = struct {
    major_only_filename: []const u8,
    name_only_filename: []const u8,
};

pub const base_tag: Step.Tag = .install_artifact;

pub const Options = struct {
    /// Which installation directory to put the main output file into.
    dest_dir: Dir = .default,
    pdb_dir: Dir = .default,
    compiler_rt_dyn_lib_dir: Dir = .default,
    h_dir: Dir = .default,
    implib_dir: Dir = .default,

    /// Whether to install symlinks along with dynamic libraries.
    dylib_symlinks: ?bool = null,
    /// If non-null, adds additional path components relative to bin dir, and
    /// overrides the basename of the Compile step for installation purposes.
    dest_sub_path: ?[]const u8 = null,

    pub const Dir = union(enum) {
        disabled,
        default,
        override: InstallDir,
    };
};

pub fn create(owner: *std.Build, artifact: *Step.Compile, options: Options) *InstallArtifact {
    const install_artifact = owner.allocator.create(InstallArtifact) catch @panic("OOM");
    const dest_dir: ?InstallDir = switch (options.dest_dir) {
        .disabled => null,
        .default => switch (artifact.kind) {
            .obj, .test_obj => @panic("object files have no standard installation procedure"),
            .exe, .@"test" => .bin,
            .lib => if (artifact.isDll()) .bin else .lib,
        },
        .override => |o| o,
    };
    const pdb_dir: ?InstallDir = switch (options.pdb_dir) {
        .disabled => null,
        .default => if (artifact.producesPdbFile()) dest_dir else null,
        .override => |o| o,
    };
    const implib_dir: ?InstallDir = switch (options.implib_dir) {
        .disabled => null,
        .default => if (artifact.producesImplib()) .lib else null,
        .override => |o| o,
    };
    install_artifact.* = .{
        .step = Step.init(.{
            .tag = base_tag,
            .name = owner.fmt("install {s}", .{artifact.name}),
            .owner = owner,
        }),
        .dest_dir = dest_dir,
        .pdb_dir = pdb_dir,
        .h_dir = switch (options.h_dir) {
            .disabled => null,
            .default => if (artifact.kind == .lib) .header else null,
            .override => |o| o,
        },
        .implib_dir = implib_dir,

        .dylib_symlinks = options.dylib_symlinks orelse (dest_dir != null and
            artifact.isDynamicLibrary() and artifact.version != null and
            std.Build.wantSharedLibSymLinks(artifact.rootModuleTarget())),

        .dest_sub_path = options.dest_sub_path,

        .emitted_bin = if (dest_dir != null) artifact.getEmittedBin() else null,
        .emitted_pdb = if (pdb_dir != null) artifact.getEmittedPdb() else null,
        // https://github.com/ziglang/zig/issues/9698
        .emitted_h = null,
        .emitted_implib = if (implib_dir != null) artifact.getEmittedImplib() else null,

        .artifact = artifact,
    };

    install_artifact.step.dependOn(&artifact.step);

    return install_artifact;
}
