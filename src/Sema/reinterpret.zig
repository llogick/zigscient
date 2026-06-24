//! This file contains logic for bit-casting arbitrary values at comptime, including splicing
//! bits together for comptime stores of bit-pointers. The strategy is to "flatten" values to
//! a sequence of values in *packed* memory, and then unflatten through a combination of special
//! cases (particularly for pointers and `undefined` values) and in-memory buffer reinterprets.
//!
//! This is a little awkward on big-endian targets, as non-packed datastructures (e.g. `extern struct`)
//! have their fields reversed when represented as packed memory on such targets.

/// If `host_bits` is `0`, attempts to convert the memory at offset
/// `byte_offset` into `val` to a non-packed value of type `dest_ty`,
/// ignoring `bit_offset`.
///
/// Otherwise, `byte_offset` is an offset in bytes into `val` to a
/// non-packed value consisting of `host_bits` bits. A value of type
/// `dest_ty` will be interpreted at a packed offset of `bit_offset`
/// into this value.
///
/// Returns `null` if the operation must be performed at runtime.
pub fn castMemory(
    sema: *Sema,
    val: Value,
    dest_ty: Type,
    byte_offset: u64,
) CompileError!?Value {
    const pt = sema.pt;
    const zcu = pt.zcu;

    const val_ty = val.typeOf(zcu);

    if (dest_ty.toIntern() == val_ty.toIntern()) {
        assert(byte_offset == 0);
        return val;
    }

    val_ty.assertHasLayout(zcu);
    dest_ty.assertHasLayout(zcu);

    var unpack: UnpackValueBytes = .{
        .pt = pt,
        .arena = sema.arena,
        .skip_bytes = byte_offset,
        .remaining_bytes = dest_ty.abiSize(zcu),
        .unpacked = .init(sema.arena),
    };
    unpack.add(val) catch |err| switch (err) {
        error.ReinterpretDeclRef => return null,
        error.OutOfMemory => |e| return e,
    };

    var pack: PackValueBytes = .{
        .pt = pt,
        .arena = sema.arena,
        .unpacked = unpack.unpacked.items,
    };
    return pack.get(dest_ty) catch |err| switch (err) {
        error.ReinterpretDeclRef => return null,
        error.OutOfMemory => |e| return e,
    };
}

/// Splice the value `splice_val` into `val` at the given `byte_offset`, replacing overlapping bits
/// and returning the modified value.
pub fn spliceMemory(
    sema: *Sema,
    val: Value,
    splice_val: Value,
    byte_offset: u64,
) CompileError!?Value {
    const pt = sema.pt;
    const zcu = pt.zcu;
    const val_ty = val.typeOf(zcu);
    const splice_val_ty = splice_val.typeOf(zcu);

    val_ty.assertHasLayout(zcu);
    splice_val_ty.assertHasLayout(zcu);

    var unpack: UnpackValueBytes = .{
        .pt = pt,
        .arena = sema.arena,
        .skip_bytes = 0,
        .remaining_bytes = byte_offset,
        .unpacked = .init(sema.arena),
    };
    unpack.add(val) catch |err| switch (err) {
        error.ReinterpretDeclRef => return null,
        error.OutOfMemory => |e| return e,
    };

    const splice_len = splice_val_ty.abiSize(zcu);

    unpack.remaining_bytes = splice_len;
    unpack.add(splice_val) catch |err| switch (err) {
        error.ReinterpretDeclRef => return null,
        error.OutOfMemory => |e| return e,
    };

    unpack.skip_bytes = byte_offset + splice_len;
    unpack.remaining_bytes = val_ty.abiSize(zcu) * 8 - byte_offset - splice_len;
    unpack.add(val) catch |err| switch (err) {
        error.ReinterpretDeclRef => return null,
        error.OutOfMemory => |e| return e,
    };

    var pack: PackValueBytes = .{
        .pt = pt,
        .arena = sema.arena,
        .unpacked = unpack.unpacked.items,
    };
    return pack.get(val_ty) catch |err| switch (err) {
        error.ReinterpretDeclRef => return null,
        error.OutOfMemory => |e| return e,
    };
}

