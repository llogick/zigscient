const Module = @This();

const std = @import("std");
const assert = std.debug.assert;
const LazyPath = std.Build.LazyPath;
const Step = std.Build.Step;
const ArrayList = std.ArrayList;

/// The one responsible for creating this module.
owner: *std.Build,
root_source_file: ?LazyPath,
/// The modules that are mapped into this module's import table.
/// Use `addImport` rather than modifying this field directly in order to
/// maintain step dependency edges.
import_table: std.array_hash_map.String(*Module),

resolved_target: ?std.Build.ResolvedTarget = null,
optimize: ?std.builtin.OptimizeMode = null,
dwarf_format: ?std.dwarf.Format,

c_macros: ArrayList([]const u8),
include_dirs: ArrayList(IncludeDir),
lib_paths: ArrayList(LazyPath),
rpaths: ArrayList(RPath),
frameworks: std.array_hash_map.String(LinkFrameworkOptions),
link_objects: ArrayList(LinkObject),

strip: ?bool,
unwind_tables: ?std.builtin.UnwindTables,
single_threaded: ?bool,
stack_protector: ?bool,
stack_check: ?bool,
sanitize_c: ?std.zig.SanitizeC,
sanitize_thread: ?bool,
fuzz: ?bool,
code_model: std.builtin.CodeModel,
valgrind: ?bool,
pic: ?bool,
red_zone: ?bool,
omit_frame_pointer: ?bool,
error_tracing: ?bool,
link_libc: ?bool,
link_libcpp: ?bool,
no_builtin: ?bool,

/// Symbols to be exported when compiling to WebAssembly.
export_symbol_names: []const []const u8 = &.{},

/// Caches the result of `getGraph` when called multiple times.
/// Use `getGraph` instead of accessing this field directly.
cached_graph: Graph = .{ .modules = &.{}, .names = &.{} },

pub const RPath = union(enum) {
    lazy_path: LazyPath,
    special: []const u8,
};

pub const LinkObject = union(enum) {
    static_path: LazyPath,
    other_step: *Step.Compile,
    system_lib: SystemLib,
    assembly_file: LazyPath,
    c_source_file: *CSourceFile,
    c_source_files: *CSourceFiles,
    win32_resource_file: *RcSourceFile,
};

pub const SystemLib = struct {
    name: []const u8,
    needed: bool,
    weak: bool,
    use_pkg_config: UsePkgConfig,
    preferred_link_mode: std.builtin.LinkMode,
    search_strategy: SystemLib.SearchStrategy,

    pub const UsePkgConfig = std.Build.Configuration.SystemLib.UsePkgConfig;
    pub const SearchStrategy = std.Build.Configuration.SystemLib.SearchStrategy;
};

pub const CSourceLanguage = enum {
    c,
    cpp,

    objective_c,
    objective_cpp,

    /// Standard assembly
    assembly,
    /// Assembly with the C preprocessor
    assembly_with_preprocessor,

    /// The value passed to "-x" CLI flag of Clang.
    pub fn clangIdentifier(self: CSourceLanguage) [:0]const u8 {
        return switch (self) {
            .c => "c",
            .cpp => "c++",
            .objective_c => "objective-c",
            .objective_cpp => "objective-c++",
            .assembly => "assembler",
            .assembly_with_preprocessor => "assembler-with-cpp",
        };
    }
};

pub const CSourceFiles = struct {
    root: LazyPath,
    /// `files` is relative to `root`, which is
    /// the build root by default
    files: []const []const u8,
    flags: []const []const u8,
    /// By default, determines language of each file individually based on its file extension
    language: ?CSourceLanguage,
};

pub const CSourceFile = struct {
    file: LazyPath,
    flags: []const []const u8 = &.{},
    /// By default, determines language of each file individually based on its file extension
    language: ?CSourceLanguage = null,

    pub fn dupe(file: CSourceFile, graph: *const std.Build.Graph) CSourceFile {
        return .{
            .file = file.file.dupe(graph),
            .flags = graph.dupeStrings(file.flags),
            .language = file.language,
        };
    }
};

