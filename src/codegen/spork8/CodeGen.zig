const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const CodeGen = @This();
const link = @import("../../link.zig");
const Spork8 = link.File.Spork8;
const Zcu = @import("../../Zcu.zig");
const InternPool = @import("../../InternPool.zig");
const Air = @import("../../Air.zig");
const Liveness = Air.Liveness;
const Mir = @import("Mir.zig");

air: Air,
liveness: Liveness,
gpa: Allocator,
pt: Zcu.PerThread,
owner_nav: InternPool.Nav.Index,
func_index: InternPool.Index,
mir_instructions: std.MultiArrayList(Mir.Inst),
/// Contains extra data for MIR
mir_extra: std.ArrayListUnmanaged(u32),

pub fn legalizeFeatures(_: *const std.Target) *const Air.Legalize.Features {
    return comptime &.initMany(&.{
        .expand_bit_cast_safe,
        .expand_int_cast_safe,
        .expand_int_from_float_safe,
        .expand_int_from_float_optimized_safe,
        .expand_add_safe,
        .expand_sub_safe,
        .expand_mul_safe,

        .expand_packed_load,
        .expand_packed_store,
        .expand_packed_agg_field_val,
        .expand_packed_aggregate_init,
        .expand_array_to_vector,

        .scalarize_add,
        .scalarize_add_optimized,
        .scalarize_add_wrap,
        .scalarize_add_sat,
        .scalarize_sub,
        .scalarize_sub_optimized,
        .scalarize_sub_wrap,
        .scalarize_sub_sat,
        .scalarize_mul,
        .scalarize_mul_optimized,
        .scalarize_mul_wrap,
        .scalarize_mul_sat,
        .scalarize_div_float,
        .scalarize_div_float_optimized,
        .scalarize_div_trunc,
        .scalarize_div_trunc_optimized,
        .scalarize_div_floor,
        .scalarize_div_floor_optimized,
        .scalarize_div_ceil,
        .scalarize_div_ceil_optimized,
        .scalarize_div_exact,
        .scalarize_div_exact_optimized,
        .scalarize_rem,
        .scalarize_rem_optimized,
        .scalarize_mod,
        .scalarize_mod_optimized,
        .scalarize_max,
        .scalarize_min,
        .scalarize_add_with_overflow,
        .scalarize_sub_with_overflow,
        .scalarize_mul_with_overflow,
        .scalarize_shl_with_overflow,
        .scalarize_bit_and,
        .scalarize_bit_or,
        .scalarize_shr,
        .scalarize_shr_exact,
        .scalarize_shl,
        .scalarize_shl_exact,
        .scalarize_shl_sat,
        .scalarize_xor,
        .scalarize_not,
        .scalarize_clz,
        .scalarize_ctz,
        .scalarize_popcount,
        .scalarize_byte_swap,
        .scalarize_bit_reverse,
        .scalarize_sqrt,
        .scalarize_sin,
        .scalarize_cos,
        .scalarize_tan,
        .scalarize_exp,
        .scalarize_exp2,
        .scalarize_log,
        .scalarize_log2,
        .scalarize_log10,
        .scalarize_abs,
        .scalarize_floor,
        .scalarize_ceil,
        .scalarize_round,
        .scalarize_trunc_float,
        .scalarize_neg,
        .scalarize_neg_optimized,
        .scalarize_cmp_vector,
        .scalarize_cmp_vector_optimized,
        .scalarize_fptrunc,
        .scalarize_fpext,
        .scalarize_int_cast,
        .scalarize_ptr_cast,
        .scalarize_ptr_from_int,
        .scalarize_int_from_ptr,
        .scalarize_trunc,
        .scalarize_int_from_float,
        .scalarize_int_from_float_optimized,
        .scalarize_float_from_int,
        .scalarize_reduce,
        .scalarize_reduce_optimized,
        .scalarize_shuffle_one,
        .scalarize_shuffle_two,
        .scalarize_select,
        .scalarize_mul_add,

        .scalarize_bit_cast_padded_elems,
    });
}

