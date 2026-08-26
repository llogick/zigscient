const Compile = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const mem = std.mem;
const Configuration = std.Build.Configuration;
const Dir = std.Io.Dir;
const Path = std.Build.Cache.Path;
const Module = std.Build.Configuration.Module;
const Io = std.Io;
const Sha256 = std.crypto.hash.sha2.Sha256;
const assert = std.debug.assert;

const Step = @import("../Step.zig");
const Maker = @import("../../Maker.zig");
const PkgConfig = @import("../PkgConfig.zig");

pub const Info = struct {
    args: std.ArrayList([]const u8) = .empty,
    mods: std.ArrayList(NamePathPair) = .empty,

    pub const NamePathPair = struct {
        name: []const u8,
        path: []const u8,
    };
};

/// Populated when there is compiler process that lives across multiple calls
/// to `make`.
zig_process: ?*Step.ZigProcess = null,
/// Populated by InstallArtifact.
installed_path: ?Path = null,
/// Populated by `make`, used by `Run`.
is_linking_libc: bool = false,

pub fn make(
    compile: *Compile,
    compile_index: Configuration.Step.Index,
    maker: *Maker,
    progress_node: std.Progress.Node,
) Step.ExtendedMakeError!void {
    const graph = maker.graph;
    const gpa = maker.gpa;
    const conf = &maker.scanned_config.configuration;
    const conf_step = compile_index.ptr(conf);
    const conf_comp = conf_step.extended.get(conf.extra).compile;

    var arena_allocator: std.heap.ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    if (maker.dump_compile_step_info) extract_cs_args: {
        try maker.compile_steps_info_mutex.lock(maker.graph.io);
        defer maker.compile_steps_info_mutex.unlock(maker.graph.io);
        const gop = try maker.compile_steps_info.getOrPut(maker.graph.arena, compile_index);
        if (gop.found_existing) break :extract_cs_args;
        gop.key_ptr.* = compile_index;
        gop.value_ptr.* = .{};
        var curated_argv: std.ArrayList([]const u8) = .empty;
        defer curated_argv.deinit(gpa);
        try lowerZigArgs(arena, compile, compile_index, maker, progress_node, &curated_argv, false, true);
        for (curated_argv.items) |arg| {
            try gop.value_ptr.args.append(maker.graph.arena, try maker.graph.arena.dupe(u8, arg));
        }
    }

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);

    try lowerZigArgs(arena, compile, compile_index, maker, progress_node, &argv, false, false);

    const incremental = conf_comp.flags4.incremental.toBool() orelse graph.incremental == true;

    const maybe_output_dir = Step.evalZigProcess(
        compile_index,
        maker,
        argv.items,
        progress_node,
        incremental and (maker.watch or maker.web_server != null),
    ) catch |err| switch (err) {
        error.NeedCompileErrorCheck => {
            try checkCompileErrors(arena, maker, compile_index);
            return;
        },
        else => |e| return e,
    };

    const root_module = conf_comp.root_module.get(conf);
    const target = root_module.resolved_target.get(conf).?.result.get(conf);

    // Update generated files
    if (maybe_output_dir) |output_dir| {
        if (conf_comp.emit_directory.value) |gf| maker.generatedPath(gf).* = output_dir;
        try updateGeneratedFile(maker, arena, &conf_comp, output_dir, &target, conf_comp.generated_bin.value, .bin);
        try updateGeneratedFile(maker, arena, &conf_comp, output_dir, &target, conf_comp.generated_pdb.value, .pdb);
        try updateGeneratedFile(maker, arena, &conf_comp, output_dir, &target, conf_comp.generated_implib.value, .implib);
        try updateGeneratedFile(maker, arena, &conf_comp, output_dir, &target, conf_comp.generated_h.value, .h);
        try updateGeneratedFile(maker, arena, &conf_comp, output_dir, &target, conf_comp.generated_docs.value, .docs);
        try updateGeneratedFile(maker, arena, &conf_comp, output_dir, &target, conf_comp.generated_asm.value, .@"asm");
        try updateGeneratedFile(maker, arena, &conf_comp, output_dir, &target, conf_comp.generated_llvm_ir.value, .llvm_ir);
        try updateGeneratedFile(maker, arena, &conf_comp, output_dir, &target, conf_comp.generated_llvm_bc.value, .llvm_bc);
    }

    if (conf_comp.flags3.kind == .lib and conf_comp.flags2.linkage == .dynamic and
        conf_comp.version.value != null and target.flags.os_tag != .windows)
    {
        if (conf_comp.generated_bin.value) |generated_bin| {
            const full_dest_path = maker.generatedPath(generated_bin).*;
            try maker.installSymLinks(arena, full_dest_path, compile_index, compile_index);
        }
    }
}

fn updateGeneratedFile(
    maker: *Maker,
    arena: Allocator,
    conf_comp: *const Configuration.Step.Compile,
    out_path: std.Build.Cache.Path,
    target: *const Configuration.TargetQuery,
    opt_gf: ?Configuration.GeneratedFileIndex,
    ea: std.zig.EmitArtifact,
) Allocator.Error!void {
    const gf = opt_gf orelse return;
    const graph = maker.graph;
    const conf = &maker.scanned_config.configuration;
    const name = try ea.cacheName(arena, .{
        .root_name = conf_comp.root_name.slice(conf),
        .cpu_arch = target.flags.cpu_arch.unwrap().?,
        .os_tag = target.flags.os_tag.unwrap().?,
        .ofmt = target.flags.object_format.unwrap().?,
        .abi = target.flags.abi.unwrap().?,
        .output_mode = switch (conf_comp.flags3.kind) {
            .lib => .Lib,
            .obj, .test_obj => .Obj,
            .exe, .@"test" => .Exe,
        },
        .link_mode = conf_comp.flags2.linkage.unwrap(),
        .version = if (conf_comp.version.value) |v|
            std.SemanticVersion.parse(v.slice(conf)) catch unreachable
        else
            null,
    });
    maker.generatedPath(gf).* = try out_path.join(graph.arena, name);
}

/// List of importable modules in a compilation's module graph, including
/// the root module. The root module is guaranteed to be first.
const ModuleList = std.array_hash_map.Auto(Configuration.Module.Index, Configuration.String);
/// Keyed on the first key in the module list.
pub const ModuleGraph = std.array_hash_map.Custom(ModuleList, void, ModuleListContext, false);

const ModuleListContext = struct {
    pub fn eql(ctx: @This(), a: ModuleList, b: ModuleList) bool {
        _ = ctx;
        return a.keys()[0] == b.keys()[0];
    }

    pub fn hash(ctx: @This(), key: ModuleList) u32 {
        _ = ctx;
        return std.hash.int(@backingInt(key.keys()[0]));
    }

    const Adapter = struct {
        pub fn eql(ctx: @This(), a: Configuration.Module.Index, b: ModuleList, b_index: usize) bool {
            _ = ctx;
            _ = b_index;
            return a == b.keys()[0];
        }

        pub fn hash(ctx: @This(), key: Configuration.Module.Index) u32 {
            _ = ctx;
            return std.hash.int(@backingInt(key));
        }
    };
};