/// Recurses through struct fields, array elements, etc, to get a sequence of "primitive" values
/// which are bit-packed in memory to represent a single value. `unpacked` represents a series
/// of values in *packed* memory - therefore, on big-endian targets, the first element of this
/// list contains bits from the *final* byte of the value.
const UnpackValueBytes = struct {
    pt: Zcu.PerThread,
    arena: Allocator,
    skip_bytes: u64,
    remaining_bytes: u64,
    unpacked: std.array_list.Managed(InternPool.Index),

    fn add(unpack: *UnpackValueBytes, val: Value) (error{ReinterpretDeclRef} || Allocator.Error)!void {
        const pt = unpack.pt;
        const zcu = pt.zcu;
        const ip = &zcu.intern_pool;

        if (unpack.remaining_bytes == 0) {
            return;
        }

        const ty = val.typeOf(zcu);
        const size = ty.abiSize(zcu);

        if (unpack.skip_bytes >= size) {
            unpack.skip_bytes -= size;
            return;
        }

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
            .@"extern",
            .func,
            .err,
            .error_union,
            .enum_literal,
            .slice,
            .memoized_call,
            => unreachable, // ill-defined layout or not real values

            .undef,
            .int,
            .enum_tag,
            .simple_value,
            .float,
            .ptr,
            .opt,
            => try unpack.primitive(val),

            .bitpack => |bitpack| try unpack.primitive(.fromInterned(bitpack.backing_int_val)),

            .aggregate => switch (ty.zigTypeTag(zcu)) {
                .vector => unreachable, // ill-defined layout
                .array => {
                    for (0..@intCast(ty.arrayLen(zcu))) |elem_index| {
                        const elem_val = try val.elemValue(pt, @intCast(elem_index));
                        try unpack.add(elem_val);
                    }
                    if (ty.sentinel(zcu)) |s| {
                        try unpack.add(s);
                    }
                },
                .@"struct" => switch (ty.containerLayout(zcu)) {
                    .auto => unreachable, // ill-defined layout
                    .@"packed" => unreachable, // uses `.bitpack`, not `.aggregate`
                    .@"extern" => {
                        var it = ip.loadStructType(ty.toIntern()).iterateRuntimeOrder(ip);
                        var offset: u64 = 0;
                        while (it.next()) |field_index| {
                            const pad_bytes = ty.structFieldOffset(field_index, zcu) - offset;
                            const field_val = try val.fieldValue(pt, field_index);
                            try unpack.padding(pad_bytes);
                            try unpack.add(field_val);
                            offset += pad_bytes + field_val.typeOf(zcu).abiSize(zcu);
                        }
                        try unpack.padding(size - offset);
                    },
                },
                else => unreachable,
            },

            .un => |un| {
                const payload_val = Value.fromInterned(un.val);
                const pad_bytes = size - payload_val.typeOf(zcu).abiSize(zcu);
                try unpack.add(payload_val);
                try unpack.padding(pad_bytes);
            },
        }
    }

    fn padding(unpack: *UnpackValueBytes, num_bytes: u64) Allocator.Error!void {
        if (num_bytes == 0) return;
        const undef_u8 = try unpack.pt.undefValue(Type.u8);
        for (0..@intCast(num_bytes)) |_| {
            unpack.primitive(undef_u8) catch |err| switch (err) {
                error.OutOfMemory => |e| return e,
                error.ReinterpretDeclRef => unreachable,
            };
        }
    }

    fn primitive(unpack: *UnpackValueBytes, val: Value) (error{ReinterpretDeclRef} || Allocator.Error)!void {
        const pt = unpack.pt;
        const zcu = pt.zcu;

        if (unpack.remaining_bytes == 0) {
            return;
        }

        const ty = val.typeOf(pt.zcu);
        const size = ty.abiSize(zcu);

        if (unpack.skip_bytes >= size) {
            unpack.skip_bytes -= size;
            return;
        }

        if (unpack.skip_bytes > 0) {
            const offset = unpack.skip_bytes;
            unpack.skip_bytes = 0;
            return unpack.splitPrimitive(val, offset, @min(size - offset, unpack.remaining_bytes));
        }

        if (unpack.remaining_bytes < size) {
            return unpack.splitPrimitive(val, 0, unpack.remaining_bytes);
        }

        unpack.remaining_bytes -= size;
        try unpack.unpacked.append(val.toIntern());
    }

    fn splitPrimitive(unpack: *UnpackValueBytes, val: Value, offset: u64, len: u64) (error{ReinterpretDeclRef} || Allocator.Error)!void {
        const pt = unpack.pt;
        const zcu = pt.zcu;
        const ty = val.typeOf(pt.zcu);

        assert(offset + len <= ty.abiSize(zcu));

        try unpack.unpacked.ensureUnusedCapacity(@intCast(len));
        unpack.remaining_bytes -= len;

        switch (pt.zcu.intern_pool.indexToKey(val.toIntern())) {
            // In the `ptr` case, this will return `error.ReinterpretDeclRef`
            // if we're trying to split a non-integer pointer value.
            .int, .float, .enum_tag, .ptr, .opt => {
                const buf = try unpack.arena.alloc(u8, @intCast(ty.abiSize(zcu)));
                val.writeToMemory(zcu, buf) catch |err| switch (err) {
                    error.IllDefinedMemoryLayout => unreachable,
                    else => |e| return e,
                };
                for (buf[@intCast(offset)..][0..@intCast(len)]) |byte_raw| {
                    const byte_val = try pt.intValue(.u8, byte_raw);
                    unpack.unpacked.appendAssumeCapacity(byte_val.toIntern());
                }
            },
            .undef => {
                const undef_u8 = try pt.undefValue(.u8);
                for (0..@intCast(len)) |_| {
                    unpack.unpacked.appendAssumeCapacity(undef_u8.toIntern());
                }
            },
            // The only values here with runtime bits are `true` and `false`.
            // These are both 1 byte, so will never need splitting.
            .simple_value => unreachable,
            else => unreachable, // zero-bit or not primitives
        }
    }
};

