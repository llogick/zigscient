const std = @import("std");
const Allocator = std.mem.Allocator;
const Path = std.Build.Cache.Path;
const assert = std.debug.assert;
const InternPool = @import("../../InternPool.zig");
const link = @import("../../link.zig");
const Type = @import("../../Type.zig");
const Linker = @import("../Spirv.zig");
const Mir = @import("../../codegen/spirv/Mir.zig");
const spec = @import("../../codegen/spirv/spec.zig");
const Section = @import("../../codegen/spirv/Section.zig");
const zig_version = @import("builtin").zig_version;
const Id = spec.Id;
const Word = spec.Word;
const Flush = @This();

linker: *Linker,
arena: Allocator,
id_bound: Word,
navs: std.array_hash_map.Auto(InternPool.Nav.Index, Id),
symbols: std.array_hash_map.String(Symbol),
interned: std.array_hash_map.String(Id),
variables: std.array_hash_map.Auto(Id, spec.StorageClass),
function_references: std.array_hash_map.Auto(Id, []const Id),
entry_points: std.ArrayList(Mir.EntryPoint),
deps: std.ArrayList(Id),
scratch: Section,
extended_instruction_sets: Section,
object_entry_points: Section,
object_execution_modes: Section,
debug_strings: Section,
names: Section,
decorations: Section,
globals: Section,
declarations: Section,
functions: Section,

const Symbol = struct {
    id: Id,
    defined: bool,
    declaration: []const Word,
};

const Annotation = struct {
    target: Word,
    class: spec.Class,
    start: usize,
    end: usize,
};

const Input = struct {
    mir: *const Mir,
    ids: []Id,
    marks: []u32,
    mark: u32,

    fn copy(
        input: *Input,
        flush: *Flush,
        dest: *Section,
        start: usize,
        end: usize,
        result_index: ?usize,
    ) !void {
        const words = input.mir.module.instructions.items;
        try dest.ensureUnusedCapacity(flush.arena, end - start);
        for (words[start..end], start..) |word, i| {
            if (i == result_index) {
                dest.writeWord(0);
                continue;
            }
            if (!input.mir.module.ids.isSet(i)) {
                dest.writeWord(word);
                continue;
            }
            if (input.marks[word] != input.mark) {
                input.marks[word] = input.mark;
                try flush.deps.append(flush.arena, input.ids[word]);
            }
            dest.writeWord(@backingInt(input.ids[word]));
        }
    }
};

fn allocId(flush: *Flush) Id {
    const id: Id = @fromBackingInt(flush.id_bound);
    flush.id_bound += 1;
    return id;
}

fn navId(flush: *Flush, nav: InternPool.Nav.Index) !Id {
    const gop = try flush.navs.getOrPut(flush.arena, nav);
    if (!gop.found_existing) gop.value_ptr.* = flush.allocId();
    return gop.value_ptr.*;
}

