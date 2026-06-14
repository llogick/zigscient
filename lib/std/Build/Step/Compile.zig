const Compile = @This();

const builtin = @import("builtin");

const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const fs = std.fs;
const assert = std.debug.assert;
const panic = std.debug.panic;
const StringHashMap = std.StringHashMap;
const Allocator = std.mem.Allocator;
const Step = std.Build.Step;
const LazyPath = std.Build.LazyPath;
const Module = std.Build.Module;
const InstallDir = std.Build.InstallDir;
const Path = std.Build.Cache.Path;
const Configuration = std.Build.Configuration;

pub const base_tag: Step.Tag = .compile;

step: Step,
root_module: *Module,

name: []const u8,
linker_script: ?LazyPath = null,
version_script: ?LazyPath = null,
/// Deprecated.
out_filename: []const u8,
linkage: ?std.builtin.LinkMode = null,
version: ?std.SemanticVersion,
kind: Kind,
formatted_panics: ?bool = null,
compress_debug_sections: std.zig.CompressDebugSections = .none,
verbose_link: bool,
verbose_cc: bool,
bundle_compiler_rt: ?bool = null,
bundle_ubsan_rt: ?bool = null,
rdynamic: bool,
import_memory: bool = false,
export_memory: bool = false,
/// For WebAssembly targets, this will allow for undefined symbols to
/// be imported from the host environment.
import_symbols: bool = false,
/// (WebAssembly) import function table from the host environment
import_table: bool = false,
export_table: bool = false,
initial_memory: ?u64 = null,
max_memory: ?u64 = null,
shared_memory: bool = false,
global_base: ?u64 = null,
/// Set via options; intended to be read-only after that.
zig_lib_dir: ?LazyPath,
exec_cmd_args: ?[]const ?[]const u8,
filters: []const []const u8,
test_runner: ?TestRunner,
wasi_exec_model: ?std.builtin.WasiExecModel = null,

installed_headers: std.ArrayList(HeaderInstallation),

/// This step is used to create an include tree that dependent modules can add to their include
/// search paths. Installed headers are copied to this step.
/// This step is created the first time a module links with this artifact and is not
/// created otherwise.
installed_headers_include_tree: ?*Step.WriteFile = null,

/// Behavior of automatic detection of include directories when compiling .rc files.
///  any: Use MSVC if available, fall back to MinGW.
///  msvc: Use MSVC include paths (must be present on the system).
///  gnu: Use MinGW include paths (distributed with Zig).
///  none: Do not use any autodetected include paths.
rc_includes: std.zig.RcIncludes = .any,

/// (Windows) .manifest file to embed in the compilation
/// Set via options; intended to be read-only after that.
win32_manifest: ?LazyPath = null,

/// (Windows) .def file to embed in the compilation (dll)
/// Set via options; intended to be read-only after that.
win32_module_definition: ?LazyPath = null,

/// Base address for an executable image.
image_base: ?u64 = null,

libc_file: ?LazyPath = null,

each_lib_rpath: ?bool = null,
/// On ELF targets, this will emit a link section called ".note.gnu.build-id"
/// which can be used to coordinate a stripped binary with its debug symbols.
///
/// As an example, the bloaty project refuses to work unless its inputs have
/// build ids, in order to prevent accidental mismatches.
///
/// The default is to not include this section because it slows down linking.
///
/// This option overrides the CLI argument passed to `zig build`.
build_id: ?std.zig.BuildId = null,

/// Create a .eh_frame_hdr section and a PT_GNU_EH_FRAME segment in the ELF
/// file.
link_eh_frame_hdr: bool = false,
link_emit_relocs: bool = false,

/// Place every function in its own section so that unused ones may be
/// safely garbage-collected during the linking phase.
link_function_sections: bool = false,

/// Place every data in its own section so that unused ones may be
/// safely garbage-collected during the linking phase.
link_data_sections: bool = false,

/// Remove functions and data that are unreachable by the entry point or
/// exported symbols.
link_gc_sections: ?bool = null,

/// (Windows) Whether or not to enable ASLR. Maps to the /DYNAMICBASE[:NO] linker argument.
linker_dynamicbase: bool = true,

