const std = @import("std");
const Allocator = std.mem.Allocator;
const Path = std.Build.Cache.Path;
const assert = std.debug.assert;
const log = std.log.scoped(.link);
const zig_version = @import("builtin").zig_version;
const Zcu = @import("../Zcu.zig");
const InternPool = @import("../InternPool.zig");
const Compilation = @import("../Compilation.zig");
const link = @import("../link.zig");
const Air = @import("../Air.zig");
const Type = @import("../Type.zig");
const codegen = @import("../codegen.zig");
const CodeGen = @import("../codegen/spirv/CodeGen.zig");
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
external_objects: std.ArrayListUnmanaged(ExternalObject) = .empty,

const EntryPointDecl = struct {
    nav: InternPool.Nav.Index,
    name: []const u8,
    cc: std.builtin.CallingConvention,
};

const ExternalObject = struct {
    instructions: []const Word,
    id_bound: u32,
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
    for (linker.external_objects.items) |obj| {
        gpa.free(obj.instructions);
    }
    linker.external_objects.deinit(gpa);
}

pub fn loadInput(linker: *Linker, input: link.Input) !void {
    switch (input) {
        .object => |obj| {
            const comp = linker.base.comp;
            const gpa = comp.gpa;
            const io = comp.io;
            const diags = &comp.link_diags;

            const stat = obj.file.stat(io) catch |err|
                return diags.fail("failed to stat SPIR-V object '{f}': {t}", .{ obj.path, err });
            const file_size = std.math.cast(usize, stat.size) orelse
                return diags.fail("SPIR-V object '{f}' is too large", .{obj.path});
            if (file_size < 5 * @sizeOf(Word))
                return diags.fail("SPIR-V object '{f}' is too small to contain a valid header", .{obj.path});
            if (file_size % @sizeOf(Word) != 0)
                return diags.fail("SPIR-V object '{f}' size is not a multiple of the word size", .{obj.path});

            const word_count = file_size / @sizeOf(Word);
            const all_words = try gpa.alloc(Word, word_count);
            defer gpa.free(all_words);

            const bytes = std.mem.sliceAsBytes(all_words);
            const n_read = obj.file.readPositionalAll(io, bytes, 0) catch |err|
                return diags.fail("failed to read SPIR-V object '{f}': {t}", .{ obj.path, err });
            if (n_read != bytes.len)
                return diags.fail("SPIR-V object '{f}': incomplete read", .{obj.path});

            const needs_swap = all_words[0] == @byteSwap(spec.magic_number);
            if (needs_swap) {
                for (all_words) |*w| w.* = @byteSwap(w.*);
            }

            if (all_words[0] != spec.magic_number)
                return diags.fail("SPIR-V object '{f}': invalid magic number", .{obj.path});

            const id_bound = all_words[3];
            const instructions = try gpa.dupe(Word, all_words[5..]);
            errdefer gpa.free(instructions);

            // OpCapability instructions appear at the top of the module
            // so we can stop scanning as soon as we hit anything else.
            var it: BinaryModule.Instruction.Iterator = .init(instructions, 0);
            const has_linkage = while (it.next()) |inst| switch (inst.opcode) {
                .OpCapability => {
                    const cap: spec.Capability = @enumFromInt(inst.operands[0]);
                    if (cap == .linkage) break true;
                },
                else => break false,
            } else false;
            if (!has_linkage) {
                return diags.fail("SPIR-V object '{f}' is missing the Linkage capability and cannot be linked", .{obj.path});
            }

            try linker.external_objects.append(gpa, .{
                .instructions = instructions,
                .id_bound = id_bound,
            });
        },
        else => {
            const diags = &linker.base.comp.link_diags;
            return diags.fail("unsupported link input for SPIR-V target", .{});
        },
    }
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
    const sub_prog_node = prog_node.start("Flush Module", 0);
    defer sub_prog_node.end();

    const comp = linker.base.comp;
    const diags = &comp.link_diags;
    const gpa = comp.gpa;
    const io = comp.io;

    if (comp.zcu) |zcu| {
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
    }

    const merged = mergeFragments(linker, gpa, arena) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
    };

    var binary = linkModule(arena, merged.words, merged.id_bound, sub_prog_node) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        else => |other| {
            return diags.fail("error while linking: {s}", .{@errorName(other)});
        },
    };
    defer binary.deinit(arena);

    const header = [_]Word{
        spec.magic_number,
        merged.version.toWord(),
        merged.generator_id,
        binary.id_bound,
        0,
    };

    var file_writer = linker.base.file.?.writer(io, &.{});
    file_writer.interface.writeSliceEndian(Word, &header, .little) catch |err| switch (err) {
        error.WriteFailed => return diags.fail("failed to write: {t}", .{file_writer.err.?}),
    };
    file_writer.interface.writeSliceEndian(Word, binary.instructions, .little) catch |err| switch (err) {
        error.WriteFailed => return diags.fail("failed to write: {t}", .{file_writer.err.?}),
    };
    file_writer.end() catch |err| switch (err) {
        error.WriteFailed => return diags.fail("failed to write: {t}", .{file_writer.err.?}),
        else => |e| return diags.fail("failed to write: {t}", .{e}),
    };
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
    const target = &comp.root_mod.resolved_target.result;
    const maybe_ip: ?*InternPool = if (comp.zcu) |zcu| &zcu.intern_pool else null;
    const is_obj = comp.config.output_mode == .Obj;

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
        frag_infos.appendAssumeCapacity(.{ .id_offset = id_offset });
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

    // Resolve Zig extern navs against external objects.
    var ext_id_offsets: std.ArrayListUnmanaged(Word) = .empty;
    defer ext_id_offsets.deinit(gpa);
    try ext_id_offsets.ensureTotalCapacity(gpa, linker.external_objects.items.len);

    var unresolved_extern_count: u32 = 0;
    var resolved_ids: std.AutoArrayHashMapUnmanaged(Id, void) = .empty;
    defer resolved_ids.deinit(gpa);

    if (maybe_ip) |ip| {
        var extern_name_map: std.StringArrayHashMapUnmanaged(InternPool.Nav.Index) = .empty;
        defer extern_name_map.deinit(gpa);

        var nav_it = nav_final_ids.iterator();
        while (nav_it.next()) |entry| {
            const nav = ip.getNav(entry.key_ptr.*);
            if (!nav.resolved.?.is_extern_decl) continue;
            const name = if (nav.getExtern(ip)) |e| e.name.toSlice(ip) else nav.fqn.toSlice(ip);
            try extern_name_map.put(gpa, name, entry.key_ptr.*);
        }

        for (linker.external_objects.items) |ext_obj| {
            const id_offset = next_id - 1;
            ext_id_offsets.appendAssumeCapacity(id_offset);

            var it: BinaryModule.Instruction.Iterator = .init(ext_obj.instructions, 0);
            while (it.next()) |inst| {
                const ld = LinkageDecoration.parse(inst) orelse continue;
                if (ld.linkage_type != .@"export") continue;
                const remapped_id: Id = @enumFromInt(@intFromEnum(ld.target_id) + id_offset);

                if (extern_name_map.get(ld.name)) |nav_index| {
                    log.debug("extern resolve: '{s}' -> ext_fn_id={d}", .{ ld.name, @intFromEnum(remapped_id) });
                    nav_final_ids.getPtr(nav_index).?.* = remapped_id;
                    _ = extern_name_map.swapRemove(ld.name);
                    try resolved_ids.put(gpa, remapped_id, {});
                }
            }
            next_id += ext_obj.id_bound - 1;
        }

        unresolved_extern_count = @intCast(extern_name_map.count());
    } else {
        for (linker.external_objects.items) |ext_obj| {
            ext_id_offsets.appendAssumeCapacity(next_id - 1);
            next_id += ext_obj.id_bound - 1;
        }
    }

    var parser = BinaryModule.Parser.init(gpa) catch return error.OutOfMemory;
    defer parser.deinit();
    var sections: Sections = .{};
    defer sections.deinit(gpa);

    try mergeZigFragments(linker, gpa, &parser, &sections, frag_infos.items, &nav_final_ids, &uav_final_ids, &resolved_ids, maybe_ip);

    var has_linkage = false;
    try appendExternalObjects(linker, gpa, &parser, ext_id_offsets.items, &sections, &has_linkage, linker.fragments.count() == 0, is_obj, &resolved_ids);

    if (is_obj) {
        for (linker.entry_points.items) |ep| {
            if (ep.cc != .spirv_device) continue;
            const final_id = nav_final_ids.get(ep.nav) orelse continue;
            try sections.annotations.emit(gpa, .OpDecorate, .{
                .target = final_id,
                .decoration = .{ .linkage_attributes = .{ .name = ep.name, .linkage_type = .@"export" } },
            });
            has_linkage = true;
        }
        if (unresolved_extern_count > 0) has_linkage = true;
    }

    var capabilities_section = Section{};
    defer capabilities_section.deinit(gpa);
    var extensions_section = Section{};
    defer extensions_section.deinit(gpa);
    var memory_model_section = Section{};
    defer memory_model_section.deinit(gpa);

    try emitPreamble(
        gpa,
        target,
        has_linkage,
        &capabilities_section,
        &extensions_section,
        &memory_model_section,
    );
    try emitEntryPoints(
        linker,
        gpa,
        target,
        &sections.entry_points,
        &sections.execution_modes,
        &nav_final_ids,
        &uav_final_ids,
        &frag_infos,
    );

    const zig_packed_version = (zig_version.major << 12) | (zig_version.minor << 7) | zig_version.patch;
    if (maybe_ip) |ip| {
        try emitSourceInfo(gpa, ip, zig_packed_version, &sections.debug_strings);
    }

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

    const buffers = &[_][]const Word{
        capabilities_section.toWords(),
        extensions_section.toWords(),
        sections.ext_inst.toWords(),
        memory_model_section.toWords(),
        sections.entry_points.toWords(),
        sections.execution_modes.toWords(),
        sections.debug_strings.toWords(),
        sections.debug_names.toWords(),
        sections.annotations.toWords(),
        sections.globals.toWords(),
        sections.functions.toWords(),
    };

    var total_size: usize = 0;
    for (buffers) |buffer| total_size += buffer.len;
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
        .generator_id = (spec.zig_generator_id << 16) | zig_packed_version,
    };
}

