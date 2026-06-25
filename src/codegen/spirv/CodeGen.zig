// Compilation
pt: Zcu.PerThread,
zcu: *Zcu,
gpa: Allocator,
arena: Allocator,
air: Air,
liveness: Air.Liveness,
owner_nav: InternPool.Nav.Index,
base_line: u32,

// Module-level output (accumulated across the nav's codegen)
next_result_id: Word = 1,
decls: std.ArrayList(Decl) = .empty,
decl_deps: std.ArrayList(Decl.Index) = .empty,
nav_link: std.AutoHashMapUnmanaged(InternPool.Nav.Index, Decl.Index) = .empty,
uav_link: std.AutoHashMapUnmanaged(struct { InternPool.Index, spec.StorageClass }, Decl.Index) = .empty,
entry_points: std.array_hash_map.Auto(Id, EntryPoint) = .empty,
error_buffer: ?Decl.Index = null,
struct_types: std.array_hash_map.Custom(StructType, Id, StructType.HashContext, true) = .empty,
builtins: std.AutoHashMapUnmanaged(struct { spec.BuiltIn, spec.StorageClass }, Decl.Index) = .empty,
sections: struct {
    // Module layout, according to SPIR-V Spec section 2.4, "Logical Layout of a Module".
    extended_instruction_set: Section = .{},
    memory_model: Section = .{},
    execution_modes: Section = .{},
    debug_strings: Section = .{},
    debug_names: Section = .{},
    annotations: Section = .{},
    globals: Section = .{},
    functions: Section = .{},
} = .{},

// Per-function state (reset between top-level genNav calls)
prologue: Section = .{},
body: Section = .{},
args: std.ArrayList(Id) = .empty,
next_arg_index: u32 = 0,
block_stack: std.ArrayList(*Block) = .empty,
block_label: Id = .none,
/// Whether the current block has been terminated by a terminator
/// instruction (e.g. OpKill from inline assembly). When true, no further
/// branch instructions should be emitted for the current block.
block_terminated: bool = false,
block_results: std.AutoHashMapUnmanaged(Air.Inst.Index, Id) = .empty,
inst_results: std.AutoHashMapUnmanaged(Air.Inst.Index, Id) = .empty,
tracked_allocas: std.AutoHashMapUnmanaged(Id, ?Id) = .empty,
loop_switches: std.AutoHashMapUnmanaged(Air.Inst.Index, LoopSwitch) = .empty,
id_scratch: std.ArrayList(Id) = .empty,

const big_int_bits = @bitSizeOf(u32);

/// Data can be lowered into in two basic representations: indirect, which is when
/// a type is stored in memory, and direct, which is how a type is stored when its
/// a direct SPIR-V value.
pub const Repr = enum {
    /// A SPIR-V value as it would be used in operations.
    direct,
    /// A SPIR-V value as it is stored in memory.
    indirect,
};

/// A function or global, tracked here so the linker can order globals and build
/// per-entry-point interface lists.
pub const Decl = struct {
    pub const Index = enum(u32) { _ };
    pub const Kind = enum { func, global, invocation_global };

    kind: Kind,
    /// Result-id of the associated OpFunction / OpVariable / InvocationGlobal.
    result_id: Id,
    /// Range into `decl_deps` for this decl's dependencies.
    begin_dep: usize = 0,
    end_dep: usize = 0,
    /// Whether an extern-function stub has been emitted.
    has_extern_stub: bool = false,
};

pub const EntryPoint = struct {
    decl_index: Decl.Index,
    name: []const u8,
    cc: std.builtin.CallingConvention,
};

const StructType = struct {
    fields: []const Id,
    ip_index: InternPool.Index,

    const HashContext = struct {
        pub fn hash(_: @This(), ty: StructType) u32 {
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(std.mem.sliceAsBytes(ty.fields));
            hasher.update(std.mem.asBytes(&ty.ip_index));
            return @truncate(hasher.final());
        }

        pub fn eql(_: @This(), a: StructType, b: StructType, _: usize) bool {
            return a.ip_index == b.ip_index and std.mem.eql(Id, a.fields, b.fields);
        }
    };
};

pub fn legalizeFeatures(_: *const std.Target) *const Air.Legalize.Features {
    return comptime &.initMany(&.{
        .expand_int_cast_safe,
        .expand_int_from_float_safe,
        .expand_int_from_float_optimized_safe,
        .expand_add_safe,
        .expand_sub_safe,
        .expand_mul_safe,
    });
}

const LoopSwitch = struct { cond_var: Id, continue_label: Id };

/// Pointer-typed AIR refs should resolve through `resolvePtr` to handle the
/// `tracked_allocas` case explicitly at every use site.
const Ptr = union(enum) {
    id: Id,
    /// Function-local pointer whose value lives in `tracked_allocas` rather
    /// than a real OpVariable. `slot` is the current pointee value.
    tracked: struct { id: Id, slot: *?Id },
};

/// Tracks how control flow leaves a Zig `block` under SPIR-V's structured
/// control flow rules.
const Block = union(enum) {
    const Incoming = struct {
        src_label: Id,
        /// Block index (u32) that control flow should jump to next.
        next_block: Id,
    };

    const SelectionMerge = struct {
        incoming: Incoming,
        /// Label of the cond_br's merge block (undefined for top-of-stack).
        merge_block: Id,
    };

    /// Selection blocks can't use early exits. Closing requires a "merge ladder"
    /// of nested OpSelectionMerge instructions, one per pending merge.
    selection: struct {
        merge_stack: std.ArrayList(SelectionMerge) = .empty,
    },
    /// Loop blocks early-exit by jumping to the loop merge label.
    loop: struct {
        merges: std.ArrayList(Incoming) = .empty,
        merge_block: Id,
    },

    fn deinit(block: *Block, gpa: Allocator) void {
        switch (block.*) {
            .selection => |*merge| merge.merge_stack.deinit(gpa),
            .loop => |*merge| merge.merges.deinit(gpa),
        }
        block.* = undefined;
    }
};

pub fn deinit(cg: *CodeGen) void {
    const gpa = cg.gpa;
    cg.block_stack.deinit(gpa);
    cg.block_results.deinit(gpa);
    cg.args.deinit(gpa);
    cg.tracked_allocas.deinit(gpa);
    cg.inst_results.deinit(gpa);
    cg.loop_switches.deinit(gpa);
    cg.id_scratch.deinit(gpa);
    cg.prologue.deinit(gpa);
    cg.body.deinit(gpa);

    cg.nav_link.deinit(gpa);
    cg.uav_link.deinit(gpa);

    cg.sections.extended_instruction_set.deinit(gpa);
    cg.sections.memory_model.deinit(gpa);
    cg.sections.execution_modes.deinit(gpa);
    cg.sections.debug_strings.deinit(gpa);
    cg.sections.debug_names.deinit(gpa);
    cg.sections.annotations.deinit(gpa);
    cg.sections.globals.deinit(gpa);
    cg.sections.functions.deinit(gpa);

    cg.struct_types.deinit(gpa);
    cg.builtins.deinit(gpa);

    cg.decls.deinit(gpa);
    cg.decl_deps.deinit(gpa);
    cg.entry_points.deinit(gpa);
}

pub fn generate(
    _: *link.File,
    pt: Zcu.PerThread,
    func_index: InternPool.Index,
    air: *const Air,
    liveness: *const ?Air.Liveness,
) codegen.Error!Mir {
    const zcu = pt.zcu;
    const gpa = zcu.gpa;
    const nav = zcu.funcInfo(func_index).owner_nav;

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    var cg: CodeGen = .{
        .pt = pt,
        .gpa = gpa,
        .arena = arena.allocator(),
        .zcu = zcu,
        .air = air.*,
        .liveness = liveness.*.?,
        .owner_nav = nav,
        .base_line = zcu.navSrcLine(nav),
    };
    defer cg.deinit();

    cg.genNav(true) catch |err| switch (err) {
        error.AlreadyReported => return error.AlreadyReported,
        error.OutOfMemory => return error.OutOfMemory,
    };

    return cg.serializeToMir(gpa);
}

pub fn generateNav(
    pt: Zcu.PerThread,
    nav_index: InternPool.Nav.Index,
) codegen.Error!Mir {
    const zcu = pt.zcu;
    const gpa = zcu.gpa;

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    var cg: CodeGen = .{
        .pt = pt,
        .gpa = gpa,
        .arena = arena.allocator(),
        .zcu = zcu,
        .air = undefined,
        .liveness = undefined,
        .owner_nav = nav_index,
        .base_line = zcu.navSrcLine(nav_index),
    };
    defer cg.deinit();

    cg.genNav(false) catch |err| switch (err) {
        error.AlreadyReported => return error.AlreadyReported,
        error.OutOfMemory => return error.OutOfMemory,
    };

    return cg.serializeToMir(gpa);
}

fn serializeToMir(cg: *CodeGen, gpa: Allocator) codegen.Error!Mir {
    const owner_entry = cg.nav_link.get(cg.owner_nav);
    const owner_decl_index = owner_entry orelse return .{
        .id_bound = cg.next_result_id,
        .owner_nav = cg.owner_nav,
        .kind = .func,
        .decl_result_id = .none,
        .extended_instruction_set = &.{},
        .globals = &.{},
        .functions = &.{},
        .annotations = &.{},
        .debug_names = &.{},
        .debug_strings = &.{},
        .execution_modes = &.{},
        .nav_refs = &.{},
        .uav_refs = &.{},
        .decl_deps = &.{},
        .internal_globals = &.{},
        .entry_points = &.{},
    };

    const owner_decl = cg.declPtr(owner_decl_index);

    var nav_refs: std.ArrayList(Mir.NavRef) = .empty;
    defer nav_refs.deinit(gpa);
    var nav_it = cg.nav_link.iterator();
    while (nav_it.next()) |entry| {
        if (entry.key_ptr.* == cg.owner_nav) continue;
        const decl = cg.declPtr(entry.value_ptr.*);
        try nav_refs.append(gpa, .{
            .local_id = decl.result_id,
            .nav = entry.key_ptr.*,
            .kind = decl.kind,
        });
    }

    var uav_refs: std.ArrayList(Mir.UavRef) = .empty;
    defer uav_refs.deinit(gpa);
    var uav_it = cg.uav_link.iterator();
    while (uav_it.next()) |entry| {
        const decl = cg.declPtr(entry.value_ptr.*);
        try uav_refs.append(gpa, .{
            .local_id = decl.result_id,
            .val = entry.key_ptr.*[0],
            .storage_class = entry.key_ptr.*[1],
            .kind = decl.kind,
        });
    }

    var decl_deps: std.ArrayList(Mir.DeclDep) = .empty;
    defer decl_deps.deinit(gpa);
    var internal_globals: std.ArrayList(Id) = .empty;
    defer internal_globals.deinit(gpa);

    const deps = cg.decl_deps.items[owner_decl.begin_dep..owner_decl.end_dep];
    for (deps) |dep_index| {
        const dep_decl = cg.declPtr(dep_index);
        var found = false;
        nav_it.index = 0;
        while (nav_it.next()) |entry| {
            if (entry.value_ptr.* == dep_index) {
                try decl_deps.append(gpa, .{
                    .kind = dep_decl.kind,
                    .nav = entry.key_ptr.*,
                });
                found = true;
                break;
            }
        }
        if (!found and dep_decl.kind == .global) {
            try internal_globals.append(gpa, dep_decl.result_id);
        }
    }

    var ep_list: std.ArrayList(Mir.EntryPoint) = .empty;
    defer ep_list.deinit(gpa);
    var ep_it = cg.entry_points.iterator();
    while (ep_it.next()) |entry| {
        const ep = entry.value_ptr;
        const ep_decl = cg.declPtr(ep.decl_index);
        try ep_list.append(gpa, .{
            .local_id = ep_decl.result_id,
            .name = try gpa.dupe(u8, ep.name),
            .cc = ep.cc,
        });
    }

    return .{
        .id_bound = cg.next_result_id,
        .owner_nav = cg.owner_nav,
        .kind = owner_decl.kind,
        .decl_result_id = owner_decl.result_id,
        .extended_instruction_set = try cg.sections.extended_instruction_set.instructions.toOwnedSlice(gpa),
        .globals = try cg.sections.globals.instructions.toOwnedSlice(gpa),
        .functions = try cg.sections.functions.instructions.toOwnedSlice(gpa),
        .annotations = try cg.sections.annotations.instructions.toOwnedSlice(gpa),
        .debug_names = try cg.sections.debug_names.instructions.toOwnedSlice(gpa),
        .debug_strings = try cg.sections.debug_strings.instructions.toOwnedSlice(gpa),
        .execution_modes = try cg.sections.execution_modes.instructions.toOwnedSlice(gpa),
        .nav_refs = try nav_refs.toOwnedSlice(gpa),
        .uav_refs = try uav_refs.toOwnedSlice(gpa),
        .decl_deps = try decl_deps.toOwnedSlice(gpa),
        .internal_globals = try internal_globals.toOwnedSlice(gpa),
        .entry_points = try ep_list.toOwnedSlice(gpa),
    };
}

fn typeOf(cg: *CodeGen, inst: Air.Inst.Ref) Type {
    const zcu = cg.zcu;
    return cg.air.typeOf(inst, &zcu.intern_pool);
}

fn typeOfIndex(cg: *CodeGen, inst: Air.Inst.Index) Type {
    const zcu = cg.zcu;
    return cg.air.typeOfIndex(inst, &zcu.intern_pool);
}

/// Does not generate the nav.
pub fn resolveNav(cg: *CodeGen, ip: *InternPool, nav_index: InternPool.Nav.Index) !Decl.Index {
    const entry = try cg.nav_link.getOrPut(cg.gpa, nav_index);
    if (!entry.found_existing) {
        const nav = ip.getNav(nav_index);
        // TODO: Extern fn?
        const kind: Decl.Kind = if (ip.isFunctionType(nav.resolved.?.type))
            .func
        else switch (nav.resolved.?.@"addrspace") {
            .generic => .invocation_global,
            else => .global,
        };
        entry.value_ptr.* = try cg.allocDecl(kind);
    }

    return entry.value_ptr.*;
}

pub fn allocIds(cg: *CodeGen, n: u32) spec.IdRange {
    defer cg.next_result_id += n;
    return .{ .base = cg.next_result_id, .len = n };
}

pub fn allocId(cg: *CodeGen) Id {
    return cg.allocIds(1).at(0);
}

pub fn idBound(cg: *const CodeGen) Word {
    return cg.next_result_id;
}

pub fn addEntryPointDeps(
    cg: *CodeGen,
    decl_index: Decl.Index,
    seen: *std.bit_set.Dynamic,
    interface: *std.array_list.Managed(Id),
) !void {
    const decl = cg.declPtr(decl_index);
    const deps = cg.decl_deps.items[decl.begin_dep..decl.end_dep];

    if (seen.isSet(@intFromEnum(decl_index))) {
        return;
    }

    seen.set(@intFromEnum(decl_index));

    if (decl.kind == .global) {
        try interface.append(decl.result_id);
    }

    for (deps) |dep| {
        try cg.addEntryPointDeps(dep, seen, interface);
    }
}

pub fn importInstructionSet(cg: *CodeGen, set: spec.InstructionSet) !Id {
    assert(set != .core);
    const result_id = cg.allocId();
    try cg.sections.extended_instruction_set.emit(cg.gpa, .OpExtInstImport, .{
        .id_result = result_id,
        .name = @tagName(set),
    });
    return result_id;
}

pub fn boolType(cg: *CodeGen) !Id {
    const result_id = cg.allocId();
    try cg.sections.globals.emit(cg.gpa, .OpTypeBool, .{
        .id_result = result_id,
    });
    return result_id;
}

pub fn voidType(cg: *CodeGen) !Id {
    const result_id = cg.allocId();
    try cg.sections.globals.emit(cg.gpa, .OpTypeVoid, .{
        .id_result = result_id,
    });
    try cg.debugName(result_id, "void");
    return result_id;
}

pub fn opaqueType(cg: *CodeGen, name: []const u8) !Id {
    const result_id = cg.allocId();
    try cg.sections.globals.emit(cg.gpa, .OpTypeOpaque, .{
        .id_result = result_id,
        .literal_string = name,
    });
    try cg.debugName(result_id, name);
    return result_id;
}

pub fn backingIntBits(cg: *const CodeGen, bits: u16) struct { u16, bool } {
    assert(bits != 0);
    const target = cg.zcu.getTarget();
    const ints = [_]struct { bits: u16, enabled: bool }{
        .{ .bits = 8, .enabled = target.cpu.has(.spirv, .int8) },
        .{ .bits = 16, .enabled = target.cpu.has(.spirv, .int16) },
        .{ .bits = 32, .enabled = true },
        .{ .bits = 64, .enabled = target.cpu.has(.spirv, .int64) or target.cpu.arch == .spirv64 },
    };

    for (ints) |int| {
        if (bits <= int.bits and int.enabled) return .{ int.bits, false };
    }

    return .{ std.mem.alignForward(u16, bits, big_int_bits), true };
}

pub fn intType(cg: *CodeGen, signedness: std.lang.Signedness, bits: u16) !Id {
    assert(bits > 0);

    const target = cg.zcu.getTarget();
    const actual_signedness = switch (target.os.tag) {
        // Kernel only supports unsigned ints.
        .opencl, .amdhsa => .unsigned,
        else => signedness,
    };
    const backing_bits, const big_int = cg.backingIntBits(bits);
    if (big_int) {
        const u32_ty = try cg.intType(.unsigned, 32);
        const len_id = cg.allocId();
        try cg.sections.globals.emit(cg.gpa, .OpConstant, .{
            .id_result_type = u32_ty,
            .id_result = len_id,
            .value = .{ .uint32 = backing_bits / big_int_bits },
        });
        return cg.arrayType(len_id, u32_ty);
    }

    const result_id = cg.allocId();
    try cg.sections.globals.emit(cg.gpa, .OpTypeInt, .{
        .id_result = result_id,
        .width = backing_bits,
        .signedness = switch (actual_signedness) {
            .signed => 1,
            .unsigned => 0,
        },
    });
    switch (actual_signedness) {
        .signed => try cg.debugNameFmt(result_id, "i{}", .{backing_bits}),
        .unsigned => try cg.debugNameFmt(result_id, "u{}", .{backing_bits}),
    }
    return result_id;
}

pub fn floatType(cg: *CodeGen, bits: u16) !Id {
    assert(bits > 0);
    const result_id = cg.allocId();
    try cg.sections.globals.emit(cg.gpa, .OpTypeFloat, .{
        .id_result = result_id,
        .width = bits,
    });
    try cg.debugNameFmt(result_id, "f{}", .{bits});
    return result_id;
}

pub fn vectorType(cg: *CodeGen, len: u32, child_ty_id: Id) !Id {
    const result_id = cg.allocId();
    try cg.sections.globals.emit(cg.gpa, .OpTypeVector, .{
        .id_result = result_id,
        .component_type = child_ty_id,
        .component_count = len,
    });
    return result_id;
}

pub fn arrayType(cg: *CodeGen, len_id: Id, child_ty_id: Id) !Id {
    const result_id = cg.allocId();
    try cg.sections.globals.emit(cg.gpa, .OpTypeArray, .{
        .id_result = result_id,
        .element_type = child_ty_id,
        .length = len_id,
    });
    return result_id;
}

pub fn ptrType(cg: *CodeGen, child_ty_id: Id, storage_class: spec.StorageClass) !Id {
    const result_id = cg.allocId();
    try cg.sections.globals.emit(cg.gpa, .OpTypePointer, .{
        .id_result = result_id,
        .storage_class = storage_class,
        .type = child_ty_id,
    });
    return result_id;
}

pub fn structType(
    cg: *CodeGen,
    types: []const Id,
    maybe_names: ?[]const []const u8,
    ip_index: InternPool.Index,
) !Id {
    const actual_ip_index = if (cg.zcu.comp.config.root_strip) .none else ip_index;

    if (cg.struct_types.get(.{ .fields = types, .ip_index = actual_ip_index })) |id| return id;
    const result_id = cg.allocId();
    const types_dup = try cg.arena.dupe(Id, types);
    try cg.sections.globals.emit(cg.gpa, .OpTypeStruct, .{
        .id_result = result_id,
        .id_ref = types_dup,
    });

    if (maybe_names) |names| {
        assert(names.len == types.len);
        for (names, 0..) |name, i| {
            try cg.memberDebugName(result_id, @intCast(i), name);
        }
    }

    try cg.struct_types.put(
        cg.gpa,
        .{ .fields = types_dup, .ip_index = actual_ip_index },
        result_id,
    );
    return result_id;
}

pub fn functionType(cg: *CodeGen, return_ty_id: Id, param_type_ids: []const Id) !Id {
    const result_id = cg.allocId();
    try cg.sections.globals.emit(cg.gpa, .OpTypeFunction, .{
        .id_result = result_id,
        .return_type = return_ty_id,
        .id_ref_2 = param_type_ids,
    });
    return result_id;
}

pub fn constUndef(cg: *CodeGen, ty_id: Id) !Id {
    const result_id = cg.allocId();
    try cg.sections.globals.emit(cg.gpa, .OpUndef, .{
        .id_result_type = ty_id,
        .id_result = result_id,
    });
    return result_id;
}

pub fn constNull(cg: *CodeGen, ty_id: Id) !Id {
    const result_id = cg.allocId();
    try cg.sections.globals.emit(cg.gpa, .OpConstantNull, .{
        .id_result_type = ty_id,
        .id_result = result_id,
    });
    return result_id;
}

pub fn decorate(
    cg: *CodeGen,
    target: Id,
    decoration: spec.Decoration.Extended,
) !void {
    try cg.sections.annotations.emit(cg.gpa, .OpDecorate, .{
        .target = target,
        .decoration = decoration,
    });
}

pub fn decorateMember(
    cg: *CodeGen,
    structure_type: Id,
    member: u32,
    decoration: spec.Decoration.Extended,
) !void {
    try cg.sections.annotations.emit(cg.gpa, .OpMemberDecorate, .{
        .structure_type = structure_type,
        .member = member,
        .decoration = decoration,
    });
}

pub fn allocDecl(cg: *CodeGen, kind: Decl.Kind) !Decl.Index {
    try cg.decls.append(cg.gpa, .{
        .kind = kind,
        .result_id = cg.allocId(),
    });

    return @as(Decl.Index, @enumFromInt(@as(u32, @intCast(cg.decls.items.len - 1))));
}

pub fn declPtr(cg: *CodeGen, index: Decl.Index) *Decl {
    return &cg.decls.items[@intFromEnum(index)];
}

pub fn debugName(cg: *CodeGen, target: Id, name: []const u8) !void {
    if (cg.zcu.comp.config.root_strip) return;
    try cg.sections.debug_names.emit(cg.gpa, .OpName, .{
        .target = target,
        .name = name,
    });
}

pub fn debugNameFmt(cg: *CodeGen, target: Id, comptime fmt: []const u8, args: anytype) !void {
    if (cg.zcu.comp.config.root_strip) return;
    const name = try std.fmt.allocPrint(cg.gpa, fmt, args);
    defer cg.gpa.free(name);
    try cg.debugName(target, name);
}

pub fn memberDebugName(cg: *CodeGen, target: Id, member: u32, name: []const u8) !void {
    if (cg.zcu.comp.config.root_strip) return;
    try cg.sections.debug_names.emit(cg.gpa, .OpMemberName, .{
        .type = target,
        .member = member,
        .name = name,
    });
}

pub fn storageClass(cg: *const CodeGen, as: std.lang.AddressSpace) spec.StorageClass {
    const target = cg.zcu.getTarget();
    return switch (as) {
        .generic => .function,
        .global => switch (target.os.tag) {
            .opencl, .amdhsa => .cross_workgroup,
            else => .storage_buffer,
        },
        .push_constant => .push_constant,
        .output => .output,
        .uniform => .uniform,
        .storage_buffer => .storage_buffer,
        .physical_storage_buffer => .physical_storage_buffer,
        .constant => .uniform_constant,
        .shared => .workgroup,
        .local => .function,
        .input => .input,
        .gs,
        .fs,
        .ss,
        .far,
        .param,
        .flash,
        .flash1,
        .flash2,
        .flash3,
        .flash4,
        .flash5,
        .cog,
        .lut,
        .hub,
        .externref,
        .funcref,
        => unreachable,
    };
}

const Error = error{ AlreadyReported, OutOfMemory };

pub fn genNav(cg: *CodeGen, do_codegen: bool) Error!void {
    const gpa = cg.gpa;
    const zcu = cg.zcu;
    const ip = &zcu.intern_pool;
    const target = zcu.getTarget();

    const nav = ip.getNav(cg.owner_nav);
    const val = zcu.navValue(cg.owner_nav);
    const ty = val.typeOf(zcu);

    if (!do_codegen and !ty.hasRuntimeBits(zcu)) {
        const child_ty = if (ty.zigTypeTag(zcu) == .pointer) ty.childType(zcu) else ty;
        if (child_ty.zigTypeTag(zcu) != .spirv) return;
    }

    const spv_decl_index = try cg.resolveNav(ip, cg.owner_nav);
    const decl = cg.declPtr(spv_decl_index);
    const result_id = decl.result_id;
    decl.begin_dep = cg.decl_deps.items.len;

    switch (decl.kind) {
        .func => {
            if (nav.resolved.?.is_extern_decl) {
                _ = try cg.resolveType(ty, .direct);
                try emitExternFnStub(cg, nav, decl, ty);
                decl.end_dep = cg.decl_deps.items.len;
                return;
            }

            const fn_info = zcu.typeToFunc(ty).?;
            const return_ty_id = try cg.resolveFnReturnType(.fromInterned(fn_info.return_type));
            const is_test = zcu.test_functions.contains(cg.owner_nav);

            const func_result_id = if (is_test) cg.allocId() else result_id;
            const prototype_ty_id = try cg.resolveType(ty, .direct);
            try cg.prologue.emit(gpa, .OpFunction, .{
                .id_result_type = return_ty_id,
                .id_result = func_result_id,
                .function_type = prototype_ty_id,
                // Note: the backend will never be asked to generate an inline function
                // (this is handled in sema), so we don't need to set function_control here.
                .function_control = .{},
            });

            try cg.args.ensureUnusedCapacity(gpa, fn_info.param_types.len);
            for (fn_info.param_types.get(ip)) |param_ty_index| {
                const param_ty: Type = .fromInterned(param_ty_index);
                if (!param_ty.hasRuntimeBits(zcu)) continue;

                const param_type_id = try cg.resolveType(param_ty, .direct);
                const arg_result_id = cg.allocId();
                try cg.prologue.emit(gpa, .OpFunctionParameter, .{
                    .id_result_type = param_type_id,
                    .id_result = arg_result_id,
                });
                cg.args.appendAssumeCapacity(arg_result_id);
            }

            // TODO: This could probably be done in a better way...
            const root_block_id = cg.allocId();

            // The root block of a function declaration should appear before OpVariable instructions,
            // so it is generated into the function's prologue.
            try cg.prologue.emit(gpa, .OpLabel, .{
                .id_result = root_block_id,
            });
            cg.block_label = root_block_id;

            const main_body = cg.air.getMainBody();
            _ = try cg.genStructuredBody(.selection, main_body);
            // We always expect paths to here to end, but we still need the block
            // to act as a dummy merge block.
            try cg.body.emit(gpa, .OpUnreachable, {});
            try cg.body.emit(gpa, .OpFunctionEnd, {});
            // Append the actual code into the functions section.
            try cg.sections.functions.append(gpa, cg.prologue);
            try cg.sections.functions.append(gpa, cg.body);

            // Temporarily generate a test kernel declaration if this is a test function.
            if (is_test) {
                try cg.generateTestEntryPoint(nav.fqn.toSlice(ip), spv_decl_index, func_result_id);
            }

            try cg.debugName(func_result_id, nav.fqn.toSlice(ip));
        },
        .global => {
            const key = ip.indexToKey(val.toIntern()).@"extern";

            const storage_class = cg.storageClass(nav.resolved.?.@"addrspace");
            assert(storage_class != .generic); // These should be instance globals

            const ty_id = try cg.resolveType(ty, .indirect);
            const ptr_ty_id = try cg.ptrType(ty_id, storage_class);

            try cg.sections.globals.emit(gpa, .OpVariable, .{
                .id_result_type = ptr_ty_id,
                .id_result = result_id,
                .storage_class = storage_class,
            });

            switch (target.os.tag) {
                .vulkan, .opengl => {
                    switch (storage_class) {
                        .uniform, .push_constant, .storage_buffer, .physical_storage_buffer => {
                            if (ty.zigTypeTag(zcu) == .@"struct" and storage_class != .physical_storage_buffer) {
                                try cg.decorate(ty_id, .block);
                            }

                            if (ty.hasRuntimeBits(zcu)) {
                                try cg.decorate(ptr_ty_id, .{
                                    .array_stride = .{ .array_stride = @intCast(ty.abiSize(zcu)) },
                                });
                                try cg.decorateLayout(ty, ty_id);
                            }
                        },
                        else => {},
                    }

                    if (key.decoration) |decoration| switch (decoration) {
                        .location => |location| {
                            if (storage_class != .output and storage_class != .input and storage_class != .uniform_constant) {
                                return cg.fail("storage class must be one of (output, input, uniform_constant) but is {s}", .{@tagName(storage_class)});
                            }
                            try cg.decorate(result_id, .{
                                .location = .{ .location = location },
                            });
                        },
                        .flat => |location| {
                            try cg.decorate(result_id, .{ .location = .{ .location = location } });
                            try cg.decorate(result_id, .flat);
                        },
                        .descriptor => |descriptor| {
                            if (storage_class != .storage_buffer and storage_class != .uniform and storage_class != .uniform_constant) {
                                return cg.fail("storage class must be one of (storage_buffer, uniform, uniform_constant) but is {s}", .{@tagName(storage_class)});
                            }
                            try cg.decorate(result_id, .{
                                .binding = .{ .binding_point = descriptor.binding },
                            });

                            try cg.decorate(result_id, .{
                                .descriptor_set = .{ .descriptor_set = descriptor.set },
                            });
                        },
                    };
                },
                else => {},
            }

            if (std.meta.stringToEnum(spec.BuiltIn, nav.fqn.toSlice(ip))) |built_in| {
                try cg.decorate(result_id, .{ .built_in = .{ .built_in = built_in } });
            }

            try cg.debugName(result_id, nav.fqn.toSlice(ip));
        },
        .invocation_global => {
            // `@extern()` produces an invocation_global whose value is a
            // comptime-known pointer to an underlying extern symbol's Nav.
            // The pointer is inlined at use sites so we don't need a Function-scope wrapper here.
            if (ip.indexToKey(val.toIntern()) == .ptr) alias: {
                const ptr_key = ip.indexToKey(val.toIntern()).ptr;
                if (ptr_key.base_addr != .nav or ptr_key.byte_offset != 0) break :alias;
                const underlying_nav = ip.getNav(ptr_key.base_addr.nav);
                if (!underlying_nav.resolved.?.is_extern_decl) break :alias;
                cg.declPtr(spv_decl_index).end_dep = cg.decl_deps.items.len;
                return;
            }

            const ty_id = try cg.resolveType(ty, .indirect);
            const ptr_ty_id = try cg.ptrType(ty_id, .function);

            // TODO: Combine with resolveAnonDecl?
            const void_ty_id = try cg.resolveType(.void, .direct);
            const initializer_proto_ty_id = try cg.functionType(void_ty_id, &.{});

            const initializer_id = cg.allocId();
            try cg.prologue.emit(gpa, .OpFunction, .{
                .id_result_type = try cg.resolveType(.void, .direct),
                .id_result = initializer_id,
                .function_control = .{},
                .function_type = initializer_proto_ty_id,
            });

            const root_block_id = cg.allocId();
            try cg.prologue.emit(gpa, .OpLabel, .{
                .id_result = root_block_id,
            });
            cg.block_label = root_block_id;

            const val_id = try cg.constant(ty, val, .indirect);
            try cg.body.emit(gpa, .OpStore, .{
                .pointer = result_id,
                .object = val_id,
            });

            try cg.body.emit(gpa, .OpReturn, {});
            try cg.body.emit(gpa, .OpFunctionEnd, {});
            try cg.sections.functions.append(gpa, cg.prologue);
            try cg.sections.functions.append(gpa, cg.body);

            try cg.debugNameFmt(initializer_id, "initializer of {f}", .{nav.fqn.fmt(ip)});
            try cg.debugName(result_id, nav.fqn.toSlice(ip));

            try cg.sections.globals.emit(gpa, .OpExtInst, .{
                .id_result_type = ptr_ty_id,
                .id_result = result_id,
                .set = try cg.importInstructionSet(.zig),
                .instruction = .{ .inst = @intFromEnum(spec.Zig.InvocationGlobal) },
                .id_ref_4 = &.{initializer_id},
            });
        },
    }

    cg.declPtr(spv_decl_index).end_dep = cg.decl_deps.items.len;
}

fn decorateLayout(cg: *CodeGen, ty: Type, ty_id: spec.Id) Error!void {
    const zcu = cg.zcu;
    const ip = &zcu.intern_pool;
    switch (ty.zigTypeTag(zcu)) {
        .array => {
            const elem_ty = ty.childType(zcu);
            if (!elem_ty.hasRuntimeBits(zcu)) return;
            try cg.decorate(ty_id, .{
                .array_stride = .{ .array_stride = @intCast(elem_ty.abiSize(zcu)) },
            });
            try cg.decorateLayout(elem_ty, try cg.resolveType(elem_ty, .indirect));
        },
        .vector => {
            const elem_ty = ty.childType(zcu);
            try cg.decorateLayout(elem_ty, try cg.resolveType(elem_ty, .indirect));
            if (cg.isSpvVector(ty)) return;
            try cg.decorate(ty_id, .{
                .array_stride = .{ .array_stride = @intCast(elem_ty.abiSize(zcu)) },
            });
        },
        .@"struct" => switch (ip.indexToKey(ty.toIntern())) {
            .struct_type => {
                const struct_type = ip.loadStructType(ty.toIntern());
                if (struct_type.layout == .@"packed") return;
                var it = struct_type.iterateRuntimeOrder(ip);
                var member: u32 = 0;
                while (it.next()) |field_index| {
                    const field_ty: Type = .fromInterned(struct_type.field_types.get(ip)[field_index]);
                    if (!field_ty.hasRuntimeBits(zcu)) continue;
                    const offset: u32 = @intCast(ty.structFieldOffset(field_index, zcu));
                    try cg.decorateMember(ty_id, member, .{ .offset = .{ .byte_offset = offset } });
                    try cg.decorateLayout(field_ty, try cg.resolveType(field_ty, .indirect));
                    member += 1;
                }
            },
            .tuple_type => |tuple| {
                for (tuple.types.get(ip), tuple.values.get(ip)) |field_ty, field_val| {
                    if (field_val != .none) continue;
                    const ft: Type = .fromInterned(field_ty);
                    if (ft.hasRuntimeBits(zcu)) try cg.decorateLayout(ft, try cg.resolveType(ft, .indirect));
                }
            },
            else => {},
        },
        .@"union" => {
            const union_obj = zcu.typeToUnion(ty).?;
            if (union_obj.layout == .@"packed") return;
            const layout = cg.unionLayout(ty);
            if (layout.tag_size != 0) {
                const tag_ty: Type = .fromInterned(union_obj.enum_tag_type);
                try cg.decorateLayout(tag_ty, try cg.resolveType(tag_ty, .indirect));
            }
            if (layout.has_payload) {
                try cg.decorateLayout(layout.payload_ty, try cg.resolveType(layout.payload_ty, .indirect));
            }
            const u8_id = try cg.resolveType(.u8, .direct);
            if (layout.payload_padding_size != 0) {
                const len_id = try cg.constInt(.u32, layout.payload_padding_size);
                const arr_id = try cg.arrayType(len_id, u8_id);
                try cg.decorate(arr_id, .{ .array_stride = .{ .array_stride = 1 } });
            }
            if (layout.padding_size != 0) {
                const len_id = try cg.constInt(.u32, layout.padding_size);
                const arr_id = try cg.arrayType(len_id, u8_id);
                try cg.decorate(arr_id, .{ .array_stride = .{ .array_stride = 1 } });
            }
        },
        .optional => {
            const payload_ty = ty.optionalChild(zcu);
            if (payload_ty.hasRuntimeBits(zcu)) try cg.decorateLayout(payload_ty, try cg.resolveType(payload_ty, .indirect));
        },
        .error_union => {
            const payload_ty = ty.errorUnionPayload(zcu);
            if (payload_ty.hasRuntimeBits(zcu)) try cg.decorateLayout(payload_ty, try cg.resolveType(payload_ty, .indirect));
        },
        else => {},
    }
}

pub fn fail(cg: *CodeGen, comptime format: []const u8, args: anytype) Error {
    @branchHint(.cold);
    return cg.zcu.codegenFail(cg.owner_nav, format, args);
}

pub fn todo(cg: *CodeGen, comptime format: []const u8, args: anytype) Error {
    return cg.fail("TODO (SPIR-V): " ++ format, args);
}

/// This imports the "default" extended instruction set for the target
/// For OpenCL, OpenCL.std.100. For Vulkan and OpenGL, GLSL.std.450.
fn importExtendedSet(cg: *CodeGen) !Id {
    const target = cg.zcu.getTarget();
    return switch (target.os.tag) {
        .opencl, .amdhsa => try cg.importInstructionSet(.@"OpenCL.std"),
        .vulkan, .opengl => try cg.importInstructionSet(.@"GLSL.std.450"),
        else => unreachable,
    };
}

/// Fetch the result-id for a previously generated instruction or constant.
fn resolve(cg: *CodeGen, inst: Air.Inst.Ref) !Id {
    const zcu = cg.zcu;
    const ip = &zcu.intern_pool;
    if (inst.toInterned()) |val_ip_index| {
        const ty = cg.typeOf(inst);
        if (ty.zigTypeTag(zcu) == .@"fn") {
            const val_key = zcu.intern_pool.indexToKey(val_ip_index);
            const fn_nav = switch (val_key) {
                .@"extern" => |@"extern"| @"extern".owner_nav,
                .func => |func| func.owner_nav,
                else => unreachable,
            };
            const spv_decl_index = try cg.resolveNav(ip, fn_nav);
            try cg.decl_deps.append(cg.gpa, spv_decl_index);
            const decl = cg.declPtr(spv_decl_index);
            if (val_key == .@"extern") {
                const nav = ip.getNav(fn_nav);
                const nav_ty: Type = .fromInterned(nav.resolved.?.type);
                try emitExternFnStub(cg, nav, decl, nav_ty);
            }
            return decl.result_id;
        }

        return try cg.constant(ty, .fromInterned(val_ip_index), .direct);
    }
    const index = inst.toIndex().?;
    return cg.inst_results.get(index).?; // Assertion means instruction does not dominate usage.
}

fn resolveUav(cg: *CodeGen, val: InternPool.Index) !Id {
    const gpa = cg.gpa;

    // TODO: This cannot be a function at this point, but it should probably be handled anyway.

    const zcu = cg.zcu;
    const ty: Type = .fromInterned(zcu.intern_pool.typeOf(val));
    const ty_id = try cg.resolveType(ty, .indirect);

    const spv_decl_index = blk: {
        const entry = try cg.uav_link.getOrPut(gpa, .{ val, .function });
        if (entry.found_existing) {
            try cg.addFunctionDep(entry.value_ptr.*, .function);
            return cg.declPtr(entry.value_ptr.*).result_id;
        }

        const spv_decl_index = try cg.allocDecl(.invocation_global);
        try cg.addFunctionDep(spv_decl_index, .function);
        entry.value_ptr.* = spv_decl_index;
        break :blk spv_decl_index;
    };

    // TODO: At some point we will be able to generate this all constant here, but then all of
    //   constant() will need to be implemented such that it doesn't generate any at-runtime code.
    // NOTE: Because this is a global, we really only want to initialize it once. Therefore the
    //   constant lowering of this value will need to be deferred to an initializer similar to
    //   other globals.

    const result_id = cg.declPtr(spv_decl_index).result_id;

    {
        // Save the current state so that we can temporarily generate into a different function.
        // TODO: This should probably be made a little more robust.
        const func_prologue = cg.prologue;
        const func_body = cg.body;
        const block_label = cg.block_label;
        defer {
            cg.prologue = func_prologue;
            cg.body = func_body;
            cg.block_label = block_label;
        }

        cg.prologue = .{};
        cg.body = .{};
        defer {
            cg.prologue.deinit(gpa);
            cg.body.deinit(gpa);
        }

        const void_ty_id = try cg.resolveType(.void, .direct);
        const initializer_proto_ty_id = try cg.functionType(void_ty_id, &.{});

        const initializer_id = cg.allocId();
        try cg.prologue.emit(gpa, .OpFunction, .{
            .id_result_type = try cg.resolveType(.void, .direct),
            .id_result = initializer_id,
            .function_control = .{},
            .function_type = initializer_proto_ty_id,
        });
        const root_block_id = cg.allocId();
        try cg.prologue.emit(gpa, .OpLabel, .{
            .id_result = root_block_id,
        });
        cg.block_label = root_block_id;

        const val_id = try cg.constant(ty, .fromInterned(val), .indirect);
        try cg.body.emit(gpa, .OpStore, .{
            .pointer = result_id,
            .object = val_id,
        });

        try cg.body.emit(gpa, .OpReturn, {});
        try cg.body.emit(gpa, .OpFunctionEnd, {});

        try cg.sections.functions.append(gpa, cg.prologue);
        try cg.sections.functions.append(gpa, cg.body);

        try cg.debugNameFmt(initializer_id, "initializer of __anon_{d}", .{@intFromEnum(val)});

        const fn_decl_ptr_ty_id = try cg.ptrType(ty_id, .function);
        try cg.sections.globals.emit(gpa, .OpExtInst, .{
            .id_result_type = fn_decl_ptr_ty_id,
            .id_result = result_id,
            .set = try cg.importInstructionSet(.zig),
            .instruction = .{ .inst = @intFromEnum(spec.Zig.InvocationGlobal) },
            .id_ref_4 = &.{initializer_id},
        });
    }

    return result_id;
}

fn resolvePtr(cg: *CodeGen, ref: Air.Inst.Ref) !Ptr {
    const id = try cg.resolve(ref);
    if (cg.tracked_allocas.getPtr(id)) |slot| return .{ .tracked = .{ .id = id, .slot = slot } };
    return .{ .id = id };
}

fn addFunctionDep(cg: *CodeGen, decl_index: Decl.Index, storage_class: StorageClass) !void {
    const gpa = cg.gpa;
    const target = cg.zcu.getTarget();
    if (target.cpu.has(.spirv, .v1_4)) {
        try cg.decl_deps.append(gpa, decl_index);
    } else {
        // Before version 1.4, the interface’s storage classes are limited to the Input and Output
        if (storage_class == .input or storage_class == .output) {
            try cg.decl_deps.append(gpa, decl_index);
        }
    }
}

/// Start a new SPIR-V block, Emits the label of the new block, and stores which
/// block we are currently generating.
/// Note that there is no such thing as nested blocks like in ZIR or AIR, so we don't need to
/// keep track of the previous block.
fn beginSpvBlock(cg: *CodeGen, label: Id) !void {
    try cg.body.emit(cg.gpa, .OpLabel, .{ .id_result = label });
    cg.block_label = label;
    cg.block_terminated = false;
}

const ArithmeticTypeInfo = struct {
    const Class = enum {
        bool,
        /// A regular, **native**, integer.
        /// This is only returned when the backend supports this int as a native type (when
        /// the relevant capability is enabled).
        integer,
        /// A regular float. These are all required to be natively supported. Floating points
        /// for which the relevant capability is not enabled are not emulated.
        float,
        /// An integer of a 'strange' size (which' bit size is not the same as its backing
        /// type. **Note**: this may **also** include power-of-2 integers for which the
        /// relevant capability is not enabled), but still within the limits of the largest
        /// natively supported integer type.
        strange_integer,
        /// An integer with more bits than the largest natively supported integer type.
        composite_integer,
    };

    /// A classification of the inner type.
    /// These scenarios will all have to be handled slightly different.
    class: Class,
    /// The number of bits in the inner type.
    /// This is the actual number of bits of the type, not the size of the backing integer.
    bits: u16,
    /// The number of bits required to store the type.
    /// For `integer` and `float`, this is equal to `bits`.
    /// For `strange_integer` and `bool` this is the size of the backing integer.
    /// For `composite_integer` this is the elements count.
    backing_bits: u16,
    /// Null if this type is a scalar, or the length of the vector otherwise.
    vector_len: ?u32,
    /// Whether the inner type is signed. Only relevant for integers.
    signedness: std.lang.Signedness,
};

fn arithmeticTypeInfo(cg: *CodeGen, ty: Type) ArithmeticTypeInfo {
    const zcu = cg.zcu;
    const target = cg.zcu.getTarget();
    var scalar_ty = ty.scalarType(zcu);
    if (scalar_ty.zigTypeTag(zcu) == .@"enum") {
        scalar_ty = scalar_ty.intTagType(zcu);
    }
    const vector_len = if (ty.isVector(zcu)) ty.vectorLen(zcu) else null;
    return switch (scalar_ty.zigTypeTag(zcu)) {
        .bool => .{
            .bits = 1, // Doesn't matter for this class.
            .backing_bits = cg.backingIntBits(1).@"0",
            .vector_len = vector_len,
            .signedness = .unsigned, // Technically, but doesn't matter for this class.
            .class = .bool,
        },
        .float => .{
            .bits = scalar_ty.floatBits(target),
            .backing_bits = scalar_ty.floatBits(target), // TODO: F80?
            .vector_len = vector_len,
            .signedness = .signed, // Technically, but doesn't matter for this class.
            .class = .float,
        },
        .int => blk: {
            const int_info = scalar_ty.intInfo(zcu);
            // TODO: Maybe it's useful to also return this value.
            const backing_bits, const big_int = cg.backingIntBits(int_info.bits);
            break :blk .{
                .bits = int_info.bits,
                .backing_bits = backing_bits,
                .vector_len = vector_len,
                .signedness = int_info.signedness,
                .class = class: {
                    if (big_int) break :class .composite_integer;
                    break :class if (backing_bits == int_info.bits) .integer else .strange_integer;
                },
            };
        },
        .@"enum" => unreachable,
        .vector => unreachable,
        else => unreachable, // Unhandled arithmetic type
    };
}

/// Checks whether the type can be directly translated to SPIR-V vectors
fn isSpvVector(cg: *CodeGen, ty: Type) bool {
    const zcu = cg.zcu;
    const target = cg.zcu.getTarget();
    if (ty.zigTypeTag(zcu) != .vector) return false;

    // TODO: This check must be expanded for types that can be represented
    // as integers (enums / packed structs?) and types that are represented
    // by multiple SPIR-V values.
    const scalar_ty = ty.scalarType(zcu);
    switch (scalar_ty.zigTypeTag(zcu)) {
        .bool,
        .int,
        .float,
        => {},
        else => return false,
    }

    const elem_ty = ty.childType(zcu);
    const len = ty.vectorLen(zcu);

    if (elem_ty.isNumeric(zcu) or elem_ty.toIntern() == .bool_type) {
        if (len > 1 and len <= 4) return true;
        if (target.cpu.has(.spirv, .vector16)) return (len == 8 or len == 16);
    }

    return false;
}

/// Emits a bool constant in a particular representation.
fn constBool(cg: *CodeGen, value: bool, repr: Repr) !Id {
    switch (repr) {
        .indirect => return cg.constInt(.u1, @intFromBool(value)),
        .direct => {
            const result_ty_id = try cg.boolType();
            const result_id = cg.allocId();
            switch (value) {
                inline else => |value_ct| try cg.sections.globals.emit(
                    cg.gpa,
                    if (value_ct) .OpConstantTrue else .OpConstantFalse,
                    .{ .id_result_type = result_ty_id, .id_result = result_id },
                ),
            }
            return result_id;
        },
    }
}

/// Emits an integer constant.
/// This function, unlike cg.constInt, takes care to bitcast
/// the value to an unsigned int first for Kernels.
fn constInt(cg: *CodeGen, ty: Type, value: anytype) !Id {
    const gpa = cg.gpa;
    const zcu = cg.zcu;
    const target = cg.zcu.getTarget();
    const scalar_ty = ty.scalarType(zcu);
    const int_info = scalar_ty.intInfo(zcu);
    // Use backing bits so that negatives are sign extended
    const backing_bits, const big_int = cg.backingIntBits(int_info.bits);
    assert(backing_bits != 0); // u0 is comptime

    const result_ty_id = try cg.resolveType(scalar_ty, .indirect);
    const signedness: Signedness = switch (@typeInfo(@TypeOf(value))) {
        .int => |int| int.signedness,
        .comptime_int => if (value < 0) .signed else .unsigned,
        else => unreachable,
    };
    if (@TypeOf(value) != comptime_int and @sizeOf(@TypeOf(value)) >= 4 and big_int) {
        const value64: u64 = switch (signedness) {
            .signed => @bitCast(@as(i64, @intCast(value))),
            .unsigned => @as(u64, @intCast(value)),
        };
        const n_limbs = backing_bits / big_int_bits;
        const fill: u32 = if (signedness == .signed and value < 0) 0xFFFFFFFF else 0;
        const scratch_top = cg.id_scratch.items.len;
        defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
        const constituents = try cg.id_scratch.addManyAsSlice(gpa, n_limbs);
        for (constituents, 0..) |*c, i| {
            c.* = try cg.constInt(
                .u32,
                if (i < 2) @as(u32, @truncate(value64 >> @intCast(i * 32))) else fill,
            );
        }
        return cg.constructComposite(result_ty_id, constituents);
    }

    const final_value: spec.LiteralContextDependentNumber = switch (target.os.tag) {
        .opencl, .amdhsa => blk: {
            const value64: u64 = switch (signedness) {
                .signed => @bitCast(@as(i64, @intCast(value))),
                .unsigned => @as(u64, @intCast(value)),
            };

            // Manually truncate the value to the right amount of bits.
            const truncated_value = if (backing_bits == 64)
                value64
            else
                value64 & (@as(u64, 1) << @intCast(backing_bits)) - 1;

            break :blk switch (backing_bits) {
                1...32 => .{ .uint32 = @truncate(truncated_value) },
                33...64 => .{ .uint64 = truncated_value },
                else => unreachable,
            };
        },
        else => switch (backing_bits) {
            1...32 => if (signedness == .signed) .{ .int32 = @intCast(value) } else .{ .uint32 = @intCast(value) },
            33...64 => if (signedness == .signed) .{ .int64 = value } else .{ .uint64 = value },
            else => unreachable,
        },
    };

    const result_id = cg.allocId();
    try cg.sections.globals.emit(cg.gpa, .OpConstant, .{
        .id_result_type = result_ty_id,
        .id_result = result_id,
        .value = final_value,
    });

    if (!ty.isVector(zcu)) return result_id;
    return cg.constructCompositeSplat(ty, result_id);
}

/// Construct a composite value from its constituents.
/// In logical addressing mode (Vulkan/OpenGL), OpCompositeConstruct cannot accept
/// pointer operands, so for struct types we use alloc, store for each field and load instead.
pub fn constructComposite(cg: *CodeGen, result_ty_id: Id, constituents: []const Id) !Id {
    const gpa = cg.gpa;

    const maybe_fields: ?[]const Id = for (cg.struct_types.keys(), cg.struct_types.values()) |key, val| {
        if (val == result_ty_id) break key.fields;
    } else null;
    if (maybe_fields) |fields| {
        assert(fields.len == constituents.len);
        const u32_ty_id = try cg.intType(.unsigned, 32);
        const var_id = try cg.alloc(result_ty_id, null);
        for (fields, constituents, 0..) |field_ty_id, constituent, i| {
            const field_ptr_ty_id = try cg.ptrType(field_ty_id, .function);
            const index_id = cg.allocId();
            try cg.sections.globals.emit(gpa, .OpConstant, .{
                .id_result_type = u32_ty_id,
                .id_result = index_id,
                .value = .{ .uint32 = @intCast(i) },
            });
            const field_ptr = try cg.accessChainId(field_ptr_ty_id, var_id, &.{index_id});
            try cg.body.emit(gpa, .OpStore, .{
                .pointer = field_ptr,
                .object = constituent,
            });
        }
        const result_id = cg.allocId();
        try cg.body.emit(gpa, .OpLoad, .{
            .id_result_type = result_ty_id,
            .id_result = result_id,
            .pointer = var_id,
        });
        return result_id;
    }

    const result_id = cg.allocId();
    try cg.body.emit(gpa, .OpCompositeConstruct, .{
        .id_result_type = result_ty_id,
        .id_result = result_id,
        .constituents = constituents,
    });
    return result_id;
}

/// Construct a composite at runtime with all lanes set to the same value.
/// ty must be an aggregate type.
fn constructCompositeSplat(cg: *CodeGen, ty: Type, constituent: Id) !Id {
    const gpa = cg.gpa;
    const zcu = cg.zcu;
    const n: usize = @intCast(ty.arrayLen(zcu));

    const scratch_top = cg.id_scratch.items.len;
    defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);

    const constituents = try cg.id_scratch.addManyAsSlice(gpa, n);
    @memset(constituents, constituent);

    const result_ty_id = try cg.resolveType(ty, .direct);
    return cg.constructComposite(result_ty_id, constituents);
}

/// This function generates a load for a constant in direct (ie, non-memory) representation.
/// When the constant is simple, it can be generated directly using OpConstant instructions.
/// When the constant is more complicated however, it needs to be constructed using multiple values. This
/// is done by emitting a sequence of instructions that initialize the value.
//
/// This function should only be called during function code generation.
fn constant(cg: *CodeGen, ty: Type, val: Value, repr: Repr) Error!Id {
    const gpa = cg.gpa;

    const pt = cg.pt;
    const zcu = cg.zcu;
    const target = cg.zcu.getTarget();
    const result_ty_id = try cg.resolveType(ty, repr);
    const ip = &zcu.intern_pool;

    log.debug("lowering constant: ty = {f}, val = {f}, key = {s}", .{ ty.fmt(pt), val.fmtValue(pt), @tagName(ip.indexToKey(val.toIntern())) });
    if (val.isUndef(zcu)) {
        return cg.constUndef(result_ty_id);
    }

    const cacheable_id = cache: {
        switch (ip.indexToKey(val.toIntern())) {
            .int_type,
            .ptr_type,
            .array_type,
            .vector_type,
            .opt_type,
            .anyframe_type,
            .error_union_type,
            .simple_type,
            .struct_type,
            .tuple_type,
            .union_type,
            .opaque_type,
            .spirv_type,
            .enum_type,
            .func_type,
            .error_set_type,
            .inferred_error_set_type,
            => unreachable, // types, not values

            .undef => unreachable, // handled above

            .@"extern",
            .func,
            .enum_literal,
            => unreachable, // non-runtime values

            .simple_value => |simple_value| switch (simple_value) {
                .void,
                .null,
                .@"unreachable",
                => unreachable, // non-runtime values

                .false, .true => break :cache try cg.constBool(val.toBool(), repr),
            },
            .int => {
                const int_info = ty.intInfo(zcu);
                const backing_bits, const is_big_int = cg.backingIntBits(int_info.bits);
                if (is_big_int) {
                    const n_limbs = backing_bits / big_int_bits;
                    const big_result_ty_id = try cg.resolveType(ty, .indirect);
                    var bigint_space: Value.BigIntSpace = undefined;
                    const bigint = val.toBigInt(&bigint_space, zcu);
                    const limb_values = try gpa.alloc(u32, n_limbs);
                    defer gpa.free(limb_values);
                    bigint.writeTwosComplement(std.mem.sliceAsBytes(limb_values), .little);
                    if (builtin.cpu.arch.endian() == .big) {
                        for (limb_values) |*limb| limb.* = @byteSwap(limb.*);
                    }
                    const scratch_top = cg.id_scratch.items.len;
                    defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
                    const constituents = try cg.id_scratch.addManyAsSlice(gpa, n_limbs);
                    for (constituents, 0..) |*c, i| {
                        c.* = try cg.constInt(.u32, limb_values[i]);
                    }
                    break :cache try cg.constructComposite(big_result_ty_id, constituents);
                }
                if (ty.isSignedInt(zcu)) {
                    break :cache try cg.constInt(ty, val.toSignedInt(zcu));
                } else {
                    break :cache try cg.constInt(ty, val.toUnsignedInt(zcu));
                }
            },
            .float => {
                const lit: spec.LiteralContextDependentNumber = switch (ty.floatBits(target)) {
                    16 => .{ .uint32 = @as(u16, @bitCast(val.toFloat(f16, zcu))) },
                    32 => .{ .float32 = val.toFloat(f32, zcu) },
                    64 => .{ .float64 = val.toFloat(f64, zcu) },
                    80, 128 => unreachable, // TODO
                    else => unreachable,
                };
                const lit_id = cg.allocId();
                try cg.sections.globals.emit(gpa, .OpConstant, .{
                    .id_result_type = result_ty_id,
                    .id_result = lit_id,
                    .value = lit,
                });
                break :cache lit_id;
            },
            .err => |err| {
                const value = try pt.getErrorValue(err.name);
                break :cache try cg.constInt(ty, value);
            },
            .error_union => |error_union| {
                // TODO: Error unions may be constructed with constant instructions if the payload type
                // allows it. For now, just generate it here regardless.
                const err_ty = ty.errorUnionSet(zcu);
                const payload_ty = ty.errorUnionPayload(zcu);
                const err_val_id = switch (error_union.val) {
                    .err_name => |err_name| try cg.constInt(
                        err_ty,
                        try pt.getErrorValue(err_name),
                    ),
                    .payload => try cg.constInt(err_ty, 0),
                };
                const eu_layout = cg.errorUnionLayout(payload_ty);
                if (!eu_layout.payload_has_bits) {
                    // We use the error type directly as the type.
                    break :cache err_val_id;
                }

                const payload_val_id = switch (error_union.val) {
                    .err_name => try cg.constant(payload_ty, .undef, .indirect),
                    .payload => |p| try cg.constant(payload_ty, .fromInterned(p), .indirect),
                };

                var constituents: [2]Id = undefined;
                var types: [2]Type = undefined;
                if (eu_layout.error_first) {
                    constituents[0] = err_val_id;
                    constituents[1] = payload_val_id;
                    types = .{ err_ty, payload_ty };
                } else {
                    constituents[0] = payload_val_id;
                    constituents[1] = err_val_id;
                    types = .{ payload_ty, err_ty };
                }

                const comp_ty_id = try cg.resolveType(ty, .direct);
                return try cg.constructComposite(comp_ty_id, &constituents);
            },
            .enum_tag => {
                const int_val = val.intFromEnum(zcu);
                const int_ty = ty.intTagType(zcu);
                break :cache try cg.constant(int_ty, int_val, repr);
            },
            .ptr => return cg.constantPtr(val),
            .slice => |slice| {
                const ptr_id = try cg.constantPtr(.fromInterned(slice.ptr));
                const len_id = try cg.constant(.usize, .fromInterned(slice.len), .indirect);
                const comp_ty_id = try cg.resolveType(ty, .direct);
                return try cg.constructComposite(comp_ty_id, &.{ ptr_id, len_id });
            },
            .opt => {
                const payload_ty = ty.optionalChild(zcu);
                const maybe_payload_val = val.optionalValue(zcu);

                if (!payload_ty.hasRuntimeBits(zcu)) {
                    break :cache try cg.constBool(maybe_payload_val != null, .indirect);
                } else if (ty.optionalReprIsPayload(zcu)) {
                    // Optional representation is a nullable pointer or slice.
                    if (maybe_payload_val) |payload_val| {
                        return try cg.constant(payload_ty, payload_val, .indirect);
                    } else {
                        break :cache try cg.constNull(result_ty_id);
                    }
                }

                // Optional representation is a structure.
                // { Payload, Bool }

                const has_pl_id = try cg.constBool(maybe_payload_val != null, .indirect);
                const payload_id = if (maybe_payload_val) |payload_val|
                    try cg.constant(payload_ty, payload_val, .indirect)
                else
                    try cg.constUndef(try cg.resolveType(payload_ty, .indirect));

                const comp_ty_id = try cg.resolveType(ty, .direct);
                return try cg.constructComposite(comp_ty_id, &.{ payload_id, has_pl_id });
            },
            .aggregate => |aggregate| switch (ip.indexToKey(ty.ip_index)) {
                inline .array_type, .vector_type => |array_type, tag| {
                    const elem_ty: Type = .fromInterned(array_type.child);

                    const scratch_top = cg.id_scratch.items.len;
                    defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
                    const constituents = try cg.id_scratch.addManyAsSlice(gpa, @intCast(ty.arrayLenIncludingSentinel(zcu)));

                    const child_repr: Repr = switch (tag) {
                        .array_type => .indirect,
                        .vector_type => .direct,
                        else => unreachable,
                    };

                    switch (aggregate.storage) {
                        .bytes => |bytes| {
                            // TODO: This is really space inefficient, perhaps there is a better
                            // way to do it?
                            for (constituents, bytes.toSlice(constituents.len, ip)) |*constituent, byte| {
                                constituent.* = try cg.constInt(elem_ty, byte);
                            }
                        },
                        .elems => |elems| {
                            for (constituents, elems) |*constituent, elem| {
                                constituent.* = try cg.constant(elem_ty, .fromInterned(elem), child_repr);
                            }
                        },
                        .repeated_elem => |elem| {
                            @memset(constituents, try cg.constant(elem_ty, .fromInterned(elem), child_repr));
                        },
                    }

                    const comp_ty_id = try cg.resolveType(ty, .direct);
                    return cg.constructComposite(comp_ty_id, constituents);
                },
                .struct_type => {
                    const struct_type = zcu.typeToStruct(ty).?;
                    assert(struct_type.layout != .@"packed"); // packed structs use `bitpack`

                    var types = std.array_list.Managed(Type).init(gpa);
                    defer types.deinit();

                    var constituents = std.array_list.Managed(Id).init(gpa);
                    defer constituents.deinit();

                    var it = struct_type.iterateRuntimeOrder(ip);
                    while (it.next()) |field_index| {
                        const field_ty: Type = .fromInterned(struct_type.field_types.get(ip)[field_index]);
                        if (!field_ty.hasRuntimeBits(zcu)) {
                            // This is a zero-bit field - we only needed it for the alignment.
                            continue;
                        }

                        // TODO: Padding?
                        const field_val = try val.fieldValue(pt, field_index);
                        const field_id = try cg.constant(field_ty, field_val, .indirect);

                        try types.append(field_ty);
                        try constituents.append(field_id);
                    }

                    const comp_ty_id = try cg.resolveType(ty, .direct);
                    return try cg.constructComposite(comp_ty_id, constituents.items);
                },
                .tuple_type => |tuple| {
                    var constituents: std.ArrayList(Id) = .empty;
                    defer constituents.deinit(gpa);

                    for (tuple.types.get(ip), tuple.values.get(ip), 0..) |field_ty, field_val, i| {
                        if (field_val != .none) continue;
                        const ft: Type = .fromInterned(field_ty);
                        if (!ft.hasRuntimeBits(zcu)) continue;

                        const fv = try val.fieldValue(pt, i);
                        const field_id = try cg.constant(ft, fv, .indirect);
                        try constituents.append(gpa, field_id);
                    }

                    const comp_ty_id = try cg.resolveType(ty, .direct);
                    return try cg.constructComposite(comp_ty_id, constituents.items);
                },
                else => unreachable,
            },
            .un => |un| {
                assert(ty.containerLayout(zcu) != .@"packed"); // packed unions use `bitpack`
                if (un.tag == .none) {
                    @panic("TODO");
                }
                const active_field = ty.unionTagFieldIndex(.fromInterned(un.tag), zcu).?;
                const union_obj = zcu.typeToUnion(ty).?;
                const field_ty: Type = .fromInterned(union_obj.field_types.get(ip)[active_field]);
                const payload = if (field_ty.hasRuntimeBits(zcu))
                    try cg.constant(field_ty, .fromInterned(un.val), .direct)
                else
                    null;
                return try cg.unionInit(ty, active_field, payload);
            },
            .bitpack => |bitpack| {
                const int_val: Value = .fromInterned(bitpack.backing_int_val);
                break :cache try cg.constant(int_val.typeOf(zcu), int_val, repr);
            },

            .memoized_call => unreachable,
        }
    };
    return cacheable_id;
}

fn constantPtr(cg: *CodeGen, ptr_val: Value) !Id {
    const pt = cg.pt;
    const zcu = cg.zcu;
    const gpa = cg.gpa;

    if (ptr_val.isUndef(zcu)) {
        const result_ty = ptr_val.typeOf(zcu);
        const result_ty_id = try cg.resolveType(result_ty, .direct);
        return cg.constUndef(result_ty_id);
    }

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    const derivation = try ptr_val.pointerDerivation(arena.allocator(), pt, null);
    return cg.derivePtr(derivation);
}

fn derivePtr(cg: *CodeGen, derivation: Value.PointerDeriveStep) !Id {
    const gpa = cg.gpa;
    const pt = cg.pt;
    const zcu = cg.zcu;
    const target = zcu.getTarget();
    switch (derivation) {
        .comptime_alloc_ptr, .comptime_field_ptr => unreachable,
        .int => |int| {
            if (target.os.tag != .opencl) {
                if (int.ptr_ty.ptrAddressSpace(zcu) != .physical_storage_buffer) {
                    return cg.fail(
                        "cannot cast integer to pointer with address space '{s}'",
                        .{@tagName(int.ptr_ty.ptrAddressSpace(zcu))},
                    );
                }
            }
            const result_ty_id = try cg.resolveType(int.ptr_ty, .direct);
            // TODO: This can probably be an OpSpecConstantOp Bitcast, but
            // that is not implemented by Mesa yet. Therefore, just generate it
            // as a runtime operation.
            const result_ptr_id = cg.allocId();
            const value_id = try cg.constInt(.usize, int.addr);
            try cg.body.emit(gpa, .OpConvertUToPtr, .{
                .id_result_type = result_ty_id,
                .id_result = result_ptr_id,
                .integer_value = value_id,
            });
            return result_ptr_id;
        },
        .nav_ptr => |nav_index| {
            const ip = &zcu.intern_pool;
            const result_ptr_ty = try pt.navPtrType(nav_index);
            const ty_id = try cg.resolveType(result_ptr_ty, .direct);
            const nav = ip.getNav(nav_index);
            const nav_ty: Type = .fromInterned(nav.resolved.?.type);

            switch (nav.resolved.?.value) {
                .none => {},
                else => |value| switch (ip.indexToKey(value)) {
                    // TODO: Properly lower function pointers; for now substitute undef.
                    .func => return try cg.constUndef(ty_id),
                    .@"extern" => if (ip.isFunctionType(nav_ty.toIntern())) {
                        const spv_decl_index = try cg.resolveNav(ip, nav_index);
                        const decl = cg.declPtr(spv_decl_index);
                        try emitExternFnStub(cg, nav, decl, nav_ty);
                        return decl.result_id;
                    },
                    else => {},
                },
            }

            if (!nav_ty.hasRuntimeBits(zcu) and nav_ty.zigTypeTag(zcu) != .spirv) {
                return cg.constUndef(ty_id);
            }

            const spv_decl_index = try cg.resolveNav(ip, nav_index);
            const spv_decl = cg.declPtr(spv_decl_index);
            assert(spv_decl.kind != .func);
            const storage_class = cg.storageClass(nav.resolved.?.@"addrspace");
            try cg.addFunctionDep(spv_decl_index, storage_class);

            const nav_ty_id = try cg.resolveType(nav_ty, .indirect);
            const decl_ptr_ty_id = try cg.ptrType(nav_ty_id, storage_class);
            if (decl_ptr_ty_id == ty_id) return spv_decl.result_id;
            switch (target.os.tag) {
                .vulkan, .opengl => return spv_decl.result_id,
                else => {},
            }
            const casted_ptr_id = cg.allocId();
            try cg.body.emit(gpa, .OpBitcast, .{
                .id_result_type = ty_id,
                .id_result = casted_ptr_id,
                .operand = spv_decl.result_id,
            });
            return casted_ptr_id;
        },
        .uav_ptr => |uav| {
            const ip = &zcu.intern_pool;
            const result_ptr_ty: Type = .fromInterned(uav.orig_ty);
            const ty_id = try cg.resolveType(result_ptr_ty, .direct);
            const uav_ty: Type = .fromInterned(ip.typeOf(uav.val));

            switch (ip.indexToKey(uav.val)) {
                .func => unreachable, // TODO
                .@"extern" => assert(!ip.isFunctionType(uav_ty.toIntern())),
                else => {},
            }

            if (!uav_ty.hasRuntimeBits(zcu) and uav_ty.zigTypeTag(zcu) != .spirv) {
                return cg.constUndef(ty_id);
            }

            // Uav refs are always generic.
            assert(result_ptr_ty.ptrAddressSpace(zcu) == .generic);
            const uav_ty_id = try cg.resolveType(uav_ty, .indirect);
            const decl_ptr_ty_id = try cg.ptrType(uav_ty_id, .function);
            const ptr_id = try cg.resolveUav(uav.val);

            if (decl_ptr_ty_id == ty_id) return ptr_id;
            switch (target.os.tag) {
                .vulkan, .opengl => return ptr_id,
                else => {},
            }
            const casted_ptr_id = cg.allocId();
            try cg.body.emit(gpa, .OpBitcast, .{
                .id_result_type = ty_id,
                .id_result = casted_ptr_id,
                .operand = ptr_id,
            });
            return casted_ptr_id;
        },
        .eu_payload_ptr => @panic("TODO"),
        .opt_payload_ptr => @panic("TODO"),
        .field_ptr => |field| {
            const parent_ptr_id = try cg.derivePtr(field.parent.*);
            const parent_ptr_ty = try field.parent.ptrType(pt);
            return cg.structFieldPtr(field.result_ptr_ty, parent_ptr_ty, parent_ptr_id, field.field_idx);
        },
        .elem_ptr => |elem| {
            const parent_ptr_id = try cg.derivePtr(elem.parent.*);
            const parent_ptr_ty = try elem.parent.ptrType(pt);
            const index_id = try cg.constInt(.usize, elem.elem_idx);
            return cg.ptrElemPtr(parent_ptr_ty, parent_ptr_id, index_id);
        },
        .offset_and_cast => |oac| {
            const parent_ptr_id = try cg.derivePtr(oac.parent.*);
            const parent_ptr_ty = try oac.parent.ptrType(pt);
            const result_ty_id = try cg.resolveType(oac.new_ptr_ty, .direct);

            if (parent_ptr_ty.childType(zcu).isVector(zcu)) {
                // Vector element ptr accesses are derived as offset_and_cast.
                // We can just use OpAccessChain.
                const child_size = oac.new_ptr_ty.childType(zcu).abiSize(zcu);
                if (oac.byte_offset % child_size == 0) {
                    return cg.accessChain(
                        result_ty_id,
                        parent_ptr_id,
                        &.{@intCast(@divExact(oac.byte_offset, child_size))},
                    );
                }
            }

            if (oac.byte_offset == 0) {
                var depth: u32 = 0;
                var cur = parent_ptr_ty.childType(zcu);
                const dst_child = oac.new_ptr_ty.childType(zcu);
                while (cur.toIntern() != dst_child.toIntern()) {
                    if (cur.zigTypeTag(zcu) == .array) {
                        cur = cur.childType(zcu);
                        depth += 1;
                    } else break;
                }
                if (depth > 0 and cur.toIntern() == dst_child.toIntern()) {
                    const scratch_top = cg.id_scratch.items.len;
                    defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
                    const zero = try cg.constInt(.u32, 0);
                    const ids = try cg.id_scratch.addManyAsSlice(gpa, depth);
                    @memset(ids, zero);
                    return cg.accessChainId(result_ty_id, parent_ptr_id, ids);
                }
                if (target.os.tag == .opencl) {
                    const result_ptr_id = cg.allocId();
                    try cg.body.emit(gpa, .OpBitcast, .{
                        .id_result_type = result_ty_id,
                        .id_result = result_ptr_id,
                        .operand = parent_ptr_id,
                    });
                    return result_ptr_id;
                }
            }

            return cg.fail("cannot perform pointer cast: '{f}' to '{f}'", .{
                parent_ptr_ty.fmt(pt),
                oac.new_ptr_ty.fmt(pt),
            });
        },
    }
}

/// Emit a stub OpFunction/OpFunctionEnd + Import linkage decoration for an
/// extern function so the module is structurally valid. The stub will be
/// replaced by the real definition at link time.
fn emitExternFnStub(cg: *CodeGen, nav: InternPool.Nav, decl: *Decl, fn_ty: Type) !void {
    if (decl.has_extern_stub) return;
    decl.has_extern_stub = true;

    const gpa = cg.gpa;
    const zcu = cg.zcu;
    const ip = &zcu.intern_pool;
    const fn_info = zcu.typeToFunc(fn_ty).?;
    const return_ty_id = try cg.resolveFnReturnType(.fromInterned(fn_info.return_type));
    const prototype_ty_id = try cg.resolveType(fn_ty, .direct);

    var stub: Section = .{};
    defer stub.deinit(gpa);
    try stub.emit(gpa, .OpFunction, .{
        .id_result_type = return_ty_id,
        .id_result = decl.result_id,
        .function_type = prototype_ty_id,
        .function_control = .{},
    });
    for (fn_info.param_types.get(ip)) |param_ty_index| {
        const param_ty: Type = .fromInterned(param_ty_index);
        if (!param_ty.hasRuntimeBits(zcu)) continue;
        const param_type_id = try cg.resolveType(param_ty, .direct);
        try stub.emit(gpa, .OpFunctionParameter, .{
            .id_result_type = param_type_id,
            .id_result = cg.allocId(),
        });
    }
    try stub.emit(gpa, .OpFunctionEnd, {});
    try cg.sections.functions.append(gpa, stub);

    const extern_name = nav.getExtern(ip).?.name.toSlice(ip);
    try cg.sections.annotations.emit(gpa, .OpDecorate, .{
        .target = decl.result_id,
        .decoration = .{ .linkage_attributes = .{
            .name = extern_name,
            .linkage_type = .import,
        } },
    });
    try cg.debugName(decl.result_id, extern_name);
}

fn resolveTypeName(cg: *CodeGen, ty: Type) ![]const u8 {
    const gpa = cg.gpa;
    var aw: std.Io.Writer.Allocating = .init(gpa);
    defer aw.deinit();
    ty.print(&aw.writer, cg.pt, null) catch |err| switch (err) {
        error.WriteFailed => return error.OutOfMemory,
    };
    return try aw.toOwnedSlice();
}

/// Generate a union type. Union types are always generated with the
/// most aligned field active. If the tag alignment is greater
/// than that of the payload, a regular union (non-packed, with both tag and
/// payload), will be generated as follows:
///  struct {
///    tag: TagType,
///    payload: MostAlignedFieldType,
///    payload_padding: [payload_size - @sizeOf(MostAlignedFieldType)]u8,
///    padding: [padding_size]u8,
///  }
/// If the payload alignment is greater than that of the tag:
///  struct {
///    payload: MostAlignedFieldType,
///    payload_padding: [payload_size - @sizeOf(MostAlignedFieldType)]u8,
///    tag: TagType,
///    padding: [padding_size]u8,
///  }
/// If any of the fields' size is 0, it will be omitted.
fn resolveFnReturnType(cg: *CodeGen, ret_ty: Type) !Id {
    const zcu = cg.zcu;
    if (!ret_ty.hasRuntimeBits(zcu)) {
        // If the return type is an error set or an error union, then we make this
        // anyerror return type instead, so that it can be coerced into a function
        // pointer type which has anyerror as the return type.
        if (ret_ty.isError(zcu)) {
            return cg.resolveType(.anyerror, .direct);
        } else {
            return cg.resolveType(.void, .direct);
        }
    }

    return try cg.resolveType(ret_ty, .direct);
}

fn resolveType(cg: *CodeGen, ty: Type, repr: Repr) Error!Id {
    const gpa = cg.gpa;
    const pt = cg.pt;
    const zcu = cg.zcu;
    const ip = &zcu.intern_pool;
    const target = cg.zcu.getTarget();

    log.debug("resolveType: ty = {f}", .{ty.fmt(pt)});

    switch (ty.zigTypeTag(zcu)) {
        .noreturn => {
            assert(repr == .direct);
            return try cg.voidType();
        },
        .void => switch (repr) {
            .direct => return try cg.voidType(),
            .indirect => {
                if (target.os.tag != .opencl) return cg.fail("cannot generate opaque type", .{});
                return try cg.opaqueType("void");
            },
        },
        .bool => switch (repr) {
            .direct => return try cg.boolType(),
            .indirect => return try cg.resolveType(.u1, .indirect),
        },
        .int => {
            if (ty.toIntern() == .u0_type) {
                assert(repr == .indirect);
                if (target.os.tag != .opencl) return cg.fail("cannot generate opaque type", .{});
                return try cg.opaqueType("u0");
            }
            const int_info = ty.intInfo(zcu);
            return try cg.intType(int_info.signedness, int_info.bits);
        },
        .@"enum" => return try cg.resolveType(ty.intTagType(zcu), repr),
        .float => {
            const bits = ty.floatBits(target);
            const supported = switch (bits) {
                16 => target.cpu.has(.spirv, .float16),
                32 => true,
                64 => target.cpu.has(.spirv, .float64),
                else => false,
            };

            if (!supported) {
                return cg.fail(
                    "floating point width of {} bits is not supported for the current SPIR-V feature set",
                    .{bits},
                );
            }

            return try cg.floatType(bits);
        },
        .array => {
            const elem_ty = ty.childType(zcu);
            const elem_ty_id = try cg.resolveType(elem_ty, .indirect);
            const total_len = std.math.cast(u32, ty.arrayLenIncludingSentinel(zcu)) orelse {
                return cg.fail("array type of {} elements is too large", .{ty.arrayLenIncludingSentinel(zcu)});
            };

            if (!elem_ty.hasRuntimeBits(zcu)) {
                assert(repr == .indirect);
                if (target.os.tag != .opencl) return cg.fail("cannot generate opaque type", .{});
                return try cg.opaqueType("zero-sized-array");
            } else if (total_len == 0) {
                // The size of the array would be 0, but that is not allowed in SPIR-V.
                // This path can be reached for example when there is a slicing of a pointer
                // that produces a zero-length array. In all cases where this type can be generated,
                // this should be an indirect path.
                assert(repr == .indirect);
                // In this case, we have an array of a non-zero sized type. In this case,
                // generate an array of 1 element instead, so that ptr_elem_ptr instructions
                // can be lowered to ptrAccessChain instead of manually performing the math.
                const len_id = try cg.constInt(.u32, 1);
                return try cg.arrayType(len_id, elem_ty_id);
            } else {
                const total_len_id = try cg.constInt(.u32, total_len);
                return try cg.arrayType(total_len_id, elem_ty_id);
            }
        },
        .vector => {
            const elem_ty = ty.childType(zcu);
            const elem_ty_id = try cg.resolveType(elem_ty, repr);
            const len = ty.vectorLen(zcu);
            if (cg.isSpvVector(ty)) return try cg.vectorType(len, elem_ty_id);
            const len_id = try cg.constInt(.u32, len);
            return try cg.arrayType(len_id, elem_ty_id);
        },
        .@"fn" => switch (repr) {
            .direct => {
                const fn_info = zcu.typeToFunc(ty).?;

                assert(!fn_info.is_var_args);
                switch (fn_info.cc) {
                    .auto,
                    .spirv_kernel,
                    .spirv_fragment,
                    .spirv_vertex,
                    .spirv_device,
                    .spirv_task,
                    .spirv_mesh,
                    => {},
                    else => unreachable,
                }

                const return_ty_id = try cg.resolveFnReturnType(.fromInterned(fn_info.return_type));

                const scratch_top = cg.id_scratch.items.len;
                defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
                const param_ty_ids = try cg.id_scratch.addManyAsSlice(gpa, fn_info.param_types.len);

                var param_index: usize = 0;
                for (fn_info.param_types.get(ip)) |param_ty_index| {
                    const param_ty: Type = .fromInterned(param_ty_index);
                    if (!param_ty.hasRuntimeBits(zcu)) continue;

                    param_ty_ids[param_index] = try cg.resolveType(param_ty, .direct);
                    param_index += 1;
                }

                return try cg.functionType(return_ty_id, param_ty_ids[0..param_index]);
            },
            .indirect => {
                // TODO: Represent function pointers properly.
                // For now, just use an usize type.
                return try cg.resolveType(.usize, .indirect);
            },
        },
        .pointer => {
            const ptr_info = ty.ptrInfo(zcu);

            const child_ty: Type = switch (ptr_info.packed_offset.host_size) {
                0 => .fromInterned(ptr_info.child),
                else => switch (ptr_info.flags.vector_index) {
                    // Accepted proposal https://github.com/ziglang/zig/issues/24061 will eliminate these usages of `pt`.
                    .none => try pt.intType(.unsigned, ptr_info.packed_offset.host_size * 8),
                    else => try pt.vectorType(.{
                        .child = ptr_info.child,
                        .len = ptr_info.packed_offset.host_size,
                    }),
                },
            };
            const child_ty_id = try cg.resolveType(child_ty, .indirect);
            const storage_class = cg.storageClass(ptr_info.flags.address_space);
            const ptr_ty_id = try cg.ptrType(child_ty_id, storage_class);

            if (ptr_info.flags.size != .slice) {
                return ptr_ty_id;
            }

            const size_ty_id = try cg.resolveType(.usize, .direct);
            return try cg.structType(
                &.{ ptr_ty_id, size_ty_id },
                &.{ "ptr", "len" },
                .none,
            );
        },
        .@"struct" => {
            const struct_type = switch (ip.indexToKey(ty.toIntern())) {
                .tuple_type => |tuple| {
                    const scratch_top = cg.id_scratch.items.len;
                    defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
                    const member_types = try cg.id_scratch.addManyAsSlice(gpa, tuple.values.len);

                    var member_index: usize = 0;
                    for (tuple.types.get(ip), tuple.values.get(ip)) |field_ty, field_val| {
                        if (field_val != .none or !Type.fromInterned(field_ty).hasRuntimeBits(zcu)) continue;

                        member_types[member_index] = try cg.resolveType(.fromInterned(field_ty), .indirect);
                        member_index += 1;
                    }

                    const result_id = try cg.structType(
                        member_types[0..member_index],
                        null,
                        .none,
                    );
                    const type_name = try cg.resolveTypeName(ty);
                    defer gpa.free(type_name);
                    try cg.debugName(result_id, type_name);
                    return result_id;
                },
                .struct_type => ip.loadStructType(ty.toIntern()),
                else => unreachable,
            };

            if (struct_type.layout == .@"packed") {
                return try cg.resolveType(.fromInterned(struct_type.packed_backing_int_type), .direct);
            }

            var member_types = std.array_list.Managed(Id).init(gpa);
            defer member_types.deinit();

            var member_names = std.array_list.Managed([]const u8).init(gpa);
            defer member_names.deinit();

            var it = struct_type.iterateRuntimeOrder(ip);
            while (it.next()) |field_index| {
                const field_ty: Type = .fromInterned(struct_type.field_types.get(ip)[field_index]);
                if (!field_ty.hasRuntimeBits(zcu)) continue;

                const field_name = struct_type.field_names.get(ip)[field_index];
                try member_types.append(try cg.resolveType(field_ty, .indirect));
                try member_names.append(field_name.toSlice(ip));
            }

            const result_id = try cg.structType(
                member_types.items,
                member_names.items,
                ty.toIntern(),
            );

            const type_name = try cg.resolveTypeName(ty);
            defer gpa.free(type_name);
            try cg.debugName(result_id, type_name);

            return result_id;
        },
        .optional => {
            const payload_ty = ty.optionalChild(zcu);
            if (!payload_ty.hasRuntimeBits(zcu)) {
                // Just use a bool.
                // Note: Always generate the bool with indirect format, to save on some sanity
                // Perform the conversion to a direct bool when the field is extracted.
                return try cg.resolveType(.bool, .indirect);
            }

            const payload_ty_id = try cg.resolveType(payload_ty, .indirect);
            if (ty.optionalReprIsPayload(zcu)) {
                // Optional is actually a pointer or a slice.
                return payload_ty_id;
            }

            const bool_ty_id = try cg.resolveType(.bool, .indirect);

            return try cg.structType(
                &.{ payload_ty_id, bool_ty_id },
                &.{ "payload", "valid" },
                .none,
            );
        },
        .@"union" => {
            const union_obj = zcu.typeToUnion(ty).?;
            if (union_obj.layout == .@"packed") {
                return try cg.intType(.unsigned, @intCast(ty.bitSize(zcu)));
            }
            const layout = cg.unionLayout(ty);
            if (!layout.has_payload) {
                return try cg.resolveType(.fromInterned(union_obj.enum_tag_type), .indirect);
            }
            var member_types: [4]Id = undefined;
            var member_names: [4][]const u8 = undefined;
            const u8_ty_id = try cg.resolveType(.u8, .direct);
            if (layout.tag_size != 0) {
                member_types[layout.tag_index] = try cg.resolveType(.fromInterned(union_obj.enum_tag_type), .indirect);
                member_names[layout.tag_index] = "(tag)";
            }
            if (layout.payload_size != 0) {
                member_types[layout.payload_index] = try cg.resolveType(layout.payload_ty, .indirect);
                member_names[layout.payload_index] = "(payload)";
            }
            if (layout.payload_padding_size != 0) {
                const len_id = try cg.constInt(.u32, layout.payload_padding_size);
                member_types[layout.payload_padding_index] = try cg.arrayType(len_id, u8_ty_id);
                member_names[layout.payload_padding_index] = "(payload padding)";
            }
            if (layout.padding_size != 0) {
                const len_id = try cg.constInt(.u32, layout.padding_size);
                member_types[layout.padding_index] = try cg.arrayType(len_id, u8_ty_id);
                member_names[layout.padding_index] = "(padding)";
            }
            const result_id = try cg.structType(
                member_types[0..layout.total_fields],
                member_names[0..layout.total_fields],
                .none,
            );
            const type_name = try cg.resolveTypeName(ty);
            defer gpa.free(type_name);
            try cg.debugName(result_id, type_name);
            return result_id;
        },
        .error_set => {
            const err_int_ty = try pt.errorIntType();
            return try cg.resolveType(err_int_ty, repr);
        },
        .error_union => {
            const payload_ty = ty.errorUnionPayload(zcu);
            const err_ty = ty.errorUnionSet(zcu);
            const error_ty_id = try cg.resolveType(err_ty, .indirect);

            const eu_layout = cg.errorUnionLayout(payload_ty);
            if (!eu_layout.payload_has_bits) {
                return error_ty_id;
            }

            const payload_ty_id = try cg.resolveType(payload_ty, .indirect);

            var member_types: [2]Id = undefined;
            var member_names: [2][]const u8 = undefined;
            if (eu_layout.error_first) {
                // Put the error first
                member_types = .{ error_ty_id, payload_ty_id };
                member_names = .{ "error", "payload" };
                // TODO: ABI padding?
            } else {
                // Put the payload first.
                member_types = .{ payload_ty_id, error_ty_id };
                member_names = .{ "payload", "error" };
                // TODO: ABI padding?
            }

            return try cg.structType(&member_types, &member_names, .none);
        },
        .@"opaque" => {
            if (target.os.tag != .opencl) return cg.fail("cannot generate opaque type", .{});
            const type_name = try cg.resolveTypeName(ty);
            defer gpa.free(type_name);
            return try cg.opaqueType(type_name);
        },
        .spirv => {
            const spirv_type = ip.loadSpirvType(ty.toIntern());
            const result_id = cg.allocId();
            switch (spirv_type.flags.tag) {
                .sampler => try cg.sections.globals.emit(gpa, .OpTypeSampler, .{ .id_result = result_id }),
                .image => {
                    const sampled_type_id = try cg.resolveType(.fromInterned(spirv_type.ty), .direct);
                    try cg.sections.globals.emit(gpa, .OpTypeImage, .{
                        .id_result = result_id,
                        .sampled_type = sampled_type_id,
                        .dim = switch (spirv_type.flags.dim) {
                            .@"1d" => .@"1d",
                            .@"2d" => .@"2d",
                            .@"3d" => .@"3d",
                            .cube => .cube,
                        },
                        .depth = switch (spirv_type.flags.depth) {
                            .not_depth => 0,
                            .depth => 1,
                            .unknown => 2,
                        },
                        .arrayed = @intFromBool(spirv_type.flags.is_arrayed),
                        .ms = @intFromBool(spirv_type.flags.is_multisampled),
                        .sampled = switch (spirv_type.flags.usage) {
                            .unknown => 0,
                            .sampled => 1,
                            .storage => 2,
                        },
                        .image_format = switch (spirv_type.flags.format) {
                            .unknown => .unknown,
                            .rgba32f => .rgba32f,
                            .rgba32i => .rgba32i,
                            .rgba32u => .rgba32ui,
                            .rgba16f => .rgba16f,
                            .rgba16i => .rgba16i,
                            .rgba16u => .rgba16ui,
                            .rgba8unorm => .rgba8,
                            .rgba8snorm => .rgba8snorm,
                            .rgba8i => .rgba8i,
                            .rgba8u => .rgba8ui,
                            .r32f => .r32f,
                            .r32i => .r32i,
                            .r32u => .r32ui,
                        },
                        .access_qualifier = switch (spirv_type.flags.access) {
                            .unknown => null,
                            .read_only => .read_only,
                            .write_only => .write_only,
                            .read_write => .read_write,
                        },
                    });
                },
                .sampled_image => {
                    const image_ty_id = try cg.resolveType(.fromInterned(spirv_type.ty), .indirect);
                    try cg.sections.globals.emit(gpa, .OpTypeSampledImage, .{
                        .id_result = result_id,
                        .image_type = image_ty_id,
                    });
                },
                .runtime_array => {
                    const elem_ty: Type = .fromInterned(spirv_type.ty);
                    const elem_ty_id = try cg.resolveType(elem_ty, .indirect);
                    try cg.sections.globals.emit(gpa, .OpTypeRuntimeArray, .{
                        .id_result = result_id,
                        .element_type = elem_ty_id,
                    });
                    if (elem_ty.hasRuntimeBits(zcu)) {
                        try cg.decorate(result_id, .{ .array_stride = .{
                            .array_stride = @intCast(elem_ty.abiSize(zcu)),
                        } });
                    }
                },
            }
            return result_id;
        },

        .null,
        .undefined,
        .enum_literal,
        .comptime_float,
        .comptime_int,
        .type,
        => unreachable, // Must be comptime.

        .frame, .@"anyframe" => unreachable, // TODO
    }
}

const ErrorUnionLayout = struct {
    payload_has_bits: bool,
    error_first: bool,

    fn errorFieldIndex(cg: @This()) u32 {
        assert(cg.payload_has_bits);
        return if (cg.error_first) 0 else 1;
    }

    fn payloadFieldIndex(cg: @This()) u32 {
        assert(cg.payload_has_bits);
        return if (cg.error_first) 1 else 0;
    }
};

fn errorUnionLayout(cg: *CodeGen, payload_ty: Type) ErrorUnionLayout {
    const zcu = cg.zcu;

    const error_align = Type.abiAlignment(.anyerror, zcu);
    const payload_align = payload_ty.abiAlignment(zcu);

    const error_first = error_align.compare(.gt, payload_align);
    return .{
        .payload_has_bits = payload_ty.hasRuntimeBits(zcu),
        .error_first = error_first,
    };
}

const UnionLayout = struct {
    /// If false, this union is represented
    /// by only an integer of the tag type.
    has_payload: bool,
    tag_size: u32,
    tag_index: u32,
    /// Note: This is the size of the payload type itcg, NOT the size of the ENTIRE payload.
    /// Use `has_payload` instead!!
    payload_ty: Type,
    payload_size: u32,
    payload_index: u32,
    payload_padding_size: u32,
    payload_padding_index: u32,
    padding_size: u32,
    padding_index: u32,
    total_fields: u32,
};

fn unionLayout(cg: *CodeGen, ty: Type) UnionLayout {
    const zcu = cg.zcu;
    const ip = &zcu.intern_pool;
    const layout = ty.unionGetLayout(zcu);
    const union_obj = zcu.typeToUnion(ty).?;

    var union_layout: UnionLayout = .{
        .has_payload = layout.payload_size != 0,
        .tag_size = @intCast(layout.tag_size),
        .tag_index = undefined,
        .payload_ty = undefined,
        .payload_size = undefined,
        .payload_index = undefined,
        .payload_padding_size = undefined,
        .payload_padding_index = undefined,
        .padding_size = @intCast(layout.padding),
        .padding_index = undefined,
        .total_fields = undefined,
    };

    if (union_layout.has_payload) {
        const most_aligned_field = layout.most_aligned_field;
        const most_aligned_field_ty: Type = .fromInterned(union_obj.field_types.get(ip)[most_aligned_field]);
        union_layout.payload_ty = most_aligned_field_ty;
        union_layout.payload_size = @intCast(most_aligned_field_ty.abiSize(zcu));
    } else {
        union_layout.payload_size = 0;
    }

    union_layout.payload_padding_size = @intCast(layout.payload_size - union_layout.payload_size);

    const tag_first = layout.tag_align.compare(.gte, layout.payload_align);
    var field_index: u32 = 0;

    if (union_layout.tag_size != 0 and tag_first) {
        union_layout.tag_index = field_index;
        field_index += 1;
    }

    if (union_layout.payload_size != 0) {
        union_layout.payload_index = field_index;
        field_index += 1;
    }

    if (union_layout.payload_padding_size != 0) {
        union_layout.payload_padding_index = field_index;
        field_index += 1;
    }

    if (union_layout.tag_size != 0 and !tag_first) {
        union_layout.tag_index = field_index;
        field_index += 1;
    }

    if (union_layout.padding_size != 0) {
        union_layout.padding_index = field_index;
        field_index += 1;
    }

    union_layout.total_fields = field_index;

    return union_layout;
}

/// This structure represents a "temporary" value: Something we are currently
/// operating on. It typically lives no longer than the function that
/// implements a particular AIR operation. These are used to easier
/// implement vectorizable operations (see Vectorization and the build*
/// functions), and typically are only used for vectors of primitive types.
const Temporary = struct {
    /// The type of the temporary. This is here mainly
    /// for easier bookkeeping. Because we will never really
    /// store Temporaries, they only cause extra stack space,
    /// therefore no real storage is wasted.
    ty: Type,
    /// The value that this temporary holds. This is not necessarily
    /// a value that is actually usable, or a single value: It is virtual
    /// until materialize() is called, at which point is turned into
    /// the usual SPIR-V representation of `cg.ty`.
    value: Temporary.Value,

    const Value = union(enum) {
        singleton: Id,
        exploded_vector: IdRange,
    };

    fn init(ty: Type, singleton: Id) Temporary {
        return .{ .ty = ty, .value = .{ .singleton = singleton } };
    }

    fn materialize(temp: Temporary, cg: *CodeGen) !Id {
        const gpa = cg.gpa;
        const zcu = cg.zcu;
        switch (temp.value) {
            .singleton => |id| return id,
            .exploded_vector => |range| {
                assert(temp.ty.isVector(zcu));
                assert(temp.ty.vectorLen(zcu) == range.len);

                const scratch_top = cg.id_scratch.items.len;
                defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
                const constituents = try cg.id_scratch.addManyAsSlice(gpa, range.len);
                for (constituents, 0..range.len) |*id, i| {
                    id.* = range.at(i);
                }

                const result_ty_id = try cg.resolveType(temp.ty, .direct);
                return cg.constructComposite(result_ty_id, constituents);
            },
        }
    }

    fn vectorization(temp: Temporary, cg: *CodeGen) Vectorization {
        return .fromType(temp.ty, cg);
    }

    fn pun(temp: Temporary, new_ty: Type) Temporary {
        return .{
            .ty = new_ty,
            .value = temp.value,
        };
    }

    /// 'Explode' a temporary into separate elements. This turns a vector
    /// into a bag of elements.
    fn explode(temp: Temporary, cg: *CodeGen) !IdRange {
        const zcu = cg.zcu;

        // If the value is a scalar, then this is a no-op.
        if (!temp.ty.isVector(zcu)) {
            return switch (temp.value) {
                .singleton => |id| .{ .base = @intFromEnum(id), .len = 1 },
                .exploded_vector => |range| range,
            };
        }

        const ty_id = try cg.resolveType(temp.ty.scalarType(zcu), .direct);
        const n = temp.ty.vectorLen(zcu);
        const results = cg.allocIds(n);

        const id = switch (temp.value) {
            .singleton => |id| id,
            .exploded_vector => |range| return range,
        };

        for (0..n) |i| {
            const indexes = [_]u32{@intCast(i)};
            try cg.body.emit(cg.gpa, .OpCompositeExtract, .{
                .id_result_type = ty_id,
                .id_result = results.at(i),
                .composite = id,
                .indexes = &indexes,
            });
        }

        return results;
    }
};

/// composite integers are represented as [N]u32 arrays
const CompositeInt = struct {
    cg: *CodeGen,
    limbs: []Id,
    n_limbs: u16,
    info: ArithmeticTypeInfo,

    fn init(cg: *CodeGen, composite_id: Id, info: ArithmeticTypeInfo) !CompositeInt {
        const n_limbs: u16 = info.backing_bits / big_int_bits;
        const gpa = cg.gpa;
        const u32_ty_id = try cg.resolveType(.u32, .direct);
        const limbs = try cg.id_scratch.addManyAsSlice(gpa, n_limbs);
        for (limbs, 0..) |*limb, i| {
            const result_id = cg.allocId();
            try cg.body.emit(gpa, .OpCompositeExtract, .{
                .id_result_type = u32_ty_id,
                .id_result = result_id,
                .composite = composite_id,
                .indexes = &.{@as(u32, @intCast(i))},
            });
            limb.* = result_id;
        }
        return .{ .cg = cg, .limbs = limbs, .n_limbs = n_limbs, .info = info };
    }

    fn fromLimbs(cg: *CodeGen, limbs: []Id, info: ArithmeticTypeInfo) CompositeInt {
        return .{
            .cg = cg,
            .limbs = limbs,
            .n_limbs = @intCast(limbs.len),
            .info = info,
        };
    }

    fn zero(cg: *CodeGen, info: ArithmeticTypeInfo) !CompositeInt {
        const n_limbs: u16 = info.backing_bits / big_int_bits;
        const limbs = try cg.id_scratch.addManyAsSlice(cg.gpa, n_limbs);
        const zero_id = try cg.constInt(.u32, @as(u32, 0));
        for (limbs) |*limb| limb.* = zero_id;
        return .{ .cg = cg, .limbs = limbs, .n_limbs = n_limbs, .info = info };
    }

    fn materialize(ci: CompositeInt, ty: Type) !Id {
        const result_ty_id = try ci.cg.resolveType(ty, .indirect);
        return ci.cg.constructComposite(result_ty_id, ci.limbs);
    }

    fn limbBinOp(ci: CompositeInt, opcode: Opcode, lhs: Id, rhs: Id) !Id {
        const cg = ci.cg;
        const gpa = cg.gpa;
        const u32_ty_id = try cg.resolveType(.u32, .direct);
        const result_id = cg.allocId();
        try cg.body.emitRaw(gpa, opcode, 4);
        cg.body.writeOperand(Id, u32_ty_id);
        cg.body.writeOperand(Id, result_id);
        cg.body.writeOperand(Id, lhs);
        cg.body.writeOperand(Id, rhs);
        return result_id;
    }

    fn limbUnOp(ci: CompositeInt, opcode: Opcode, operand: Id) !Id {
        const cg = ci.cg;
        const gpa = cg.gpa;
        const u32_ty_id = try cg.resolveType(.u32, .direct);
        const result_id = cg.allocId();
        try cg.body.emitRaw(gpa, opcode, 3);
        cg.body.writeOperand(Id, u32_ty_id);
        cg.body.writeOperand(Id, result_id);
        cg.body.writeOperand(Id, operand);
        return result_id;
    }

    fn bitwiseOp(ci: CompositeInt, other: CompositeInt, opcode: Opcode) !CompositeInt {
        const cg = ci.cg;
        const gpa = cg.gpa;
        const result_limbs = try cg.id_scratch.addManyAsSlice(gpa, ci.n_limbs);
        for (result_limbs, 0..) |*r, i| {
            r.* = try ci.limbBinOp(opcode, ci.limbs[i], other.limbs[i]);
        }
        return .fromLimbs(cg, result_limbs, ci.info);
    }

    fn bitwiseNot(ci: CompositeInt) !CompositeInt {
        const cg = ci.cg;
        const gpa = cg.gpa;
        const result_limbs = try cg.id_scratch.addManyAsSlice(gpa, ci.n_limbs);
        for (result_limbs, 0..) |*r, i| {
            r.* = try ci.limbUnOp(.OpNot, ci.limbs[i]);
        }
        return .fromLimbs(cg, result_limbs, ci.info);
    }

    fn cmp(ci: CompositeInt, other: CompositeInt, op: std.math.CompareOperator) !Id {
        const cg = ci.cg;
        const gpa = cg.gpa;
        const bool_ty_id = try cg.resolveType(.bool, .direct);

        switch (op) {
            .eq, .neq => {
                var result = blk: {
                    const r = cg.allocId();
                    try cg.body.emit(gpa, .OpIEqual, .{
                        .id_result_type = bool_ty_id,
                        .id_result = r,
                        .operand_1 = ci.limbs[0],
                        .operand_2 = other.limbs[0],
                    });
                    break :blk r;
                };
                for (1..ci.n_limbs) |i| {
                    const limb_eq = cg.allocId();
                    try cg.body.emit(gpa, .OpIEqual, .{
                        .id_result_type = bool_ty_id,
                        .id_result = limb_eq,
                        .operand_1 = ci.limbs[i],
                        .operand_2 = other.limbs[i],
                    });
                    const combined = cg.allocId();
                    try cg.body.emit(gpa, .OpLogicalAnd, .{
                        .id_result_type = bool_ty_id,
                        .id_result = combined,
                        .operand_1 = result,
                        .operand_2 = limb_eq,
                    });
                    result = combined;
                }
                if (op == .neq) {
                    const negated = cg.allocId();
                    try cg.body.emit(gpa, .OpLogicalNot, .{
                        .id_result_type = bool_ty_id,
                        .id_result = negated,
                        .operand = result,
                    });
                    result = negated;
                }
                return result;
            },
            .lt, .lte, .gt, .gte => {
                const is_lt = (op == .lt or op == .lte);
                const is_strict = (op == .lt or op == .gt);
                var result = try cg.constBool(!is_strict, .direct);

                for (0..ci.n_limbs) |i| {
                    const l = ci.limbs[i];
                    const r = other.limbs[i];
                    const limb_ne = cg.allocId();
                    try cg.body.emit(gpa, .OpINotEqual, .{
                        .id_result_type = bool_ty_id,
                        .id_result = limb_ne,
                        .operand_1 = l,
                        .operand_2 = r,
                    });

                    const is_top = (i == ci.n_limbs - 1);
                    const use_signed = is_top and ci.info.signedness == .signed;
                    var cmp_l = l;
                    var cmp_r = r;
                    if (use_signed) {
                        const i32_ty_id = try cg.resolveType(.i32, .direct);
                        const sl = cg.allocId();
                        try cg.body.emit(gpa, .OpBitcast, .{
                            .id_result_type = i32_ty_id,
                            .id_result = sl,
                            .operand = l,
                        });
                        const sr = cg.allocId();
                        try cg.body.emit(gpa, .OpBitcast, .{
                            .id_result_type = i32_ty_id,
                            .id_result = sr,
                            .operand = r,
                        });
                        cmp_l = sl;
                        cmp_r = sr;
                    }

                    const cmp_opcode: Opcode = if (is_lt)
                        (if (use_signed) .OpSLessThan else .OpULessThan)
                    else
                        (if (use_signed) .OpSGreaterThan else .OpUGreaterThan);

                    const limb_cmp = cg.allocId();
                    try cg.body.emitRaw(gpa, cmp_opcode, 4);
                    cg.body.writeOperand(Id, bool_ty_id);
                    cg.body.writeOperand(Id, limb_cmp);
                    cg.body.writeOperand(Id, cmp_l);
                    cg.body.writeOperand(Id, cmp_r);

                    const selected = cg.allocId();
                    try cg.body.emit(gpa, .OpSelect, .{
                        .id_result_type = bool_ty_id,
                        .id_result = selected,
                        .condition = limb_ne,
                        .object_1 = limb_cmp,
                        .object_2 = result,
                    });
                    result = selected;
                }
                return result;
            },
        }
    }

    fn addSub(ci: CompositeInt, other: CompositeInt, comptime is_add: bool) !CompositeInt {
        const cg = ci.cg;
        const gpa = cg.gpa;
        const pt = cg.pt;
        const zcu = cg.zcu;
        const ip = &zcu.intern_pool;
        const comp = zcu.comp;
        const io = comp.io;

        const u32_zig = try pt.intType(.unsigned, 32);
        const u32_ty_id = try cg.resolveType(.u32, .direct);
        const carry_struct_ty: Type = .fromInterned(try ip.getTupleType(gpa, io, pt.tid, .{
            .types = &.{ u32_zig.toIntern(), u32_zig.toIntern() },
            .values = &.{ .none, .none },
        }));
        const carry_struct_ty_id = try cg.resolveType(carry_struct_ty, .direct);

        const result_limbs = try cg.id_scratch.addManyAsSlice(gpa, ci.n_limbs);
        var carry_id = try cg.constInt(.u32, @as(u32, 0));

        const opcode: Opcode = if (is_add) .OpIAddCarry else .OpISubBorrow;

        for (0..ci.n_limbs) |i| {
            const op1 = cg.allocId();
            try cg.body.emitRaw(gpa, opcode, 4);
            cg.body.writeOperand(Id, carry_struct_ty_id);
            cg.body.writeOperand(Id, op1);
            cg.body.writeOperand(Id, ci.limbs[i]);
            cg.body.writeOperand(Id, other.limbs[i]);

            const sum1 = cg.allocId();
            try cg.body.emit(gpa, .OpCompositeExtract, .{
                .id_result_type = u32_ty_id,
                .id_result = sum1,
                .composite = op1,
                .indexes = &.{0},
            });
            const carry1 = cg.allocId();
            try cg.body.emit(gpa, .OpCompositeExtract, .{
                .id_result_type = u32_ty_id,
                .id_result = carry1,
                .composite = op1,
                .indexes = &.{1},
            });

            const op2 = cg.allocId();
            try cg.body.emitRaw(gpa, opcode, 4);
            cg.body.writeOperand(Id, carry_struct_ty_id);
            cg.body.writeOperand(Id, op2);
            cg.body.writeOperand(Id, sum1);
            cg.body.writeOperand(Id, carry_id);

            result_limbs[i] = cg.allocId();
            try cg.body.emit(gpa, .OpCompositeExtract, .{
                .id_result_type = u32_ty_id,
                .id_result = result_limbs[i],
                .composite = op2,
                .indexes = &.{0},
            });
            const carry2 = cg.allocId();
            try cg.body.emit(gpa, .OpCompositeExtract, .{
                .id_result_type = u32_ty_id,
                .id_result = carry2,
                .composite = op2,
                .indexes = &.{1},
            });

            carry_id = try ci.limbBinOp(.OpBitwiseOr, carry1, carry2);
        }

        return .fromLimbs(cg, result_limbs, ci.info);
    }

    fn shl(ci: CompositeInt, shift_amt_id: Id) !CompositeInt {
        const cg = ci.cg;
        const gpa = cg.gpa;
        const u32_ty_id = try cg.resolveType(.u32, .direct);
        const bool_ty_id = try cg.resolveType(.bool, .direct);
        const zero_id = try cg.constInt(.u32, @as(u32, 0));
        const five_id = try cg.constInt(.u32, @as(u32, 5));
        const thirty_one_id = try cg.constInt(.u32, @as(u32, 31));
        const thirty_two_id = try cg.constInt(.u32, @as(u32, 32));

        const whole = try ci.limbBinOp(.OpShiftRightLogical, shift_amt_id, five_id);
        const frac = try ci.limbBinOp(.OpBitwiseAnd, shift_amt_id, thirty_one_id);
        const comp_frac = try ci.limbBinOp(.OpISub, thirty_two_id, frac);
        const frac_is_zero = blk: {
            const r = cg.allocId();
            try cg.body.emit(gpa, .OpIEqual, .{
                .id_result_type = bool_ty_id,
                .id_result = r,
                .operand_1 = frac,
                .operand_2 = zero_id,
            });
            break :blk r;
        };

        const result_limbs = try cg.id_scratch.addManyAsSlice(gpa, ci.n_limbs);

        for (0..ci.n_limbs) |i| {
            const i_id = try cg.constInt(.u32, @as(u32, @intCast(i)));
            var main_val = zero_id;
            var carry_val = zero_id;

            for (0..ci.n_limbs) |j| {
                const j_id = try cg.constInt(.u32, @as(u32, @intCast(j)));
                const j_plus_whole = try ci.limbBinOp(.OpIAdd, j_id, whole);

                const is_main = blk: {
                    const r = cg.allocId();
                    try cg.body.emit(gpa, .OpIEqual, .{
                        .id_result_type = bool_ty_id,
                        .id_result = r,
                        .operand_1 = j_plus_whole,
                        .operand_2 = i_id,
                    });
                    break :blk r;
                };
                const shifted = try ci.limbBinOp(.OpShiftLeftLogical, ci.limbs[j], frac);
                main_val = blk: {
                    const r = cg.allocId();
                    try cg.body.emit(gpa, .OpSelect, .{
                        .id_result_type = u32_ty_id,
                        .id_result = r,
                        .condition = is_main,
                        .object_1 = shifted,
                        .object_2 = main_val,
                    });
                    break :blk r;
                };

                const one_id = try cg.constInt(.u32, @as(u32, 1));
                const j_plus_whole_plus_1 = try ci.limbBinOp(.OpIAdd, j_plus_whole, one_id);
                const is_carry = blk: {
                    const r = cg.allocId();
                    try cg.body.emit(gpa, .OpIEqual, .{
                        .id_result_type = bool_ty_id,
                        .id_result = r,
                        .operand_1 = j_plus_whole_plus_1,
                        .operand_2 = i_id,
                    });
                    break :blk r;
                };
                const carry_shifted = try ci.limbBinOp(.OpShiftRightLogical, ci.limbs[j], comp_frac);
                const guarded_carry = blk: {
                    const r = cg.allocId();
                    try cg.body.emit(gpa, .OpSelect, .{
                        .id_result_type = u32_ty_id,
                        .id_result = r,
                        .condition = frac_is_zero,
                        .object_1 = zero_id,
                        .object_2 = carry_shifted,
                    });
                    break :blk r;
                };
                carry_val = blk: {
                    const r = cg.allocId();
                    try cg.body.emit(gpa, .OpSelect, .{
                        .id_result_type = u32_ty_id,
                        .id_result = r,
                        .condition = is_carry,
                        .object_1 = guarded_carry,
                        .object_2 = carry_val,
                    });
                    break :blk r;
                };
            }

            result_limbs[i] = try ci.limbBinOp(.OpBitwiseOr, main_val, carry_val);
        }

        return .fromLimbs(cg, result_limbs, ci.info);
    }

    fn shr(ci: CompositeInt, shift_amt_id: Id, comptime is_arithmetic: bool) !CompositeInt {
        const cg = ci.cg;
        const gpa = cg.gpa;
        const u32_ty_id = try cg.resolveType(.u32, .direct);
        const bool_ty_id = try cg.resolveType(.bool, .direct);
        const zero_id = try cg.constInt(.u32, @as(u32, 0));
        const five_id = try cg.constInt(.u32, @as(u32, 5));
        const thirty_one_id = try cg.constInt(.u32, @as(u32, 31));
        const thirty_two_id = try cg.constInt(.u32, @as(u32, 32));

        const whole = try ci.limbBinOp(.OpShiftRightLogical, shift_amt_id, five_id);
        const frac = try ci.limbBinOp(.OpBitwiseAnd, shift_amt_id, thirty_one_id);
        const comp_frac = try ci.limbBinOp(.OpISub, thirty_two_id, frac);
        const frac_is_zero = blk: {
            const r = cg.allocId();
            try cg.body.emit(gpa, .OpIEqual, .{
                .id_result_type = bool_ty_id,
                .id_result = r,
                .operand_1 = frac,
                .operand_2 = zero_id,
            });
            break :blk r;
        };

        const fill_id = if (is_arithmetic) blk: {
            const i32_ty_id = try cg.resolveType(.i32, .direct);
            const msb_signed = cg.allocId();
            try cg.body.emit(gpa, .OpBitcast, .{
                .id_result_type = i32_ty_id,
                .id_result = msb_signed,
                .operand = ci.limbs[ci.n_limbs - 1],
            });
            const shift31 = try cg.constInt(.i32, @as(i32, 31));
            const sign_ext = cg.allocId();
            try cg.body.emit(gpa, .OpShiftRightArithmetic, .{
                .id_result_type = i32_ty_id,
                .id_result = sign_ext,
                .base = msb_signed,
                .shift = shift31,
            });
            const back = cg.allocId();
            try cg.body.emit(gpa, .OpBitcast, .{
                .id_result_type = u32_ty_id,
                .id_result = back,
                .operand = sign_ext,
            });
            break :blk back;
        } else zero_id;

        const result_limbs = try cg.id_scratch.addManyAsSlice(gpa, ci.n_limbs);

        const arith_carry_init = if (is_arithmetic) blk: {
            const shifted_fill = try ci.limbBinOp(.OpShiftLeftLogical, fill_id, comp_frac);
            const guarded = cg.allocId();
            try cg.body.emit(gpa, .OpSelect, .{
                .id_result_type = u32_ty_id,
                .id_result = guarded,
                .condition = frac_is_zero,
                .object_1 = zero_id,
                .object_2 = shifted_fill,
            });
            break :blk guarded;
        } else zero_id;

        for (0..ci.n_limbs) |i| {
            const i_id = try cg.constInt(.u32, @as(u32, @intCast(i)));
            var main_val = fill_id;
            var carry_val = arith_carry_init;

            for (0..ci.n_limbs) |j| {
                const j_id = try cg.constInt(.u32, @as(u32, @intCast(j)));
                const i_plus_whole = try ci.limbBinOp(.OpIAdd, i_id, whole);
                const is_main = blk: {
                    const r = cg.allocId();
                    try cg.body.emit(gpa, .OpIEqual, .{
                        .id_result_type = bool_ty_id,
                        .id_result = r,
                        .operand_1 = j_id,
                        .operand_2 = i_plus_whole,
                    });
                    break :blk r;
                };
                const shifted = try ci.limbBinOp(.OpShiftRightLogical, ci.limbs[j], frac);
                main_val = blk: {
                    const r = cg.allocId();
                    try cg.body.emit(gpa, .OpSelect, .{
                        .id_result_type = u32_ty_id,
                        .id_result = r,
                        .condition = is_main,
                        .object_1 = shifted,
                        .object_2 = main_val,
                    });
                    break :blk r;
                };

                const one_id = try cg.constInt(.u32, @as(u32, 1));
                const i_plus_whole_plus_1 = try ci.limbBinOp(.OpIAdd, i_plus_whole, one_id);
                const is_carry = blk: {
                    const r = cg.allocId();
                    try cg.body.emit(gpa, .OpIEqual, .{
                        .id_result_type = bool_ty_id,
                        .id_result = r,
                        .operand_1 = j_id,
                        .operand_2 = i_plus_whole_plus_1,
                    });
                    break :blk r;
                };
                const carry_shifted = try ci.limbBinOp(.OpShiftLeftLogical, ci.limbs[j], comp_frac);
                const guarded_carry = blk: {
                    const r = cg.allocId();
                    try cg.body.emit(gpa, .OpSelect, .{
                        .id_result_type = u32_ty_id,
                        .id_result = r,
                        .condition = frac_is_zero,
                        .object_1 = zero_id,
                        .object_2 = carry_shifted,
                    });
                    break :blk r;
                };
                carry_val = blk: {
                    const r = cg.allocId();
                    try cg.body.emit(gpa, .OpSelect, .{
                        .id_result_type = u32_ty_id,
                        .id_result = r,
                        .condition = is_carry,
                        .object_1 = guarded_carry,
                        .object_2 = carry_val,
                    });
                    break :blk r;
                };
            }

            result_limbs[i] = try ci.limbBinOp(.OpBitwiseOr, main_val, carry_val);
        }

        return .fromLimbs(cg, result_limbs, ci.info);
    }

    fn mul(ci: CompositeInt, other: CompositeInt, comptime wide: bool) ![]Id {
        const cg = ci.cg;
        const gpa = cg.gpa;
        const pt = cg.pt;
        const zcu = cg.zcu;
        const ip = &zcu.intern_pool;
        const comp = zcu.comp;
        const io = comp.io;
        const target = zcu.getTarget();

        const n: usize = ci.n_limbs;
        const total: usize = if (wide) 2 * n else n;
        const u32_zig = try pt.intType(.unsigned, 32);
        const u32_ty_id = try cg.resolveType(.u32, .direct);

        const pair_struct_ty: Type = .fromInterned(try ip.getTupleType(gpa, io, pt.tid, .{
            .types = &.{ u32_zig.toIntern(), u32_zig.toIntern() },
            .values = &.{ .none, .none },
        }));
        const pair_struct_ty_id = try cg.resolveType(pair_struct_ty, .direct);

        const result_limbs = try cg.id_scratch.addManyAsSlice(gpa, total);
        const zero_id = try cg.constInt(.u32, @as(u32, 0));
        for (result_limbs) |*r| r.* = zero_id;

        for (0..n) |i| {
            var carry_id = zero_id;
            for (0..n) |j| {
                const k = i + j;
                if (k >= total) break;

                var lo: Id = undefined;
                var hi: Id = undefined;
                switch (target.os.tag) {
                    .opencl => {
                        lo = cg.allocId();
                        try cg.body.emit(gpa, .OpIMul, .{
                            .id_result_type = u32_ty_id,
                            .id_result = lo,
                            .operand_1 = ci.limbs[i],
                            .operand_2 = other.limbs[j],
                        });

                        const set = try cg.importExtendedSet();
                        hi = cg.allocId();
                        try cg.body.emit(gpa, .OpExtInst, .{
                            .id_result_type = u32_ty_id,
                            .id_result = hi,
                            .set = set,
                            .instruction = .{ .inst = @intFromEnum(spec.OpenClOpcode.u_mul_hi) },
                            .id_ref_4 = &.{ ci.limbs[i], other.limbs[j] },
                        });
                    },
                    else => {
                        const mul_result = cg.allocId();
                        try cg.body.emit(gpa, .OpUMulExtended, .{
                            .id_result_type = pair_struct_ty_id,
                            .id_result = mul_result,
                            .operand_1 = ci.limbs[i],
                            .operand_2 = other.limbs[j],
                        });

                        lo = cg.allocId();
                        try cg.body.emit(gpa, .OpCompositeExtract, .{
                            .id_result_type = u32_ty_id,
                            .id_result = lo,
                            .composite = mul_result,
                            .indexes = &.{0},
                        });
                        hi = cg.allocId();
                        try cg.body.emit(gpa, .OpCompositeExtract, .{
                            .id_result_type = u32_ty_id,
                            .id_result = hi,
                            .composite = mul_result,
                            .indexes = &.{1},
                        });
                    },
                }

                const add1 = cg.allocId();
                try cg.body.emit(gpa, .OpIAddCarry, .{
                    .id_result_type = pair_struct_ty_id,
                    .id_result = add1,
                    .operand_1 = result_limbs[k],
                    .operand_2 = lo,
                });

                const sum1 = cg.allocId();
                try cg.body.emit(gpa, .OpCompositeExtract, .{
                    .id_result_type = u32_ty_id,
                    .id_result = sum1,
                    .composite = add1,
                    .indexes = &.{0},
                });
                const c1 = cg.allocId();
                try cg.body.emit(gpa, .OpCompositeExtract, .{
                    .id_result_type = u32_ty_id,
                    .id_result = c1,
                    .composite = add1,
                    .indexes = &.{1},
                });

                const add2 = cg.allocId();
                try cg.body.emit(gpa, .OpIAddCarry, .{
                    .id_result_type = pair_struct_ty_id,
                    .id_result = add2,
                    .operand_1 = sum1,
                    .operand_2 = carry_id,
                });

                result_limbs[k] = cg.allocId();
                try cg.body.emit(gpa, .OpCompositeExtract, .{
                    .id_result_type = u32_ty_id,
                    .id_result = result_limbs[k],
                    .composite = add2,
                    .indexes = &.{0},
                });
                const c2 = cg.allocId();
                try cg.body.emit(gpa, .OpCompositeExtract, .{
                    .id_result_type = u32_ty_id,
                    .id_result = c2,
                    .composite = add2,
                    .indexes = &.{1},
                });

                const hi_plus_c1 = try ci.limbBinOp(.OpIAdd, hi, c1);
                carry_id = try ci.limbBinOp(.OpIAdd, hi_plus_c1, c2);
            }
            if (wide and i + n < 2 * n) {
                result_limbs[i + n] = try ci.limbBinOp(.OpIAdd, result_limbs[i + n], carry_id);
            }
        }

        return result_limbs;
    }

    fn normalize(ci: CompositeInt) !CompositeInt {
        if (ci.info.bits == ci.info.backing_bits) return ci;
        const cg = ci.cg;
        const gpa = cg.gpa;
        const top_bits: u16 = ci.info.bits % big_int_bits;
        assert(top_bits != 0);

        const result_limbs = try cg.id_scratch.addManyAsSlice(gpa, ci.n_limbs);
        for (0..ci.n_limbs - 1) |i| {
            result_limbs[i] = ci.limbs[i];
        }

        const top_limb = ci.limbs[ci.n_limbs - 1];
        switch (ci.info.signedness) {
            .unsigned => {
                const mask_val: u32 = (@as(u32, 1) << @as(u5, @intCast(top_bits))) - 1;
                const mask_id = try cg.constInt(.u32, mask_val);
                result_limbs[ci.n_limbs - 1] = try ci.limbBinOp(.OpBitwiseAnd, top_limb, mask_id);
            },
            .signed => {
                const u32_ty_id = try cg.resolveType(.u32, .direct);
                const i32_ty_id = try cg.resolveType(.i32, .direct);
                const shift_amt: u32 = 32 - top_bits;
                const shift_id = try cg.constInt(.u32, shift_amt);

                const as_signed = cg.allocId();
                try cg.body.emit(gpa, .OpBitcast, .{
                    .id_result_type = i32_ty_id,
                    .id_result = as_signed,
                    .operand = top_limb,
                });
                const shifted_left = cg.allocId();
                try cg.body.emit(gpa, .OpShiftLeftLogical, .{
                    .id_result_type = i32_ty_id,
                    .id_result = shifted_left,
                    .base = as_signed,
                    .shift = shift_id,
                });
                const shifted_right = cg.allocId();
                try cg.body.emit(gpa, .OpShiftRightArithmetic, .{
                    .id_result_type = i32_ty_id,
                    .id_result = shifted_right,
                    .base = shifted_left,
                    .shift = shift_id,
                });
                const back = cg.allocId();
                try cg.body.emit(gpa, .OpBitcast, .{
                    .id_result_type = u32_ty_id,
                    .id_result = back,
                    .operand = shifted_right,
                });
                result_limbs[ci.n_limbs - 1] = back;
            },
        }

        return .fromLimbs(cg, result_limbs, ci.info);
    }
};

/// Initialize a `Temporary` from an AIR value.
fn temporary(cg: *CodeGen, inst: Air.Inst.Ref) !Temporary {
    return .{
        .ty = cg.typeOf(inst),
        .value = .{ .singleton = try cg.resolve(inst) },
    };
}

/// This union describes how a particular operation should be vectorized.
/// That depends on the operation and number of components of the inputs.
const Vectorization = union(enum) {
    /// This is an operation between scalars.
    scalar,
    /// This operation is unrolled into separate operations.
    /// Inputs may still be SPIR-V vectors, for example,
    /// when the operation can't be vectorized in SPIR-V.
    /// Value is number of components.
    unrolled: u32,

    /// Derive a vectorization from a particular type
    fn fromType(ty: Type, cg: *CodeGen) Vectorization {
        const zcu = cg.zcu;
        if (!ty.isVector(zcu)) return .scalar;
        return .{ .unrolled = ty.vectorLen(zcu) };
    }

    /// Given two vectorization methods, compute a "unification": a fallback
    /// that works for both, according to the following rules:
    /// - Scalars may broadcast
    /// - SPIR-V vectorized operations will unroll
    /// - Prefer scalar > unrolled
    fn unify(a: Vectorization, b: Vectorization) Vectorization {
        if (a == .scalar and b == .scalar) return .scalar;
        if (a == .unrolled or b == .unrolled) {
            if (a == .unrolled and b == .unrolled) assert(a.components() == b.components());
            if (a == .unrolled) return .{ .unrolled = a.components() };
            return .{ .unrolled = b.components() };
        }
        unreachable;
    }

    /// Query the number of components that inputs of this operation have.
    /// Note: for broadcasting scalars, this returns the number of elements
    /// that the broadcasted vector would have.
    fn components(vec: Vectorization) u32 {
        return switch (vec) {
            .scalar => 1,
            .unrolled => |n| n,
        };
    }

    /// Turns `ty` into the result-type of the entire operation.
    /// `ty` may be a scalar or vector, it doesn't matter.
    fn resultType(vec: Vectorization, cg: *CodeGen, ty: Type) !Type {
        const pt = cg.pt;
        const zcu = cg.zcu;
        const scalar_ty = ty.scalarType(zcu);
        return switch (vec) {
            .scalar => scalar_ty,
            .unrolled => |n| try pt.vectorType(.{ .len = n, .child = scalar_ty.toIntern() }),
        };
    }

    /// Before a temporary can be used, some setup may need to be one. This function implements
    /// this setup, and returns a new type that holds the relevant information on how to access
    /// elements of the input.
    fn prepare(vec: Vectorization, cg: *CodeGen, tmp: Temporary) !PreparedOperand {
        const zcu = cg.zcu;
        const is_vector = tmp.ty.isVector(zcu);
        const value: PreparedOperand.Value = switch (tmp.value) {
            .singleton => |id| switch (vec) {
                .scalar => blk: {
                    assert(!is_vector);
                    break :blk .{ .scalar = id };
                },
                .unrolled => blk: {
                    if (is_vector) break :blk .{ .vector_exploded = try tmp.explode(cg) };
                    break :blk .{ .scalar_broadcast = id };
                },
            },
            .exploded_vector => |range| switch (vec) {
                .scalar => unreachable,
                .unrolled => |n| blk: {
                    assert(range.len == n);
                    break :blk .{ .vector_exploded = range };
                },
            },
        };

        return .{
            .ty = tmp.ty,
            .value = value,
        };
    }

    /// Finalize the results of an operation back into a temporary. `results` is
    /// a list of result-ids of the operation.
    fn finalize(vec: Vectorization, ty: Type, results: IdRange) Temporary {
        assert(vec.components() == results.len);
        return .{
            .ty = ty,
            .value = switch (vec) {
                .scalar => .{ .singleton = results.at(0) },
                .unrolled => .{ .exploded_vector = results },
            },
        };
    }

    /// This struct represents an operand that has gone through some setup, and is
    /// ready to be used as part of an operation.
    const PreparedOperand = struct {
        ty: Type,
        value: PreparedOperand.Value,

        /// The types of value that a prepared operand can hold internally. Depends
        /// on the operation and input value.
        const Value = union(enum) {
            /// A single scalar value that is used by a scalar operation.
            scalar: Id,
            /// A single scalar that is broadcasted in an unrolled operation.
            scalar_broadcast: Id,
            /// A vector represented by a consecutive list of IDs that is used in an unrolled operation.
            vector_exploded: IdRange,
        };

        /// Query the value at a particular index of the operation. Note that
        /// the index is *not* the component/lane, but the index of the *operation*.
        fn at(op: PreparedOperand, i: usize) Id {
            switch (op.value) {
                .scalar => |id| {
                    assert(i == 0);
                    return id;
                },
                .scalar_broadcast => |id| return id,
                .vector_exploded => |range| return range.at(i),
            }
        }
    };
};

/// A utility function to compute the vectorization style of
/// a list of values. These values may be any of the following:
/// - A `Vectorization` instance
/// - A Type, in which case the vectorization is computed via `Vectorization.fromType`.
/// - A Temporary, in which case the vectorization is computed via `Temporary.vectorization`.
fn vectorization(cg: *CodeGen, args: anytype) Vectorization {
    var v: Vectorization = undefined;
    assert(args.len >= 1);
    inline for (args, 0..) |arg, i| {
        const iv: Vectorization = switch (@TypeOf(arg)) {
            Vectorization => arg,
            Type => Vectorization.fromType(arg, cg),
            Temporary => arg.vectorization(cg),
            else => @compileError("invalid type"),
        };
        if (i == 0) {
            v = iv;
        } else {
            v = v.unify(iv);
        }
    }
    return v;
}

/// This function builds an OpSConvert of OpUConvert depending on the
/// signedness of the types.
fn buildConvert(cg: *CodeGen, dst_ty: Type, src: Temporary) !Temporary {
    const zcu = cg.zcu;

    const v = cg.vectorization(.{ dst_ty, src });
    const result_ty = try v.resultType(cg, dst_ty);

    const dst_scalar = dst_ty.scalarType(zcu);
    const src_scalar = src.ty.scalarType(zcu);
    if (dst_scalar.toIntern() == src_scalar.toIntern()) {
        return src.pun(result_ty);
    }
    if (dst_scalar.isInt(zcu) and src_scalar.isInt(zcu)) {
        const dst_info = dst_scalar.intInfo(zcu);
        const src_info = src_scalar.intInfo(zcu);
        if (cg.backingIntBits(dst_info.bits).@"0" == cg.backingIntBits(src_info.bits).@"0" and
            dst_info.signedness == src_info.signedness)
        {
            return src.pun(result_ty);
        }
    }

    const ops = v.components();
    const results = cg.allocIds(ops);

    const op_result_ty = dst_ty.scalarType(zcu);
    const op_result_ty_id = try cg.resolveType(op_result_ty, .direct);

    const opcode: Opcode = blk: {
        if (dst_ty.scalarType(zcu).isAnyFloat()) break :blk .OpFConvert;
        if (dst_ty.scalarType(zcu).isSignedInt(zcu)) break :blk .OpSConvert;
        break :blk .OpUConvert;
    };

    const op_src = try v.prepare(cg, src);

    for (0..ops) |i| {
        try cg.body.emitRaw(cg.gpa, opcode, 3);
        cg.body.writeOperand(Id, op_result_ty_id);
        cg.body.writeOperand(Id, results.at(i));
        cg.body.writeOperand(Id, op_src.at(i));
    }

    return v.finalize(result_ty, results);
}

fn buildSelect(cg: *CodeGen, condition: Temporary, lhs: Temporary, rhs: Temporary) !Temporary {
    const zcu = cg.zcu;

    const v = cg.vectorization(.{ condition, lhs, rhs });
    const ops = v.components();
    const results = cg.allocIds(ops);

    const op_result_ty = lhs.ty.scalarType(zcu);
    const op_result_ty_id = try cg.resolveType(op_result_ty, .direct);
    const result_ty = try v.resultType(cg, lhs.ty);

    assert(condition.ty.scalarType(zcu).zigTypeTag(zcu) == .bool);

    const cond = try v.prepare(cg, condition);
    const object_1 = try v.prepare(cg, lhs);
    const object_2 = try v.prepare(cg, rhs);

    for (0..ops) |i| {
        try cg.body.emit(cg.gpa, .OpSelect, .{
            .id_result_type = op_result_ty_id,
            .id_result = results.at(i),
            .condition = cond.at(i),
            .object_1 = object_1.at(i),
            .object_2 = object_2.at(i),
        });
    }

    return v.finalize(result_ty, results);
}

fn buildCmp(cg: *CodeGen, opcode: Opcode, lhs: Temporary, rhs: Temporary) !Temporary {
    const v = cg.vectorization(.{ lhs, rhs });
    const ops = v.components();
    const results = cg.allocIds(ops);

    const op_result_ty: Type = .bool;
    const op_result_ty_id = try cg.resolveType(op_result_ty, .direct);
    const result_ty = try v.resultType(cg, Type.bool);

    const op_lhs = try v.prepare(cg, lhs);
    const op_rhs = try v.prepare(cg, rhs);

    for (0..ops) |i| {
        try cg.body.emitRaw(cg.gpa, opcode, 4);
        cg.body.writeOperand(Id, op_result_ty_id);
        cg.body.writeOperand(Id, results.at(i));
        cg.body.writeOperand(Id, op_lhs.at(i));
        cg.body.writeOperand(Id, op_rhs.at(i));
    }

    return v.finalize(result_ty, results);
}

const UnaryOp = enum {
    l_not,
    bit_not,
    i_neg,
    f_neg,
    i_abs,
    f_abs,
    clz,
    ctz,
    floor,
    ceil,
    trunc,
    round,
    sqrt,
    sin,
    cos,
    tan,
    exp,
    exp2,
    log,
    log2,
    log10,

    pub fn extInstOpcode(op: UnaryOp, target: *const std.Target) ?u32 {
        return switch (target.os.tag) {
            .opencl => @intFromEnum(@as(spec.OpenClOpcode, switch (op) {
                .i_abs => .s_abs,
                .f_abs => .fabs,
                .clz => .clz,
                .ctz => .ctz,
                .floor => .floor,
                .ceil => .ceil,
                .trunc => .trunc,
                .round => .round,
                .sqrt => .sqrt,
                .sin => .sin,
                .cos => .cos,
                .tan => .tan,
                .exp => .exp,
                .exp2 => .exp2,
                .log => .log,
                .log2 => .log2,
                .log10 => .log10,
                else => return null,
            })),
            // Note: We'll need to check these for floating point accuracy
            // Vulkan does not put tight requirements on these, for correction
            // we might want to emulate them at some point.
            .vulkan, .opengl => @intFromEnum(@as(spec.GlslOpcode, switch (op) {
                .i_abs => .SAbs,
                .f_abs => .FAbs,
                .floor => .Floor,
                .ceil => .Ceil,
                .trunc => .Trunc,
                .round => .Round,
                .sin => .Sin,
                .cos => .Cos,
                .tan => .Tan,
                .sqrt => .Sqrt,
                .exp => .Exp,
                .exp2 => .Exp2,
                .log => .Log,
                .log2 => .Log2,
                else => return null,
            })),
            else => unreachable,
        };
    }
};

fn buildUnary(cg: *CodeGen, op: UnaryOp, operand: Temporary) !Temporary {
    const zcu = cg.zcu;
    const target = cg.zcu.getTarget();
    const v = cg.vectorization(.{operand});
    const ops = v.components();
    const results = cg.allocIds(ops);
    const op_result_ty = operand.ty.scalarType(zcu);
    const op_result_ty_id = try cg.resolveType(op_result_ty, .direct);
    const result_ty = try v.resultType(cg, operand.ty);
    const op_operand = try v.prepare(cg, operand);

    if (op.extInstOpcode(target)) |opcode| {
        const set = try cg.importExtendedSet();
        for (0..ops) |i| {
            try cg.body.emit(cg.gpa, .OpExtInst, .{
                .id_result_type = op_result_ty_id,
                .id_result = results.at(i),
                .set = set,
                .instruction = .{ .inst = opcode },
                .id_ref_4 = &.{op_operand.at(i)},
            });
        }
    } else {
        const opcode: Opcode = switch (op) {
            .l_not => .OpLogicalNot,
            .bit_not => .OpNot,
            .i_neg => .OpSNegate,
            .f_neg => .OpFNegate,
            else => return cg.todo(
                "implement unary operation '{s}' for {s} os",
                .{ @tagName(op), @tagName(target.os.tag) },
            ),
        };
        for (0..ops) |i| {
            try cg.body.emitRaw(cg.gpa, opcode, 3);
            cg.body.writeOperand(Id, op_result_ty_id);
            cg.body.writeOperand(Id, results.at(i));
            cg.body.writeOperand(Id, op_operand.at(i));
        }
    }

    return v.finalize(result_ty, results);
}

fn buildBinary(cg: *CodeGen, opcode: Opcode, lhs: Temporary, rhs: Temporary) !Temporary {
    const zcu = cg.zcu;

    const v = cg.vectorization(.{ lhs, rhs });
    const ops = v.components();
    const results = cg.allocIds(ops);

    const op_result_ty = lhs.ty.scalarType(zcu);
    const op_result_ty_id = try cg.resolveType(op_result_ty, .direct);
    const result_ty = try v.resultType(cg, lhs.ty);

    const op_lhs = try v.prepare(cg, lhs);
    const op_rhs = try v.prepare(cg, rhs);

    for (0..ops) |i| {
        try cg.body.emitRaw(cg.gpa, opcode, 4);
        cg.body.writeOperand(Id, op_result_ty_id);
        cg.body.writeOperand(Id, results.at(i));
        cg.body.writeOperand(Id, op_lhs.at(i));
        cg.body.writeOperand(Id, op_rhs.at(i));
    }

    return v.finalize(result_ty, results);
}

/// This function builds an extended multiplication, either OpSMulExtended or OpUMulExtended on Vulkan,
/// or OpIMul and s_mul_hi or u_mul_hi on OpenCL.
fn buildWideMul(
    cg: *CodeGen,
    signedness: std.lang.Signedness,
    lhs: Temporary,
    rhs: Temporary,
) !struct { Temporary, Temporary } {
    const pt = cg.pt;
    const zcu = cg.zcu;
    const comp = zcu.comp;
    const gpa = comp.gpa;
    const io = comp.io;
    const target = cg.zcu.getTarget();
    const ip = &zcu.intern_pool;

    const v = lhs.vectorization(cg).unify(rhs.vectorization(cg));
    const ops = v.components();

    const arith_op_ty = lhs.ty.scalarType(zcu);
    const arith_op_ty_id = try cg.resolveType(arith_op_ty, .direct);

    const lhs_op = try v.prepare(cg, lhs);
    const rhs_op = try v.prepare(cg, rhs);

    const value_results = cg.allocIds(ops);
    const overflow_results = cg.allocIds(ops);

    switch (target.os.tag) {
        .opencl => {
            // Currently, SPIRV-LLVM-Translator based backends cannot deal with OpSMulExtended and
            // OpUMulExtended. For these we will use the OpenCL s_mul_hi to compute the high-order bits
            // instead.
            const set = try cg.importExtendedSet();
            const overflow_inst: spec.OpenClOpcode = switch (signedness) {
                .signed => .s_mul_hi,
                .unsigned => .u_mul_hi,
            };

            for (0..ops) |i| {
                try cg.body.emit(gpa, .OpIMul, .{
                    .id_result_type = arith_op_ty_id,
                    .id_result = value_results.at(i),
                    .operand_1 = lhs_op.at(i),
                    .operand_2 = rhs_op.at(i),
                });

                try cg.body.emit(gpa, .OpExtInst, .{
                    .id_result_type = arith_op_ty_id,
                    .id_result = overflow_results.at(i),
                    .set = set,
                    .instruction = .{ .inst = @intFromEnum(overflow_inst) },
                    .id_ref_4 = &.{ lhs_op.at(i), rhs_op.at(i) },
                });
            }
        },
        .vulkan, .opengl => {
            // Operations return a struct{T, T}
            // where T is maybe vectorized.
            const op_result_ty: Type = .fromInterned(try ip.getTupleType(gpa, io, pt.tid, .{
                .types = &.{ arith_op_ty.toIntern(), arith_op_ty.toIntern() },
                .values = &.{ .none, .none },
            }));
            const op_result_ty_id = try cg.resolveType(op_result_ty, .direct);

            const opcode: Opcode = switch (signedness) {
                .signed => .OpSMulExtended,
                .unsigned => .OpUMulExtended,
            };

            for (0..ops) |i| {
                const op_result = cg.allocId();

                try cg.body.emitRaw(gpa, opcode, 4);
                cg.body.writeOperand(Id, op_result_ty_id);
                cg.body.writeOperand(Id, op_result);
                cg.body.writeOperand(Id, lhs_op.at(i));
                cg.body.writeOperand(Id, rhs_op.at(i));

                // The above operation returns a struct. We might want to expand
                // Temporary to deal with the fact that these are structs eventually,
                // but for now, take the struct apart and return two separate vectors.

                try cg.body.emit(gpa, .OpCompositeExtract, .{
                    .id_result_type = arith_op_ty_id,
                    .id_result = value_results.at(i),
                    .composite = op_result,
                    .indexes = &.{0},
                });

                try cg.body.emit(gpa, .OpCompositeExtract, .{
                    .id_result_type = arith_op_ty_id,
                    .id_result = overflow_results.at(i),
                    .composite = op_result,
                    .indexes = &.{1},
                });
            }
        },
        else => unreachable,
    }

    const result_ty = try v.resultType(cg, lhs.ty);
    return .{
        v.finalize(result_ty, value_results),
        v.finalize(result_ty, overflow_results),
    };
}

/// The SPIR-V backend is not yet advanced enough to support the std testing infrastructure.
/// In order to be able to run tests, we "temporarily" lower test kernels into separate entry-
/// points. The test executor will then be able to invoke these to run the tests.
/// Note that tests are lowered according to std.lang.TestFn, which is `fn () anyerror!void`.
/// (anyerror!void has the same layout as anyerror).
/// Each test declaration generates a function like.
///   %anyerror = OpTypeInt 0 16
///   %p_invocation_globals_struct_ty = ...
///   %p_anyerror = OpTypePointer CrossWorkgroup %anyerror
///   %K = OpTypeFunction %void %p_invocation_globals_struct_ty %p_anyerror
///
///   %test = OpFunction %void %K
///   %p_invocation_globals = OpFunctionParameter p_invocation_globals_struct_ty
///   %p_err = OpFunctionParameter %p_anyerror
///   %lbl = OpLabel
///   %result = OpFunctionCall %anyerror %func %p_invocation_globals
///   OpStore %p_err %result
///   OpFunctionEnd
/// TODO is to also write out the error as a function call parameter, and to somehow fetch
/// the name of an error in the text executor.
fn generateTestEntryPoint(
    cg: *CodeGen,
    name: []const u8,
    spv_decl_index: Decl.Index,
    test_id: Id,
) !void {
    const gpa = cg.gpa;
    const zcu = cg.zcu;
    const target = cg.zcu.getTarget();

    const anyerror_ty_id = try cg.resolveType(.anyerror, .direct);
    const ptr_anyerror_ty = try cg.pt.ptrType(.{
        .child = .anyerror_type,
        .flags = .{ .address_space = .global },
    });
    const ptr_anyerror_ty_id = try cg.resolveType(ptr_anyerror_ty, .direct);

    const kernel_id = cg.declPtr(spv_decl_index).result_id;

    const section = &cg.sections.functions;

    const p_error_id = cg.allocId();
    switch (target.os.tag) {
        .opencl, .amdhsa => {
            const void_ty_id = try cg.resolveType(.void, .direct);
            const kernel_proto_ty_id = try cg.functionType(void_ty_id, &.{ptr_anyerror_ty_id});

            try section.emit(gpa, .OpFunction, .{
                .id_result_type = try cg.resolveType(.void, .direct),
                .id_result = kernel_id,
                .function_control = .{},
                .function_type = kernel_proto_ty_id,
            });

            try section.emit(gpa, .OpFunctionParameter, .{
                .id_result_type = ptr_anyerror_ty_id,
                .id_result = p_error_id,
            });

            try section.emit(gpa, .OpLabel, .{
                .id_result = cg.allocId(),
            });
        },
        .vulkan, .opengl => {
            if (cg.error_buffer == null) {
                const spv_err_decl_index = try cg.allocDecl(.global);
                const err_buf_result_id = cg.declPtr(spv_err_decl_index).result_id;

                const buffer_struct_ty_id = cg.allocId();
                try cg.sections.globals.emit(gpa, .OpTypeStruct, .{
                    .id_result = buffer_struct_ty_id,
                    .id_ref = &.{anyerror_ty_id},
                });
                try cg.memberDebugName(buffer_struct_ty_id, 0, "error_out");
                try cg.decorate(buffer_struct_ty_id, .block);
                try cg.decorateMember(buffer_struct_ty_id, 0, .{ .offset = .{ .byte_offset = 0 } });

                const ptr_buffer_struct_ty_id = cg.allocId();
                try cg.sections.globals.emit(gpa, .OpTypePointer, .{
                    .id_result = ptr_buffer_struct_ty_id,
                    .storage_class = cg.storageClass(.global),
                    .type = buffer_struct_ty_id,
                });

                try cg.sections.globals.emit(gpa, .OpVariable, .{
                    .id_result_type = ptr_buffer_struct_ty_id,
                    .id_result = err_buf_result_id,
                    .storage_class = cg.storageClass(.global),
                });
                try cg.decorate(err_buf_result_id, .{ .descriptor_set = .{ .descriptor_set = 0 } });
                try cg.decorate(err_buf_result_id, .{ .binding = .{ .binding_point = 0 } });

                cg.error_buffer = spv_err_decl_index;
            }

            const void_ty_id = try cg.resolveType(.void, .direct);
            const kernel_proto_ty_id = try cg.functionType(void_ty_id, &.{});
            try section.emit(gpa, .OpFunction, .{
                .id_result_type = try cg.resolveType(.void, .direct),
                .id_result = kernel_id,
                .function_control = .{},
                .function_type = kernel_proto_ty_id,
            });
            try section.emit(gpa, .OpLabel, .{
                .id_result = cg.allocId(),
            });

            const spv_err_decl_index = cg.error_buffer.?;
            const buffer_id = cg.declPtr(spv_err_decl_index).result_id;
            try cg.decl_deps.append(gpa, spv_err_decl_index);

            const zero_id = try cg.constInt(.u32, 0);
            try section.emit(gpa, .OpInBoundsAccessChain, .{
                .id_result_type = ptr_anyerror_ty_id,
                .id_result = p_error_id,
                .base = buffer_id,
                .indexes = &.{zero_id},
            });
        },
        else => unreachable,
    }

    const error_id = cg.allocId();
    try section.emit(gpa, .OpFunctionCall, .{
        .id_result_type = anyerror_ty_id,
        .id_result = error_id,
        .function = test_id,
    });
    // Note: Convert to direct not required.
    try section.emit(gpa, .OpStore, .{
        .pointer = p_error_id,
        .object = error_id,
        .memory_access = .{
            .aligned = .{ .literal_integer = @intCast(Type.abiAlignment(.anyerror, zcu).toByteUnits().?) },
        },
    });
    try section.emit(gpa, .OpReturn, {});
    try section.emit(gpa, .OpFunctionEnd, {});

    // Just generate a quick other name because the intel runtime crashes when the entry-
    // point name is the same as a different OpName.
    const test_name = try std.fmt.allocPrint(cg.arena, "test {s}", .{name});

    const ep_gop = try cg.entry_points.getOrPut(cg.gpa, cg.declPtr(spv_decl_index).result_id);
    ep_gop.value_ptr.* = .{
        .decl_index = spv_decl_index,
        .name = test_name,
        .cc = .{ .spirv_kernel = .{ .x = 1, .y = 1, .z = 1 } },
    };
}

fn intFromBool(cg: *CodeGen, value: Temporary, result_ty: Type) !Temporary {
    const zero_id = try cg.constInt(result_ty, 0);
    const one_id = try cg.constInt(result_ty, 1);

    return try cg.buildSelect(
        value,
        Temporary.init(result_ty, one_id),
        Temporary.init(result_ty, zero_id),
    );
}

/// Convert representation from indirect (in memory) to direct (in 'register')
/// This converts the argument type from resolveType(ty, .indirect) to resolveType(ty, .direct).
fn convertToDirect(cg: *CodeGen, ty: Type, operand_id: Id) !Id {
    const pt = cg.pt;
    const zcu = cg.zcu;
    switch (ty.scalarType(zcu).zigTypeTag(zcu)) {
        .bool => {
            const false_id = try cg.constBool(false, .indirect);
            const operand_ty = blk: {
                if (!ty.isVector(zcu)) break :blk Type.u1;
                break :blk try pt.vectorType(.{
                    .len = ty.vectorLen(zcu),
                    .child = .u1_type,
                });
            };

            const result = try cg.buildCmp(
                .OpINotEqual,
                Temporary.init(operand_ty, operand_id),
                Temporary.init(.u1, false_id),
            );
            return try result.materialize(cg);
        },
        else => return operand_id,
    }
}

/// Convert representation from direct (in 'register) to direct (in memory)
/// This converts the argument type from resolveType(ty, .direct) to resolveType(ty, .indirect).
fn convertToIndirect(cg: *CodeGen, ty: Type, operand_id: Id) !Id {
    const zcu = cg.zcu;
    switch (ty.scalarType(zcu).zigTypeTag(zcu)) {
        .bool => {
            const result = try cg.intFromBool(.init(ty, operand_id), .u1);
            return try result.materialize(cg);
        },
        else => return operand_id,
    }
}

fn extractField(cg: *CodeGen, result_ty: Type, object: Id, field: u32) !Id {
    const result_ty_id = try cg.resolveType(result_ty, .indirect);
    const result_id = cg.allocId();
    const indexes = [_]u32{field};
    try cg.body.emit(cg.gpa, .OpCompositeExtract, .{
        .id_result_type = result_ty_id,
        .id_result = result_id,
        .composite = object,
        .indexes = &indexes,
    });
    // Convert bools; direct structs have their field types as indirect values.
    return try cg.convertToDirect(result_ty, result_id);
}

fn extractVectorComponent(cg: *CodeGen, result_ty: Type, vector_id: Id, field: u32) !Id {
    const result_ty_id = try cg.resolveType(result_ty, .direct);
    const result_id = cg.allocId();
    const indexes = [_]u32{field};
    try cg.body.emit(cg.gpa, .OpCompositeExtract, .{
        .id_result_type = result_ty_id,
        .id_result = result_id,
        .composite = vector_id,
        .indexes = &indexes,
    });
    // Vector components are already stored in direct representation.
    return result_id;
}

const MemoryOptions = struct {
    is_volatile: bool = false,
};

fn load(cg: *CodeGen, value_ty: Type, ptr_id: Id, options: MemoryOptions) !Id {
    const zcu = cg.zcu;
    const alignment: u32 = @intCast(value_ty.abiAlignment(zcu).toByteUnits().?);
    const indirect_value_ty_id = try cg.resolveType(value_ty, .indirect);
    const result_id = cg.allocId();
    const access: spec.MemoryAccess.Extended = .{
        .@"volatile" = options.is_volatile,
        .aligned = .{ .literal_integer = alignment },
    };
    try cg.body.emit(cg.gpa, .OpLoad, .{
        .id_result_type = indirect_value_ty_id,
        .id_result = result_id,
        .pointer = ptr_id,
        .memory_access = access,
    });
    return try cg.convertToDirect(value_ty, result_id);
}

fn store(cg: *CodeGen, value_ty: Type, ptr_id: Id, value_id: Id, options: MemoryOptions) !void {
    const indirect_value_id = try cg.convertToIndirect(value_ty, value_id);
    const access: spec.MemoryAccess.Extended = .{ .@"volatile" = options.is_volatile };
    try cg.body.emit(cg.gpa, .OpStore, .{
        .pointer = ptr_id,
        .object = indirect_value_id,
        .memory_access = access,
    });
}

fn genBody(cg: *CodeGen, body: []const Air.Inst.Index) !void {
    for (body) |inst| {
        try cg.genInst(inst);
    }
}

fn genInst(cg: *CodeGen, inst: Air.Inst.Index) Error!void {
    const gpa = cg.gpa;
    const zcu = cg.zcu;
    const ip = &zcu.intern_pool;
    if (cg.liveness.isUnused(inst) and !cg.air.mustLower(inst, ip))
        return;

    const air_tags = cg.air.instructions.items(.tag);
    const maybe_result_id: ?Id = switch (air_tags[@intFromEnum(inst)]) {
        // zig fmt: off
            .add, .add_wrap, .add_optimized => try cg.airArithOp(inst, .OpFAdd, .OpIAdd, .OpIAdd),
            .sub, .sub_wrap, .sub_optimized => try cg.airArithOp(inst, .OpFSub, .OpISub, .OpISub),
            .mul, .mul_wrap, .mul_optimized => try cg.airArithOp(inst, .OpFMul, .OpIMul, .OpIMul),

            .sqrt => try cg.airUnOpSimple(inst, .sqrt),
            .sin => try cg.airUnOpSimple(inst, .sin),
            .cos => try cg.airUnOpSimple(inst, .cos),
            .tan => try cg.airUnOpSimple(inst, .tan),
            .exp => try cg.airUnOpSimple(inst, .exp),
            .exp2 => try cg.airUnOpSimple(inst, .exp2),
            .log => try cg.airUnOpSimple(inst, .log),
            .log2 => try cg.airUnOpSimple(inst, .log2),
            .log10 => try cg.airUnOpSimple(inst, .log10),
            .abs => try cg.airAbs(inst),
            .floor => try cg.airUnOpSimple(inst, .floor),
            .ceil => try cg.airUnOpSimple(inst, .ceil),
            .round => try cg.airUnOpSimple(inst, .round),
            .trunc_float => try cg.airUnOpSimple(inst, .trunc),
            .neg, .neg_optimized => try cg.airUnOpSimple(inst, .f_neg),

            .div_float, .div_float_optimized => try cg.airArithOp(inst, .OpFDiv, .OpSDiv, .OpUDiv),
            .div_floor, .div_floor_optimized => try cg.airDivFloor(inst),
            .div_trunc, .div_trunc_optimized => try cg.airDivTrunc(inst),

            .rem, .rem_optimized => try cg.airArithOp(inst, .OpFRem, .OpSRem, .OpUMod),
            .mod, .mod_optimized => try cg.airArithOp(inst, .OpFMod, .OpSMod, .OpUMod),

            .add_with_overflow => try cg.airAddSubOverflow(inst, .OpIAdd, .OpULessThan, .OpSLessThan),
            .sub_with_overflow => try cg.airAddSubOverflow(inst, .OpISub, .OpUGreaterThan, .OpSGreaterThan),
            .mul_with_overflow => try cg.airMulOverflow(inst),
            .shl_with_overflow => try cg.airShlOverflow(inst),

            .mul_add => try cg.airMulAdd(inst),

            .ctz => try cg.airClzCtz(inst, .ctz),
            .clz => try cg.airClzCtz(inst, .clz),

            .select => try cg.airSelect(inst),

            .splat => try cg.airSplat(inst),
            .reduce, .reduce_optimized => try cg.airReduce(inst),
            .shuffle_one               => try cg.airShuffleOne(inst),
            .shuffle_two               => try cg.airShuffleTwo(inst),

            .ptr_add => try cg.airPtrAdd(inst),
            .ptr_sub => try cg.airPtrSub(inst),

            .bit_and => try cg.airBitwiseOp(inst, .bit_and),
            .bit_or  => try cg.airBitwiseOp(inst, .bit_or),
            .xor     => try cg.airBitwiseOp(inst, .xor),

            .shl, .shl_exact => try cg.airShift(inst, .OpShiftLeftLogical, .OpShiftLeftLogical),
            .shr, .shr_exact => try cg.airShift(inst, .OpShiftRightLogical, .OpShiftRightArithmetic),

            .min => try cg.airMinMax(inst, .min),
            .max => try cg.airMinMax(inst, .max),

            .bit_cast         => try cg.airBitCast(inst),
            .ptr_cast         => try cg.airBitCast(inst),
            .ptr_from_int     => try cg.airBitCast(inst),
            .int_from_ptr     => try cg.airBitCast(inst),
            .error_cast       => try cg.airBitCast(inst),
            .error_from_int   => try cg.airBitCast(inst),
            .int_from_error   => try cg.airBitCast(inst),
            .union_from_enum  => try cg.airBitCast(inst),
            .int_cast, .trunc => try cg.airIntCast(inst),
            .float_from_int   => try cg.airFloatFromInt(inst),
            .int_from_float   => try cg.airIntFromFloat(inst),
            .fpext, .fptrunc  => try cg.airFloatCast(inst),
            .not              => try cg.airNot(inst),

            .array_to_slice => try cg.airArrayToSlice(inst),
            .slice          => try cg.airSlice(inst),
            .aggregate_init => try cg.airAggregateInit(inst),
            .memcpy         => return cg.airMemcpy(inst),
            .memmove        => return cg.airMemmove(inst),

            .slice_ptr               => try cg.airSliceField(inst, 0),
            .slice_len               => try cg.airSliceField(inst, 1),
            .ptr_slice_ptr_ptr       => try cg.airStructFieldPtrIndex(inst, 0),
            .ptr_slice_len_ptr       => try cg.airStructFieldPtrIndex(inst, 1),
            .spirv_runtime_array_len => try cg.airSpirvRuntimeArrayLen(inst),
            .slice_elem_ptr          => try cg.airSliceElemPtr(inst),
            .slice_elem_val          => try cg.airSliceElemVal(inst),
            .ptr_elem_ptr            => try cg.airPtrElemPtr(inst),
            .ptr_elem_val            => try cg.airPtrElemVal(inst),
            .array_elem_val          => try cg.airArrayElemVal(inst),

            .set_union_tag => return cg.airSetUnionTag(inst),
            .get_union_tag => try cg.airGetUnionTag(inst),
            .union_init => try cg.airUnionInit(inst),

            .struct_field_val => try cg.airStructFieldVal(inst),
            .field_parent_ptr => try cg.airFieldParentPtr(inst),

            .struct_field_ptr => try cg.airStructFieldPtr(inst),

            .struct_field_ptr_index_0 => try cg.airStructFieldPtrIndex(inst, 0),
            .struct_field_ptr_index_1 => try cg.airStructFieldPtrIndex(inst, 1),
            .struct_field_ptr_index_2 => try cg.airStructFieldPtrIndex(inst, 2),
            .struct_field_ptr_index_3 => try cg.airStructFieldPtrIndex(inst, 3),

            .cmp_eq     => try cg.airCmp(inst, .eq),
            .cmp_neq    => try cg.airCmp(inst, .neq),
            .cmp_gt     => try cg.airCmp(inst, .gt),
            .cmp_gte    => try cg.airCmp(inst, .gte),
            .cmp_lt     => try cg.airCmp(inst, .lt),
            .cmp_lte    => try cg.airCmp(inst, .lte),
            .cmp_vector => try cg.airVectorCmp(inst),

            .arg     => cg.airArg(),
            .alloc   => try cg.airAlloc(inst),
            // TODO: We probably need to have a special implementation of this for the C abi.
            .ret_ptr => try cg.airAlloc(inst),
            .block   => try cg.airBlock(inst),

            .load               => try cg.airLoad(inst),
            .store, .store_safe => return cg.airStore(inst),

            .br              => return cg.airBr(inst),
            // For now just ignore this instruction. This effectively falls back on the old implementation,
            // this doesn't change anything for us.
            .repeat          => return,
            .breakpoint      => return,
            .cond_br         => return cg.airCondBr(inst),
            .loop            => return cg.airLoop(inst),
            .ret             => return cg.airRet(inst),
            .ret_safe        => return cg.airRet(inst), // TODO
            .ret_load        => return cg.airRetLoad(inst),
            .@"try"          => try cg.airTry(inst),
            .switch_br       => return cg.airSwitchBr(inst),
            .loop_switch_br  => return cg.airLoopSwitchBr(inst),
            .switch_dispatch => return cg.airSwitchDispatch(inst),
            .unreach, .trap  => return cg.airUnreach(),

            .dbg_empty_stmt            => return,
            .dbg_stmt                  => return cg.airDbgStmt(inst),
            .dbg_inline_block          => try cg.airDbgInlineBlock(inst),
            .dbg_var_ptr, .dbg_var_val, .dbg_arg_inline => return cg.airDbgVar(inst),

            .unwrap_errunion_err => try cg.airErrUnionErr(inst),
            .unwrap_errunion_payload => try cg.airErrUnionPayload(inst),
            .wrap_errunion_err => try cg.airWrapErrUnionErr(inst),
            .wrap_errunion_payload => try cg.airWrapErrUnionPayload(inst),

            .is_null         => try cg.airIsNull(inst, false, .is_null),
            .is_non_null     => try cg.airIsNull(inst, false, .is_non_null),
            .is_null_ptr     => try cg.airIsNull(inst, true, .is_null),
            .is_non_null_ptr => try cg.airIsNull(inst, true, .is_non_null),
            .is_err          => try cg.airIsErr(inst, .is_err),
            .is_non_err      => try cg.airIsErr(inst, .is_non_err),

            .optional_payload     => try cg.airUnwrapOptional(inst),
            .optional_payload_ptr => try cg.airUnwrapOptionalPtr(inst),
            .wrap_optional        => try cg.airWrapOptional(inst),

            .assembly => try cg.airAssembly(inst),

            .call              => try cg.airCall(inst, .auto),
            .call_always_tail  => try cg.airCall(inst, .always_tail),
            .call_never_tail   => try cg.airCall(inst, .never_tail),
            .call_never_inline => try cg.airCall(inst, .never_inline),

            .work_item_id => try cg.airWorkItemId(inst),
            .work_group_size => try cg.airWorkGroupSize(inst),
            .work_group_id => try cg.airWorkGroupId(inst),

            // zig fmt: on

        else => |tag| return cg.todo("implement AIR tag {s}", .{@tagName(tag)}),
    };

    const result_id = maybe_result_id orelse return;
    try cg.inst_results.putNoClobber(gpa, inst, result_id);
}

fn airBinOpSimple(cg: *CodeGen, inst: Air.Inst.Index, op: Opcode) !?Id {
    const bin_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try cg.temporary(bin_op.lhs);
    const rhs = try cg.temporary(bin_op.rhs);

    const result = try cg.buildBinary(op, lhs, rhs);
    return try result.materialize(cg);
}

const BitwiseOp = enum { bit_and, bit_or, xor };

fn airBitwiseOp(cg: *CodeGen, inst: Air.Inst.Index, op: BitwiseOp) !?Id {
    const bin_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try cg.temporary(bin_op.lhs);
    const rhs = try cg.temporary(bin_op.rhs);
    const info = cg.arithmeticTypeInfo(lhs.ty);

    // SPIR-V requires logical opcodes for booleans, bitwise opcodes for integers.
    const opcode: Opcode = switch (info.class) {
        .bool => switch (op) {
            .bit_and => .OpLogicalAnd,
            .bit_or => .OpLogicalOr,
            .xor => .OpLogicalNotEqual,
        },
        .integer, .strange_integer => switch (op) {
            .bit_and => .OpBitwiseAnd,
            .bit_or => .OpBitwiseOr,
            .xor => .OpBitwiseXor,
        },
        .float => unreachable,
        .composite_integer => {
            const spv_opcode: Opcode = switch (op) {
                .bit_and => .OpBitwiseAnd,
                .bit_or => .OpBitwiseOr,
                .xor => .OpBitwiseXor,
            };
            const lhs_id = try lhs.materialize(cg);
            const rhs_id = try rhs.materialize(cg);
            const scratch_top = cg.id_scratch.items.len;
            defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
            const ci_lhs = try CompositeInt.init(cg, lhs_id, info);
            const ci_rhs = try CompositeInt.init(cg, rhs_id, info);
            const ci_result = try ci_lhs.bitwiseOp(ci_rhs, spv_opcode);
            return try ci_result.materialize(lhs.ty);
        },
    };

    const result = try cg.buildBinary(opcode, lhs, rhs);
    return try result.materialize(cg);
}

fn airShift(cg: *CodeGen, inst: Air.Inst.Index, unsigned: Opcode, signed: Opcode) !?Id {
    const zcu = cg.zcu;
    const bin_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;

    if (cg.typeOf(bin_op.lhs).isVector(zcu) and !cg.typeOf(bin_op.rhs).isVector(zcu)) {
        return cg.fail("vector shift with scalar rhs", .{});
    }

    const base = try cg.temporary(bin_op.lhs);
    const shift = try cg.temporary(bin_op.rhs);

    const result_ty = cg.typeOfIndex(inst);

    const info = cg.arithmeticTypeInfo(result_ty);
    switch (info.class) {
        .composite_integer => {
            const shift_info = cg.arithmeticTypeInfo(shift.ty);
            const shift_amt_id = switch (shift_info.class) {
                .composite_integer => blk: {
                    const shift_id = try shift.materialize(cg);
                    const u32_ty_id = try cg.resolveType(.u32, .direct);
                    const result_id = cg.allocId();
                    try cg.body.emit(cg.gpa, .OpCompositeExtract, .{
                        .id_result_type = u32_ty_id,
                        .id_result = result_id,
                        .composite = shift_id,
                        .indexes = &.{@as(u32, 0)},
                    });
                    break :blk result_id;
                },
                else => blk: {
                    const converted = try cg.buildConvert(.u32, shift);
                    break :blk try converted.materialize(cg);
                },
            };
            const base_id = try base.materialize(cg);
            const scratch_top = cg.id_scratch.items.len;
            defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
            const ci = try CompositeInt.init(cg, base_id, info);
            const ci_result = if (unsigned == .OpShiftLeftLogical)
                try ci.shl(shift_amt_id)
            else switch (info.signedness) {
                .unsigned => try ci.shr(shift_amt_id, false),
                .signed => try ci.shr(shift_amt_id, true),
            };
            const normalized = try ci_result.normalize();
            return try normalized.materialize(result_ty);
        },
        .integer, .strange_integer => {},
        .float, .bool => unreachable,
    }

    // Sometimes Zig doesn't make both of the arguments the same types here. SPIR-V expects that,
    // so just manually upcast it if required.

    // Note: The sign may differ here between the shift and the base type, in case
    // of an arithmetic right shift. SPIR-V still expects the same type,
    // so in that case we have to cast convert to signed.
    const casted_shift = try cg.buildConvert(base.ty.scalarType(zcu), shift);

    const shifted = switch (info.signedness) {
        .unsigned => try cg.buildBinary(unsigned, base, casted_shift),
        .signed => try cg.buildBinary(signed, base, casted_shift),
    };

    const result = try cg.normalize(shifted, info);
    return try result.materialize(cg);
}

const MinMax = enum {
    min,
    max,

    pub fn extInstOpcode(
        op: MinMax,
        target: *const std.Target,
        info: ArithmeticTypeInfo,
    ) u32 {
        return switch (target.os.tag) {
            .opencl => @intFromEnum(@as(spec.OpenClOpcode, switch (info.class) {
                .float => switch (op) {
                    .min => .fmin,
                    .max => .fmax,
                },
                .integer, .strange_integer, .composite_integer => switch (info.signedness) {
                    .signed => switch (op) {
                        .min => .s_min,
                        .max => .s_max,
                    },
                    .unsigned => switch (op) {
                        .min => .u_min,
                        .max => .u_max,
                    },
                },
                .bool => unreachable,
            })),
            .vulkan, .opengl => @intFromEnum(@as(spec.GlslOpcode, switch (info.class) {
                .float => switch (op) {
                    .min => .FMin,
                    .max => .FMax,
                },
                .integer, .strange_integer, .composite_integer => switch (info.signedness) {
                    .signed => switch (op) {
                        .min => .SMin,
                        .max => .SMax,
                    },
                    .unsigned => switch (op) {
                        .min => .UMin,
                        .max => .UMax,
                    },
                },
                .bool => unreachable,
            })),
            else => unreachable,
        };
    }
};

fn airMinMax(cg: *CodeGen, inst: Air.Inst.Index, op: MinMax) !?Id {
    const bin_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;

    const lhs = try cg.temporary(bin_op.lhs);
    const rhs = try cg.temporary(bin_op.rhs);

    const result = try cg.minMax(lhs, rhs, op);
    return try result.materialize(cg);
}

fn minMax(cg: *CodeGen, lhs: Temporary, rhs: Temporary, op: MinMax) !Temporary {
    const zcu = cg.zcu;
    const target = zcu.getTarget();
    const info = cg.arithmeticTypeInfo(lhs.ty);

    const v = cg.vectorization(.{ lhs, rhs });
    const ops = v.components();
    const results = cg.allocIds(ops);

    const op_result_ty = lhs.ty.scalarType(zcu);
    const op_result_ty_id = try cg.resolveType(op_result_ty, .direct);
    const result_ty = try v.resultType(cg, lhs.ty);

    const op_lhs = try v.prepare(cg, lhs);
    const op_rhs = try v.prepare(cg, rhs);

    const set = try cg.importExtendedSet();
    const opcode = op.extInstOpcode(target, info);
    for (0..ops) |i| {
        try cg.body.emit(cg.gpa, .OpExtInst, .{
            .id_result_type = op_result_ty_id,
            .id_result = results.at(i),
            .set = set,
            .instruction = .{ .inst = opcode },
            .id_ref_4 = &.{ op_lhs.at(i), op_rhs.at(i) },
        });
    }

    return v.finalize(result_ty, results);
}

/// This function normalizes values to a canonical representation
/// after some arithmetic operation. This mostly consists of wrapping
/// behavior for strange integers:
/// - Unsigned integers are bitwise masked with a mask that only passes
///   the valid bits through.
/// - Signed integers are also sign extended if they are negative.
/// All other values are returned unmodified (this makes strange integer
/// wrapping easier to use in generic operations).
fn normalize(cg: *CodeGen, value: Temporary, info: ArithmeticTypeInfo) !Temporary {
    const zcu = cg.zcu;
    const ty = value.ty;
    switch (info.class) {
        .integer, .bool, .float => return value,
        .composite_integer => {
            if (info.bits == info.backing_bits) return value;
            const val_id = try value.materialize(cg);
            const scratch_top = cg.id_scratch.items.len;
            defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
            const ci = try CompositeInt.init(cg, val_id, info);
            const normalized = try ci.normalize();
            return .init(ty, try normalized.materialize(ty));
        },
        .strange_integer => switch (info.signedness) {
            .unsigned => {
                const mask_value = @as(u64, std.math.maxInt(u64)) >> @as(u6, @intCast(64 - info.bits));
                const mask_id = try cg.constInt(ty.scalarType(zcu), mask_value);
                return try cg.buildBinary(.OpBitwiseAnd, value, Temporary.init(ty.scalarType(zcu), mask_id));
            },
            .signed => {
                // Shift left and right so that we can copy the sight bit that way.
                const shift_amt_id = try cg.constInt(ty.scalarType(zcu), info.backing_bits - info.bits);
                const shift_amt: Temporary = .init(ty.scalarType(zcu), shift_amt_id);
                const left = try cg.buildBinary(.OpShiftLeftLogical, value, shift_amt);
                return try cg.buildBinary(.OpShiftRightArithmetic, left, shift_amt);
            },
        },
    }
}

fn airDivFloor(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const bin_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;

    const lhs = try cg.temporary(bin_op.lhs);
    const rhs = try cg.temporary(bin_op.rhs);

    const info = cg.arithmeticTypeInfo(lhs.ty);
    switch (info.class) {
        .composite_integer => return cg.todo("div_floor for composite integers", .{}),
        .integer, .strange_integer => {
            switch (info.signedness) {
                .unsigned => {
                    const result = try cg.buildBinary(.OpUDiv, lhs, rhs);
                    return try result.materialize(cg);
                },
                .signed => {},
            }

            // For signed integers:
            //   (a / b) - (a % b != 0 && a < 0 != b < 0);
            // There shouldn't be any overflow issues.

            const div = try cg.buildBinary(.OpSDiv, lhs, rhs);
            const rem = try cg.buildBinary(.OpSRem, lhs, rhs);
            const zero: Temporary = .init(lhs.ty, try cg.constInt(lhs.ty, 0));
            const rem_non_zero = try cg.buildCmp(.OpINotEqual, rem, zero);
            const lhs_rhs_xor = try cg.buildBinary(.OpBitwiseXor, lhs, rhs);
            const signs_differ = try cg.buildCmp(.OpSLessThan, lhs_rhs_xor, zero);
            const adjust = try cg.buildBinary(.OpLogicalAnd, rem_non_zero, signs_differ);
            const result = try cg.buildBinary(.OpISub, div, try cg.intFromBool(adjust, div.ty));
            return try result.materialize(cg);
        },
        .float => {
            const div = try cg.buildBinary(.OpFDiv, lhs, rhs);
            const result = try cg.buildUnary(.floor, div);
            return try result.materialize(cg);
        },
        .bool => unreachable,
    }
}

fn airDivTrunc(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const bin_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try cg.temporary(bin_op.lhs);
    const rhs = try cg.temporary(bin_op.rhs);
    const info = cg.arithmeticTypeInfo(lhs.ty);
    switch (info.class) {
        .composite_integer => return cg.todo("div_trunc for composite integers", .{}),
        .integer, .strange_integer => switch (info.signedness) {
            .unsigned => {
                const result = try cg.buildBinary(.OpUDiv, lhs, rhs);
                return try result.materialize(cg);
            },
            .signed => {
                const result = try cg.buildBinary(.OpSDiv, lhs, rhs);
                return try result.materialize(cg);
            },
        },
        .float => {
            const div = try cg.buildBinary(.OpFDiv, lhs, rhs);
            const result = try cg.buildUnary(.trunc, div);
            return try result.materialize(cg);
        },
        .bool => unreachable,
    }
}

fn airUnOpSimple(cg: *CodeGen, inst: Air.Inst.Index, op: UnaryOp) !?Id {
    const un_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].un_op;
    const operand = try cg.temporary(un_op);
    const result = try cg.buildUnary(op, operand);
    return try result.materialize(cg);
}

fn airArithOp(
    cg: *CodeGen,
    inst: Air.Inst.Index,
    comptime fop: Opcode,
    comptime sop: Opcode,
    comptime uop: Opcode,
) !?Id {
    const bin_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try cg.temporary(bin_op.lhs);
    const rhs = try cg.temporary(bin_op.rhs);
    const info = cg.arithmeticTypeInfo(lhs.ty);
    const result = switch (info.class) {
        .composite_integer => res: {
            const lhs_id = try lhs.materialize(cg);
            const rhs_id = try rhs.materialize(cg);
            const scratch_top = cg.id_scratch.items.len;
            defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
            const ci_lhs = try CompositeInt.init(cg, lhs_id, info);
            const ci_rhs = try CompositeInt.init(cg, rhs_id, info);
            const ci_result = switch (uop) {
                .OpIAdd => try ci_lhs.addSub(ci_rhs, true),
                .OpISub => try ci_lhs.addSub(ci_rhs, false),
                .OpIMul => CompositeInt.fromLimbs(cg, try ci_lhs.mul(ci_rhs, false), info),
                else => return cg.todo("arith op for composite integers", .{}),
            };
            const normalized = try ci_result.normalize();
            break :res Temporary.init(lhs.ty, try normalized.materialize(lhs.ty));
        },
        .integer, .strange_integer => res: {
            const raw = switch (info.signedness) {
                .signed => try cg.buildBinary(sop, lhs, rhs),
                .unsigned => try cg.buildBinary(uop, lhs, rhs),
            };
            break :res try cg.normalize(raw, info);
        },
        .float => try cg.buildBinary(fop, lhs, rhs),
        .bool => unreachable,
    };
    return try result.materialize(cg);
}

fn airAbs(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const zcu = cg.zcu;
    const target = zcu.getTarget();
    const ty_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const value = try cg.temporary(ty_op.operand);
    // Note: operand_ty may be signed, while ty is always unsigned.
    const result_ty = cg.typeOfIndex(inst);
    const operand_info = cg.arithmeticTypeInfo(value.ty);
    const result: Temporary = switch (operand_info.class) {
        .float => try cg.buildUnary(.f_abs, value),
        .integer, .strange_integer => abs: {
            var abs_value = try cg.buildUnary(.i_abs, value);
            switch (target.os.tag) {
                .vulkan, .opengl => {
                    if (value.ty.intInfo(zcu).signedness == .signed) {
                        const abs_id = try abs_value.materialize(cg);
                        const dst_ty_id = try cg.resolveType(result_ty, .direct);
                        const cast_id = cg.allocId();
                        try cg.body.emit(cg.gpa, .OpBitcast, .{
                            .id_result_type = dst_ty_id,
                            .id_result = cast_id,
                            .operand = abs_id,
                        });
                        abs_value = .init(result_ty, cast_id);
                    }
                },
                else => {},
            }
            break :abs try cg.normalize(abs_value, cg.arithmeticTypeInfo(result_ty));
        },
        .composite_integer => abs: {
            const val_id = try value.materialize(cg);
            const scratch_top = cg.id_scratch.items.len;
            defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
            const ci = try CompositeInt.init(cg, val_id, operand_info);
            const ci_z = try CompositeInt.zero(cg, operand_info);
            const is_neg = try ci.cmp(ci_z, .lt);
            const ci_neg = try ci_z.addSub(ci, false);
            const result_info = cg.arithmeticTypeInfo(result_ty);
            const u32_ty_id = try cg.resolveType(.u32, .direct);
            const result_limbs = try cg.id_scratch.addManyAsSlice(cg.gpa, ci.n_limbs);
            for (0..ci.n_limbs) |i| {
                result_limbs[i] = cg.allocId();
                try cg.body.emit(cg.gpa, .OpSelect, .{
                    .id_result_type = u32_ty_id,
                    .id_result = result_limbs[i],
                    .condition = is_neg,
                    .object_1 = ci_neg.limbs[i],
                    .object_2 = ci.limbs[i],
                });
            }
            const ci_result = CompositeInt.fromLimbs(cg, result_limbs, result_info);
            const normalized = try ci_result.normalize();
            break :abs .init(result_ty, try normalized.materialize(result_ty));
        },
        .bool => unreachable,
    };
    return try result.materialize(cg);
}

fn airAddSubOverflow(
    cg: *CodeGen,
    inst: Air.Inst.Index,
    comptime add: Opcode,
    u_opcode: Opcode,
    s_opcode: Opcode,
) !?Id {
    // Note: OpIAddCarry and OpISubBorrow are not really useful here: For unsigned numbers,
    // there is in both cases only one extra operation required. For signed operations,
    // the overflow bit is set then going from 0x80.. to 0x00.., but this doesn't actually
    // normally set a carry bit. So the SPIR-V overflow operations are not particularly
    // useful here.

    _ = s_opcode;

    const ty_pl = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const extra = cg.air.extraData(Air.Bin, ty_pl.payload).data;
    const lhs = try cg.temporary(extra.lhs);
    const rhs = try cg.temporary(extra.rhs);
    const result_ty = cg.typeOfIndex(inst);

    const info = cg.arithmeticTypeInfo(lhs.ty);
    switch (info.class) {
        .composite_integer => {
            const lhs_id = try lhs.materialize(cg);
            const rhs_id = try rhs.materialize(cg);
            const scratch_top = cg.id_scratch.items.len;
            defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
            const ci_lhs = try CompositeInt.init(cg, lhs_id, info);
            const ci_rhs = try CompositeInt.init(cg, rhs_id, info);
            const ci_sum = if (add == .OpIAdd) try ci_lhs.addSub(ci_rhs, true) else try ci_lhs.addSub(ci_rhs, false);
            const ci_result = try ci_sum.normalize();
            const result_val_id = try ci_result.materialize(lhs.ty);

            const ov_bool = switch (info.signedness) {
                .unsigned => blk: {
                    const ci_res2 = try CompositeInt.init(cg, result_val_id, info);
                    const ci_lhs2 = try CompositeInt.init(cg, lhs_id, info);
                    break :blk if (add == .OpIAdd)
                        try ci_res2.cmp(ci_lhs2, .lt)
                    else
                        try ci_res2.cmp(ci_lhs2, .gt);
                },
                .signed => blk: {
                    const ci_res2 = try CompositeInt.init(cg, result_val_id, info);
                    const ci_lhs2 = try CompositeInt.init(cg, lhs_id, info);
                    const ci_rhs2 = try CompositeInt.init(cg, rhs_id, info);
                    const ci_z = try CompositeInt.zero(cg, info);
                    const lhs_neg = try ci_lhs2.cmp(ci_z, .lt);
                    const rhs_neg = try ci_rhs2.cmp(ci_z, .lt);
                    const res_neg = try ci_res2.cmp(ci_z, .lt);

                    const bool_ty_id = try cg.resolveType(.bool, .direct);
                    const signs_match = cg.allocId();
                    try cg.body.emit(cg.gpa, .OpLogicalEqual, .{
                        .id_result_type = bool_ty_id,
                        .id_result = signs_match,
                        .operand_1 = lhs_neg,
                        .operand_2 = rhs_neg,
                    });
                    const res_sign_diff = cg.allocId();
                    try cg.body.emit(cg.gpa, .OpLogicalNotEqual, .{
                        .id_result_type = bool_ty_id,
                        .id_result = res_sign_diff,
                        .operand_1 = lhs_neg,
                        .operand_2 = res_neg,
                    });
                    const ov_cond = if (add == .OpIAdd) signs_match else blk2: {
                        const not_match = cg.allocId();
                        try cg.body.emit(cg.gpa, .OpLogicalNot, .{
                            .id_result_type = bool_ty_id,
                            .id_result = not_match,
                            .operand = signs_match,
                        });
                        break :blk2 not_match;
                    };
                    const ov_result = cg.allocId();
                    try cg.body.emit(cg.gpa, .OpLogicalAnd, .{
                        .id_result_type = bool_ty_id,
                        .id_result = ov_result,
                        .operand_1 = ov_cond,
                        .operand_2 = res_sign_diff,
                    });
                    break :blk ov_result;
                },
            };
            const ov = try cg.intFromBool(.init(.bool, ov_bool), .u1);
            const result_ty_id = try cg.resolveType(result_ty, .direct);
            return try cg.constructComposite(result_ty_id, &.{ result_val_id, try ov.materialize(cg) });
        },
        .strange_integer, .integer => {},
        .float, .bool => unreachable,
    }

    const sum = try cg.buildBinary(add, lhs, rhs);
    const result = try cg.normalize(sum, info);
    const overflowed = switch (info.signedness) {
        // Overflow happened if the result is smaller than either of the operands. It doesn't matter which.
        // For subtraction the conditions need to be swapped.
        .unsigned => try cg.buildCmp(u_opcode, result, lhs),
        // For signed operations, we check the signs of the operands and the result.
        .signed => blk: {
            // Signed overflow detection using the sign bits of the operands and the result.
            // For addition (a + b), overflow occurs if the operands have the same sign
            // and the result's sign is different from the operands' sign.
            //   (sign(a) == sign(b)) && (sign(a) != sign(result))
            // For subtraction (a - b), overflow occurs if the operands have different signs
            // and the result's sign is different from the minuend's (a's) sign.
            //   (sign(a) != sign(b)) && (sign(a) != sign(result))
            const zero: Temporary = .init(rhs.ty, try cg.constInt(rhs.ty, 0));
            const lhs_is_neg = try cg.buildCmp(.OpSLessThan, lhs, zero);
            const rhs_is_neg = try cg.buildCmp(.OpSLessThan, rhs, zero);
            const result_is_neg = try cg.buildCmp(.OpSLessThan, result, zero);
            const signs_match = try cg.buildCmp(.OpLogicalEqual, lhs_is_neg, rhs_is_neg);
            const result_sign_differs = try cg.buildCmp(.OpLogicalNotEqual, lhs_is_neg, result_is_neg);
            const overflow_condition = switch (add) {
                .OpIAdd => signs_match,
                .OpISub => try cg.buildUnary(.l_not, signs_match),
                else => unreachable,
            };
            break :blk try cg.buildCmp(.OpLogicalAnd, overflow_condition, result_sign_differs);
        },
    };

    const ov = try cg.intFromBool(overflowed, .u1);
    const result_ty_id = try cg.resolveType(result_ty, .direct);
    return try cg.constructComposite(result_ty_id, &.{ try result.materialize(cg), try ov.materialize(cg) });
}

fn airMulOverflow(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const pt = cg.pt;
    const gpa = cg.gpa;
    const ty_pl = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const extra = cg.air.extraData(Air.Bin, ty_pl.payload).data;
    const lhs = try cg.temporary(extra.lhs);
    const rhs = try cg.temporary(extra.rhs);
    const result_ty = cg.typeOfIndex(inst);

    const info = cg.arithmeticTypeInfo(lhs.ty);
    switch (info.class) {
        .composite_integer => {
            const lhs_id = try lhs.materialize(cg);
            const rhs_id = try rhs.materialize(cg);
            const scratch_top = cg.id_scratch.items.len;
            defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
            const ci_lhs = try CompositeInt.init(cg, lhs_id, info);
            const ci_rhs = try CompositeInt.init(cg, rhs_id, info);

            const low_limbs = try ci_lhs.mul(ci_rhs, false);
            const ci_result = try CompositeInt.fromLimbs(cg, low_limbs, info).normalize();
            const result_val_id = try ci_result.materialize(lhs.ty);

            const ci_lhs2 = try CompositeInt.init(cg, lhs_id, info);
            const ci_rhs2 = try CompositeInt.init(cg, rhs_id, info);
            const wide_limbs = try ci_lhs2.mul(ci_rhs2, true);
            const high_limbs = wide_limbs[ci_lhs2.n_limbs..];

            const bool_ty_id = try cg.resolveType(.bool, .direct);
            const u32_ty_id = try cg.resolveType(.u32, .direct);
            const n: usize = info.backing_bits / big_int_bits;

            const ov_bool = switch (info.signedness) {
                .unsigned => blk: {
                    const zero_id = try cg.constInt(.u32, @as(u32, 0));
                    var any_nonzero = cg.allocId();
                    try cg.body.emit(gpa, .OpINotEqual, .{
                        .id_result_type = bool_ty_id,
                        .id_result = any_nonzero,
                        .operand_1 = high_limbs[0],
                        .operand_2 = zero_id,
                    });

                    for (1..n) |i| {
                        const limb_nz = cg.allocId();
                        try cg.body.emit(gpa, .OpINotEqual, .{
                            .id_result_type = bool_ty_id,
                            .id_result = limb_nz,
                            .operand_1 = high_limbs[i],
                            .operand_2 = zero_id,
                        });

                        const combined = cg.allocId();
                        try cg.body.emit(gpa, .OpLogicalOr, .{
                            .id_result_type = bool_ty_id,
                            .id_result = combined,
                            .operand_1 = any_nonzero,
                            .operand_2 = limb_nz,
                        });
                        any_nonzero = combined;
                    }

                    break :blk any_nonzero;
                },
                .signed => blk: {
                    const ci_res = try CompositeInt.init(cg, result_val_id, info);
                    const top_limb = ci_res.limbs[n - 1];
                    const i32_ty_id = try cg.resolveType(.i32, .direct);

                    const top_bits: u16 = if (info.bits % big_int_bits == 0)
                        big_int_bits
                    else
                        info.bits % big_int_bits;

                    const shift_amt: u32 = top_bits - 1;
                    const shift_id = try cg.constInt(.u32, shift_amt);

                    const as_signed = cg.allocId();
                    try cg.body.emit(gpa, .OpBitcast, .{
                        .id_result_type = i32_ty_id,
                        .id_result = as_signed,
                        .operand = top_limb,
                    });
                    const sign_ext = cg.allocId();
                    try cg.body.emit(gpa, .OpShiftRightArithmetic, .{
                        .id_result_type = i32_ty_id,
                        .id_result = sign_ext,
                        .base = as_signed,
                        .shift = shift_id,
                    });
                    const expected = cg.allocId();
                    try cg.body.emit(gpa, .OpBitcast, .{
                        .id_result_type = u32_ty_id,
                        .id_result = expected,
                        .operand = sign_ext,
                    });

                    var any_mismatch = cg.allocId();
                    try cg.body.emit(gpa, .OpINotEqual, .{
                        .id_result_type = bool_ty_id,
                        .id_result = any_mismatch,
                        .operand_1 = high_limbs[0],
                        .operand_2 = expected,
                    });

                    for (1..n) |i| {
                        const limb_ne = cg.allocId();
                        try cg.body.emit(gpa, .OpINotEqual, .{
                            .id_result_type = bool_ty_id,
                            .id_result = limb_ne,
                            .operand_1 = high_limbs[i],
                            .operand_2 = expected,
                        });

                        const combined = cg.allocId();
                        try cg.body.emit(gpa, .OpLogicalOr, .{
                            .id_result_type = bool_ty_id,
                            .id_result = combined,
                            .operand_1 = any_mismatch,
                            .operand_2 = limb_ne,
                        });
                        any_mismatch = combined;
                    }

                    if (info.bits != info.backing_bits) {
                        const top_bits_s: u16 = info.bits % big_int_bits;
                        const s_shift_id = try cg.constInt(.u32, top_bits_s - 1);

                        const top_as_signed = cg.allocId();
                        try cg.body.emit(gpa, .OpBitcast, .{
                            .id_result_type = i32_ty_id,
                            .id_result = top_as_signed,
                            .operand = top_limb,
                        });
                        const top_sign_ext = cg.allocId();
                        try cg.body.emit(gpa, .OpShiftRightArithmetic, .{
                            .id_result_type = i32_ty_id,
                            .id_result = top_sign_ext,
                            .base = top_as_signed,
                            .shift = s_shift_id,
                        });
                        const top_expected = cg.allocId();
                        try cg.body.emit(gpa, .OpBitcast, .{
                            .id_result_type = u32_ty_id,
                            .id_result = top_expected,
                            .operand = top_sign_ext,
                        });
                        const top_mismatch = cg.allocId();
                        try cg.body.emit(gpa, .OpINotEqual, .{
                            .id_result_type = bool_ty_id,
                            .id_result = top_mismatch,
                            .operand_1 = top_limb,
                            .operand_2 = top_expected,
                        });

                        const combined = cg.allocId();
                        try cg.body.emit(gpa, .OpLogicalOr, .{
                            .id_result_type = bool_ty_id,
                            .id_result = combined,
                            .operand_1 = any_mismatch,
                            .operand_2 = top_mismatch,
                        });
                        any_mismatch = combined;
                    }

                    break :blk any_mismatch;
                },
            };

            const ov = try cg.intFromBool(.init(.bool, ov_bool), .u1);
            const result_ty_id = try cg.resolveType(result_ty, .direct);
            return try cg.constructComposite(result_ty_id, &.{ result_val_id, try ov.materialize(cg) });
        },
        .strange_integer, .integer => {},
        .float, .bool => unreachable,
    }

    // There are 3 cases which we have to deal with:
    // - If info.bits < 32 / 2, we will upcast to 32 and check the higher bits
    // - If info.bits > 32 / 2, we have to use extended multiplication
    // - Additionally, if info.bits != 32, we'll have to check the high bits
    //   of the result too.

    const target = cg.zcu.getTarget();
    const largest_int_bits: u16 = if (target.cpu.has(.spirv, .int64) or target.cpu.arch == .spirv64) 64 else 32;
    // If non-null, the number of bits that the multiplication should be performed in. If
    // null, we have to use wide multiplication.
    const maybe_op_ty_bits: ?u16 = switch (info.bits) {
        0 => unreachable,
        1...16 => 32,
        17...32 => if (largest_int_bits > 32) 64 else null, // Upcast if we can.
        33...64 => null, // Always use wide multiplication.
        else => unreachable,
    };

    const result, const overflowed = switch (info.signedness) {
        .unsigned => blk: {
            if (maybe_op_ty_bits) |op_ty_bits| {
                const op_ty = try pt.intType(.unsigned, op_ty_bits);
                const casted_lhs = try cg.buildConvert(op_ty, lhs);
                const casted_rhs = try cg.buildConvert(op_ty, rhs);
                const full_result = try cg.buildBinary(.OpIMul, casted_lhs, casted_rhs);
                const low_bits = try cg.buildConvert(lhs.ty, full_result);
                const result = try cg.normalize(low_bits, info);
                // Shift the result bits away to get the overflow bits.
                const shift: Temporary = .init(full_result.ty, try cg.constInt(full_result.ty, info.bits));
                const overflow = try cg.buildBinary(.OpShiftRightLogical, full_result, shift);
                // Directly check if its zero in the op_ty without converting first.
                const zero: Temporary = .init(full_result.ty, try cg.constInt(full_result.ty, 0));
                const overflowed = try cg.buildCmp(.OpINotEqual, zero, overflow);
                break :blk .{ result, overflowed };
            }

            const low_bits, const high_bits = try cg.buildWideMul(.unsigned, lhs, rhs);

            // Truncate the result, if required.
            const result = try cg.normalize(low_bits, info);

            // Overflow happened if the high-bits of the result are non-zero OR if the
            // high bits of the low word of the result (those outside the range of the
            // int) are nonzero.
            const zero: Temporary = .init(lhs.ty, try cg.constInt(lhs.ty, 0));
            const high_overflowed = try cg.buildCmp(.OpINotEqual, zero, high_bits);

            // If no overflow bits in low_bits, no extra work needs to be done.
            if (info.backing_bits == info.bits) break :blk .{ result, high_overflowed };

            // Shift the result bits away to get the overflow bits.
            const shift: Temporary = .init(lhs.ty, try cg.constInt(lhs.ty, info.bits));
            const low_overflow = try cg.buildBinary(.OpShiftRightLogical, low_bits, shift);
            const low_overflowed = try cg.buildCmp(.OpINotEqual, zero, low_overflow);

            const overflowed = try cg.buildCmp(.OpLogicalOr, low_overflowed, high_overflowed);

            break :blk .{ result, overflowed };
        },
        .signed => blk: {
            // - lhs >= 0, rhxs >= 0: expect positive; overflow should be  0
            // - lhs == 0          : expect positive; overflow should be  0
            // -           rhs == 0: expect positive; overflow should be  0
            // - lhs  > 0, rhs  < 0: expect negative; overflow should be -1
            // - lhs  < 0, rhs  > 0: expect negative; overflow should be -1
            // - lhs <= 0, rhs <= 0: expect positive; overflow should be  0
            // ------
            // overflow should be -1 when
            //   (lhs > 0 && rhs < 0) || (lhs < 0 && rhs > 0)

            const zero: Temporary = .init(lhs.ty, try cg.constInt(lhs.ty, 0));
            const lhs_negative = try cg.buildCmp(.OpSLessThan, lhs, zero);
            const rhs_negative = try cg.buildCmp(.OpSLessThan, rhs, zero);
            const lhs_positive = try cg.buildCmp(.OpSGreaterThan, lhs, zero);
            const rhs_positive = try cg.buildCmp(.OpSGreaterThan, rhs, zero);

            // Set to `true` if we expect -1.
            const expected_overflow_bit = try cg.buildBinary(
                .OpLogicalOr,
                try cg.buildCmp(.OpLogicalAnd, lhs_positive, rhs_negative),
                try cg.buildCmp(.OpLogicalAnd, lhs_negative, rhs_positive),
            );

            if (maybe_op_ty_bits) |op_ty_bits| {
                const op_ty = try pt.intType(.signed, op_ty_bits);
                // Assume normalized; sign bit is set. We want a sign extend.
                const casted_lhs = try cg.buildConvert(op_ty, lhs);
                const casted_rhs = try cg.buildConvert(op_ty, rhs);

                const full_result = try cg.buildBinary(.OpIMul, casted_lhs, casted_rhs);

                // Truncate to the result type.
                const low_bits = try cg.buildConvert(lhs.ty, full_result);
                const result = try cg.normalize(low_bits, info);

                // Now, we need to check the overflow bits AND the sign
                // bit for the expected overflow bits.
                // To do that, shift out everything bit the sign bit and
                // then check what remains.
                const shift: Temporary = .init(full_result.ty, try cg.constInt(full_result.ty, info.bits - 1));
                // Use SRA so that any sign bits are duplicated. Now we can just check if ALL bits are set
                // for negative cases.
                const overflow = try cg.buildBinary(.OpShiftRightArithmetic, full_result, shift);

                const long_all_set: Temporary = .init(full_result.ty, try cg.constInt(full_result.ty, -1));
                const long_zero: Temporary = .init(full_result.ty, try cg.constInt(full_result.ty, 0));
                const mask = try cg.buildSelect(expected_overflow_bit, long_all_set, long_zero);

                const overflowed = try cg.buildCmp(.OpINotEqual, mask, overflow);

                break :blk .{ result, overflowed };
            }

            const low_bits, const high_bits = try cg.buildWideMul(.signed, lhs, rhs);

            // Truncate result if required.
            const result = try cg.normalize(low_bits, info);

            const all_set: Temporary = .init(lhs.ty, try cg.constInt(lhs.ty, -1));
            const mask = try cg.buildSelect(expected_overflow_bit, all_set, zero);

            // Like with unsigned, overflow happened if high_bits are not the ones we expect,
            // and we also need to check some ones from the low bits.

            const high_overflowed = try cg.buildCmp(.OpINotEqual, mask, high_bits);

            // If no overflow bits in low_bits, no extra work needs to be done.
            // Careful, we still have to check the sign bit, so this branch
            // only goes for i33 and such.
            if (info.backing_bits == info.bits + 1) break :blk .{ result, high_overflowed };

            // Shift the result bits away to get the overflow bits.
            const shift: Temporary = .init(lhs.ty, try cg.constInt(lhs.ty, info.bits - 1));
            // Use SRA so that any sign bits are duplicated. Now we can just check if ALL bits are set
            // for negative cases.
            const low_overflow = try cg.buildBinary(.OpShiftRightArithmetic, low_bits, shift);
            const low_overflowed = try cg.buildCmp(.OpINotEqual, mask, low_overflow);

            const overflowed = try cg.buildCmp(.OpLogicalOr, low_overflowed, high_overflowed);

            break :blk .{ result, overflowed };
        },
    };

    const ov = try cg.intFromBool(overflowed, .u1);

    const result_ty_id = try cg.resolveType(result_ty, .direct);
    return try cg.constructComposite(result_ty_id, &.{ try result.materialize(cg), try ov.materialize(cg) });
}

fn airShlOverflow(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const zcu = cg.zcu;

    const ty_pl = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const extra = cg.air.extraData(Air.Bin, ty_pl.payload).data;

    if (cg.typeOf(extra.lhs).isVector(zcu) and !cg.typeOf(extra.rhs).isVector(zcu)) {
        return cg.fail("vector shift with scalar rhs", .{});
    }

    const base = try cg.temporary(extra.lhs);
    const shift = try cg.temporary(extra.rhs);

    const result_ty = cg.typeOfIndex(inst);

    const info = cg.arithmeticTypeInfo(base.ty);
    switch (info.class) {
        .composite_integer => return cg.todo("shl-with-overflow for composite integers", .{}),
        .integer, .strange_integer => {},
        .float, .bool => unreachable,
    }

    // Sometimes Zig doesn't make both of the arguments the same types here. SPIR-V expects that,
    // so just manually upcast it if required.
    const casted_shift = try cg.buildConvert(base.ty.scalarType(zcu), shift);

    const left = try cg.buildBinary(.OpShiftLeftLogical, base, casted_shift);
    const result = try cg.normalize(left, info);

    const right = switch (info.signedness) {
        .unsigned => try cg.buildBinary(.OpShiftRightLogical, result, casted_shift),
        .signed => try cg.buildBinary(.OpShiftRightArithmetic, result, casted_shift),
    };

    const overflowed = try cg.buildCmp(.OpINotEqual, base, right);
    const ov = try cg.intFromBool(overflowed, .u1);

    const result_ty_id = try cg.resolveType(result_ty, .direct);
    return try cg.constructComposite(result_ty_id, &.{ try result.materialize(cg), try ov.materialize(cg) });
}

fn airMulAdd(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const pl_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].pl_op;
    const extra = cg.air.extraData(Air.Bin, pl_op.payload).data;

    const a = try cg.temporary(extra.lhs);
    const b = try cg.temporary(extra.rhs);
    const c = try cg.temporary(pl_op.operand);

    const result_ty = cg.typeOfIndex(inst);
    const info = cg.arithmeticTypeInfo(result_ty);
    assert(info.class == .float); // .mul_add is only emitted for floats

    const zcu = cg.zcu;
    const target = zcu.getTarget();

    const v = cg.vectorization(.{ a, b, c });
    const ops = v.components();
    const results = cg.allocIds(ops);

    const op_result_ty = a.ty.scalarType(zcu);
    const op_result_ty_id = try cg.resolveType(op_result_ty, .direct);
    const result_temp_ty = try v.resultType(cg, a.ty);

    const op_a = try v.prepare(cg, a);
    const op_b = try v.prepare(cg, b);
    const op_c = try v.prepare(cg, c);

    const set = try cg.importExtendedSet();
    const opcode: u32 = switch (target.os.tag) {
        .opencl => @intFromEnum(spec.OpenClOpcode.fma),
        // NOTE: Vulkan's FMA does not meet Zig's nor OpenCL's precision guarantees and needs
        // to be emulated.
        .vulkan, .opengl => @intFromEnum(spec.GlslOpcode.Fma),
        else => unreachable,
    };

    for (0..ops) |i| {
        try cg.body.emit(cg.gpa, .OpExtInst, .{
            .id_result_type = op_result_ty_id,
            .id_result = results.at(i),
            .set = set,
            .instruction = .{ .inst = opcode },
            .id_ref_4 = &.{ op_a.at(i), op_b.at(i), op_c.at(i) },
        });
    }

    const result = v.finalize(result_temp_ty, results);
    return try result.materialize(cg);
}

fn airClzCtz(cg: *CodeGen, inst: Air.Inst.Index, op: UnaryOp) !?Id {
    if (cg.liveness.isUnused(inst)) return null;

    const zcu = cg.zcu;
    const ty_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand = try cg.temporary(ty_op.operand);

    const scalar_result_ty = cg.typeOfIndex(inst).scalarType(zcu);

    const info = cg.arithmeticTypeInfo(operand.ty);
    switch (info.class) {
        .composite_integer => return cg.todo("@clz/@ctz for composite integers", .{}),
        .integer, .strange_integer => {},
        .float, .bool => unreachable,
    }

    const count = try cg.buildUnary(op, operand);

    // Result of OpenCL ctz/clz returns operand.ty, and we want result_ty.
    // result_ty is always large enough to hold the result, so we might have to down
    // cast it.
    const result = try cg.buildConvert(scalar_result_ty, count);
    return try result.materialize(cg);
}

fn airSelect(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const pl_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].pl_op;
    const extra = cg.air.extraData(Air.Bin, pl_op.payload).data;
    const pred = try cg.temporary(pl_op.operand);
    const a = try cg.temporary(extra.lhs);
    const b = try cg.temporary(extra.rhs);

    const result = try cg.buildSelect(pred, a, b);
    return try result.materialize(cg);
}

fn airSplat(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const ty_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;

    const operand_id = try cg.resolve(ty_op.operand);
    const result_ty = cg.typeOfIndex(inst);

    return try cg.constructCompositeSplat(result_ty, operand_id);
}

fn airReduce(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const zcu = cg.zcu;
    const reduce = cg.air.instructions.items(.data)[@intFromEnum(inst)].reduce;
    const operand = try cg.resolve(reduce.operand);
    const operand_ty = cg.typeOf(reduce.operand);
    const scalar_ty = operand_ty.scalarType(zcu);
    const info = cg.arithmeticTypeInfo(operand_ty);
    const len = operand_ty.vectorLen(zcu);
    const first = try cg.extractVectorComponent(scalar_ty, operand, 0);

    switch (reduce.operation) {
        .Min, .Max => |op| {
            var result: Temporary = .init(scalar_ty, first);
            const cmp_op: MinMax = switch (op) {
                .Max => .max,
                .Min => .min,
                else => unreachable,
            };
            for (1..len) |i| {
                const lhs = result;
                const rhs_id = try cg.extractVectorComponent(scalar_ty, operand, @intCast(i));
                const rhs: Temporary = .init(scalar_ty, rhs_id);

                result = try cg.minMax(lhs, rhs, cmp_op);
            }

            return try result.materialize(cg);
        },
        else => {},
    }

    const opcode: Opcode = switch (info.class) {
        .bool => switch (reduce.operation) {
            .And => .OpLogicalAnd,
            .Or => .OpLogicalOr,
            .Xor => .OpLogicalNotEqual,
            else => unreachable,
        },
        .strange_integer, .integer => switch (reduce.operation) {
            .And => .OpBitwiseAnd,
            .Or => .OpBitwiseOr,
            .Xor => .OpBitwiseXor,
            .Add => .OpIAdd,
            .Mul => .OpIMul,
            else => unreachable,
        },
        .float => switch (reduce.operation) {
            .Add => .OpFAdd,
            .Mul => .OpFMul,
            else => unreachable,
        },
        .composite_integer => return cg.todo("@reduce for composite integers", .{}),
    };

    const needs_normalize = info.class == .strange_integer and
        (reduce.operation == .Add or reduce.operation == .Mul);

    var result: Temporary = .init(scalar_ty, first);
    for (1..len) |i| {
        const rhs_id = try cg.extractVectorComponent(scalar_ty, operand, @intCast(i));
        const rhs: Temporary = .init(scalar_ty, rhs_id);
        const stepped = try cg.buildBinary(opcode, result, rhs);
        result = if (needs_normalize) try cg.normalize(stepped, info) else stepped;
    }

    return try result.materialize(cg);
}

fn airShuffleOne(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const zcu = cg.zcu;
    const gpa = zcu.gpa;

    const unwrapped = cg.air.unwrapShuffleOne(zcu, inst);
    const mask = unwrapped.mask;
    const result_ty = unwrapped.result_ty;
    const elem_ty = result_ty.childType(zcu);
    const operand = try cg.resolve(unwrapped.operand);

    const scratch_top = cg.id_scratch.items.len;
    defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
    const constituents = try cg.id_scratch.addManyAsSlice(gpa, mask.len);

    for (constituents, mask) |*id, mask_elem| {
        id.* = switch (mask_elem.unwrap()) {
            .elem => |idx| try cg.extractVectorComponent(elem_ty, operand, idx),
            .value => |val| try cg.constant(elem_ty, .fromInterned(val), .direct),
        };
    }

    const result_ty_id = try cg.resolveType(result_ty, .direct);
    return try cg.constructComposite(result_ty_id, constituents);
}

fn airShuffleTwo(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const zcu = cg.zcu;
    const gpa = zcu.gpa;

    const unwrapped = cg.air.unwrapShuffleTwo(zcu, inst);
    const mask = unwrapped.mask;
    const result_ty = unwrapped.result_ty;
    const elem_ty = result_ty.childType(zcu);
    const elem_ty_id = try cg.resolveType(elem_ty, .direct);
    const operand_a = try cg.resolve(unwrapped.operand_a);
    const operand_b = try cg.resolve(unwrapped.operand_b);

    const scratch_top = cg.id_scratch.items.len;
    defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
    const constituents = try cg.id_scratch.addManyAsSlice(gpa, mask.len);

    for (constituents, mask) |*id, mask_elem| {
        id.* = switch (mask_elem.unwrap()) {
            .a_elem => |idx| try cg.extractVectorComponent(elem_ty, operand_a, idx),
            .b_elem => |idx| try cg.extractVectorComponent(elem_ty, operand_b, idx),
            .undef => try cg.constUndef(elem_ty_id),
        };
    }

    const result_ty_id = try cg.resolveType(result_ty, .direct);
    return try cg.constructComposite(result_ty_id, constituents);
}

fn accessChainId(
    cg: *CodeGen,
    result_ty_id: Id,
    base: Id,
    indices: []const Id,
) !Id {
    const result_id = cg.allocId();
    try cg.body.emit(cg.gpa, .OpInBoundsAccessChain, .{
        .id_result_type = result_ty_id,
        .id_result = result_id,
        .base = base,
        .indexes = indices,
    });
    return result_id;
}

/// AccessChain is essentially PtrAccessChain with 0 as initial argument. The effective
/// difference lies in whether the resulting type of the first dereference will be the
/// same as that of the base pointer, or that of a dereferenced base pointer. AccessChain
/// is the latter and PtrAccessChain is the former.
fn accessChain(
    cg: *CodeGen,
    result_ty_id: Id,
    base: Id,
    indices: []const u32,
) !Id {
    const gpa = cg.gpa;
    const scratch_top = cg.id_scratch.items.len;
    defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
    const ids = try cg.id_scratch.addManyAsSlice(gpa, indices.len);
    for (indices, ids) |index, *id| {
        id.* = try cg.constInt(.u32, index);
    }
    return try cg.accessChainId(result_ty_id, base, ids);
}

fn ptrAccessChain(
    cg: *CodeGen,
    result_ty_id: Id,
    base: Id,
    element: Id,
    indices: []const u32,
) !Id {
    const gpa = cg.gpa;
    const target = cg.zcu.getTarget();

    const scratch_top = cg.id_scratch.items.len;
    defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
    const ids = try cg.id_scratch.addManyAsSlice(gpa, indices.len);
    for (indices, ids) |index, *id| {
        id.* = try cg.constInt(.u32, index);
    }

    const result_id = cg.allocId();
    switch (target.os.tag) {
        .opencl, .amdhsa => {
            try cg.body.emit(gpa, .OpInBoundsPtrAccessChain, .{
                .id_result_type = result_ty_id,
                .id_result = result_id,
                .base = base,
                .element = element,
                .indexes = ids,
            });
        },
        .vulkan, .opengl => {
            try cg.body.emit(gpa, .OpPtrAccessChain, .{
                .id_result_type = result_ty_id,
                .id_result = result_id,
                .base = base,
                .element = element,
                .indexes = ids,
            });
        },
        else => unreachable,
    }
    return result_id;
}

fn ptrAdd(cg: *CodeGen, result_ty: Type, ptr_ty: Type, ptr_id: Id, offset_id: Id) !Id {
    const zcu = cg.zcu;
    const result_ty_id = try cg.resolveType(result_ty, .direct);

    switch (ptr_ty.ptrSize(zcu)) {
        .one => {
            // Pointer to array
            // TODO: Is this correct?
            return try cg.accessChainId(result_ty_id, ptr_id, &.{offset_id});
        },
        .c, .many => {
            return try cg.ptrAccessChain(result_ty_id, ptr_id, offset_id, &.{});
        },
        .slice => {
            // TODO: This is probably incorrect. A slice should be returned here, though this is what llvm does.
            const slice_ptr_id = try cg.extractField(result_ty, ptr_id, 0);
            return try cg.ptrAccessChain(result_ty_id, slice_ptr_id, offset_id, &.{});
        },
    }
}

fn airPtrAdd(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const ty_pl = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const bin_op = cg.air.extraData(Air.Bin, ty_pl.payload).data;
    const ptr_id = try cg.resolve(bin_op.lhs);
    const offset_id = try cg.resolve(bin_op.rhs);
    const ptr_ty = cg.typeOf(bin_op.lhs);
    const result_ty = cg.typeOfIndex(inst);

    return try cg.ptrAdd(result_ty, ptr_ty, ptr_id, offset_id);
}

fn airPtrSub(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const ty_pl = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const bin_op = cg.air.extraData(Air.Bin, ty_pl.payload).data;
    const ptr_id = try cg.resolve(bin_op.lhs);
    const ptr_ty = cg.typeOf(bin_op.lhs);
    const offset_id = try cg.resolve(bin_op.rhs);
    const offset_ty = cg.typeOf(bin_op.rhs);
    const offset_ty_id = try cg.resolveType(offset_ty, .direct);
    const result_ty = cg.typeOfIndex(inst);

    const negative_offset_id = cg.allocId();
    try cg.body.emit(cg.gpa, .OpSNegate, .{
        .id_result_type = offset_ty_id,
        .id_result = negative_offset_id,
        .operand = offset_id,
    });
    return try cg.ptrAdd(result_ty, ptr_ty, ptr_id, negative_offset_id);
}

fn cmp(
    cg: *CodeGen,
    op: std.math.CompareOperator,
    lhs: Temporary,
    rhs: Temporary,
) !Temporary {
    const gpa = cg.gpa;
    const pt = cg.pt;
    const zcu = cg.zcu;
    const scalar_ty = lhs.ty.scalarType(zcu);
    const is_vector = lhs.ty.isVector(zcu);

    switch (scalar_ty.zigTypeTag(zcu)) {
        .int, .bool, .float => {},
        .@"enum" => {
            assert(!is_vector);
            const ty = lhs.ty.intTagType(zcu);
            return try cg.cmp(op, lhs.pun(ty), rhs.pun(ty));
        },
        .@"struct" => {
            const struct_ty = zcu.typeToPackedStruct(scalar_ty).?;
            const ty: Type = .fromInterned(struct_ty.packed_backing_int_type);
            return try cg.cmp(op, lhs.pun(ty), rhs.pun(ty));
        },
        .error_set => {
            assert(!is_vector);
            const err_int_ty = try pt.errorIntType();
            return try cg.cmp(op, lhs.pun(err_int_ty), rhs.pun(err_int_ty));
        },
        .pointer => {
            assert(!is_vector);
            // Note that while SPIR-V offers OpPtrEqual and OpPtrNotEqual, they are
            // currently not implemented in the SPIR-V LLVM translator. Thus, we emit these using
            // OpConvertPtrToU...

            const usize_ty_id = try cg.resolveType(.usize, .direct);

            const lhs_int_id = cg.allocId();
            try cg.body.emit(gpa, .OpConvertPtrToU, .{
                .id_result_type = usize_ty_id,
                .id_result = lhs_int_id,
                .pointer = try lhs.materialize(cg),
            });

            const rhs_int_id = cg.allocId();
            try cg.body.emit(gpa, .OpConvertPtrToU, .{
                .id_result_type = usize_ty_id,
                .id_result = rhs_int_id,
                .pointer = try rhs.materialize(cg),
            });

            const lhs_int: Temporary = .init(.usize, lhs_int_id);
            const rhs_int: Temporary = .init(.usize, rhs_int_id);
            return try cg.cmp(op, lhs_int, rhs_int);
        },
        .optional => {
            assert(!is_vector);

            const ty = lhs.ty;

            const payload_ty = ty.optionalChild(zcu);
            if (ty.optionalReprIsPayload(zcu)) {
                assert(payload_ty.hasRuntimeBits(zcu));
                assert(!payload_ty.isSlice(zcu));

                return try cg.cmp(op, lhs.pun(payload_ty), rhs.pun(payload_ty));
            }

            const lhs_id = try lhs.materialize(cg);
            const rhs_id = try rhs.materialize(cg);

            const lhs_valid_id = if (payload_ty.hasRuntimeBits(zcu))
                try cg.extractField(.bool, lhs_id, 1)
            else
                try cg.convertToDirect(.bool, lhs_id);

            const rhs_valid_id = if (payload_ty.hasRuntimeBits(zcu))
                try cg.extractField(.bool, rhs_id, 1)
            else
                try cg.convertToDirect(.bool, rhs_id);

            const lhs_valid: Temporary = .init(.bool, lhs_valid_id);
            const rhs_valid: Temporary = .init(.bool, rhs_valid_id);

            if (!payload_ty.hasRuntimeBits(zcu)) {
                return try cg.cmp(op, lhs_valid, rhs_valid);
            }

            // a = lhs_valid
            // b = rhs_valid
            // c = lhs_pl == rhs_pl
            //
            // For op == .eq we have:
            //   a == b && a -> c
            // = a == b && (!a || c)
            //
            // For op == .neq we have
            //   a == b && a -> c
            // = !(a == b && a -> c)
            // = a != b || !(a -> c
            // = a != b || !(!a || c)
            // = a != b || a && !c

            const lhs_pl_id = try cg.extractField(payload_ty, lhs_id, 0);
            const rhs_pl_id = try cg.extractField(payload_ty, rhs_id, 0);

            const lhs_pl: Temporary = .init(payload_ty, lhs_pl_id);
            const rhs_pl: Temporary = .init(payload_ty, rhs_pl_id);

            return switch (op) {
                .eq => try cg.buildBinary(
                    .OpLogicalAnd,
                    try cg.cmp(.eq, lhs_valid, rhs_valid),
                    try cg.buildBinary(
                        .OpLogicalOr,
                        try cg.buildUnary(.l_not, lhs_valid),
                        try cg.cmp(.eq, lhs_pl, rhs_pl),
                    ),
                ),
                .neq => try cg.buildBinary(
                    .OpLogicalOr,
                    try cg.cmp(.neq, lhs_valid, rhs_valid),
                    try cg.buildBinary(
                        .OpLogicalAnd,
                        lhs_valid,
                        try cg.cmp(.neq, lhs_pl, rhs_pl),
                    ),
                ),
                else => unreachable,
            };
        },
        else => |ty| return cg.todo("implement cmp operation for '{s}' type", .{@tagName(ty)}),
    }

    const info = cg.arithmeticTypeInfo(scalar_ty);
    const pred: Opcode = switch (info.class) {
        .composite_integer => {
            const lhs_id = try lhs.materialize(cg);
            const rhs_id = try rhs.materialize(cg);
            const scratch_top = cg.id_scratch.items.len;
            defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
            const ci_lhs = try CompositeInt.init(cg, lhs_id, info);
            const ci_rhs = try CompositeInt.init(cg, rhs_id, info);
            const result_id = try ci_lhs.cmp(ci_rhs, op);
            return .init(.bool, result_id);
        },
        .float => switch (op) {
            .eq => .OpFOrdEqual,
            .neq => .OpFUnordNotEqual,
            .lt => .OpFOrdLessThan,
            .lte => .OpFOrdLessThanEqual,
            .gt => .OpFOrdGreaterThan,
            .gte => .OpFOrdGreaterThanEqual,
        },
        .bool => switch (op) {
            .eq => .OpLogicalEqual,
            .neq => .OpLogicalNotEqual,
            else => unreachable,
        },
        .integer, .strange_integer => switch (info.signedness) {
            .signed => switch (op) {
                .eq => .OpIEqual,
                .neq => .OpINotEqual,
                .lt => .OpSLessThan,
                .lte => .OpSLessThanEqual,
                .gt => .OpSGreaterThan,
                .gte => .OpSGreaterThanEqual,
            },
            .unsigned => switch (op) {
                .eq => .OpIEqual,
                .neq => .OpINotEqual,
                .lt => .OpULessThan,
                .lte => .OpULessThanEqual,
                .gt => .OpUGreaterThan,
                .gte => .OpUGreaterThanEqual,
            },
        },
    };

    return try cg.buildCmp(pred, lhs, rhs);
}

fn airCmp(
    cg: *CodeGen,
    inst: Air.Inst.Index,
    comptime op: std.math.CompareOperator,
) !?Id {
    const bin_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const lhs = try cg.temporary(bin_op.lhs);
    const rhs = try cg.temporary(bin_op.rhs);

    const result = try cg.cmp(op, lhs, rhs);
    return try result.materialize(cg);
}

fn airVectorCmp(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const ty_pl = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const vec_cmp = cg.air.extraData(Air.VectorCmp, ty_pl.payload).data;
    const lhs = try cg.temporary(vec_cmp.lhs);
    const rhs = try cg.temporary(vec_cmp.rhs);
    const op = vec_cmp.compareOperator();

    const result = try cg.cmp(op, lhs, rhs);
    return try result.materialize(cg);
}

/// Bitcast one type to another. Note: both types, input, output are expected in **direct** representation.
fn bitCast(
    cg: *CodeGen,
    dst_ty: Type,
    src_ty: Type,
    src_id: Id,
) !Id {
    const gpa = cg.gpa;
    const zcu = cg.zcu;
    const target = zcu.getTarget();

    if (src_ty.toIntern() == dst_ty.toIntern()) return src_id;
    if (src_ty.isPtrAtRuntime(zcu) and dst_ty.isPtrAtRuntime(zcu)) switch (target.os.tag) {
        .vulkan, .opengl => if (src_ty.ptrAddressSpace(zcu) != .physical_storage_buffer) return src_id,
        else => {},
    };

    const dst_ty_id = try cg.resolveType(dst_ty, .direct);
    const result_id = blk: {
        // Big-int ↔ big-int bitcast: the indirect representation is an array,
        // which OpBitcast cannot operate on. The arrays are bitwise identical
        // apart from the top limb's padding; the normalize pass below fixes
        // the padding.
        if (src_ty.isInt(zcu) and dst_ty.isInt(zcu)) {
            const src_info = src_ty.intInfo(zcu);
            const dst_info = dst_ty.intInfo(zcu);
            const src_backing, const src_big = cg.backingIntBits(src_info.bits);
            const dst_backing, const dst_big = cg.backingIntBits(dst_info.bits);
            if (src_backing == dst_backing and src_big and dst_big) break :blk src_id;
        }

        // TODO: Some more cases are missing here
        //   See fn bitCast in llvm.zig

        if (src_ty.zigTypeTag(zcu) == .int and dst_ty.isPtrAtRuntime(zcu)) {
            if (target.os.tag != .opencl) {
                if (dst_ty.ptrAddressSpace(zcu) != .physical_storage_buffer) {
                    return cg.fail(
                        "cannot cast integer to pointer with address space '{s}'",
                        .{@tagName(dst_ty.ptrAddressSpace(zcu))},
                    );
                }
            }

            const result_id = cg.allocId();
            try cg.body.emit(gpa, .OpConvertUToPtr, .{
                .id_result_type = dst_ty_id,
                .id_result = result_id,
                .integer_value = src_id,
            });
            break :blk result_id;
        }

        // We can only use OpBitcast for specific conversions: between numerical types, and
        // between pointers. If the resolved spir-v types fall into this category then emit OpBitcast,
        // otherwise use a temporary and perform a pointer cast.
        const can_bitcast = (src_ty.isNumeric(zcu) and dst_ty.isNumeric(zcu)) or (src_ty.isPtrAtRuntime(zcu) and dst_ty.isPtrAtRuntime(zcu));
        if (can_bitcast) {
            const result_id = cg.allocId();
            try cg.body.emit(gpa, .OpBitcast, .{
                .id_result_type = dst_ty_id,
                .id_result = result_id,
                .operand = src_id,
            });

            break :blk result_id;
        }

        switch (target.os.tag) {
            .vulkan, .opengl => {
                // Logical addressing forbids OpBitcast on pointers. Allocate
                // the temp with dst_ty so the load reads through a slot of the right type.
                const dst_ty_indirect_id = try cg.resolveType(dst_ty, .indirect);
                const tmp_id = try cg.alloc(dst_ty_indirect_id, null);
                try cg.store(dst_ty, tmp_id, src_id, .{});
                break :blk try cg.load(dst_ty, tmp_id, .{});
            },
            else => {},
        }

        const dst_ptr_ty_id = try cg.ptrType(dst_ty_id, .function);

        const src_ty_indirect_id = try cg.resolveType(src_ty, .indirect);
        const tmp_id = try cg.alloc(src_ty_indirect_id, null);
        try cg.store(src_ty, tmp_id, src_id, .{});
        const casted_ptr_id = cg.allocId();
        try cg.body.emit(gpa, .OpBitcast, .{
            .id_result_type = dst_ptr_ty_id,
            .id_result = casted_ptr_id,
            .operand = tmp_id,
        });
        break :blk try cg.load(dst_ty, casted_ptr_id, .{});
    };

    // Because strange integers use sign-extended representation, we may need to normalize
    // the result here.
    // TODO: This detail could cause stuff like @as(*const i1, @ptrCast(&@as(u1, 1))) to break
    // should we change the representation of strange integers?
    if (dst_ty.zigTypeTag(zcu) == .int) {
        const info = cg.arithmeticTypeInfo(dst_ty);
        const result = try cg.normalize(Temporary.init(dst_ty, result_id), info);
        return try result.materialize(cg);
    }

    return result_id;
}

fn airBitCast(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const ty_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand_ty = cg.typeOf(ty_op.operand);
    const result_ty = cg.typeOfIndex(inst);
    if (operand_ty.toIntern() == .bool_type) {
        const operand = try cg.temporary(ty_op.operand);
        const result = try cg.intFromBool(operand, .u1);
        return try result.materialize(cg);
    }
    if (operand_ty.zigTypeTag(cg.zcu) == .pointer) {
        switch (try cg.resolvePtr(ty_op.operand)) {
            .tracked => |t| return t.id, // TODO
            .id => |operand_id| return try cg.bitCast(result_ty, operand_ty, operand_id),
        }
    }
    const operand_id = try cg.resolve(ty_op.operand);
    return try cg.bitCast(result_ty, operand_ty, operand_id);
}

fn airIntCast(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const ty_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const src = try cg.temporary(ty_op.operand);
    const dst_ty = cg.typeOfIndex(inst);

    const src_info = cg.arithmeticTypeInfo(src.ty);
    const dst_info = cg.arithmeticTypeInfo(dst_ty);

    const src_composite = src_info.class == .composite_integer;
    const dst_composite = dst_info.class == .composite_integer;

    if (src_composite or dst_composite) {
        const gpa = cg.gpa;
        const scratch_top = cg.id_scratch.items.len;
        defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);

        if (src_composite and dst_composite) {
            const src_id = try src.materialize(cg);
            const src_n: u16 = src_info.backing_bits / big_int_bits;
            const dst_n: u16 = dst_info.backing_bits / big_int_bits;
            const result_limbs = try cg.id_scratch.addManyAsSlice(gpa, dst_n);
            const min_n = @min(src_n, dst_n);
            const u32_ty_id = try cg.resolveType(.u32, .direct);
            for (0..min_n) |i| {
                result_limbs[i] = cg.allocId();
                try cg.body.emit(gpa, .OpCompositeExtract, .{
                    .id_result_type = u32_ty_id,
                    .id_result = result_limbs[i],
                    .composite = src_id,
                    .indexes = &.{@as(u32, @intCast(i))},
                });
            }
            if (dst_n > src_n) {
                const fill = if (src_info.signedness == .signed) blk: {
                    const i32_ty_id = try cg.resolveType(.i32, .direct);
                    const msb = result_limbs[src_n - 1];
                    const msb_signed = cg.allocId();
                    try cg.body.emit(gpa, .OpBitcast, .{
                        .id_result_type = i32_ty_id,
                        .id_result = msb_signed,
                        .operand = msb,
                    });
                    const shift31 = try cg.constInt(.i32, @as(i32, 31));
                    const sign_ext = cg.allocId();
                    try cg.body.emit(gpa, .OpShiftRightArithmetic, .{
                        .id_result_type = i32_ty_id,
                        .id_result = sign_ext,
                        .base = msb_signed,
                        .shift = shift31,
                    });
                    const back = cg.allocId();
                    try cg.body.emit(gpa, .OpBitcast, .{
                        .id_result_type = u32_ty_id,
                        .id_result = back,
                        .operand = sign_ext,
                    });
                    break :blk back;
                } else try cg.constInt(.u32, @as(u32, 0));
                for (min_n..dst_n) |i| {
                    result_limbs[i] = fill;
                }
            }
            const ci = CompositeInt.fromLimbs(cg, result_limbs, dst_info);
            const normalized = try ci.normalize();
            return try normalized.materialize(dst_ty);
        } else if (src_composite and !dst_composite) {
            const src_id = try src.materialize(cg);
            const u32_ty_id = try cg.resolveType(.u32, .direct);
            if (dst_info.backing_bits <= 32) {
                const limb0 = cg.allocId();
                try cg.body.emit(gpa, .OpCompositeExtract, .{
                    .id_result_type = u32_ty_id,
                    .id_result = limb0,
                    .composite = src_id,
                    .indexes = &.{@as(u32, 0)},
                });
                const tmp: Temporary = .init(.u32, limb0);
                const converted = try cg.buildConvert(dst_ty, tmp);
                const result = if (dst_info.bits < src_info.bits)
                    try cg.normalize(converted, dst_info)
                else
                    converted;
                return try result.materialize(cg);
            } else {
                const limb0 = cg.allocId();
                try cg.body.emit(gpa, .OpCompositeExtract, .{
                    .id_result_type = u32_ty_id,
                    .id_result = limb0,
                    .composite = src_id,
                    .indexes = &.{@as(u32, 0)},
                });
                const limb1 = cg.allocId();
                try cg.body.emit(gpa, .OpCompositeExtract, .{
                    .id_result_type = u32_ty_id,
                    .id_result = limb1,
                    .composite = src_id,
                    .indexes = &.{@as(u32, 1)},
                });
                const u64_ty_id = try cg.resolveType(.u64, .direct);
                const lo = cg.allocId();
                try cg.body.emit(gpa, .OpUConvert, .{
                    .id_result_type = u64_ty_id,
                    .id_result = lo,
                    .unsigned_value = limb0,
                });
                const hi = cg.allocId();
                try cg.body.emit(gpa, .OpUConvert, .{
                    .id_result_type = u64_ty_id,
                    .id_result = hi,
                    .unsigned_value = limb1,
                });
                const shift32 = try cg.constInt(.u64, @as(u64, 32));
                const hi_shifted = cg.allocId();
                try cg.body.emit(gpa, .OpShiftLeftLogical, .{
                    .id_result_type = u64_ty_id,
                    .id_result = hi_shifted,
                    .base = hi,
                    .shift = shift32,
                });
                const combined = cg.allocId();
                try cg.body.emit(gpa, .OpBitwiseOr, .{
                    .id_result_type = u64_ty_id,
                    .id_result = combined,
                    .operand_1 = lo,
                    .operand_2 = hi_shifted,
                });
                const tmp: Temporary = .init(.u64, combined);
                const converted = try cg.buildConvert(dst_ty, tmp);
                const result = if (dst_info.bits < src_info.bits)
                    try cg.normalize(converted, dst_info)
                else
                    converted;
                return try result.materialize(cg);
            }
        } else {
            const dst_n: u16 = dst_info.backing_bits / big_int_bits;
            const result_limbs = try cg.id_scratch.addManyAsSlice(gpa, dst_n);
            const u32_ty_id = try cg.resolveType(.u32, .direct);

            if (src_info.backing_bits <= 32) {
                const converted = try cg.buildConvert(.u32, src);
                result_limbs[0] = try converted.materialize(cg);
            } else {
                const src_as_u64 = try cg.buildConvert(.u64, src);
                const src_id = try src_as_u64.materialize(cg);
                result_limbs[0] = cg.allocId();
                try cg.body.emit(gpa, .OpUConvert, .{
                    .id_result_type = u32_ty_id,
                    .id_result = result_limbs[0],
                    .unsigned_value = src_id,
                });
                const u64_ty_id = try cg.resolveType(.u64, .direct);
                const shift32 = try cg.constInt(.u64, @as(u64, 32));
                const hi = cg.allocId();
                try cg.body.emit(gpa, .OpShiftRightLogical, .{
                    .id_result_type = u64_ty_id,
                    .id_result = hi,
                    .base = src_id,
                    .shift = shift32,
                });
                result_limbs[1] = cg.allocId();
                try cg.body.emit(gpa, .OpUConvert, .{
                    .id_result_type = u32_ty_id,
                    .id_result = result_limbs[1],
                    .unsigned_value = hi,
                });
            }
            // Sign/zero-extend remaining limbs.
            const fill_start: u16 = if (src_info.backing_bits <= 32) 1 else 2;
            const fill = if (src_info.signedness == .signed) blk: {
                const i32_ty_id = try cg.resolveType(.i32, .direct);
                const msb = result_limbs[fill_start - 1];
                const msb_signed = cg.allocId();
                try cg.body.emit(gpa, .OpBitcast, .{
                    .id_result_type = i32_ty_id,
                    .id_result = msb_signed,
                    .operand = msb,
                });
                const shift31 = try cg.constInt(.i32, @as(i32, 31));
                const sign_ext = cg.allocId();
                try cg.body.emit(gpa, .OpShiftRightArithmetic, .{
                    .id_result_type = i32_ty_id,
                    .id_result = sign_ext,
                    .base = msb_signed,
                    .shift = shift31,
                });
                const back = cg.allocId();
                try cg.body.emit(gpa, .OpBitcast, .{
                    .id_result_type = u32_ty_id,
                    .id_result = back,
                    .operand = sign_ext,
                });
                break :blk back;
            } else try cg.constInt(.u32, @as(u32, 0));
            for (fill_start..dst_n) |i| {
                result_limbs[i] = fill;
            }
            const ci = CompositeInt.fromLimbs(cg, result_limbs, dst_info);
            const normalized = try ci.normalize();
            return try normalized.materialize(dst_ty);
        }
    }

    if (src_info.backing_bits == dst_info.backing_bits) {
        const result = if (dst_info.bits < src_info.bits)
            try cg.normalize(src.pun(dst_ty), dst_info)
        else
            src.pun(dst_ty);
        return try result.materialize(cg);
    }

    const converted = try cg.buildConvert(dst_ty, src);

    // Make sure to normalize the result if shrinking.
    // Because strange ints are sign extended in their backing
    // type, we don't need to normalize when growing the type. The
    // representation is already the same.
    const result = if (dst_info.bits < src_info.bits)
        try cg.normalize(converted, dst_info)
    else
        converted;

    return try result.materialize(cg);
}

fn intFromPtr(cg: *CodeGen, operand_id: Id) !Id {
    const result_type_id = try cg.resolveType(.usize, .direct);
    const result_id = cg.allocId();
    try cg.body.emit(cg.gpa, .OpConvertPtrToU, .{
        .id_result_type = result_type_id,
        .id_result = result_id,
        .pointer = operand_id,
    });
    return result_id;
}

fn airFloatFromInt(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const gpa = cg.gpa;
    const ty_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand_ty = cg.typeOf(ty_op.operand);
    const operand_id = try cg.resolve(ty_op.operand);
    const result_ty = cg.typeOfIndex(inst);
    const operand_info = cg.arithmeticTypeInfo(operand_ty);
    const result_id = cg.allocId();
    const result_ty_id = try cg.resolveType(result_ty, .direct);
    switch (operand_info.signedness) {
        .signed => try cg.body.emit(gpa, .OpConvertSToF, .{
            .id_result_type = result_ty_id,
            .id_result = result_id,
            .signed_value = operand_id,
        }),
        .unsigned => try cg.body.emit(gpa, .OpConvertUToF, .{
            .id_result_type = result_ty_id,
            .id_result = result_id,
            .unsigned_value = operand_id,
        }),
    }
    return result_id;
}

fn airIntFromFloat(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const gpa = cg.gpa;
    const ty_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand_id = try cg.resolve(ty_op.operand);
    const result_ty = cg.typeOfIndex(inst);
    const result_info = cg.arithmeticTypeInfo(result_ty);
    const result_ty_id = try cg.resolveType(result_ty, .direct);
    const result_id = cg.allocId();
    switch (result_info.signedness) {
        .signed => try cg.body.emit(gpa, .OpConvertFToS, .{
            .id_result_type = result_ty_id,
            .id_result = result_id,
            .float_value = operand_id,
        }),
        .unsigned => try cg.body.emit(gpa, .OpConvertFToU, .{
            .id_result_type = result_ty_id,
            .id_result = result_id,
            .float_value = operand_id,
        }),
    }
    return result_id;
}

fn airFloatCast(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const ty_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand = try cg.temporary(ty_op.operand);
    const dest_ty = cg.typeOfIndex(inst);
    const result = try cg.buildConvert(dest_ty, operand);
    return try result.materialize(cg);
}

fn airNot(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const ty_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand = try cg.temporary(ty_op.operand);
    const result_ty = cg.typeOfIndex(inst);
    const info = cg.arithmeticTypeInfo(result_ty);

    const result = switch (info.class) {
        .bool => try cg.buildUnary(.l_not, operand),
        .float => unreachable,
        .composite_integer => blk: {
            const op_id = try operand.materialize(cg);
            const scratch_top = cg.id_scratch.items.len;
            defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
            const ci = try CompositeInt.init(cg, op_id, info);
            const notted = try ci.bitwiseNot();
            const normalized = try notted.normalize();
            break :blk Temporary.init(result_ty, try normalized.materialize(result_ty));
        },
        .strange_integer, .integer => blk: {
            const complement = try cg.buildUnary(.bit_not, operand);
            break :blk try cg.normalize(complement, info);
        },
    };

    return try result.materialize(cg);
}

fn airArrayToSlice(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const zcu = cg.zcu;
    const ty_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const array_ptr_ty = cg.typeOf(ty_op.operand);
    const array_ty = array_ptr_ty.childType(zcu);
    const slice_ty = cg.typeOfIndex(inst);
    const elem_ptr_ty = slice_ty.slicePtrFieldType(zcu);

    const elem_ptr_ty_id = try cg.resolveType(elem_ptr_ty, .direct);

    const array_ptr_id = try cg.resolve(ty_op.operand);
    const len_id = try cg.constInt(.usize, array_ty.arrayLen(zcu));

    const elem_ptr_id = if (!array_ty.hasRuntimeBits(zcu))
        // Note: The pointer is something like *opaque{}, so we need to bitcast it to the element type.
        try cg.bitCast(elem_ptr_ty, array_ptr_ty, array_ptr_id)
    else
        // Convert the pointer-to-array to a pointer to the first element.
        try cg.accessChain(elem_ptr_ty_id, array_ptr_id, &.{0});

    const slice_ty_id = try cg.resolveType(slice_ty, .direct);
    return try cg.constructComposite(slice_ty_id, &.{ elem_ptr_id, len_id });
}

fn airSlice(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const ty_pl = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const bin_op = cg.air.extraData(Air.Bin, ty_pl.payload).data;
    const ptr_id = try cg.resolve(bin_op.lhs);
    const len_id = try cg.resolve(bin_op.rhs);
    const slice_ty = cg.typeOfIndex(inst);
    const slice_ty_id = try cg.resolveType(slice_ty, .direct);
    return try cg.constructComposite(slice_ty_id, &.{ ptr_id, len_id });
}

fn airAggregateInit(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const gpa = cg.gpa;
    const pt = cg.pt;
    const zcu = cg.zcu;
    const ip = &zcu.intern_pool;
    const target = cg.zcu.getTarget();
    const ty_pl = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const result_ty = cg.typeOfIndex(inst);
    const len: usize = @intCast(result_ty.arrayLen(zcu));
    const elements: []const Air.Inst.Ref = @ptrCast(cg.air.extra.items[ty_pl.payload..][0..len]);

    switch (result_ty.zigTypeTag(zcu)) {
        .@"struct" => {
            if (zcu.typeToPackedStruct(result_ty)) |struct_type| {
                comptime assert(Type.packed_struct_layout_version == 2);
                const backing_int_ty: Type = .fromInterned(struct_type.packed_backing_int_type);
                var running_int_id = try cg.constInt(backing_int_ty, 0);
                var running_bits: u16 = 0;
                for (struct_type.field_types.get(ip), elements) |field_ty_ip, element| {
                    const field_ty: Type = .fromInterned(field_ty_ip);
                    if (!field_ty.hasRuntimeBits(zcu)) continue;
                    const field_id = try cg.resolve(element);
                    const ty_bit_size: u16 = @intCast(field_ty.bitSize(zcu));
                    const field_int_ty = try cg.pt.intType(.unsigned, ty_bit_size);
                    const field_int_id = blk: {
                        if (field_ty.isPtrAtRuntime(zcu)) {
                            assert(target.cpu.arch == .spirv64 and
                                field_ty.ptrAddressSpace(zcu) == .storage_buffer);
                            break :blk try cg.intFromPtr(field_id);
                        }
                        break :blk try cg.bitCast(field_int_ty, field_ty, field_id);
                    };
                    const shift_rhs = try cg.constInt(backing_int_ty, running_bits);
                    const extended_int_conv = try cg.buildConvert(backing_int_ty, .{
                        .ty = field_int_ty,
                        .value = .{ .singleton = field_int_id },
                    });
                    const shifted = try cg.buildBinary(.OpShiftLeftLogical, extended_int_conv, .{
                        .ty = backing_int_ty,
                        .value = .{ .singleton = shift_rhs },
                    });
                    const running_int_tmp = try cg.buildBinary(
                        .OpBitwiseOr,
                        .{ .ty = backing_int_ty, .value = .{ .singleton = running_int_id } },
                        shifted,
                    );
                    running_int_id = try running_int_tmp.materialize(cg);
                    running_bits += ty_bit_size;
                }
                return running_int_id;
            }

            const scratch_top = cg.id_scratch.items.len;
            defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
            const constituents = try cg.id_scratch.addManyAsSlice(gpa, elements.len);

            const types = try gpa.alloc(Type, elements.len);
            defer gpa.free(types);

            var index: usize = 0;

            switch (ip.indexToKey(result_ty.toIntern())) {
                .tuple_type => |tuple| {
                    for (tuple.types.get(ip), elements, 0..) |field_ty, element, i| {
                        if ((try result_ty.structFieldValueComptime(pt, i)) != null) continue;
                        assert(Type.fromInterned(field_ty).hasRuntimeBits(zcu));

                        const id = try cg.resolve(element);
                        types[index] = .fromInterned(field_ty);
                        constituents[index] = try cg.convertToIndirect(.fromInterned(field_ty), id);
                        index += 1;
                    }
                },
                .struct_type => {
                    const struct_type = ip.loadStructType(result_ty.toIntern());
                    var it = struct_type.iterateRuntimeOrder(ip);
                    for (elements, 0..) |element, i| {
                        const field_index = it.next().?;
                        if ((try result_ty.structFieldValueComptime(pt, i)) != null) continue;
                        const field_ty: Type = .fromInterned(struct_type.field_types.get(ip)[field_index]);
                        assert(field_ty.hasRuntimeBits(zcu));

                        const id = try cg.resolve(element);
                        types[index] = field_ty;
                        constituents[index] = try cg.convertToIndirect(field_ty, id);
                        index += 1;
                    }
                },
                else => unreachable,
            }

            const result_ty_id = try cg.resolveType(result_ty, .direct);
            return try cg.constructComposite(result_ty_id, constituents[0..index]);
        },
        .vector => {
            const n_elems = result_ty.vectorLen(zcu);
            const scratch_top = cg.id_scratch.items.len;
            defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
            const elem_ids = try cg.id_scratch.addManyAsSlice(gpa, n_elems);

            for (elements, 0..) |element, i| {
                elem_ids[i] = try cg.resolve(element);
            }

            const result_ty_id = try cg.resolveType(result_ty, .direct);
            return try cg.constructComposite(result_ty_id, elem_ids);
        },
        .array => {
            const array_info = result_ty.arrayInfo(zcu);
            const n_elems: usize = @intCast(result_ty.arrayLenIncludingSentinel(zcu));
            const scratch_top = cg.id_scratch.items.len;
            defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
            const elem_ids = try cg.id_scratch.addManyAsSlice(gpa, n_elems);

            for (elements, 0..) |element, i| {
                const id = try cg.resolve(element);
                elem_ids[i] = try cg.convertToIndirect(array_info.elem_type, id);
            }

            if (array_info.sentinel) |sentinel_val| {
                elem_ids[n_elems - 1] = try cg.constant(array_info.elem_type, sentinel_val, .indirect);
            }

            const result_ty_id = try cg.resolveType(result_ty, .direct);
            return try cg.constructComposite(result_ty_id, elem_ids);
        },
        else => unreachable,
    }
}

fn sliceOrArrayPtr(cg: *CodeGen, operand_id: Id, ty: Type) !Id {
    const zcu = cg.zcu;
    if (ty.isSlice(zcu)) {
        const ptr_ty = ty.slicePtrFieldType(zcu);
        return cg.extractField(ptr_ty, operand_id, 0);
    }
    return operand_id;
}

fn airMemcpy(cg: *CodeGen, inst: Air.Inst.Index) !void {
    const bin_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const dest_slice = try cg.resolve(bin_op.lhs);
    const src_slice = try cg.resolve(bin_op.rhs);
    const dest_ty = cg.typeOf(bin_op.lhs);
    const src_ty = cg.typeOf(bin_op.rhs);
    const dest_ptr = try cg.sliceOrArrayPtr(dest_slice, dest_ty);
    const src_ptr = try cg.sliceOrArrayPtr(src_slice, src_ty);
    const len = switch (dest_ty.ptrSize(cg.zcu)) {
        .slice => try cg.extractField(.usize, dest_slice, 1),
        .one => len: {
            const array_ty = dest_ty.childType(cg.zcu);
            const elem_ty = array_ty.childType(cg.zcu);
            const size = array_ty.arrayLenIncludingSentinel(cg.zcu) * elem_ty.abiSize(cg.zcu);
            break :len try cg.constInt(.usize, size);
        },
        .many, .c => unreachable,
    };
    try cg.body.emit(cg.gpa, .OpCopyMemorySized, .{
        .target = dest_ptr,
        .source = src_ptr,
        .size = len,
    });
}

fn airMemmove(cg: *CodeGen, inst: Air.Inst.Index) !void {
    _ = inst;
    return cg.fail("TODO implement airMemcpy for spirv", .{});
}

fn airSliceField(cg: *CodeGen, inst: Air.Inst.Index, field: u32) !?Id {
    const ty_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const field_ty = cg.typeOfIndex(inst);
    const operand_id = try cg.resolve(ty_op.operand);
    return try cg.extractField(field_ty, operand_id, field);
}

fn airSpirvRuntimeArrayLen(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const gpa = cg.gpa;
    const ty_pl = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const extra = cg.air.extraData(Air.StructField, ty_pl.payload).data;
    const struct_ptr_id = try cg.resolve(extra.struct_operand);
    const u32_ty_id = try cg.intType(.unsigned, 32);
    const result_id = cg.allocId();
    try cg.body.emit(gpa, .OpArrayLength, .{
        .id_result_type = u32_ty_id,
        .id_result = result_id,
        .structure = struct_ptr_id,
        .array_member = extra.field_index,
    });
    return result_id;
}

fn airSliceElemPtr(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const zcu = cg.zcu;
    const ty_pl = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const bin_op = cg.air.extraData(Air.Bin, ty_pl.payload).data;
    const slice_ty = cg.typeOf(bin_op.lhs);
    if (!slice_ty.isVolatilePtr(zcu) and cg.liveness.isUnused(inst)) return null;

    const slice_id = try cg.resolve(bin_op.lhs);
    const index_id = try cg.resolve(bin_op.rhs);

    const ptr_ty = cg.typeOfIndex(inst);
    const ptr_ty_id = try cg.resolveType(ptr_ty, .direct);

    const slice_ptr = try cg.extractField(ptr_ty, slice_id, 0);
    return try cg.ptrAccessChain(ptr_ty_id, slice_ptr, index_id, &.{});
}

fn airSliceElemVal(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const zcu = cg.zcu;
    const bin_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const slice_ty = cg.typeOf(bin_op.lhs);
    if (!slice_ty.isVolatilePtr(zcu) and cg.liveness.isUnused(inst)) return null;

    const slice_id = try cg.resolve(bin_op.lhs);
    const index_id = try cg.resolve(bin_op.rhs);

    const ptr_ty = slice_ty.slicePtrFieldType(zcu);
    const ptr_ty_id = try cg.resolveType(ptr_ty, .direct);

    const slice_ptr = try cg.extractField(ptr_ty, slice_id, 0);
    const elem_ptr = try cg.ptrAccessChain(ptr_ty_id, slice_ptr, index_id, &.{});
    return try cg.load(slice_ty.childType(zcu), elem_ptr, .{ .is_volatile = slice_ty.isVolatilePtr(zcu) });
}

fn ptrElemPtr(cg: *CodeGen, ptr_ty: Type, ptr_id: Id, index_id: Id) !Id {
    const zcu = cg.zcu;
    // Construct new pointer type for the resulting pointer
    const elem_ty = ptr_ty.indexableElem(zcu);
    const elem_ty_id = try cg.resolveType(elem_ty, .indirect);
    const elem_ptr_ty_id = try cg.ptrType(elem_ty_id, cg.storageClass(ptr_ty.ptrAddressSpace(zcu)));
    if (ptr_ty.isSinglePointer(zcu)) {
        // Pointer-to-array. In this case, the resulting pointer is not of the same type
        // as the ptr_ty (we want a *T, not a *[N]T), and hence we need to use accessChain.
        return try cg.accessChainId(elem_ptr_ty_id, ptr_id, &.{index_id});
    } else {
        // Resulting pointer type is the same as the ptr_ty, so use ptrAccessChain
        return try cg.ptrAccessChain(elem_ptr_ty_id, ptr_id, index_id, &.{});
    }
}

fn airPtrElemPtr(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const zcu = cg.zcu;
    const ty_pl = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const bin_op = cg.air.extraData(Air.Bin, ty_pl.payload).data;
    const src_ptr_ty = cg.typeOf(bin_op.lhs);
    const elem_ty = src_ptr_ty.childType(zcu);
    const ptr_id = try cg.resolve(bin_op.lhs);

    assert(elem_ty.hasRuntimeBits(zcu));

    const index_id = try cg.resolve(bin_op.rhs);
    return try cg.ptrElemPtr(src_ptr_ty, ptr_id, index_id);
}

fn airArrayElemVal(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const gpa = cg.gpa;
    const zcu = cg.zcu;
    const bin_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const array_ty = cg.typeOf(bin_op.lhs);
    const elem_ty = array_ty.childType(zcu);
    const array_id = try cg.resolve(bin_op.lhs);
    const index_id = try cg.resolve(bin_op.rhs);

    // SPIR-V doesn't have an array indexing function for some damn reason.
    // For now, just generate a temporary and use that.
    // TODO: This backend probably also should use isByRef from llvm...

    const is_vector = array_ty.isVector(zcu);
    const elem_repr: Repr = if (is_vector) .direct else .indirect;
    const array_ty_id = try cg.resolveType(array_ty, .direct);
    const elem_ty_id = try cg.resolveType(elem_ty, elem_repr);
    const ptr_array_ty_id = try cg.ptrType(array_ty_id, .function);
    const ptr_elem_ty_id = try cg.ptrType(elem_ty_id, .function);

    const tmp_id = cg.allocId();
    try cg.prologue.emit(gpa, .OpVariable, .{
        .id_result_type = ptr_array_ty_id,
        .id_result = tmp_id,
        .storage_class = .function,
    });

    try cg.body.emit(gpa, .OpStore, .{
        .pointer = tmp_id,
        .object = array_id,
    });

    const elem_ptr_id = try cg.accessChainId(ptr_elem_ty_id, tmp_id, &.{index_id});

    const result_id = cg.allocId();
    try cg.body.emit(gpa, .OpLoad, .{
        .id_result_type = try cg.resolveType(elem_ty, elem_repr),
        .id_result = result_id,
        .pointer = elem_ptr_id,
    });

    if (is_vector) {
        // Result is already in direct representation
        return result_id;
    }

    // This is an array type; the elements are stored in indirect representation.
    // We have to convert the type to direct.

    return try cg.convertToDirect(elem_ty, result_id);
}

fn airPtrElemVal(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const zcu = cg.zcu;
    const bin_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const ptr_ty = cg.typeOf(bin_op.lhs);
    const elem_ty = cg.typeOfIndex(inst);
    const ptr_id = try cg.resolve(bin_op.lhs);
    const index_id = try cg.resolve(bin_op.rhs);
    const elem_ptr_id = try cg.ptrElemPtr(ptr_ty, ptr_id, index_id);
    return try cg.load(elem_ty, elem_ptr_id, .{ .is_volatile = ptr_ty.isVolatilePtr(zcu) });
}

fn airSetUnionTag(cg: *CodeGen, inst: Air.Inst.Index) !void {
    const zcu = cg.zcu;
    const bin_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const un_ptr_ty = cg.typeOf(bin_op.lhs);
    const un_ty = un_ptr_ty.childType(zcu);
    const layout = cg.unionLayout(un_ty);

    if (layout.tag_size == 0) return;

    const tag_ty = un_ty.unionTagTypeRuntime(zcu).?;
    const tag_ty_id = try cg.resolveType(tag_ty, .indirect);
    const tag_ptr_ty_id = try cg.ptrType(tag_ty_id, cg.storageClass(un_ptr_ty.ptrAddressSpace(zcu)));

    const union_ptr_id = try cg.resolve(bin_op.lhs);
    const new_tag_id = try cg.resolve(bin_op.rhs);

    if (!layout.has_payload) {
        try cg.store(tag_ty, union_ptr_id, new_tag_id, .{ .is_volatile = un_ptr_ty.isVolatilePtr(zcu) });
    } else {
        const ptr_id = try cg.accessChain(tag_ptr_ty_id, union_ptr_id, &.{layout.tag_index});
        try cg.store(tag_ty, ptr_id, new_tag_id, .{ .is_volatile = un_ptr_ty.isVolatilePtr(zcu) });
    }
}

fn airGetUnionTag(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const ty_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const un_ty = cg.typeOf(ty_op.operand);

    const zcu = cg.zcu;
    const layout = cg.unionLayout(un_ty);
    if (layout.tag_size == 0) return null;

    const union_handle = try cg.resolve(ty_op.operand);
    if (!layout.has_payload) return union_handle;

    const tag_ty = un_ty.unionTagTypeRuntime(zcu).?;
    return try cg.extractField(tag_ty, union_handle, layout.tag_index);
}

fn unionInit(
    cg: *CodeGen,
    ty: Type,
    active_field: u32,
    payload: ?Id,
) !Id {
    // To initialize a union, generate a temporary variable with the
    // union type, then get the field pointer and pointer-cast it to the
    // right type to store it. Finally load the entire union.

    // Note: The result here is not cached, because it generates runtime code.

    const pt = cg.pt;
    const zcu = cg.zcu;
    const ip = &zcu.intern_pool;
    const union_ty = zcu.typeToUnion(ty).?;
    const tag_ty: Type = .fromInterned(union_ty.enum_tag_type);

    const layout = cg.unionLayout(ty);
    const payload_ty: Type = .fromInterned(union_ty.field_types.get(ip)[active_field]);

    assert(union_ty.layout != .@"packed");

    const tag_int = if (layout.tag_size != 0) blk: {
        const tag_val = try pt.enumValueFieldIndex(tag_ty, active_field);
        const tag_int_val = tag_val.intFromEnum(zcu);
        break :blk tag_int_val.toUnsignedInt(zcu);
    } else 0;

    if (!layout.has_payload) {
        return try cg.constInt(tag_ty, tag_int);
    }

    const ty_id = try cg.resolveType(ty, .indirect);
    const tmp_id = try cg.alloc(ty_id, null);

    if (layout.tag_size != 0) {
        const tag_ty_id = try cg.resolveType(tag_ty, .indirect);
        const tag_ptr_ty_id = try cg.ptrType(tag_ty_id, .function);
        const ptr_id = try cg.accessChain(tag_ptr_ty_id, tmp_id, &.{@as(u32, @intCast(layout.tag_index))});
        const tag_id = try cg.constInt(tag_ty, tag_int);
        try cg.store(tag_ty, ptr_id, tag_id, .{});
    }

    if (payload_ty.hasRuntimeBits(zcu)) {
        const layout_payload_ty_id = try cg.resolveType(layout.payload_ty, .indirect);
        const pl_ptr_ty_id = try cg.ptrType(layout_payload_ty_id, .function);
        const pl_ptr_id = try cg.accessChain(pl_ptr_ty_id, tmp_id, &.{layout.payload_index});
        const active_pl_ptr_id = if (!layout.payload_ty.eql(payload_ty)) blk: {
            const payload_ty_id = try cg.resolveType(payload_ty, .indirect);
            const active_pl_ptr_ty_id = try cg.ptrType(payload_ty_id, .function);
            const active_pl_ptr_id = cg.allocId();
            try cg.body.emit(cg.gpa, .OpBitcast, .{
                .id_result_type = active_pl_ptr_ty_id,
                .id_result = active_pl_ptr_id,
                .operand = pl_ptr_id,
            });
            break :blk active_pl_ptr_id;
        } else pl_ptr_id;

        try cg.store(payload_ty, active_pl_ptr_id, payload.?, .{});
    } else {
        assert(payload == null);
    }

    // Just leave the padding fields uninitialized...
    // TODO: Or should we initialize them with undef explicitly?

    return try cg.load(ty, tmp_id, .{});
}

fn airUnionInit(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const zcu = cg.zcu;
    const ip = &zcu.intern_pool;
    const ty_pl = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const extra = cg.air.extraData(Air.UnionInit, ty_pl.payload).data;
    const ty = cg.typeOfIndex(inst);

    const union_obj = zcu.typeToUnion(ty).?;
    const field_ty: Type = .fromInterned(union_obj.field_types.get(ip)[extra.field_index]);
    const payload = if (field_ty.hasRuntimeBits(zcu))
        try cg.resolve(extra.init)
    else
        null;
    return try cg.unionInit(ty, extra.field_index, payload);
}

fn airStructFieldVal(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const pt = cg.pt;
    const zcu = cg.zcu;
    const ty_pl = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const struct_field = cg.air.extraData(Air.StructField, ty_pl.payload).data;

    const object_ty = cg.typeOf(struct_field.struct_operand);
    const object_id = try cg.resolve(struct_field.struct_operand);
    const field_index = struct_field.field_index;
    const field_ty = object_ty.fieldType(field_index, zcu);

    assert(field_ty.hasRuntimeBits(zcu));

    switch (object_ty.zigTypeTag(zcu)) {
        .@"struct" => switch (object_ty.containerLayout(zcu)) {
            .@"packed" => {
                const struct_ty = zcu.typeToPackedStruct(object_ty).?;
                const struct_backing_int_bits = cg.backingIntBits(@intCast(object_ty.bitSize(zcu))).@"0";
                const bit_offset = zcu.structPackedFieldBitOffset(struct_ty, field_index);
                // We use the same int type the packed struct is backed by, because even though it would
                // be valid SPIR-V to use an smaller type like u16, some implementations like PoCL will complain.
                const bit_offset_id = try cg.constInt(object_ty, bit_offset);
                const signedness = if (field_ty.isInt(zcu)) field_ty.intInfo(zcu).signedness else .unsigned;
                const field_bit_size: u16 = @intCast(field_ty.bitSize(zcu));
                const field_int_ty = try pt.intType(signedness, field_bit_size);
                const shift_lhs: Temporary = .{ .ty = object_ty, .value = .{ .singleton = object_id } };
                const shift = try cg.buildBinary(.OpShiftRightLogical, shift_lhs, .{ .ty = object_ty, .value = .{ .singleton = bit_offset_id } });
                const mask_id = try cg.constInt(object_ty, (@as(u64, 1) << @as(u6, @intCast(field_bit_size))) - 1);
                const masked = try cg.buildBinary(.OpBitwiseAnd, shift, .{ .ty = object_ty, .value = .{ .singleton = mask_id } });
                const result_id = blk: {
                    if (cg.backingIntBits(field_bit_size).@"0" == struct_backing_int_bits)
                        break :blk try cg.bitCast(field_int_ty, object_ty, try masked.materialize(cg));
                    const trunc = try cg.buildConvert(field_int_ty, masked);
                    break :blk try trunc.materialize(cg);
                };
                if (field_ty.ip_index == .bool_type) return try cg.convertToDirect(.bool, result_id);
                if (field_ty.isInt(zcu)) return result_id;
                return try cg.bitCast(field_ty, field_int_ty, result_id);
            },
            else => return try cg.extractField(field_ty, object_id, field_index),
        },
        .@"union" => switch (object_ty.containerLayout(zcu)) {
            .@"packed" => {
                const backing_int_ty = try pt.intType(.unsigned, @intCast(object_ty.bitSize(zcu)));
                const signedness = if (field_ty.isInt(zcu)) field_ty.intInfo(zcu).signedness else .unsigned;
                const field_bit_size: u16 = @intCast(field_ty.bitSize(zcu));
                const int_ty = try pt.intType(signedness, field_bit_size);
                const mask_id = try cg.constInt(backing_int_ty, (@as(u64, 1) << @as(u6, @intCast(field_bit_size))) - 1);
                const masked = try cg.buildBinary(
                    .OpBitwiseAnd,
                    .{ .ty = backing_int_ty, .value = .{ .singleton = object_id } },
                    .{ .ty = backing_int_ty, .value = .{ .singleton = mask_id } },
                );
                const result_id = blk: {
                    if (cg.backingIntBits(field_bit_size).@"0" == cg.backingIntBits(@intCast(backing_int_ty.bitSize(zcu))).@"0")
                        break :blk try cg.bitCast(int_ty, backing_int_ty, try masked.materialize(cg));
                    const trunc = try cg.buildConvert(int_ty, masked);
                    break :blk try trunc.materialize(cg);
                };
                if (field_ty.ip_index == .bool_type) return try cg.convertToDirect(.bool, result_id);
                if (field_ty.isInt(zcu)) return result_id;
                return try cg.bitCast(field_ty, int_ty, result_id);
            },
            else => {
                // Store, ptr-elem-ptr, pointer-cast, load
                const layout = cg.unionLayout(object_ty);
                assert(layout.has_payload);

                const object_ty_id = try cg.resolveType(object_ty, .indirect);
                const tmp_id = try cg.alloc(object_ty_id, null);
                try cg.store(object_ty, tmp_id, object_id, .{});

                const layout_payload_ty_id = try cg.resolveType(layout.payload_ty, .indirect);
                const pl_ptr_ty_id = try cg.ptrType(layout_payload_ty_id, .function);
                const pl_ptr_id = try cg.accessChain(pl_ptr_ty_id, tmp_id, &.{layout.payload_index});

                const field_ty_id = try cg.resolveType(field_ty, .indirect);
                const active_pl_ptr_ty_id = try cg.ptrType(field_ty_id, .function);
                const active_pl_ptr_id = cg.allocId();
                try cg.body.emit(cg.gpa, .OpBitcast, .{
                    .id_result_type = active_pl_ptr_ty_id,
                    .id_result = active_pl_ptr_id,
                    .operand = pl_ptr_id,
                });
                return try cg.load(field_ty, active_pl_ptr_id, .{});
            },
        },
        else => unreachable,
    }
}

fn airFieldParentPtr(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const zcu = cg.zcu;
    const target = zcu.getTarget();
    const ty_pl = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const extra = cg.air.extraData(Air.FieldParentPtr, ty_pl.payload).data;

    const parent_ptr_ty = ty_pl.ty.toType();
    const parent_ty = parent_ptr_ty.childType(zcu);
    const result_ty_id = try cg.resolveType(parent_ptr_ty, .indirect);

    const field_ptr = try cg.resolve(extra.field_ptr);
    const field_ptr_ty = cg.typeOf(extra.field_ptr);
    const field_ptr_int = try cg.intFromPtr(field_ptr);
    const field_offset = parent_ty.structFieldOffset(extra.field_index, zcu);

    const base_ptr_int = base_ptr_int: {
        if (field_offset == 0) break :base_ptr_int field_ptr_int;

        const field_offset_id = try cg.constInt(.usize, field_offset);
        const field_ptr_tmp: Temporary = .init(.usize, field_ptr_int);
        const field_offset_tmp: Temporary = .init(.usize, field_offset_id);
        const result = try cg.buildBinary(.OpISub, field_ptr_tmp, field_offset_tmp);
        break :base_ptr_int try result.materialize(cg);
    };

    if (target.os.tag != .opencl) {
        if (field_ptr_ty.ptrAddressSpace(zcu) != .physical_storage_buffer) {
            return cg.fail(
                "cannot cast integer to pointer with address space '{s}'",
                .{@tagName(field_ptr_ty.ptrAddressSpace(zcu))},
            );
        }
    }

    const base_ptr = cg.allocId();
    try cg.body.emit(cg.gpa, .OpConvertUToPtr, .{
        .id_result_type = result_ty_id,
        .id_result = base_ptr,
        .integer_value = base_ptr_int,
    });

    return base_ptr;
}

fn structFieldPtr(
    cg: *CodeGen,
    result_ptr_ty: Type,
    object_ptr_ty: Type,
    object_ptr: Id,
    field_index: u32,
) !Id {
    const result_ty_id = try cg.resolveType(result_ptr_ty, .direct);

    const zcu = cg.zcu;
    const object_ty = object_ptr_ty.childType(zcu);
    switch (object_ty.zigTypeTag(zcu)) {
        .pointer => {
            assert(object_ty.isSlice(zcu));
            return cg.accessChain(result_ty_id, object_ptr, &.{field_index});
        },
        .@"struct" => switch (object_ty.containerLayout(zcu)) {
            .@"packed" => {
                const byte_offset = codegen.fieldOffset(object_ptr_ty, result_ptr_ty, field_index, zcu);
                if (byte_offset == 0) return object_ptr;
                const usize_ty_id = try cg.resolveType(.usize, .direct);
                const base_int = cg.allocId();
                try cg.body.emit(cg.gpa, .OpConvertPtrToU, .{
                    .id_result_type = usize_ty_id,
                    .id_result = base_int,
                    .pointer = object_ptr,
                });
                const offset_id = try cg.constInt(.usize, byte_offset);
                const adjusted = try cg.buildBinary(.OpIAdd, .{ .ty = .usize, .value = .{ .singleton = base_int } }, .{ .ty = .usize, .value = .{ .singleton = offset_id } });
                const adjusted_id = try adjusted.materialize(cg);
                const result_id = cg.allocId();
                try cg.body.emit(cg.gpa, .OpConvertUToPtr, .{
                    .id_result_type = result_ty_id,
                    .id_result = result_id,
                    .integer_value = adjusted_id,
                });
                return result_id;
            },
            .auto, .@"extern" => {
                return try cg.accessChain(result_ty_id, object_ptr, &.{field_index});
            },
        },
        .@"union" => switch (object_ty.containerLayout(zcu)) {
            .@"packed" => return cg.todo("implement field access for packed unions", .{}),
            .auto, .@"extern" => {
                const layout = cg.unionLayout(object_ty);
                if (!layout.has_payload) {
                    // Asked to get a pointer to a zero-sized field. Just lower this
                    // to undefined, there is no reason to make it be a valid pointer.
                    return try cg.constUndef(result_ty_id);
                }

                const storage_class = cg.storageClass(object_ptr_ty.ptrAddressSpace(zcu));
                const layout_payload_ty_id = try cg.resolveType(layout.payload_ty, .indirect);
                const pl_ptr_ty_id = try cg.ptrType(layout_payload_ty_id, storage_class);
                const pl_ptr_id = blk: {
                    if (object_ty.containerLayout(zcu) == .@"packed") break :blk object_ptr;
                    break :blk try cg.accessChain(pl_ptr_ty_id, object_ptr, &.{layout.payload_index});
                };

                const active_pl_ptr_id = cg.allocId();
                try cg.body.emit(cg.gpa, .OpBitcast, .{
                    .id_result_type = result_ty_id,
                    .id_result = active_pl_ptr_id,
                    .operand = pl_ptr_id,
                });
                return active_pl_ptr_id;
            },
        },
        else => unreachable,
    }
}

fn airStructFieldPtr(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const ty_pl = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_pl;
    const struct_field = cg.air.extraData(Air.StructField, ty_pl.payload).data;
    const struct_ptr = try cg.resolve(struct_field.struct_operand);
    const struct_ptr_ty = cg.typeOf(struct_field.struct_operand);
    const result_ptr_ty = cg.typeOfIndex(inst);
    return try cg.structFieldPtr(result_ptr_ty, struct_ptr_ty, struct_ptr, struct_field.field_index);
}

fn airStructFieldPtrIndex(cg: *CodeGen, inst: Air.Inst.Index, field_index: u32) !?Id {
    const ty_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const struct_ptr = try cg.resolve(ty_op.operand);
    const struct_ptr_ty = cg.typeOf(ty_op.operand);
    const result_ptr_ty = cg.typeOfIndex(inst);
    return try cg.structFieldPtr(result_ptr_ty, struct_ptr_ty, struct_ptr, field_index);
}

fn alloc(cg: *CodeGen, ty_id: Id, initializer: ?Id) !Id {
    const ptr_ty_id = try cg.ptrType(ty_id, .function);
    const result_id = cg.allocId();
    try cg.prologue.emit(cg.gpa, .OpVariable, .{
        .id_result_type = ptr_ty_id,
        .id_result = result_id,
        .storage_class = .function,
        .initializer = initializer,
    });
    return result_id;
}

fn airAlloc(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const zcu = cg.zcu;
    const target = zcu.getTarget();
    const ptr_ty = cg.typeOfIndex(inst);
    const child_ty = ptr_ty.childType(zcu);

    switch (target.os.tag) {
        .vulkan, .opengl => {
            if (child_ty.zigTypeTag(zcu) == .pointer and !child_ty.isSlice(zcu)) {
                const as = child_ty.ptrAddressSpace(zcu);
                if (cg.storageClass(as) == .function) {
                    const result_id = cg.allocId();
                    try cg.tracked_allocas.put(cg.gpa, result_id, null);
                    return result_id;
                }
            }
        },
        else => {},
    }

    const child_ty_id = try cg.resolveType(child_ty, .indirect);
    const ptr_align = ptr_ty.ptrAlignment(zcu);
    const result_id = try cg.alloc(child_ty_id, null);
    if (ptr_align != child_ty.abiAlignment(zcu)) {
        if (target.os.tag != .opencl) return cg.fail("cannot apply alignment to variables", .{});
        try cg.decorate(result_id, .{
            .alignment = .{ .alignment = @intCast(ptr_align.toByteUnits().?) },
        });
    }
    return result_id;
}

fn airArg(cg: *CodeGen) Id {
    defer cg.next_arg_index += 1;
    return cg.args.items[cg.next_arg_index];
}

/// Given a slice of incoming block connections, returns the block-id of the next
/// block to jump to. This function emits instructions, so it should be emitted
/// inside the merge block of the block.
/// This function should only be called with structured control flow generation.
fn structuredNextBlock(cg: *CodeGen, incoming: []const Block.Incoming) !Id {
    const result_id = cg.allocId();
    const block_id_ty_id = try cg.resolveType(.u32, .direct);
    try cg.body.emitRaw(cg.gpa, .OpPhi, @intCast(2 + incoming.len * 2)); // result type + result + variable/parent...
    cg.body.writeOperand(Id, block_id_ty_id);
    cg.body.writeOperand(Id, result_id);

    for (incoming) |incoming_block| {
        cg.body.writeOperand(spec.PairIdRefIdRef, .{ incoming_block.next_block, incoming_block.src_label });
    }

    return result_id;
}

/// Jumps to the block with the target block-id. This function must only be called when
/// terminating a body, there should be no instructions after it.
/// This function should only be called with structured control flow generation.
fn structuredBreak(cg: *CodeGen, target_block: Id) !void {
    if (cg.block_terminated) return;

    const gpa = cg.gpa;
    const sblock = cg.block_stack.getLast().?;
    const merge_block = switch (sblock.*) {
        .selection => |*merge| blk: {
            const merge_label = cg.allocId();
            try merge.merge_stack.append(gpa, .{
                .incoming = .{
                    .src_label = cg.block_label,
                    .next_block = target_block,
                },
                .merge_block = merge_label,
            });
            break :blk merge_label;
        },
        // Loop blocks do not end in a break. Not through a direct break,
        // and also not through another instruction like cond_br or unreachable (these
        // situations are replaced by `cond_br` in sema, or there is a `block` instruction
        // placed around them).
        .loop => unreachable,
    };

    try cg.body.emit(gpa, .OpBranch, .{ .target_label = merge_block });
}

/// Generate a body in a way that exits the body using only structured constructs.
/// Returns the block-id of the next block to jump to. After this function, a jump
/// should still be emitted to the block that should follow this structured body.
/// This function should only be called with structured control flow generation.
fn genStructuredBody(
    cg: *CodeGen,
    /// This parameter defines the method that this structured body is exited with.
    block_merge_type: union(enum) {
        /// Using selection; early exits from this body are surrounded with
        /// if() statements.
        selection,
        /// Using loops; loops can be early exited by jumping to the merge block at
        /// any time.
        loop: struct {
            merge_label: Id,
            continue_label: Id,
        },
    },
    body: []const Air.Inst.Index,
) !Id {
    const gpa = cg.gpa;

    var sblock: Block = switch (block_merge_type) {
        .loop => |merge| .{ .loop = .{
            .merge_block = merge.merge_label,
        } },
        .selection => .{ .selection = .{} },
    };
    defer sblock.deinit(gpa);

    {
        try cg.block_stack.append(gpa, &sblock);
        defer _ = cg.block_stack.pop();

        try cg.genBody(body);
    }

    switch (sblock) {
        .selection => |merge| {
            // Now generate the merge block for all merges that
            // still need to be performed.
            const merge_stack = merge.merge_stack.items;

            // If no merges on the stack, this block didn't generate any jumps (all paths
            // ended with a return or an unreachable). In that case, we don't need to do
            // any merging.
            if (merge_stack.len == 0) {
                // We still need to return a value of a next block to jump to.
                // For example, if we have code like
                //  if (x) {
                //    if (y) return else return;
                //  } else {}
                // then we still need the outer to have an OpSelectionMerge and consequently
                // a phi node. In that case we can just return bogus, since we know that its
                // path will never be taken.

                // Make sure that we are still in a block when exiting the function.
                // TODO: Can we get rid of that?
                try cg.beginSpvBlock(cg.allocId());
                const block_id_ty_id = try cg.resolveType(.u32, .direct);
                return try cg.constUndef(block_id_ty_id);
            }

            // The top-most merge actually only has a single source, the
            // final jump of the block, or the merge block of a sub-block, cond_br,
            // or loop. Therefore we just need to generate a block with a jump to the
            // next merge block.
            try cg.beginSpvBlock(merge_stack[merge_stack.len - 1].merge_block);

            // Now generate a merge ladder for the remaining merges in the stack.
            var incoming: Block.Incoming = .{
                .src_label = cg.block_label,
                .next_block = merge_stack[merge_stack.len - 1].incoming.next_block,
            };
            var i = merge_stack.len - 1;
            while (i > 0) {
                i -= 1;
                const step = merge_stack[i];

                try cg.body.emit(gpa, .OpBranch, .{ .target_label = step.merge_block });
                try cg.beginSpvBlock(step.merge_block);
                const next_block = try cg.structuredNextBlock(&.{ incoming, step.incoming });
                incoming = .{
                    .src_label = step.merge_block,
                    .next_block = next_block,
                };
            }

            return incoming.next_block;
        },
        .loop => |merge| {
            // Close the loop by jumping to the continue label

            try cg.body.emit(gpa, .OpBranch, .{ .target_label = block_merge_type.loop.continue_label });
            // For blocks we must simple merge all the incoming blocks to get the next block.
            try cg.beginSpvBlock(merge.merge_block);
            return try cg.structuredNextBlock(merge.merges.items);
        },
    }
}

fn airBlock(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const block = cg.air.unwrapBlock(inst);
    return cg.lowerBlock(inst, block.body);
}

fn lowerBlock(cg: *CodeGen, inst: Air.Inst.Index, body: []const Air.Inst.Index) !?Id {
    // In AIR, a block doesn't really define an entry point like a block, but
    // more like a scope that breaks can jump out of and "return" a value from.
    // This cannot be directly modelled in SPIR-V, so in a block instruction,
    // we're going to split up the current block by first generating the code
    // of the block, then a label, and then generate the rest of the current
    // ir.Block in a different SPIR-V block.

    const gpa = cg.gpa;
    const zcu = cg.zcu;
    const ty = cg.typeOfIndex(inst);
    const have_block_result = ty.hasRuntimeBits(zcu);

    const maybe_block_result_var_id = if (have_block_result) blk: {
        const ty_id = try cg.resolveType(ty, .indirect);
        const block_result_var_id = try cg.alloc(ty_id, null);
        try cg.block_results.putNoClobber(gpa, inst, block_result_var_id);
        break :blk block_result_var_id;
    } else null;
    defer if (have_block_result) assert(cg.block_results.remove(inst));

    const next_block = try cg.genStructuredBody(.selection, body);

    // When encountering a block instruction, we are always at least in the function's scope,
    // so there always has to be another entry.
    assert(cg.block_stack.items.len > 0);

    // Check if the target of the branch was this current block.
    const this_block = try cg.constInt(.u32, @intFromEnum(inst));
    const jump_to_this_block_id = cg.allocId();
    const bool_ty_id = try cg.resolveType(.bool, .direct);
    try cg.body.emit(gpa, .OpIEqual, .{
        .id_result_type = bool_ty_id,
        .id_result = jump_to_this_block_id,
        .operand_1 = next_block,
        .operand_2 = this_block,
    });

    const sblock = cg.block_stack.getLast().?;

    if (ty.isNoReturn(zcu)) {
        // If this block is noreturn, this instruction is the last of a block,
        // and we must simply jump to the block's merge unconditionally.
        try cg.structuredBreak(next_block);
    } else {
        switch (sblock.*) {
            .selection => |*merge| {
                // To jump out of a selection block, push a new entry onto its merge stack and
                // generate a conditional branch to there and to the instructions following this block.
                const merge_label = cg.allocId();
                const then_label = cg.allocId();
                try cg.body.emit(gpa, .OpSelectionMerge, .{
                    .merge_block = merge_label,
                    .selection_control = .{},
                });
                try cg.body.emit(gpa, .OpBranchConditional, .{
                    .condition = jump_to_this_block_id,
                    .true_label = then_label,
                    .false_label = merge_label,
                });
                try merge.merge_stack.append(gpa, .{
                    .incoming = .{
                        .src_label = cg.block_label,
                        .next_block = next_block,
                    },
                    .merge_block = merge_label,
                });

                try cg.beginSpvBlock(then_label);
            },
            .loop => |*merge| {
                // To jump out of a loop block, generate a conditional that exits the block
                // to the loop merge if the target ID is not the one of this block.
                const continue_label = cg.allocId();
                try cg.body.emit(gpa, .OpBranchConditional, .{
                    .condition = jump_to_this_block_id,
                    .true_label = continue_label,
                    .false_label = merge.merge_block,
                });
                try merge.merges.append(gpa, .{
                    .src_label = cg.block_label,
                    .next_block = next_block,
                });
                try cg.beginSpvBlock(continue_label);
            },
        }
    }

    if (maybe_block_result_var_id) |block_result_var_id| {
        return try cg.load(ty, block_result_var_id, .{});
    }

    return null;
}

fn airBr(cg: *CodeGen, inst: Air.Inst.Index) !void {
    const zcu = cg.zcu;
    const br = cg.air.instructions.items(.data)[@intFromEnum(inst)].br;
    const operand_ty = cg.typeOf(br.operand);

    if (operand_ty.hasRuntimeBits(zcu)) {
        const operand_id = try cg.resolve(br.operand);
        const block_result_var_id = cg.block_results.get(br.block_inst).?;
        try cg.store(operand_ty, block_result_var_id, operand_id, .{});
    }

    const next_block = try cg.constInt(.u32, @intFromEnum(br.block_inst));
    try cg.structuredBreak(next_block);
}

fn airCondBr(cg: *CodeGen, inst: Air.Inst.Index) !void {
    const gpa = cg.gpa;
    const cond_br = cg.air.unwrapCondBr(inst);
    const then_body = cond_br.then_body;
    const else_body = cond_br.else_body;
    const condition_id = try cg.resolve(cond_br.condition);

    const then_label = cg.allocId();
    const else_label = cg.allocId();

    const merge_label = cg.allocId();

    try cg.body.emit(gpa, .OpSelectionMerge, .{
        .merge_block = merge_label,
        .selection_control = .{},
    });
    try cg.body.emit(gpa, .OpBranchConditional, .{
        .condition = condition_id,
        .true_label = then_label,
        .false_label = else_label,
    });

    try cg.beginSpvBlock(then_label);
    const then_next = try cg.genStructuredBody(.selection, then_body);
    const then_incoming: Block.Incoming = .{
        .src_label = cg.block_label,
        .next_block = then_next,
    };

    if (!cg.block_terminated) {
        try cg.body.emit(gpa, .OpBranch, .{ .target_label = merge_label });
    }

    try cg.beginSpvBlock(else_label);
    const else_next = try cg.genStructuredBody(.selection, else_body);
    const else_incoming: Block.Incoming = .{
        .src_label = cg.block_label,
        .next_block = else_next,
    };

    if (!cg.block_terminated) {
        try cg.body.emit(gpa, .OpBranch, .{ .target_label = merge_label });
    }

    try cg.beginSpvBlock(merge_label);
    const next_block = try cg.structuredNextBlock(&.{ then_incoming, else_incoming });

    try cg.structuredBreak(next_block);
}

fn airLoop(cg: *CodeGen, inst: Air.Inst.Index) !void {
    const gpa = cg.gpa;
    const block = cg.air.unwrapBlock(inst);

    const body_label = cg.allocId();

    const header_label = cg.allocId();
    const merge_label = cg.allocId();
    const continue_label = cg.allocId();

    // The back-edge must point to the loop header, so generate a separate block for the
    // loop header so that we don't accidentally include some instructions from there
    // in the loop.

    try cg.body.emit(gpa, .OpBranch, .{ .target_label = header_label });
    try cg.beginSpvBlock(header_label);

    // Emit loop header and jump to loop body
    try cg.body.emit(gpa, .OpLoopMerge, .{
        .merge_block = merge_label,
        .continue_target = continue_label,
        .loop_control = .{},
    });

    try cg.body.emit(gpa, .OpBranch, .{ .target_label = body_label });

    try cg.beginSpvBlock(body_label);

    const next_block = try cg.genStructuredBody(.{ .loop = .{
        .merge_label = merge_label,
        .continue_label = continue_label,
    } }, block.body);
    try cg.structuredBreak(next_block);

    try cg.beginSpvBlock(continue_label);

    try cg.body.emit(gpa, .OpBranch, .{ .target_label = header_label });
}

fn airLoad(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const zcu = cg.zcu;
    const pt = cg.pt;
    const ty_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const ptr_ty = cg.typeOf(ty_op.operand);
    const ptr_info = ptr_ty.ptrInfo(zcu);
    const elem_ty = cg.typeOfIndex(inst);
    const ptr = try cg.resolvePtr(ty_op.operand);
    assert(ptr_info.child == elem_ty.toIntern());

    const operand_ptr_id = switch (ptr) {
        .tracked => |t| return t.slot.*.?,
        .id => |id| id,
    };

    if (ptr_info.packed_offset.host_size != 0 and
        ptr_info.flags.vector_index == .none)
    {
        const host_bits: u16 = ptr_info.packed_offset.host_size * 8;
        const elem_bit_size: u16 = @intCast(elem_ty.bitSize(zcu));
        const host_int_ty = try pt.intType(.unsigned, host_bits);
        const host_val = try cg.load(host_int_ty, operand_ptr_id, .{ .is_volatile = ptr_info.flags.is_volatile });
        const signedness: Signedness = if (elem_ty.isInt(zcu)) elem_ty.intInfo(zcu).signedness else .unsigned;
        const field_int_ty = try pt.intType(signedness, elem_bit_size);
        const narrowed = if (ptr_info.packed_offset.bit_offset > 0) blk: {
            const bit_offset_id = try cg.constInt(host_int_ty, ptr_info.packed_offset.bit_offset);
            const shifted = try cg.buildBinary(.OpShiftRightLogical, .{ .ty = host_int_ty, .value = .{ .singleton = host_val } }, .{ .ty = host_int_ty, .value = .{ .singleton = bit_offset_id } });
            break :blk try shifted.materialize(cg);
        } else host_val;
        const result_id = blk: {
            if (cg.backingIntBits(elem_bit_size).@"0" == cg.backingIntBits(host_bits).@"0")
                break :blk try cg.bitCast(field_int_ty, host_int_ty, narrowed);
            const trunc = try cg.buildConvert(field_int_ty, .{ .ty = host_int_ty, .value = .{ .singleton = narrowed } });
            break :blk try trunc.materialize(cg);
        };
        if (elem_ty.ip_index == .bool_type) return try cg.convertToDirect(.bool, result_id);
        if (elem_ty.isInt(zcu)) return result_id;
        return try cg.bitCast(elem_ty, field_int_ty, result_id);
    }

    const ptr_id = switch (ptr_info.flags.vector_index) {
        .none => operand_ptr_id,
        else => |index| ptr_id: {
            const elem_ptr_ty_id = try cg.ptrType(
                try cg.resolveType(elem_ty, .indirect),
                cg.storageClass(ptr_info.flags.address_space),
            );
            break :ptr_id try cg.accessChain(elem_ptr_ty_id, operand_ptr_id, &.{@intFromEnum(index)});
        },
    };
    return try cg.load(elem_ty, ptr_id, .{ .is_volatile = ptr_info.flags.is_volatile });
}

fn airStore(cg: *CodeGen, inst: Air.Inst.Index) !void {
    const zcu = cg.zcu;
    const pt = cg.pt;
    const bin_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].bin_op;
    const ptr_ty = cg.typeOf(bin_op.lhs);
    const ptr_info = ptr_ty.ptrInfo(zcu);
    const elem_ty: Type = .fromInterned(ptr_info.child);
    const value_id = try cg.resolve(bin_op.rhs);
    const operand_ptr_id = switch (try cg.resolvePtr(bin_op.lhs)) {
        .tracked => |t| {
            t.slot.* = value_id;
            return;
        },
        .id => |id| id,
    };

    if (ptr_info.packed_offset.host_size != 0 and
        ptr_info.flags.vector_index == .none)
    {
        const host_bits: u16 = ptr_info.packed_offset.host_size * 8;
        const host_int_ty = try pt.intType(.unsigned, host_bits);
        const host_val = try cg.load(host_int_ty, operand_ptr_id, .{ .is_volatile = ptr_info.flags.is_volatile });
        const elem_bit_size: u16 = @intCast(elem_ty.bitSize(zcu));
        const signedness: Signedness = if (elem_ty.isInt(zcu)) elem_ty.intInfo(zcu).signedness else .unsigned;
        const field_int_ty = try pt.intType(signedness, elem_bit_size);

        var value_as_int: Id = undefined;
        if (elem_ty.ip_index == .bool_type) {
            value_as_int = try cg.convertToIndirect(.bool, value_id);
            value_as_int = try cg.bitCast(field_int_ty, .u1, value_as_int);
        } else if (elem_ty.isInt(zcu)) {
            value_as_int = value_id;
        } else {
            value_as_int = try cg.bitCast(field_int_ty, elem_ty, value_id);
        }

        const extended = blk: {
            if (cg.backingIntBits(elem_bit_size).@"0" == cg.backingIntBits(host_bits).@"0")
                break :blk try cg.bitCast(host_int_ty, field_int_ty, value_as_int);
            const conv = try cg.buildConvert(host_int_ty, .{ .ty = field_int_ty, .value = .{ .singleton = value_as_int } });
            break :blk try conv.materialize(cg);
        };

        const bit_offset = ptr_info.packed_offset.bit_offset;
        const field_mask = (@as(u64, 1) << @as(u6, @intCast(elem_bit_size))) - 1;
        const host_mask = if (host_bits == 64) @as(u64, std.math.maxInt(u64)) else (@as(u64, 1) << @as(u6, @intCast(host_bits))) - 1;
        const clear_mask = ~(field_mask << @as(u6, @intCast(bit_offset))) & host_mask;
        const clear_mask_id = try cg.constInt(host_int_ty, clear_mask);
        const cleared = try cg.buildBinary(.OpBitwiseAnd, .{ .ty = host_int_ty, .value = .{ .singleton = host_val } }, .{ .ty = host_int_ty, .value = .{ .singleton = clear_mask_id } });
        const bit_offset_id = try cg.constInt(host_int_ty, bit_offset);
        const shifted_val = try cg.buildBinary(.OpShiftLeftLogical, .{ .ty = host_int_ty, .value = .{ .singleton = extended } }, .{ .ty = host_int_ty, .value = .{ .singleton = bit_offset_id } });
        const combined = try cg.buildBinary(.OpBitwiseOr, cleared, shifted_val);
        const combined_id = try combined.materialize(cg);

        try cg.store(host_int_ty, operand_ptr_id, combined_id, .{ .is_volatile = ptr_info.flags.is_volatile });
        return;
    }

    const ptr_id = switch (ptr_info.flags.vector_index) {
        .none => operand_ptr_id,
        else => |index| ptr_id: {
            const elem_ptr_ty_id = try cg.ptrType(
                try cg.resolveType(elem_ty, .indirect),
                cg.storageClass(ptr_info.flags.address_space),
            );
            break :ptr_id try cg.accessChain(elem_ptr_ty_id, operand_ptr_id, &.{@intFromEnum(index)});
        },
    };

    try cg.store(elem_ty, ptr_id, value_id, .{ .is_volatile = ptr_info.flags.is_volatile });
}

fn airRet(cg: *CodeGen, inst: Air.Inst.Index) !void {
    const gpa = cg.gpa;
    const zcu = cg.zcu;
    const operand = cg.air.instructions.items(.data)[@intFromEnum(inst)].un_op;
    const ret_ty = cg.typeOf(operand);
    if (!ret_ty.hasRuntimeBits(zcu)) {
        const fn_info = zcu.typeToFunc(zcu.navValue(cg.owner_nav).typeOf(zcu)).?;
        if (Type.fromInterned(fn_info.return_type).isError(zcu)) {
            // Functions with an empty error set are emitted with an error code
            // return type and return zero so they can be function pointers coerced
            // to functions that return anyerror.
            const no_err_id = try cg.constInt(.anyerror, 0);
            return try cg.body.emit(gpa, .OpReturnValue, .{ .value = no_err_id });
        } else {
            return try cg.body.emit(gpa, .OpReturn, {});
        }
    }

    const operand_id = try cg.resolve(operand);
    try cg.body.emit(gpa, .OpReturnValue, .{ .value = operand_id });
}

fn airRetLoad(cg: *CodeGen, inst: Air.Inst.Index) !void {
    const gpa = cg.gpa;
    const zcu = cg.zcu;
    const un_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].un_op;
    const ptr_ty = cg.typeOf(un_op);
    const ret_ty = ptr_ty.childType(zcu);

    if (!ret_ty.hasRuntimeBits(zcu)) {
        const fn_info = zcu.typeToFunc(zcu.navValue(cg.owner_nav).typeOf(zcu)).?;
        if (Type.fromInterned(fn_info.return_type).isError(zcu)) {
            // Functions with an empty error set are emitted with an error code
            // return type and return zero so they can be function pointers coerced
            // to functions that return anyerror.
            const no_err_id = try cg.constInt(.anyerror, 0);
            return try cg.body.emit(gpa, .OpReturnValue, .{ .value = no_err_id });
        } else {
            return try cg.body.emit(gpa, .OpReturn, {});
        }
    }

    const value = switch (try cg.resolvePtr(un_op)) {
        .tracked => |t| t.slot.*.?,
        .id => |ptr| try cg.load(ret_ty, ptr, .{ .is_volatile = ptr_ty.isVolatilePtr(zcu) }),
    };
    try cg.body.emit(gpa, .OpReturnValue, .{
        .value = value,
    });
}

fn airTry(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const gpa = cg.gpa;
    const zcu = cg.zcu;
    const unwrapped_try = cg.air.unwrapTry(inst);
    const body = unwrapped_try.else_body;

    const err_union_id = try cg.resolve(unwrapped_try.error_union);
    const err_union_ty = cg.air.typeOf(unwrapped_try.error_union, &zcu.intern_pool);
    const payload_ty = cg.typeOfIndex(inst);

    const bool_ty_id = try cg.resolveType(.bool, .direct);

    const eu_layout = cg.errorUnionLayout(payload_ty);

    if (!err_union_ty.errorUnionSet(zcu).errorSetIsEmpty(zcu)) {
        const err_id = if (eu_layout.payload_has_bits)
            try cg.extractField(.anyerror, err_union_id, eu_layout.errorFieldIndex())
        else
            err_union_id;

        const zero_id = try cg.constInt(.anyerror, 0);
        const is_err_id = cg.allocId();
        try cg.body.emit(gpa, .OpINotEqual, .{
            .id_result_type = bool_ty_id,
            .id_result = is_err_id,
            .operand_1 = err_id,
            .operand_2 = zero_id,
        });

        // When there is an error, we must evaluate `body`. Otherwise we must continue
        // with the current body.
        // Just generate a new block here, then generate a new block inline for the remainder of the body.

        const err_block = cg.allocId();
        const ok_block = cg.allocId();

        // According to AIR documentation, this block is guaranteed
        // to not break and end in a return instruction. Thus,
        // we can just naively use the ok block as the merge block here.
        try cg.body.emit(gpa, .OpSelectionMerge, .{
            .merge_block = ok_block,
            .selection_control = .{},
        });

        try cg.body.emit(gpa, .OpBranchConditional, .{
            .condition = is_err_id,
            .true_label = err_block,
            .false_label = ok_block,
        });

        try cg.beginSpvBlock(err_block);
        try cg.genBody(body);

        try cg.beginSpvBlock(ok_block);
    }

    if (!eu_layout.payload_has_bits) {
        return null;
    }

    // Now just extract the payload, if required.
    return try cg.extractField(payload_ty, err_union_id, eu_layout.payloadFieldIndex());
}

fn airErrUnionErr(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const zcu = cg.zcu;
    const ty_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand_id = try cg.resolve(ty_op.operand);
    const err_union_ty = cg.typeOf(ty_op.operand);
    const err_ty_id = try cg.resolveType(.anyerror, .direct);

    if (err_union_ty.errorUnionSet(zcu).errorSetIsEmpty(zcu)) {
        // No error possible, so just return undefined.
        return try cg.constUndef(err_ty_id);
    }

    const payload_ty = err_union_ty.errorUnionPayload(zcu);
    const eu_layout = cg.errorUnionLayout(payload_ty);

    if (!eu_layout.payload_has_bits) {
        // If no payload, error union is represented by error set.
        return operand_id;
    }

    return try cg.extractField(.anyerror, operand_id, eu_layout.errorFieldIndex());
}

fn airErrUnionPayload(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const ty_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand_id = try cg.resolve(ty_op.operand);
    const payload_ty = cg.typeOfIndex(inst);
    const eu_layout = cg.errorUnionLayout(payload_ty);

    if (!eu_layout.payload_has_bits) {
        return null; // No error possible.
    }

    return try cg.extractField(payload_ty, operand_id, eu_layout.payloadFieldIndex());
}

fn airWrapErrUnionErr(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const zcu = cg.zcu;
    const ty_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const err_union_ty = cg.typeOfIndex(inst);
    const payload_ty = err_union_ty.errorUnionPayload(zcu);
    const operand_id = try cg.resolve(ty_op.operand);
    const eu_layout = cg.errorUnionLayout(payload_ty);

    if (!eu_layout.payload_has_bits) {
        return operand_id;
    }

    const payload_ty_id = try cg.resolveType(payload_ty, .indirect);

    var members: [2]Id = undefined;
    members[eu_layout.errorFieldIndex()] = operand_id;
    members[eu_layout.payloadFieldIndex()] = try cg.constUndef(payload_ty_id);

    var types: [2]Type = undefined;
    types[eu_layout.errorFieldIndex()] = .anyerror;
    types[eu_layout.payloadFieldIndex()] = payload_ty;

    const err_union_ty_id = try cg.resolveType(err_union_ty, .direct);
    return try cg.constructComposite(err_union_ty_id, &members);
}

fn airWrapErrUnionPayload(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const ty_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const err_union_ty = cg.typeOfIndex(inst);
    const operand_id = try cg.resolve(ty_op.operand);
    const payload_ty = cg.typeOf(ty_op.operand);
    const eu_layout = cg.errorUnionLayout(payload_ty);

    if (!eu_layout.payload_has_bits) {
        return try cg.constInt(.anyerror, 0);
    }

    var members: [2]Id = undefined;
    members[eu_layout.errorFieldIndex()] = try cg.constInt(.anyerror, 0);
    members[eu_layout.payloadFieldIndex()] = try cg.convertToIndirect(payload_ty, operand_id);

    var types: [2]Type = undefined;
    types[eu_layout.errorFieldIndex()] = .anyerror;
    types[eu_layout.payloadFieldIndex()] = payload_ty;

    const err_union_ty_id = try cg.resolveType(err_union_ty, .direct);
    return try cg.constructComposite(err_union_ty_id, &members);
}

fn airIsNull(cg: *CodeGen, inst: Air.Inst.Index, is_pointer: bool, pred: enum { is_null, is_non_null }) !?Id {
    const zcu = cg.zcu;
    const un_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].un_op;
    const operand_id = try cg.resolve(un_op);
    const operand_ty = cg.typeOf(un_op);
    const optional_ty = if (is_pointer) operand_ty.childType(zcu) else operand_ty;
    const payload_ty = optional_ty.optionalChild(zcu);

    const bool_ty_id = try cg.resolveType(.bool, .direct);

    if (optional_ty.optionalReprIsPayload(zcu)) {
        // Pointer payload represents nullability: pointer or slice.
        const loaded_id = if (is_pointer)
            try cg.load(optional_ty, operand_id, .{})
        else
            operand_id;

        const ptr_ty = if (payload_ty.isSlice(zcu))
            payload_ty.slicePtrFieldType(zcu)
        else
            payload_ty;

        const ptr_id = if (payload_ty.isSlice(zcu))
            try cg.extractField(ptr_ty, loaded_id, 0)
        else
            loaded_id;

        const ptr_ty_id = try cg.resolveType(ptr_ty, .direct);
        const null_id = try cg.constNull(ptr_ty_id);
        const null_tmp: Temporary = .init(ptr_ty, null_id);
        const ptr: Temporary = .init(ptr_ty, ptr_id);

        const op: std.math.CompareOperator = switch (pred) {
            .is_null => .eq,
            .is_non_null => .neq,
        };
        const result = try cg.cmp(op, ptr, null_tmp);
        return try result.materialize(cg);
    }

    const is_non_null_id = blk: {
        if (is_pointer) {
            if (payload_ty.hasRuntimeBits(zcu)) {
                const storage_class = cg.storageClass(operand_ty.ptrAddressSpace(zcu));
                const bool_indirect_ty_id = try cg.resolveType(.bool, .indirect);
                const bool_ptr_ty_id = try cg.ptrType(bool_indirect_ty_id, storage_class);
                const tag_ptr_id = try cg.accessChain(bool_ptr_ty_id, operand_id, &.{1});
                break :blk try cg.load(.bool, tag_ptr_id, .{});
            }

            break :blk try cg.load(.bool, operand_id, .{});
        }

        break :blk if (payload_ty.hasRuntimeBits(zcu))
            try cg.extractField(.bool, operand_id, 1)
        else
            // Optional representation is bool indicating whether the optional is set
            // Optionals with no payload are represented as an (indirect) bool, so convert
            // it back to the direct bool here.
            try cg.convertToDirect(.bool, operand_id);
    };

    return switch (pred) {
        .is_null => blk: {
            // Invert condition
            const result_id = cg.allocId();
            try cg.body.emit(cg.gpa, .OpLogicalNot, .{
                .id_result_type = bool_ty_id,
                .id_result = result_id,
                .operand = is_non_null_id,
            });
            break :blk result_id;
        },
        .is_non_null => is_non_null_id,
    };
}

fn airIsErr(cg: *CodeGen, inst: Air.Inst.Index, pred: enum { is_err, is_non_err }) !?Id {
    const zcu = cg.zcu;
    const un_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].un_op;
    const operand_id = try cg.resolve(un_op);
    const err_union_ty = cg.typeOf(un_op);

    if (err_union_ty.errorUnionSet(zcu).errorSetIsEmpty(zcu)) {
        return try cg.constBool(pred == .is_non_err, .direct);
    }

    const payload_ty = err_union_ty.errorUnionPayload(zcu);
    const eu_layout = cg.errorUnionLayout(payload_ty);
    const bool_ty_id = try cg.resolveType(.bool, .direct);

    const error_id = if (!eu_layout.payload_has_bits)
        operand_id
    else
        try cg.extractField(.anyerror, operand_id, eu_layout.errorFieldIndex());

    const result_id = cg.allocId();
    switch (pred) {
        inline else => |pred_ct| try cg.body.emit(
            cg.gpa,
            switch (pred_ct) {
                .is_err => .OpINotEqual,
                .is_non_err => .OpIEqual,
            },
            .{
                .id_result_type = bool_ty_id,
                .id_result = result_id,
                .operand_1 = error_id,
                .operand_2 = try cg.constInt(.anyerror, 0),
            },
        ),
    }
    return result_id;
}

fn airUnwrapOptional(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const zcu = cg.zcu;
    const ty_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand_id = try cg.resolve(ty_op.operand);
    const optional_ty = cg.typeOf(ty_op.operand);
    const payload_ty = cg.typeOfIndex(inst);

    if (!payload_ty.hasRuntimeBits(zcu)) return null;

    if (optional_ty.optionalReprIsPayload(zcu)) {
        return operand_id;
    }

    return try cg.extractField(payload_ty, operand_id, 0);
}

fn airUnwrapOptionalPtr(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const zcu = cg.zcu;
    const ty_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const operand_id = try cg.resolve(ty_op.operand);
    const operand_ty = cg.typeOf(ty_op.operand);
    const optional_ty = operand_ty.childType(zcu);
    const payload_ty = optional_ty.optionalChild(zcu);
    const result_ty = cg.typeOfIndex(inst);
    const result_ty_id = try cg.resolveType(result_ty, .direct);

    if (!payload_ty.hasRuntimeBits(zcu)) {
        // There is no payload, but we still need to return a valid pointer.
        // We can just return anything here, so just return a pointer to the operand.
        return try cg.bitCast(result_ty, operand_ty, operand_id);
    }

    if (optional_ty.optionalReprIsPayload(zcu)) {
        // They are the same value.
        return try cg.bitCast(result_ty, operand_ty, operand_id);
    }

    return try cg.accessChain(result_ty_id, operand_id, &.{0});
}

fn airWrapOptional(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const zcu = cg.zcu;
    const ty_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].ty_op;
    const payload_ty = cg.typeOf(ty_op.operand);

    assert(payload_ty.hasRuntimeBits(zcu));

    const operand_id = try cg.resolve(ty_op.operand);

    const optional_ty = cg.typeOfIndex(inst);
    if (optional_ty.optionalReprIsPayload(zcu)) {
        return operand_id;
    }

    const payload_id = try cg.convertToIndirect(payload_ty, operand_id);
    const members = [_]Id{ payload_id, try cg.constBool(true, .indirect) };
    const optional_ty_id = try cg.resolveType(optional_ty, .direct);
    return try cg.constructComposite(optional_ty_id, &members);
}

fn airSwitchBr(cg: *CodeGen, inst: Air.Inst.Index) !void {
    const gpa = cg.gpa;
    const zcu = cg.zcu;
    const target = cg.zcu.getTarget();
    const switch_br = cg.air.unwrapSwitch(inst);
    const cond_ty = cg.typeOf(switch_br.operand);
    const cond = try cg.resolve(switch_br.operand);
    var cond_indirect = try cg.convertToIndirect(cond_ty, cond);

    const cond_words: u32 = switch (cond_ty.zigTypeTag(zcu)) {
        .bool, .error_set => 1,
        .int => blk: {
            const bits = cond_ty.intInfo(zcu).bits;
            const backing_bits, const big_int = cg.backingIntBits(bits);
            if (big_int) return cg.todo("implement composite int switch", .{});
            break :blk if (backing_bits <= 32) 1 else 2;
        },
        .@"enum" => blk: {
            const int_ty = cond_ty.intTagType(zcu);
            const int_info = int_ty.intInfo(zcu);
            const backing_bits, const big_int = cg.backingIntBits(int_info.bits);
            if (big_int) return cg.todo("implement composite int switch", .{});
            break :blk if (backing_bits <= 32) 1 else 2;
        },
        .pointer => blk: {
            cond_indirect = try cg.intFromPtr(cond_indirect);
            break :blk target.ptrBitWidth() / 32;
        },
        // TODO: Figure out which types apply here, and work around them as we can only do integers.
        else => return cg.todo("implement switch for type {s}", .{@tagName(cond_ty.zigTypeTag(zcu))}),
    };

    const num_cases = switch_br.cases_len;

    // compute the total number of scalar arms and find the last range case
    var num_conditions: u32 = 0;
    var last_range_case: ?u32 = null;
    {
        var it = switch_br.iterateCases();
        while (it.next()) |case| {
            if (case.ranges.len > 0) {
                last_range_case = case.idx;
            } else {
                num_conditions += @intCast(case.items.len);
            }
        }
    }

    // First, pre-allocate the labels for the cases.
    const case_labels = cg.allocIds(num_cases);
    // We always need the default case - if zig has none, we will generate unreachable there.
    const default_label = cg.allocId();
    const switch_default = if (last_range_case != null) cg.allocId() else default_label;

    const merge_label = cg.allocId();

    try cg.body.emit(gpa, .OpSelectionMerge, .{
        .merge_block = merge_label,
        .selection_control = .{},
    });

    // Emit the instruction before generating the blocks.
    try cg.body.emitRaw(gpa, .OpSwitch, 2 + (cond_words + 1) * num_conditions);
    cg.body.writeOperand(Id, cond_indirect);
    cg.body.writeOperand(Id, switch_default);

    // Emit the non-range cases into the OpSwitch.
    // Cases with ranges are handled by the conditional chain below.
    {
        var it = switch_br.iterateCases();
        while (it.next()) |case| {
            if (case.ranges.len > 0) continue;
            const label = case_labels.at(case.idx);

            for (case.items) |item| {
                const value: Value = .fromInterned(item.toInterned().?);
                const int_val: u64 = switch (cond_ty.zigTypeTag(zcu)) {
                    .bool, .int => if (cond_ty.isSignedInt(zcu)) @bitCast(value.toSignedInt(zcu)) else value.toUnsignedInt(zcu),
                    .@"enum" => value.intFromEnum(zcu).toUnsignedInt(zcu),
                    .error_set => value.getErrorInt(zcu),
                    .pointer => value.toUnsignedInt(zcu),
                    else => unreachable,
                };
                const int_lit: spec.LiteralContextDependentNumber = switch (cond_words) {
                    1 => .{ .uint32 = @intCast(int_val) },
                    2 => .{ .uint64 = int_val },
                    else => unreachable,
                };
                cg.body.writeOperand(spec.LiteralContextDependentNumber, int_lit);
                cg.body.writeOperand(Id, label);
            }
        }
    }

    var incoming_structured_blocks: std.ArrayList(Block.Incoming) = .empty;
    defer incoming_structured_blocks.deinit(gpa);
    try incoming_structured_blocks.ensureUnusedCapacity(gpa, num_cases + 1);

    // emit the range-checking chain as nested if-else inside the switch's default branch.
    // each range case becomes:
    // - check condition,
    // - if true emit case body and branch to merge,
    // - else continue to next check or default
    if (last_range_case != null) {
        const cond_tmp: Temporary = .init(cond_ty, cond);
        const bool_ty_id = try cg.resolveType(.bool, .direct);

        try cg.beginSpvBlock(switch_default);

        var it_range = switch_br.iterateCases();
        while (it_range.next()) |case| {
            if (case.ranges.len == 0) continue;

            var case_cond: ?Id = null;

            for (case.items) |item| {
                const item_tmp: Temporary = try cg.temporary(item);
                const eq = try (try cg.cmp(.eq, cond_tmp, item_tmp)).materialize(cg);
                case_cond = if (case_cond) |prev| blk: {
                    const combined = cg.allocId();
                    try cg.body.emit(gpa, .OpLogicalOr, .{
                        .id_result_type = bool_ty_id,
                        .id_result = combined,
                        .operand_1 = prev,
                        .operand_2 = eq,
                    });
                    break :blk combined;
                } else eq;
            }

            for (case.ranges) |range| {
                const lo_tmp: Temporary = try cg.temporary(range[0]);
                const hi_tmp: Temporary = try cg.temporary(range[1]);
                const ge = try (try cg.cmp(.gte, cond_tmp, lo_tmp)).materialize(cg);
                const le = try (try cg.cmp(.lte, cond_tmp, hi_tmp)).materialize(cg);
                const in_range = cg.allocId();
                try cg.body.emit(gpa, .OpLogicalAnd, .{
                    .id_result_type = bool_ty_id,
                    .id_result = in_range,
                    .operand_1 = ge,
                    .operand_2 = le,
                });
                case_cond = if (case_cond) |prev| blk: {
                    const combined = cg.allocId();
                    try cg.body.emit(gpa, .OpLogicalOr, .{
                        .id_result_type = bool_ty_id,
                        .id_result = combined,
                        .operand_1 = prev,
                        .operand_2 = in_range,
                    });
                    break :blk combined;
                } else in_range;
            }

            const case_label = case_labels.at(case.idx);
            const is_last = case.idx == last_range_case.?;
            const next_check = if (is_last) default_label else cg.allocId();

            try cg.body.emit(gpa, .OpSelectionMerge, .{
                .merge_block = next_check,
                .selection_control = .{},
            });

            try cg.body.emit(gpa, .OpBranchConditional, .{
                .condition = case_cond.?,
                .true_label = case_label,
                .false_label = next_check,
            });

            if (!is_last) {
                try cg.beginSpvBlock(next_check);
            }
        }
    }

    // emit bodies
    var it = switch_br.iterateCases();
    while (it.next()) |case| {
        const label = case_labels.at(case.idx);

        try cg.beginSpvBlock(label);

        const next_block = try cg.genStructuredBody(.selection, case.body);
        incoming_structured_blocks.appendAssumeCapacity(.{
            .src_label = cg.block_label,
            .next_block = next_block,
        });

        try cg.body.emit(gpa, .OpBranch, .{ .target_label = merge_label });
    }

    const else_body = blk: {
        var it_else = switch_br.iterateCases();
        while (it_else.next()) |_| {}
        break :blk it_else.elseBody();
    };
    try cg.beginSpvBlock(default_label);
    if (else_body.len != 0) {
        const next_block = try cg.genStructuredBody(.selection, else_body);
        incoming_structured_blocks.appendAssumeCapacity(.{
            .src_label = cg.block_label,
            .next_block = next_block,
        });

        try cg.body.emit(gpa, .OpBranch, .{ .target_label = merge_label });
    } else {
        try cg.body.emit(gpa, .OpUnreachable, {});
    }

    try cg.beginSpvBlock(merge_label);
    const next_block = try cg.structuredNextBlock(incoming_structured_blocks.items);
    try cg.structuredBreak(next_block);
}

fn airLoopSwitchBr(cg: *CodeGen, inst: Air.Inst.Index) !void {
    const gpa = cg.gpa;
    const zcu = cg.zcu;
    const target = cg.zcu.getTarget();
    const switch_br = cg.air.unwrapSwitch(inst);
    const cond_ty = cg.typeOf(switch_br.operand);
    const initial_cond = try cg.resolve(switch_br.operand);
    var initial_cond_indirect = try cg.convertToIndirect(cond_ty, initial_cond);

    const cond_words: u32 = switch (cond_ty.zigTypeTag(zcu)) {
        .bool, .error_set => 1,
        .int => blk: {
            const bits = cond_ty.intInfo(zcu).bits;
            const backing_bits, const big_int = cg.backingIntBits(bits);
            if (big_int) return cg.todo("implement composite int loop switch", .{});
            break :blk if (backing_bits <= 32) 1 else 2;
        },
        .@"enum" => blk: {
            const int_ty = cond_ty.intTagType(zcu);
            const int_info = int_ty.intInfo(zcu);
            const backing_bits, const big_int = cg.backingIntBits(int_info.bits);
            if (big_int) return cg.todo("implement composite int loop switch", .{});
            break :blk if (backing_bits <= 32) 1 else 2;
        },
        .pointer => blk: {
            initial_cond_indirect = try cg.intFromPtr(initial_cond_indirect);
            break :blk target.ptrBitWidth() / 32;
        },
        else => return cg.todo("implement loop switch for type {s}", .{@tagName(cond_ty.zigTypeTag(zcu))}),
    };

    const cond_ty_id = try cg.resolveType(cond_ty, .indirect);
    const cond_var = try cg.alloc(cond_ty_id, null);
    try cg.store(cond_ty, cond_var, initial_cond_indirect, .{});

    const num_cases = switch_br.cases_len;

    var num_conditions: u32 = 0;
    var last_range_case: ?u32 = null;
    {
        var it = switch_br.iterateCases();
        while (it.next()) |case| {
            if (case.ranges.len > 0) {
                last_range_case = case.idx;
            } else {
                num_conditions += @intCast(case.items.len);
            }
        }
    }

    const case_labels = cg.allocIds(num_cases);
    const default_label = cg.allocId();
    const switch_default = if (last_range_case != null) cg.allocId() else default_label;

    const header_label = cg.allocId();
    const loop_merge = cg.allocId();
    const continue_label = cg.allocId();
    const switch_merge = cg.allocId();
    const body_label = cg.allocId();

    // switch_dispatch signals "continue the loop" by using this sentinel as the
    // next_block in structuredBreak. at switch_merge, a phi + comparison distinguishes
    // dispatch (continue) from break (exit)
    const dispatch_sentinel = try cg.constInt(.u32, @intFromEnum(inst));

    try cg.loop_switches.putNoClobber(gpa, inst, .{
        .cond_var = cond_var,
        .continue_label = dispatch_sentinel,
    });
    defer assert(cg.loop_switches.remove(inst));

    try cg.body.emit(gpa, .OpBranch, .{ .target_label = header_label });
    try cg.beginSpvBlock(header_label);

    try cg.body.emit(gpa, .OpLoopMerge, .{
        .merge_block = loop_merge,
        .continue_target = continue_label,
        .loop_control = .{},
    });

    try cg.body.emit(gpa, .OpBranch, .{ .target_label = body_label });
    try cg.beginSpvBlock(body_label);

    const cond = try cg.load(cond_ty, cond_var, .{});
    const cond_indirect = try cg.convertToIndirect(cond_ty, cond);

    try cg.body.emit(gpa, .OpSelectionMerge, .{
        .merge_block = switch_merge,
        .selection_control = .{},
    });

    try cg.body.emitRaw(gpa, .OpSwitch, 2 + (cond_words + 1) * num_conditions);
    cg.body.writeOperand(Id, cond_indirect);
    cg.body.writeOperand(Id, switch_default);

    {
        var it = switch_br.iterateCases();
        while (it.next()) |case| {
            if (case.ranges.len > 0) continue;
            const label = case_labels.at(case.idx);
            for (case.items) |item| {
                const value: Value = .fromInterned(item.toInterned().?);
                const int_val: u64 = switch (cond_ty.zigTypeTag(zcu)) {
                    .bool, .int => if (cond_ty.isSignedInt(zcu)) @bitCast(value.toSignedInt(zcu)) else value.toUnsignedInt(zcu),
                    .@"enum" => value.intFromEnum(zcu).toUnsignedInt(zcu),
                    .error_set => value.getErrorInt(zcu),
                    .pointer => value.toUnsignedInt(zcu),
                    else => unreachable,
                };
                const int_lit: spec.LiteralContextDependentNumber = switch (cond_words) {
                    1 => .{ .uint32 = @intCast(int_val) },
                    2 => .{ .uint64 = int_val },
                    else => unreachable,
                };
                cg.body.writeOperand(spec.LiteralContextDependentNumber, int_lit);
                cg.body.writeOperand(Id, label);
            }
        }
    }

    var incoming_structured_blocks: std.ArrayList(Block.Incoming) = .empty;
    defer incoming_structured_blocks.deinit(gpa);
    try incoming_structured_blocks.ensureUnusedCapacity(gpa, num_cases + 1);

    if (last_range_case != null) {
        const cond_tmp: Temporary = .init(cond_ty, cond);
        const bool_ty_id = try cg.resolveType(.bool, .direct);

        try cg.beginSpvBlock(switch_default);

        var it_range = switch_br.iterateCases();
        while (it_range.next()) |case| {
            if (case.ranges.len == 0) continue;

            var case_cond: ?Id = null;

            for (case.items) |item| {
                const item_tmp: Temporary = try cg.temporary(item);
                const eq = try (try cg.cmp(.eq, cond_tmp, item_tmp)).materialize(cg);
                case_cond = if (case_cond) |prev| blk: {
                    const combined = cg.allocId();
                    try cg.body.emit(gpa, .OpLogicalOr, .{
                        .id_result_type = bool_ty_id,
                        .id_result = combined,
                        .operand_1 = prev,
                        .operand_2 = eq,
                    });
                    break :blk combined;
                } else eq;
            }

            for (case.ranges) |range| {
                const lo_tmp: Temporary = try cg.temporary(range[0]);
                const hi_tmp: Temporary = try cg.temporary(range[1]);
                const ge = try (try cg.cmp(.gte, cond_tmp, lo_tmp)).materialize(cg);
                const le = try (try cg.cmp(.lte, cond_tmp, hi_tmp)).materialize(cg);
                const in_range = cg.allocId();
                try cg.body.emit(gpa, .OpLogicalAnd, .{
                    .id_result_type = bool_ty_id,
                    .id_result = in_range,
                    .operand_1 = ge,
                    .operand_2 = le,
                });
                case_cond = if (case_cond) |prev| blk: {
                    const combined = cg.allocId();
                    try cg.body.emit(gpa, .OpLogicalOr, .{
                        .id_result_type = bool_ty_id,
                        .id_result = combined,
                        .operand_1 = prev,
                        .operand_2 = in_range,
                    });
                    break :blk combined;
                } else in_range;
            }

            const case_label = case_labels.at(case.idx);
            const is_last = case.idx == last_range_case.?;
            const next_check = if (is_last) default_label else cg.allocId();

            try cg.body.emit(gpa, .OpSelectionMerge, .{
                .merge_block = next_check,
                .selection_control = .{},
            });

            try cg.body.emit(gpa, .OpBranchConditional, .{
                .condition = case_cond.?,
                .true_label = case_label,
                .false_label = next_check,
            });

            if (!is_last) {
                try cg.beginSpvBlock(next_check);
            }
        }
    }

    {
        var it = switch_br.iterateCases();
        while (it.next()) |case| {
            const label = case_labels.at(case.idx);
            try cg.beginSpvBlock(label);

            const next_block = try cg.genStructuredBody(.selection, case.body);
            incoming_structured_blocks.appendAssumeCapacity(.{
                .src_label = cg.block_label,
                .next_block = next_block,
            });
            try cg.body.emit(gpa, .OpBranch, .{ .target_label = switch_merge });
        }
    }

    const else_body = blk: {
        var it_else = switch_br.iterateCases();
        while (it_else.next()) |_| {}
        break :blk it_else.elseBody();
    };
    try cg.beginSpvBlock(default_label);
    if (else_body.len != 0) {
        const next_block = try cg.genStructuredBody(.selection, else_body);
        incoming_structured_blocks.appendAssumeCapacity(.{
            .src_label = cg.block_label,
            .next_block = next_block,
        });
        try cg.body.emit(gpa, .OpBranch, .{ .target_label = switch_merge });
    } else {
        try cg.body.emit(gpa, .OpUnreachable, {});
    }

    try cg.beginSpvBlock(switch_merge);
    const next_block = try cg.structuredNextBlock(incoming_structured_blocks.items);

    const is_dispatch = cg.allocId();
    const bool_ty_id = try cg.resolveType(.bool, .direct);
    try cg.body.emit(gpa, .OpIEqual, .{
        .id_result_type = bool_ty_id,
        .id_result = is_dispatch,
        .operand_1 = next_block,
        .operand_2 = dispatch_sentinel,
    });

    const dispatch_check_merge = cg.allocId();
    try cg.body.emit(gpa, .OpSelectionMerge, .{
        .merge_block = dispatch_check_merge,
        .selection_control = .{},
    });
    const exit_block = cg.allocId();
    try cg.body.emit(gpa, .OpBranchConditional, .{
        .condition = is_dispatch,
        .true_label = dispatch_check_merge,
        .false_label = exit_block,
    });

    try cg.beginSpvBlock(exit_block);
    try cg.body.emit(gpa, .OpBranch, .{ .target_label = loop_merge });

    try cg.beginSpvBlock(dispatch_check_merge);
    try cg.body.emit(gpa, .OpBranch, .{ .target_label = continue_label });

    try cg.beginSpvBlock(continue_label);
    try cg.body.emit(gpa, .OpBranch, .{ .target_label = header_label });

    try cg.beginSpvBlock(loop_merge);
    try cg.structuredBreak(next_block);
}

fn airSwitchDispatch(cg: *CodeGen, inst: Air.Inst.Index) !void {
    const br = cg.air.instructions.items(.data)[@intFromEnum(inst)].br;
    const loop_switch = cg.loop_switches.get(br.block_inst).?;
    const cond_ty = cg.typeOf(br.operand);
    const operand = try cg.resolve(br.operand);
    const operand_indirect = try cg.convertToIndirect(cond_ty, operand);

    try cg.store(cond_ty, loop_switch.cond_var, operand_indirect, .{});
    try cg.structuredBreak(loop_switch.continue_label);
}

fn airUnreach(cg: *CodeGen) !void {
    try cg.body.emit(cg.gpa, .OpUnreachable, {});
}

fn airDbgStmt(cg: *CodeGen, inst: Air.Inst.Index) !void {
    const zcu = cg.zcu;
    const dbg_stmt = cg.air.instructions.items(.data)[@intFromEnum(inst)].dbg_stmt;
    const path = zcu.navFileScope(cg.owner_nav).sub_file_path;

    if (zcu.comp.config.root_strip) return;

    const path_id = cg.allocId();
    try cg.sections.debug_strings.emit(cg.gpa, .OpString, .{
        .id_result = path_id,
        .string = path,
    });
    try cg.body.emit(cg.gpa, .OpLine, .{
        .file = path_id,
        .line = cg.base_line + dbg_stmt.line + 1,
        .column = dbg_stmt.column + 1,
    });
}

fn airDbgInlineBlock(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const zcu = cg.zcu;
    const block = cg.air.unwrapDbgBlock(inst);
    const old_base_line = cg.base_line;
    defer cg.base_line = old_base_line;
    cg.base_line = zcu.navSrcLine(zcu.funcInfo(block.func).owner_nav);
    return cg.lowerBlock(inst, block.body);
}

fn airDbgVar(cg: *CodeGen, inst: Air.Inst.Index) !void {
    const pl_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].pl_op;
    const target_id = switch (try cg.resolvePtr(pl_op.operand)) {
        .tracked => return,
        .id => |id| id,
    };
    const name: Air.NullTerminatedString = @enumFromInt(pl_op.payload);
    try cg.debugName(target_id, name.toSlice(cg.air));
}

fn airAssembly(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    const gpa = cg.gpa;
    const zcu = cg.zcu;
    const unwrapped_asm = cg.air.unwrapAsm(inst);

    const is_volatile = unwrapped_asm.is_volatile;
    const outputs_len = unwrapped_asm.outputs.len;

    if (!is_volatile and cg.liveness.isUnused(inst)) return null;

    if (outputs_len > 1) {
        return cg.todo("implement inline asm with more than 1 output", .{});
    }

    var ass: Assembler = .{ .cg = cg };
    defer ass.deinit();

    var it = unwrapped_asm.iterateOutputs();
    while (it.next()) |out| {
        if (out.operand != .none) {
            return cg.todo("implement inline asm with non-returned output", .{});
        }
    }

    it = unwrapped_asm.iterateInputs();
    while (it.next()) |in| {
        const input_ty = cg.typeOf(in.operand);

        if (std.mem.eql(u8, in.constraint, "c")) {
            // constant
            const val: Value = .fromInterned(in.operand.toInterned() orelse {
                return cg.fail("assembly inputs with 'c' constraint have to be compile-time known", .{});
            });

            const ip = &zcu.intern_pool;
            switch (ip.indexToKey(val.toIntern())) {
                .int_type,
                .ptr_type,
                .array_type,
                .vector_type,
                .opt_type,
                .anyframe_type,
                .error_union_type,
                .simple_type,
                .struct_type,
                .union_type,
                .opaque_type,
                .spirv_type,
                .enum_type,
                .func_type,
                .error_set_type,
                .inferred_error_set_type,
                => unreachable, // types, not values

                .undef => return cg.fail("assembly input with 'c' constraint cannot be undefined", .{}),

                .int => try ass.value_map.put(gpa, in.name, .{ .constant = @intCast(val.toUnsignedInt(zcu)) }),
                .enum_literal => |str| try ass.value_map.put(gpa, in.name, .{ .string = str.toSlice(ip) }),

                else => unreachable, // TODO
            }
        } else if (std.mem.eql(u8, in.constraint, "t")) {
            // type
            if (input_ty.zigTypeTag(zcu) == .type) {
                // This assembly input is a type instead of a value.
                // That's fine for now, just make sure to resolve it as such.
                const ty_id = try cg.resolveType(in.operand.toType(), .direct);
                try ass.value_map.put(gpa, in.name, .{ .ty = ty_id });
            } else {
                const ty_id = try cg.resolveType(input_ty, .direct);
                try ass.value_map.put(gpa, in.name, .{ .ty = ty_id });
            }
        } else {
            if (input_ty.zigTypeTag(zcu) == .type) {
                return cg.fail("use the 't' constraint to supply types to SPIR-V inline assembly", .{});
            }

            const val_id = try cg.resolve(in.operand);
            try ass.value_map.put(gpa, in.name, .{ .value = val_id });
        }
    }
    // TODO: do something with clobbers
    _ = unwrapped_asm.clobbers;

    const asm_source = unwrapped_asm.source;

    ass.assemble(asm_source) catch |err| switch (err) {
        error.AssembleFail => {
            // TODO: For now the compiler only supports a single error message per decl,
            // so to translate the possible multiple errors from the assembler, emit
            // them as notes here.
            // TODO: Translate proper error locations.
            assert(ass.errors.items.len != 0);
            const msg: *Zcu.ErrorMsg = msg: {
                const src_loc = zcu.navSrcLoc(cg.owner_nav);
                var msg: *Zcu.ErrorMsg = try .create(zcu.gpa, src_loc, "failed to assemble SPIR-V inline assembly", .{});
                errdefer msg.destroy(zcu.gpa);

                const notes = try zcu.gpa.alloc(Zcu.ErrorMsg, ass.errors.items.len);
                errdefer zcu.gpa.free(notes);

                var i: usize = 0;
                errdefer for (notes[0..i]) |*note| {
                    note.deinit(zcu.gpa);
                };

                while (i < ass.errors.items.len) : (i += 1) {
                    notes[i] = try Zcu.ErrorMsg.init(zcu.gpa, src_loc, "{s}", .{ass.errors.items[i].msg});
                }

                break :msg msg;
            };
            return zcu.codegenFailMsg(cg.owner_nav, msg);
        },
        else => |others| return others,
    };

    it = unwrapped_asm.iterateOutputs();
    while (it.next()) |out| {
        const result = ass.value_map.get(out.name) orelse return {
            return cg.fail("invalid asm output '{s}'", .{out.name});
        };
        switch (result) {
            .just_declared, .unresolved_forward_reference => unreachable,
            .ty => return cg.fail("cannot return spir-v type as value from assembly", .{}),
            .value => |ref| return ref,
            .constant, .string => return cg.fail("cannot return constant from assembly", .{}),
        }
        // TODO: Multiple results
        // TODO: Check that the output type from assembly is the same as the type actually expected by Zig.

    }

    return null;
}

fn airCall(cg: *CodeGen, inst: Air.Inst.Index, modifier: std.lang.CallModifier) !?Id {
    _ = modifier;

    const gpa = cg.gpa;
    const zcu = cg.zcu;
    const air_call = cg.air.unwrapCall(inst);
    const args = air_call.args;
    const callee_ty = cg.typeOf(air_call.callee);
    const zig_fn_ty = switch (callee_ty.zigTypeTag(zcu)) {
        .@"fn" => callee_ty,
        .pointer => return cg.fail("cannot call function pointers", .{}),
        else => unreachable,
    };
    const fn_info = zcu.typeToFunc(zig_fn_ty).?;
    const return_type = fn_info.return_type;

    const result_type_id = try cg.resolveFnReturnType(.fromInterned(return_type));
    const result_id = cg.allocId();
    const callee_id = try cg.resolve(air_call.callee);

    const scratch_top = cg.id_scratch.items.len;
    defer cg.id_scratch.shrinkRetainingCapacity(scratch_top);
    const params = try cg.id_scratch.addManyAsSlice(gpa, args.len);

    var n_params: usize = 0;
    for (args) |arg| {
        // Note: resolve() might emit instructions, so we need to call it
        // before starting to emit OpFunctionCall instructions. Hence the
        // temporary params buffer.
        const arg_ty = cg.typeOf(arg);
        if (!arg_ty.hasRuntimeBits(zcu)) continue;

        if (arg_ty.zigTypeTag(zcu) == .pointer and !arg_ty.isSlice(zcu) and
            !arg_ty.childType(zcu).hasRuntimeBits(zcu) and
            cg.storageClass(arg_ty.ptrAddressSpace(zcu)) == .function)
        {
            // in logical addressing, pointer arguments to function calls
            // must be memory object declarations (OpVariable). for pointers to
            // zero-sized types, the source value may not be a variable, so just
            // allocate a dummy one.
            const child_ty_id = try cg.resolveType(arg_ty.childType(zcu), .indirect);
            params[n_params] = try cg.alloc(child_ty_id, null);
        } else {
            params[n_params] = try cg.resolve(arg);
        }
        n_params += 1;
    }

    try cg.body.emit(gpa, .OpFunctionCall, .{
        .id_result_type = result_type_id,
        .id_result = result_id,
        .function = callee_id,
        .id_ref_3 = params[0..n_params],
    });

    if (cg.liveness.isUnused(inst) or !Type.fromInterned(return_type).hasRuntimeBits(zcu)) {
        return null;
    }

    return result_id;
}

fn builtin3D(
    cg: *CodeGen,
    result_ty: Type,
    built_in: spec.BuiltIn,
    dimension: u32,
    out_of_range_value: anytype,
) !Id {
    const gpa = cg.gpa;
    if (dimension >= 3) return try cg.constInt(result_ty, out_of_range_value);
    const u32_ty_id = try cg.intType(.unsigned, 32);
    const vec_ty_id = try cg.vectorType(3, u32_ty_id);
    const ptr_ty_id = try cg.ptrType(vec_ty_id, .input);
    const builtins_gop = try cg.builtins.getOrPut(gpa, .{ built_in, .input });
    if (!builtins_gop.found_existing) {
        builtins_gop.value_ptr.* = try cg.allocDecl(.global);
        const decl = cg.declPtr(builtins_gop.value_ptr.*);
        try cg.sections.globals.emit(gpa, .OpVariable, .{
            .id_result_type = ptr_ty_id,
            .id_result = decl.result_id,
            .storage_class = .input,
        });
        try cg.decorate(decl.result_id, .{ .built_in = .{ .built_in = built_in } });
    }
    const spv_decl_index = builtins_gop.value_ptr.*;
    try cg.decl_deps.append(gpa, spv_decl_index);
    const ptr_id = cg.declPtr(spv_decl_index).result_id;
    const vec_id = cg.allocId();
    try cg.body.emit(gpa, .OpLoad, .{
        .id_result_type = vec_ty_id,
        .id_result = vec_id,
        .pointer = ptr_id,
    });
    return try cg.extractVectorComponent(result_ty, vec_id, dimension);
}

fn airWorkItemId(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    if (cg.liveness.isUnused(inst)) return null;
    const pl_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].pl_op;
    const dimension = pl_op.payload;
    return try cg.builtin3D(.u32, .local_invocation_id, dimension, 0);
}

// TODO: this must be an OpConstant/OpSpec but even then the driver crashes.
fn airWorkGroupSize(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    if (cg.liveness.isUnused(inst)) return null;
    const pl_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].pl_op;
    const dimension = pl_op.payload;
    return try cg.builtin3D(.u32, .workgroup_size, dimension, 0);
}

fn airWorkGroupId(cg: *CodeGen, inst: Air.Inst.Index) !?Id {
    if (cg.liveness.isUnused(inst)) return null;
    const pl_op = cg.air.instructions.items(.data)[@intFromEnum(inst)].pl_op;
    const dimension = pl_op.payload;
    return try cg.builtin3D(.u32, .workgroup_id, dimension, 0);
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Target = std.Target;
const Signedness = std.lang.Signedness;
const assert = std.debug.assert;
const log = std.log.scoped(.codegen);

const builtin = @import("builtin");
const link = @import("../../link.zig");
const codegen = @import("../../codegen.zig");
const Zcu = @import("../../Zcu.zig");
const Type = @import("../../Type.zig");
const Value = @import("../../Value.zig");
const Air = @import("../../Air.zig");
const InternPool = @import("../../InternPool.zig");
const Section = @import("Section.zig");
const Assembler = @import("Assembler.zig");
const Mir = @import("Mir.zig");

const spec = @import("spec.zig");
const Opcode = spec.Opcode;
const Word = spec.Word;
const Id = spec.Id;
const IdRange = spec.IdRange;
const StorageClass = spec.StorageClass;

const CodeGen = @This();