/// Given a sequence of bit-packed values in packed memory (see `UnpackValueBytes`),
/// reconstructs a value of an arbitrary type, with correct handling of `undefined`
/// values and of pointers which align in virtual memory.
const PackValueBytes = struct {
    pt: Zcu.PerThread,
    arena: Allocator,
    byte_offset: u64 = 0,
    unpacked: []const InternPool.Index,

    fn get(pack: *PackValueBytes, ty: Type) (Allocator.Error || error{ReinterpretDeclRef})!Value {
        const pt = pack.pt;
        const zcu = pt.zcu;
        const ip = &zcu.intern_pool;
        const arena = pack.arena;
        switch (ty.zigTypeTag(zcu)) {
            .vector => unreachable, // ill-defined layout
            .array => {
                // Each element is padded up to its ABI size. The final element does not have trailing padding.
                const elem_ty = ty.childType(zcu);
                const elems = try arena.alloc(InternPool.Index, @intCast(ty.arrayLen(zcu)));

                for (elems) |*elem| {
                    elem.* = (try pack.get(elem_ty)).toIntern();
                }

                if (ty.sentinel(zcu)) |s| {
                    _ = s; // TODO: validate sentinel was preserved!
                    pack.padding(elem_ty.abiSize(zcu));
                }

                return pt.aggregateValue(ty, elems);
            },
            .@"struct" => switch (ty.containerLayout(zcu)) {
                .auto => unreachable, // ill-defined layout
                .@"extern" => {
                    const elems = try arena.alloc(InternPool.Index, ty.structFieldCount(zcu));
                    @memset(elems, .none);
                    var offset: u64 = 0;
                    var it = ip.loadStructType(ty.toIntern()).iterateRuntimeOrder(ip);
                    while (it.next()) |field_index| {
                        const field_ty = ty.fieldType(field_index, zcu);
                        const pad_bytes = ty.structFieldOffset(field_index, zcu) - offset;
                        pack.padding(pad_bytes);
                        elems[field_index] = (try pack.get(field_ty)).toIntern();
                        offset += pad_bytes + field_ty.abiSize(zcu);
                    }
                    pack.padding(ty.abiSize(zcu) - offset);
                    // Any fields which do not have runtime bits should be OPV or comptime fields.
                    // Fill those values now.
                    for (elems, 0..) |*elem, field_index| {
                        if (elem.* != .none) continue;
                        const val = (try ty.structFieldValueComptime(pt, field_index)).?;
                        elem.* = val.toIntern();
                    }
                    return pt.aggregateValue(ty, elems);
                },
                .@"packed" => {
                    const backing_int_val = try pack.primitive(ty.bitpackBackingInt(zcu));
                    if (backing_int_val.isUndef(zcu)) return pt.undefValue(ty);
                    return pt.bitpackValue(ty, backing_int_val);
                },
            },
            .@"union" => switch (ty.containerLayout(zcu)) {
                .auto => unreachable, // ill-defined layout
                .@"extern" => {
                    // We will attempt to read as the backing representation. If this emits
                    // `error.ReinterpretDeclRef`, we will try each union field, preferring larger ones.
                    // We will also attempt smaller fields when we get `undefined`, as if some bits are
                    // defined we want to include them.
                    // TODO: this is very very bad. We need a more sophisticated union representation.

                    const prev_unpacked = pack.unpacked;
                    const prev_byte_offset = pack.byte_offset;

                    const backing_ty = try ty.externUnionBackingType(pt);

                    const backing_result: enum { undef, reinterpret_decl_ref } = backing: {
                        const backing_val = pack.get(backing_ty) catch |err| switch (err) {
                            error.ReinterpretDeclRef => break :backing .reinterpret_decl_ref,
                            else => |e| return e,
                        };
                        if (backing_val.isUndef(zcu)) break :backing .undef;
                        return .fromInterned(try pt.internUnion(.{
                            .ty = ty.toIntern(),
                            .tag = .none,
                            .val = backing_val.toIntern(),
                        }));
                    };

                    const field_order = try pack.arena.alloc(u32, ty.unionTagTypeHypothetical(zcu).enumFieldCount(zcu));
                    for (field_order, 0..) |*f, i| f.* = @intCast(i);
                    // Sort `field_order` to put the fields with the largest ABI sizes first.
                    const SizeSortCtx = struct {
                        zcu: *const Zcu,
                        field_types: []const InternPool.Index,
                        fn lessThan(ctx: @This(), a_idx: u32, b_idx: u32) bool {
                            const a_ty: Type = .fromInterned(ctx.field_types[a_idx]);
                            const b_ty: Type = .fromInterned(ctx.field_types[b_idx]);
                            return a_ty.abiSize(ctx.zcu) > b_ty.abiSize(ctx.zcu);
                        }
                    };
                    std.mem.sortUnstable(u32, field_order, SizeSortCtx{
                        .zcu = zcu,
                        .field_types = zcu.typeToUnion(ty).?.field_types.get(ip),
                    }, SizeSortCtx.lessThan);

                    for (field_order) |field_index| {
                        pack.unpacked = prev_unpacked;
                        pack.byte_offset = prev_byte_offset;
                        const field_ty = ty.fieldType(field_index, zcu);
                        const field_val = pack.get(field_ty) catch |err| switch (err) {
                            error.ReinterpretDeclRef => continue,
                            else => |e| return e,
                        };
                        if (field_val.isUndef(zcu)) continue;
                        pack.padding(ty.abiSize(zcu) - field_ty.abiSize(zcu));
                        const tag_val = try pt.enumValueFieldIndex(ty.unionTagTypeHypothetical(zcu), field_index);
                        return pt.unionValue(ty, tag_val, field_val);
                    }

                    // No field could represent the value. Just do whatever happens when we try to read
                    // the backing type - either `undefined` or `error.ReinterpretDeclRef`.
                    switch (backing_result) {
                        .undef => return pt.undefValue(ty),
                        .reinterpret_decl_ref => return error.ReinterpretDeclRef,
                    }
                },
                .@"packed" => {
                    const backing_int_val = try pack.primitive(ty.bitpackBackingInt(zcu));
                    if (backing_int_val.isUndef(zcu)) return pt.undefValue(ty);
                    return pt.bitpackValue(ty, backing_int_val);
                },
            },
            .@"enum" => {
                const tag_int_val = try pack.primitive(ty.intTagType(zcu));
                if (tag_int_val.isUndef(zcu)) return pt.undefValue(ty);
                return pt.enumValue(ty, tag_int_val.toIntern());
            },
            else => return pack.primitive(ty),
        }
    }

    fn padding(pack: *PackValueBytes, num_bytes: u64) void {
        _ = pack.prepareBytes(num_bytes);
    }

    fn primitive(pack: *PackValueBytes, want_ty: Type) (Allocator.Error || error{ReinterpretDeclRef})!Value {
        const pt = pack.pt;
        const zcu = pt.zcu;

        if (try want_ty.onePossibleValue(pt)) |opv| return opv;

        const vals, const byte_offset = pack.prepareBytes(want_ty.abiSize(zcu));

        for (vals) |val| {
            if (!Value.fromInterned(val).isUndef(zcu)) break;
        } else {
            // All bits of the value are `undefined`.
            return pt.undefValue(want_ty);
        }

        // TODO: we need to decide how to handle partially-undef values here.
        // Currently, a value with some undefined bits becomes `0xAA` so that we
        // preserve the well-defined bits, because we can't currently represent
        // a partially-undefined primitive (e.g. an int with some undef bits).
        // In future, we probably want to take one of these two routes:
        // * Define that if any bits are `undefined`, the entire value is `undefined`.
        //   This is a major breaking change, and probably a footgun.
        // * Introduce tracking for partially-undef values at comptime.
        //   This would complicate a lot of operations in Sema, such as basic
        //   arithmetic.
        // This design complexity is tracked by #19634.

        if (vals.len == 1 and
            want_ty.isPtrAtRuntime(zcu) and
            Value.fromInterned(vals[0]).typeOf(zcu).isPtrAtRuntime(zcu))
        {
            return pt.getCoerced(.fromInterned(vals[0]), want_ty);
        }

        // Reinterpret via an in-memory buffer.

        var buf_len: u64 = 0;
        for (vals) |ip_val| {
            const val: Value = .fromInterned(ip_val);
            buf_len += val.typeOf(zcu).abiSize(zcu);
        }

        const buf = try pack.arena.alloc(u8, @intCast(buf_len));
        {
            var offset: usize = 0;
            for (vals) |ip_val| {
                const val: Value = .fromInterned(ip_val);
                const ty = val.typeOf(zcu);
                const size = ty.abiSize(zcu);
                if (val.isUndef(zcu)) {
                    @memset(buf[offset..][0..@intCast(size)], 0xAA);
                } else {
                    val.writeToMemory(zcu, buf[offset..][0..@intCast(size)]) catch |err| switch (err) {
                        error.IllDefinedMemoryLayout => unreachable,
                        else => |e| return e,
                    };
                }
                offset += @intCast(size);
            }
        }
        const bytes = buf[@intCast(byte_offset)..];

        const target = zcu.getTarget();
        const endian = target.cpu.arch.endian();
        switch (want_ty.zigTypeTag(zcu)) {
            .bool => return .makeBool(bytes[0] != 0),
            .int => return .readIntFromMemory(want_ty, pt, bytes, pack.arena),
            .float => switch (want_ty.floatBits(target)) {
                16 => return pt.floatValue(want_ty, @as(f16, @bitCast(std.mem.readInt(u16, bytes[0..2], endian)))),
                32 => return pt.floatValue(want_ty, @as(f32, @bitCast(std.mem.readInt(u32, bytes[0..4], endian)))),
                64 => return pt.floatValue(want_ty, @as(f64, @bitCast(std.mem.readInt(u64, bytes[0..8], endian)))),
                80 => return pt.floatValue(want_ty, @as(f80, @bitCast(std.mem.readInt(u80, bytes[0..10], endian)))),
                128 => return pt.floatValue(want_ty, @as(f128, @bitCast(std.mem.readInt(u128, bytes[0..16], endian)))),
                else => unreachable,
            },
            .pointer => {
                assert(!want_ty.isSlice(zcu));
                const ptr_addr = std.mem.readVarInt(u64, bytes[0..@intCast(want_ty.abiSize(zcu))], endian);
                return pt.ptrIntValue(want_ty, ptr_addr);
            },
            .optional => {
                assert(want_ty.isPtrLikeOptional(zcu));
                const ptr_ty = want_ty.optionalChild(zcu);
                const ptr_addr = std.mem.readVarInt(u64, bytes[0..@intCast(want_ty.abiSize(zcu))], endian);
                return .fromInterned(try pt.intern(.{ .opt = .{
                    .ty = want_ty.toIntern(),
                    .val = if (ptr_addr == 0) .none else (try pt.ptrIntValue(ptr_ty, ptr_addr)).toIntern(),
                } }));
            },
            else => unreachable,
        }
    }

    fn prepareBytes(pack: *PackValueBytes, need_bytes: u64) struct { []const InternPool.Index, u64 } {
        if (need_bytes == 0) return .{ &.{}, 0 };

        const pt = pack.pt;
        const zcu = pt.zcu;

        var bytes: u64 = 0;
        var len: usize = 0;
        while (bytes < pack.byte_offset + need_bytes) {
            bytes += Value.fromInterned(pack.unpacked[len]).typeOf(zcu).abiSize(zcu);
            len += 1;
        }

        const result_vals = pack.unpacked[0..len];
        const result_offset = pack.byte_offset;

        const extra_bytes = bytes - pack.byte_offset - need_bytes;
        if (extra_bytes == 0) {
            pack.unpacked = pack.unpacked[len..];
            pack.byte_offset = 0;
        } else {
            pack.unpacked = pack.unpacked[len - 1 ..];
            pack.byte_offset = Value.fromInterned(pack.unpacked[0]).typeOf(zcu).abiSize(zcu) - extra_bytes;
        }

        return .{ result_vals, result_offset };
    }
};

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Sema = @import("../Sema.zig");
const Zcu = @import("../Zcu.zig");
const InternPool = @import("../InternPool.zig");
const Type = @import("../Type.zig");
const Value = @import("../Value.zig");
const CompileError = Zcu.CompileError;
