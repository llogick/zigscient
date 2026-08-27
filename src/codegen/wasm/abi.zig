//! Classifies Zig types to follow the C-ABI for Wasm.
//! The convention for Wasm's C-ABI can be found at the tool-conventions repo:
//! https://github.com/WebAssembly/tool-conventions/blob/main/BasicCABI.md
//! When not targeting the C-ABI, Zig is allowed to do derail from this convention.
//! Note: Above mentioned document is not an official specification, therefore called a convention.

const std = @import("std");
const Target = std.Target;
const assert = std.debug.assert;

const Type = @import("../../Type.zig");
const Zcu = @import("../../Zcu.zig");

/// Describes how the Wasm backend represents a C ABI value.
pub const Class = union(enum) {
    direct: Type,
    double_i64,
    indirect,
    unrolled: struct {
        elem_type: Type,
        len: u32,
    },
};

pub const LlvmClass = union(enum) {
    direct: Type,
    indirect,
};

pub fn classifyType(ty: Type, zcu: *const Zcu, target: *const Target) Class {
    if (ty.zigTypeTag(zcu) == .vector) {
        if (!(ty.bitSize(zcu) == 128 and target.cpu.has(.wasm, .simd128))) {
            const elem_type = ty.childType(zcu);
            return .{ .unrolled = .{
                .elem_type = elem_type,
                .len = ty.vectorLen(zcu),
            } };
        }
        return .{ .direct = ty };
    }

    return switch (classifyTypeForLlvm(ty, zcu)) {
        .direct => |scalar_ty| if (scalar_ty.bitSize(zcu) > 64)
            .double_i64
        else
            .{ .direct = scalar_ty },
        .indirect => .indirect,
    };
}

pub fn classifyTypeForLlvm(ty: Type, zcu: *const Zcu) LlvmClass {
    const ip = &zcu.intern_pool;
    assert(ty.hasRuntimeBits(zcu));
    switch (ty.zigTypeTag(zcu)) {
        .int, .@"enum", .error_set => return .{ .direct = ty },
        .float => return switch (ty.floatBits(zcu.getTarget())) {
            else => unreachable,
            16, 32, 64, 128 => .{ .direct = ty },
            80 => .indirect,
        },
        .bool => return .{ .direct = ty },
        .vector => return .{ .direct = ty },
        .array => return .indirect,
        .optional => {
            assert(ty.isPtrLikeOptional(zcu));
            return .{ .direct = ty };
        },
        .pointer => {
            assert(!ty.isSlice(zcu));
            return .{ .direct = ty };
        },
        .@"struct" => {
            const struct_type = zcu.typeToStruct(ty).?;
            switch (struct_type.layout) {
                .auto => unreachable,
                .@"packed" => return .{ .direct = ty },
                .@"extern" => {},
            }
            var opt_single_field_ty: ?Type = null;
            for (struct_type.field_types.get(ip), 0..) |field_ty_index, field_index| {
                const field_ty: Type = .fromInterned(field_ty_index);
                if (!field_ty.hasRuntimeBits(zcu)) continue;

                if (opt_single_field_ty != null) {
                    return .indirect;
                }

                const field_align = struct_type.field_aligns.getOrNone(ip, field_index);
                if (field_align != .none and field_align.compareStrict(.gt, field_ty.abiAlignment(zcu))) {
                    return .indirect;
                }
                opt_single_field_ty = field_ty;
            }
            const single_field_ty = opt_single_field_ty.?;
            if (single_field_ty.zigTypeTag(zcu) == .array) {
                switch (single_field_ty.arrayLenIncludingSentinel(zcu)) {
                    0 => unreachable,
                    1 => return classifyTypeForLlvm(single_field_ty.childType(zcu), zcu),
                    else => {},
                }
            }
            return classifyTypeForLlvm(single_field_ty, zcu);
        },
        .@"union" => {
            const union_obj = zcu.typeToUnion(ty).?;
            if (union_obj.layout == .@"packed") {
                return .{ .direct = ty };
            }
            const layout = ty.unionGetLayout(zcu);
            assert(layout.tag_size == 0);
            if (union_obj.field_types.len > 1) return .indirect;
            const first_field_ty = Type.fromInterned(union_obj.field_types.get(ip)[0]);
            if (first_field_ty.zigTypeTag(zcu) == .array) {
                switch (first_field_ty.arrayLenIncludingSentinel(zcu)) {
                    0 => unreachable,
                    1 => return classifyTypeForLlvm(first_field_ty.childType(zcu), zcu),
                    else => {},
                }
            }
            return classifyTypeForLlvm(first_field_ty, zcu);
        },
        .error_union,
        .frame,
        .@"anyframe",
        .noreturn,
        .void,
        .type,
        .comptime_float,
        .comptime_int,
        .undefined,
        .null,
        .@"fn",
        .@"opaque",
        .spirv,
        .enum_literal,
        => unreachable,
    }
}