fn mergeZigFragments(
    linker: *Linker,
    gpa: Allocator,
    parser: *BinaryModule.Parser,
    sections: *Sections,
    frag_infos: []const FragmentInfo,
    nav_final_ids: *const std.AutoHashMapUnmanaged(InternPool.Nav.Index, Id),
    uav_final_ids: *const std.AutoHashMapUnmanaged(struct { InternPool.Index, spec.StorageClass }, Id),
    resolved_ids: *const std.AutoArrayHashMapUnmanaged(Id, void),
    maybe_ip: ?*InternPool,
) error{OutOfMemory}!void {
    for (linker.fragments.values(), frag_infos) |*mir, frag_info| {
        var id_remap: std.AutoHashMapUnmanaged(Id, Id) = .empty;
        defer id_remap.deinit(gpa);

        var resolved_local_ids: std.AutoArrayHashMapUnmanaged(Id, void) = .empty;
        defer resolved_local_ids.deinit(gpa);

        for (mir.nav_refs) |ref| {
            if (nav_final_ids.get(ref.nav)) |final_id| {
                try id_remap.put(gpa, ref.local_id, final_id);
                if (maybe_ip) |ip| {
                    const nav = ip.getNav(ref.nav);
                    if (nav.resolved.?.is_extern_decl and resolved_ids.contains(final_id)) {
                        try resolved_local_ids.put(gpa, ref.local_id, {});
                    }
                }
            }
        }
        for (mir.uav_refs) |ref| {
            if (uav_final_ids.get(.{ ref.val, ref.storage_class })) |final_id| {
                try id_remap.put(gpa, ref.local_id, final_id);
            }
        }

        try remapAndAppend(gpa, &sections.ext_inst, mir.extended_instruction_set, frag_info.id_offset, &id_remap, parser);
        try remapAndAppend(gpa, &sections.globals, mir.globals, frag_info.id_offset, &id_remap, parser);

        try remapFilteredInsts(gpa, &sections.functions, mir.functions, frag_info.id_offset, &id_remap, parser, &resolved_local_ids, .skip_functions);
        try remapFilteredInsts(gpa, &sections.annotations, mir.annotations, frag_info.id_offset, &id_remap, parser, &resolved_local_ids, .skip_linkage);
        try remapFilteredInsts(gpa, &sections.debug_names, mir.debug_names, frag_info.id_offset, &id_remap, parser, &resolved_local_ids, .skip_names);
        try remapAndAppend(gpa, &sections.debug_strings, mir.debug_strings, frag_info.id_offset, &id_remap, parser);
        try remapAndAppend(gpa, &sections.execution_modes, mir.execution_modes, frag_info.id_offset, &id_remap, parser);

        for (mir.entry_points) |ep| {
            try linker.entry_points.append(gpa, .{ .nav = mir.owner_nav, .name = ep.name, .cc = ep.cc });
        }
    }
}

