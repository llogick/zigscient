const std = @import("std");
const expectEqual = std.testing.expectEqual;

const E = enum {
    one,
    two,
    three,
};

const U = union(E) {
    one: i32,
    two: f32,
    three,
};

const U2 = union(enum) {
    a: void,
    b: f32,

    fn tag(self: U2) usize {
        switch (self) {
            .a => return 1,
            .b => return 2,
        }
    }
};

test "coercion between unions and enums" {
    const u = U{ .two = 12.34 };
    const e: E = u; // coerce union to enum
    try expectEqual(E.two, e);

    const three = E.three;
    const u_2: U = three; // coerce enum to union
    try expectEqual(E.three, u_2);

    const u_3: U = .three; // coerce enum literal to union
    try expectEqual(E.three, u_3);

    const u_4: U2 = .a; // coerce enum literal to union with inferred enum tag type.
    try expectEqual(1, u_4.tag());

    // The following example is invalid.
    // error: coercion from enum '@EnumLiteral()' to union 'test_coerce_unions_enum.U2' must initialize 'f32' field 'b'
    //var u_5: U2 = .b;
    //try expectEqual(2, u_5.tag());
}

// test
