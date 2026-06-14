const std = @import("std");
const Allocator = std.mem.Allocator;
const Path = std.Build.Cache.Path;
const assert = std.debug.assert;
const log = std.log.scoped(.link);

const Zcu = @import("../Zcu.zig");
const InternPool = @import("../InternPool.zig");
const Compilation = @import("../Compilation.zig");
const link = @import("../link.zig");
const Air = @import("../Air.zig");
const Type = @import("../Type.zig");
const codegen = @import("../codegen.zig");
const CodeGen = @import("../codegen/spirv/CodeGen.zig");
const Module = @import("../codegen/spirv/Module.zig");
const trace = @import("../tracy.zig").trace;
const BinaryModule = @import("SpirV/BinaryModule.zig");
const lower_invocation_globals = @import("SpirV/lower_invocation_globals.zig");
const dedup_types = @import("SpirV/dedup_types.zig");
const prune_unused = @import("SpirV/prune_unused.zig");

const spec = @import("../codegen/spirv/spec.zig");
const Section = @import("../codegen/spirv/Section.zig");
const Id = spec.Id;
const Word = spec.Word;
const Mir = @import("../codegen/spirv/Mir.zig");

const Linker = @This();

base: link.File,
fragments: std.AutoArrayHashMapUnmanaged(InternPool.Nav.Index, Mir) = .empty,
pending_navs: std.ArrayListUnmanaged(InternPool.Nav.Index) = .empty,
entry_points: std.ArrayListUnmanaged(EntryPointDecl) = .empty,

const EntryPointDecl = struct {
    nav: InternPool.Nav.Index,
    name: []const u8,
    cc: std.builtin.CallingConvention,
};

pub fn createEmpty(
    arena: Allocator,
    comp: *Compilation,
    emit: Path,
    options: link.File.OpenOptions,
) !*Linker {
    const io = comp.io;
    const target = &comp.root_mod.resolved_target.result;

    assert(!comp.config.use_lld); // Caught by Compilation.Config.resolve
    assert(!comp.config.use_llvm); // Caught by Compilation.Config.resolve
    assert(target.ofmt == .spirv); // Caught by Compilation.Config.resolve
    switch (target.cpu.arch) {
        .spirv32, .spirv64 => {},
        else => unreachable, // Caught by Compilation.Config.resolve.
    }
    switch (target.os.tag) {
        .opencl, .opengl, .vulkan => {},
        else => unreachable, // Caught by Compilation.Config.resolve.
    }

    const linker = try arena.create(Linker);
    linker.* = .{
        .base = .{
            .tag = .spirv,
            .comp = comp,
            .emit = emit,
            .gc_sections = options.gc_sections orelse false,
            .print_gc_sections = options.print_gc_sections,
            .stack_size = options.stack_size orelse 0,
            .allow_shlib_undefined = options.allow_shlib_undefined orelse false,
            .file = null,
            .build_id = options.build_id,
        },
    };
    errdefer linker.deinit();

    linker.base.file = try emit.root_dir.handle.createFile(io, emit.sub_path, .{
        .truncate = true,
        .read = true,
    });

    return linker;
}

pub fn open(
    arena: Allocator,
    comp: *Compilation,
    emit: Path,
    options: link.File.OpenOptions,
) !*Linker {
    return createEmpty(arena, comp, emit, options);
}

pub fn deinit(linker: *Linker) void {
    const gpa = linker.base.comp.gpa;
    for (linker.fragments.values()) |*mir| {
        mir.deinit(gpa);
    }
    linker.fragments.deinit(gpa);
    linker.pending_navs.deinit(gpa);
    linker.entry_points.deinit(gpa);
}

pub fn updateFunc(
    linker: *Linker,
    pt: Zcu.PerThread,
    func_index: InternPool.Index,
    mir: *codegen.AnyMir,
) !void {
    const gpa = linker.base.comp.gpa;
    const nav = pt.zcu.funcInfo(func_index).owner_nav;

    if (linker.fragments.getPtr(nav)) |existing| {
        existing.deinit(gpa);
    }

    try linker.fragments.put(gpa, nav, mir.spirv);
    mir.spirv = .{
        .extended_instruction_set = &.{},
        .globals = &.{},
        .functions = &.{},
        .annotations = &.{},
        .debug_names = &.{},
        .debug_strings = &.{},
        .execution_modes = &.{},
        .id_bound = 0,
        .owner_nav = mir.spirv.owner_nav,
        .kind = mir.spirv.kind,
        .decl_result_id = .none,
        .nav_refs = &.{},
        .uav_refs = &.{},
        .decl_deps = &.{},
        .internal_globals = &.{},
        .entry_points = &.{},
    };
}