const FilterMode = enum { skip_functions, skip_linkage, skip_names };

fn remapFilteredInsts(
    gpa: Allocator,
    dest: *Section,
    words: []const Word,
    id_offset: Word,
    id_remap: *const std.AutoHashMapUnmanaged(Id, Id),
    parser: *BinaryModule.Parser,
    skip_ids: *const std.AutoArrayHashMapUnmanaged(Id, void),
    mode: FilterMode,
) error{OutOfMemory}!void {
    if (words.len == 0) return;
    var it: BinaryModule.Instruction.Iterator = .init(words, 0);
    var skip_function = false;
    while (it.next()) |inst| {
        switch (mode) {
            .skip_functions => {
                if (inst.opcode == .OpFunction) {
                    skip_function = skip_ids.contains(@enumFromInt(inst.operands[1]));
                }
                if (skip_function) {
                    if (inst.opcode == .OpFunctionEnd) skip_function = false;
                    continue;
                }
            },
            .skip_linkage => {
                if (LinkageDecoration.parse(inst)) |ld| {
                    if (skip_ids.contains(ld.target_id)) continue;
                }
            },
            .skip_names => {
                if (inst.opcode == .OpName and inst.operands.len >= 1) {
                    if (skip_ids.contains(@enumFromInt(inst.operands[0]))) continue;
                }
            },
        }
        try remapAndAppendInst(gpa, dest, words, inst, id_offset, id_remap, parser);
    }
}