pub fn generate(
    bin_file: *link.File,
    pt: Zcu.PerThread,
    func_index: InternPool.Index,
    air: *const Air,
    liveness: *const ?Air.Liveness,
) link.Error!Mir {
    _ = bin_file;
    const zcu = pt.zcu;
    const gpa = zcu.gpa;
    const cg = zcu.funcInfo(func_index);

    var code_gen: CodeGen = .{
        .gpa = gpa,
        .pt = pt,
        .air = air.*,
        .liveness = liveness.*.?,
        .owner_nav = cg.owner_nav,
        .func_index = func_index,
        .mir_instructions = .empty,
        .mir_extra = .empty,
    };
    defer code_gen.deinit();

    return generateInner(&code_gen) catch |err| switch (err) {
        error.AlreadyReported,
        error.OutOfMemory,
        => |e| return e,
    };
}

pub fn deinit(cg: *CodeGen) void {
    cg.* = undefined;
}

const InnerError = error{
    AlreadyReported,
    OutOfMemory,
};

fn generateInner(cg: *CodeGen) InnerError!Mir {
    // Generate MIR for function body
    try cg.genBody(cg.air.getMainBody());

    try cg.mir_extra.shrinkToLen(cg.gpa);

    return .{
        .instructions = cg.mir_instructions.toOwnedSlice(),
        .extra = cg.mir_extra.toOwnedSliceAssert(),
    };
}

fn genBody(cg: *CodeGen, body: []const Air.Inst.Index) InnerError!void {
    const zcu = cg.pt.zcu;
    const ip = &zcu.intern_pool;

    for (body) |inst| {
        if (cg.liveness.isUnused(inst) and !cg.air.mustLower(inst, ip)) continue;
        try cg.genInst(inst);
    }
}

