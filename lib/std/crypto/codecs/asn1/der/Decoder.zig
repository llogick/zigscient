//! A secure DER parser that:
//! - Prefers calling `fn decodeDer(self: @This(), decoder: *der.Decoder)`
//! - Does NOT allocate. If you wish to parse lists you can do so lazily
//!   with an opaque type.
//! - Does NOT read memory outside `bytes`.
//! - Does NOT return elements with slices outside `bytes`.
//! - Errors on values that do NOT follow DER rules:
//!   - Lengths that could be represented in a shorter form.
//!   - Booleans that are not 0xff or 0x00.
bytes: []const u8,
index: Index = 0,
/// The field tag of the most recently visited field.
/// This is needed because we might visit an implicitly tagged container with a `fn decodeDer`.
field_tag: ?FieldTag = null,

/// Expect a value.
pub fn any(self: *Decoder, comptime T: type) !T {
    if (std.meta.hasFn(T, "decodeDer")) return try T.decodeDer(self);

    const tag = Tag.fromZig(T).toExpected();
    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            const ele = try self.element(tag);
            defer self.index = ele.slice.end; // don't force parsing all fields

            var res: T = undefined;

            inline for (info.field_names, info.field_types, info.field_attrs) |f_name, f_type, f_attrs| {
                self.field_tag = FieldTag.fromContainer(T, f_name);

                if (self.field_tag) |ft| {
                    if (ft.explicit) {
                        const seq = try self.element(ft.toTag().toExpected());
                        self.index = seq.slice.start;
                        self.field_tag = null;
                    }
                }

                @field(res, f_name) = self.any(f_type) catch |err| brk: {
                    if (f_attrs.defaultValue(f_type)) |d| {
                        break :brk d;
                    }
                    return err;
                };
                // DER encodes null values by skipping them.
                if (@typeInfo(f_type) == .optional and @field(res, f_name) == null) {
                    if (f_attrs.defaultValue(f_type)) |d| @field(res, f_name) = d;
                }
            }

            return res;
        },
        .bool => {
            const ele = try self.element(tag);
            const bytes = self.view(ele);
            if (bytes.len != 1) return error.InvalidBool;

            return switch (bytes[0]) {
                0x00 => false,
                0xff => true,
                else => error.InvalidBool,
            };
        },
        .int => {
            const ele = try self.element(tag);
            const bytes = self.view(ele);
            return try int(T, bytes);
        },
        .@"enum" => |e| {
            const ele = try self.element(tag);
            const bytes = self.view(ele);
            if (@hasDecl(T, "oids")) {
                return T.oids.oidToEnum(bytes) orelse return error.UnknownOid;
            }
            return @enumFromInt(try int(e.tag_type, bytes));
        },
        .optional => |o| return self.any(o.child) catch return null,
        else => @compileError("cannot decode type " ++ @typeName(T)),
    }
}

//// Expect a sequence.
pub fn sequence(self: *Decoder) !Element {
    return try self.element(ExpectedTag.init(.sequence, true, .universal));
}

//// Expect an element.
pub fn element(
    self: *Decoder,
    expected: ExpectedTag,
) (error{ EndOfStream, UnexpectedElement } || Element.DecodeError)!Element {
    if (self.index >= self.bytes.len) return error.EndOfStream;

    const res = try Element.decode(self.bytes, self.index);
    var e = expected;
    if (self.field_tag) |ft| {
        e.number = @enumFromInt(ft.number);
        e.class = ft.class;
    }
    if (!e.match(res.tag)) {
        return error.UnexpectedElement;
    }

    self.index = if (res.tag.constructed) res.slice.start else res.slice.end;
    return res;
}

/// View of element bytes.
pub fn view(self: Decoder, elem: Element) []const u8 {
    return elem.slice.view(self.bytes);
}