linker_allow_shlib_undefined: ?bool = null,

/// Allow version scripts to refer to undefined symbols.
linker_allow_undefined_version: ?bool = null,

// Enable (or disable) the new DT_RUNPATH tag in the dynamic section.
linker_enable_new_dtags: ?bool = null,

/// Permit read-only relocations in read-only segments. Disallowed by default.
link_z_notext: bool = false,

/// Force all relocations to be read-only after processing.
link_z_relro: bool = true,

/// Allow relocations to be lazily processed after load.
link_z_lazy: bool = false,

/// Common page size
link_z_common_page_size: ?u64 = null,

/// Maximum page size
link_z_max_page_size: ?u64 = null,

/// Force a fatal error if any undefined symbols remain.
link_z_defs: bool = false,

/// (Darwin) Install name for the dylib
install_name: ?[]const u8 = null,

/// Must be passed in via `Options`.
entitlements: ?LazyPath = null,

/// (Darwin) Size of the pagezero segment.
pagezero_size: ?u64 = null,

/// (Darwin) Set size of the padding between the end of load commands
/// and start of `__TEXT,__text` section.
headerpad_size: ?u32 = null,

/// (Darwin) Automatically Set size of the padding between the end of load commands
/// and start of `__TEXT,__text` section to a value fitting all paths expanded to MAXPATHLEN.
headerpad_max_install_names: bool = false,

/// (Darwin) Remove dylibs that are unreachable by the entry point or exported symbols.
dead_strip_dylibs: bool = false,

/// (Darwin) Force load all members of static archives that implement an Objective-C class or category
force_load_objc: bool = false,

/// Whether local symbols should be discarded from the symbol table.
discard_local_symbols: bool = false,

/// Position Independent Executable
pie: ?bool = null,

/// Link Time Optimization mode
lto: ?std.zig.LtoMode = null,

dll_export_fns: ?bool = null,

subsystem: ?std.zig.Subsystem = null,

/// (Windows) When targeting the MinGW ABI, use the unicode entry point (wmain/wWinMain)
mingw_unicode_entry_point: bool = false,

/// How the linker must handle the entry point of the executable.
entry: Entry = .default,

/// List of symbols forced as undefined in the symbol table
/// thus forcing their resolution by the linker.
/// Corresponds to `-u <symbol>` for ELF/MachO and `/include:<symbol>` for COFF/PE.
force_undefined_symbols: std.array_hash_map.String(void),

/// Overrides the default stack size
stack_size: ?u64 = null,

use_llvm: ?bool,
use_lld: ?bool,
use_new_linker: ?bool,

/// Corresponds to the `-fallow-so-scripts` / `-fno-allow-so-scripts` CLI
/// flags, overriding the global user setting provided to the `zig build`
/// command.
///
/// The compiler defaults this value to off so that users whose system shared
/// libraries are all ELF files don't have to pay the cost of checking every
/// file to find out if it is a text file instead.
allow_so_scripts: ?bool = null,

/// This is an advanced setting that can change the intent of this Compile step.
/// If this value is non-null, it means that this Compile step exists to
/// check for compile errors and return *success* if they match, and failure
/// otherwise.
expect_errors: ?ExpectedCompileErrors = null,

/// The maximum number of distinct errors within a compilation step Defaults to
/// `std.math.maxInt(u16)`. Overrides the argument passed to `zig build`.
error_limit: ?u32 = null,

/// Computed during make().
is_linking_libc: bool = false,
/// Computed during make().
is_linking_libcpp: bool = false,

/// Enables coverage instrumentation that is only useful if you are using third
/// party fuzzers that depend on it. Otherwise, slows down the instrumented
/// binary with unnecessary function calls.
///
/// This kind of coverage instrumentation is used by AFLplusplus v4.21c,
/// however, modern fuzzers - including Zig - have switched to using "inline
/// 8-bit counters" or "inline bool flag" which incurs only a single
/// instruction for coverage, along with "trace cmp" which instruments
/// comparisons and reports the operands.
///
/// To instead enable fuzz testing instrumentation on a compilation using Zig's
/// builtin fuzzer, see the `fuzz` flag in `Module`.
sanitize_coverage_trace_pc_guard: ?bool = null,

