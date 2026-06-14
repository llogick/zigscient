//! A buffered DER encoder.
//!
//! Prefers calling container's `fn encodeDer(self: @This(), encoder: *der.Encoder)`.
//! That function should encode values, lengths, then tags.
buffer: ArrayListReverse,
/// The field tag set by a parent container.
/// This is needed because we might visit an implicitly tagged container with a `fn encodeDer`.
field_tag: ?FieldTag = null,

pub fn init(allocator: std.mem.Allocator) Encoder {
    return Encoder{ .buffer = ArrayListReverse.init(allocator) };
}

pub fn deinit(self: *Encoder) void {
    self.buffer.deinit();
}

/// Encode any value.
pub fn any(self: *Encoder, val: anytype) !void {
    const T = @TypeOf(val);
    try self.anyTag(Tag.fromZig(T), val);
}

fn anyTag(self: *Encoder, tag_: Tag, val: anytype) !void {
    const T = @TypeOf(val);
    if (std.meta.hasFn(T, "encodeDer")) return try val.encodeDer(self);
    const outer_field_tag = self.field_tag;
    const start = self.buffer.data.len;
    const merged_tag = self.mergedTag(tag_);

    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            inline for (0..info.field_names.len) |i| {
                const f_idx = info.field_names.len - i - 1;
                const f_name = info.field_names[f_idx];
                const f_type = info.field_types[f_idx];
                const f_attrs = info.field_attrs[f_idx];
                const field_val = @field(val, f_name);
                const field_tag = FieldTag.fromContainer(T, f_name);

                // > The encoding of a set value or sequence value shall not include an encoding for any
                // > component value which is equal to its default value.
                const is_default = if (f_attrs.@"comptime") false else if (f_attrs.defaultValue(f_type)) |default_val| brk: {
                    break :brk std.mem.eql(u8, std.mem.asBytes(&default_val), std.mem.asBytes(&field_val));
                } else false;
                const is_null_optional = if (@typeInfo(f_type) == .optional) field_val == null else false;

                if (!is_default and !is_null_optional) {
                    const start2 = self.buffer.data.len;
                    self.field_tag = field_tag;
                    // will merge with self.field_tag.
                    // may mutate self.field_tag.
                    try self.anyTag(Tag.fromZig(f_type), field_val);
                    if (field_tag) |ft| {
                        if (ft.explicit) {
                            try self.length(self.buffer.data.len - start2);
                            try self.tag(ft.toTag());
                            self.field_tag = null;
                        }
                    }
                }
            }
            self.field_tag = outer_field_tag;
        },
        .bool => try self.buffer.prependSlice(&[_]u8{if (val) 0xff else 0}),
        .int => try self.int(T, val),
        .@"enum" => |e| {
            if (@hasDecl(T, "oids")) {
                return self.any(T.oids.enumToOid(val));
            } else {
                try self.int(e.tag_type, @intFromEnum(val));
            }
        },
        .optional => if (val) |v| return try self.anyTag(tag_, v) else return,
        .null => {},
        else => @compileError("cannot encode type " ++ @typeName(T)),
    }

    try self.length(self.buffer.data.len - start);
    try self.tag(merged_tag);
}

/// Encode a tag.
pub fn tag(self: *Encoder, tag_: Tag) !void {
    const t = self.mergedTag(tag_);
    var buf: [Tag.max_encoded_len]u8 = undefined;
    try self.buffer.prependSlice(t.encodeToSlice(&buf));
}

fn mergedTag(self: *Encoder, tag_: Tag) Tag {
    var res = tag_;
    if (self.field_tag) |ft| {
        if (!ft.explicit) {
            res.number = @enumFromInt(ft.number);
            res.class = ft.class;
        }
    }
    return res;
}

/// Encode a length.
pub fn length(self: *Encoder, len: usize) !void {
    if (len < 128) return self.buffer.prependSlice(&.{@intCast(len)});
    const len32 = std.math.cast(u32, len) orelse return error.InvalidLength;
    var buf: [@sizeOf(u32) + 1]u8 = undefined;
    std.mem.writeInt(u32, buf[1..], len32, .big);
    var first: usize = 1;
    while (buf[first] == 0) first += 1;
    buf[first - 1] = @intCast((buf.len - first) | 0x80);
    return self.buffer.prependSlice(buf[first - 1 ..]);
}

/// Encode a tag and length-prefixed bytes.
pub fn tagBytes(self: *Encoder, tag_: Tag, bytes: []const u8) !void {
    try self.buffer.prependSlice(bytes);
    try self.length(bytes.len);
    try self.tag(tag_);
}