pub fn emitModule(flush: *Flush, out: *Section) link.Error!void {
    const linker = flush.linker;
    const comp = linker.base.comp;
    const zcu = comp.zcu.?;
    const ip = &zcu.intern_pool;
    const gpa = comp.gpa;
    const arena = flush.arena;
    const diags = &comp.link_diags;
    const target = &comp.root_mod.resolved_target.result;
    const is_object = comp.config.output_mode == .Obj;

    for (linker.exports.keys(), linker.exports.values()) |nav_index, name| {
        if (!linker.mirs.contains(nav_index)) {
            assert(zcu.failed_codegen.contains(nav_index));
            return error.AlreadyReported;
        }

        const id = try flush.navId(nav_index);
        const nav_ty: Type = .fromInterned(ip.getNav(nav_index).resolved.?.type);
        if (nav_ty.zigTypeTag(zcu) == .@"fn") {
            const cc = nav_ty.fnCallingConvention(zcu);
            if (cc != .spirv_device) {
                try flush.entry_points.append(arena, .{
                    .id = id,
                    .name = name.toSlice(ip),
                    .cc = cc,
                });
                continue;
            }
        }
        if (!is_object) continue;

        try flush.symbols.putNoClobber(arena, name.toSlice(ip), .{
            .id = id,
            .defined = true,
            .declaration = &.{},
        });
    }

    for (linker.objects.items) |*object| {
        try flush.load(&object.mir, object.path);
    }

    const references = try zcu.resolveReferences();
    for (linker.mirs.keys(), linker.mirs.values()) |nav_index, *mir| {
        const nav = ip.getNav(nav_index);
        if (nav.getExtern(ip) != null) continue;

        const unit: InternPool.AnalUnit = switch (ip.indexToKey(nav.resolved.?.type)) {
            .func_type => .wrap(.{ .func = zcu.navValue(nav_index).toIntern() }),
            else => .wrap(.{ .nav_val = nav_index }),
        };
        if (references.contains(unit)) try flush.load(mir, null);
    }

    for (linker.mirs.keys(), linker.mirs.values()) |nav_index, *mir| {
        if (ip.getNav(nav_index).getExtern(ip) == null) continue;
        if (flush.navs.contains(nav_index)) try flush.load(mir, null);
    }

    var failed = false;
    for (flush.navs.keys()) |nav_index| {
        if (linker.mirs.contains(nav_index) or zcu.failed_codegen.contains(nav_index)) continue;
        diags.addError("undefined reference to '{f}'", .{ip.getNav(nav_index).fqn.fmt(ip)});
        failed = true;
    }
    for (flush.symbols.keys(), flush.symbols.values()) |name, symbol| {
        if (is_object) {
            try flush.decorations.emit(arena, .OpDecorate, .{
                .target = symbol.id,
                .decoration = .{ .linkage_attributes = .{
                    .name = name,
                    .linkage_type = if (symbol.defined) .@"export" else .import,
                } },
            });
        }
        if (symbol.defined) continue;
        if (!is_object or symbol.declaration.len == 0) {
            diags.addError("undefined symbol '{s}'", .{name});
            failed = true;
            continue;
        }
        const header: spec.InstructionHeader = @bitCast(symbol.declaration[0]);
        const section = if (header.opcode == .OpVariable) &flush.globals else &flush.declarations;
        try section.writeWords(arena, symbol.declaration);
    }
    if (failed) return error.AlreadyReported;

    var version: spec.Version = .{ .major = 1, .minor = 0 };
    for ([_]std.Target.spirv.Feature{
        .v1_1,
        .v1_2,
        .v1_3,
        .v1_4,
        .v1_5,
        .v1_6,
    }) |feature| {
        if (target.cpu.has(.spirv, feature)) version.minor += 1;
    }

    const zig_packed_version = (zig_version.major << 12) | (zig_version.minor << 7) | zig_version.patch;
    const header: spec.Header = .{
        .magic = spec.magic_number,
        .version = version,
        .generator = .{ .tool = spec.zig_generator_id, .version = zig_packed_version },
        .id_bound = flush.id_bound,
        .schema = 0,
    };
    try out.writeWords(gpa, @ptrCast(@alignCast(&header)));
    try flush.emitCapabilities(out);
    try out.writeWords(gpa, flush.extended_instruction_sets.instructions.items);
    try flush.emitMemoryModel(out);
    try flush.emitEntryPoints(out);
    try out.writeWords(gpa, flush.object_entry_points.instructions.items);
    try flush.emitExecutionModes(out);
    try out.writeWords(gpa, flush.object_execution_modes.instructions.items);
    try out.writeWords(gpa, flush.debug_strings.instructions.items);
    try flush.emitSourceInfo(out, zig_packed_version);
    try out.writeWords(gpa, flush.names.instructions.items);
    try out.writeWords(gpa, flush.decorations.instructions.items);
    try out.writeWords(gpa, flush.globals.instructions.items);
    try out.writeWords(gpa, flush.declarations.instructions.items);
    try out.writeWords(gpa, flush.functions.instructions.items);
}