/// Enable or disable incremental compilation.
///
/// Incremental compilation reduces compile time by mutating an existing build artifact. Non-
/// incremental compilation is slower but preserves previous build artifacts.
incremental: ?bool = null,

emit_directory: Configuration.OptionalGeneratedFileIndex = .none,
generated_docs: Configuration.OptionalGeneratedFileIndex = .none,
generated_asm: Configuration.OptionalGeneratedFileIndex = .none,
generated_bin: Configuration.OptionalGeneratedFileIndex = .none,
generated_pdb: Configuration.OptionalGeneratedFileIndex = .none,
generated_implib: Configuration.OptionalGeneratedFileIndex = .none,
generated_llvm_bc: Configuration.OptionalGeneratedFileIndex = .none,
generated_llvm_ir: Configuration.OptionalGeneratedFileIndex = .none,
generated_h: Configuration.OptionalGeneratedFileIndex = .none,

pub const ExpectedCompileErrors = union(enum) {
    contains: []const u8,
    exact: []const []const u8,
    starts_with: []const u8,
    stderr_contains: []const u8,
};

pub const Entry = union(enum) {
    /// Let the compiler decide whether to make an entry point and what to name
    /// it.
    default,
    /// The executable will have no entry point.
    disabled,
    /// The executable will have an entry point with the default symbol name.
    enabled,
    /// The executable will have an entry point with the specified symbol name.
    symbol_name: []const u8,
};

pub const Options = struct {
    name: []const u8,
    root_module: *Module,
    kind: Kind,
    linkage: ?std.builtin.LinkMode = null,
    version: ?std.SemanticVersion = null,
    max_rss: u64 = 0,
    filters: []const []const u8 = &.{},
    test_runner: ?TestRunner = null,
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    zig_lib_dir: ?LazyPath = null,
    /// Embed a `.manifest` file in the compilation if the object format supports it.
    /// https://learn.microsoft.com/en-us/windows/win32/sbscs/manifest-files-reference
    /// Manifest files must have the extension `.manifest`.
    /// Can be set regardless of target. The `.manifest` file will be ignored
    /// if the target object format does not support embedded manifests.
    win32_manifest: ?LazyPath = null,
    /// Win32 module definition file.
    win32_module_definition: ?LazyPath = null,
    /// (Darwin) Path to entitlements file
    entitlements: ?LazyPath = null,
};

pub const Kind = Configuration.Step.Compile.Kind;

pub const HeaderInstallation = union(enum) {
    file: File,
    directory: Directory,

    pub const File = struct {
        source: LazyPath,
        dest_rel_path: []const u8,

        pub fn dupe(file: File, graph: *const std.Build.Graph) File {
            return .{
                .source = file.source.dupe(graph),
                .dest_rel_path = graph.dupePath(file.dest_rel_path),
            };
        }
    };

    pub const Directory = struct {
        source: LazyPath,
        dest_rel_path: []const u8,
        options: Directory.Options,

        pub const Options = struct {
            /// File paths that end in any of these suffixes will be excluded from installation.
            exclude_extensions: []const []const u8 = &.{},
            /// Only file paths that end in any of these suffixes will be included in installation.
            /// `null` means that all suffixes will be included.
            /// `exclude_extensions` takes precedence over `include_extensions`.
            include_extensions: ?[]const []const u8 = &.{".h"},

            pub fn dupe(opts: Directory.Options, graph: *const std.Build.Graph) Directory.Options {
                return .{
                    .exclude_extensions = graph.dupeStrings(opts.exclude_extensions),
                    .include_extensions = if (opts.include_extensions) |incs| graph.dupeStrings(incs) else null,
                };
            }
        };

        pub fn dupe(dir: Directory, graph: *const std.Build.Graph) Directory {
            return .{
                .source = dir.source.dupe(graph),
                .dest_rel_path = graph.dupePath(dir.dest_rel_path),
                .options = dir.options.dupe(graph),
            };
        }
    };

    pub fn getSource(installation: HeaderInstallation) LazyPath {
        return switch (installation) {
            inline .file, .directory => |x| x.source,
        };
    }

    pub fn dupe(installation: HeaderInstallation, graph: *const std.Build.Graph) HeaderInstallation {
        return switch (installation) {
            .file => |f| .{ .file = f.dupe(graph) },
            .directory => |d| .{ .directory = d.dupe(graph) },
        };
    }
};

