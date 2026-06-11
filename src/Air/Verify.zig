/// Verifies that AIR is valid, in that every instruction has valid operands and types. In compiler
/// builds with debug extensions, this is run on all AIR, both before `Air.Legalize` is run and (if
/// it is run) after it.
///
/// This verification pass is currently highly incomplete---expand it as needed.
const Verify = @This();

zcu: *Zcu,
func_index: InternPool.Index,
ret_ty: Type,
air: *const Air,
cur_inst: Air.Inst.Index,

pub fn run(pt: Zcu.PerThread, func_index: InternPool.Index, air: *const Air) void {
    if (!@import("build_options").enable_debug_extensions) {
        // `Air.Verify` is a debugging feature---it should not be used in release builds because it
        // has little benefit and negatively affects compiler performance.
        return;
    }

    const zcu = pt.zcu;

    const func_ty: Type = Value.fromInterned(func_index).typeOf(zcu);
    const ret_ty = func_ty.fnReturnType(zcu);

    var verify: Verify = .{
        .zcu = zcu,
        .func_index = func_index,
        .ret_ty = ret_ty,
        .air = air,
        .cur_inst = undefined, // populated by `body(...)`
    };
    verify.body(air.getMainBody()) catch |verify_err| switch (verify_err) {
        error.VerifyFail => {
            const ip = &zcu.intern_pool;
            const func_nav = ip.indexToKey(func_index).func.owner_nav;
            const func_fqn = ip.getNav(func_nav).fqn.toSlice(ip);
            log.info("AIR for '{s}':", .{func_fqn});
            const io = zcu.comp.io;
            const stderr = io.lockStderr(&.{}, null) catch |err| switch (err) {
                error.Canceled => return io.recancel(),
            };
            defer io.unlockStderr();
            air.write(&stderr.file_writer.interface, pt, null) catch |err| switch (err) {
                error.WriteFailed => switch (stderr.file_writer.err.?) {
                    error.Canceled => return io.recancel(),
                    else => {},
                },
            };
        },
    };
}

const Error = error{VerifyFail};

fn fail(verify: *Verify, msg: []const u8) Error {
    const ip = &verify.zcu.intern_pool;
    const func_nav = ip.indexToKey(verify.func_index).func.owner_nav;
    const func_fqn = ip.getNav(func_nav).fqn.toSlice(ip);
    log.err("'{s}', %{d}: {s}", .{ func_fqn, verify.cur_inst, msg });
    return error.VerifyFail;
}

