const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.spirv_parse);

const spec = @import("../../codegen/spirv/spec.zig");
const Opcode = spec.Opcode;
const Word = spec.Word;
const InstructionSet = spec.InstructionSet;
const ResultId = spec.Id;

const BinaryModule = @This();

/// The result-id bound of this SPIR-V module.
id_bound: u32,

/// The instructions of this module (no header).
instructions: []const Word,

/// Maps OpExtInstImport result-ids to their InstructionSet.
ext_inst_map: std.AutoHashMapUnmanaged(ResultId, InstructionSet),

/// Width of arithmetic types (OpTypeInt/OpTypeFloat). Needed to correctly
/// parse operands of Op(Spec)Constant and OpSwitch.
arith_type_width: std.AutoHashMapUnmanaged(ResultId, u16),

functions_start: usize,

pub fn deinit(bm: *BinaryModule, gpa: Allocator) void {
    bm.ext_inst_map.deinit(gpa);
    bm.arith_type_width.deinit(gpa);
    bm.* = undefined;
}

pub fn iterateInstructions(bm: BinaryModule) Instruction.Iterator {
    return Instruction.Iterator.init(bm.instructions, 0);
}

pub fn iterateInstructionsFrom(bm: BinaryModule, offset: usize) Instruction.Iterator {
    return Instruction.Iterator.init(bm.instructions, offset);
}

pub const Instruction = struct {
    pub const Iterator = struct {
        words: []const Word,
        offset: usize = 0,

        pub fn init(words: []const Word, start_offset: usize) Iterator {
            return .{ .words = words, .offset = start_offset };
        }

        pub fn next(it: *Iterator) ?Instruction {
            if (it.offset >= it.words.len) return null;

            const instruction_len = it.words[it.offset] >> 16;
            defer it.offset += instruction_len;
            assert(instruction_len != 0);
            assert(it.offset < it.words.len);

            return Instruction{
                .opcode = @fromBackingInt(@intCast(it.words[it.offset] & 0xFFFF)),
                .offset = it.offset,
                .operands = it.words[it.offset..][1..instruction_len],
            };
        }
    };

    opcode: Opcode,
    offset: usize,
    operands: []const Word,
};

