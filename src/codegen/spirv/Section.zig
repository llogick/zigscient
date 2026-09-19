//! Represents a section or subsection of instructions in a SPIR-V binary. Instructions can be append
//! to separate sections, which can then later be merged into the final binary.
const std = @import("std");
const Allocator = std.mem.Allocator;
const spec = @import("spec.zig");
const Opcode = spec.Opcode;
const InstructionHeader = spec.InstructionHeader;
const Word = spec.Word;
const Id = spec.Id;
const Section = @This();

instructions: std.ArrayList(Word),
ids: std.bit_set.Dynamic,

pub const empty: Section = .{ .instructions = .empty, .ids = .{} };

pub const Error = error{
    OutOfMemory,
    UnknownOpcode,
    InvalidInstruction,
    InvalidInstructionLength,
    NestedFunction,
    UnterminatedFunction,
    UndefinedId,
};

pub fn fromWords(gpa: Allocator, words: []const Word, id_bound: Word) Error!Section {
    var section: Section = .empty;
    errdefer section.deinit(gpa);
    try section.writeWords(gpa, words);
    const type_widths = try gpa.alloc(u16, id_bound);
    defer gpa.free(type_widths);
    @memset(type_widths, 0);
    var instruction_sets: std.array_hash_map.Auto(Word, spec.InstructionSet) = .empty;
    defer instruction_sets.deinit(gpa);
    var results: std.bit_set.Dynamic = try .initEmpty(gpa, id_bound);
    defer results.deinit(gpa);

    var in_function = false;
    var offset: usize = 0;
    while (offset < words.len) {
        const header: InstructionHeader = @bitCast(words[offset]);
        const len = header.word_count;
        if (len == 0 or offset + len > words.len) return error.InvalidInstructionLength;

        const inst = words[offset..][0..len];
        const op = std.enums.fromInt(Opcode, @as(u16, @truncate(inst[0]))) orelse
            return error.UnknownOpcode;
        const end = offset + len;
        var index = offset + 1;
        const list: []const spec.Operand = switch (op) {
            .OpFunction => list: {
                if (in_function) return error.NestedFunction;
                in_function = true;
                break :list op.operands();
            },
            .OpFunctionEnd => list: {
                if (!in_function) return error.InvalidInstruction;
                in_function = false;
                break :list op.operands();
            },
            .OpSpecConstantOp => list: {
                const prefix = op.operands()[0..2];
                index = try section.parseOperands(type_widths, offset, end, prefix, index);
                if (index >= end) return error.InvalidInstruction;
                const inner = std.enums.fromInt(Opcode, words[index]) orelse
                    return error.InvalidInstruction;
                index += 1;
                break :list inner.operands()[2..];
            },
            .OpExtInst => list: {
                if (len < 5) return error.InvalidInstruction;
                const set = instruction_sets.get(inst[3]) orelse return error.InvalidInstruction;
                const prefix = op.operands()[0..4];
                index = try section.parseOperands(type_widths, offset, end, prefix, index);
                break :list set.operands(inst[4]) orelse return error.InvalidInstruction;
            },
            else => op.operands(),
        };
        const operands_end = try section.parseOperands(type_widths, offset, end, list, index);
        if (operands_end != end) return error.InvalidInstruction;
        if (op.resultIndex()) |result_index| {
            if (results.isSet(inst[result_index])) return error.InvalidInstruction;
            results.set(inst[result_index]);
        }

        switch (op) {
            .OpTypeInt, .OpTypeFloat => {
                type_widths[inst[1]] = std.math.cast(u16, inst[2]) orelse
                    return error.InvalidInstruction;
            },
            .OpExtInstImport => {
                const set_name = std.mem.sliceTo(std.mem.sliceAsBytes(inst[2..]), 0);
                if (std.meta.stringToEnum(spec.InstructionSet, set_name)) |set| {
                    if (set != .core) try instruction_sets.put(gpa, inst[1], set);
                }
            },
            else => if (op.resultIndex() == 2) {
                type_widths[inst[2]] = type_widths[inst[1]];
            },
        }
        offset = end;
    }
    if (in_function) return error.UnterminatedFunction;
    var it = section.ids.iterator(.{});
    while (it.next()) |index| {
        if (!results.isSet(section.instructions.items[index])) return error.UndefinedId;
    }

    return section;
}

pub fn deinit(section: *Section, gpa: Allocator) void {
    section.instructions.deinit(gpa);
    section.ids.deinit(gpa);
    section.* = undefined;
}

pub fn reset(section: *Section) void {
    section.instructions.clearRetainingCapacity();
    section.ids.unsetAll();
}

pub fn append(section: *Section, gpa: Allocator, other: Section) error{OutOfMemory}!void {
    const offset = section.instructions.items.len;
    try section.writeWords(gpa, other.instructions.items);
    var it = other.ids.iterator(.{});
    while (it.next()) |index| section.ids.set(offset + index);
}

