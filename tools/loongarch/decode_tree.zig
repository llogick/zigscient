const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.loongarch_decode_tree);

const OpcodeDesc = @import("OpcodeDesc.zig");
const Opcode = OpcodeDesc.Opcode;

pub const Node = struct {
    mask: u32,
    /// `cases` when mask is non-zero. `instruction` when mask is zero.
    next: union {
        /// catch-all case
        cases: []const Case,
        instruction: *const Opcode,
    },
};

pub const Case = struct {
    catch_all: bool,
    variant: u32, // valid only when catch-all is not set
    child: *const Node,
};

pub fn populate(arena: Allocator, desc: *const OpcodeDesc) !*Node {
    var ops: std.ArrayList(*const Opcode) = .empty;
    defer ops.deinit(arena);
    try ops.ensureUnusedCapacity(arena, desc.opcode.items.len);
    for (desc.opcode.items) |*op| ops.appendAssumeCapacity(op);

    return try populateAdvanced(arena, ops.items, 0);
}

pub fn populateAdvanced(arena: Allocator, ops: []const *const Opcode, checked_mask: u32) !*Node {
    if (ops.len == 1) {
        const node = try arena.create(Node);
        node.* = .{ .mask = 0, .next = .{ .instruction = ops[0] } };
        return node;
    }

    // look for unchecked common static bits
    common_static_bits: {
        var common_mask: u32 = ~checked_mask;
        for (ops) |op| {
            for (op.format.slots) |slot| {
                if (slot.tag == .none) break;
                common_mask &= ~slot.mask();
            }
        }
        if (common_mask == 0) break :common_static_bits;

        // there are some common bits to check
        var cases: std.ArrayList(Case) = .empty;
        defer cases.deinit(arena);
        var known_variants: std.ArrayList(u32) = .empty;
        defer known_variants.deinit(arena);

        for (ops) |op| {
            const variant = op.word & common_mask;
            if (std.mem.indexOfScalar(u32, known_variants.items, variant) == null) {
                // new variant
                try known_variants.append(arena, variant);

                var variant_ops: std.ArrayList(*const Opcode) = .empty;
                defer variant_ops.deinit(arena);
                variant_ops.ensureTotalCapacity(arena, ops.len / 2) catch {};
                for (ops) |op1|
                    if ((op1.word & common_mask) == variant) try variant_ops.append(arena, op1);

                const child = try populateAdvanced(arena, variant_ops.items, checked_mask | common_mask);
                try cases.append(arena, .{
                    .catch_all = false,
                    .variant = variant,
                    .child = child,
                });
            }
        }

        const node = try arena.create(Node);
        node.* = .{
            .mask = common_mask,
            .next = .{ .cases = try cases.toOwnedSlice(arena) },
        };
        return node;
    }

    // look for bits that are static for some opcodes but dynamic for one opcode, e.g. csrxchg
    half_static_bits: {
        // these bits are static in at least one opcode
        var half_static_mask: u32 = 0;
        for (ops) |op| {
            var op_static_mask: u32 = 0xffffffff;
            for (op.format.slots) |slot| {
                if (slot.tag == .none) break;
                op_static_mask &= ~slot.mask();
            }
            half_static_mask |= op_static_mask;
        }
        half_static_mask &= ~checked_mask;
        if (half_static_mask == 0) break :half_static_bits;

        var cases: std.ArrayList(Case) = .empty;
        defer cases.deinit(arena);
        var maybe_dynamic_op: ?*const Opcode = null;

        for (ops) |op| {
            const variant = op.word & half_static_mask;

            var op_static_mask = ~checked_mask;
            for (op.format.slots) |slot| {
                if (slot.tag == .none) break;
                op_static_mask &= ~slot.mask();
            }
            if (op_static_mask != half_static_mask) {
                if (maybe_dynamic_op) |dynamic_op| {
                    log.err("unsupported: {s}, {s}", .{ dynamic_op.name, op.name });
                    return error.Unsupported;
                } else {
                    maybe_dynamic_op = op;
                    continue;
                }
            }

            const child = try populateAdvanced(arena, &.{op}, checked_mask | half_static_mask);
            try cases.append(arena, .{
                .catch_all = false,
                .variant = variant,
                .child = child,
            });
        }

        if (maybe_dynamic_op) |dynamic_op| {
            const child = try populateAdvanced(arena, &.{dynamic_op}, checked_mask | half_static_mask);
            try cases.append(arena, .{
                .catch_all = true,
                .variant = 0,
                .child = child,
            });
        } else unreachable;

        const node = try arena.create(Node);
        node.* = .{
            .mask = half_static_mask,
            .next = .{ .cases = try cases.toOwnedSlice(arena) },
        };
        return node;
    }

    return error.Unsupported;
}