fn genInst(cg: *CodeGen, inst: Air.Inst.Index) InnerError!void {
    const air_tags = cg.air.instructions.items(.tag);
    return switch (air_tags[@backingInt(inst)]) {
        .inferred_alloc, .inferred_alloc_comptime => unreachable,

        .add,
        .add_sat,
        .add_wrap,
        .sub,
        .sub_sat,
        .sub_wrap,
        .mul,
        .mul_sat,
        .mul_wrap,
        .div_float,
        .div_exact,
        .div_trunc,
        .div_floor,
        .bit_and,
        .bit_or,
        .rem,
        .mod,
        .shl,
        .shl_exact,
        .shl_sat,
        .shr,
        .shr_exact,
        .xor,
        .max,
        .min,
        .mul_add,

        .sqrt,
        .sin,
        .cos,
        .tan,
        .exp,
        .exp2,
        .log,
        .log2,
        .log10,
        .floor,
        .ceil,
        .round,
        .trunc_float,
        .neg,

        .abs,

        .add_with_overflow,
        .sub_with_overflow,
        .shl_with_overflow,
        .mul_with_overflow,

        .clz,
        .ctz,

        .cmp_eq,
        .cmp_gte,
        .cmp_gt,
        .cmp_lte,
        .cmp_lt,
        .cmp_neq,

        .cmp_vector,

        .array_elem_val,
        .array_to_slice,
        .alloc,
        .arg,
        .block,
        .breakpoint,
        .br,
        .repeat,
        .switch_dispatch,
        .cond_br,
        .fptrunc,
        .fpext,
        .int_from_float,
        .float_from_int,
        .get_union_tag,

        .@"try",
        .try_cold,
        .try_ptr,
        .try_ptr_cold,

        .dbg_stmt,
        .dbg_empty_stmt,
        .dbg_inline_block,
        .dbg_var_ptr,
        .dbg_var_val,
        .dbg_arg_inline,

        .call,
        .call_always_tail,
        .call_never_tail,
        .call_never_inline,

        .is_err,
        .is_non_err,

        .is_null,
        .is_non_null,
        .is_null_ptr,
        .is_non_null_ptr,

        .load,
        .loop,
        .memset,
        .memset_safe,
        .not,
        .optional_payload,
        .optional_payload_ptr,
        .optional_payload_ptr_set,
        .ptr_add,
        .ptr_sub,
        .ptr_elem_ptr,
        .ptr_elem_val,
        .ret,
        .ret_safe,
        .ret_ptr,
        .ret_load,
        .splat,
        .select,
        .reduce,
        .aggregate_init,
        .union_init,
        .prefetch,
        .popcount,
        .byte_swap,
        .bit_reverse,

        .slice,
        .slice_len,
        .slice_elem_val,
        .slice_elem_ptr,
        .slice_ptr,
        .ptr_slice_len_ptr,
        .ptr_slice_ptr_ptr,
        .store,
        .store_safe,

        .set_union_tag,
        .struct_field_ptr,
        .struct_field_ptr_index_0,
        .struct_field_ptr_index_1,
        .struct_field_ptr_index_2,
        .struct_field_ptr_index_3,
        .field_parent_ptr,

        .switch_br,
        .loop_switch_br,
        .trunc,

        .wrap_optional,
        .unwrap_errunion_payload,
        .unwrap_errunion_payload_ptr,
        .unwrap_errunion_err,
        .unwrap_errunion_err_ptr,
        .wrap_errunion_payload,
        .wrap_errunion_err,
        .errunion_payload_ptr_set,
        .error_name,

        .wasm_memory_size,
        .wasm_memory_grow,

        .memcpy,

        .ret_addr,
        .tag_name,

        .error_set_has_value,
        .frame_addr,

        .is_err_ptr,
        .is_non_err_ptr,

        .err_return_trace,
        .set_err_return_trace,
        .save_err_return_trace_index,
        .is_named_enum_value,
        .addrspace_cast,
        .c_va_arg,
        .c_va_copy,
        .c_va_end,
        .c_va_start,
        .memmove,

        .atomic_load,
        .atomic_store_unordered,
        .atomic_store_monotonic,
        .atomic_store_release,
        .atomic_store_seq_cst,
        .atomic_rmw,
        .cmpxchg_weak,
        .cmpxchg_strong,

        .add_optimized,
        .sub_optimized,
        .mul_optimized,
        .div_float_optimized,
        .div_trunc_optimized,
        .div_floor_optimized,
        .div_exact_optimized,
        .rem_optimized,
        .mod_optimized,
        .neg_optimized,
        .cmp_lt_optimized,
        .cmp_lte_optimized,
        .cmp_eq_optimized,
        .cmp_gte_optimized,
        .cmp_gt_optimized,
        .cmp_neq_optimized,
        .cmp_vector_optimized,
        .reduce_optimized,
        .int_from_float_optimized,
        .add_safe,
        .sub_safe,
        .mul_safe,
        .div_ceil,
        .div_ceil_optimized,
        .bit_cast,
        .bit_cast_safe,
        .ptr_cast,
        .ptr_from_int,
        .int_from_ptr,
        .error_cast,
        .error_from_int,
        .int_from_error,
        .union_from_enum,
        .int_cast,
        .int_cast_safe,
        .agg_field_val,
        .array_to_vector,
        .int_from_float_safe,
        .int_from_float_optimized_safe,
        .shuffle_one,
        .shuffle_two,
        .cmp_lte_errors_len,
        .runtime_nav_ptr,
        .spirv_runtime_array_len,
        .legalize_vec_store_elem,
        .legalize_vec_elem_val,
        .legalize_compiler_rt_call,
        => |tag| return cg.fail("TODO: implement spork8 inst: {t}", .{tag}),

        .unreach => cg.airUnreachable(inst),
        .assembly => cg.airAssembly(inst),
        .trap => cg.airTrap(inst),

        .work_item_id,
        .work_group_size,
        .work_group_id,
        => unreachable,
    };
}

fn airUnreachable(cg: *CodeGen, inst: Air.Inst.Index) InnerError!void {
    _ = cg;
    _ = inst;
}

fn airTrap(cg: *CodeGen, inst: Air.Inst.Index) InnerError!void {
    _ = inst;
    try cg.addTag(.halt);
}