pub const TestRunner = struct {
    path: LazyPath,
    /// Test runners can either be "simple", running tests when spawned and terminating when the
    /// tests are complete, or they can use `std.zig.Server` over stdio to interact more closely
    /// with the build system.
    mode: enum { simple, server },
};

pub fn create(owner: *std.Build, options: Options) *Compile {
    const graph = owner.graph;
    const arena = graph.arena;

    const name = owner.dupe(options.name);
    if (mem.find(u8, name, "/") != null or mem.find(u8, name, "\\") != null) {
        panic("invalid name: '{s}'. It looks like a file path, but it is supposed to be the library or application name.", .{name});
    }

    const resolved_target = options.root_module.resolved_target orelse
        @panic("the root Module of a Compile step must be created with a known 'target' field");
    const target = &resolved_target.result;

    const step_name = owner.fmt("compile {s} {s} {s}", .{
        // Avoid the common case of the step name looking like "compile test test".
        if (options.kind.isTest() and mem.eql(u8, name, "test"))
            @tagName(options.kind)
        else
            owner.fmt("{t} {s}", .{ options.kind, name }),
        @tagName(options.root_module.optimize orelse .Debug),
        resolved_target.query.zigTriple(arena) catch @panic("OOM"),
    });

    const out_filename = std.zig.binNameAlloc(arena, .{
        .root_name = name,
        .cpu_arch = target.cpu.arch,
        .os_tag = target.os.tag,
        .ofmt = target.ofmt,
        .abi = target.abi,
        .output_mode = switch (options.kind) {
            .lib => .Lib,
            .obj, .test_obj => .Obj,
            .exe, .@"test" => .Exe,
        },
        .link_mode = options.linkage,
        .version = options.version,
    }) catch @panic("OOM");

    const compile = arena.create(Compile) catch @panic("OOM");
    compile.* = .{
        .root_module = options.root_module,
        .verbose_link = false,
        .verbose_cc = false,
        .linkage = options.linkage,
        .kind = options.kind,
        .name = name,
        .step = .init(.{
            .tag = base_tag,
            .name = step_name,
            .owner = owner,
            .max_rss = options.max_rss,
        }),
        .version = options.version,
        .out_filename = out_filename,
        .installed_headers = .empty,
        .zig_lib_dir = null,
        .exec_cmd_args = null,
        .filters = options.filters,
        .test_runner = null, // set below
        .rdynamic = false,
        .force_undefined_symbols = .empty,

        .use_llvm = options.use_llvm,
        .use_lld = options.use_lld,
        .use_new_linker = null,
    };

    if (options.zig_lib_dir) |lp| {
        compile.zig_lib_dir = lp.dupe(graph);
        lp.addStepDependencies(&compile.step);
    }

    if (options.test_runner) |runner| {
        compile.test_runner = .{
            .path = runner.path.dupe(graph),
            .mode = runner.mode,
        };
        runner.path.addStepDependencies(&compile.step);
    }

    // Only the PE/COFF format has a Resource Table which is where the manifest
    // gets embedded, so for any other target the manifest file is just ignored.
    if (target.ofmt == .coff) {
        if (options.win32_manifest) |lp| {
            compile.win32_manifest = lp.dupe(graph);
            lp.addStepDependencies(&compile.step);
        }
        if (compile.kind == .lib and compile.linkage != null and compile.linkage.? == .dynamic) {
            // Building a Win32 DLL, check for win32 .def file.
            if (options.win32_module_definition) |lp| {
                compile.win32_module_definition = lp.dupe(graph);
                lp.addStepDependencies(&compile.step);
            }
        }
    }

    if (options.entitlements) |lp| {
        compile.entitlements = lp.dupe(graph);
        lp.addStepDependencies(&compile.step);
    }

    return compile;
}