fn lowerZigArgs(
    arena: Allocator,
    compile: *Compile,
    compile_index: Configuration.Step.Index,
    maker: *Maker,
    progress_node: std.Progress.Node,
    zig_args: *std.ArrayList([]const u8),
    fuzz: bool,
    curate: bool,
) Step.ExtendedMakeError!void {
    const step = maker.stepByIndex(compile_index);
    const graph = maker.graph;
    const gpa = maker.gpa;
    const conf = &maker.scanned_config.configuration;
    const conf_step = compile_index.ptr(conf);
    const conf_comp = conf_step.extended.get(conf.extra).compile;
    const root_module_target = conf_comp.rootModuleTarget(conf);

    try zig_args.append(gpa, graph.zig_exe);

    const cmd = switch (conf_comp.flags3.kind) {
        .lib => "build-lib",
        .exe => "build-exe",
        .obj => "build-obj",
        .@"test" => "test",
        .test_obj => "test-obj",
    };
    try zig_args.append(gpa, cmd);

    if (graph.reference_trace) |some| {
        try zig_args.append(gpa, try arena.print("-freference-trace={d}", .{some}));
    }
    try addFlag(gpa, zig_args, "allow-so-scripts", conf_comp.flags2.allow_so_scripts.toBool() orelse graph.allow_so_scripts);

    try addFlag(gpa, zig_args, "llvm", conf_comp.flags2.use_llvm.toBool());
    try addFlag(gpa, zig_args, "lld", conf_comp.flags2.use_lld.toBool());
    try addFlag(gpa, zig_args, "new-linker", conf_comp.flags2.use_new_linker.toBool());

    const root_module = conf_comp.root_module.get(conf);

    if (root_module.resolved_target.get(conf).?.query.unwrap()) |query| {
        if (query.get(conf).flags.object_format.unwrap()) |ofmt| {
            try zig_args.append(gpa, try arena.print("-ofmt={t}", .{ofmt}));
        }
    }

    switch (conf_comp.flags3.entry) {
        .default => {},
        .disabled => try zig_args.append(gpa, "-fno-entry"),
        .enabled => try zig_args.append(gpa, "-fentry"),
        .symbol_name => {
            const symbol_name = conf_comp.entry.value.?.slice(conf);
            try zig_args.append(gpa, try arena.print("-fentry={s}", .{symbol_name}));
        },
    }

    for (conf_comp.force_undefined_symbols.slice) |symbol_name| {
        try zig_args.appendSlice(gpa, &.{ "--force_undefined", symbol_name.slice(conf) });
    }

    if (conf_comp.stack_size.value) |stack_size| {
        try zig_args.appendSlice(gpa, &.{ "--stack", try arena.print("{d}", .{stack_size}) });
    }

    try addBool(gpa, zig_args, "-ffuzz", fuzz);

    {
        var is_linking_libc = false;
        var is_linking_libcpp = false;

        // Stores system libraries that have already been seen for at least one
        // module, along with any C compiler arguments that need to be passed
        // to the compiler for each module individually as reported by
        // pkg-config.
        var seen_system_libs: std.array_hash_map.Auto(Configuration.String, []const []const u8) = .empty;
        var frameworks: std.array_hash_map.Auto(Configuration.String, Configuration.Module.Framework.Flags) = .empty;
        var module_graph: ModuleGraph = .empty;

        var prev_has_cflags = false;
        var prev_has_rcflags = false;
        var prev_search_strategy: Configuration.SystemLib.SearchStrategy = .paths_first;
        var prev_preferred_link_mode: std.builtin.LinkMode = .dynamic;
        // Track the number of positional arguments so that a nice error can be
        // emitted if there is nothing to link.
        var total_linker_objects: usize = @intFromBool(root_module.root_source_file != .none);

        // Fully recursive iteration including dynamic libraries to detect
        // libc and libc++ linkage.
        for (try getCompileDependencies(arena, &module_graph, conf, compile_index, true)) |some_compile_index| {
            const some_compile = some_compile_index.ptr(conf).extended.get(conf.extra).compile;
            const modules = try getModuleList(arena, &module_graph, some_compile.root_module, conf);
            for (modules.keys()) |mod_index| {
                const mod = mod_index.get(conf);
                is_linking_libc = is_linking_libc or mod.flags2.link_libc == .true;
                is_linking_libcpp = is_linking_libcpp or mod.flags2.link_libcpp == .true;
            }
        }

        var cli_named_modules = try CliNamedModules.init(arena, &module_graph, compile_index, maker);

        // For this loop, don't chase dynamic libraries because their link
        // objects are already linked.
        for (try getCompileDependencies(arena, &module_graph, conf, compile_index, false)) |dep_compile_index| {
            const dep_compile = dep_compile_index.ptr(conf).extended.get(conf.extra).compile;
            const modules = try getModuleList(arena, &module_graph, dep_compile.root_module, conf);
            for (modules.keys()) |mod_index| {
                const mod = mod_index.get(conf);
                // While walking transitive dependencies, if a given link object is
                // already included in a library, it should not redundantly be
                // placed on the linker line of the dependee.
                const my_responsibility = dep_compile_index == compile_index;
                const already_linked = !my_responsibility and dep_compile.isDynamicLibrary();

                // Inherit dependencies on darwin frameworks.
                if (!already_linked) {
                    for (mod.frameworks.slice) |framework| {
                        try frameworks.put(arena, framework.name, framework.flags);
                    }
                }

                // Inherit dependencies on system libraries and static libraries.
                for (0..mod.link_objects.len) |lo_i| switch (mod.link_objects.get(conf.extra, lo_i)) {
                    .static_path => |static_path| {
                        if (my_responsibility) {
                            try zig_args.append(gpa, try maker.resolveLazyPathIndexAbs(arena, static_path, compile_index));
                            total_linker_objects += 1;
                        }
                    },
                    .system_lib => |system_lib_index| {
                        const system_lib = system_lib_index.get(conf);
                        const system_lib_name = system_lib.name.slice(conf);
                        const system_lib_gop = try seen_system_libs.getOrPut(arena, system_lib.name);
                        if (system_lib_gop.found_existing) {
                            try zig_args.appendSlice(gpa, system_lib_gop.value_ptr.*);
                            continue;
                        } else {
                            system_lib_gop.value_ptr.* = &.{};
                        }

                        if (already_linked)
                            continue;

                        if ((system_lib.flags.search_strategy != prev_search_strategy or
                            system_lib.flags.preferred_link_mode != prev_preferred_link_mode) and
                            conf_comp.flags2.linkage != .static)
                        {
                            try zig_args.ensureUnusedCapacity(gpa, 1);
                            switch (system_lib.flags.search_strategy) {
                                .no_fallback => switch (system_lib.flags.preferred_link_mode) {
                                    .dynamic => zig_args.appendAssumeCapacity("-search_dylibs_only"),
                                    .static => zig_args.appendAssumeCapacity("-search_static_only"),
                                },
                                .paths_first => switch (system_lib.flags.preferred_link_mode) {
                                    .dynamic => zig_args.appendAssumeCapacity("-search_paths_first"),
                                    .static => zig_args.appendAssumeCapacity("-search_paths_first_static"),
                                },
                                .mode_first => switch (system_lib.flags.preferred_link_mode) {
                                    .dynamic => zig_args.appendAssumeCapacity("-search_dylibs_first"),
                                    .static => zig_args.appendAssumeCapacity("-search_static_first"),
                                },
                            }
                            prev_search_strategy = system_lib.flags.search_strategy;
                            prev_preferred_link_mode = system_lib.flags.preferred_link_mode;
                        }

                        const prefix: []const u8 = prefix: {
                            if (system_lib.flags.needed) break :prefix "-needed-l";
                            if (system_lib.flags.weak) break :prefix "-weak-l";
                            break :prefix "-l";
                        };
                        l: {
                            pc: {
                                const force = switch (system_lib.flags.use_pkg_config) {
                                    .no => break :pc,
                                    .yes => false,
                                    .force => true,
                                };

                                const pkg_conf_node = progress_node.start("pkg-config", 0);
                                defer pkg_conf_node.end();

                                if (PkgConfig.run(maker, step, arena, pkg_conf_node, system_lib_name, force)) |pc| {
                                    try zig_args.appendSlice(gpa, pc.cflags);
                                    try zig_args.appendSlice(gpa, pc.libs);
                                    try seen_system_libs.put(arena, system_lib.name, pc.cflags);
                                    break :l;
                                } else |err| switch (err) {
                                    error.PkgConfigUnavailable,
                                    error.PackageNotFound,
                                    => {
                                        // pkg-config failed, so fall back to linking the library by name directly.
                                        assert(!force);
                                        break :pc;
                                    },
                                    else => |e| return e,
                                }
                            }
                            try zig_args.append(gpa, try arena.print("{s}{s}", .{
                                prefix, system_lib_name,
                            }));
                        }
                    },
                    .other_step => |other_step_index| {
                        const other = other_step_index.ptr(conf);
                        const other_compile = other.extended.get(conf.extra).compile;
                        switch (other_compile.flags3.kind) {
                            .exe => return step.fail(maker, "cannot link with an executable build artifact", .{}),
                            .@"test" => return step.fail(maker, "cannot link with a test", .{}),
                            .obj, .test_obj => {
                                const included_in_lib_or_obj = switch (dep_compile.flags3.kind) {
                                    .lib, .obj, .test_obj => !my_responsibility,
                                    else => false,
                                };
                                if (!already_linked and !included_in_lib_or_obj) {
                                    try zig_args.append(gpa, try maker.resolveLazyPathAbs(
                                        arena,
                                        .{ .generated = .{ .index = other_compile.generated_bin.value.? } },
                                        compile_index,
                                    ));
                                    total_linker_objects += 1;
                                }
                            },
                            .lib => l: {
                                const other_produces_implib = other_compile.producesImplib(conf);
                                const other_is_static = other_produces_implib or other_compile.isStaticLibrary();

                                if (conf_comp.isStaticLibrary() and other_is_static) {
                                    // Avoid putting a static library inside a static library.
                                    break :l;
                                }

                                // For DLLs, we must link against the implib.
                                // For everything else, we directly link
                                // against the library file.
                                const full_path_lib = try maker.resolveLazyPathAbs(
                                    arena,
                                    .{ .generated = .{
                                        .index = if (other_produces_implib)
                                            other_compile.generated_implib.value.?
                                        else
                                            other_compile.generated_bin.value.?,
                                    } },
                                    compile_index,
                                );

                                try zig_args.append(gpa, full_path_lib);
                                total_linker_objects += 1;

                                if (other_compile.flags2.linkage == .dynamic and
                                    root_module_target.flags.os_tag != .windows)
                                {
                                    if (Dir.path.dirname(full_path_lib)) |dirname| {
                                        try zig_args.appendSlice(gpa, &.{ "-rpath", dirname });
                                    }
                                }
                            },
                        }
                    },
                    .assembly_file => |asm_file| l: {
                        if (!my_responsibility or curate) break :l;

                        if (prev_has_cflags) {
                            try zig_args.appendSlice(gpa, &.{ "-cflags", "--" });
                            prev_has_cflags = false;
                        }
                        try zig_args.append(gpa, try maker.resolveLazyPathIndexAbs(arena, asm_file, compile_index));
                        total_linker_objects += 1;
                    },

                    .c_source_file => |c_source_file_index| l: {
                        if (!my_responsibility or curate) break :l;

                        const c_source_file = c_source_file_index.get(conf);

                        if (prev_has_cflags or c_source_file.args.slice.len != 0) {
                            try zig_args.ensureUnusedCapacity(gpa, 2 + c_source_file.args.slice.len);
                            zig_args.appendAssumeCapacity("-cflags");
                            for (c_source_file.args.slice) |arg| {
                                zig_args.appendAssumeCapacity(arg.slice(conf));
                            }
                            zig_args.appendAssumeCapacity("--");
                        }
                        prev_has_cflags = (c_source_file.args.slice.len != 0);

                        if (c_source_file.flags.lang.get()) |lang|
                            (try zig_args.addManyAsArray(gpa, 2)).* = .{ "-x", lang.clangIdentifier() };

                        try zig_args.append(gpa, try maker.resolveLazyPathIndexAbs(arena, c_source_file.file, compile_index));

                        if (c_source_file.flags.lang != .default)
                            (try zig_args.addManyAsArray(gpa, 2)).* = .{ "-x", "none" };

                        total_linker_objects += 1;
                    },

                    .c_source_files => |c_source_files_index| l: {
                        if (!my_responsibility or curate) break :l;

                        const c_source_files = c_source_files_index.get(conf);

                        if (prev_has_cflags or c_source_files.args.slice.len != 0) {
                            try zig_args.ensureUnusedCapacity(gpa, 2 + c_source_files.args.slice.len);
                            zig_args.appendAssumeCapacity("-cflags");
                            for (c_source_files.args.slice) |arg| {
                                zig_args.appendAssumeCapacity(arg.slice(conf));
                            }
                            zig_args.appendAssumeCapacity("--");
                        }
                        prev_has_cflags = (c_source_files.args.slice.len != 0);

                        if (c_source_files.flags.lang.get()) |lang|
                            (try zig_args.addManyAsArray(gpa, 2)).* = .{ "-x", lang.clangIdentifier() };

                        const root_path = try maker.resolveLazyPathIndexAbs(arena, c_source_files.root, compile_index);
                        try zig_args.ensureUnusedCapacity(gpa, c_source_files.sub_paths.slice.len);
                        for (c_source_files.sub_paths.slice) |sub_path| {
                            zig_args.appendAssumeCapacity(try Dir.path.join(arena, &.{
                                root_path, sub_path.slice(conf),
                            }));
                        }

                        if (c_source_files.flags.lang != .default)
                            (try zig_args.addManyAsArray(gpa, 2)).* = .{ "-x", "none" };

                        total_linker_objects += c_source_files.sub_paths.slice.len;
                    },

                    .win32_resource_file => |rc_source_file_index| l: {
                        if (!my_responsibility or curate) break :l;

                        const rc_source_file = rc_source_file_index.get(conf);

                        if (rc_source_file.args.slice.len == 0 and rc_source_file.include_paths.slice.len == 0) {
                            if (prev_has_rcflags) {
                                (try zig_args.addManyAsArray(gpa, 2)).* = .{ "-rcflags", "--" };
                                prev_has_rcflags = false;
                            }
                        } else {
                            try zig_args.ensureUnusedCapacity(gpa, 1 + rc_source_file.args.slice.len);
                            zig_args.appendAssumeCapacity("-rcflags");
                            for (rc_source_file.args.slice) |arg| {
                                zig_args.appendAssumeCapacity(arg.slice(conf));
                            }
                            try zig_args.ensureUnusedCapacity(gpa, 1 + 2 * rc_source_file.include_paths.slice.len);
                            for (rc_source_file.include_paths.slice) |include_path| {
                                zig_args.appendAssumeCapacity("/I");
                                zig_args.appendAssumeCapacity(try maker.resolveLazyPathIndexAbs(arena, include_path, compile_index));
                            }
                            zig_args.appendAssumeCapacity("--");
                            prev_has_rcflags = true;
                        }
                        try zig_args.append(gpa, try maker.resolveLazyPathIndexAbs(arena, rc_source_file.file, compile_index));
                        total_linker_objects += 1;
                    },
                };

                // We need to emit the --mod argument here so that the above link objects
                // have the correct parent module, but only if the module is part of
                // this compilation.
                if (!my_responsibility) continue;
                if (cli_named_modules.modules.getIndex(mod_index)) |module_cli_index| {
                    const module_cli_name = cli_named_modules.names.keys()[module_cli_index];
                    const module_index = cli_named_modules.modules.keys()[module_cli_index];
                    try appendModuleFlags(arena, module_index, zig_args, compile_index, maker);

                    const imports = mod.import_table.get(conf).imports.mal;

                    // --dep arguments
                    try zig_args.ensureUnusedCapacity(gpa, imports.len * 2);
                    for (imports.items(.name), imports.items(.module)) |name, import| {
                        const import_index = cli_named_modules.modules.getIndex(import).?;
                        const import_cli_name = cli_named_modules.names.keys()[import_index];
                        zig_args.appendAssumeCapacity("--dep");
                        const name_slice = name.slice(conf);
                        if (mem.eql(u8, import_cli_name, name_slice)) {
                            zig_args.appendAssumeCapacity(import_cli_name);
                        } else {
                            zig_args.appendAssumeCapacity(try arena.print("{s}={s}", .{
                                name_slice, import_cli_name,
                            }));
                        }
                    }

                    // When the CLI sees a -M argument, it determines whether it
                    // implies the existence of a Zig compilation unit based on
                    // whether there is a root source file. If there is no root
                    // source file, then this is not a zig compilation unit - it is
                    // perhaps a set of linker objects, or C source files instead.
                    // Linker objects are added to the CLI globally, while C source
                    // files must have a module parent.
                    try zig_args.ensureUnusedCapacity(gpa, 1);
                    if (mod.root_source_file.unwrap()) |lp| {
                        const src = try maker.resolveLazyPathIndexAbs(arena, lp, compile_index);
                        zig_args.appendAssumeCapacity(try arena.print("-M{s}={s}", .{ module_cli_name, src }));
                        if (curate) blk: {
                            var info = maker.compile_steps_info.getPtr(compile_index) orelse break :blk;
                            if (info.args.items.len == 0) {
                                const cwd = maker.graph.build_root_directory.path orelse std.process.currentPathAlloc(maker.graph.io, arena) catch |err| switch (err) {
                                    error.Canceled => |e| return e,
                                    else => break :blk,
                                };
                                try info.mods.append(maker.graph.arena, .{
                                    .name = try maker.graph.arena.dupe(u8, module_cli_name),
                                    .path = Dir.path.resolve(maker.graph.arena, &.{ cwd, src }) catch src,
                                });
                            }
                        }
                    } else if (moduleNeedsCliArg(&mod, conf)) {
                        zig_args.appendAssumeCapacity(try arena.print("-M{s}", .{module_cli_name}));
                    }
                }
            }
        }

        if (total_linker_objects == 0 and !curate) {
            return step.fail(maker, "the linker needs one or more objects to link", .{});
        }

        for (frameworks.keys(), frameworks.values()) |name, info| {
            try zig_args.ensureUnusedCapacity(gpa, 2);
            if (info.needed) {
                zig_args.appendAssumeCapacity("-needed_framework");
            } else if (info.weak) {
                zig_args.appendAssumeCapacity("-weak_framework");
            } else {
                zig_args.appendAssumeCapacity("-framework");
            }
            zig_args.appendAssumeCapacity(name.slice(conf));
        }

        try zig_args.ensureUnusedCapacity(gpa, 2);
        if (is_linking_libcpp) zig_args.appendAssumeCapacity("-lc++");
        if (is_linking_libc) zig_args.appendAssumeCapacity("-lc");

        compile.is_linking_libc = is_linking_libc;
    }

    if (conf_comp.win32_manifest.value) |manifest_file| {
        try zig_args.append(gpa, try maker.resolveLazyPathIndexAbs(arena, manifest_file, compile_index));
    }

    if (conf_comp.win32_module_definition.value) |module_file| {
        try zig_args.append(gpa, try maker.resolveLazyPathIndexAbs(arena, module_file, compile_index));
    }

    if (conf_comp.image_base.value) |image_base| {
        (try zig_args.addManyAsArray(gpa, 2)).* = .{
            "--image-base", try arena.print("0x{x}", .{image_base}),
        };
    }

    for (conf_comp.filters.slice) |filter| {
        (try zig_args.addManyAsArray(gpa, 2)).* = .{ "--test-filter", filter.slice(conf) };
    }

    switch (conf_comp.test_runner.u) {
        .default => {},
        .simple, .server => |lp| (try zig_args.addManyAsArray(gpa, 2)).* = .{
            "--test-runner", try maker.resolveLazyPathIndexAbs(arena, lp, compile_index),
        },
    }

    for (graph.debug_log_scopes.items) |log_scope| {
        (try zig_args.addManyAsArray(gpa, 2)).* = .{ "--debug-log", log_scope };
    }

    try addBool(gpa, zig_args, "--debug-compile-errors", graph.debug_compile_errors);
    try addBool(gpa, zig_args, "--debug-incremental", graph.debug_incremental);
    try addBool(gpa, zig_args, "--verbose-air", graph.verbose_air);
    try addBool(gpa, zig_args, "--verbose-llvm-ir", graph.verbose_llvm_ir);
    try addBool(gpa, zig_args, "--verbose-link", graph.verbose_link or conf_comp.flags.verbose_link);
    try addBool(gpa, zig_args, "--verbose-cc", graph.verbose_cc or conf_comp.flags.verbose_cc);
    try addBool(gpa, zig_args, "--verbose-llvm-cpu-features", graph.verbose_llvm_cpu_features);
    try addBool(gpa, zig_args, "--time-report", graph.time_report);

    if (conf_comp.generated_bin.value == null) try zig_args.append(gpa, "-fno-emit-bin");
    if (conf_comp.generated_asm.value != null) try zig_args.append(gpa, "-femit-asm");
    if (conf_comp.generated_docs.value != null) try zig_args.append(gpa, "-femit-docs");
    if (conf_comp.generated_implib.value != null) try zig_args.append(gpa, "-femit-implib");
    if (conf_comp.generated_llvm_bc.value != null) try zig_args.append(gpa, "-femit-llvm-bc");
    if (conf_comp.generated_llvm_ir.value != null) try zig_args.append(gpa, "-femit-llvm-ir");
    if (conf_comp.generated_h.value != null) try zig_args.append(gpa, "-femit-h");

    try addFlag(gpa, zig_args, "formatted-panics", conf_comp.flags2.formatted_panics.toBool());

    switch (conf_comp.flags3.compress_debug_sections) {
        .none => {},
        .zlib => try zig_args.append(gpa, "--compress-debug-sections=zlib"),
        .zstd => try zig_args.append(gpa, "--compress-debug-sections=zstd"),
    }

    try addBool(gpa, zig_args, "--eh-frame-hdr", conf_comp.flags.link_eh_frame_hdr);
    try addBool(gpa, zig_args, "--emit-relocs", conf_comp.flags.link_emit_relocs);
    try addBool(gpa, zig_args, "-ffunction-sections", conf_comp.flags.link_function_sections);
    try addBool(gpa, zig_args, "-fdata-sections", conf_comp.flags.link_data_sections);

    if (conf_comp.flags2.link_gc_sections.toBool()) |x|
        try zig_args.append(gpa, if (x) "--gc-sections" else "--no-gc-sections");

    if (!conf_comp.flags.linker_dynamicbase)
        try zig_args.append(gpa, "--no-dynamicbase");

    try addFlag(gpa, zig_args, "allow-shlib-undefined", conf_comp.flags2.linker_allow_shlib_undefined.toBool());
    if (conf_comp.flags.link_z_notext) (try zig_args.addManyAsArray(gpa, 2)).* = .{ "-z", "notext" };
    if (!conf_comp.flags.link_z_relro) (try zig_args.addManyAsArray(gpa, 2)).* = .{ "-z", "norelro" };
    if (conf_comp.flags.link_z_lazy) (try zig_args.addManyAsArray(gpa, 2)).* = .{ "-z", "lazy" };
    if (conf_comp.link_z_common_page_size.value) |size| (try zig_args.addManyAsArray(gpa, 2)).* = .{
        "-z", try arena.print("common-page-size={d}", .{size}),
    };
    if (conf_comp.link_z_max_page_size.value) |size| (try zig_args.addManyAsArray(gpa, 2)).* = .{
        "-z", try arena.print("max-page-size={d}", .{size}),
    };
    if (conf_comp.flags.link_z_defs) (try zig_args.addManyAsArray(gpa, 2)).* = .{ "-z", "defs" };

    try zig_args.ensureUnusedCapacity(gpa, 2);
    if (conf_comp.libc_file.value) |libc_file| {
        zig_args.appendAssumeCapacity("--libc");
        zig_args.appendAssumeCapacity(try maker.resolveLazyPathIndexAbs(arena, libc_file, compile_index));
    } else if (graph.libc_file) |libc_file| {
        zig_args.appendAssumeCapacity("--libc");
        zig_args.appendAssumeCapacity(libc_file);
    }

    (try zig_args.addManyAsArray(gpa, 6)).* = .{
        "--cache-dir",        graph.local_cache_root.path orelse ".",
        "--global-cache-dir", graph.global_cache_root.path orelse ".",
        "--build-root",       graph.build_root_directory.path orelse ".",
    };

    try zig_args.ensureUnusedCapacity(gpa, 1);
    if (graph.debug_compiler_runtime_libs) |mode| switch (mode) {
        .debug => zig_args.appendAssumeCapacity("--debug-rt"),
        else => zig_args.appendAssumeCapacity(try arena.print("--debug-rt={t}", .{mode})),
    };

    {
        try zig_args.ensureUnusedCapacity(gpa, 7);

        zig_args.addManyAsArrayAssumeCapacity(2).* = .{ "--name", conf_comp.root_name.slice(conf) };

        switch (conf_comp.flags2.linkage) {
            .dynamic => zig_args.appendAssumeCapacity("-dynamic"),
            .static => zig_args.appendAssumeCapacity("-static"),
            .default => {},
        }

        if (conf_comp.flags3.kind == .lib and conf_comp.flags2.linkage == .dynamic) {
            if (conf_comp.version.value) |version| zig_args.addManyAsArrayAssumeCapacity(2).* = .{
                "--version", version.slice(conf),
            };

            const os_tag = root_module_target.flags.os_tag.unwrap().?;
            if (os_tag.isDarwin()) {
                const abi = root_module_target.flags.abi.unwrap().?;
                zig_args.addManyAsArrayAssumeCapacity(2).* = .{
                    "-install_name",
                    if (conf_comp.install_name.value) |s| s.slice(conf) else try arena.print("@rpath/{s}{s}{s}", .{
                        os_tag.libPrefix(abi), conf_comp.root_name.slice(conf), os_tag.dynamicLibSuffix(),
                    }),
                };
            }
        }
    }

    if (conf_comp.entitlements.value) |entitlements| {
        (try zig_args.addManyAsArray(gpa, 2)).* = .{
            "--entitlements", try maker.resolveLazyPathIndexAbs(arena, entitlements, compile_index),
        };
    }
    if (conf_comp.pagezero_size.value) |pagezero_size| {
        (try zig_args.addManyAsArray(gpa, 2)).* = .{
            "-pagezero_size", try arena.print("{x}", .{pagezero_size}),
        };
    }
    if (conf_comp.headerpad_size.value) |headerpad_size| {
        (try zig_args.addManyAsArray(gpa, 2)).* = .{
            "-headerpad", try arena.print("{x}", .{headerpad_size}),
        };
    }
    try addBool(gpa, zig_args, "-headerpad_max_install_names", conf_comp.flags.headerpad_max_install_names);
    try addBool(gpa, zig_args, "-dead_strip_dylibs", conf_comp.flags.dead_strip_dylibs);
    try addBool(gpa, zig_args, "-ObjC", conf_comp.flags.force_load_objc);
    try addBool(gpa, zig_args, "--discard-all", conf_comp.flags.discard_local_symbols);

    try addFlag(gpa, zig_args, "compiler-rt", conf_comp.flags2.bundle_compiler_rt.toBool());
    try addFlag(gpa, zig_args, "ubsan-rt", conf_comp.flags2.bundle_ubsan_rt.toBool());
    try addFlag(gpa, zig_args, "dll-export-fns", conf_comp.flags2.dll_export_fns.toBool());

    try addBool(gpa, zig_args, "-rdynamic", conf_comp.flags.rdynamic);
    try addBool(gpa, zig_args, "--import-memory", conf_comp.flags.import_memory);
    try addBool(gpa, zig_args, "--export-memory", conf_comp.flags.export_memory);
    try addBool(gpa, zig_args, "--import-symbols", conf_comp.flags.import_symbols);
    try addBool(gpa, zig_args, "--import-table", conf_comp.flags.import_table);
    try addBool(gpa, zig_args, "--export-table", conf_comp.flags.export_table);
    try addBool(gpa, zig_args, "--growable-table", conf_comp.flags.growable_table);
    try addBool(gpa, zig_args, "--shared-memory", conf_comp.flags.shared_memory);

    {
        try zig_args.ensureUnusedCapacity(gpa, 4);
        if (conf_comp.initial_memory.value) |initial_memory| {
            zig_args.appendAssumeCapacity(try arena.print("--initial-memory={d}", .{initial_memory}));
        }
        if (conf_comp.max_memory.value) |max_memory| {
            zig_args.appendAssumeCapacity(try arena.print("--max-memory={d}", .{max_memory}));
        }
        if (conf_comp.global_base.value) |global_base| {
            zig_args.appendAssumeCapacity(try arena.print("--global-base={d}", .{global_base}));
        }
        switch (conf_comp.flags3.wasi_exec_model) {
            .default => {},
            .command => zig_args.appendAssumeCapacity("-mexec-model=command"),
            .reactor => zig_args.appendAssumeCapacity("-mexec-model=reactor"),
        }
    }

    if (conf_comp.linker_script.value) |linker_script| (try zig_args.addManyAsArray(gpa, 2)).* = .{
        "--script", try maker.resolveLazyPathIndexAbs(arena, linker_script, compile_index),
    };
    if (conf_comp.version_script.value) |version_script| (try zig_args.addManyAsArray(gpa, 2)).* = .{
        "--version-script", try maker.resolveLazyPathIndexAbs(arena, version_script, compile_index),
    };
    if (conf_comp.flags2.linker_allow_undefined_version.toBool()) |x| {
        try zig_args.append(gpa, if (x) "--undefined-version" else "--no-undefined-version");
    }

    if (conf_comp.flags2.linker_enable_new_dtags.toBool()) |enabled| {
        try zig_args.append(gpa, if (enabled) "--enable-new-dtags" else "--disable-new-dtags");
    }

    if (graph.sysroot) |sysroot| try zig_args.appendSlice(gpa, &.{ "--sysroot", sysroot });

    // -I and -L arguments that appear after the last --mod argument apply to all modules.
    const cwd: Io.Dir = .cwd();
    const io = graph.io;

    for (graph.search_prefixes.items) |search_prefix| {
        var prefix_dir = cwd.openDir(io, search_prefix, .{}) catch |err| {
            return step.fail(maker, "unable to open prefix directory {q}: {t}", .{ search_prefix, err });
        };
        defer prefix_dir.close(io);

        // Avoid passing -L and -I flags for nonexistent directories.
        // This prevents a warning, that should probably be upgraded to an error in Zig's
        // CLI parsing code, when the linker sees an -L directory that does not exist.

        if (prefix_dir.access(io, "lib", .{})) |_| {
            try zig_args.appendSlice(gpa, &.{
                "-L", try Dir.path.join(arena, &.{ search_prefix, "lib" }),
            });
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => |e| return step.fail(maker, "unable to access {s}/lib directory: {t}", .{ search_prefix, e }),
        }

        if (prefix_dir.access(io, "include", .{})) |_| {
            try zig_args.appendSlice(gpa, &.{
                "-I", try Dir.path.join(arena, &.{ search_prefix, "include" }),
            });
        } else |err| switch (err) {
            error.FileNotFound => {},
            else => |e| return step.fail(maker, "unable to access {s}/include directory: {t}", .{ search_prefix, e }),
        }
    }

    if (!curate and conf_comp.flags3.rc_includes != .any) (try zig_args.addManyAsArray(gpa, 2)).* = .{
        "-rcincludes", @tagName(conf_comp.flags3.rc_includes),
    };

    try addFlag(gpa, zig_args, "each-lib-rpath", conf_comp.flags2.each_lib_rpath.toBool());

    if (conf_comp.flags3.build_id.unwrap(conf_comp.build_id.value, conf) orelse graph.build_id) |build_id| {
        try zig_args.append(gpa, switch (build_id) {
            .hexstring => |hs| try arena.print("--build-id=0x{x}", .{hs.toSlice()}),
            .none, .fast, .uuid, .sha1, .md5 => try arena.print("--build-id={t}", .{build_id}),
        });
    }

    const opt_zig_lib_dir: ?[]const u8 = if (conf_comp.zig_lib_dir.value) |dir|
        try maker.resolveLazyPathIndexAbs(arena, dir, compile_index)
    else if (graph.zig_lib_directory.path) |_|
        try arena.print("{f}", .{graph.zig_lib_directory})
    else
        null;

    if (opt_zig_lib_dir) |zig_lib_dir| (try zig_args.addManyAsArray(gpa, 2)).* = .{
        "--zig-lib-dir", zig_lib_dir,
    };

    try addFlag(gpa, zig_args, "PIE", conf_comp.flags2.pie.toBool());

    try zig_args.ensureUnusedCapacity(gpa, 1);
    switch (conf_comp.flags3.lto) {
        .full => zig_args.appendAssumeCapacity("-flto=full"),
        .thin => zig_args.appendAssumeCapacity("-flto=thin"),
        .none => zig_args.appendAssumeCapacity("-fno-lto"),
        .default => {},
    }

    try addFlag(gpa, zig_args, "sanitize-coverage-trace-pc-guard", conf_comp.flags2.sanitize_coverage_trace_pc_guard.toBool());

    switch (conf_comp.flags3.subsystem) {
        .default => {},
        else => |t| (try zig_args.addManyAsArray(gpa, 2)).* = .{ "--subsystem", @tagName(t) },
    }

    try addBool(gpa, zig_args, "-municode", conf_comp.flags.mingw_unicode_entry_point);

    if (conf_comp.error_limit.value orelse graph.error_limit) |err_limit| (try zig_args.addManyAsArray(gpa, 2)).* = .{
        "--error-limit", try arena.print("{d}", .{err_limit}),
    };

    try addFlag(gpa, zig_args, "incremental", conf_comp.flags4.incremental.toBool() orelse graph.incremental);

    try zig_args.append(gpa, "--listen=-");

    // Windows has an argument length limit of 32,766 characters, macOS 262,144 and Linux
    // 2,097,152. If our args exceed 30 KiB, we instead write them to a "response file" and
    // pass that to zig, e.g. via 'zig build-lib @args.rsp'
    // See @file syntax here: https://gcc.gnu.org/onlinedocs/gcc/Overall-Options.html
    var args_length: usize = 0;
    for (zig_args.items) |arg| {
        args_length += arg.len + 1; // +1 to account for null terminator
    }
    if (args_length >= 30 * 1024) {
        const local_cache_root = graph.local_cache_root;
        const args_path: Path = .{ .root_dir = local_cache_root, .sub_path = "args" };
        args_path.root_dir.handle.createDirPath(io, args_path.sub_path) catch |err|
            return step.fail(maker, "failed creating directory {f}: {t}", .{ args_path, err });

        const args_to_escape = zig_args.items[2..];
        var escaped_args = try std.array_list.Managed([]const u8).initCapacity(arena, args_to_escape.len);
        arg_blk: for (args_to_escape) |arg| {
            for (arg, 0..) |c, arg_idx| {
                if (c == '\\' or c == '"') {
                    // Slow path for arguments that need to be escaped. We'll need to allocate and copy
                    var escaped: std.ArrayList(u8) = .empty;
                    try escaped.ensureTotalCapacityPrecise(arena, arg.len + 1);
                    try escaped.appendSlice(arena, arg[0..arg_idx]);
                    for (arg[arg_idx..]) |to_escape| {
                        if (to_escape == '\\' or to_escape == '"') try escaped.append(arena, '\\');
                        try escaped.append(arena, to_escape);
                    }
                    escaped_args.appendAssumeCapacity(escaped.items);
                    continue :arg_blk;
                }
            }
            escaped_args.appendAssumeCapacity(arg); // no escaping needed so just use original argument
        }

        // Write the args to zig-cache/args/<SHA256 hash of args> to avoid conflicts with
        // other zig build commands running in parallel.
        const partially_quoted = try mem.join(arena, "\" \"", escaped_args.items);
        const args = try mem.concat(arena, u8, &[_][]const u8{ "\"", partially_quoted, "\"" });

        var args_hash: [Sha256.digest_length]u8 = undefined;
        Sha256.hash(args, &args_hash, .{});
        var args_hex_hash: [Sha256.digest_length * 2]u8 = undefined;
        _ = std.fmt.bufPrint(&args_hex_hash, "{x}", .{&args_hash}) catch unreachable;

        const args_file = "args" ++ Dir.path.sep_str ++ args_hex_hash;
        local_cache_root.handle.access(io, args_file, .{}) catch {
            var af = local_cache_root.handle.createFileAtomic(io, args_file, .{
                .replace = false,
                .make_path = true,
            }) catch |e| return step.fail(maker, "failed creating tmp args file {f}{s}: {t}", .{
                local_cache_root, args_file, e,
            });
            defer af.deinit(io);

            af.file.writeStreamingAll(io, args) catch |e| {
                return step.fail(maker, "failed writing args data to tmp file {f}{s}: {t}", .{
                    local_cache_root, args_file, e,
                });
            };
            // Note we can't clean up this file, not even after build
            // success, because that might interfere with another build
            // process that needs the same file.
            af.link(io) catch |e| switch (e) {
                error.PathAlreadyExists => {
                    // The args file was created by another concurrent build process.
                },
                else => |other_err| return step.fail(maker, "failed linking tmp file {f}{s}: {t}", .{
                    local_cache_root, args_file, other_err,
                }),
            };
        };

        const resolved_args_file = try mem.concat(arena, u8, &.{
            "@", try local_cache_root.join(arena, &.{args_file}),
        });

        zig_args.shrinkRetainingCapacity(2);
        try zig_args.append(gpa, resolved_args_file);
    }
}