pub const RcSourceFile = struct {
    file: LazyPath,
    /// Any option that rc.exe accepts will work here, with the exception of:
    /// - `/fo`: The output filename is set by the build system
    /// - `/p`: Only running the preprocessor is not supported in this context
    /// - `/:no-preprocess` (non-standard option): Not supported in this context
    /// - Any MUI-related option
    /// https://learn.microsoft.com/en-us/windows/win32/menurc/using-rc-the-rc-command-line-
    ///
    /// Implicitly defined options:
    ///  /x (ignore the INCLUDE environment variable)
    ///  /D_DEBUG or /DNDEBUG depending on the optimization mode
    flags: []const []const u8 = &.{},
    /// Include paths that may or may not exist yet and therefore need to be
    /// specified as a LazyPath. Each path will be appended to the flags
    /// as `/I <resolved path>`.
    include_paths: []const LazyPath = &.{},

    pub fn dupe(file: RcSourceFile, graph: *const std.Build.Graph) RcSourceFile {
        return .{
            .file = file.file.dupe(graph),
            .flags = graph.dupeStrings(file.flags),
            .include_paths = LazyPath.dupeList(file.include_paths, graph),
        };
    }
};

pub const IncludeDir = union(enum) {
    path: LazyPath,
    path_system: LazyPath,
    path_after: LazyPath,
    framework_path: LazyPath,
    framework_path_system: LazyPath,
    other_step: *Step.Compile,
    config_header_step: *Step.ConfigHeader,
    embed_path: LazyPath,
};

pub const LinkFrameworkOptions = struct {
    /// Causes dynamic libraries to be linked regardless of whether they are
    /// actually depended on. When false, dynamic libraries with no referenced
    /// symbols will be omitted by the linker.
    needed: bool = false,
    /// Marks all referenced symbols from this library as weak, meaning that if
    /// a same-named symbol is provided by another compilation unit, instead of
    /// emitting a "duplicate symbol" error, the linker will resolve all
    /// references to the symbol with the strong version.
    ///
    /// When the linker encounters two weak symbols, the chosen one is
    /// determined by the order compilation units are provided to the linker,
    /// priority given to later ones.
    weak: bool = false,
};

/// Unspecified options here will be inherited from parent `Module` when
/// inserted into an import table.
pub const CreateOptions = struct {
    /// This could either be a generated file, in which case the module
    /// contains exactly one file, or it could be a path to the root source
    /// file of directory of files which constitute the module.
    /// If `null`, it means this module is made up of only `link_objects`.
    root_source_file: ?LazyPath = null,

    /// The table of other modules that this module can access via `@import`.
    /// Imports are allowed to be cyclical, so this table can be added to after
    /// the `Module` is created via `addImport`.
    imports: []const Import = &.{},

    target: ?std.Build.ResolvedTarget = null,
    optimize: ?std.builtin.OptimizeMode = null,

    /// `true` requires a compilation that includes this Module to link libc.
    /// `false` causes a build failure if a compilation that includes this Module would link libc.
    /// `null` neither requires nor prevents libc from being linked.
    link_libc: ?bool = null,
    /// `true` requires a compilation that includes this Module to link libc++.
    /// `false` causes a build failure if a compilation that includes this Module would link libc++.
    /// `null` neither requires nor prevents libc++ from being linked.
    link_libcpp: ?bool = null,
    single_threaded: ?bool = null,
    strip: ?bool = null,
    unwind_tables: ?std.builtin.UnwindTables = null,
    dwarf_format: ?std.dwarf.Format = null,
    code_model: std.builtin.CodeModel = .default,
    stack_protector: ?bool = null,
    stack_check: ?bool = null,
    sanitize_c: ?std.zig.SanitizeC = null,
    sanitize_thread: ?bool = null,
    fuzz: ?bool = null,
    /// Whether to emit machine code that integrates with Valgrind.
    valgrind: ?bool = null,
    /// Position Independent Code
    pic: ?bool = null,
    red_zone: ?bool = null,
    /// Whether to omit the stack frame pointer. Frees up a register and makes it
    /// more difficult to obtain stack traces. Has target-dependent effects.
    omit_frame_pointer: ?bool = null,
    error_tracing: ?bool = null,
    no_builtin: ?bool = null,
};

pub const Import = struct {
    name: []const u8,
    module: *Module,
};

