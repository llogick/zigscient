//! Parser for format description files in
//! https://github.com/loongson-community/loongarch-opcodes.

const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Reader = std.Io.Reader;

const OpcodeDesc = @This();

/// Maximum number of slots in one instruction format.
const max_slots = 4;

opcode: std.ArrayList(Opcode) = .empty,
format_pool: std.heap.MemoryPool(Format) = .empty,
format: std.StringArrayHashMapUnmanaged(*Format) = .empty,

pub fn deinit(desc: *OpcodeDesc, gpa: Allocator) void {
    desc.opcode.deinit(gpa);
    desc.format.deinit(gpa);
    desc.format_pool.deinit(gpa);
}

/// Instruction format. Slots are filled one by one, ending with reaching max_slots or a .none slot.
pub const Format = struct {
    name: []const u8,
    slots: [max_slots]Slot,

    pub fn parse(name: []const u8) !Format {
        var format: Format = .{
            .name = name,
            .slots = .{ .none, .none, .none, .none },
        };
        var reader: Reader = .fixed(name);
        var slot_index: std.math.IntFittingRange(0, max_slots) = 0;
        parse_empty: {
            const str = reader.peekArray(5) catch |err| switch (err) {
                error.EndOfStream => break :parse_empty,
                else => return err,
            };
            if (mem.eql(u8, &str.*, "EMPTY"))
                return format;
        }

        parse_slots: while (slot_index < max_slots) : (slot_index += 1) {
            switch (reader.takeByte() catch |err| switch (err) {
                error.EndOfStream => break :parse_slots,
                else => return err,
            }) {
                'D' => format.slots[slot_index] = .{ .tag = .reg, .payload = .{ .reg = .{
                    .class = .int,
                    .index = .d,
                } } },
                'J' => format.slots[slot_index] = .{ .tag = .reg, .payload = .{ .reg = .{
                    .class = .int,
                    .index = .j,
                } } },
                'K' => format.slots[slot_index] = .{ .tag = .reg, .payload = .{ .reg = .{
                    .class = .int,
                    .index = .k,
                } } },
                'A' => format.slots[slot_index] = .{ .tag = .reg, .payload = .{ .reg = .{
                    .class = .int,
                    .index = .a,
                } } },
                'F' => format.slots[slot_index] = .{ .tag = .reg, .payload = .{ .reg = .{
                    .class = .fp,
                    .index = try .parse(&reader),
                } } },
                'C' => format.slots[slot_index] = .{ .tag = .reg, .payload = .{ .reg = .{
                    .class = .fcc,
                    .index = try .parse(&reader),
                } } },
                'T' => format.slots[slot_index] = .{ .tag = .reg, .payload = .{ .reg = .{
                    .class = .lbt_scratch,
                    .index = try .parse(&reader),
                } } },
                'V' => format.slots[slot_index] = .{ .tag = .reg, .payload = .{ .reg = .{
                    .class = .lsx,
                    .index = try .parse(&reader),
                } } },
                'X' => format.slots[slot_index] = .{ .tag = .reg, .payload = .{ .reg = .{
                    .class = .lasx,
                    .index = try .parse(&reader),
                } } },
                'S', 'U' => |signedness_ch| {
                    const signedness: std.builtin.Signedness = if (signedness_ch == 'S') .signed else .unsigned;
                    while (slot_index < max_slots and continue_imm_slot: {
                        _ = Slot.Index.fromChar(reader.peekByte() catch |err| switch (err) {
                            error.EndOfStream => break :continue_imm_slot false,
                            else => return err,
                        }) catch break :continue_imm_slot false;
                        break :continue_imm_slot true;
                    }) : (slot_index += 1) {
                        const index: Slot.Index = try .parse(&reader);
                        const length = try takeInteger(u5, &reader);
                        const post_proc = post_proc: {
                            if ('p' == reader.peekByte() catch |err| switch (err) {
                                error.EndOfStream => ' ',
                                else => return err,
                            }) {
                                reader.toss(1);
                                break :post_proc try Slot.PostProcess.parse(&reader);
                            } else break :post_proc Slot.PostProcess.none;
                        };
                        format.slots[slot_index] = .{ .tag = .imm, .payload = .{ .imm = .{
                            .index = index,
                            .length = length,
                            .signedness = signedness,
                            .post_proc = post_proc,
                        } } };
                    }
                    slot_index -= 1;
                },
                else => return error.InvalidCharacter,
            }
        }

        return format;
    }
};