pub fn rebuildInFuzzMode(
    compile: *Compile,
    maker: *Maker,
    compile_index: Configuration.Step.Index,
    progress_node: std.Progress.Node,
) !Path {
    const gpa = maker.gpa;
    const step = maker.stepByIndex(compile_index);

    var arena_allocator: std.heap.ArenaAllocator = .init(gpa);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    step.result_error_msgs.clearRetainingCapacity();
    step.clearResultStderr(gpa);
    step.clearErrorBundle(gpa);
    step.result_error_bundle.deinit(gpa);
    step.result_error_bundle = std.zig.ErrorBundle.empty;

    step.clearFailedCommand(gpa);

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(gpa);

    try lowerZigArgs(arena, compile, compile_index, maker, progress_node, &argv, true, false);
    const maybe_output_bin_path = try Step.evalZigProcess(compile_index, maker, argv.items, progress_node, false);
    return maybe_output_bin_path.?;
}

fn addBool(gpa: Allocator, args: *std.ArrayList([]const u8), arg: []const u8, opt: bool) !void {
    if (opt) try args.append(gpa, arg);
}

fn addFlag(gpa: Allocator, args: *std.ArrayList([]const u8), comptime name: []const u8, opt: ?bool) !void {
    const cond = opt orelse return;
    try args.append(gpa, if (cond) "-f" ++ name else "-fno-" ++ name);
}

