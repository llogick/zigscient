const assert = std.debug.assert;
const std = @import("std");
const InternPool = @import("../../InternPool.zig");
const Type = @import("../../Type.zig");
const Zcu = @import("../../Zcu.zig");

pub const Context = enum { ret, arg };

pub const Class = enum {
    none,
    double_or_float,
    vector,
    simple,
    simple_aggregate,
    pointer,
};

pub fn classifyType(ty: Type, context: Context, zcu: *Zcu) Class {
    tag: switch (ty.zigTypeTag(zcu)) {
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
        .void, .noreturn => return .none,
        .bool => return .simple,
        .int, .@"enum" => return switch (ty.intInfo(zcu).bits) {
            0 => .none,
            1...64 => .simple,
            else => .pointer,
        },
        .float => switch (ty.floatBits(zcu.getTarget())) {
            else => unreachable,
            16, 32, 64 => return .double_or_float,
            80 => {},
            128 => return .pointer,
        },
        .pointer, .optional => return .simple,
        .array => {},
        .@"struct", .@"union" => |tag| switch (ty.containerLayout(zcu)) {
            .auto => unreachable,
            .@"extern" => switch (context) {
                .ret => {},
                .arg => {
                    var class: Class = .none;
                    for (0..switch (tag) {
                        else => unreachable,
                        .@"struct" => ty.structFieldCount(zcu),
                        .@"union" => ty.unionTagTypeHypothetical(zcu).enumFieldCount(zcu),
                    }) |field_index| {
                        switch (tag) {
                            else => unreachable,
                            .@"struct" => if (ty.structFieldIsComptime(field_index, zcu)) continue,
                            .@"union" => {},
                        }
                        const field_class = classifyType(ty.fieldType(field_index, zcu), context, zcu);
                        if (field_class == .none) continue;
                        if (class != .none) break :tag;
                        class = field_class;
                    }
                    return class;
                },
            },
            .@"packed" => return classifyType(ty.backingIntType(zcu), context, zcu),
        },
        .vector => return if (ty.abiSize(zcu) <= 16) .vector else .pointer,
    }
    return switch (ty.abiSize(zcu)) {
        0 => .none,
        1, 2, 4, 8 => switch (context) {
            .ret => .pointer,
            .arg => .simple_aggregate,
        },
        else => .pointer,
    };
}