fn emitPreamble(
    gpa: Allocator,
    target: *const std.Target,
    has_linkage: bool,
    capabilities: *Section,
    extensions: *Section,
    memory_model: *Section,
) !void {
    var caps: std.EnumSet(spec.Capability) = .empty;
    var exts: std.StringHashMapUnmanaged(void) = .empty;
    defer exts.deinit(gpa);

    switch (target.os.tag) {
        .opengl, .vulkan => caps.insert(.shader),
        .opencl, .amdhsa => {
            caps.insert(.kernel);
            caps.insert(.addresses);
        },
        else => unreachable,
    }
    if (target.os.tag == .vulkan and target.cpu.arch == .spirv64) {
        caps.insert(.physical_storage_buffer_addresses);
        try exts.put(gpa, "SPV_KHR_physical_storage_buffer", {});
    }
    if (has_linkage) caps.insert(.linkage);

    inline for (@typeInfo(spec.Capability).@"enum".field_names) |cap_name| {
        if (target.cpu.has(.spirv, @field(std.Target.spirv.Feature, cap_name)))
            caps.insert(@field(spec.Capability, cap_name));
    }
    inline for (@typeInfo(spec.Extension).@"enum".field_names) |ext_name| {
        switch (@field(spec.Extension, ext_name)) {
            .v1_0, .v1_1, .v1_2, .v1_3, .v1_4, .v1_5, .v1_6 => {},
            else => if (target.cpu.has(.spirv, @field(std.Target.spirv.Feature, ext_name)))
                try exts.put(gpa, ext_name, {}),
        }
    }

    var cit = caps.iterator();
    while (cit.next()) |cap| try capabilities.emit(gpa, .OpCapability, .{ .capability = cap });
    var eit = exts.iterator();
    while (eit.next()) |e| try extensions.emit(gpa, .OpExtension, .{ .name = e.key_ptr.* });

    const addressing_model: spec.AddressingModel = switch (target.os.tag) {
        .opengl => .logical,
        .vulkan => switch (target.cpu.arch) {
            .spirv32 => .logical,
            .spirv64 => .physical_storage_buffer64,
            else => unreachable,
        },
        .opencl => switch (target.cpu.arch) {
            .spirv32 => .physical32,
            .spirv64 => .physical64,
            else => unreachable,
        },
        .amdhsa => .physical64,
        else => unreachable,
    };
    try memory_model.emit(gpa, .OpMemoryModel, .{
        .addressing_model = addressing_model,
        .memory_model = switch (target.os.tag) {
            .opencl => .open_cl,
            .vulkan, .opengl => .glsl450,
            .amdhsa => unreachable, // TODO
            else => unreachable,
        },
    });
}