fn load(flush: *Flush, mir: *const Mir, path: ?Path) link.Error!void {
    const comp = flush.linker.base.comp;
    const gpa = comp.gpa;
    const arena = flush.arena;
    const diags = &comp.link_diags;

    const ids = try gpa.alloc(Id, mir.id_bound);
    defer gpa.free(ids);
    ids[0] = .none;
    for (ids[1..], flush.id_bound..) |*id, i| id.* = @fromBackingInt(@intCast(i));
    flush.id_bound += mir.id_bound - 1;

    const marks = try gpa.alloc(u32, mir.id_bound);
    defer gpa.free(marks);
    @memset(marks, 0);
    var input: Input = .{ .mir = mir, .ids = ids, .marks = marks, .mark = 0 };

    var forward_pointers: std.bit_set.Dynamic = try .initEmpty(gpa, mir.id_bound);
    defer forward_pointers.deinit(gpa);
    var imports: std.array_hash_map.Auto(Word, u32) = .empty;
    defer imports.deinit(gpa);
    var annotations: std.ArrayList(Annotation) = .empty;
    defer annotations.deinit(gpa);

    for (mir.nav_refs) |ref| ids[@backingInt(ref.id)] = try flush.navId(ref.nav);
    for (mir.externs) |ext| {
        const gop = try flush.symbols.getOrPut(arena, ext.name);
        if (!gop.found_existing) gop.value_ptr.* = .{
            .id = ids[@backingInt(ext.id)],
            .defined = false,
            .declaration = &.{},
        };
        ids[@backingInt(ext.id)] = gop.value_ptr.id;
        try imports.put(gpa, @backingInt(ext.id), @intCast(gop.index));
    }

    const words = mir.module.instructions.items;
    var offset: usize = 0;
    while (offset < words.len) {
        const start = offset;
        const header: spec.InstructionHeader = @bitCast(words[start]);
        const inst = words[start..][0..header.word_count];
        offset += inst.len;

        if (header.opcode == .OpDecorate) {
            const target = inst[1];
            const decoration: spec.Decoration = @fromBackingInt(inst[2]);
            if (decoration == .linkage_attributes) {
                const parameters = inst[3..];
                const name_words = parameters[0 .. parameters.len - 1];
                const name = std.mem.sliceTo(std.mem.sliceAsBytes(name_words), 0);
                const linkage: spec.LinkageType = @fromBackingInt(parameters[parameters.len - 1]);
                const gop = try flush.symbols.getOrPut(arena, name);
                if (!gop.found_existing) gop.value_ptr.* = .{
                    .id = ids[target],
                    .defined = false,
                    .declaration = &.{},
                };

                switch (linkage) {
                    .@"export" => {
                        if (gop.value_ptr.defined) {
                            return diags.failParse(path.?, "duplicate export '{s}'", .{name});
                        }
                        gop.value_ptr.defined = true;
                    },
                    .import => try imports.put(gpa, target, @intCast(gop.index)),
                    .link_once_odr => {
                        return diags.failParse(path.?, "unsupported linkage '{t}'", .{linkage});
                    },
                }

                ids[target] = gop.value_ptr.id;
                continue;
            }
        }

        const class = header.opcode.class();
        const target: Word = switch (header.opcode) {
            .OpName, .OpMemberName => inst[1],
            .OpDecorationGroup, .OpGroupDecorate, .OpGroupMemberDecorate => {
                return diags.failParse(path.?, "decoration groups are not supported", .{});
            },
            else => if (class == .annotation) inst[1] else continue,
        };
        try annotations.append(gpa, .{
            .target = target,
            .class = class,
            .start = start,
            .end = offset,
        });
    }

    const starts = try gpa.alloc(u32, mir.id_bound + 1);
    defer gpa.free(starts);
    @memset(starts, 0);

    for (annotations.items) |annotation| starts[annotation.target + 1] += 1;
    for (1..starts.len) |i| starts[i] += starts[i - 1];

    const cursors = try gpa.dupe(u32, starts);
    defer gpa.free(cursors);
    const by_target = try gpa.alloc(u32, annotations.items.len);
    defer gpa.free(by_target);
    for (annotations.items, 0..) |annotation, i| {
        by_target[cursors[annotation.target]] = @intCast(i);
        cursors[annotation.target] += 1;
    }

    var results: std.ArrayList(Word) = .empty;
    defer results.deinit(gpa);

    offset = 0;
    while (offset < words.len) {
        const start = offset;
        const header: spec.InstructionHeader = @bitCast(words[start]);
        const inst = words[start..][0..header.word_count];
        offset += inst.len;
        input.mark += 1;
        flush.deps.clearRetainingCapacity();

        const result_index = header.opcode.resultIndex() orelse {
            switch (header.opcode) {
                .OpEntryPoint => {
                    try input.copy(flush, &flush.object_entry_points, start, offset, null);
                },
                .OpExecutionMode, .OpExecutionModeId => {
                    try input.copy(flush, &flush.object_execution_modes, start, offset, null);
                },
                .OpTypeForwardPointer => {
                    forward_pointers.set(inst[1]);
                    try input.copy(flush, &flush.globals, start, offset, null);
                },
                else => {},
            }
            continue;
        };
        const result = inst[result_index];
        results.clearRetainingCapacity();
        try results.append(gpa, result);

        var has_body = false;
        if (header.opcode == .OpFunction) {
            while (true) {
                const body: spec.InstructionHeader = @bitCast(words[offset]);
                if (body.opcode == .OpLabel) has_body = true;
                if (body.opcode.resultIndex()) |index| {
                    try results.append(gpa, words[offset + index]);
                }
                offset += body.word_count;
                if (body.opcode == .OpFunctionEnd) break;
            }
        }

        for (results.items) |own| input.marks[own] = input.mark;

        if (imports.get(result)) |symbol_index| {
            flush.scratch.reset();
            try input.copy(flush, &flush.scratch, start, offset, null);
            const declaration = try arena.dupe(Word, flush.scratch.instructions.items);
            flush.symbols.values()[symbol_index].declaration = declaration;
            continue;
        }

        switch (header.opcode) {
            .OpFunction => if (!has_body) return diags.failParse(path.?, "function declaration without linkage", .{}),
            .OpVariable => try flush.variables.put(arena, ids[result], @fromBackingInt(inst[3])),
            else => if (!forward_pointers.isSet(result)) {
                flush.scratch.reset();
                try input.copy(flush, &flush.scratch, start, offset, start + result_index);
                for (by_target[starts[result]..starts[result + 1]]) |index| {
                    const annotation = annotations.items[index];
                    if (annotation.class != .annotation) continue;
                    const target = annotation.start + 1;
                    try input.copy(flush, &flush.scratch, annotation.start, annotation.end, target);
                }

                const key = std.mem.sliceAsBytes(flush.scratch.instructions.items);
                const gop = try flush.interned.getOrPut(arena, key);
                if (gop.found_existing) {
                    ids[result] = gop.value_ptr.*;
                    continue;
                }
                gop.key_ptr.* = try arena.dupe(u8, key);
                gop.value_ptr.* = ids[result];
            },
        }

        for (results.items) |target| {
            for (by_target[starts[target]..starts[target + 1]]) |index| {
                const annotation = annotations.items[index];
                const section = switch (annotation.class) {
                    .debug => &flush.names,
                    .annotation => &flush.decorations,
                    else => unreachable,
                };
                try input.copy(flush, section, annotation.start, annotation.end, null);
            }
        }

        const section = switch (header.opcode) {
            .OpFunction => &flush.functions,
            .OpExtInstImport => &flush.extended_instruction_sets,
            .OpString => &flush.debug_strings,
            else => &flush.globals,
        };
        try input.copy(flush, section, start, offset, null);
        if (header.opcode == .OpFunction) {
            const references = try arena.dupe(Id, flush.deps.items);
            try flush.function_references.put(arena, ids[result], references);
        }
    }

    for (mir.entry_points) |entry_point| {
        try flush.entry_points.append(arena, .{
            .id = ids[@backingInt(entry_point.id)],
            .name = entry_point.name,
            .cc = entry_point.cc,
        });
    }
}

