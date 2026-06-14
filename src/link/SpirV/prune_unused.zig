const std = @import("std");
const BinaryModule = @import("BinaryModule.zig");
const spec = @import("../../codegen/spirv/spec.zig");
const Opcode = spec.Opcode;
const ResultId = spec.Id;
const Word = spec.Word;

pub fn run(parser: *BinaryModule.Parser, binary: *BinaryModule) !void {
    const gpa = parser.gpa;

    // map result-id → index in id_offsets for preamble instructions and function headers
    var id_to_index: std.AutoHashMapUnmanaged(ResultId, u32) = .empty;
    defer id_to_index.deinit(gpa);

    // for each indexed instruction, its offset in the binary
    var code_offsets: std.ArrayList(usize) = .empty;
    defer code_offsets.deinit(gpa);

    var it = binary.iterateInstructions();
    while (it.next()) |inst| {
        const inst_spec = parser.getInstSpec(inst.opcode) orelse continue;
        const result_id = getResultId(inst, inst_spec) orelse continue;

        // only index preamble instructions and function headers
        if (inst.offset < binary.functions_start or inst.opcode == .OpFunction) {
            const index: u32 = @intCast(code_offsets.items.len);
            try id_to_index.put(gpa, result_id, index);
            try code_offsets.append(gpa, inst.offset);
        }
    }

    var alive: std.bit_set.Dynamic = try .initEmpty(gpa, code_offsets.items.len);
    defer alive.deinit(gpa);

    var id_offset_buf: std.ArrayList(u16) = .empty;
    defer id_offset_buf.deinit(gpa);

    // mark non-prunable preamble instructions alive
    it = binary.iterateInstructions();
    while (it.next()) |inst| {
        if (inst.offset >= binary.functions_start) break;
        if (!canPrune(inst.opcode)) {
            markAlive(parser, binary.*, inst, &alive, &id_to_index, &code_offsets, &id_offset_buf) catch {};
        }
    }

    // mark alive functions' contents alive
    it = binary.iterateInstructionsFrom(binary.functions_start);
    while (it.next()) |inst| {
        if (inst.opcode == .OpFunction) {
            const inst_spec = parser.getInstSpec(inst.opcode) orelse continue;
            const result_id = getResultId(inst, inst_spec) orelse continue;
            const index = id_to_index.get(result_id) orelse continue;
            if (!alive.isSet(index)) {
                // skip dead function
                while (it.next()) |inner| {
                    if (inner.opcode == .OpFunctionEnd) break;
                }
                continue;
            }
        }

        // mark operands of alive function contents
        if (!canPrune(inst.opcode)) {
            markAlive(parser, binary.*, inst, &alive, &id_to_index, &code_offsets, &id_offset_buf) catch {};
        }
    }

    // rewrite
    var new_words: std.ArrayList(Word) = .empty;
    defer new_words.deinit(gpa);
    try new_words.ensureTotalCapacity(gpa, binary.instructions.len);

    var new_functions_start: ?usize = null;

    it = binary.iterateInstructions();
    while (it.next()) |inst| {
        if (inst.offset >= binary.functions_start and inst.opcode == .OpFunction) {
            const inst_spec = parser.getInstSpec(inst.opcode) orelse continue;
            const result_id = getResultId(inst, inst_spec) orelse continue;
            const index = id_to_index.get(result_id) orelse continue;
            if (!alive.isSet(index)) {
                while (it.next()) |inner| {
                    if (inner.opcode == .OpFunctionEnd) break;
                }
                continue;
            }
        }

        if (canPrune(inst.opcode)) {
            const inst_spec = parser.getInstSpec(inst.opcode) orelse {
                appendInst(&new_words, binary, inst, &new_functions_start);
                continue;
            };

            if (getResultId(inst, inst_spec)) |result_id| {
                const index = id_to_index.get(result_id) orelse {
                    appendInst(&new_words, binary, inst, &new_functions_start);
                    continue;
                };
                if (!alive.isSet(index)) continue;
            } else {
                // annotation-style: emit only if all id operands are alive
                id_offset_buf.items.len = 0;
                parser.parseInstructionResultIds(binary.*, inst, &id_offset_buf) catch continue;
                var all_alive = true;
                for (id_offset_buf.items) |off| {
                    const id: ResultId = @enumFromInt(inst.operands[off]);
                    if (id_to_index.get(id)) |idx| {
                        if (!alive.isSet(idx)) {
                            all_alive = false;
                            break;
                        }
                    }
                }
                if (!all_alive) continue;
            }
        }

        appendInst(&new_words, binary, inst, &new_functions_start);
    }

    {
        var to_remove: std.ArrayList(ResultId) = .empty;
        defer to_remove.deinit(gpa);

        var ext_it = binary.ext_inst_map.iterator();
        while (ext_it.next()) |entry| {
            if (id_to_index.get(entry.key_ptr.*)) |index| {
                if (!alive.isSet(index)) try to_remove.append(gpa, entry.key_ptr.*);
            }
        }
        for (to_remove.items) |id| _ = binary.ext_inst_map.remove(id);

        to_remove.items.len = 0;
        var arith_it = binary.arith_type_width.iterator();
        while (arith_it.next()) |entry| {
            if (id_to_index.get(entry.key_ptr.*)) |index| {
                if (!alive.isSet(index)) try to_remove.append(gpa, entry.key_ptr.*);
            }
        }
        for (to_remove.items) |id| _ = binary.arith_type_width.remove(id);
    }

    binary.instructions = try gpa.dupe(Word, new_words.items);
    binary.functions_start = new_functions_start orelse new_words.items.len;
}