fn airAssembly(cg: *CodeGen, inst: Air.Inst.Index) InnerError!void {
    const unwrapped_asm = cg.air.unwrapAsm(inst);
    const outputs = unwrapped_asm.outputs;
    // const inputs = unwrapped_asm.inputs;

    const zcu = cg.pt.zcu;
    // const output_ty = cg.typeOfIndex(inst);

    if (outputs.len != 0) {
        @panic("TODO: Support assembly outputs");
    }

    var constValues: std.array_hash_map.String(u8) = .empty;
    defer constValues.deinit(zcu.gpa);
    {
        var it = unwrapped_asm.iterateInputs();
        while (it.next()) |input| {
            const constraint = input.constraint;
            if (!mem.eql(u8, constraint, "I")) {
                return cg.fail("assembly constraint {q} not supported", .{constraint});
            }
            const operand = input.operand.toInterned() orelse {
                return cg.fail("immediate argument to inline assembly must be compile-time value", .{});
            };
            const name = input.name;

            const value = switch (zcu.intern_pool.indexToKey(operand)) {
                .int => |val| v: {
                    if (val.ty != .u8_type) {
                        return cg.fail("non-u8 type used in inline assembly value: {}", .{val.ty});
                    }
                    break :v val.storage.u64;
                },
                else => return cg.fail("non-int operands not supported", .{}),
            };

            try constValues.put(zcu.gpa, name, @intCast(value));
        }
    }

    {
        var lines = mem.tokenizeScalar(u8, unwrapped_asm.source, '\n');
        while (lines.next()) |line| {
            var tokens = mem.tokenizeScalar(u8, line, ' ');
            // If there's no tokens, then it must be a blank line, so just skip it.
            const op = tokens.next() orelse continue;
            const instType = std.meta.stringToEnum(AsmInstType, op) orelse return cg.fail("invalid asm instruction: {q}", .{op});
            switch (instType) {
                .LoadI => {
                    const registerString = tokens.next() orelse return cg.fail("missing register for LoadI instruction", .{});
                    const register = std.meta.stringToEnum(Register, registerString) orelse return cg.fail("invalid register: {q}", .{registerString});
                    const value = tokens.next() orelse return cg.fail("missing immediate value for LoadI", .{});
                    const intValue = v: {
                        if (mem.startsWith(u8, value, "%[")) {
                            const name = value[2 .. value.len - 1];
                            break :v constValues.get(name) orelse return cg.fail("constraint name {q} not included in constraints for inline asm", .{name});
                        } else {
                            break :v std.fmt.parseInt(u8, value, 0) catch |err|
                                return cg.fail("invalid LoadI immediate value: {t}", .{err});
                        }
                    };
                    if (register != .OutA) {
                        return cg.fail("TODO: support other variants of LoadI", .{});
                    }
                    try cg.addTagImm8(.load_i_outa, intValue);
                },
                else => return cg.fail("TODO: support asm instruction: {t}", .{instType}),
            }
        }
    }
}

pub fn addInst(cg: *CodeGen, inst: Mir.Inst) error{OutOfMemory}!void {
    try cg.mir_instructions.append(cg.gpa, inst);
}

pub fn addTag(cg: *CodeGen, tag: Mir.Inst.Tag) error{OutOfMemory}!void {
    try cg.addInst(.{ .tag = tag, .data = .{ .nothing = {} } });
}

pub fn addTagImm8(cg: *CodeGen, tag: Mir.Inst.Tag, imm8: u8) error{OutOfMemory}!void {
    try cg.addInst(.{ .tag = tag, .data = .{ .imm8 = imm8 } });
}

fn fail(cg: *CodeGen, comptime fmt: []const u8, args: anytype) error{ OutOfMemory, AlreadyReported } {
    const zcu = cg.pt.zcu;
    const func = zcu.funcInfo(cg.func_index);
    return zcu.codegenFail(func.owner_nav, fmt, args);
}