pub fn ensureUnusedCapacity(section: *Section, gpa: Allocator, words: usize) !void {
    try section.instructions.ensureUnusedCapacity(gpa, words);
    try section.ids.resize(gpa, section.instructions.capacity, false);
}

fn parseOperands(
    section: *Section,
    type_widths: []const u16,
    inst_start: usize,
    inst_end: usize,
    operands: []const spec.Operand,
    index: usize,
) Error!usize {
    const words = section.instructions.items;
    var next = index;
    var lists: [16][]const spec.Operand = undefined;
    lists[0] = operands;
    var depth: usize = 1;
    while (depth > 0) {
        const list = &lists[depth - 1];
        if (list.len == 0) {
            depth -= 1;
            continue;
        }
        const entry = list.*[0];
        if (next >= inst_end) {
            if (entry.quantifier == .required) return error.InvalidInstruction;
            list.* = &.{};
            continue;
        }
        if (entry.quantifier != .variadic) list.* = list.*[1..];
        const single = [_]spec.OperandKind{entry.kind};
        const kinds: []const spec.OperandKind = switch (entry.kind.category()) {
            .composite => entry.kind.bases(),
            else => &single,
        };
        for (kinds) |base| {
            if (next >= inst_end) return error.InvalidInstruction;
            const is_pair_literal = entry.kind == .pair_literal_integer_id_ref;
            const kind: spec.OperandKind = if (is_pair_literal and base == .literal_integer)
                .literal_context_dependent_number
            else
                base;
            switch (kind.category()) {
                .id => {
                    if (words[next] == 0 or words[next] >= type_widths.len) {
                        return error.InvalidInstruction;
                    }
                    section.ids.set(next);
                    next += 1;
                },
                .literal => switch (kind) {
                    .literal_string => {
                        next = for (words[next..inst_end], next + 1..) |word, after| {
                            const bytes: [4]u8 = @bitCast(word);
                            if (std.mem.findScalar(u8, &bytes, 0) != null) break after;
                        } else return error.InvalidInstruction;
                    },
                    .literal_context_dependent_number => {
                        next += switch (type_widths[words[inst_start + 1]]) {
                            1...32 => 1,
                            33...64 => 2,
                            else => return error.InvalidInstruction,
                        };
                        if (next > inst_end) return error.InvalidInstruction;
                    },
                    .literal_spec_constant_op_integer => unreachable,
                    else => next += 1,
                },
                .value_enum => {
                    const enumerant = for (kind.enumerants()) |enumerant| {
                        if (enumerant.value == words[next]) break enumerant;
                    } else return error.InvalidInstruction;
                    next += 1;
                    if (enumerant.parameters.len != 0) {
                        if (depth == lists.len) return error.InvalidInstruction;
                        lists[depth] = enumerant.parameters;
                        depth += 1;
                    }
                },
                .bit_enum => {
                    const mask = words[next];
                    next += 1;
                    const enumerants = kind.enumerants();
                    var i = enumerants.len;
                    while (i > 0) {
                        i -= 1;
                        const enumerant = enumerants[i];
                        if (mask & enumerant.value == 0) continue;
                        if (enumerant.parameters.len == 0) continue;
                        if (depth == lists.len) return error.InvalidInstruction;
                        lists[depth] = enumerant.parameters;
                        depth += 1;
                    }
                },
                .composite => unreachable,
            }
        }
    }
    return next;
}

pub fn emitRaw(
    section: *Section,
    gpa: Allocator,
    opcode: Opcode,
    operand_words: usize,
) !void {
    const word_count = 1 + operand_words;
    if (word_count > std.math.maxInt(u16)) return error.OutOfMemory;
    try section.ensureUnusedCapacity(gpa, word_count);
    const header: InstructionHeader = .{ .opcode = opcode, .word_count = @intCast(word_count) };
    section.writeWord(@bitCast(header));
}

pub fn emitFormatted(
    section: *Section,
    gpa: Allocator,
    comptime opcode: Opcode,
    ids: []const Id,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const len = std.fmt.count(fmt, args);
    const string_words = len / @sizeOf(Word) + 1;
    try section.emitRaw(gpa, opcode, ids.len + string_words);
    for (ids) |id| section.writeId(id);
    const words = section.instructions.addManyAsSliceAssumeCapacity(string_words);
    @memset(words, 0);
    _ = std.fmt.bufPrint(std.mem.sliceAsBytes(words), fmt, args) catch unreachable;
    for (words) |*word| word.* = std.mem.littleToNative(Word, word.*);
}

pub fn emit(
    section: *Section,
    gpa: Allocator,
    comptime opcode: spec.Opcode,
    operands: opcode.Operands(),
) !void {
    try section.emitRaw(gpa, opcode, opcode.instructionSize(operands) - 1);
    section.writeOperands(opcode.Operands(), operands);
}

pub fn writeWord(section: *Section, word: Word) void {
    section.instructions.appendAssumeCapacity(word);
}

pub fn writeWords(section: *Section, gpa: Allocator, words: []const Word) error{OutOfMemory}!void {
    try section.ensureUnusedCapacity(gpa, words.len);
    section.instructions.appendSliceAssumeCapacity(words);
}