pub fn init(
    m: *Module,
    owner: *std.Build,
    value: union(enum) { options: CreateOptions, existing: *const Module },
) void {
    const graph = owner.graph;
    const arena = graph.arena;

    switch (value) {
        .options => |options| {
            m.* = .{
                .owner = owner,
                .root_source_file = if (options.root_source_file) |lp| lp.dupe(graph) else null,
                .import_table = .empty,
                .resolved_target = options.target,
                .optimize = options.optimize,
                .link_libc = options.link_libc,
                .link_libcpp = options.link_libcpp,
                .dwarf_format = options.dwarf_format,
                .c_macros = .empty,
                .include_dirs = .empty,
                .lib_paths = .empty,
                .rpaths = .empty,
                .frameworks = .empty,
                .link_objects = .empty,
                .strip = options.strip,
                .unwind_tables = options.unwind_tables,
                .single_threaded = options.single_threaded,
                .stack_protector = options.stack_protector,
                .stack_check = options.stack_check,
                .sanitize_c = options.sanitize_c,
                .sanitize_thread = options.sanitize_thread,
                .fuzz = options.fuzz,
                .code_model = options.code_model,
                .valgrind = options.valgrind,
                .pic = options.pic,
                .red_zone = options.red_zone,
                .omit_frame_pointer = options.omit_frame_pointer,
                .error_tracing = options.error_tracing,
                .export_symbol_names = &.{},
                .no_builtin = options.no_builtin,
            };

            m.import_table.ensureUnusedCapacity(arena, options.imports.len) catch @panic("OOM");
            for (options.imports) |dep| {
                m.import_table.putAssumeCapacity(dep.name, dep.module);
            }
        },
        .existing => |existing| {
            m.* = existing.*;
        },
    }
}

pub fn create(owner: *std.Build, options: CreateOptions) *Module {
    const graph = owner.graph;
    const arena = graph.arena;
    const m = arena.create(Module) catch @panic("OOM");
    m.init(owner, .{ .options = options });
    return m;
}

/// Adds an existing module to be used with `@import`.
pub fn addImport(m: *Module, name: []const u8, module: *Module) void {
    const graph = m.owner.graph;
    const arena = graph.arena;
    m.import_table.put(arena, graph.dupeString(name), module) catch @panic("OOM");
}

/// Creates a new module and adds it to be used with `@import`.
pub fn addAnonymousImport(m: *Module, name: []const u8, options: CreateOptions) void {
    const module = create(m.owner, options);
    return addImport(m, name, module);
}

/// Converts a set of key-value pairs into a Zig source file, and then inserts it into
/// the Module's import table with the specified name. This makes the options importable
/// via `@import("module_name")`.
pub fn addOptions(m: *Module, module_name: []const u8, options: *Step.Options) void {
    addImport(m, module_name, options.createModule());
}

pub const LinkSystemLibraryOptions = struct {
    /// Causes dynamic libraries to be linked regardless of whether they are
    /// actually depended on. When false, dynamic libraries with no referenced
    /// symbols will be omitted by the linker.
    needed: bool = false,
    /// Marks all referenced symbols from this library as weak, meaning that if
    /// a same-named symbol is provided by another compilation unit, instead of
    /// emitting a "duplicate symbol" error, the linker will resolve all
    /// references to the symbol with the strong version.
    ///
    /// When the linker encounters two weak symbols, the chosen one is
    /// determined by the order compilation units are provided to the linker,
    /// priority given to later ones.
    weak: bool = false,
    use_pkg_config: SystemLib.UsePkgConfig = .yes,
    preferred_link_mode: std.builtin.LinkMode = .dynamic,
    search_strategy: SystemLib.SearchStrategy = .paths_first,
};

pub fn linkSystemLibrary(
    m: *Module,
    name: []const u8,
    options: LinkSystemLibraryOptions,
) void {
    const graph = m.owner.graph;
    const arena = graph.arena;

    const target = m.requireKnownTarget();
    if (std.zig.target.isLibCLibName(target, name)) {
        m.link_libc = true;
        return;
    }
    if (std.zig.target.isLibCxxLibName(target, name)) {
        m.link_libcpp = true;
        return;
    }

    m.link_objects.append(arena, .{
        .system_lib = .{
            .name = graph.dupeString(name),
            .needed = options.needed,
            .weak = options.weak,
            .use_pkg_config = options.use_pkg_config,
            .preferred_link_mode = options.preferred_link_mode,
            .search_strategy = options.search_strategy,
        },
    }) catch @panic("OOM");
}

