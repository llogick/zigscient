const std = @import("std");
const Target = std.Target;
const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;
const Writer = std.Io.Writer;

/// Register, one per set of aliasing registers
pub const Register = enum(u7) {
    // zig fmt: off
    // integer registers
    r0, r1, r2, r3, r4, r5, r6, r7,
    r8, r9, r10, r11, r12, r13, r14, r15,
    r16, r17, r18, r19, r20, r21, r22, r23,
    r24, r25, r26, r27, r28, r29, r30, r31,

    // float-point/LSX/LASX registers
    f0, f1, f2, f3, f4, f5, f6, f7,
    f8, f9, f10, f11, f12, f13, f14, f15,
    f16, f17, f18, f19, f20, f21, f22, f23,
    f24, f25, f26, f27, f28, f29, f30, f31,

    // float-point condition code registers
    fcc0, fcc1, fcc2, fcc3, fcc4, fcc5, fcc6, fcc7,
    // zig fmt: on

    pub const zero: Register = .r0;
    pub const ra: Register = .r1;
    pub const tp: Register = .r2;
    pub const sp: Register = .r3;
    pub const fp: Register = .r22;
    pub const t0: Register = .r12;

    /// Register banks.
    pub const Class = enum { int, fp, fcc };

    /// Register accessing modifier.
    pub const Modifier = enum(u3) {
        undef,
        integer,
        floating32,
        floating64,
        lsx,
        lasx,
        fcc,

        pub fn class(modifier: Modifier) Class {
            return switch (modifier) {
                .undef => unreachable,
                .integer => .int,
                .floating32, .floating64, .lsx, .lasx => .fp,
                .fcc => .fcc,
            };
        }

        pub fn bitSize(modifier: Modifier, target: *const Target) u16 {
            return switch (modifier) {
                .undef => 0,
                .integer => switch (target.cpu.arch) {
                    .loongarch32 => 32,
                    .loongarch64 => 64,
                    else => unreachable,
                },
                .floating32 => 32,
                .floating64 => 64,
                .lsx => 128,
                .lasx => 256,
                .fcc => 1,
            };
        }

        /// Upper-rounded byte size.
        pub fn byteSize(modifier: Modifier, target: *const Target) u16 {
            return switch (modifier) {
                .undef => 0,
                .integer => switch (target.cpu.arch) {
                    .loongarch32 => 4,
                    .loongarch64 => 8,
                    else => unreachable,
                },
                .floating32 => 4,
                .floating64 => 8,
                .lsx => 16,
                .lasx => 32,
                .fcc => 1,
            };
        }

        pub fn fromFloating(bits: u16) Modifier {
            return switch (bits) {
                else => unreachable,
                32 => .floating32,
                64 => .floating64,
            };
        }
    };

    pub const Alias = struct {
        reg: Register,
        mod: Modifier,

        pub const zero: Alias = .{ .mod = .integer, .reg = .zero };

        pub fn format(self: Alias, w: *std.Io.Writer) std.Io.Writer.Error!void {
            try w.print("${s}{d}", .{
                switch (self.mod) {
                    .undef => "?",
                    .integer => "r",
                    .floating32 => "(s)f",
                    .floating64 => "(d)f",
                    .lsx => "v",
                    .lasx => "x",
                    .fcc => "fcc",
                },
                self.reg.encode(),
            });
        }
    };

    pub fn class(reg: Register) Class {
        return switch (@backingInt(reg)) {
            @backingInt(Register.r0)...@backingInt(Register.r31) => .int,
            @backingInt(Register.f0)...@backingInt(Register.f31) => .fp,
            @backingInt(Register.fcc0)...@backingInt(Register.fcc7) => .fcc,
            else => unreachable,
        };
    }

    pub fn encode(reg: Register) u5 {
        const base: u7 = switch (@backingInt(reg)) {
            @backingInt(Register.r0)...@backingInt(Register.r31) => @backingInt(Register.r0),
            @backingInt(Register.f0)...@backingInt(Register.f31) => @backingInt(Register.f0),
            @backingInt(Register.fcc0)...@backingInt(Register.fcc7) => @backingInt(Register.fcc0),
            else => unreachable,
        };
        return @intCast(@backingInt(reg) - base);
    }

    pub fn decode(reg_class: Class, reg: u5) Register {
        const base: u7 = switch (reg_class) {
            .int => @backingInt(Register.r0),
            .fp => @backingInt(Register.f0),
            .fcc => @backingInt(Register.fcc0),
        };
        return @fromBackingInt(base + @as(u7, reg));
    }

    pub fn parse(reg: []const u8) ?Register {
        if (reg.len == 0) return null;
        if (reg[0] == '$') return parse(reg[1..]);
        if (toLowerEqlAssertLower(reg, "zero")) return .zero;
        if (toLowerEqlAssertLower(reg, "ra")) return .ra;
        if (toLowerEqlAssertLower(reg, "tp")) return .tp;
        if (toLowerEqlAssertLower(reg, "sp")) return .sp;
        if (toLowerEqlAssertLower(reg, "fp")) return .fp;
        return switch (std.ascii.toLower(reg[0])) {
            else => null,
            'r' => reg: {
                break :reg if (std.fmt.parseInt(u5, reg[1..], 10)) |n| .decode(.int, n) else |_| null;
            },
            'f' => reg: {
                if (reg.len == 4 and toLowerEqlAssertLower(reg[0..3], "fcc"))
                    break :reg if (std.ascii.isDigit(reg[3])) .decode(.fcc, @intCast(reg[3] ^ '0')) else null;
                if (reg.len > 2 and toLowerEqlAssertLower(reg[0..2], "fa"))
                    break :reg if (std.fmt.parseInt(u5, reg[2..], 10)) |n| .decode(.fp, n) else |_| null;
                if (reg.len > 2 and toLowerEqlAssertLower(reg[0..2], "ft"))
                    break :reg if (std.fmt.parseInt(u5, reg[2..], 10)) |n| .decode(.fp, 8 + n) else |_| null;
                if (reg.len > 2 and toLowerEqlAssertLower(reg[0..2], "fs"))
                    break :reg if (std.fmt.parseInt(u5, reg[2..], 10)) |n| .decode(.fp, 24 + n) else |_| null;

                break :reg if (std.fmt.parseInt(u5, reg[1..], 10)) |n| .decode(.fp, n) else |_| null;
            },
            'v', 'x' => reg: {
                if (reg.len < 3 or std.ascii.toLower(reg[1]) != 'r') break :reg null;
                break :reg if (std.fmt.parseInt(u5, reg[2..], 10)) |n| .decode(.fp, n) else |_| null;
            },
            'a' => if (std.fmt.parseInt(u5, reg[1..], 10)) |n| .decode(.int, 4 + n) else |_| null,
            't' => if (std.fmt.parseInt(u5, reg[1..], 10)) |n| .decode(.int, 12 + n) else |_| null,
            's' => if (std.fmt.parseInt(u5, reg[1..], 10)) |n| reg: {
                if (n == 9) break :reg .r22;
                break :reg .decode(.int, 23 + n);
            } else |_| null,
        };
    }

    fn toLowerEqlAssertLower(lhs: []const u8, rhs: []const u8) bool {
        if (lhs.len != rhs.len) return false;
        for (lhs, rhs) |l, r| {
            assert(!std.ascii.isUpper(r));
            if (std.ascii.toLower(l) != r) return false;
        }
        return true;
    }
};