/// Marks the specified header for installation alongside this artifact.
/// When a module links with this artifact, all headers marked for installation are added to that
/// module's include search path.
pub fn installHeader(cs: *Compile, source: LazyPath, dest_rel_path: []const u8) void {
    const graph = cs.step.owner.graph;
    const arena = graph.arena;
    const installation: HeaderInstallation = .{ .file = .{
        .source = source.dupe(graph),
        .dest_rel_path = graph.dupePath(dest_rel_path),
    } };
    cs.installed_headers.append(arena, installation) catch @panic("OOM");
    cs.addHeaderInstallationToIncludeTree(installation);
    installation.getSource().addStepDependencies(&cs.step);
}

/// Marks headers from the specified directory for installation alongside this artifact.
/// When a module links with this artifact, all headers marked for installation are added to that
/// module's include search path.
pub fn installHeadersDirectory(
    cs: *Compile,
    source: LazyPath,
    dest_rel_path: []const u8,
    options: HeaderInstallation.Directory.Options,
) void {
    const graph = cs.step.owner.graph;
    const arena = graph.arena;
    const installation: HeaderInstallation = .{ .directory = .{
        .source = source.dupe(graph),
        .dest_rel_path = graph.dupePath(dest_rel_path),
        .options = options.dupe(graph),
    } };
    cs.installed_headers.append(arena, installation) catch @panic("OOM");
    cs.addHeaderInstallationToIncludeTree(installation);
    installation.getSource().addStepDependencies(&cs.step);
}

/// Marks the specified config header for installation alongside this artifact.
/// When a module links with this artifact, all headers marked for installation are added to that
/// module's include search path.
pub fn installConfigHeader(cs: *Compile, config_header: *Step.ConfigHeader) void {
    cs.installHeader(config_header.getOutputFile(), config_header.include_path);
}

/// Forwards all headers marked for installation from `lib` to this artifact.
/// When a module links with this artifact, all headers marked for installation are added to that
/// module's include search path.
pub fn installLibraryHeaders(cs: *Compile, lib: *Compile) void {
    assert(lib.kind == .lib);
    const graph = cs.step.owner.graph;
    const arena = graph.arena;
    for (lib.installed_headers.items) |installation| {
        const installation_copy = installation.dupe(graph);
        cs.installed_headers.append(arena, installation_copy) catch @panic("OOM");
        cs.addHeaderInstallationToIncludeTree(installation_copy);
        installation_copy.getSource().addStepDependencies(&cs.step);
    }
}

fn addHeaderInstallationToIncludeTree(cs: *Compile, installation: HeaderInstallation) void {
    if (cs.installed_headers_include_tree) |wf| switch (installation) {
        .file => |file| {
            _ = wf.addCopyFile(file.source, file.dest_rel_path);
        },
        .directory => |dir| {
            _ = wf.addCopyDirectory(dir.source, dir.dest_rel_path, .{
                .exclude_extensions = dir.options.exclude_extensions,
                .include_extensions = dir.options.include_extensions,
            });
        },
    };
}

pub fn getEmittedIncludeTree(cs: *Compile) LazyPath {
    if (cs.installed_headers_include_tree) |wf| return wf.getDirectory();
    const b = cs.step.owner;
    const wf = b.addWriteFiles();
    cs.installed_headers_include_tree = wf;
    for (cs.installed_headers.items) |installation| {
        cs.addHeaderInstallationToIncludeTree(installation);
    }
    // The compile step itself does not need to depend on the write files step,
    // only dependent modules do.
    return wf.getDirectory();
}

pub fn addObjCopy(cs: *Compile, options: Step.ObjCopy.Options) *Step.ObjCopy {
    const b = cs.step.owner;
    var copy = options;
    if (copy.basename == null) {
        if (options.format) |f| {
            copy.basename = b.fmt("{s}.{s}", .{ cs.name, @tagName(f) });
        } else {
            copy.basename = cs.name;
        }
    }
    return b.addObjCopy(cs.getEmittedBin(), copy);
}