fn addArchFlag(gpa: Allocator, args: *std.ArrayList([]const u8), comptime name: []const u8, opt: ?bool) !void {
    const cond = opt orelse return;
    try args.append(gpa, if (cond) "-m" ++ name else "-mno-" ++ name);
}

fn checkCompileErrors(arena: Allocator, maker: *Maker, step_index: Configuration.Step.Index) Step.ExtendedMakeError!void {
    const step = maker.stepByIndex(step_index);
    const conf = &maker.scanned_config.configuration;
    const conf_step = step_index.ptr(conf);
    const conf_comp = conf_step.extended.get(conf.extra).compile;

    // Clear this field so that it does not get printed by the build runner.
    var actual_eb = step.result_error_bundle;
    step.result_error_bundle = .empty;
    defer actual_eb.deinit(maker.gpa);

    const actual_errors = ae: {
        var aw: std.Io.Writer.Allocating = .init(arena);
        defer aw.deinit();
        actual_eb.renderToWriter(.{
            .include_reference_trace = false,
            .include_source_line = false,
        }, &aw.writer) catch |err| switch (err) {
            error.WriteFailed => return error.OutOfMemory,
        };
        break :ae try aw.toOwnedSlice();
    };

    // Render the expected lines into a string that we can compare verbatim.
    var expected_generated: std.ArrayList(u8) = .empty;
    var actual_line_it = mem.splitScalar(u8, actual_errors, '\n');

    switch (conf_comp.expect_errors.u) {
        .none => unreachable,
        .starts_with => |expect_starts_with_string| {
            const expect_starts_with = expect_starts_with_string.slice(conf);
            if (mem.startsWith(u8, actual_errors, expect_starts_with)) return;
            return step.fail(maker,
                \\
                \\========= should start with: ============
                \\{s}
                \\========= but not found: ================
                \\{s}
                \\=========================================
            , .{ expect_starts_with, actual_errors });
        },
        .contains => |expect_line_string| {
            const expect_line = expect_line_string.slice(conf);
            while (actual_line_it.next()) |actual_line| {
                if (!matchCompileError(actual_line, expect_line)) continue;
                return;
            }

            return step.fail(maker,
                \\
                \\========= should contain: ===============
                \\{s}
                \\========= but not found: ================
                \\{s}
                \\=========================================
            , .{ expect_line, actual_errors });
        },
        .stderr_contains => |expect_line_string| {
            const expect_line = expect_line_string.slice(conf);
            const actual_stderr: []const u8 = if (step.result_error_msgs.items.len > 0)
                step.result_error_msgs.items[0]
            else
                &.{};
            step.result_error_msgs.clearRetainingCapacity();

            var stderr_line_it = mem.splitScalar(u8, actual_stderr, '\n');

            while (stderr_line_it.next()) |actual_line| {
                if (!matchCompileError(actual_line, expect_line)) continue;
                return;
            }

            return step.fail(maker,
                \\
                \\========= should contain: ===============
                \\{s}
                \\========= but not found: ================
                \\{s}
                \\=========================================
            , .{ expect_line, actual_stderr });
        },
        .exact => |expect_lines| {
            for (expect_lines.slice) |expect_line_string| {
                const expect_line = expect_line_string.slice(conf);
                const actual_line = actual_line_it.next() orelse {
                    try expected_generated.appendSlice(arena, expect_line);
                    try expected_generated.append(arena, '\n');
                    continue;
                };
                if (matchCompileError(actual_line, expect_line)) {
                    try expected_generated.appendSlice(arena, actual_line);
                    try expected_generated.append(arena, '\n');
                    continue;
                }
                try expected_generated.appendSlice(arena, expect_line);
                try expected_generated.append(arena, '\n');
            }

            if (mem.eql(u8, expected_generated.items, actual_errors)) return;

            return step.fail(maker,
                \\
                \\========= expected: =====================
                \\{s}
                \\========= but found: ====================
                \\{s}
                \\=========================================
            , .{ expected_generated.items, actual_errors });
        },
    }
}