fn emitCapabilities(flush: *Flush, out: *Section) link.Error!void {
    const comp = flush.linker.base.comp;
    const target = &comp.root_mod.resolved_target.result;
    const gpa = comp.gpa;

    switch (target.os.tag) {
        .opengl, .vulkan => try out.emit(gpa, .OpCapability, .{ .capability = .shader }),
        .opencl => {
            try out.emit(gpa, .OpCapability, .{ .capability = .kernel });
            try out.emit(gpa, .OpCapability, .{ .capability = .addresses });
        },
        else => unreachable,
    }

    if (target.cpu.arch == .spirv64) {
        if (!target.cpu.has(.spirv, .int64)) {
            try out.emit(gpa, .OpCapability, .{ .capability = .int64 });
        }
        if (target.os.tag == .vulkan) {
            try out.emit(gpa, .OpCapability, .{ .capability = .physical_storage_buffer_addresses });
        }
    }

    if (comp.config.output_mode == .Obj and flush.symbols.count() > 0) {
        try out.emit(gpa, .OpCapability, .{ .capability = .linkage });
    }

    inline for (@typeInfo(spec.Capability).@"enum".field_names) |name| {
        if (@hasField(std.Target.spirv.Feature, name)) {
            const feature = @field(std.Target.spirv.Feature, name);
            if (target.cpu.has(.spirv, feature)) {
                try out.emit(gpa, .OpCapability, .{ .capability = @field(spec.Capability, name) });
            }
        }
    }

    if (target.cpu.arch == .spirv64 and target.os.tag == .vulkan) {
        try out.emit(gpa, .OpExtension, .{ .name = "SPV_KHR_physical_storage_buffer" });
    }

    inline for (@typeInfo(spec.Extension).@"enum".field_names) |name| {
        if (comptime std.mem.startsWith(u8, name, "v1_")) continue;
        if (@hasField(std.Target.spirv.Feature, name)) {
            const feature = @field(std.Target.spirv.Feature, name);
            if (target.cpu.has(.spirv, feature)) try out.emit(gpa, .OpExtension, .{ .name = name });
        }
    }
}