pub fn setLinkerScript(compile: *Compile, source: LazyPath) void {
    const graph = compile.step.owner.graph;
    compile.linker_script = source.dupe(graph);
    source.addStepDependencies(&compile.step);
}

pub fn setVersionScript(compile: *Compile, source: LazyPath) void {
    const graph = compile.step.owner.graph;
    compile.version_script = source.dupe(graph);
    source.addStepDependencies(&compile.step);
}

pub fn forceUndefinedSymbol(compile: *Compile, symbol_name: []const u8) void {
    const graph = compile.step.owner.graph;
    const arena = graph.arena;
    compile.force_undefined_symbols.put(arena, graph.dupeString(symbol_name), {}) catch @panic("OOM");
}

/// Returns whether the library, executable, or object depends on a particular system library.
/// Includes transitive dependencies.
pub fn dependsOnSystemLibrary(compile: *Compile, name: []const u8) bool {
    var is_linking_libc = false;
    var is_linking_libcpp = false;

    for (compile.getCompileDependencies(true)) |some_compile| {
        for (some_compile.root_module.getGraph().modules) |mod| {
            for (mod.link_objects.items) |lo| {
                switch (lo) {
                    .system_lib => |lib| if (mem.eql(u8, lib.name, name)) return true,
                    else => {},
                }
            }
            if (mod.link_libc orelse false) is_linking_libc = true;
            if (mod.link_libcpp orelse false) is_linking_libcpp = true;
        }
    }

    const target = compile.rootModuleTarget();

    if (std.zig.target.isLibCLibName(&target, name)) {
        return is_linking_libc;
    }

    if (std.zig.target.isLibCxxLibName(&target, name)) {
        return is_linking_libcpp;
    }

    return false;
}

pub fn isDynamicLibrary(compile: *const Compile) bool {
    return compile.kind == .lib and compile.linkage == .dynamic;
}

pub fn isStaticLibrary(compile: *const Compile) bool {
    return compile.kind == .lib and compile.linkage != .dynamic;
}

pub fn isDll(compile: *Compile) bool {
    return compile.isDynamicLibrary() and compile.rootModuleTarget().os.tag == .windows;
}

pub fn producesPdbFile(compile: *Compile) bool {
    const target = compile.rootModuleTarget();
    // TODO: Is this right? Isn't PDB for *any* PE/COFF file?
    // TODO: just share this logic with the compiler, silly!
    switch (target.os.tag) {
        .windows, .uefi => {},
        else => return false,
    }
    if (target.ofmt == .c) return false;
    if (compile.use_llvm == false) return false;
    if (compile.root_module.strip == true or
        (compile.root_module.strip == null and compile.root_module.optimize == .ReleaseSmall))
    {
        return false;
    }
    return compile.isDynamicLibrary() or compile.kind == .exe or compile.kind == .@"test";
}

pub fn producesCompilerRtDynLib(compile: *Compile) bool {
    if (compile.rootModuleTarget().ofmt != .coff) return false;
    if (compile.bundle_compiler_rt orelse (compile.kind == .exe or compile.isDynamicLibrary()))
        return compile.use_llvm == false;
    return false;
}

pub fn producesImplib(compile: *Compile) bool {
    return compile.isDll();
}

pub fn setVerboseLink(compile: *Compile, value: bool) void {
    compile.verbose_link = value;
}

pub fn setVerboseCC(compile: *Compile, value: bool) void {
    compile.verbose_cc = value;
}

pub fn setLibCFile(compile: *Compile, libc_file: ?LazyPath) void {
    const graph = compile.step.owner.graph;
    if (libc_file) |f| {
        compile.libc_file = f.dupe(graph);
        f.addStepDependencies(&compile.step);
    } else {
        compile.libc_file = null;
    }
}

fn getEmittedFileGeneric(compile: *Compile, output_file: *Configuration.OptionalGeneratedFileIndex) LazyPath {
    if (output_file.unwrap()) |index| return .{ .generated = .{ .index = index } };
    const graph = compile.step.owner.graph;
    const index = graph.addGeneratedFile(&compile.step);
    output_file.* = .init(index);
    return .{ .generated = .{ .index = index } };
}