fn matchCompileError(actual: []const u8, expected: []const u8) bool {
    if (mem.endsWith(u8, actual, expected)) return true;
    if (mem.startsWith(u8, expected, ":?:?: ")) {
        if (mem.endsWith(u8, actual, expected[":?:?: ".len..])) return true;
    }
    // We scan for /?/ in expected line and if there is a match, we match everything
    // up to and after /?/.
    const expected_trim = mem.trim(u8, expected, " ");
    if (mem.find(u8, expected_trim, "/?/")) |index| {
        const actual_trim = mem.trim(u8, actual, " ");
        const lhs = expected_trim[0..index];
        const rhs = expected_trim[index + "/?/".len ..];
        if (mem.startsWith(u8, actual_trim, lhs) and mem.endsWith(u8, actual_trim, rhs)) return true;
    }
    return false;
}

fn moduleNeedsCliArg(mod: *const Configuration.Module, conf: *const Configuration) bool {
    return for (0..mod.link_objects.len) |i| switch (mod.link_objects.tag(conf.extra, i)) {
        .c_source_file, .c_source_files, .assembly_file, .win32_resource_file => break true,
        else => continue,
    } else false;
}

const CliNamedModules = struct {
    modules: std.array_hash_map.Auto(Configuration.Module.Index, void),
    names: std.array_hash_map.String(void),

    /// Traverse the whole dependency graph and give every module a unique
    /// name, ideally one named after what it's called somewhere in the graph.
    /// It will help here to have both a mapping from module to name and a set
    /// of all the currently-used names.
    fn init(
        arena: Allocator,
        module_graph: *ModuleGraph,
        compile_index: Configuration.Step.Index,
        maker: *const Maker,
    ) Allocator.Error!CliNamedModules {
        const conf = &maker.scanned_config.configuration;
        const conf_compile = compile_index.ptr(conf).extended.get(conf.extra).compile;

        var result: CliNamedModules = .{
            .modules = .{},
            .names = .{},
        };
        const modules = try getModuleList(arena, module_graph, conf_compile.root_module, conf);
        {
            assert(conf_compile.root_module == modules.keys()[0]);
            try result.modules.put(arena, conf_compile.root_module, {});
            try result.names.put(arena, "root", {});
        }
        for (modules.keys()[1..], modules.values()[1..]) |mod, orig_name| {
            const orig_name_slice = orig_name.slice(conf);
            var name: []const u8 = orig_name_slice;
            var n: usize = 0;
            while (true) {
                const gop = try result.names.getOrPut(arena, name);
                if (!gop.found_existing) {
                    try result.modules.putNoClobber(arena, mod, {});
                    break;
                }
                name = try arena.print("{s}{d}", .{ orig_name_slice, n });
                n += 1;
            }
        }
        return result;
    }
};