fn extraLen(cg: *const CodeGen) u32 {
    return @intCast(cg.mir_extra.items.len - cg.start_mir_extra_off);
}

const AsmInstType = enum(u8) {
    /// Set the memory address high byte to a register value.
    SetPageReg,
    /// Set the memory address high byte to a constant value.
    SetPageI,
    /// Set the memory address low byte to a register value.
    SetAddrReg,
    /// Set the memory address low byte to a constant value.
    SetAddrI,
    /// Load a value from a constant address into a register.
    Load,
    /// Load a constant value into a register.
    LoadI,
    /// Load a value from a constant address (setting low byte only) into a register.
    LoadP,
    /// Load a value from the currently set memory address into a register, and increment the address n times.
    LoadInc,
    /// Load a value from an offset on the current stack frame into a register.
    LoadStck,
    /// Store a value to a constant address from a register.
    Store,
    /// Store a constant value into a constant address.
    StoreI,
    /// Store a value to a constant address (low byte only) from a register.
    StoreP,
    /// Store a value from the currently set memory address from a register, and increment the address n times.
    StoreInc,
    /// Store a value to an offset on the current stack frame, from a register.
    StoreStck,
    /// Store a value to an offset on the next stack frame, from a register.
    StoreNStck,
    /// Store a value to an offset on the previous stack frame, from a register.
    StorePStck,
    /// Store a constant value to an offset on the current stack frame.
    StoreStckI,
    /// Store a constant value to an offset on the next stack frame.
    StoreNStckI,
    /// Store a constant value to an offset on the previous stack frame.
    StorePStckI,
    /// Copy a value from one register to another register.
    Copy,
    /// Jump to a constant location.
    Jump,
    /// Jump to a register A (high byte) + register B (low byte).
    JumpReg,
    /// Jump to a location pointed to by memory at the current memory address (high byte first).
    JumpMem,
    /// Call a function.
    Call,
    /// Return from a function.
    Return,
    /// Compare A to a constant value (sets flags, but discards result).
    CmpI,
    /// Compare A to a constant value with bitwise AND (sets flags, but discards result).
    CmpAndI,
    /// Compare A to a value from memory (sets flags, but discards result).
    Cmp,
    /// Compare A to a value in memory with bitwise AND (sets flags, but discards result).
    CmpAnd,
    /// Compare A to a value from a register (sets flags, but discards result).
    CmpReg,
    /// Compare A to a value from a register with bitwise AND (sets flags, but discards result).
    CmpAndReg,
    /// Shift B left by 1.
    ShiftL,
    /// Shift B right by 1.
    ShiftR,
    /// Rotate B left by 1.
    RotateL,
    /// Rotate B right by 1.
    RotateR,
    /// Add a constant value to A.
    AddI,
    /// Subtract a constant value from A.
    SubI,
    /// Bitwise-AND A with a constant value.
    AndI,
    /// Add a constant value to A, without updating flags.
    AddINF,
    /// Subtract a constant value from A, without updating flags.
    SubINF,
    /// Bitwise-AND A with a constant value, without updating flags.
    AndINF,
    /// Add register B to A -> A.
    AccumulateAdd,
    /// Subtract register B from A -> A.
    AccumulateSub,
    /// A & B -> A.
    AccumulateAnd,
    /// Bitwise OR B with A -> A.
    OrI,
    /// Bitwise OR a constant value with A -> A.
    XorI,
    /// Invert register A.
    Not,
    /// Add a value from memory to A.
    Add,
    /// Subtract a value from memory from A.
    Sub,
    /// AND A with a value from memory.
    And,
    /// OR A with a value from memory.
    Or,
    /// XOR A with a value from memory.
    Xor,
    /// No-op.
    Nop,
    /// No-op with 1 extra clock cycle.
    Nop1,
    /// No-op with 2 extra clock cycles.
    Nop2,
    /// Halt - stop the program forever (until reset).
    Halt,
};

const Register = enum(u8) {
    A,
    B,
    C,
    PCnt,
    MAdr,
    Stack,
    OutA,
    Shift,
    Swap,
};