fn int(comptime T: type, value: []const u8) error{ NonCanonical, LargeValue }!T {
    const info = @typeInfo(T).int;
    if (info.bits % 8 != 0) @compileError("T must be byte aligned");

    if (value.len == 0) return error.NonCanonical;
    if (value.len >= 2) {
        if (value[0] == 0x00 and value[1] & 0x80 == 0) return error.NonCanonical;
        if (value[0] == 0xff and value[1] & 0x80 != 0) return error.NonCanonical;
    }

    const had_sign_byte = value.len >= 2 and value[0] == 0x00;
    const bytes = if (had_sign_byte) value[1..] else value;
    const der_negative = !had_sign_byte and bytes[0] & 0x80 != 0;

    switch (info.signedness) {
        .unsigned => {
            if (der_negative) return error.LargeValue;
            if (bytes.len > @sizeOf(T)) return error.LargeValue;
        },
        .signed => {
            const max_len: usize = if (had_sign_byte) @sizeOf(T) - 1 else @sizeOf(T);
            if (bytes.len > max_len) return error.LargeValue;
        },
    }

    var buf: [@sizeOf(T)]u8 = @splat(if (der_negative) 0xff else 0);
    @memcpy(buf[buf.len - bytes.len ..], bytes);
    return std.mem.readInt(T, &buf, .big);
}

test int {
    try expectEqual(@as(u8, 1), try int(u8, &[_]u8{1}));
    try expectError(error.NonCanonical, int(u8, &[_]u8{ 0, 1 }));
    try expectError(error.NonCanonical, int(u8, &[_]u8{ 0xff, 0xff }));

    const big = [_]u8{ 0xef, 0xff };
    try expectError(error.LargeValue, int(u8, &big));
    try expectError(error.LargeValue, int(u16, &big));
    try expectEqual(@as(i16, -4097), try int(i16, &big));

    try expectEqual(@as(u16, 255), try int(u16, &.{ 0x00, 0xff }));
    try expectEqual(@as(u16, 0x8000), try int(u16, &.{ 0x00, 0x80, 0x00 }));

    try expectEqual(@as(i8, -1), try int(i8, &.{0xff}));
    try expectEqual(@as(i16, -1), try int(i16, &.{0xff}));
    try expectEqual(@as(i16, -128), try int(i16, &.{0x80}));
    try expectEqual(@as(i16, -129), try int(i16, &.{ 0xff, 0x7f }));
    try expectEqual(@as(i16, 255), try int(i16, &.{ 0x00, 0xff }));
    try expectEqual(@as(i32, 0x7fffffff), try int(i32, &.{ 0x7f, 0xff, 0xff, 0xff }));

    try expectError(error.LargeValue, int(i8, &.{ 0x00, 0xff }));
    try expectError(error.LargeValue, int(i16, &.{ 0x00, 0x80, 0x00 }));
    try expectError(error.LargeValue, int(i32, &.{ 0x00, 0x80, 0x00, 0x00, 0x00 }));

    try expectError(error.LargeValue, int(u8, &.{0xff}));
    try expectError(error.LargeValue, int(u16, &.{0x80}));
    try expectError(error.LargeValue, int(u32, &.{ 0x80, 0x00, 0x00, 0x00 }));
}

test Decoder {
    var parser = Decoder{ .bytes = @embedFile("./testdata/id_ecc.pub.der") };
    const seq = try parser.sequence();

    {
        const seq2 = try parser.sequence();
        _ = try parser.element(ExpectedTag.init(.oid, false, .universal));
        _ = try parser.element(ExpectedTag.init(.oid, false, .universal));

        try std.testing.expectEqual(parser.index, seq2.slice.end);
    }
    _ = try parser.element(ExpectedTag.init(.bitstring, false, .universal));

    try std.testing.expectEqual(parser.index, seq.slice.end);
    try std.testing.expectEqual(parser.index, parser.bytes.len);
}

const std = @import("std");
const builtin = @import("builtin");
const asn1 = @import("../../asn1.zig");
const Oid = @import("../Oid.zig");

const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const Decoder = @This();
const Index = asn1.Index;
const Tag = asn1.Tag;
const FieldTag = asn1.FieldTag;
const ExpectedTag = asn1.ExpectedTag;
const Element = asn1.Element;