pub fn updateNav(linker: *Linker, pt: Zcu.PerThread, nav: InternPool.Nav.Index) link.Error!void {
    const ip = &pt.zcu.intern_pool;
    log.debug("deferring nav {f}({d}) to flush", .{ ip.getNav(nav).fqn.fmt(ip), nav });

    const gpa = linker.base.comp.gpa;
    linker.pending_navs.append(gpa, nav) catch return error.OutOfMemory;
}

pub fn updateExports(
    linker: *Linker,
    pt: Zcu.PerThread,
    exported: Zcu.Exported,
    export_indices: []const Zcu.Export.Index,
) !void {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const gpa = linker.base.comp.gpa;
    const nav_index = switch (exported) {
        .nav => |nav| nav,
        .uav => |uav| {
            _ = uav;
            @panic("TODO: implement Linker linker code for exporting a constant value");
        },
    };
    const nav_ty = ip.getNav(nav_index).resolved.?.type;
    if (ip.isFunctionType(nav_ty)) {
        const cc = Type.fromInterned(nav_ty).fnCallingConvention(zcu);
        if (cc == .spirv_device) return;

        for (export_indices) |export_idx| {
            const exp = export_idx.ptr(zcu);
            try linker.entry_points.append(gpa, .{
                .nav = nav_index,
                .name = exp.opts.name.toSlice(ip),
                .cc = cc,
            });
        }
    }
}

pub fn flush(
    linker: *Linker,
    arena: Allocator,
    tid: Zcu.PerThread.Id,
    prog_node: std.Progress.Node,
) link.Error!void {
    const tracy = trace(@src());
    defer tracy.end();

    const sub_prog_node = prog_node.start("Flush Module", 0);
    defer sub_prog_node.end();

    const comp = linker.base.comp;
    const diags = &comp.link_diags;
    const gpa = comp.gpa;
    const io = comp.io;

    const zcu = comp.zcu.?;
    const active = zcu.activate(tid);
    defer active.deactivate();
    const pt = active.pt;
    for (linker.pending_navs.items) |nav| {
        if (linker.fragments.contains(nav)) continue;

        const mir = CodeGen.generateNav(pt, nav) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.AlreadyReported => continue,
            error.Canceled => return error.Canceled,
        };

        linker.fragments.put(gpa, nav, mir) catch return error.OutOfMemory;
    }
    linker.pending_navs.clearRetainingCapacity();

    const merged = mergeFragments(linker, gpa, arena) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
    };

    var binary = linkModule(arena, merged.words, merged.id_bound, sub_prog_node) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        else => |other| return diags.fail("error while linking: {s}", .{@errorName(other)}),
    };
    defer binary.deinit(arena);

    const header = [_]Word{
        spec.magic_number,
        merged.version.toWord(),
        merged.generator_id,
        binary.id_bound,
        0,
    };

    linker.base.file.?.writeStreamingAll(io, @ptrCast(&header)) catch |err|
        return diags.fail("failed to write: {t}", .{err});
    linker.base.file.?.writeStreamingAll(io, @ptrCast(binary.instructions)) catch |err|
        return diags.fail("failed to write: {t}", .{err});
}

fn linkModule(arena: Allocator, words: []const Word, id_bound: u32, progress: std.Progress.Node) !BinaryModule {
    var parser = try BinaryModule.Parser.init(arena);
    defer parser.deinit();
    var binary = try parser.initFromWords(words, id_bound);
    try prune_unused.run(&parser, &binary);
    try dedup_types.run(&parser, &binary);
    try lower_invocation_globals.run(&parser, &binary, progress);
    return binary;
}