pub fn getCompileDependencies(
    arena: Allocator,
    module_graph: *ModuleGraph,
    conf: *const Configuration,
    start: Configuration.Step.Index,
    chase_dynamic: bool,
) ![]const Configuration.Step.Index {
    var compiles: std.array_hash_map.Auto(Configuration.Step.Index, void) = .empty;
    var compiles_i: usize = 0;

    try compiles.putNoClobber(arena, start, {});

    while (compiles_i < compiles.count()) : (compiles_i += 1) {
        const step = compiles.keys()[compiles_i].ptr(conf);
        const compile = step.extended.get(conf.extra).compile;
        const modules = try getModuleList(arena, module_graph, compile.root_module, conf);

        for (modules.keys()) |mod_index| {
            const mod = mod_index.get(conf);
            for (0..mod.link_objects.len) |i| {
                switch (mod.link_objects.get(conf.extra, i)) {
                    .other_step => |other_compile_index| {
                        const other_compile = other_compile_index.ptr(conf).extended.get(conf.extra).compile;
                        if (!chase_dynamic and other_compile.isDynamicLibrary()) continue;
                        try compiles.put(arena, other_compile_index, {});
                    },
                    else => {},
                }
            }
        }
    }

    return compiles.keys();
}

/// Returned pointer expires upon next call to `getModuleList`.
fn getModuleList(
    arena: Allocator,
    module_graph: *ModuleGraph,
    root_module: Configuration.Module.Index,
    conf: *const Configuration,
) !*ModuleList {
    const gop = try module_graph.getOrPutAdapted(arena, root_module, @as(ModuleListContext.Adapter, .{}));
    const modules = gop.key_ptr;

    if (gop.found_existing) return modules;
    modules.* = .empty;
    try modules.putNoClobber(arena, root_module, .root);

    var i: usize = 0;

    while (i < modules.entries.len) : (i += 1) {
        const dep_index = modules.keys()[i];
        const dep = dep_index.get(conf);
        const imports = dep.import_table.get(conf).imports;
        try modules.ensureUnusedCapacity(arena, imports.mal.len);
        for (imports.mal.items(.name), imports.mal.items(.module)) |import_name, other_mod|
            modules.putAssumeCapacity(other_mod, import_name);
    }

    return modules;
}

