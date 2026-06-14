//! Distinguised Encoding Rules as defined in X.690 and X.691.
//!
//! Subset of Basic Encoding Rules (BER) which eliminates flexibility in
//! an effort to acheive normality. Used in PKI.
const std = @import("std");
const asn1 = @import("../asn1.zig");

pub const Decoder = @import("der/Decoder.zig");
pub const Encoder = @import("der/Encoder.zig");

pub fn decode(comptime T: type, encoded: []const u8) !T {
    var decoder = Decoder{ .bytes = encoded };
    const res = try decoder.any(T);
    std.debug.assert(decoder.index == encoded.len);
    return res;
}

/// Caller owns returned memory.
pub fn encode(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var encoder = Encoder.init(allocator);
    defer encoder.deinit();
    try encoder.any(value);
    return try encoder.buffer.toOwnedSlice();
}

test encode {
    // https://lapo.it/asn1js/#MAgGAyoDBAIBBA
    const Value = struct { a: asn1.Oid, b: i32 };
    const test_case = .{
        .value = Value{ .a = asn1.Oid.fromDotComptime("1.2.3.4"), .b = 4 },
        .encoded = &[_]u8{ 0x30, 0x08, 0x06, 0x03, 0x2A, 0x03, 0x04, 0x02, 0x01, 0x04 },
    };
    const allocator = std.testing.allocator;
    const actual = try encode(allocator, test_case.value);
    defer allocator.free(actual);

    try std.testing.expectEqualSlices(u8, test_case.encoded, actual);
}

test decode {
    // https://lapo.it/asn1js/#MAgGAyoDBAIBBA
    const Value = struct { a: asn1.Oid, b: i32 };
    const test_case = .{
        .value = Value{ .a = asn1.Oid.fromDotComptime("1.2.3.4"), .b = 4 },
        .encoded = &[_]u8{ 0x30, 0x08, 0x06, 0x03, 0x2A, 0x03, 0x04, 0x02, 0x01, 0x04 },
    };
    const decoded = try decode(Value, test_case.encoded);

    try std.testing.expectEqualDeep(test_case.value, decoded);
}

test "integer round trip across signed and unsigned boundaries" {
    const allocator = std.testing.allocator;
    inline for (.{ u8, u16, u32, i8, i16, i32 }) |T| {
        const cases = comptime blk: {
            const min = std.math.minInt(T);
            const max = std.math.maxInt(T);
            break :blk [_]T{ 0, 1, max, min, @divTrunc(max, 2), @divTrunc(min, 2) };
        };
        for (cases) |value| {
            const buf = try encode(allocator, value);
            defer allocator.free(buf);
            const decoded = try decode(T, buf);
            try std.testing.expectEqual(value, decoded);
        }
    }
}

test "encode skips null optional fields" {
    const Value = struct { a: ?u8, b: u8 };
    const allocator = std.testing.allocator;
    const actual = try encode(allocator, Value{ .a = null, .b = 5 });
    defer allocator.free(actual);

    try std.testing.expectEqualSlices(u8, &.{ 0x30, 0x03, 0x02, 0x01, 0x05 }, actual);
}

test "encode preserves outer sequence tag after implicit field tags" {
    const Value = struct {
        a: u8,
        b: u8,

        pub const asn1_tags = .{
            .a = asn1.FieldTag.initImplicit(0, .context_specific),
        };
    };
    const allocator = std.testing.allocator;
    const actual = try encode(allocator, Value{ .a = 1, .b = 2 });
    defer allocator.free(actual);

    try std.testing.expectEqualSlices(u8, &.{ 0x30, 0x06, 0x80, 0x01, 0x01, 0x02, 0x01, 0x02 }, actual);
}

test {
    _ = Decoder;
    _ = Encoder;
}
