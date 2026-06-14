const expect = @import("std").testing.expect;
const expectEqual = @import("std").testing.expectEqual;
const expectEqualStrings = @import("std").testing.expectEqualStrings;
const mem = @import("std").mem;

// Declare an enum.
const Type = enum {
    ok,
    not_ok,
};

// Declare a specific enum field.
const c = Type.ok;

// If you want access to the ordinal value of an enum, you
// can specify the tag type.
const Value = enum(u2) {
    zero,
    one,
    two,
};
// Now you can cast between u2 and Value.
// The ordinal value starts from 0, counting up by 1 from the previous member.
test "enum ordinal value" {
    try expectEqual(0, @intFromEnum(Value.zero));
    try expectEqual(1, @intFromEnum(Value.one));
    try expectEqual(2, @intFromEnum(Value.two));
}

// You can override the ordinal value for an enum.
const Value2 = enum(u32) {
    hundred = 100,
    thousand = 1000,
    million = 1000000,
};
test "set enum ordinal value" {
    try expectEqual(100, @intFromEnum(Value2.hundred));
    try expectEqual(1000, @intFromEnum(Value2.thousand));
    try expectEqual(1000000, @intFromEnum(Value2.million));
}

// You can also override only some values.
const Value3 = enum(u4) {
    a,
    b = 8,
    c,
    d = 4,
    e,
};
test "enum implicit ordinal values and overridden values" {
    try expectEqual(0, @intFromEnum(Value3.a));
    try expectEqual(8, @intFromEnum(Value3.b));
    try expectEqual(9, @intFromEnum(Value3.c));
    try expectEqual(4, @intFromEnum(Value3.d));
    try expectEqual(5, @intFromEnum(Value3.e));
}

// Enums can have methods, the same as structs and unions.
// Enum methods are not special, they are only namespaced
// functions that you can call with dot syntax.
const Suit = enum {
    clubs,
    spades,
    diamonds,
    hearts,

    pub fn isClubs(self: Suit) bool {
        return self == Suit.clubs;
    }
};
test "enum method" {
    const p = Suit.spades;
    try expect(!p.isClubs());
}

// An enum can be switched upon.
const Foo = enum {
    string,
    number,
    none,
};
test "enum switch" {
    const p = Foo.number;
    const what_is_it = switch (p) {
        Foo.string => "this is a string",
        Foo.number => "this is a number",
        Foo.none => "this is a none",
    };
    try expectEqualStrings(what_is_it, "this is a number");
}

// @typeInfo can be used to access the integer tag type of an enum.
const Small = enum {
    one,
    two,
    three,
    four,
};
test "std.meta.Tag" {
    try expectEqual(u2, @typeInfo(Small).@"enum".tag_type);
}

// @typeInfo tells us the field count and the fields names:
test "@typeInfo" {
    try expectEqual(4, @typeInfo(Small).@"enum".field_names.len);
    try expectEqualStrings(@typeInfo(Small).@"enum".field_names[1], "two");
}

// @tagName gives a [:0]const u8 representation of an enum value:
test "@tagName" {
    try expectEqualStrings(@tagName(Small.three), "three");
}

// test
