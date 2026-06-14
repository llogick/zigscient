//! ASN.1 types for public consumption.
const std = @import("std");
pub const der = @import("./asn1/der.zig");
pub const Oid = @import("./asn1/Oid.zig");

pub const Index = u32;

pub const Tag = struct {
    number: Number,
    /// Whether this ASN.1 type contains other ASN.1 types.
    constructed: bool,
    class: Class,

    /// These values apply to class == .universal.
    pub const Number = enum(u16) {
        // 0 is reserved by spec
        boolean = 1,
        integer = 2,
        bitstring = 3,
        octetstring = 4,
        null = 5,
        oid = 6,
        object_descriptor = 7,
        real = 9,
        enumerated = 10,
        embedded = 11,
        string_utf8 = 12,
        oid_relative = 13,
        time = 14,
        // 15 is reserved to mean that the tag is >= 32
        sequence = 16,
        /// Elements may appear in any order.
        sequence_of = 17,
        string_numeric = 18,
        string_printable = 19,
        string_teletex = 20,
        string_videotex = 21,
        string_ia5 = 22,
        utc_time = 23,
        generalized_time = 24,
        string_graphic = 25,
        string_visible = 26,
        string_general = 27,
        string_universal = 28,
        string_char = 29,
        string_bmp = 30,
        date = 31,
        time_of_day = 32,
        date_time = 33,
        duration = 34,
        /// IRI = Internationalized Resource Identifier
        oid_iri = 35,
        oid_iri_relative = 36,
        _,
    };

    pub const Class = enum(u2) {
        universal,
        application,
        context_specific,
        private,
    };

    pub fn init(number: Tag.Number, constructed: bool, class: Tag.Class) Tag {
        return .{ .number = number, .constructed = constructed, .class = class };
    }

    pub fn universal(number: Tag.Number, constructed: bool) Tag {
        return .{ .number = number, .constructed = constructed, .class = .universal };
    }

    pub fn decode(reader: *std.Io.Reader) !Tag {
        const tag1: FirstTag = @bitCast(try reader.takeByte());
        var number: std.meta.Tag(Tag.Number) = tag1.number;

        if (tag1.number == high_tag_marker) {
            number = 0;
            for (0..max_continuations) |i| {
                const next: NextTag = @bitCast(try reader.takeByte());
                if (i == 0 and next.number == 0) return error.InvalidEncoding;
                number = std.math.shlExact(@TypeOf(number), number, 7) catch return error.InvalidEncoding;
                number |= next.number;
                if (!next.continues) break;
            } else return error.InvalidEncoding;
            if (number < high_tag_marker) return error.InvalidEncoding;
        }

        return Tag{
            .number = @enumFromInt(number),
            .constructed = tag1.constructed,
            .class = tag1.class,
        };
    }

    pub fn encodeToSlice(self: Tag, buf: *[max_encoded_len]u8) []const u8 {
        const n = @intFromEnum(self.number);
        var tag1: FirstTag = .{
            .number = undefined,
            .constructed = self.constructed,
            .class = self.class,
        };

        if (n < high_tag_marker) {
            tag1.number = @intCast(n);
            buf[0] = @bitCast(tag1);
            return buf[0..1];
        }

        tag1.number = high_tag_marker;
        buf[0] = @bitCast(tag1);

        const bits_used = @bitSizeOf(@TypeOf(n)) - @clz(n);
        const len = std.math.divCeil(usize, bits_used, 7) catch unreachable;

        var remaining = n;
        var i = len;
        while (i > 0) : (i -= 1) {
            buf[i] = @bitCast(NextTag{
                .number = @truncate(remaining),
                .continues = i != len,
            });
            remaining >>= 7;
        }
        return buf[0 .. 1 + len];
    }

    pub fn encode(self: Tag, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        var buf: [max_encoded_len]u8 = undefined;
        try writer.writeAll(self.encodeToSlice(&buf));
    }

    pub const max_encoded_len = 1 + (std.math.divCeil(
        comptime_int,
        @bitSizeOf(std.meta.Tag(Tag.Number)),
        7,
    ) catch unreachable);
    const max_continuations = max_encoded_len - 1;
    const high_tag_marker = std.math.maxInt(u5);

    const FirstTag = packed struct(u8) { number: u5, constructed: bool, class: Tag.Class };
    const NextTag = packed struct(u8) { number: u7, continues: bool };

    pub fn toExpected(self: Tag) ExpectedTag {
        return ExpectedTag{
            .number = self.number,
            .constructed = self.constructed,
            .class = self.class,
        };
    }

    pub fn fromZig(comptime T: type) Tag {
        switch (@typeInfo(T)) {
            .@"struct", .@"enum", .@"union" => {
                if (@hasDecl(T, "asn1_tag")) return T.asn1_tag;
            },
            else => {},
        }

        switch (@typeInfo(T)) {
            .@"struct", .@"union" => return universal(.sequence, true),
            .bool => return universal(.boolean, false),
            .int => return universal(.integer, false),
            .@"enum" => |e| {
                if (@hasDecl(T, "oids")) return Oid.asn1_tag;
                return universal(if (e.is_exhaustive) .enumerated else .integer, false);
            },
            .optional => |o| return fromZig(o.child),
            .null => return universal(.null, false),
            else => @compileError("cannot map Zig type to asn1_tag " ++ @typeName(T)),
        }
    }
};