fn body(verify: *Verify, body_insts: []const Air.Inst.Index) Error!void {
    const zcu = verify.zcu;
    const ip = &zcu.intern_pool;
    const air = verify.air;
    const tags = air.instructions.items(.tag);
    const data = air.instructions.items(.data);
    for (body_insts, 0..) |inst, body_index| {
        verify.cur_inst = inst;
        switch (tags[@intFromEnum(inst)]) {
            .block => {
                const block = air.unwrapBlock(inst);
                try verify.body(block.body);
            },
            .dbg_inline_block => {
                const block = air.unwrapDbgBlock(inst);
                try verify.body(block.body);
            },
            .@"try", .try_cold => {
                const @"try" = air.unwrapTry(inst);
                try verify.body(@"try".else_body);
            },
            .try_ptr, .try_ptr_cold => {
                const try_ptr = air.unwrapTryPtr(inst);
                try verify.body(try_ptr.else_body);
            },
            .loop => {
                const block = air.unwrapBlock(inst);
                try verify.body(block.body);
            },
            .cond_br => {
                const cond_br = air.unwrapCondBr(inst);
                try verify.body(cond_br.then_body);
                try verify.body(cond_br.else_body);
            },
            .switch_br, .loop_switch_br => {
                const switch_br = air.unwrapSwitch(inst);
                var it = switch_br.iterateCases();
                while (it.next()) |case| {
                    try verify.body(case.body);
                }
                const else_body = it.elseBody();
                if (else_body.len > 0) {
                    try verify.body(else_body);
                }
            },
            .ret, .ret_safe => {
                const operand = data[@intFromEnum(inst)].un_op;
                if (air.typeOf(operand, ip).toIntern() != verify.ret_ty.toIntern()) return verify.fail("bad return type");
            },
            .ret_load => {
                const operand = data[@intFromEnum(inst)].un_op;
                const ptr_ty = air.typeOf(operand, ip);
                if (ptr_ty.zigTypeTag(zcu) != .pointer) return verify.fail("operand is not a pointer");
                if (ptr_ty.ptrSize(zcu) != .one) return verify.fail("pointer size is not '.one'");
                if (ptr_ty.childType(zcu).toIntern() != verify.ret_ty.toIntern()) return verify.fail("bad return type");
            },

            .bit_cast => {
                const ty_op = data[@intFromEnum(inst)].ty_op;
                const operand_ty = air.typeOf(ty_op.operand, ip);
                const result_ty = ty_op.ty.toType();
                // Enums are allowed here even if their backing type is implicit.
                if (!operand_ty.hasBitRepresentation(zcu) and operand_ty.zigTypeTag(zcu) != .@"enum") {
                    return verify.fail("bad operand type");
                }
                if (!result_ty.hasBitRepresentation(zcu) and result_ty.zigTypeTag(zcu) != .@"enum") {
                    return verify.fail("bad result type");
                }
                if (operand_ty.isPtrAtRuntime(zcu)) return verify.fail("bad operand type (pointer)");
                if (result_ty.isPtrAtRuntime(zcu)) return verify.fail("bad result type (pointer)");
                if (operand_ty.bitSize(zcu) != result_ty.bitSize(zcu)) return verify.fail("bit size mismatch");
            },
            .ptr_cast => {
                const ty_op = data[@intFromEnum(inst)].ty_op;
                const operand_ty = air.typeOf(ty_op.operand, ip);
                const result_ty = ty_op.ty.toType();
                const operand_scalar_ty = operand_ty.scalarType(zcu);
                const result_scalar_ty = result_ty.scalarType(zcu);
                if (operand_ty.isSliceAtRuntime(zcu)) {
                    if (!result_ty.isSliceAtRuntime(zcu)) return verify.fail("operand is slice, but result is not");
                } else {
                    if (!operand_scalar_ty.isPtrAtRuntime(zcu)) return verify.fail("bad operand type");
                    if (!result_scalar_ty.isPtrAtRuntime(zcu)) return verify.fail("operand is pointer, but result is not");
                    if (operand_ty.isVector(zcu) and !result_ty.isVector(zcu)) return verify.fail("operand is vector, but result is not");
                    if (!operand_ty.isVector(zcu) and result_ty.isVector(zcu)) return verify.fail("result is vector, but operand is not");
                }
                if (operand_scalar_ty.ptrAddressSpace(zcu) != result_scalar_ty.ptrAddressSpace(zcu)) {
                    return verify.fail("illegal change to address space");
                }
            },
            .ptr_from_int => {
                const ty_op = data[@intFromEnum(inst)].ty_op;
                const operand_ty = air.typeOf(ty_op.operand, ip);
                const result_ty = ty_op.ty.toType();
                const operand_scalar_ty = operand_ty.scalarType(zcu);
                const result_scalar_ty = result_ty.scalarType(zcu);
                if (operand_scalar_ty.toIntern() != .usize_type) return verify.fail("bad operand type");
                if (!result_scalar_ty.isPtrAtRuntime(zcu)) return verify.fail("bad result type");
                if (operand_ty.isVector(zcu) and !result_ty.isVector(zcu)) return verify.fail("operand is vector, but result is not");
                if (!operand_ty.isVector(zcu) and result_ty.isVector(zcu)) return verify.fail("result is vector, but operand is not");
            },
            .int_from_ptr => {
                const ty_op = data[@intFromEnum(inst)].ty_op;
                const operand_ty = air.typeOf(ty_op.operand, ip);
                const result_ty = ty_op.ty.toType();
                const operand_scalar_ty = operand_ty.scalarType(zcu);
                const result_scalar_ty = result_ty.scalarType(zcu);
                if (!operand_scalar_ty.isPtrAtRuntime(zcu)) return verify.fail("bad operand type");
                if (result_scalar_ty.toIntern() != .usize_type) return verify.fail("bad result type");
                if (operand_ty.isVector(zcu) and !result_ty.isVector(zcu)) return verify.fail("operand is vector, but result is not");
                if (!operand_ty.isVector(zcu) and result_ty.isVector(zcu)) return verify.fail("result is vector, but operand is not");
            },
            .error_cast => {
                const ty_op = data[@intFromEnum(inst)].ty_op;
                const operand_ty = air.typeOf(ty_op.operand, ip);
                const result_ty = ty_op.ty.toType();
                switch (operand_ty.zigTypeTag(zcu)) {
                    else => return verify.fail("bad operand type"),
                    .error_union => {
                        if (result_ty.zigTypeTag(zcu) != .error_union) {
                            return verify.fail("operand is error union, but result is not");
                        }
                        if (operand_ty.errorUnionPayload(zcu).toIntern() != result_ty.errorUnionPayload(zcu).toIntern()) {
                            return verify.fail("error union payload type differs");
                        }
                    },
                    .error_set => if (result_ty.zigTypeTag(zcu) != .error_set) {
                        return verify.fail("operand is error set, but result is not");
                    },
                }
            },
            .error_from_int => {
                const ty_op = data[@intFromEnum(inst)].ty_op;
                const operand_ty = air.typeOf(ty_op.operand, ip);
                const result_ty = ty_op.ty.toType();
                if (!operand_ty.isUnsignedInt(zcu)) return verify.fail("bad operand type");
                if (operand_ty.bitSize(zcu) != zcu.errorSetBits()) return verify.fail("bad operand bit size");
                if (result_ty.zigTypeTag(zcu) != .error_set) return verify.fail("bad result type");
            },
            .int_from_error => {
                const ty_op = data[@intFromEnum(inst)].ty_op;
                const operand_ty = air.typeOf(ty_op.operand, ip);
                const result_ty = ty_op.ty.toType();
                if (operand_ty.zigTypeTag(zcu) != .error_set) return verify.fail("bad operand type");
                if (!result_ty.isUnsignedInt(zcu)) return verify.fail("bad result type");
                if (result_ty.bitSize(zcu) != zcu.errorSetBits()) return verify.fail("bad result bit size");
            },
            .union_from_enum => {
                const ty_op = data[@intFromEnum(inst)].ty_op;
                const operand_ty = air.typeOf(ty_op.operand, ip);
                const result_ty = ty_op.ty.toType();
                if (operand_ty.zigTypeTag(zcu) != .@"enum") return verify.fail("bad operand type");
                if (result_ty.zigTypeTag(zcu) != .@"union") return verify.fail("bad result type");
                const union_tag_ty = result_ty.unionTagType(zcu) orelse return verify.fail("union type is not tagged");
                if (union_tag_ty.toIntern() != operand_ty.toIntern()) return verify.fail("union tag type does not match operand type");
            },

            .ptr_elem_ptr => {
                const ty_pl = data[@intFromEnum(inst)].ty_pl;
                const bin_op = air.extraData(Air.Bin, ty_pl.payload).data;
                const ptr_ty = air.typeOf(bin_op.lhs, ip);
                const result_ty = ty_pl.ty.toType();
                if (ptr_ty.zigTypeTag(zcu) != .pointer) return verify.fail("bad pointer type");
                if (result_ty.zigTypeTag(zcu) != .pointer) return verify.fail("bad result type");
                const ptr_info = ptr_ty.ptrInfo(zcu);
                const result_ptr_info = result_ty.ptrInfo(zcu);
                if (ptr_info.packed_offset.host_size != 0) return verify.fail("pointer type is bitpacked pointer");
                if (result_ptr_info.packed_offset.host_size != 0) return verify.fail("result type is bitpacked pointer");
            },

            .arg,
            .add,
            .add_safe,
            .add_optimized,
            .add_wrap,
            .add_sat,
            .sub,
            .sub_safe,
            .sub_optimized,
            .sub_wrap,
            .sub_sat,
            .mul,
            .mul_safe,
            .mul_optimized,
            .mul_wrap,
            .mul_sat,
            .div_float,
            .div_float_optimized,
            .div_trunc,
            .div_trunc_optimized,
            .div_floor,
            .div_floor_optimized,
            .div_exact,
            .div_exact_optimized,
            .rem,
            .rem_optimized,
            .mod,
            .mod_optimized,
            .ptr_add,
            .ptr_sub,
            .max,
            .min,
            .add_with_overflow,
            .sub_with_overflow,
            .mul_with_overflow,
            .shl_with_overflow,
            .alloc,
            .inferred_alloc,
            .inferred_alloc_comptime,
            .ret_ptr,
            .assembly,
            .bit_and,
            .bit_or,
            .shr,
            .shr_exact,
            .shl,
            .shl_exact,
            .shl_sat,
            .xor,
            .not,
            .repeat,
            .br,
            .trap,
            .breakpoint,
            .ret_addr,
            .frame_addr,
            .call,
            .call_always_tail,
            .call_never_tail,
            .call_never_inline,
            .clz,
            .ctz,
            .popcount,
            .byte_swap,
            .bit_reverse,
            .sqrt,
            .sin,
            .cos,
            .tan,
            .exp,
            .exp2,
            .log,
            .log2,
            .log10,
            .abs,
            .floor,
            .ceil,
            .round,
            .trunc_float,
            .neg,
            .neg_optimized,
            .cmp_lt,
            .cmp_lt_optimized,
            .cmp_lte,
            .cmp_lte_optimized,
            .cmp_eq,
            .cmp_eq_optimized,
            .cmp_gte,
            .cmp_gte_optimized,
            .cmp_gt,
            .cmp_gt_optimized,
            .cmp_neq,
            .cmp_neq_optimized,
            .cmp_vector,
            .cmp_vector_optimized,
            .switch_dispatch,
            .dbg_stmt,
            .dbg_empty_stmt,
            .dbg_var_ptr,
            .dbg_var_val,
            .dbg_arg_inline,
            .is_null,
            .is_non_null,
            .is_null_ptr,
            .is_non_null_ptr,
            .is_err,
            .is_non_err,
            .is_err_ptr,
            .is_non_err_ptr,
            .load,
            .store,
            .store_safe,
            .unreach,
            .fptrunc,
            .fpext,
            .int_cast,
            .int_cast_safe,
            .trunc,
            .optional_payload,
            .optional_payload_ptr,
            .optional_payload_ptr_set,
            .wrap_optional,
            .unwrap_errunion_payload,
            .unwrap_errunion_err,
            .unwrap_errunion_payload_ptr,
            .unwrap_errunion_err_ptr,
            .errunion_payload_ptr_set,
            .wrap_errunion_payload,
            .wrap_errunion_err,
            .struct_field_ptr,
            .struct_field_ptr_index_0,
            .struct_field_ptr_index_1,
            .struct_field_ptr_index_2,
            .struct_field_ptr_index_3,
            .agg_field_val,
            .set_union_tag,
            .get_union_tag,
            .slice,
            .slice_len,
            .slice_ptr,
            .ptr_slice_len_ptr,
            .ptr_slice_ptr_ptr,
            .array_elem_val,
            .slice_elem_val,
            .slice_elem_ptr,
            .ptr_elem_val,
            .array_to_slice,
            .int_from_float,
            .int_from_float_optimized,
            .int_from_float_safe,
            .int_from_float_optimized_safe,
            .float_from_int,
            .reduce,
            .reduce_optimized,
            .splat,
            .shuffle_one,
            .shuffle_two,
            .select,
            .memset,
            .memset_safe,
            .memcpy,
            .memmove,
            .cmpxchg_weak,
            .cmpxchg_strong,
            .atomic_load,
            .atomic_store_unordered,
            .atomic_store_monotonic,
            .atomic_store_release,
            .atomic_store_seq_cst,
            .atomic_rmw,
            .is_named_enum_value,
            .tag_name,
            .error_name,
            .error_set_has_value,
            .aggregate_init,
            .union_init,
            .prefetch,
            .mul_add,
            .field_parent_ptr,
            .wasm_memory_size,
            .wasm_memory_grow,
            .cmp_lte_errors_len,
            .err_return_trace,
            .set_err_return_trace,
            .addrspace_cast,
            .save_err_return_trace_index,
            .runtime_nav_ptr,
            .c_va_arg,
            .c_va_copy,
            .c_va_end,
            .c_va_start,
            .spirv_runtime_array_len,
            .work_item_id,
            .work_group_size,
            .work_group_id,
            .legalize_vec_store_elem,
            .legalize_vec_elem_val,
            .legalize_compiler_rt_call,
            => {},
        }
        if (air.typeOfIndex(inst, ip).isNoReturn(zcu)) {
            if (body_index == body_insts.len - 1) return;

            // HACK: right now, we emit the safety check for noreturn functions returning in a weird
            // way, where the `call` instruction is `noreturn` but there are still instructions
            // following it. We need to figure out a better way to represent that! That safety check
            // probably just needs to live exclusively in backends; putting AIR instructions after a
            // call implies that we have e.g. a valid stack at that point, which we can't actually
            // assume when the user has gotten a function's ABI wrong.
            switch (tags[@intFromEnum(inst)]) {
                .call,
                .call_always_tail,
                .call_never_tail,
                .call_never_inline,
                => continue,
                else => {},
            }

            return verify.fail("body contains instructions after noreturn");
        }
    }
    return verify.fail("body does not terminate noreturn");
}

const std = @import("std");
const log = std.log.scoped(.air_verify);

const Zcu = @import("../Zcu.zig");
const InternPool = @import("../InternPool.zig");
const Air = @import("../Air.zig");
const Type = @import("../Type.zig");
const Value = @import("../Value.zig");