test "register classes" {
    try expectEqual(.int, Register.r0.class());
    try expectEqual(.int, Register.r31.class());
    try expectEqual(.fp, Register.f0.class());
    try expectEqual(.fp, Register.f31.class());
    try expectEqual(.fcc, Register.fcc0.class());
    try expectEqual(.fcc, Register.fcc7.class());
}

test "register encoding" {
    try expectEqual(0, Register.r0.encode());
    try expectEqual(31, Register.r31.encode());
    try expectEqual(0, Register.f0.encode());
    try expectEqual(31, Register.f31.encode());
    try expectEqual(0, Register.fcc0.encode());
    try expectEqual(7, Register.fcc7.encode());
}

test "register decoding" {
    try expectEqual(.r0, Register.decode(.int, 0));
    try expectEqual(.r31, Register.decode(.int, 31));
    try expectEqual(.f0, Register.decode(.fp, 0));
    try expectEqual(.f31, Register.decode(.fp, 31));
    try expectEqual(.fcc0, Register.decode(.fcc, 0));
    try expectEqual(.fcc7, Register.decode(.fcc, 7));
}

test "register parsing" {
    try expectEqual(.r0, Register.parse("r0").?);
    try expectEqual(.r0, Register.parse("ZERO").?);
    try expectEqual(.r0, Register.parse("zero").?);
    try expectEqual(.r0, Register.parse("$zero").?);
    try expectEqual(Register.ra, Register.parse("ra").?);
    try expectEqual(Register.tp, Register.parse("tp").?);
    try expectEqual(Register.sp, Register.parse("sp").?);
    try expectEqual(Register.fp, Register.parse("fp").?);
    try expectEqual(.r7, Register.parse("a3").?);
    try expectEqual(.r15, Register.parse("t3").?);
    try expectEqual(.r26, Register.parse("s3").?);
    try expectEqual(.r22, Register.parse("s9").?);
    try expectEqual(.fcc0, Register.parse("fcc0").?);
    try expectEqual(.fcc7, Register.parse("fcc7").?);
    try expectEqual(.f0, Register.parse("f0").?);
    try expectEqual(.f3, Register.parse("fa3").?);
    try expectEqual(.f11, Register.parse("ft3").?);
    try expectEqual(.f27, Register.parse("fs3").?);
    try expectEqual(.f0, Register.parse("vr0").?);
    try expectEqual(.f0, Register.parse("xr0").?);
}