pub const Parser = struct {
    gpa: Allocator,
    opcode_table: std.AutoHashMapUnmanaged(u32, u16) = .empty,

    pub fn init(gpa: Allocator) !Parser {
        var parser = Parser{ .gpa = gpa };
        errdefer parser.deinit();

        inline for (std.meta.tags(InstructionSet)) |set| {
            const instructions = set.instructions();
            try parser.opcode_table.ensureUnusedCapacity(gpa, @intCast(instructions.len));
            for (instructions, 0..) |inst, i| {
                const entry = parser.opcode_table.getOrPutAssumeCapacity(mapSetAndOpcode(set, @intCast(inst.opcode)));
                if (!entry.found_existing) {
                    entry.value_ptr.* = @intCast(i);
                }
            }
        }

        return parser;
    }

    pub fn deinit(parser: *Parser) void {
        parser.opcode_table.deinit(parser.gpa);
    }

    fn mapSetAndOpcode(set: InstructionSet, opcode: u16) u32 {
        return (@as(u32, @backingInt(set)) << 16) | opcode;
    }

    pub fn getInstSpec(parser: Parser, opcode: Opcode) ?spec.Instruction {
        const index = parser.opcode_table.get(mapSetAndOpcode(.core, @backingInt(opcode))) orelse return null;
        return InstructionSet.core.instructions()[index];
    }

    /// Build a BinaryModule from raw instruction words (no header).
    /// Scans for ext_inst_map, arith_type_width, and the functions section offset.
    pub fn initFromWords(parser: *Parser, words: []const Word, id_bound: u32) !BinaryModule {
        var binary = BinaryModule{
            .id_bound = id_bound,
            .instructions = words,
            .ext_inst_map = .{},
            .arith_type_width = .{},
            .functions_start = undefined,
        };

        var maybe_function_section: ?usize = null;
        var it = binary.iterateInstructions();
        while (it.next()) |inst| {
            const inst_spec = parser.getInstSpec(inst.opcode) orelse continue;
            const operands = inst.operands;

            switch (inst.opcode) {
                .OpExtInstImport => {
                    const set_name = std.mem.sliceTo(std.mem.sliceAsBytes(operands[1..]), 0);
                    const set = std.meta.stringToEnum(InstructionSet, set_name) orelse continue;
                    if (set == .core) continue;
                    try binary.ext_inst_map.put(parser.gpa, @fromBackingInt(@intCast(operands[0])), set);
                },
                .OpTypeInt, .OpTypeFloat => {
                    try binary.arith_type_width.put(parser.gpa, @fromBackingInt(@intCast(operands[0])), @intCast(operands[1]));
                },
                .OpFunction => if (maybe_function_section == null) {
                    maybe_function_section = inst.offset;
                },
                else => {},
            }

            // propagate arith type widths through instructions that return int/float
            const spec_operands = inst_spec.operands;
            if (spec_operands.len >= 2 and
                spec_operands[0].kind == .id_result_type and
                spec_operands[1].kind == .id_result)
            {
                if (operands.len >= 2) {
                    if (binary.arith_type_width.get(@fromBackingInt(@intCast(operands[0])))) |width| {
                        try binary.arith_type_width.put(parser.gpa, @fromBackingInt(@intCast(operands[1])), width);
                    }
                }
            }
        }

        binary.functions_start = maybe_function_section orelse binary.instructions.len;

        return binary;
    }

    /// Parse offsets in the instruction that contain result-ids.
    /// Returned offsets are relative to inst.operands.
    pub fn parseInstructionResultIds(
        parser: *Parser,
        binary: BinaryModule,
        inst: Instruction,
        offsets: *std.ArrayList(u16),
    ) !void {
        const index = parser.opcode_table.get(mapSetAndOpcode(.core, @backingInt(inst.opcode))).?;
        const operands = InstructionSet.core.instructions()[index].operands;

        var offset: usize = 0;
        switch (inst.opcode) {
            .OpSpecConstantOp => {
                assert(operands[0].kind == .id_result_type);
                assert(operands[1].kind == .id_result);
                offset = try parser.parseOperandsResultIds(binary, inst, operands[0..2], offset, offsets);

                if (offset >= inst.operands.len) return error.InvalidPhysicalFormat;
                const spec_opcode = std.math.cast(u16, inst.operands[offset]) orelse return error.InvalidPhysicalFormat;
                const spec_index = parser.opcode_table.get(mapSetAndOpcode(.core, spec_opcode)) orelse
                    return error.InvalidPhysicalFormat;
                const spec_operands = InstructionSet.core.instructions()[spec_index].operands;
                assert(spec_operands[0].kind == .id_result_type);
                assert(spec_operands[1].kind == .id_result);
                offset = try parser.parseOperandsResultIds(binary, inst, spec_operands[2..], offset + 1, offsets);
            },
            .OpExtInst => {
                assert(operands[0].kind == .id_result_type);
                assert(operands[1].kind == .id_result);
                offset = try parser.parseOperandsResultIds(binary, inst, operands[0..2], offset, offsets);

                if (offset + 1 >= inst.operands.len) return error.InvalidPhysicalFormat;
                const set_id: ResultId = @fromBackingInt(@intCast(inst.operands[offset]));
                try offsets.append(parser.gpa, @intCast(offset));
                const set = binary.ext_inst_map.get(set_id) orelse {
                    log.err("invalid instruction set {}", .{@backingInt(set_id)});
                    return error.InvalidId;
                };
                const ext_opcode = std.math.cast(u16, inst.operands[offset + 1]) orelse return error.InvalidPhysicalFormat;
                const ext_index = parser.opcode_table.get(mapSetAndOpcode(set, ext_opcode)) orelse
                    return error.InvalidPhysicalFormat;
                const ext_operands = set.instructions()[ext_index].operands;
                offset = try parser.parseOperandsResultIds(binary, inst, ext_operands, offset + 2, offsets);
            },
            else => {
                offset = try parser.parseOperandsResultIds(binary, inst, operands, offset, offsets);
            },
        }

        if (offset != inst.operands.len) return error.InvalidPhysicalFormat;
    }

    fn parseOperandsResultIds(
        parser: *Parser,
        binary: BinaryModule,
        inst: Instruction,
        operands: []const spec.Operand,
        start_offset: usize,
        offsets: *std.ArrayList(u16),
    ) !usize {
        var offset = start_offset;
        for (operands) |operand| {
            offset = try parser.parseOperandResultIds(binary, inst, operand, offset, offsets);
        }
        return offset;
    }

    fn parseOperandResultIds(
        parser: *Parser,
        binary: BinaryModule,
        inst: Instruction,
        operand: spec.Operand,
        start_offset: usize,
        offsets: *std.ArrayList(u16),
    ) !usize {
        var offset = start_offset;
        switch (operand.quantifier) {
            .variadic => while (offset < inst.operands.len) {
                offset = try parser.parseOperandKindResultIds(binary, inst, operand.kind, offset, offsets);
            },
            .optional => if (offset < inst.operands.len) {
                offset = try parser.parseOperandKindResultIds(binary, inst, operand.kind, offset, offsets);
            },
            .required => {
                offset = try parser.parseOperandKindResultIds(binary, inst, operand.kind, offset, offsets);
            },
        }
        return offset;
    }

    fn parseOperandKindResultIds(
        parser: *Parser,
        binary: BinaryModule,
        inst: Instruction,
        kind: spec.OperandKind,
        start_offset: usize,
        offsets: *std.ArrayList(u16),
    ) !usize {
        var offset = start_offset;
        if (offset >= inst.operands.len) return error.InvalidPhysicalFormat;

        switch (kind.category()) {
            .bit_enum => {
                const mask = inst.operands[offset];
                offset += 1;
                for (kind.enumerants()) |enumerant| {
                    if ((mask & enumerant.value) != 0) {
                        for (enumerant.parameters) |param_kind| {
                            offset = try parser.parseOperandKindResultIds(binary, inst, param_kind, offset, offsets);
                        }
                    }
                }
            },
            .value_enum => {
                const value = inst.operands[offset];
                offset += 1;
                for (kind.enumerants()) |enumerant| {
                    if (value == enumerant.value) {
                        for (enumerant.parameters) |param_kind| {
                            offset = try parser.parseOperandKindResultIds(binary, inst, param_kind, offset, offsets);
                        }
                        break;
                    }
                }
            },
            .id => {
                try offsets.append(parser.gpa, @intCast(offset));
                offset += 1;
            },
            else => switch (kind) {
                .literal_integer, .literal_float => offset += 1,
                .literal_string => while (true) {
                    if (offset >= inst.operands.len) return error.InvalidPhysicalFormat;
                    const word = inst.operands[offset];
                    offset += 1;

                    if (word & 0xFF000000 == 0 or
                        word & 0x00FF0000 == 0 or
                        word & 0x0000FF00 == 0 or
                        word & 0x000000FF == 0)
                    {
                        break;
                    }
                },
                .literal_context_dependent_number => {
                    assert(inst.opcode == .OpConstant or inst.opcode == .OpSpecConstant);
                    const bit_width = binary.arith_type_width.get(@fromBackingInt(@intCast(inst.operands[0]))) orelse {
                        log.err("invalid LiteralContextDependentNumber type {}", .{inst.operands[0]});
                        return error.InvalidId;
                    };
                    offset += switch (bit_width) {
                        1...32 => 1,
                        33...64 => 2,
                        else => unreachable,
                    };
                },
                .literal_ext_inst_integer => unreachable,
                .literal_spec_constant_op_integer => unreachable,
                .pair_literal_integer_id_ref => {
                    assert(inst.opcode == .OpSwitch);
                    const bit_width = binary.arith_type_width.get(@fromBackingInt(@intCast(inst.operands[0]))) orelse {
                        log.err("invalid OpSwitch type {}", .{inst.operands[0]});
                        return error.InvalidId;
                    };
                    offset += switch (bit_width) {
                        1...32 => 1,
                        33...64 => 2,
                        else => unreachable,
                    };
                    try offsets.append(parser.gpa, @intCast(offset));
                    offset += 1;
                },
                .pair_id_ref_literal_integer => {
                    try offsets.append(parser.gpa, @intCast(offset));
                    offset += 2;
                },
                .pair_id_ref_id_ref => {
                    try offsets.append(parser.gpa, @intCast(offset));
                    try offsets.append(parser.gpa, @intCast(offset + 1));
                    offset += 2;
                },
                else => unreachable,
            },
        }
        return offset;
    }
};
