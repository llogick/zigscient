const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const CodeGen = @import("CodeGen.zig");
const Mir = @import("Mir.zig");

pub const LocalMap = std.array_hash_map.String(u32);

pub fn assemble(
    cg: *CodeGen,
    source: [:0]const u8,
    local_map: *const LocalMap,
) !void {
    var line_it = mem.tokenizeAny(u8, source, "\n\r;");
    next_line: while (line_it.next()) |line| {
        var word_it = mem.tokenizeAny(u8, line, " \t");
        const inst = word_it.next() orelse continue :next_line;

        if (mem.eql(u8, inst, "unreachable")) {
            try cg.addTag(.@"unreachable");
        } else if (mem.eql(u8, inst, "block")) {
            try cg.addTag(.block);
        } else if (mem.eql(u8, inst, "loop")) {
            try cg.addTag(.loop);
        } else if (mem.eql(u8, inst, "end")) {
            try cg.addTag(.end);
        } else if (mem.eql(u8, inst, "br")) {
            const label = try parseLabel(cg, inst, &word_it);
            try cg.addLabel(.br, label);
        } else if (mem.eql(u8, inst, "br_if")) {
            const label = try parseLabel(cg, inst, &word_it);
            try cg.addLabel(.br_if, label);
        } else if (mem.eql(u8, inst, "return")) {
            try cg.addTag(.@"return");
        } else if (mem.eql(u8, inst, "drop")) {
            try cg.addTag(.drop);
        } else if (mem.eql(u8, inst, "select")) {
            try cg.addTag(.select);
        } else if (mem.eql(u8, inst, "local.get")) {
            const local = try parseLocalArg(cg, inst, &word_it, local_map);
            try cg.addLocal(.local_get, local);
        } else if (mem.eql(u8, inst, "local.set")) {
            const local = try parseLocalArg(cg, inst, &word_it, local_map);
            try cg.addLocal(.local_set, local);
        } else if (mem.eql(u8, inst, "local.tee")) {
            const local = try parseLocalArg(cg, inst, &word_it, local_map);
            try cg.addLocal(.local_tee, local);
        } else if (mem.eql(u8, inst, "i32.load")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i32_load, mem_arg);
        } else if (mem.eql(u8, inst, "i64.load")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i64_load, mem_arg);
        } else if (mem.eql(u8, inst, "f32.load")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.f32_load, mem_arg);
        } else if (mem.eql(u8, inst, "f64.load")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.f64_load, mem_arg);
        } else if (mem.eql(u8, inst, "i32.load8_s")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i32_load8_s, mem_arg);
        } else if (mem.eql(u8, inst, "i32.load8_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i32_load8_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.load16_s")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i32_load16_s, mem_arg);
        } else if (mem.eql(u8, inst, "i32.load16_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i32_load16_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.load8_s")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i64_load8_s, mem_arg);
        } else if (mem.eql(u8, inst, "i64.load8_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i64_load8_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.load16_s")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i64_load16_s, mem_arg);
        } else if (mem.eql(u8, inst, "i64.load16_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i64_load16_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.load32_s")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i64_load32_s, mem_arg);
        } else if (mem.eql(u8, inst, "i64.load32_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i64_load32_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.store")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i32_store, mem_arg);
        } else if (mem.eql(u8, inst, "i64.store")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i64_store, mem_arg);
        } else if (mem.eql(u8, inst, "f32.store")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.f32_store, mem_arg);
        } else if (mem.eql(u8, inst, "f64.store")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.f64_store, mem_arg);
        } else if (mem.eql(u8, inst, "i32.store8")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i32_store8, mem_arg);
        } else if (mem.eql(u8, inst, "i32.store16")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i32_store16, mem_arg);
        } else if (mem.eql(u8, inst, "i64.store8")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i64_store8, mem_arg);
        } else if (mem.eql(u8, inst, "i64.store16")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i64_store16, mem_arg);
        } else if (mem.eql(u8, inst, "i64.store32")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addMemArg(.i64_store32, mem_arg);
        } else if (mem.eql(u8, inst, "memory.size")) {
            try cg.addLabel(.memory_size, 0);
        } else if (mem.eql(u8, inst, "memory.grow")) {
            try cg.addLabel(.memory_grow, 0);
        } else if (mem.eql(u8, inst, "i32.const")) {
            const value = try parseInt(i32, cg, inst, &word_it);
            try cg.addImm32(@bitCast(value));
        } else if (mem.eql(u8, inst, "i64.const")) {
            const value = try parseInt(i64, cg, inst, &word_it);
            try cg.addImm64(@bitCast(value));
        } else if (mem.eql(u8, inst, "f32.const")) {
            const value = try parseFloat(f32, cg, inst, &word_it);
            try cg.addFloat32(value);
        } else if (mem.eql(u8, inst, "f64.const")) {
            const value = try parseFloat(f64, cg, inst, &word_it);
            try cg.addFloat64(value);
        } else if (mem.eql(u8, inst, "i32.eqz")) {
            try cg.addTag(.i32_eqz);
        } else if (mem.eql(u8, inst, "i32.eq")) {
            try cg.addTag(.i32_eq);
        } else if (mem.eql(u8, inst, "i32.ne")) {
            try cg.addTag(.i32_ne);
        } else if (mem.eql(u8, inst, "i32.lt_s")) {
            try cg.addTag(.i32_lt_s);
        } else if (mem.eql(u8, inst, "i32.lt_u")) {
            try cg.addTag(.i32_lt_u);
        } else if (mem.eql(u8, inst, "i32.gt_s")) {
            try cg.addTag(.i32_gt_s);
        } else if (mem.eql(u8, inst, "i32.gt_u")) {
            try cg.addTag(.i32_gt_u);
        } else if (mem.eql(u8, inst, "i32.le_s")) {
            try cg.addTag(.i32_le_s);
        } else if (mem.eql(u8, inst, "i32.le_u")) {
            try cg.addTag(.i32_le_u);
        } else if (mem.eql(u8, inst, "i32.ge_s")) {
            try cg.addTag(.i32_ge_s);
        } else if (mem.eql(u8, inst, "i32.ge_u")) {
            try cg.addTag(.i32_ge_u);
        } else if (mem.eql(u8, inst, "i64.eqz")) {
            try cg.addTag(.i64_eqz);
        } else if (mem.eql(u8, inst, "i64.eq")) {
            try cg.addTag(.i64_eq);
        } else if (mem.eql(u8, inst, "i64.ne")) {
            try cg.addTag(.i64_ne);
        } else if (mem.eql(u8, inst, "i64.lt_s")) {
            try cg.addTag(.i64_lt_s);
        } else if (mem.eql(u8, inst, "i64.lt_u")) {
            try cg.addTag(.i64_lt_u);
        } else if (mem.eql(u8, inst, "i64.gt_s")) {
            try cg.addTag(.i64_gt_s);
        } else if (mem.eql(u8, inst, "i64.gt_u")) {
            try cg.addTag(.i64_gt_u);
        } else if (mem.eql(u8, inst, "i64.le_s")) {
            try cg.addTag(.i64_le_s);
        } else if (mem.eql(u8, inst, "i64.le_u")) {
            try cg.addTag(.i64_le_u);
        } else if (mem.eql(u8, inst, "i64.ge_s")) {
            try cg.addTag(.i64_ge_s);
        } else if (mem.eql(u8, inst, "i64.ge_u")) {
            try cg.addTag(.i64_ge_u);
        } else if (mem.eql(u8, inst, "f32.eq")) {
            try cg.addTag(.f32_eq);
        } else if (mem.eql(u8, inst, "f32.ne")) {
            try cg.addTag(.f32_ne);
        } else if (mem.eql(u8, inst, "f32.lt")) {
            try cg.addTag(.f32_lt);
        } else if (mem.eql(u8, inst, "f32.gt")) {
            try cg.addTag(.f32_gt);
        } else if (mem.eql(u8, inst, "f32.le")) {
            try cg.addTag(.f32_le);
        } else if (mem.eql(u8, inst, "f32.ge")) {
            try cg.addTag(.f32_ge);
        } else if (mem.eql(u8, inst, "f64.eq")) {
            try cg.addTag(.f64_eq);
        } else if (mem.eql(u8, inst, "f64.ne")) {
            try cg.addTag(.f64_ne);
        } else if (mem.eql(u8, inst, "f64.lt")) {
            try cg.addTag(.f64_lt);
        } else if (mem.eql(u8, inst, "f64.gt")) {
            try cg.addTag(.f64_gt);
        } else if (mem.eql(u8, inst, "f64.le")) {
            try cg.addTag(.f64_le);
        } else if (mem.eql(u8, inst, "f64.ge")) {
            try cg.addTag(.f64_ge);
        } else if (mem.eql(u8, inst, "i32.clz")) {
            try cg.addTag(.i32_clz);
        } else if (mem.eql(u8, inst, "i32.ctz")) {
            try cg.addTag(.i32_ctz);
        } else if (mem.eql(u8, inst, "i32.popcnt")) {
            try cg.addTag(.i32_popcnt);
        } else if (mem.eql(u8, inst, "i32.add")) {
            try cg.addTag(.i32_add);
        } else if (mem.eql(u8, inst, "i32.sub")) {
            try cg.addTag(.i32_sub);
        } else if (mem.eql(u8, inst, "i32.mul")) {
            try cg.addTag(.i32_mul);
        } else if (mem.eql(u8, inst, "i32.div_s")) {
            try cg.addTag(.i32_div_s);
        } else if (mem.eql(u8, inst, "i32.div_u")) {
            try cg.addTag(.i32_div_u);
        } else if (mem.eql(u8, inst, "i32.rem_s")) {
            try cg.addTag(.i32_rem_s);
        } else if (mem.eql(u8, inst, "i32.rem_u")) {
            try cg.addTag(.i32_rem_u);
        } else if (mem.eql(u8, inst, "i32.and")) {
            try cg.addTag(.i32_and);
        } else if (mem.eql(u8, inst, "i32.or")) {
            try cg.addTag(.i32_or);
        } else if (mem.eql(u8, inst, "i32.xor")) {
            try cg.addTag(.i32_xor);
        } else if (mem.eql(u8, inst, "i32.shl")) {
            try cg.addTag(.i32_shl);
        } else if (mem.eql(u8, inst, "i32.shr_s")) {
            try cg.addTag(.i32_shr_s);
        } else if (mem.eql(u8, inst, "i32.shr_u")) {
            try cg.addTag(.i32_shr_u);
        } else if (mem.eql(u8, inst, "i64.clz")) {
            try cg.addTag(.i64_clz);
        } else if (mem.eql(u8, inst, "i64.ctz")) {
            try cg.addTag(.i64_ctz);
        } else if (mem.eql(u8, inst, "i64.popcnt")) {
            try cg.addTag(.i64_popcnt);
        } else if (mem.eql(u8, inst, "i64.add")) {
            try cg.addTag(.i64_add);
        } else if (mem.eql(u8, inst, "i64.sub")) {
            try cg.addTag(.i64_sub);
        } else if (mem.eql(u8, inst, "i64.mul")) {
            try cg.addTag(.i64_mul);
        } else if (mem.eql(u8, inst, "i64.div_s")) {
            try cg.addTag(.i64_div_s);
        } else if (mem.eql(u8, inst, "i64.div_u")) {
            try cg.addTag(.i64_div_u);
        } else if (mem.eql(u8, inst, "i64.rem_s")) {
            try cg.addTag(.i64_rem_s);
        } else if (mem.eql(u8, inst, "i64.rem_u")) {
            try cg.addTag(.i64_rem_u);
        } else if (mem.eql(u8, inst, "i64.and")) {
            try cg.addTag(.i64_and);
        } else if (mem.eql(u8, inst, "i64.or")) {
            try cg.addTag(.i64_or);
        } else if (mem.eql(u8, inst, "i64.xor")) {
            try cg.addTag(.i64_xor);
        } else if (mem.eql(u8, inst, "i64.shl")) {
            try cg.addTag(.i64_shl);
        } else if (mem.eql(u8, inst, "i64.shr_s")) {
            try cg.addTag(.i64_shr_s);
        } else if (mem.eql(u8, inst, "i64.shr_u")) {
            try cg.addTag(.i64_shr_u);
        } else if (mem.eql(u8, inst, "f32.abs")) {
            try cg.addTag(.f32_abs);
        } else if (mem.eql(u8, inst, "f32.neg")) {
            try cg.addTag(.f32_neg);
        } else if (mem.eql(u8, inst, "f32.ceil")) {
            try cg.addTag(.f32_ceil);
        } else if (mem.eql(u8, inst, "f32.floor")) {
            try cg.addTag(.f32_floor);
        } else if (mem.eql(u8, inst, "f32.trunc")) {
            try cg.addTag(.f32_trunc);
        } else if (mem.eql(u8, inst, "f32.nearest")) {
            try cg.addTag(.f32_nearest);
        } else if (mem.eql(u8, inst, "f32.sqrt")) {
            try cg.addTag(.f32_sqrt);
        } else if (mem.eql(u8, inst, "f32.add")) {
            try cg.addTag(.f32_add);
        } else if (mem.eql(u8, inst, "f32.sub")) {
            try cg.addTag(.f32_sub);
        } else if (mem.eql(u8, inst, "f32.mul")) {
            try cg.addTag(.f32_mul);
        } else if (mem.eql(u8, inst, "f32.div")) {
            try cg.addTag(.f32_div);
        } else if (mem.eql(u8, inst, "f32.min")) {
            try cg.addTag(.f32_min);
        } else if (mem.eql(u8, inst, "f32.max")) {
            try cg.addTag(.f32_max);
        } else if (mem.eql(u8, inst, "f32.copysign")) {
            try cg.addTag(.f32_copysign);
        } else if (mem.eql(u8, inst, "f64.abs")) {
            try cg.addTag(.f64_abs);
        } else if (mem.eql(u8, inst, "f64.neg")) {
            try cg.addTag(.f64_neg);
        } else if (mem.eql(u8, inst, "f64.ceil")) {
            try cg.addTag(.f64_ceil);
        } else if (mem.eql(u8, inst, "f64.floor")) {
            try cg.addTag(.f64_floor);
        } else if (mem.eql(u8, inst, "f64.trunc")) {
            try cg.addTag(.f64_trunc);
        } else if (mem.eql(u8, inst, "f64.nearest")) {
            try cg.addTag(.f64_nearest);
        } else if (mem.eql(u8, inst, "f64.sqrt")) {
            try cg.addTag(.f64_sqrt);
        } else if (mem.eql(u8, inst, "f64.add")) {
            try cg.addTag(.f64_add);
        } else if (mem.eql(u8, inst, "f64.sub")) {
            try cg.addTag(.f64_sub);
        } else if (mem.eql(u8, inst, "f64.mul")) {
            try cg.addTag(.f64_mul);
        } else if (mem.eql(u8, inst, "f64.div")) {
            try cg.addTag(.f64_div);
        } else if (mem.eql(u8, inst, "f64.min")) {
            try cg.addTag(.f64_min);
        } else if (mem.eql(u8, inst, "f64.max")) {
            try cg.addTag(.f64_max);
        } else if (mem.eql(u8, inst, "f64.copysign")) {
            try cg.addTag(.f64_copysign);
        } else if (mem.eql(u8, inst, "i32.wrap_i64")) {
            try cg.addTag(.i32_wrap_i64);
        } else if (mem.eql(u8, inst, "i32.trunc_f32_s")) {
            try cg.addTag(.i32_trunc_f32_s);
        } else if (mem.eql(u8, inst, "i32.trunc_f32_u")) {
            try cg.addTag(.i32_trunc_f32_u);
        } else if (mem.eql(u8, inst, "i32.trunc_f64_s")) {
            try cg.addTag(.i32_trunc_f64_s);
        } else if (mem.eql(u8, inst, "i32.trunc_f64_u")) {
            try cg.addTag(.i32_trunc_f64_u);
        } else if (mem.eql(u8, inst, "i64.extend_i32_s")) {
            try cg.addTag(.i64_extend_i32_s);
        } else if (mem.eql(u8, inst, "i64.extend_i32_u")) {
            try cg.addTag(.i64_extend_i32_u);
        } else if (mem.eql(u8, inst, "i64.trunc_f32_s")) {
            try cg.addTag(.i64_trunc_f32_s);
        } else if (mem.eql(u8, inst, "i64.trunc_f32_u")) {
            try cg.addTag(.i64_trunc_f32_u);
        } else if (mem.eql(u8, inst, "i64.trunc_f64_s")) {
            try cg.addTag(.i64_trunc_f64_s);
        } else if (mem.eql(u8, inst, "i64.trunc_f64_u")) {
            try cg.addTag(.i64_trunc_f64_u);
        } else if (mem.eql(u8, inst, "f32.convert_i32_s")) {
            try cg.addTag(.f32_convert_i32_s);
        } else if (mem.eql(u8, inst, "f32.convert_i32_u")) {
            try cg.addTag(.f32_convert_i32_u);
        } else if (mem.eql(u8, inst, "f32.convert_i64_s")) {
            try cg.addTag(.f32_convert_i64_s);
        } else if (mem.eql(u8, inst, "f32.convert_i64_u")) {
            try cg.addTag(.f32_convert_i64_u);
        } else if (mem.eql(u8, inst, "f32.demote_f64")) {
            try cg.addTag(.f32_demote_f64);
        } else if (mem.eql(u8, inst, "f64.convert_i32_s")) {
            try cg.addTag(.f64_convert_i32_s);
        } else if (mem.eql(u8, inst, "f64.convert_i32_u")) {
            try cg.addTag(.f64_convert_i32_u);
        } else if (mem.eql(u8, inst, "f64.convert_i64_s")) {
            try cg.addTag(.f64_convert_i64_s);
        } else if (mem.eql(u8, inst, "f64.convert_i64_u")) {
            try cg.addTag(.f64_convert_i64_u);
        } else if (mem.eql(u8, inst, "f64.promote_f32")) {
            try cg.addTag(.f64_promote_f32);
        } else if (mem.eql(u8, inst, "i32.reinterpret_f32")) {
            try cg.addTag(.i32_reinterpret_f32);
        } else if (mem.eql(u8, inst, "i64.reinterpret_f64")) {
            try cg.addTag(.i64_reinterpret_f64);
        } else if (mem.eql(u8, inst, "f32.reinterpret_i32")) {
            try cg.addTag(.f32_reinterpret_i32);
        } else if (mem.eql(u8, inst, "f64.reinterpret_i64")) {
            try cg.addTag(.f64_reinterpret_i64);
        } else if (mem.eql(u8, inst, "i32.extend8_s")) {
            try cg.addTag(.i32_extend8_s);
        } else if (mem.eql(u8, inst, "i32.extend16_s")) {
            try cg.addTag(.i32_extend16_s);
        } else if (mem.eql(u8, inst, "i64.extend8_s")) {
            try cg.addTag(.i64_extend8_s);
        } else if (mem.eql(u8, inst, "i64.extend16_s")) {
            try cg.addTag(.i64_extend16_s);
        } else if (mem.eql(u8, inst, "i64.extend32_s")) {
            try cg.addTag(.i64_extend32_s);
        } else if (mem.eql(u8, inst, "i32.trunc_sat_f32_s")) {
            try cg.addExtended(.i32_trunc_sat_f32_s);
        } else if (mem.eql(u8, inst, "i32.trunc_sat_f32_u")) {
            try cg.addExtended(.i32_trunc_sat_f32_u);
        } else if (mem.eql(u8, inst, "i32.trunc_sat_f64_s")) {
            try cg.addExtended(.i32_trunc_sat_f64_s);
        } else if (mem.eql(u8, inst, "i32.trunc_sat_f64_u")) {
            try cg.addExtended(.i32_trunc_sat_f64_u);
        } else if (mem.eql(u8, inst, "i64.trunc_sat_f32_s")) {
            try cg.addExtended(.i64_trunc_sat_f32_s);
        } else if (mem.eql(u8, inst, "i64.trunc_sat_f32_u")) {
            try cg.addExtended(.i64_trunc_sat_f32_u);
        } else if (mem.eql(u8, inst, "i64.trunc_sat_f64_s")) {
            try cg.addExtended(.i64_trunc_sat_f64_s);
        } else if (mem.eql(u8, inst, "i64.trunc_sat_f64_u")) {
            try cg.addExtended(.i64_trunc_sat_f64_u);
        } else if (mem.eql(u8, inst, "memory.init")) {
            try cg.addExtended(.memory_init);
        } else if (mem.eql(u8, inst, "data.drop")) {
            try cg.addExtended(.data_drop);
        } else if (mem.eql(u8, inst, "memory.copy")) {
            const str1 = word_it.next();
            if (str1 == null or !mem.eql(u8, str1.?, "0,")) {
                return cg.fail("Self-hosted backend requires memory.copy be in form of \"memory.copy 0, 0\"", .{});
            }
            const str2 = word_it.next();
            if (str2 == null or !mem.eql(u8, str2.?, "0")) {
                return cg.fail("Self-hosted backend requires memory.copy be in form of \"memory.copy 0, 0\"", .{});
            }
            try cg.addExtended(.memory_copy);
        } else if (mem.eql(u8, inst, "memory.fill")) {
            const str = word_it.next();
            if (str == null or !mem.eql(u8, str.?, "0")) {
                return cg.fail("Self-hosted backend requires memory.fill be in form of \"memory.fill 0\"", .{});
            }
            try cg.addExtended(.memory_fill);
        } else if (mem.eql(u8, inst, "table.init")) {
            try cg.addExtended(.table_init);
        } else if (mem.eql(u8, inst, "elem.drop")) {
            try cg.addExtended(.elem_drop);
        } else if (mem.eql(u8, inst, "table.copy")) {
            try cg.addExtended(.table_copy);
        } else if (mem.eql(u8, inst, "table.grow")) {
            try cg.addExtended(.table_grow);
        } else if (mem.eql(u8, inst, "table.size")) {
            try cg.addExtended(.table_size);
        } else if (mem.eql(u8, inst, "table.fill")) {
            try cg.addExtended(.table_fill);
        } else if (mem.eql(u8, inst, "memory.atomic.notify")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.memory_atomic_notify, mem_arg);
        } else if (mem.eql(u8, inst, "memory.atomic.wait32")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.memory_atomic_wait32, mem_arg);
        } else if (mem.eql(u8, inst, "memory.atomic.wait64")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.memory_atomic_wait64, mem_arg);
        } else if (mem.eql(u8, inst, "atomic.fence")) {
            try cg.addAtomicTag(.atomic_fence);
        } else if (mem.eql(u8, inst, "i32.atomic.load")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_load, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.load")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_load, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.load8_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_load8_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.load16_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_load16_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.load8_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_load8_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.load16_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_load16_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.load32_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_load32_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.store")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_store, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.store")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_store, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.store8")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_store8, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.store16")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_store16, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.store8")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_store8, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.store16")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_store16, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.store32")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_store32, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw.add")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw_add, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw.add")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw_add, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw8.add_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw8_add_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw16.add_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw16_add_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw8.add_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw8_add_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw16.add_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw16_add_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw32.add_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw32_add_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw.sub")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw_sub, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw.sub")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw_sub, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw8.sub_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw8_sub_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw16.sub_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw16_sub_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw8.sub_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw8_sub_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw16.sub_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw16_sub_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw32.sub_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw32_sub_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw.and")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw_and, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw.and")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw_and, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw8.and_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw8_and_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw16.and_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw16_and_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw8.and_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw8_and_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw16.and_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw16_and_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw32.and_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw32_and_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw.or")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw_or, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw.or")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw_or, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw8.or_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw8_or_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw16.or_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw16_or_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw8.or_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw8_or_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw16.or_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw16_or_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw32.or_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw32_or_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw.xor")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw_xor, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw.xor")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw_xor, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw8.xor_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw8_xor_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw16.xor_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw16_xor_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw8.xor_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw8_xor_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw16.xor_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw16_xor_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw32.xor_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw32_xor_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw.xchg")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw_xchg, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw.xchg")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw_xchg, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw8.xchg_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw8_xchg_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw16.xchg_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw16_xchg_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw8.xchg_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw8_xchg_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw16.xchg_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw16_xchg_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw32.xchg_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw32_xchg_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw.cmpxchg")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw_cmpxchg, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw.cmpxchg")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw_cmpxchg, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw8.cmpxchg_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw8_cmpxchg_u, mem_arg);
        } else if (mem.eql(u8, inst, "i32.atomic.rmw16.cmpxchg_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i32_atomic_rmw16_cmpxchg_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw8.cmpxchg_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw8_cmpxchg_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw16.cmpxchg_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw16_cmpxchg_u, mem_arg);
        } else if (mem.eql(u8, inst, "i64.atomic.rmw32.cmpxchg_u")) {
            const mem_arg = try parseMemArg(cg, inst, &word_it);
            try cg.addAtomicMemArg(.i64_atomic_rmw32_cmpxchg_u, mem_arg);
        } else {
            if (mem.startsWith(u8, inst, "#")) continue :next_line;
            if (mem.startsWith(u8, inst, "//")) continue :next_line;

            return cg.fail("Malformed assembly, unknown instruction \"{s}\"", .{inst});
        }

        const remaining = word_it.next() orelse continue :next_line;
        if (mem.startsWith(u8, inst, "#")) continue :next_line;
        if (mem.startsWith(u8, inst, "//")) continue :next_line;
        return cg.fail("Malformed assembly, unknown string after instruction \"{s}\"", .{remaining});
    }
}