test Tag {
    const buf = [_]u8{0xa3};
    var reader: std.Io.Reader = .fixed(&buf);
    const t = Tag.decode(&reader);
    try std.testing.expectEqual(Tag.init(@enumFromInt(3), true, .context_specific), t);
}

test "Tag.encode produces the exact bytes from X.690" {
    const cases = [_]struct { number: u16, expected: []const u8 }{
        .{ .number = 0, .expected = &.{0x00} },
        .{ .number = 30, .expected = &.{0x1e} },
        .{ .number = 31, .expected = &.{ 0x1f, 0x1f } },
        .{ .number = 127, .expected = &.{ 0x1f, 0x7f } },
        .{ .number = 128, .expected = &.{ 0x1f, 0x81, 0x00 } },
        .{ .number = 16383, .expected = &.{ 0x1f, 0xff, 0x7f } },
        .{ .number = 16384, .expected = &.{ 0x1f, 0x81, 0x80, 0x00 } },
        .{ .number = 65535, .expected = &.{ 0x1f, 0x83, 0xff, 0x7f } },
    };
    for (cases) |c| {
        const tag = Tag.init(@enumFromInt(c.number), false, .universal);
        var buf: [Tag.max_encoded_len]u8 = undefined;
        try std.testing.expectEqualSlices(u8, c.expected, tag.encodeToSlice(&buf));
    }
}

test "Tag.encode/decode round trip" {
    for ([_]u16{ 0, 30, 31, 32, 127, 128, 16383, 16384, 65535 }) |n| {
        const tag = Tag.init(@enumFromInt(n), false, .universal);
        var buf: [Tag.max_encoded_len]u8 = undefined;
        const encoded = tag.encodeToSlice(&buf);
        var reader: std.Io.Reader = .fixed(encoded);
        try std.testing.expectEqual(tag, try Tag.decode(&reader));
        try std.testing.expectEqual(encoded.len, reader.seek);
    }
}

test "Tag.decode rejects non-minimal high-tag form" {
    for ([_][]const u8{ &.{ 0x1f, 0x1e }, &.{ 0x1f, 0x80, 0x01 } }) |bytes| {
        var reader: std.Io.Reader = .fixed(bytes);
        try std.testing.expectError(error.InvalidEncoding, Tag.decode(&reader));
    }
}

/// A decoded view.
pub const Element = struct {
    tag: Tag,
    slice: Slice,

    pub const Slice = struct {
        start: Index,
        end: Index,

        pub fn len(self: Slice) Index {
            return self.end - self.start;
        }

        pub fn view(self: Slice, bytes: []const u8) []const u8 {
            return bytes[self.start..self.end];
        }
    };

    pub const DecodeError = error{ EndOfStream, InvalidEncoding };

    /// Safely decode a DER/BER/CER element at `index`:
    /// - Ensures length uses shortest form
    /// - Ensures length is within `bytes`
    /// - Ensures length is less than `std.math.maxInt(Index)`
    pub fn decode(bytes: []const u8, index: Index) DecodeError!Element {
        if (index > bytes.len) return error.EndOfStream;
        var reader: std.Io.Reader = .fixed(bytes[index..]);

        const tag = Tag.decode(&reader) catch |err| switch (err) {
            error.ReadFailed => unreachable, // it's all fixed buffers
            else => |e| return e,
        };
        const size_or_len_size = reader.takeByte() catch |err| switch (err) {
            error.ReadFailed => unreachable, // it's all fixed buffers
            else => |e| return e,
        };

        const len = if (size_or_len_size < 128)
            // short form between 0-127
            size_or_len_size
        else blk: {
            // long form between 0 and std.math.maxInt(u1024)
            const len_size: u7 = @truncate(size_or_len_size);
            if (len_size > @sizeOf(Index)) return error.EndOfStream;

            const len = reader.takeVarInt(Index, .big, len_size) catch |err| switch (err) {
                error.ReadFailed => unreachable, // it's all fixed buffers
                else => |e| return e,
            };
            if (len < 128) return error.EndOfStream; // should have used short form

            break :blk len;
        };

        const start = index + @as(Index, @intCast(reader.seek));
        const end = std.math.add(Index, start, len) catch return error.EndOfStream;
        if (end > bytes.len) return error.EndOfStream;

        return Element{ .tag = tag, .slice = Slice{ .start = start, .end = end } };
    }
};