fn mergeFragments(linker: *Linker, gpa: Allocator, arena: Allocator) error{OutOfMemory}!MergedModule {
    const comp = linker.base.comp;
    const zcu = comp.zcu.?;
    const target = zcu.getTarget();

    var next_id: Word = 1;

    var nav_final_ids: std.AutoHashMapUnmanaged(InternPool.Nav.Index, Id) = .empty;
    defer nav_final_ids.deinit(gpa);

    var uav_final_ids: std.AutoHashMapUnmanaged(struct { InternPool.Index, spec.StorageClass }, Id) = .empty;
    defer uav_final_ids.deinit(gpa);

    var frag_infos: std.ArrayList(FragmentInfo) = .empty;
    defer frag_infos.deinit(gpa);
    try frag_infos.ensureTotalCapacity(gpa, @intCast(linker.fragments.count()));

    for (linker.fragments.keys(), linker.fragments.values()) |nav, *mir| {
        const id_offset = next_id - 1;
        frag_infos.appendAssumeCapacity(.{
            .id_offset = id_offset,
        });

        if (mir.decl_result_id != .none) {
            try nav_final_ids.put(gpa, nav, @enumFromInt(@intFromEnum(mir.decl_result_id) + id_offset));
        }

        next_id += mir.id_bound - 1;
    }

    for (linker.fragments.values(), frag_infos.items) |*mir, frag_info| {
        for (mir.nav_refs) |ref| {
            if (!nav_final_ids.contains(ref.nav)) {
                try nav_final_ids.put(gpa, ref.nav, @enumFromInt(@intFromEnum(ref.local_id) + frag_info.id_offset));
            }
        }

        for (mir.uav_refs) |ref| {
            const key = .{ ref.val, ref.storage_class };
            if (!uav_final_ids.contains(key)) {
                try uav_final_ids.put(gpa, key, @enumFromInt(@intFromEnum(ref.local_id) + frag_info.id_offset));
            }
        }
    }

    var parser = BinaryModule.Parser.init(gpa) catch return error.OutOfMemory;
    defer parser.deinit();
    var ext_inst_section = Section{};
    defer ext_inst_section.deinit(gpa);
    var globals_section = Section{};
    defer globals_section.deinit(gpa);
    var functions_section = Section{};
    defer functions_section.deinit(gpa);
    var annotations_section = Section{};
    defer annotations_section.deinit(gpa);
    var debug_names_section = Section{};
    defer debug_names_section.deinit(gpa);
    var debug_strings_section = Section{};
    defer debug_strings_section.deinit(gpa);
    var execution_modes_section = Section{};
    defer execution_modes_section.deinit(gpa);

    for (linker.fragments.values(), frag_infos.items) |*mir, frag_info| {
        var id_remap: std.AutoHashMapUnmanaged(Id, Id) = .empty;
        defer id_remap.deinit(gpa);

        for (mir.nav_refs) |ref| {
            if (nav_final_ids.get(ref.nav)) |final_id| {
                try id_remap.put(gpa, ref.local_id, final_id);
            }
        }

        for (mir.uav_refs) |ref| {
            const key = .{ ref.val, ref.storage_class };
            if (uav_final_ids.get(key)) |final_id| {
                try id_remap.put(gpa, ref.local_id, final_id);
            }
        }

        try remapAndAppend(gpa, &ext_inst_section, mir.extended_instruction_set, frag_info.id_offset, &id_remap, &parser);
        try remapAndAppend(gpa, &globals_section, mir.globals, frag_info.id_offset, &id_remap, &parser);
        try remapAndAppend(gpa, &functions_section, mir.functions, frag_info.id_offset, &id_remap, &parser);
        try remapAndAppend(gpa, &annotations_section, mir.annotations, frag_info.id_offset, &id_remap, &parser);
        try remapAndAppend(gpa, &debug_names_section, mir.debug_names, frag_info.id_offset, &id_remap, &parser);
        try remapAndAppend(gpa, &debug_strings_section, mir.debug_strings, frag_info.id_offset, &id_remap, &parser);
        try remapAndAppend(gpa, &execution_modes_section, mir.execution_modes, frag_info.id_offset, &id_remap, &parser);

        for (mir.entry_points) |ep| {
            try linker.entry_points.append(gpa, .{
                .nav = mir.owner_nav,
                .name = ep.name,
                .cc = ep.cc,
            });
        }
    }

    var capabilities_section = Section{};
    defer capabilities_section.deinit(gpa);
    var extensions_section = Section{};
    defer extensions_section.deinit(gpa);
    var memory_model_section = Section{};
    defer memory_model_section.deinit(gpa);
    var entry_points_section = Section{};
    defer entry_points_section.deinit(gpa);

    const cap_pairs = [_]struct { cap: spec.Capability, ext: ?[]const u8 }{
        .{ .cap = .int8, .ext = null },
        .{ .cap = .int16, .ext = null },
    };
    for (cap_pairs) |pair| {
        try capabilities_section.emit(gpa, .OpCapability, .{ .capability = pair.cap });
        if (pair.ext) |ext| {
            try extensions_section.emit(gpa, .OpExtension, .{ .name = ext });
        }
    }

    switch (target.os.tag) {
        .opengl => {
            try capabilities_section.emit(gpa, .OpCapability, .{ .capability = .shader });
            try capabilities_section.emit(gpa, .OpCapability, .{ .capability = .matrix });
        },
        .vulkan => {
            try capabilities_section.emit(gpa, .OpCapability, .{ .capability = .shader });
            try capabilities_section.emit(gpa, .OpCapability, .{ .capability = .matrix });
            if (target.cpu.arch == .spirv64) {
                try extensions_section.emit(gpa, .OpExtension, .{ .name = "SPV_KHR_physical_storage_buffer" });
                try capabilities_section.emit(gpa, .OpCapability, .{ .capability = .physical_storage_buffer_addresses });
            }
        },
        .opencl, .amdhsa => {
            try capabilities_section.emit(gpa, .OpCapability, .{ .capability = .kernel });
            try capabilities_section.emit(gpa, .OpCapability, .{ .capability = .addresses });
        },
        else => unreachable,
    }
    if (target.cpu.arch == .spirv64)
        try capabilities_section.emit(gpa, .OpCapability, .{ .capability = .int64 });
    if (target.cpu.has(.spirv, .int64))
        try capabilities_section.emit(gpa, .OpCapability, .{ .capability = .int64 });
    if (target.cpu.has(.spirv, .float16)) {
        if (target.os.tag == .opencl) try extensions_section.emit(gpa, .OpExtension, .{ .name = "cl_khr_fp16" });
        try capabilities_section.emit(gpa, .OpCapability, .{ .capability = .float16 });
    }
    if (target.cpu.has(.spirv, .float64))
        try capabilities_section.emit(gpa, .OpCapability, .{ .capability = .float64 });
    if (target.cpu.has(.spirv, .generic_pointer))
        try capabilities_section.emit(gpa, .OpCapability, .{ .capability = .generic_pointer });
    if (target.cpu.has(.spirv, .vector16))
        try capabilities_section.emit(gpa, .OpCapability, .{ .capability = .vector16 });
    if (target.cpu.has(.spirv, .storage_push_constant16)) {
        try extensions_section.emit(gpa, .OpExtension, .{ .name = "SPV_KHR_16bit_storage" });
        try capabilities_section.emit(gpa, .OpCapability, .{ .capability = .storage_push_constant16 });
    }
    if (target.cpu.has(.spirv, .arbitrary_precision_integers)) {
        try extensions_section.emit(gpa, .OpExtension, .{ .name = "SPV_INTEL_arbitrary_precision_integers" });
        try capabilities_section.emit(gpa, .OpCapability, .{ .capability = .arbitrary_precision_integers_intel });
    }
    if (target.cpu.has(.spirv, .variable_pointers)) {
        try extensions_section.emit(gpa, .OpExtension, .{ .name = "SPV_KHR_variable_pointers" });
        try capabilities_section.emit(gpa, .OpCapability, .{ .capability = .variable_pointers_storage_buffer });
        try capabilities_section.emit(gpa, .OpCapability, .{ .capability = .variable_pointers });
    }

    const addressing_model: spec.AddressingModel = switch (target.os.tag) {
        .opengl => .logical,
        .vulkan => if (target.cpu.arch == .spirv32) .logical else .physical_storage_buffer64,
        .opencl => if (target.cpu.arch == .spirv32) .physical32 else .physical64,
        .amdhsa => .physical64,
        else => unreachable,
    };
    try memory_model_section.emit(gpa, .OpMemoryModel, .{
        .addressing_model = addressing_model,
        .memory_model = switch (target.os.tag) {
            .opencl => .open_cl,
            .vulkan, .opengl => .glsl450,
            else => unreachable,
        },
    });

    for (linker.entry_points.items) |ep| {
        const final_id = nav_final_ids.get(ep.nav) orelse continue;

        var interface: std.ArrayList(Id) = .empty;
        defer interface.deinit(gpa);

        var visited: std.AutoHashMapUnmanaged(InternPool.Nav.Index, void) = .empty;
        defer visited.deinit(gpa);

        try collectEntryPointInterface(linker, ep.nav, &interface, &visited, &nav_final_ids, &uav_final_ids, &frag_infos, gpa);

        const exec_model: spec.ExecutionModel = switch (target.os.tag) {
            .vulkan, .opengl => switch (ep.cc) {
                .spirv_vertex => .vertex,
                .spirv_fragment => .fragment,
                .spirv_kernel => .gl_compute,
                .spirv_task => .task_ext,
                .spirv_mesh => .mesh_ext,
                .spirv_device => continue,
                else => unreachable,
            },
            .opencl => switch (ep.cc) {
                .spirv_kernel => .kernel,
                .spirv_device => continue,
                else => unreachable,
            },
            else => unreachable,
        };

        try entry_points_section.emit(gpa, .OpEntryPoint, .{
            .execution_model = exec_model,
            .entry_point = final_id,
            .name = ep.name,
            .interface = interface.items,
        });

        switch (ep.cc) {
            .spirv_kernel, .spirv_task => |kernel| {
                try execution_modes_section.emit(gpa, .OpExecutionMode, .{
                    .entry_point = final_id,
                    .mode = .{ .local_size = .{
                        .x_size = kernel.x,
                        .y_size = kernel.y,
                        .z_size = kernel.z,
                    } },
                });
            },
            .spirv_fragment => |fragment| {
                try execution_modes_section.emit(gpa, .OpExecutionMode, .{
                    .entry_point = final_id,
                    .mode = if (target.os.tag == .vulkan) .origin_upper_left else .origin_lower_left,
                });
                if (fragment.pixel_centered_integer) {
                    try execution_modes_section.emit(gpa, .OpExecutionMode, .{
                        .entry_point = final_id,
                        .mode = .pixel_center_integer,
                    });
                }
                const exec_mode: ?spec.ExecutionMode.Extended = switch (fragment.depth_assumption) {
                    .none => null,
                    .greater => .depth_greater,
                    .less => .depth_less,
                    .unchanged => .depth_unchanged,
                };
                if (exec_mode) |mode| {
                    try execution_modes_section.emit(gpa, .OpExecutionMode, .{
                        .entry_point = final_id,
                        .mode = mode,
                    });
                }
            },
            .spirv_mesh => |mesh| {
                try execution_modes_section.emit(gpa, .OpExecutionMode, .{
                    .entry_point = final_id,
                    .mode = .{ .output_vertices = .{ .vertex_count = mesh.max_vertices } },
                });
                try execution_modes_section.emit(gpa, .OpExecutionMode, .{
                    .entry_point = final_id,
                    .mode = .{ .output_primitives_ext = .{ .primitive_count = mesh.max_primitives } },
                });
                try execution_modes_section.emit(gpa, .OpExecutionMode, .{
                    .entry_point = final_id,
                    .mode = switch (mesh.stage_output) {
                        .output_points => .output_points,
                        .output_lines => .output_lines_ext,
                        .output_triangles => .output_triangles_ext,
                    },
                });
            },
            else => {},
        }
    }

    const ip = &zcu.intern_pool;
    var error_info: std.Io.Writer.Allocating = .init(gpa);
    defer error_info.deinit();
    error_info.writer.writeAll("zig_errors:") catch return error.OutOfMemory;
    for (ip.global_error_set.getNamesFromMainThread()) |name| {
        error_info.writer.writeByte(':') catch return error.OutOfMemory;
        std.Uri.Component.percentEncode(
            &error_info.writer,
            name.toSlice(ip),
            struct {
                fn isValidChar(c: u8) bool {
                    return switch (c) {
                        0, '%', ':' => false,
                        else => true,
                    };
                }
            }.isValidChar,
        ) catch return error.OutOfMemory;
    }
    try debug_strings_section.emit(gpa, .OpSourceExtension, .{
        .extension = error_info.written(),
    });

    const zig_version = @import("builtin").zig_version;
    const zig_spirv_compiler_version = comptime (zig_version.major << 12) | (zig_version.minor << 7) | zig_version.patch;
    try debug_strings_section.emit(gpa, .OpSource, .{
        .source_language = .zig,
        .version = zig_spirv_compiler_version,
        .file = null,
        .source = null,
    });

    const version: spec.Version = .{
        .major = 1,
        .minor = blk: {
            if (target.cpu.has(.spirv, .v1_6)) break :blk 6;
            if (target.cpu.has(.spirv, .v1_5)) break :blk 5;
            if (target.cpu.has(.spirv, .v1_4)) break :blk 4;
            if (target.cpu.has(.spirv, .v1_3)) break :blk 3;
            if (target.cpu.has(.spirv, .v1_2)) break :blk 2;
            if (target.cpu.has(.spirv, .v1_1)) break :blk 1;
            break :blk 0;
        },
    };

    const generator_id: u32 = (spec.zig_generator_id << 16) | zig_spirv_compiler_version;

    const buffers = &[_][]const Word{
        capabilities_section.toWords(),
        extensions_section.toWords(),
        ext_inst_section.toWords(),
        memory_model_section.toWords(),
        entry_points_section.toWords(),
        execution_modes_section.toWords(),
        debug_strings_section.toWords(),
        debug_names_section.toWords(),
        annotations_section.toWords(),
        globals_section.toWords(),
        functions_section.toWords(),
    };

    var total_size: usize = 0;
    for (buffers) |buffer| {
        total_size += buffer.len;
    }
    const result = try arena.alloc(Word, total_size);

    var offset: usize = 0;
    for (buffers) |buffer| {
        @memcpy(result[offset..][0..buffer.len], buffer);
        offset += buffer.len;
    }

    return .{
        .words = result,
        .id_bound = next_id,
        .version = version,
        .generator_id = generator_id,
    };
}