fn emitMemoryModel(flush: *Flush, out: *Section) link.Error!void {
    const comp = flush.linker.base.comp;
    const target = &comp.root_mod.resolved_target.result;
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
        else => unreachable,
    };
    try out.emit(comp.gpa, .OpMemoryModel, .{
        .addressing_model = addressing_model,
        .memory_model = switch (target.os.tag) {
            .opencl => .open_cl,
            .vulkan, .opengl => .glsl450,
            else => unreachable,
        },
    });
}

fn emitEntryPoints(flush: *Flush, out: *Section) link.Error!void {
    const comp = flush.linker.base.comp;
    const gpa = comp.gpa;
    const arena = flush.arena;
    const target = &comp.root_mod.resolved_target.result;
    const v1_4 = target.cpu.has(.spirv, .v1_4);

    var visited: std.bit_set.Dynamic = try .initEmpty(arena, flush.id_bound);
    var pending: std.ArrayList(Id) = .empty;
    var interface: std.ArrayList(Id) = .empty;
    for (flush.entry_points.items) |entry_point| {
        const execution_model: spec.ExecutionModel = switch (entry_point.cc) {
            .spirv_kernel => if (target.os.tag == .opencl) .kernel else .gl_compute,
            .spirv_vertex => .vertex,
            .spirv_fragment => .fragment,
            .spirv_task => .task_ext,
            .spirv_mesh => .mesh_ext,
            else => unreachable,
        };

        visited.unsetAll();
        interface.clearRetainingCapacity();
        try pending.append(arena, entry_point.id);
        while (pending.pop()) |id| {
            if (visited.isSet(@backingInt(id))) continue;
            visited.set(@backingInt(id));
            if (flush.variables.get(id)) |storage_class| {
                if (storage_class == .function) continue;
                if (!v1_4 and storage_class != .input and storage_class != .output) continue;
                try interface.append(arena, id);
            } else if (flush.function_references.get(id)) |references| {
                try pending.appendSlice(arena, references);
            }
        }

        try out.emit(gpa, .OpEntryPoint, .{
            .execution_model = execution_model,
            .entry_point = entry_point.id,
            .name = entry_point.name,
            .interface = interface.items,
        });
    }
}