fn appendInst(
    new_words: *std.ArrayList(Word),
    binary: *const BinaryModule,
    inst: BinaryModule.Instruction,
    new_functions_start: *?usize,
) void {
    if (new_functions_start.* == null and inst.offset >= binary.functions_start) {
        new_functions_start.* = new_words.items.len;
    }
    const len = @as(usize, binary.instructions[inst.offset] >> 16);
    new_words.appendSliceAssumeCapacity(binary.instructions[inst.offset..][0..len]);
}

fn markAlive(
    parser: *BinaryModule.Parser,
    binary: BinaryModule,
    inst: BinaryModule.Instruction,
    alive: *std.DynamicBitSetUnmanaged,
    id_to_index: *const std.AutoHashMapUnmanaged(ResultId, u32),
    code_offsets: *const std.ArrayList(usize),
    id_offset_buf: *std.ArrayList(u16),
) !void {
    const start = id_offset_buf.items.len;
    try parser.parseInstructionResultIds(binary, inst, id_offset_buf);
    const end = id_offset_buf.items.len;

    var i = start;
    while (i < end) : (i += 1) {
        const off = id_offset_buf.items[i];
        const id: ResultId = @enumFromInt(inst.operands[off]);
        const index = id_to_index.get(id) orelse continue;
        if (alive.isSet(index)) continue;
        alive.set(index);

        const offset = code_offsets.items[index];
        const ref_inst = BinaryModule.Instruction{
            .opcode = @enumFromInt(binary.instructions[offset] & 0xFFFF),
            .offset = offset,
            .operands = blk: {
                const l = binary.instructions[offset] >> 16;
                break :blk binary.instructions[offset..][1..l];
            },
        };

        if (ref_inst.opcode == .OpFunction) {
            var fn_it = binary.iterateInstructionsFrom(ref_inst.offset);
            _ = fn_it.next();
            while (fn_it.next()) |fn_inst| {
                if (fn_inst.opcode == .OpFunctionEnd) break;
                markAlive(parser, binary, fn_inst, alive, id_to_index, code_offsets, id_offset_buf) catch {};
            }
            markAlive(parser, binary, ref_inst, alive, id_to_index, code_offsets, id_offset_buf) catch {};
        } else {
            markAlive(parser, binary, ref_inst, alive, id_to_index, code_offsets, id_offset_buf) catch {};
        }
    }
}

fn getResultId(inst: BinaryModule.Instruction, inst_spec: spec.Instruction) ?ResultId {
    for (0..@min(2, inst_spec.operands.len)) |i| {
        if (inst_spec.operands[i].kind == .id_result) {
            if (i < inst.operands.len) return @enumFromInt(inst.operands[i]);
        }
    }
    return null;
}

fn canPrune(op: Opcode) bool {
    return switch (op.class()) {
        .type_declaration,
        .constant_creation,
        .annotation,
        => true,
        else => switch (op) {
            .OpFunction,
            .OpUndef,
            .OpString,
            .OpName,
            .OpMemberName,
            .OpExtInstImport,
            .OpVariable,
            => true,
            else => false,
        },
    };
}