test "parse format" {
    _ = try Format.parse("DJFmSk12m13ps3");
    _ = try Format.parse("DJSk12m13ps3U16pp1");
    _ = try Format.parse("DJK");
}

pub const Slot = packed struct {
    tag: Slot.Tag,
    payload: Slot.Payload,

    comptime {
        std.debug.assert(@sizeOf(Slot) == 4);
    }

    const Payload = packed union {
        none: u16, // unused number, just for padding
        imm: packed struct {
            index: Index,
            length: u5,
            signedness: std.builtin.Signedness,
            post_proc: PostProcess = .none,
        },
        reg: packed struct {
            class: enum(u13) { int, fp, fcc, lbt_scratch, lsx, lasx },
            index: Index,
        },
    };

    const Tag = enum(u16) { reg, imm, none };

    pub const none: Slot = .{ .tag = .none, .payload = .{ .none = 0 } };

    pub const Index = enum(u3) {
        // zig fmt: off
        d, j, k, a, m, n,
        // zig fmt: on

        pub fn offset(index: Index) u5 {
            return switch (index) {
                .d => 0,
                .j => 5,
                .k => 10,
                .a => 15,
                .m => 16,
                .n => 18,
            };
        }

        pub fn fromChar(ch: u8) error{UnknownIndexChar}!Index {
            return switch (ch) {
                'd' => .d,
                'j' => .j,
                'k' => .k,
                'a' => .a,
                'm' => .m,
                'n' => .n,
                else => return error.UnknownIndexChar,
            };
        }

        pub const ParseError = Reader.Error || error{UnknownIndexChar};
        pub fn parse(reader: *Reader) Index.ParseError!Index {
            return fromChar(try reader.takeByte());
        }
    };

    /// Post-process operations for disassemblying.
    pub const PostProcess = packed struct {
        tag: PostProcess.Tag,
        payload: PostProcess.Payload,

        const Payload = packed union {
            /// assembly value = encoded value + N
            add: u5,
            /// assembly value = encoded value << N
            shl: u5,
            none: u5, // unused number, for padding
        };

        const Tag = std.meta.FieldEnum(PostProcess.Payload);

        pub const none: PostProcess = .{ .tag = .none, .payload = .{ .none = 0 } };

        pub const ParseError = Reader.Error || std.fmt.ParseIntError;
        pub fn parse(reader: *Reader) PostProcess.ParseError!PostProcess {
            switch (try reader.takeByte()) {
                'p' => return .{
                    .tag = .add,
                    .payload = .{ .add = try takeInteger(u4, reader) },
                },
                's' => return .{
                    .tag = .shl,
                    .payload = .{ .shl = try takeInteger(u4, reader) },
                },
                else => return error.InvalidCharacter,
            }
        }
    };

    pub fn offset(slot: Slot) u5 {
        return switch (slot.tag) {
            .none => unreachable,
            .imm => slot.payload.imm.index.offset(),
            .reg => slot.payload.reg.index.offset(),
        };
    }

    pub fn width(slot: Slot) u5 {
        return switch (slot.tag) {
            .none => unreachable,
            .imm => slot.payload.imm.length,
            .reg => switch (slot.payload.reg.class) {
                .fcc => 3,
                else => 5,
            },
        };
    }

    pub fn mask(slot: Slot) u32 {
        const off = slot.offset();
        const size = slot.width();
        const msb, const overflow = @addWithOverflow(off, size);
        if (overflow == 1) {
            @branchHint(.unlikely);
            return ~((@as(u32, 1) << off) - 1);
        }
        return ((@as(u32, 1) << msb) - 1) ^ ((@as(u32, 1) << off) - 1);
    }
};