fn parseLocalArg(
    cg: *CodeGen,
    inst: []const u8,
    word_it: *mem.TokenIterator(u8, .any),
    local_map: *const LocalMap,
) !u32 {
    const arg = word_it.next() orelse {
        return cg.fail("Malformed assembly, argument not found for \"{s}\"", .{inst});
    };
    if (arg.len < 3 or arg[0] != '%' or arg[1] != '[' or arg[arg.len - 1] != ']') {
        const local = std.fmt.parseInt(u32, arg, 0) catch {
            return cg.fail("Malformed assembly, malformed argument \"{s}\"", .{arg});
        };
        return local;
    }
    const name = arg[2 .. arg.len - 1];
    return local_map.get(name) orelse {
        return cg.fail("Malformed assembly, unknown name \"{s}\"", .{name});
    };
}

fn parseLabel(cg: *CodeGen, inst: []const u8, word_it: *mem.TokenIterator(u8, .any)) !u32 {
    const label_str = word_it.next() orelse {
        return cg.fail("Malformed assembly, label not found for \"{s}\"", .{inst});
    };
    const label = std.fmt.parseInt(u32, label_str, 0) catch {
        return cg.fail("Malformed assembly, malformed label \"{s}\"", .{label_str});
    };
    return label;
}

fn parseMemArg(cg: *CodeGen, inst: []const u8, word_it: *mem.TokenIterator(u8, .any)) !Mir.MemArg {
    const mem_arg_str = word_it.next() orelse {
        return cg.fail("Malformed assembly, memory argument not found for \"{s}\"", .{inst});
    };
    if (mem.cut(u8, mem_arg_str, ":p2align=")) |oa| {
        const offset_str = oa[0];
        const alignment_str = oa[1];

        const offset = std.fmt.parseInt(i32, offset_str, 0) catch {
            return cg.fail("Malformed assembly, malformed offset \"{s}\"", .{offset_str});
        };
        const alignment_p2 = std.fmt.parseInt(u5, alignment_str, 0) catch {
            return cg.fail("Malformed assembly, malformed offset \"{s}\"", .{alignment_str});
        };

        return .{ .offset = @bitCast(offset), .alignment = @as(u32, 1) << alignment_p2 };
    } else {
        const offset_str = mem_arg_str;
        const offset = std.fmt.parseInt(i32, offset_str, 0) catch {
            return cg.fail("Malformed assembly, malformed offset \"{s}\"", .{offset_str});
        };
        return .{ .offset = @bitCast(offset), .alignment = 1 };
    }
}

fn parseInt(comptime T: type, cg: *CodeGen, inst: []const u8, word_it: *mem.TokenIterator(u8, .any)) !T {
    const value_str = word_it.next() orelse {
        return cg.fail("Malformed assembly, value not found for \"{s}\"", .{inst});
    };
    const value = std.fmt.parseInt(T, value_str, 0) catch {
        return cg.fail("Malformed assembly, malformed integer value \"{s}\"", .{value_str});
    };
    return value;
}

fn parseFloat(comptime T: type, cg: *CodeGen, inst: []const u8, word_it: *mem.TokenIterator(u8, .any)) !T {
    const value_str = word_it.next() orelse {
        return cg.fail("Malformed assembly, value not found for \"{s}\"", .{inst});
    };
    const value = std.fmt.parseFloat(T, value_str) catch {
        return cg.fail("Malformed assembly, malformed float value \"{s}\"", .{value_str});
    };
    return value;
}
