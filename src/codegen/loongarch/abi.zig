const std = @import("std");
const InternPool = @import("../../InternPool.zig");
const Type = @import("../../Type.zig");
const Zcu = @import("../../Zcu.zig");

pub const Class = union(enum) {
    ignored,
    gar,
    far,
    member: Type,
    member_pair: [2]Type,
    memory_gar,
    memory_gar_pair,
    address,

    fn combineMember(container_class: Class, member_class: Class, member_ty: Type) Class {
        const second_member_ty = switch (member_class) {
            .ignored => return container_class,
            .gar, .far => member_ty,
            .member => |second_member_ty| second_member_ty,
            .member_pair, .memory_gar, .memory_gar_pair, .address => return .address,
        };
        return switch (container_class) {
            .ignored => .{ .member = second_member_ty },
            .gar, .far, .memory_gar, .memory_gar_pair => unreachable,
            .member => |first_member_ty| .{ .member_pair = .{ first_member_ty, second_member_ty } },
            .member_pair, .address => .address,
        };
    }
};

pub fn classifyType(ty: Type, zcu: *Zcu) Class {
    return Classifier.init(zcu).classifyType(ty);
}

const Classifier = struct {
    zcu: *Zcu,
    target: *const std.Target,
    grlen: u8,
    frlen: u8,

    fn init(zcu: *Zcu) Classifier {
        const target = zcu.getTarget();
        return .{
            .zcu = zcu,
            .target = target,
            .grlen = switch (target.cpu.arch) {
                else => unreachable,
                .loongarch32 => 32,
                .loongarch64 => 64,
            },
            .frlen = if (target.cpu.has(.loongarch, .d))
                64
            else if (target.cpu.has(.loongarch, .f))
                32
            else
                0,
        };
    }

    fn classifyType(c: Classifier, ty: Type) Class {
        switch (ty.zigTypeTag(c.zcu)) {
            .type,
            .comptime_float,
            .comptime_int,
            .undefined,
            .null,
            .error_union,
            .error_set,
            .@"fn",
            .@"opaque",
            .frame,
            .@"anyframe",
            .enum_literal,
            .spirv,
            => unreachable,
            .void, .noreturn => return .ignored,
            .bool => return .gar,
            .int, .@"enum" => {
                const bits = ty.intInfo(c.zcu).bits;
                if (bits == 0) return .ignored;
                if (bits <= c.grlen) return .gar;
                if (bits <= 2 * c.grlen) return .memory_gar_pair;
                return .address;
            },
            .float => {
                const bits = ty.floatBits(c.target);
                if (bits <= c.frlen) return .far;
                if (bits <= c.grlen) return .gar;
                if (bits <= 2 * c.grlen) return .memory_gar_pair;
                return .address;
            },
            .pointer, .optional => return .gar,
            .array => {
                var class: Class = .ignored;
                const elem_ty = ty.childType(c.zcu);
                const elem_class = c.classifyType(elem_ty);
                for (0..std.math.lossyCast(usize, ty.arrayLen(c.zcu))) |_| {
                    class = class.combineMember(elem_class, elem_ty);
                    if (class == .address) break;
                }
                if (class != .address) return class;
            },
            .@"struct" => switch (ty.containerLayout(c.zcu)) {
                .auto => unreachable,
                .@"extern" => {
                    var class: Class = .ignored;
                    var field_it: InternPool.LoadedStructType.RuntimeOrderIterator = if (c.zcu.typeToStruct(ty)) |loaded_struct|
                        loaded_struct.iterateRuntimeOrder(&c.zcu.intern_pool)
                    else
                        .{ .runtime_order = null, .fields_len = ty.structFieldCount(c.zcu), .next_index = 0 };
                    while (field_it.next()) |field_index| {
                        const field_ty = ty.fieldType(field_index, c.zcu);
                        class = class.combineMember(c.classifyType(field_ty), field_ty);
                        if (class == .address) break;
                    }
                    if (class != .address) return class;
                },
                .@"packed" => return c.classifyType(ty.backingIntType(c.zcu)),
            },
            .@"union" => switch (ty.containerLayout(c.zcu)) {
                .auto => unreachable,
                .@"extern" => {},
                .@"packed" => return c.classifyType(ty.backingIntType(c.zcu)),
            },
            .vector => {},
        }
        const size = ty.abiSize(c.zcu);
        if (size <= @divExact(c.grlen, 8)) return .memory_gar;
        if (size <= @divExact(2 * c.grlen, 8)) return .memory_gar_pair;
        return .address;
    }
};