const MergedModule = struct {
    words: []const Word,
    id_bound: Word,
    version: spec.Version,
    generator_id: u32,
};

const FragmentInfo = struct {
    id_offset: Word,
};

fn collectEntryPointInterface(
    linker: *Linker,
    nav: InternPool.Nav.Index,
    interface: *std.ArrayList(Id),
    visited: *std.AutoHashMapUnmanaged(InternPool.Nav.Index, void),
    nav_final_ids: *const std.AutoHashMapUnmanaged(InternPool.Nav.Index, Id),
    uav_final_ids: *const std.AutoHashMapUnmanaged(struct { InternPool.Index, spec.StorageClass }, Id),
    frag_infos: *const std.ArrayList(FragmentInfo),
    gpa: Allocator,
) error{OutOfMemory}!void {
    const visited_gop = try visited.getOrPut(gpa, nav);
    if (visited_gop.found_existing) return;

    const frag_index = linker.fragments.getIndex(nav) orelse return;
    const mir = &linker.fragments.values()[frag_index];
    const id_offset = frag_infos.items[frag_index].id_offset;

    if (mir.kind == .global) {
        if (nav_final_ids.get(nav)) |final_id| {
            try interface.append(gpa, final_id);
        }
    }

    for (mir.uav_refs) |ref| {
        if (ref.kind == .global) {
            if (uav_final_ids.get(.{ ref.val, ref.storage_class })) |final_id| {
                try interface.append(gpa, final_id);
            }
        }
    }

    for (mir.internal_globals) |local_id| {
        const global_id: Id = @enumFromInt(@intFromEnum(local_id) + id_offset);
        try interface.append(gpa, global_id);
    }

    for (mir.decl_deps) |dep| {
        try collectEntryPointInterface(linker, dep.nav, interface, visited, nav_final_ids, uav_final_ids, frag_infos, gpa);
    }

    for (mir.nav_refs) |ref| {
        try collectEntryPointInterface(linker, ref.nav, interface, visited, nav_final_ids, uav_final_ids, frag_infos, gpa);
    }
}