pub const DoubleWord = @Int(.unsigned, @bitSizeOf(Word) * 2);

pub fn writeDoubleWord(section: *Section, dword: DoubleWord) void {
    section.instructions.appendSliceAssumeCapacity(&.{
        @truncate(dword),
        @truncate(dword >> @bitSizeOf(Word)),
    });
}

pub fn writeId(section: *Section, id: Id) void {
    section.ids.set(section.instructions.items.len);
    section.instructions.appendAssumeCapacity(@backingInt(id));
}

pub fn writeOperands(section: *Section, comptime Operands: type, operands: Operands) void {
    const info = switch (@typeInfo(Operands)) {
        .@"struct" => |info| info,
        .void => return,
        else => unreachable,
    };
    inline for (info.field_names, info.field_types) |field_name, field_type| {
        section.writeOperand(field_type, @field(operands, field_name));
    }
}

pub fn writeOperand(section: *Section, comptime Operand: type, operand: Operand) void {
    switch (Operand) {
        spec.LiteralSpecConstantOpInteger => unreachable,
        spec.Id => section.writeId(operand),
        spec.LiteralInteger => section.writeWord(operand),
        spec.LiteralString => section.writeString(operand),
        spec.LiteralContextDependentNumber => section.writeNumber(operand),
        spec.LiteralExtInstInteger => section.writeWord(operand.inst),
        spec.PairLiteralIntegerIdRef => {
            section.writeWord(operand.value);
            section.writeId(operand.label);
        },
        spec.PairIdRefLiteralInteger => {
            section.writeId(operand.target);
            section.writeWord(operand.member);
        },
        spec.PairIdRefIdRef => {
            section.writeId(operand[0]);
            section.writeId(operand[1]);
        },
        else => switch (@typeInfo(Operand)) {
            .@"enum" => section.writeWord(@backingInt(operand)),
            .optional => |info| if (operand) |child| section.writeOperand(info.child, child),
            .pointer => |info| {
                std.debug.assert(info.size == .slice);
                for (operand) |item| {
                    section.writeOperand(info.child, item);
                }
            },
            .@"struct" => |info| {
                if (info.layout == .@"packed") {
                    section.writeWord(@as(Word, @bitCast(operand)));
                } else {
                    section.writeExtendedMask(Operand, operand);
                }
            },
            .@"union" => section.writeExtendedUnion(Operand, operand),
            else => unreachable,
        },
    }
}

pub fn writeString(section: *Section, str: []const u8) void {
    const zero_terminated_len = str.len + 1;
    var i: usize = 0;
    while (i < zero_terminated_len) : (i += @sizeOf(Word)) {
        var word: Word = 0;
        var j: usize = 0;
        while (j < @sizeOf(Word) and i + j < str.len) : (j += 1) {
            const shift: std.math.Log2Int(Word) = @intCast(j * @bitSizeOf(u8));
            word |= @as(Word, str[i + j]) << shift;
        }
        section.instructions.appendAssumeCapacity(word);
    }
}

pub fn writeNumber(section: *Section, operand: spec.LiteralContextDependentNumber) void {
    switch (operand) {
        .int32 => |int| section.writeWord(@bitCast(int)),
        .uint32 => |int| section.writeWord(@bitCast(int)),
        .int64 => |int| section.writeDoubleWord(@bitCast(int)),
        .uint64 => |int| section.writeDoubleWord(@bitCast(int)),
        .float32 => |float| section.writeWord(@bitCast(float)),
        .float64 => |float| section.writeDoubleWord(@bitCast(float)),
    }
}

pub fn writeExtendedMask(section: *Section, comptime Operand: type, operand: Operand) void {
    var mask: Word = 0;
    const info = @typeInfo(Operand).@"struct";
    comptime var bit: usize = 0;
    inline for (info.field_names, info.field_types) |field_name, field_type| {
        switch (@typeInfo(field_type)) {
            .optional => {
                if (@field(operand, field_name) != null) {
                    mask |= @as(Word, 1) << @intCast(bit);
                }
                bit += 1;
            },
            .bool => {
                if (@field(operand, field_name)) mask |= @as(Word, 1) << @intCast(bit);
                bit += 1;
            },
            .int => bit += @bitSizeOf(field_type),
            else => unreachable,
        }
    }

    section.writeWord(mask);

    inline for (info.field_names, info.field_types) |field_name, field_type| {
        switch (@typeInfo(field_type)) {
            .optional => |opt_info| {
                if (@field(operand, field_name)) |child| {
                    section.writeOperands(opt_info.child, child);
                }
            },
            .bool, .int => {},
            else => unreachable,
        }
    }
}

pub fn writeExtendedUnion(section: *Section, comptime Operand: type, operand: Operand) void {
    return switch (operand) {
        inline else => |op, tag| {
            section.writeWord(@backingInt(tag));
            section.writeOperands(@FieldType(Operand, @tagName(tag)), op);
        },
    };
}