test "mask" {
    try std.testing.expectEqual(0b111100000, (Slot{ .tag = .imm, .payload = .{ .imm = .{
        .index = .j,
        .length = 4,
        .signedness = .unsigned,
    } } }).mask());
    try std.testing.expectEqual(0x7fffffff, (Slot{ .tag = .imm, .payload = .{ .imm = .{
        .index = .d,
        .length = 31,
        .signedness = .unsigned,
    } } }).mask());
    try std.testing.expectEqual(0x7fffffff, (Slot{ .tag = .imm, .payload = .{ .imm = .{
        .index = .d,
        .length = 31,
        .signedness = .unsigned,
    } } }).mask());
    try std.testing.expectEqual(0xffffffe0, (Slot{ .tag = .imm, .payload = .{ .imm = .{
        .index = .j,
        .length = 27,
        .signedness = .unsigned,
    } } }).mask());
    try std.testing.expectEqual(0b111110000000000, (Slot{ .tag = .reg, .payload = .{ .reg = .{
        .class = .int,
        .index = .k,
    } } }).mask());
}

fn takeInteger(comptime T: type, reader: *Reader) (Reader.Error || std.fmt.ParseIntError)!T {
    if (std.math.maxInt(T) < 10) {
        const ch = try reader.takeByte();
        return std.math.cast(T, ch ^ '0') orelse return error.Overflow;
    }
    var v: T = 0;

    var ch: u8 = try reader.peekByte();
    if (!std.ascii.isDigit(ch)) return error.InvalidCharacter;

    while (std.ascii.isDigit(ch)) : (ch = reader.peekByte() catch |err| switch (err) {
        error.EndOfStream => break,
        else => return err,
    }) {
        v = try std.math.add(
            T,
            try std.math.add(
                T,
                try std.math.shlExact(T, v, 3),
                try std.math.shlExact(T, v, 1),
            ),
            std.math.cast(T, ch ^ '0') orelse return error.Overflow,
        );
        reader.toss(1);
    }
    return v;
}

test takeInteger {
    var reader: std.Io.Reader = undefined;

    reader = .fixed("123");
    try std.testing.expectEqual(123, try takeInteger(u8, &reader));
    reader = .fixed("123ignored");
    try std.testing.expectEqual(123, try takeInteger(u8, &reader));
    reader = .fixed("bad");
    try std.testing.expectError(error.InvalidCharacter, takeInteger(u8, &reader));
    reader = .fixed("1");
    try std.testing.expectEqual(1, try takeInteger(u1, &reader));
}

pub const Opcode = struct {
    word: u32,
    name: []const u8,
    format: *Format,
    orig_name: []const u8,
    orig_format: *Format,
    required_features: RequiredFeatures,

    pub const RequiredFeatures = packed struct {
        @"32bit": bool = false,
        @"32s": bool = false,
        @"64bit": bool = false,
        f: bool = false,
        d: bool = false,
        lsx: bool = false,
        lasx: bool = false,
        lbt: bool = false,
        lvz: bool = false,
    };
};