fn remapAndAppend(
    gpa: Allocator,
    dest: *Section,
    words: []const Word,
    id_offset: Word,
    id_remap: *const std.AutoHashMapUnmanaged(Id, Id),
    parser: *BinaryModule.Parser,
) error{OutOfMemory}!void {
    if (words.len == 0) return;

    try dest.instructions.ensureUnusedCapacity(gpa, words.len);

    var iter = BinaryModule.Instruction.Iterator.init(words, 0);
    while (iter.next()) |inst| {
        const dest_start = dest.instructions.items.len;
        const inst_words = words[inst.offset..][0..((words[inst.offset] >> 16))];
        dest.instructions.appendSliceAssumeCapacity(inst_words);
        const inst_slice = dest.instructions.items[dest_start..][0..inst_words.len];

        const inst_spec = parser.getInstSpec(inst.opcode) orelse continue;
        var offset: usize = 0;
        for (inst_spec.operands) |operand| {
            const cat = operand.kind.category();
            switch (operand.quantifier) {
                .required => {
                    if (offset >= inst.operands.len) break;
                    if (cat == .id) {
                        remapSingleId(&inst_slice[1 + offset], id_offset, id_remap);
                        offset += 1;
                    } else if (cat == .literal) {
                        offset += operandLiteralWordCount(operand.kind, inst, offset);
                    } else if (cat == .composite) {
                        remapCompositeOperand(operand.kind, inst_slice, offset, id_offset, id_remap);
                        offset += 2;
                    } else {
                        offset += 1;
                    }
                },
                .optional => {
                    if (offset >= inst.operands.len) break;
                    if (cat == .id) {
                        remapSingleId(&inst_slice[1 + offset], id_offset, id_remap);
                        offset += 1;
                    } else if (cat == .literal) {
                        offset += operandLiteralWordCount(operand.kind, inst, offset);
                    } else {
                        offset += 1;
                    }
                },
                .variadic => {
                    while (offset < inst.operands.len) {
                        if (cat == .id) {
                            remapSingleId(&inst_slice[1 + offset], id_offset, id_remap);
                            offset += 1;
                        } else if (cat == .literal) {
                            offset += operandLiteralWordCount(operand.kind, inst, offset);
                        } else if (cat == .composite) {
                            if (offset + 1 < inst.operands.len) {
                                remapCompositeOperand(operand.kind, inst_slice, offset, id_offset, id_remap);
                            }
                            offset += 2;
                        } else {
                            offset += 1;
                        }
                    }
                },
            }
        }
    }
}