/// Returns the path to the directory that contains the emitted binary file.
pub fn getEmittedBinDirectory(compile: *Compile) LazyPath {
    _ = compile.getEmittedBin();
    return compile.getEmittedFileGeneric(&compile.emit_directory);
}

/// Returns the path to the generated executable, library or object file.
/// To run an executable built with zig build, use `run`, or create an install step and invoke it.
pub fn getEmittedBin(compile: *Compile) LazyPath {
    return compile.getEmittedFileGeneric(&compile.generated_bin);
}

/// Returns the path to the generated import library.
/// This function can only be called for libraries.
pub fn getEmittedImplib(compile: *Compile) LazyPath {
    assert(compile.kind == .lib);
    return compile.getEmittedFileGeneric(&compile.generated_implib);
}

/// Returns the path to the generated header file.
/// This function can only be called for libraries or objects.
pub fn getEmittedH(compile: *Compile) LazyPath {
    assert(compile.kind != .exe and compile.kind != .@"test");
    return compile.getEmittedFileGeneric(&compile.generated_h);
}

/// Returns the generated PDB file.
/// If the compilation does not produce a PDB file, this causes a FileNotFound error
/// at build time.
pub fn getEmittedPdb(compile: *Compile) LazyPath {
    _ = compile.getEmittedBin();
    return compile.getEmittedFileGeneric(&compile.generated_pdb);
}

/// Returns the path to the generated documentation directory.
pub fn getEmittedDocs(compile: *Compile) LazyPath {
    return compile.getEmittedFileGeneric(&compile.generated_docs);
}

/// Returns the path to the generated assembly code.
pub fn getEmittedAsm(compile: *Compile) LazyPath {
    return compile.getEmittedFileGeneric(&compile.generated_asm);
}

/// Returns the path to the generated LLVM IR.
pub fn getEmittedLlvmIr(compile: *Compile) LazyPath {
    return compile.getEmittedFileGeneric(&compile.generated_llvm_ir);
}

/// Returns the path to the generated LLVM BC.
pub fn getEmittedLlvmBc(compile: *Compile) LazyPath {
    return compile.getEmittedFileGeneric(&compile.generated_llvm_bc);
}

pub fn setExecCmd(compile: *Compile, args: []const ?[]const u8) void {
    const graph = compile.step.owner.graph;
    const arena = graph.arena;
    assert(compile.kind == .@"test");
    const duped_args = arena.alloc(?[]const u8, args.len) catch @panic("OOM");
    for (args, 0..) |arg, i| {
        duped_args[i] = if (arg) |a| graph.dupeString(a) else null;
    }
    compile.exec_cmd_args = duped_args;
}

pub fn rootModuleTarget(c: *Compile) std.Target {
    // The root module is always given a target, so we know this to be non-null.
    return c.root_module.resolved_target.?.result;
}

/// Return the full set of `Step.Compile` which `start` depends on, recursively. `start` itself is
/// always returned as the first element. If `chase_dynamic` is `false`, then dynamic libraries are
/// not included, and their dependencies are not considered; if `chase_dynamic` is `true`, dynamic
/// libraries are treated the same as other linked `Compile`s.
pub fn getCompileDependencies(start: *Compile, chase_dynamic: bool) []const *Compile {
    const arena = start.step.owner.graph.arena;

    var compiles: std.array_hash_map.Auto(*Compile, void) = .empty;
    var next_idx: usize = 0;

    compiles.putNoClobber(arena, start, {}) catch @panic("OOM");

    while (next_idx < compiles.count()) {
        const compile = compiles.keys()[next_idx];
        next_idx += 1;

        for (compile.root_module.getGraph().modules) |mod| {
            for (mod.link_objects.items) |lo| {
                switch (lo) {
                    .other_step => |other_compile| {
                        if (!chase_dynamic and other_compile.isDynamicLibrary()) continue;
                        compiles.put(arena, other_compile, {}) catch @panic("OOM");
                    },
                    else => {},
                }
            }
        }
    }

    return compiles.keys();
}