test Element {
    const short_form = [_]u8{ 0x30, 0x03, 0x02, 0x01, 0x09 };
    try std.testing.expectEqual(Element{
        .tag = Tag.universal(.sequence, true),
        .slice = Element.Slice{ .start = 2, .end = short_form.len },
    }, Element.decode(&short_form, 0));

    const long_form = [_]u8{ 0x30, 129, 129 } ++ @as([129]u8, @splat(0));
    try std.testing.expectEqual(Element{
        .tag = Tag.universal(.sequence, true),
        .slice = Element.Slice{ .start = 3, .end = long_form.len },
    }, Element.decode(&long_form, 0));

    const multi_byte_tag = [_]u8{ 0x1F, 0x20, 0x08, 0x30, 0x36, 0x3A, 0x32, 0x37, 0x3A, 0x31, 0x35 };
    try std.testing.expectEqual(Element{
        .tag = Tag.universal(.time_of_day, false),
        .slice = Element.Slice{ .start = 3, .end = multi_byte_tag.len },
    }, Element.decode(&multi_byte_tag, 0));
}

/// For decoding.
pub const ExpectedTag = struct {
    number: ?Tag.Number = null,
    constructed: ?bool = null,
    class: ?Tag.Class = null,

    pub fn init(number: ?Tag.Number, constructed: ?bool, class: ?Tag.Class) ExpectedTag {
        return .{ .number = number, .constructed = constructed, .class = class };
    }

    pub fn primitive(number: ?Tag.Number) ExpectedTag {
        return .{ .number = number, .constructed = false, .class = .universal };
    }

    pub fn match(self: ExpectedTag, tag: Tag) bool {
        if (self.number) |e| {
            if (tag.number != e) return false;
        }
        if (self.constructed) |e| {
            if (tag.constructed != e) return false;
        }
        if (self.class) |e| {
            if (tag.class != e) return false;
        }
        return true;
    }
};

pub const FieldTag = struct {
    number: std.meta.Tag(Tag.Number),
    class: Tag.Class,
    explicit: bool = true,

    pub fn initExplicit(number: std.meta.Tag(Tag.Number), class: Tag.Class) FieldTag {
        return .{ .number = number, .class = class, .explicit = true };
    }

    pub fn initImplicit(number: std.meta.Tag(Tag.Number), class: Tag.Class) FieldTag {
        return .{ .number = number, .class = class, .explicit = false };
    }

    pub fn fromContainer(comptime Container: type, comptime field_name: []const u8) ?FieldTag {
        if (@hasDecl(Container, "asn1_tags") and @hasField(@TypeOf(Container.asn1_tags), field_name)) {
            return @field(Container.asn1_tags, field_name);
        }

        return null;
    }

    pub fn toTag(self: FieldTag) Tag {
        return Tag.init(@enumFromInt(self.number), self.explicit, self.class);
    }
};

pub const BitString = struct {
    /// Number of bits in rightmost byte that are unused.
    right_padding: u3 = 0,
    bytes: []const u8,

    pub fn bitLen(self: BitString) usize {
        return self.bytes.len * 8 - self.right_padding;
    }

    const asn1_tag = Tag.universal(.bitstring, false);

    pub fn decodeDer(decoder: *der.Decoder) !BitString {
        const ele = try decoder.element(asn1_tag.toExpected());
        const bytes = decoder.view(ele);

        if (bytes.len < 1) return error.InvalidBitString;
        const padding = bytes[0];
        if (padding >= 8) return error.InvalidBitString;
        const right_padding: u3 = @intCast(padding);

        // DER requires that unused bits be zero.
        if (@ctz(bytes[bytes.len - 1]) < right_padding) return error.InvalidBitString;

        return BitString{ .bytes = bytes[1..], .right_padding = right_padding };
    }

    pub fn encodeDer(self: BitString, encoder: *der.Encoder) !void {
        try encoder.prependBytes(self.bytes);
        try encoder.prependBytes(&.{self.right_padding});
        try encoder.length(self.bytes.len + 1);
        try encoder.tag(asn1_tag);
    }
};

test BitString {
    const bs = BitString{ .bytes = &.{ 0x6e, 0x5d, 0xc0 }, .right_padding = 6 };
    const allocator = std.testing.allocator;
    const buf = try der.encode(allocator, bs);
    defer allocator.free(buf);
    try std.testing.expectEqualSlices(u8, &.{ 0x03, 0x04, 0x06, 0x6e, 0x5d, 0xc0 }, buf);
    try std.testing.expectEqualDeep(bs, try der.decode(BitString, buf));
}

pub fn Opaque(comptime tag: Tag) type {
    return struct {
        bytes: []const u8,

        pub fn decodeDer(decoder: *der.Decoder) !@This() {
            const ele = try decoder.element(tag.toExpected());
            if (tag.constructed) decoder.index = ele.slice.end;
            return .{ .bytes = decoder.view(ele) };
        }

        pub fn encodeDer(self: @This(), encoder: *der.Encoder) !void {
            try encoder.tagBytes(tag, self.bytes);
        }
    };
}

/// Use sparingly.
pub const Any = struct {
    tag: Tag,
    bytes: []const u8,

    pub fn decodeDer(decoder: *der.Decoder) !@This() {
        const ele = try decoder.element(ExpectedTag{});
        return .{ .tag = ele.tag, .bytes = decoder.view(ele) };
    }

    pub fn encodeDer(self: @This(), encoder: *der.Encoder) !void {
        try encoder.tagBytes(self.tag, self.bytes);
    }
};

test {
    _ = der;
    _ = Oid;
    _ = @import("asn1/test.zig");
}