fn appendModuleFlags(
    arena: Allocator,
    module_index: Configuration.Module.Index,
    zig_args: *std.ArrayList([]const u8),
    asking_step: Configuration.Step.Index,
    maker: *const Maker,
) !void {
    const gpa = maker.gpa;
    const conf = &maker.scanned_config.configuration;
    const m = module_index.get(conf);

    try addFlag(gpa, zig_args, "strip", m.flags.strip.toBool());
    try addFlag(gpa, zig_args, "single-threaded", m.flags.single_threaded.toBool());
    try addFlag(gpa, zig_args, "stack-check", m.flags.stack_check.toBool());
    try addFlag(gpa, zig_args, "stack-protector", m.flags.stack_protector.toBool());
    try addFlag(gpa, zig_args, "omit-frame-pointer", m.flags2.omit_frame_pointer.toBool());
    try addFlag(gpa, zig_args, "error-tracing", m.flags2.error_tracing.toBool());
    try addFlag(gpa, zig_args, "sanitize-thread", m.flags.sanitize_thread.toBool());
    try addFlag(gpa, zig_args, "fuzz", m.flags.fuzz.toBool());
    try addFlag(gpa, zig_args, "valgrind", m.flags2.valgrind.toBool());
    try addFlag(gpa, zig_args, "PIC", m.flags2.pic.toBool());
    try addFlag(gpa, zig_args, "no-builtin", m.flags2.no_builtin.toBool());

    try addArchFlag(gpa, zig_args, "red-zone", m.flags2.red_zone.toBool());
    {
        try zig_args.ensureUnusedCapacity(gpa, 6);

        switch (m.flags.sanitize_c) {
            .off => zig_args.appendAssumeCapacity("-fno-sanitize-c"),
            .trap => zig_args.appendAssumeCapacity("-fsanitize-c=trap"),
            .full => zig_args.appendAssumeCapacity("-fsanitize-c=full"),
            .default => {},
        }

        switch (m.flags.dwarf_format) {
            .@"32" => zig_args.appendAssumeCapacity("-gdwarf32"),
            .@"64" => zig_args.appendAssumeCapacity("-gdwarf64"),
            .default => {},
        }

        switch (m.flags.unwind_tables) {
            .none => zig_args.appendAssumeCapacity("-fno-unwind-tables"),
            .sync => zig_args.appendAssumeCapacity("-funwind-tables"),
            .async => zig_args.appendAssumeCapacity("-fasync-unwind-tables"),
            .default => {},
        }

        switch (m.flags.optimize) {
            .debug => zig_args.appendAssumeCapacity("-Odebug"),
            .safe => zig_args.appendAssumeCapacity("-Osafe"),
            .fast => zig_args.appendAssumeCapacity("-Ofast"),
            .small => zig_args.appendAssumeCapacity("-Osmall"),
            .default => {},
        }

        if (m.flags.code_model != .default) {
            zig_args.appendAssumeCapacity("-mcmodel");
            zig_args.appendAssumeCapacity(@tagName(m.flags.code_model));
        }
    }

    if (m.resolved_target.get(conf)) |resolved_target| {
        // Communicate the query via CLI since it's more compact.
        if (resolved_target.unwrapQuery(conf)) |query| {
            try zig_args.ensureUnusedCapacity(gpa, 6);

            zig_args.appendAssumeCapacity("-target");
            zig_args.appendAssumeCapacity(try query.zigTriple(arena));

            zig_args.appendAssumeCapacity("-mcpu");
            zig_args.appendAssumeCapacity(try query.serializeCpuAlloc(arena));

            if (query.dynamic_linker) |*dynamic_linker| {
                if (dynamic_linker.get()) |dynamic_linker_path| {
                    zig_args.appendAssumeCapacity("--dynamic-linker");
                    zig_args.appendAssumeCapacity(dynamic_linker_path);
                } else {
                    zig_args.appendAssumeCapacity("--no-dynamic-linker");
                }
            }
        }
    }

    for (m.export_symbol_names.slice) |symbol_name| {
        try zig_args.append(gpa, try arena.print("--export={s}", .{symbol_name.slice(conf)}));
    }

    try zig_args.ensureUnusedCapacity(gpa, 2 * m.include_dirs.len);
    for (0..m.include_dirs.len) |i|
        try appendIncludeDirFlags(arena, m.include_dirs.get(conf.extra, i), zig_args, asking_step, maker);

    try zig_args.ensureUnusedCapacity(gpa, m.c_macros.slice.len);
    for (m.c_macros.slice) |c_macro|
        zig_args.appendAssumeCapacity(c_macro.slice(conf));

    try zig_args.ensureUnusedCapacity(gpa, 2 * m.lib_paths.slice.len);
    for (m.lib_paths.slice) |lib_path| {
        zig_args.appendAssumeCapacity("-L");
        zig_args.appendAssumeCapacity(try maker.resolveLazyPathIndexAbs(arena, lib_path, asking_step));
    }

    try zig_args.ensureUnusedCapacity(gpa, 2 * m.rpaths.len);
    for (0..m.rpaths.len) |i| switch (m.rpaths.get(conf.extra, i)) {
        .lazy_path => |lp| {
            zig_args.appendAssumeCapacity("-rpath");
            zig_args.appendAssumeCapacity(try maker.resolveLazyPathIndexAbs(arena, lp, asking_step));
        },
        .special => |string| {
            zig_args.appendAssumeCapacity("-rpath");
            zig_args.appendAssumeCapacity(string.slice(conf));
        },
    };
}