/// Write raw bytes. The encoder builds its output back-to-front, so chained
/// calls should be made in reverse of the desired on-wire order.
pub fn prependBytes(self: *Encoder, bytes: []const u8) !void {
    return self.buffer.prependSlice(bytes);
}

fn int(self: *Encoder, comptime T: type, value: T) !void {
    const info = @typeInfo(T).int;
    const Unsigned = @Int(.unsigned, info.bits);
    const pad: u8 = if (info.signedness == .signed and value < 0) 0xff else 0;
    var buf: [@sizeOf(Unsigned) + 1]u8 = undefined;
    buf[0] = pad;
    std.mem.writeInt(Unsigned, buf[1..], @bitCast(value), .big);

    var first: usize = 0;
    while (first + 1 < buf.len and buf[first] == pad and (buf[first + 1] ^ pad) & 0x80 == 0) first += 1;
    try self.buffer.prependSlice(buf[first..]);
}

test int {
    const allocator = std.testing.allocator;
    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    try encoder.int(u8, 0);
    try std.testing.expectEqualSlices(u8, &.{0}, encoder.buffer.data);

    encoder.buffer.clearAndFree();
    try encoder.int(u16, 0x00ff);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0xff }, encoder.buffer.data);

    encoder.buffer.clearAndFree();
    try encoder.int(u32, 0xffff);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0xff, 0xff }, encoder.buffer.data);

    encoder.buffer.clearAndFree();
    try encoder.int(u32, 0x01020304);
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0x02, 0x03, 0x04 }, encoder.buffer.data);

    encoder.buffer.clearAndFree();
    try encoder.int(u8, 127);
    try std.testing.expectEqualSlices(u8, &.{0x7f}, encoder.buffer.data);

    encoder.buffer.clearAndFree();
    try encoder.int(u16, 128);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0x80 }, encoder.buffer.data);

    encoder.buffer.clearAndFree();
    try encoder.int(u16, 256);
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0x00 }, encoder.buffer.data);

    encoder.buffer.clearAndFree();
    try encoder.int(u8, 128);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0x80 }, encoder.buffer.data);

    encoder.buffer.clearAndFree();
    try encoder.int(u8, 255);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0xff }, encoder.buffer.data);

    encoder.buffer.clearAndFree();
    try encoder.int(u16, 0x8000);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0x80, 0 }, encoder.buffer.data);

    encoder.buffer.clearAndFree();
    try encoder.int(i8, -1);
    try std.testing.expectEqualSlices(u8, &.{0xff}, encoder.buffer.data);

    encoder.buffer.clearAndFree();
    try encoder.int(i8, -128);
    try std.testing.expectEqualSlices(u8, &.{0x80}, encoder.buffer.data);

    encoder.buffer.clearAndFree();
    try encoder.int(i16, -129);
    try std.testing.expectEqualSlices(u8, &.{ 0xff, 0x7f }, encoder.buffer.data);
}

test length {
    const allocator = std.testing.allocator;
    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    try encoder.length(127);
    try std.testing.expectEqualSlices(u8, &.{0x7f}, encoder.buffer.data);

    encoder.buffer.clearAndFree();
    try encoder.length(128);
    try std.testing.expectEqualSlices(u8, &.{ 0x81, 0x80 }, encoder.buffer.data);

    encoder.buffer.clearAndFree();
    try encoder.length(255);
    try std.testing.expectEqualSlices(u8, &.{ 0x81, 0xff }, encoder.buffer.data);

    encoder.buffer.clearAndFree();
    try encoder.length(256);
    try std.testing.expectEqualSlices(u8, &.{ 0x82, 0x01, 0x00 }, encoder.buffer.data);

    encoder.buffer.clearAndFree();
    try encoder.length(65535);
    try std.testing.expectEqualSlices(u8, &.{ 0x82, 0xff, 0xff }, encoder.buffer.data);

    encoder.buffer.clearAndFree();
    try encoder.length(65536);
    try std.testing.expectEqualSlices(u8, &.{ 0x83, 0x01, 0x00, 0x00 }, encoder.buffer.data);
}

const std = @import("std");
const Oid = @import("../Oid.zig");
const asn1 = @import("../../asn1.zig");
const ArrayListReverse = @import("./ArrayListReverse.zig");
const Tag = asn1.Tag;
const FieldTag = asn1.FieldTag;
const Encoder = @This();