pub fn linkFramework(m: *Module, name: []const u8, options: LinkFrameworkOptions) void {
    const graph = m.owner.graph;
    const arena = graph.arena;
    m.frameworks.put(arena, graph.dupeString(name), options) catch @panic("OOM");
}

pub const AddCSourceFilesOptions = struct {
    /// When provided, `files` are relative to `root` rather than the
    /// package that owns the `Compile` step.
    root: ?LazyPath = null,
    files: []const []const u8,
    flags: []const []const u8 = &.{},
    /// By default, determines language of each file individually based on its file extension
    language: ?CSourceLanguage = null,
};

/// Handy when you have many non-Zig source files and want them all to have the same flags.
pub fn addCSourceFiles(m: *Module, options: AddCSourceFilesOptions) void {
    const b = m.owner;
    const graph = m.owner.graph;
    const arena = graph.arena;

    for (options.files) |path| {
        if (std.fs.path.isAbsolute(path)) {
            std.debug.panic(
                "file paths added with 'addCSourceFiles' must be relative, found absolute path '{s}'",
                .{path},
            );
        }
    }

    const c_source_files = arena.create(CSourceFiles) catch @panic("OOM");
    c_source_files.* = .{
        .root = options.root orelse b.path(""),
        .files = b.dupeStrings(options.files),
        .flags = b.dupeStrings(options.flags),
        .language = options.language,
    };
    m.link_objects.append(arena, .{ .c_source_files = c_source_files }) catch @panic("OOM");
}

pub fn addCSourceFile(m: *Module, source: CSourceFile) void {
    const graph = m.owner.graph;
    const arena = graph.arena;
    const c_source_file = arena.create(CSourceFile) catch @panic("OOM");
    c_source_file.* = source.dupe(graph);
    m.link_objects.append(arena, .{ .c_source_file = c_source_file }) catch @panic("OOM");
}

/// Resource files must have the extension `.rc`.
/// Can be called regardless of target. The .rc file will be ignored
/// if the target object format does not support embedded resources.
pub fn addWin32ResourceFile(m: *Module, source: RcSourceFile) void {
    const graph = m.owner.graph;
    const arena = graph.arena;
    const target = m.requireKnownTarget();
    // Only the PE/COFF format has a Resource Table, so for any other target
    // the resource file is ignored.
    if (target.ofmt != .coff) return;

    const rc_source_file = arena.create(RcSourceFile) catch @panic("OOM");
    rc_source_file.* = source.dupe(graph);
    m.link_objects.append(arena, .{ .win32_resource_file = rc_source_file }) catch @panic("OOM");
}

pub fn addAssemblyFile(m: *Module, source: LazyPath) void {
    const graph = m.owner.graph;
    const arena = graph.arena;
    m.link_objects.append(arena, .{ .assembly_file = source.dupe(graph) }) catch @panic("OOM");
}

pub fn addObjectFile(m: *Module, object: LazyPath) void {
    const graph = m.owner.graph;
    const arena = graph.arena;
    m.link_objects.append(arena, .{ .static_path = object.dupe(graph) }) catch @panic("OOM");
}

pub fn addObject(m: *Module, object: *Step.Compile) void {
    assert(object.kind == .obj or object.kind == .test_obj);
    m.linkLibraryOrObject(object);
}

pub fn linkLibrary(m: *Module, library: *Step.Compile) void {
    assert(library.kind == .lib);
    m.linkLibraryOrObject(library);
}

pub fn addAfterIncludePath(m: *Module, lazy_path: LazyPath) void {
    const graph = m.owner.graph;
    const arena = graph.arena;
    m.include_dirs.append(arena, .{ .path_after = lazy_path.dupe(graph) }) catch @panic("OOM");
}

pub fn addSystemIncludePath(m: *Module, lazy_path: LazyPath) void {
    const graph = m.owner.graph;
    const arena = graph.arena;
    m.include_dirs.append(arena, .{ .path_system = lazy_path.dupe(graph) }) catch @panic("OOM");
}

pub fn addIncludePath(m: *Module, lazy_path: LazyPath) void {
    const graph = m.owner.graph;
    const arena = graph.arena;
    m.include_dirs.append(arena, .{ .path = lazy_path.dupe(graph) }) catch @panic("OOM");
}

