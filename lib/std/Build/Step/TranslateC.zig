const TranslateC = @This();

const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const allocPrint = std.fmt.allocPrint;
const Step = std.Build.Step;
const LazyPath = std.Build.LazyPath;
const Configuration = std.Build.Configuration;

step: Step,
source: std.Build.LazyPath,
include_dirs: std.ArrayList(std.Build.Module.IncludeDir) = .empty,
system_libs: std.ArrayList(std.Build.Module.SystemLib) = .empty,
c_macros: std.ArrayList(Configuration.String) = .empty,
target: std.Build.ResolvedTarget,
optimize: std.builtin.OptimizeMode,
output_file: Configuration.GeneratedFileIndex,
link_libc: bool,

pub const base_tag: Step.Tag = .translate_c;

pub const Options = struct {
    root_source_file: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    link_libc: bool = true,
};

pub fn create(owner: *std.Build, options: Options) *TranslateC {
    const graph = owner.graph;
    const translate_c = graph.create(TranslateC);
    const source = options.root_source_file.dupe(graph);
    translate_c.* = .{
        .step = .init(.{
            .tag = base_tag,
            .name = "translate-c",
            .owner = owner,
        }),
        .source = source,
        .target = options.target,
        .optimize = options.optimize,
        .output_file = graph.addGeneratedFile(&translate_c.step),
        .link_libc = options.link_libc,
    };
    source.addStepDependencies(&translate_c.step);
    return translate_c;
}

pub const AddExecutableOptions = struct {
    name: ?[]const u8 = null,
    version: ?std.SemanticVersion = null,
    target: ?std.Build.ResolvedTarget = null,
    optimize: ?std.builtin.OptimizeMode = null,
    linkage: ?std.builtin.LinkMode = null,
};

pub fn getOutput(translate_c: *TranslateC) std.Build.LazyPath {
    return .{ .generated = .{ .index = translate_c.output_file } };
}

/// Creates a module from the translated source and adds it to the package's
/// module set making it available to other packages which depend on this one.
/// `createModule` can be used instead to create a private module.
pub fn addModule(translate_c: *TranslateC, name: []const u8) *std.Build.Module {
    return setUpModule(translate_c, translate_c.step.owner.addModule(name, .{
        .root_source_file = translate_c.getOutput(),
        .target = translate_c.target,
        .optimize = translate_c.optimize,
        .link_libc = translate_c.link_libc,
    }));
}

/// Creates a private module from the translated source to be used by the
/// current package, but not exposed to other packages depending on this one.
/// `addModule` can be used instead to create a public module.
pub fn createModule(translate_c: *TranslateC) *std.Build.Module {
    return setUpModule(translate_c, translate_c.step.owner.createModule(.{
        .root_source_file = translate_c.getOutput(),
        .target = translate_c.target,
        .optimize = translate_c.optimize,
        .link_libc = translate_c.link_libc,
    }));
}

fn setUpModule(translate_c: *TranslateC, module: *std.Build.Module) *std.Build.Module {
    const graph = translate_c.step.owner.graph;
    const arena = graph.arena;

    if (translate_c.link_libc) module.link_libc = true;

    for (translate_c.system_libs.items) |system_lib| {
        module.link_objects.append(arena, .{ .system_lib = system_lib }) catch @panic("OOM");
    }

    return module;
}

pub fn addAfterIncludePath(translate_c: *TranslateC, lazy_path: LazyPath) void {
    const graph = translate_c.step.owner.graph;
    const arena = graph.arena;
    translate_c.include_dirs.append(arena, .{ .path_after = lazy_path.dupe(graph) }) catch
        @panic("OOM");
    lazy_path.addStepDependencies(&translate_c.step);
}

pub fn addSystemIncludePath(translate_c: *TranslateC, lazy_path: LazyPath) void {
    const graph = translate_c.step.owner.graph;
    const arena = graph.arena;
    translate_c.include_dirs.append(arena, .{ .path_system = lazy_path.dupe(graph) }) catch
        @panic("OOM");
    lazy_path.addStepDependencies(&translate_c.step);
}

pub fn addIncludePath(translate_c: *TranslateC, lazy_path: LazyPath) void {
    const graph = translate_c.step.owner.graph;
    const arena = graph.arena;
    translate_c.include_dirs.append(arena, .{ .path = lazy_path.dupe(graph) }) catch
        @panic("OOM");
    lazy_path.addStepDependencies(&translate_c.step);
}

pub fn addConfigHeader(translate_c: *TranslateC, config_header: *Step.ConfigHeader) void {
    const graph = translate_c.step.owner.graph;
    const arena = graph.arena;
    translate_c.include_dirs.append(arena, .{ .config_header_step = config_header }) catch
        @panic("OOM");
    translate_c.step.dependOn(&config_header.step);
}

pub fn addSystemFrameworkPath(translate_c: *TranslateC, directory_path: LazyPath) void {
    const graph = translate_c.step.owner.graph;
    const arena = graph.arena;
    translate_c.include_dirs.append(arena, .{ .framework_path_system = directory_path.dupe(graph) }) catch
        @panic("OOM");
    directory_path.addStepDependencies(&translate_c.step);
}

pub fn addFrameworkPath(translate_c: *TranslateC, directory_path: LazyPath) void {
    const graph = translate_c.step.owner.graph;
    const arena = graph.arena;
    translate_c.include_dirs.append(arena, .{ .framework_path = directory_path.dupe(graph) }) catch
        @panic("OOM");
    directory_path.addStepDependencies(&translate_c.step);
}

pub fn addCheckFile(translate_c: *TranslateC, expected_matches: []const []const u8) *Step.CheckFile {
    return Step.CheckFile.create(
        translate_c.step.owner,
        translate_c.getOutput(),
        .{ .expected_matches = expected_matches },
    );
}

/// If the value is omitted, it is set to 1.
/// `name` and `value` need not live longer than the function call.
pub fn defineCMacro(translate_c: *TranslateC, name: []const u8, value: ?[]const u8) void {
    const graph = translate_c.step.owner.graph;
    const arena = graph.arena;
    const wc = &graph.wip_configuration;
    const macro = allocPrint(arena, "{s}={s}", .{ name, value orelse "1" }) catch @panic("OOM");
    const macro_string = wc.addString(macro) catch @panic("OOM");
    translate_c.c_macros.append(arena, macro_string) catch @panic("OOM");
}

/// name_and_value looks like [name]=[value].
pub fn defineCMacroRaw(translate_c: *TranslateC, name_and_value: []const u8) void {
    const graph = translate_c.step.owner.graph;
    const arena = graph.arena;
    const wc = &graph.wip_configuration;
    const macro_string = wc.addString(name_and_value) catch @panic("OOM");
    translate_c.c_macros.append(arena, macro_string) catch @panic("OOM");
}

pub fn linkSystemLibrary(
    translate_c: *TranslateC,
    name: []const u8,
    options: std.Build.Module.LinkSystemLibraryOptions,
) void {
    const graph = translate_c.step.owner.graph;
    const arena = graph.arena;
    translate_c.system_libs.append(arena, .{
        .name = graph.dupeString(name),
        .needed = options.needed,
        .weak = options.weak,
        .use_pkg_config = options.use_pkg_config,
        .preferred_link_mode = options.preferred_link_mode,
        .search_strategy = options.search_strategy,
    }) catch @panic("OOM");
}