/// Parses a opcode data file.
/// Caller owns the data string and the data string must live longer
/// than the OpcodeDesc.
pub fn parse(desc: *OpcodeDesc, gpa: Allocator, data: []const u8) !void {
    var lines = mem.tokenizeScalar(u8, data, '\n');
    while (lines.next()) |line| {
        if (line[0] == '#') continue; // skip comments, not used by upstream but used in tools/loongarch/extra.txt
        var tokens = mem.tokenizeScalar(u8, line, ' ');

        const word_buf = tokens.next() orelse return error.UnexpectedEol;
        const word = try std.fmt.parseInt(u32, word_buf, 16);
        const name = tokens.next() orelse return error.UnexpectedEol;
        const format_str = tokens.next() orelse return error.UnexpectedEol;
        const format = try desc.getOrParseFormat(gpa, format_str);

        const opcode = try desc.opcode.addOne(gpa);
        opcode.* = .{
            .word = word,
            .name = name,
            .format = format,
            .orig_name = name,
            .orig_format = format,
            .required_features = .{},
        };

        // parse attributes
        while (tokens.next()) |attr| {
            if (attr[0] != '@') return error.MalformedAttribute;
            if (mem.indexOfScalar(u8, attr, '=')) |eql_pos| {
                const attr_name = attr[1..][0 .. eql_pos - 1];
                const attr_val = attr[eql_pos + 1 ..];

                if (mem.eql(u8, attr_name, "orig_name")) { // manual name
                    opcode.orig_name = attr_val;
                } else if (mem.eql(u8, attr_name, "orig_fmt")) { // manual format
                    opcode.orig_format = try desc.getOrParseFormat(gpa, attr_val);
                }
            } else {
                const attr_name = attr[1..];

                if (mem.eql(u8, attr_name, "la32")) { // available in LA32S
                    if (!opcode.required_features.@"32bit")
                        opcode.required_features.@"32s" = true;
                } else if (mem.eql(u8, attr_name, "primary")) { // available in LA32R
                    opcode.required_features.@"32bit" = true;
                    opcode.required_features.@"32s" = false;
                } else if (mem.eql(u8, attr_name, "lvz")) { // requires LVZ
                    opcode.required_features.lvz = false;
                } else if (mem.eql(u8, attr_name, "lbt")) { // requires LBT
                    opcode.required_features.lbt = false;
                }
            }
        }

        // determine based on register usages
        for (opcode.format.slots) |slot| {
            switch (slot.tag) {
                .none => break,
                .imm => {},
                .reg => {
                    switch (slot.payload.reg.class) {
                        .fp => {
                            opcode.required_features.f = true;
                            if (mem.eql(u8, opcode.name, ".d")) { // requires double-precision FP
                                opcode.required_features.d = true;
                            }
                        },
                        .fcc => opcode.required_features.f = true,
                        .lsx => opcode.required_features.lsx = true,
                        .lasx => opcode.required_features.lasx = true,
                        .lbt_scratch => opcode.required_features.lbt = true,
                        else => {},
                    }
                },
            }
        }

        // if there are not any attributes indicating that the instruction requires
        // any other features or supports LA32, we assume that it requires LA64.
        if (opcode.required_features == Opcode.RequiredFeatures{}) {
            opcode.required_features.@"64bit" = true;
        }
    }
}

/// Gets or parses a format string.
/// The string must live longer than the OpcodeDesc.
pub fn getOrParseFormat(desc: *OpcodeDesc, gpa: Allocator, format: []const u8) !*Format {
    const gop = try desc.format.getOrPut(gpa, format);
    if (!gop.found_existing) {
        errdefer _ = desc.format.swapRemove(format);
        const format_ptr = try desc.format_pool.create(gpa);
        errdefer desc.format_pool.destroy(format_ptr);

        format_ptr.* = try Format.parse(format);
        gop.value_ptr.* = format_ptr;
    }
    return gop.value_ptr.*;
}

pub fn sort(desc: *OpcodeDesc) void {
    mem.sort(Opcode, desc.opcode.items, false, struct {
        fn cmp(_: bool, lhs: Opcode, rhs: Opcode) bool {
            return mem.order(u8, lhs.name, rhs.name) == .lt;
        }
    }.cmp);
    desc.format.sort(struct {
        keys: [][]const u8,

        pub fn lessThan(ctx: @This(), a_index: usize, b_index: usize) bool {
            return mem.order(u8, ctx.keys[a_index], ctx.keys[b_index]) == .lt;
        }
    }{ .keys = desc.format.keys() });
}
