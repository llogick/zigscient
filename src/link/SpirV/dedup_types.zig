const std = @import("std");
const Allocator = std.mem.Allocator;
const BinaryModule = @import("BinaryModule.zig");

const spec = @import("../../codegen/spirv/spec.zig");
const Word = spec.Word;
const Id = spec.Id;
const Opcode = spec.Opcode;
const Instruction = BinaryModule.Instruction;

/// Deduplicate types and constants in a SPIR-V binary module.
///
/// The SPIR-V spec requires that non-aggregate types be unique.
/// When merging fragments from parallel codegen, duplicate type definitions
/// may exist. This pass identifies structurally identical types/constants,
/// keeps one canonical instance, and remaps all references to duplicates.
///
/// Decorations and names (OpName, OpMemberName) are included in the
/// equality check: two types that are structurally identical but have
/// different decorations or names are NOT considered duplicates.
pub fn run(parser: *BinaryModule.Parser, binary: *BinaryModule) !void {
    const gpa = parser.gpa;

    const Decoration = struct { offset: usize, len: usize };
    var decorations_by_id: std.array_hash_map.Auto(Id, std.ArrayList(Decoration)) = .empty;
    defer {
        for (decorations_by_id.values()) |*list| list.deinit(gpa);
        decorations_by_id.deinit(gpa);
    }

    var it = binary.iterateInstructions();
    while (it.next()) |inst| {
        if (inst.offset >= binary.functions_start) break;
        switch (inst.opcode) {
            .OpName, .OpMemberName => {},
            else => switch (inst.opcode.class()) {
                .annotation => {},
                else => continue,
            },
        }
        if (inst.operands.len == 0) continue;
        const target_id: Id = @enumFromInt(inst.operands[0]);

        const gop = try decorations_by_id.getOrPut(gpa, target_id);
        if (!gop.found_existing) gop.value_ptr.* = .empty;
        try gop.value_ptr.append(gpa, .{
            .offset = inst.offset,
            .len = 1 + inst.operands.len,
        });
    }

    var canonical_map: std.array_hash_map.Custom(TypeKey, Id, TypeKey.HashContext, true) = .empty;
    defer {
        for (canonical_map.keys()) |key| gpa.free(key.words);
        canonical_map.deinit(gpa);
    }

    var id_remap: std.AutoHashMapUnmanaged(Id, Id) = .empty;
    defer id_remap.deinit(gpa);

    var id_offsets: std.ArrayList(u16) = .empty;
    defer id_offsets.deinit(gpa);

    var key_words: std.ArrayList(Word) = .empty;
    defer key_words.deinit(gpa);

    var dec_hashes: std.ArrayList(u64) = .empty;
    defer dec_hashes.deinit(gpa);

    // first pass: build canonical map, identify duplicates
    it = binary.iterateInstructions();
    while (it.next()) |inst| {
        if (inst.offset >= binary.functions_start) break;
        if (!canDeduplicate(inst.opcode)) continue;

        const result_id_index: usize = switch (inst.opcode.class()) {
            .type_declaration, .extension => 0,
            .constant_creation => 1,
            else => continue,
        };
        if (result_id_index >= inst.operands.len) continue;
        const result_id: Id = @enumFromInt(inst.operands[result_id_index]);

        key_words.items.len = 0;
        try key_words.append(gpa, @intFromEnum(inst.opcode));

        id_offsets.items.len = 0;
        parser.parseInstructionResultIds(binary.*, inst, &id_offsets) catch continue;

        for (inst.operands, 0..) |word, i| {
            if (i == result_id_index) continue;
            if (std.mem.indexOfScalar(u16, id_offsets.items, @intCast(i)) != null) {
                const canonical = id_remap.get(@enumFromInt(word)) orelse @as(Id, @enumFromInt(word));
                try key_words.append(gpa, @intFromEnum(canonical));
            } else {
                try key_words.append(gpa, word);
            }
        }

        if (decorations_by_id.getPtr(result_id)) |dec_list| {
            dec_hashes.items.len = 0;
            for (dec_list.items) |dec| {
                const dec_words = binary.instructions[dec.offset..][0..dec.len];
                const dec_opcode: Opcode = @enumFromInt(dec_words[0] & 0xFFFF);
                var hasher = std.hash.Wyhash.init(0);
                hasher.update(std.mem.asBytes(&dec_words[0]));
                // OpName/OpMemberName operands are literals (member index, string),
                // not ids — hash them directly without remapping
                if (dec_opcode == .OpName or dec_opcode == .OpMemberName) {
                    hasher.update(std.mem.sliceAsBytes(dec_words[2..]));
                } else {
                    for (dec_words[2..]) |w| {
                        const w_val = if (id_remap.get(@enumFromInt(w))) |c| @intFromEnum(c) else w;
                        hasher.update(std.mem.asBytes(&w_val));
                    }
                }
                try dec_hashes.append(gpa, hasher.final());
            }
            std.mem.sort(u64, dec_hashes.items, {}, std.sort.asc(u64));
            var prev: u64 = 0;
            for (dec_hashes.items) |h| {
                if (h == prev) continue;
                prev = h;
                try key_words.append(gpa, @truncate(h));
                try key_words.append(gpa, @truncate(h >> 32));
            }
        }

        const key = TypeKey{ .words = try gpa.dupe(Word, key_words.items) };
        const gop = try canonical_map.getOrPut(gpa, key);
        if (gop.found_existing) {
            try id_remap.put(gpa, result_id, gop.value_ptr.*);
            gpa.free(key.words);
        } else {
            gop.value_ptr.* = result_id;
        }
    }

    if (id_remap.count() == 0) return;

    // second pass: rewrite id references, remove duplicates and redundant annotations
    var new_words: std.ArrayList(Word) = .empty;
    defer new_words.deinit(gpa);
    try new_words.ensureTotalCapacity(gpa, binary.instructions.len);

    var emitted_annotations: std.AutoHashMapUnmanaged(u64, void) = .empty;
    defer emitted_annotations.deinit(gpa);

    var new_functions_offset: ?usize = null;
    var max_id: Word = 0;

    it = binary.iterateInstructions();
    while (it.next()) |inst| {
        if (new_functions_offset == null and inst.offset >= binary.functions_start) {
            new_functions_offset = new_words.items.len;
        }

        if (canDeduplicate(inst.opcode)) {
            const result_id_index: usize = switch (inst.opcode.class()) {
                .type_declaration, .extension => 0,
                .constant_creation => 1,
                else => unreachable,
            };
            if (result_id_index < inst.operands.len) {
                const result_id: Id = @enumFromInt(inst.operands[result_id_index]);
                if (id_remap.contains(result_id)) continue;
            }
        }

        switch (inst.opcode.class()) {
            .annotation, .debug => {
                if (inst.operands.len > 0) {
                    const target: Id = @enumFromInt(inst.operands[0]);
                    if (id_remap.contains(target)) continue;
                }
            },
            else => {},
        }

        const inst_start = new_words.items.len;
        new_words.appendAssumeCapacity(binary.instructions[inst.offset]);
        new_words.appendSliceAssumeCapacity(inst.operands);
        const inst_slice = new_words.items[inst_start + 1 ..];

        id_offsets.items.len = 0;
        parser.parseInstructionResultIds(binary.*, inst, &id_offsets) catch continue;

        const inst_spec = parser.getInstSpec(inst.opcode);
        const maybe_result_id_index: ?usize = if (inst_spec) |ispec| blk: {
            break :blk for (0..@min(2, ispec.operands.len)) |i| {
                if (ispec.operands[i].kind == .id_result) break @intCast(i);
            } else null;
        } else null;

        for (inst_slice, 0..) |*word, i| {
            if (std.mem.indexOfScalar(u16, id_offsets.items, @intCast(i)) == null) continue;
            max_id = @max(max_id, word.*);
            if (maybe_result_id_index != null and i == maybe_result_id_index.?) continue;

            if (id_remap.get(@enumFromInt(word.*))) |canonical| {
                word.* = @intFromEnum(canonical);
                max_id = @max(max_id, word.*);
            }
        }

        switch (inst.opcode.class()) {
            .annotation, .debug => {
                const ann_words = new_words.items[inst_start..];
                const ann_hash = std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(ann_words));
                const gop = try emitted_annotations.getOrPut(gpa, ann_hash);
                if (gop.found_existing) {
                    new_words.items.len = inst_start;
                    continue;
                }
            },
            else => {},
        }
    }

    var remap_it = id_remap.iterator();
    while (remap_it.next()) |entry| {
        _ = binary.ext_inst_map.remove(entry.key_ptr.*);
        _ = binary.arith_type_width.remove(entry.key_ptr.*);
    }

    binary.instructions = try gpa.dupe(Word, new_words.items);
    binary.functions_start = new_functions_offset orelse new_words.items.len;
    binary.id_bound = max_id + 1;
}

fn canDeduplicate(opcode: Opcode) bool {
    return switch (opcode) {
        .OpTypeForwardPointer => false,
        .OpGroupDecorate, .OpGroupMemberDecorate => false,
        else => switch (opcode.class()) {
            .type_declaration, .constant_creation => true,
            .extension => opcode == .OpExtInstImport,
            else => false,
        },
    };
}

const TypeKey = struct {
    words: []const Word,

    const HashContext = struct {
        pub fn hash(_: @This(), key: TypeKey) u32 {
            return @truncate(std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(key.words)));
        }

        pub fn eql(_: @This(), a: TypeKey, b: TypeKey, _: usize) bool {
            return std.mem.eql(Word, a.words, b.words);
        }
    };
};