/// Assumes unused capacity for at least 2 items.
pub fn appendIncludeDirFlags(
    arena: Allocator,
    include_dir: Configuration.Module.IncludeDir,
    zig_args: *std.ArrayList([]const u8),
    asking_step: Configuration.Step.Index,
    maker: *const Maker,
) !void {
    const conf = &maker.scanned_config.configuration;

    switch (include_dir) {
        .path => |lp| {
            zig_args.appendAssumeCapacity("-I");
            zig_args.appendAssumeCapacity(try maker.resolveLazyPathIndexAbs(arena, lp, asking_step));
        },
        .path_system => |lp| {
            zig_args.appendAssumeCapacity("-isystem");
            zig_args.appendAssumeCapacity(try maker.resolveLazyPathIndexAbs(arena, lp, asking_step));
        },
        .path_after => |lp| {
            zig_args.appendAssumeCapacity("-idirafter");
            zig_args.appendAssumeCapacity(try maker.resolveLazyPathIndexAbs(arena, lp, asking_step));
        },
        .framework_path => |lp| {
            zig_args.appendAssumeCapacity("-F");
            zig_args.appendAssumeCapacity(try maker.resolveLazyPathIndexAbs(arena, lp, asking_step));
        },
        .framework_path_system => |lp| {
            zig_args.appendAssumeCapacity("-iframework");
            zig_args.appendAssumeCapacity(try maker.resolveLazyPathIndexAbs(arena, lp, asking_step));
        },
        .config_header_step => |ch_index| {
            const conf_ch = ch_index.ptr(conf).extended.get(conf.extra).config_header;
            const path = maker.generatedPath(conf_ch.generated_dir).*;
            zig_args.appendAssumeCapacity("-I");
            zig_args.appendAssumeCapacity(try path.toString(arena));
        },
        .embed_path => |lazy_path| {
            zig_args.appendAssumeCapacity(try arena.print("--embed-dir={f}", .{
                try maker.resolveLazyPathIndex(arena, lazy_path, asking_step),
            }));
        },
    }
}