pub fn addConfigHeader(m: *Module, config_header: *Step.ConfigHeader) void {
    const graph = m.owner.graph;
    const arena = graph.arena;
    m.include_dirs.append(arena, .{ .config_header_step = config_header }) catch @panic("OOM");
}

pub fn addSystemFrameworkPath(m: *Module, directory_path: LazyPath) void {
    const graph = m.owner.graph;
    const arena = graph.arena;
    m.include_dirs.append(arena, .{ .framework_path_system = directory_path.dupe(graph) }) catch @panic("OOM");
}

pub fn addFrameworkPath(m: *Module, directory_path: LazyPath) void {
    const graph = m.owner.graph;
    const arena = graph.arena;
    m.include_dirs.append(arena, .{ .framework_path = directory_path.dupe(graph) }) catch @panic("OOM");
}

pub fn addEmbedPath(m: *Module, lazy_path: LazyPath) void {
    const graph = m.owner.graph;
    const arena = graph.arena;
    m.include_dirs.append(arena, .{ .embed_path = lazy_path.dupe(graph) }) catch @panic("OOM");
}

pub fn addLibraryPath(m: *Module, directory_path: LazyPath) void {
    const graph = m.owner.graph;
    const arena = graph.arena;
    m.lib_paths.append(arena, directory_path.dupe(graph)) catch @panic("OOM");
}

pub fn addRPath(m: *Module, directory_path: LazyPath) void {
    const graph = m.owner.graph;
    const arena = graph.arena;
    m.rpaths.append(arena, .{ .lazy_path = directory_path.dupe(graph) }) catch @panic("OOM");
}

pub fn addRPathSpecial(m: *Module, bytes: []const u8) void {
    const graph = m.owner.graph;
    const arena = graph.arena;
    m.rpaths.append(arena, .{ .special = graph.dupeString(bytes) }) catch @panic("OOM");
}

/// Equvialent to the following C code, applied to all C source files owned by
/// this `Module`:
/// ```c
/// #define name value
/// ```
/// `name` and `value` need not live longer than the function call.
pub fn addCMacro(m: *Module, name: []const u8, value: []const u8) void {
    const b = m.owner;
    const graph = m.owner.graph;
    const arena = graph.arena;
    m.c_macros.append(arena, b.fmt("-D{s}={s}", .{ name, value })) catch @panic("OOM");
}

fn linkLibraryOrObject(m: *Module, other: *Step.Compile) void {
    const graph = m.owner.graph;
    const arena = graph.arena;

    _ = other.getEmittedBin(); // Indicate there is a dependency on the outputted binary.

    if (other.rootModuleTarget().os.tag == .windows and other.isDynamicLibrary()) {
        _ = other.getEmittedImplib(); // Indicate dependency on the outputted implib.
    }

    m.link_objects.append(arena, .{ .other_step = other }) catch @panic("OOM");
    m.include_dirs.append(arena, .{ .other_step = other }) catch @panic("OOM");
}

fn requireKnownTarget(m: *Module) *const std.Target {
    const resolved_target = &(m.resolved_target orelse
        @panic("this API requires the Module to be created with a known 'target' field"));
    return &resolved_target.result;
}

/// Elements of `modules` and `names` are matched one-to-one.
pub const Graph = struct {
    modules: []const *Module,
    names: []const []const u8,
};

/// Given that `root` is the root `Module` of a compilation, return all
/// `Module` in the module graph, including `root` itself. `root` is guaranteed
/// to be the first module in the returned slice.
pub fn getGraph(root: *Module) Graph {
    if (root.cached_graph.modules.len != 0) {
        return root.cached_graph;
    }

    const arena = root.owner.graph.arena;

    var modules: std.array_hash_map.Auto(*std.Build.Module, []const u8) = .empty;
    var next_idx: usize = 0;

    modules.putNoClobber(arena, root, "root") catch @panic("OOM");

    while (next_idx < modules.count()) {
        const mod = modules.keys()[next_idx];
        next_idx += 1;
        modules.ensureUnusedCapacity(arena, mod.import_table.count()) catch @panic("OOM");
        for (mod.import_table.keys(), mod.import_table.values()) |import_name, other_mod| {
            modules.putAssumeCapacity(other_mod, import_name);
        }
    }

    const result: Graph = .{
        .modules = modules.keys(),
        .names = modules.values(),
    };
    root.cached_graph = result;
    return result;
}