fn remapCompositeOperand(
    kind: spec.OperandKind,
    inst_slice: []Word,
    offset: usize,
    id_offset: Word,
    id_remap: *const std.AutoHashMapUnmanaged(Id, Id),
) void {
    switch (kind) {
        .pair_literal_integer_id_ref => {
            remapSingleId(&inst_slice[1 + offset + 1], id_offset, id_remap);
        },
        .pair_id_ref_literal_integer => {
            remapSingleId(&inst_slice[1 + offset], id_offset, id_remap);
        },
        .pair_id_ref_id_ref => {
            remapSingleId(&inst_slice[1 + offset], id_offset, id_remap);
            remapSingleId(&inst_slice[1 + offset + 1], id_offset, id_remap);
        },
        else => {},
    }
}

fn operandLiteralWordCount(kind: spec.OperandKind, inst: BinaryModule.Instruction, offset: usize) usize {
    return switch (kind) {
        .literal_integer, .literal_float => 1,
        .literal_string => blk: {
            var count: usize = 0;
            var off = offset;
            while (off < inst.operands.len) {
                const word = inst.operands[off];
                count += 1;
                off += 1;
                if (word & 0xFF000000 == 0 or
                    word & 0x00FF0000 == 0 or
                    word & 0x0000FF00 == 0 or
                    word & 0x000000FF == 0)
                {
                    break;
                }
            }
            break :blk count;
        },
        .literal_context_dependent_number => inst.operands.len - offset,
        .literal_ext_inst_integer => 1,
        else => 1,
    };
}

fn remapSingleId(word: *Word, id_offset: Word, id_remap: *const std.AutoHashMapUnmanaged(Id, Id)) void {
    const id: Id = @enumFromInt(word.*);
    if (id == .none) return;
    if (id_remap.get(id)) |final_id| {
        word.* = @intFromEnum(final_id);
    } else {
        word.* = @intFromEnum(id) + id_offset;
    }
}