fn emitEntryPoints(
    linker: *Linker,
    gpa: Allocator,
    target: *const std.Target,
    entry_points_section: *Section,
    execution_modes_section: *Section,
    nav_final_ids: *const std.AutoHashMapUnmanaged(InternPool.Nav.Index, Id),
    uav_final_ids: *const std.AutoHashMapUnmanaged(struct { InternPool.Index, spec.StorageClass }, Id),
    frag_infos: *const std.ArrayList(FragmentInfo),
) error{OutOfMemory}!void {
    for (linker.entry_points.items) |ep| {
        const final_id = nav_final_ids.get(ep.nav) orelse continue;

        var interface: std.ArrayList(Id) = .empty;
        defer interface.deinit(gpa);
        var visited: std.AutoHashMapUnmanaged(InternPool.Nav.Index, void) = .empty;
        defer visited.deinit(gpa);
        try collectEntryPointInterface(linker, ep.nav, &interface, &visited, nav_final_ids, uav_final_ids, frag_infos, gpa);

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
                    .mode = .{ .local_size = .{ .x_size = kernel.x, .y_size = kernel.y, .z_size = kernel.z } },
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
}

fn emitSourceInfo(gpa: Allocator, ip: *InternPool, version: u32, debug_strings: *Section) error{OutOfMemory}!void {
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
    try debug_strings.emit(gpa, .OpSourceExtension, .{ .extension = error_info.written() });
    try debug_strings.emit(gpa, .OpSource, .{ .source_language = .zig, .version = version, .file = null, .source = null });
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

const LinkageDecoration = struct {
    target_id: Id,
    name: []const u8,
    linkage_type: spec.LinkageType,

    fn parse(inst: BinaryModule.Instruction) ?LinkageDecoration {
        if (inst.opcode != .OpDecorate) return null;
        if (inst.operands.len < 3) return null;
        if (inst.operands[1] != @intFromEnum(spec.Decoration.linkage_attributes)) return null;
        return .{
            .target_id = @enumFromInt(inst.operands[0]),
            .name = std.mem.sliceTo(std.mem.sliceAsBytes(inst.operands[2 .. inst.operands.len - 1]), 0),
            .linkage_type = @enumFromInt(inst.operands[inst.operands.len - 1]),
        };
    }
};

const Sections = struct {
    ext_inst: Section = .{},
    globals: Section = .{},
    functions: Section = .{},
    annotations: Section = .{},
    debug_names: Section = .{},
    debug_strings: Section = .{},
    entry_points: Section = .{},
    execution_modes: Section = .{},

    fn deinit(self: *Sections, gpa: Allocator) void {
        self.ext_inst.deinit(gpa);
        self.globals.deinit(gpa);
        self.functions.deinit(gpa);
        self.annotations.deinit(gpa);
        self.debug_names.deinit(gpa);
        self.debug_strings.deinit(gpa);
        self.entry_points.deinit(gpa);
        self.execution_modes.deinit(gpa);
    }

    const SectionClass = enum { ext_inst, debug_name, debug_string, annotation, global };

    fn classifyPreambleInst(opcode: spec.Opcode) SectionClass {
        return switch (opcode) {
            .OpExtInstImport => .ext_inst,
            .OpName, .OpMemberName => .debug_name,
            .OpString => .debug_string,
            .OpDecorate,
            .OpMemberDecorate,
            .OpGroupDecorate,
            .OpGroupMemberDecorate,
            .OpDecorationGroup,
            .OpDecorateId,
            .OpDecorateString,
            .OpMemberDecorateString,
            => .annotation,
            else => .global,
        };
    }

    fn getSection(self: *Sections, class: SectionClass) *Section {
        return switch (class) {
            .ext_inst => &self.ext_inst,
            .debug_name => &self.debug_names,
            .debug_string => &self.debug_strings,
            .annotation => &self.annotations,
            .global => &self.globals,
        };
    }
};

fn appendExternalObjects(
    linker: *Linker,
    gpa: Allocator,
    parser: *BinaryModule.Parser,
    ext_id_offsets: []const Word,
    sections: *Sections,
    has_linkage: *bool,
    keep_entry_points: bool,
    is_obj: bool,
    resolved_ids: *const std.AutoArrayHashMapUnmanaged(Id, void),
) error{OutOfMemory}!void {
    var export_map: std.StringArrayHashMapUnmanaged(Id) = .empty;
    defer export_map.deinit(gpa);

    for (linker.external_objects.items, ext_id_offsets) |ext_obj, id_offset| {
        var it: BinaryModule.Instruction.Iterator = .init(ext_obj.instructions, 0);
        while (it.next()) |inst| {
            const ld = LinkageDecoration.parse(inst) orelse continue;
            if (ld.linkage_type != .@"export") continue;
            try export_map.put(gpa, ld.name, @enumFromInt(@intFromEnum(ld.target_id) + id_offset));
        }
    }

    var per_obj_remaps = try gpa.alloc(std.AutoHashMapUnmanaged(Id, Id), linker.external_objects.items.len);
    defer {
        for (per_obj_remaps) |*m| m.deinit(gpa);
        gpa.free(per_obj_remaps);
    }
    for (per_obj_remaps) |*m| m.* = .empty;

    var resolved_linkage_ids: std.AutoArrayHashMapUnmanaged(Id, void) = .empty;
    defer resolved_linkage_ids.deinit(gpa);

    for (resolved_ids.keys()) |id| {
        try resolved_linkage_ids.put(gpa, id, {});
    }

    for (linker.external_objects.items, ext_id_offsets, 0..) |ext_obj, id_offset, obj_idx| {
        var it: BinaryModule.Instruction.Iterator = .init(ext_obj.instructions, 0);
        while (it.next()) |inst| {
            const ld = LinkageDecoration.parse(inst) orelse continue;
            if (ld.linkage_type != .import) continue;
            const remapped_import: Id = @enumFromInt(@intFromEnum(ld.target_id) + id_offset);

            if (export_map.get(ld.name)) |export_id| {
                try per_obj_remaps[obj_idx].put(gpa, ld.target_id, export_id);
                try resolved_linkage_ids.put(gpa, remapped_import, {});
                try resolved_linkage_ids.put(gpa, export_id, {});
                log.debug("cross-object resolve: '{s}' import={d} -> export={d}", .{
                    ld.name, @intFromEnum(remapped_import), @intFromEnum(export_id),
                });
            } else {
                has_linkage.* = true;
            }
        }
    }

    for (linker.external_objects.items, ext_id_offsets, 0..) |ext_obj, id_offset, obj_idx| {
        var binary = parser.initFromWords(ext_obj.instructions, ext_obj.id_bound) catch
            return error.OutOfMemory;
        defer binary.deinit(gpa);

        const id_remap = &per_obj_remaps[obj_idx];

        var preamble_it: BinaryModule.Instruction.Iterator = .init(ext_obj.instructions, 0);
        while (preamble_it.next()) |inst| {
            if (inst.offset >= binary.functions_start) break;

            switch (inst.opcode) {
                .OpCapability,
                .OpExtension,
                .OpMemoryModel,
                .OpSource,
                .OpSourceExtension,
                .OpSourceContinued,
                => continue,
                .OpEntryPoint => {
                    if (keep_entry_points)
                        try remapAndAppendInst(gpa, &sections.entry_points, ext_obj.instructions, inst, id_offset, id_remap, parser);
                    continue;
                },
                .OpExecutionMode, .OpExecutionModeId => {
                    if (keep_entry_points)
                        try remapAndAppendInst(gpa, &sections.execution_modes, ext_obj.instructions, inst, id_offset, id_remap, parser);
                    continue;
                },
                else => {},
            }

            if (LinkageDecoration.parse(inst)) |ld| {
                const remapped: Id = @enumFromInt(@intFromEnum(ld.target_id) + id_offset);
                if (resolved_linkage_ids.contains(remapped)) {
                    if (ld.linkage_type == .@"export" and is_obj) {
                        has_linkage.* = true;
                    } else {
                        continue;
                    }
                }
            }

            if (inst.opcode == .OpName and inst.operands.len >= 1) {
                if (id_remap.contains(@enumFromInt(inst.operands[0]))) continue;
            }

            const dest = sections.getSection(Sections.classifyPreambleInst(inst.opcode));
            try remapAndAppendInst(gpa, dest, ext_obj.instructions, inst, id_offset, id_remap, parser);
        }

        var fn_it: BinaryModule.Instruction.Iterator = .init(ext_obj.instructions, binary.functions_start);
        var skip_function = false;
        while (fn_it.next()) |inst| {
            if (inst.opcode == .OpFunction) {
                skip_function = id_remap.contains(@enumFromInt(inst.operands[1]));
            }
            if (!skip_function) {
                try remapAndAppendInst(gpa, &sections.functions, ext_obj.instructions, inst, id_offset, id_remap, parser);
            }
            if (inst.opcode == .OpFunctionEnd) {
                skip_function = false;
            }
        }
    }
}

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

    var it: BinaryModule.Instruction.Iterator = .init(words, 0);
    while (it.next()) |inst| {
        try remapAndAppendInst(gpa, dest, words, inst, id_offset, id_remap, parser);
    }
}

fn remapAndAppendInst(
    gpa: Allocator,
    dest: *Section,
    words: []const Word,
    inst: BinaryModule.Instruction,
    id_offset: Word,
    id_remap: *const std.AutoHashMapUnmanaged(Id, Id),
    parser: *BinaryModule.Parser,
) error{OutOfMemory}!void {
    const inst_words = words[inst.offset..][0..((words[inst.offset] >> 16))];
    try dest.instructions.ensureUnusedCapacity(gpa, inst_words.len);
    const dest_start = dest.instructions.items.len;
    dest.instructions.appendSliceAssumeCapacity(inst_words);
    const inst_slice = dest.instructions.items[dest_start..][0..inst_words.len];

    const inst_spec = parser.getInstSpec(inst.opcode) orelse return;
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