fn emitExecutionModes(flush: *Flush, out: *Section) link.Error!void {
    const comp = flush.linker.base.comp;
    const gpa = comp.gpa;
    const target = &comp.root_mod.resolved_target.result;

    for (flush.entry_points.items) |entry_point| switch (entry_point.cc) {
        .spirv_kernel, .spirv_task => |kernel| {
            try out.emit(gpa, .OpExecutionMode, .{
                .entry_point = entry_point.id,
                .mode = .{ .local_size = .{
                    .x_size = kernel.x,
                    .y_size = kernel.y,
                    .z_size = kernel.z,
                } },
            });
        },
        .spirv_fragment => |fragment| {
            try out.emit(gpa, .OpExecutionMode, .{
                .entry_point = entry_point.id,
                .mode = if (target.os.tag == .vulkan) .origin_upper_left else .origin_lower_left,
            });
            if (fragment.pixel_centered_integer) {
                try out.emit(gpa, .OpExecutionMode, .{
                    .entry_point = entry_point.id,
                    .mode = .pixel_center_integer,
                });
            }
            if (fragment.depth_assumption != .none) {
                try out.emit(gpa, .OpExecutionMode, .{
                    .entry_point = entry_point.id,
                    .mode = switch (fragment.depth_assumption) {
                        .none => unreachable,
                        .greater => .depth_greater,
                        .less => .depth_less,
                        .unchanged => .depth_unchanged,
                    },
                });
            }
        },
        .spirv_mesh => |mesh| {
            try out.emit(gpa, .OpExecutionMode, .{
                .entry_point = entry_point.id,
                .mode = .{ .output_vertices = .{ .vertex_count = mesh.max_vertices } },
            });
            try out.emit(gpa, .OpExecutionMode, .{
                .entry_point = entry_point.id,
                .mode = .{ .output_primitives_ext = .{ .primitive_count = mesh.max_primitives } },
            });
            try out.emit(gpa, .OpExecutionMode, .{
                .entry_point = entry_point.id,
                .mode = .{ .local_size = .{
                    .x_size = mesh.x,
                    .y_size = mesh.y,
                    .z_size = mesh.z,
                } },
            });
            try out.emit(gpa, .OpExecutionMode, .{
                .entry_point = entry_point.id,
                .mode = switch (mesh.stage_output) {
                    .output_points => .output_points,
                    .output_lines => .output_lines_ext,
                    .output_triangles => .output_triangles_ext,
                },
            });
        },
        else => {},
    };
}

fn emitSourceInfo(flush: *Flush, out: *Section, version: u32) link.Error!void {
    const comp = flush.linker.base.comp;
    const gpa = comp.gpa;
    const zcu = comp.zcu orelse return;
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

    try out.emit(gpa, .OpSourceExtension, .{ .extension = error_info.written() });
    try out.emit(gpa, .OpSource, .{
        .source_language = .zig,
        .version = version,
        .file = null,
        .source = null,
    });
}
