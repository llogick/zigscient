const encoding = @import("encoding.zig");
const Mnemonic = encoding.Mnemonic;
const Instruction = encoding.Instruction;
const bits = @import("bits.zig");
const Register = bits.Register;
const Disassemble = @This();

const decode_tree = @import("decode_tree.zon");
const inst_formats = @import("inst_formats.zon");

mnemonic_operands_separator: []const u8 = " ",
operands_separator: []const u8 = ", ",
enable_aliases: bool = false,
preferred_style: Style = .manual,

pub const Style = enum {
    /// Encoding style, used by loongson-community/loongarch-opcodes.
    ///
    /// Output operands are not post-processed, sorted with slot offset.
    encoding,
    /// Manual style, used by the official manual and assembly code.
    ///
    /// Output operands are post-processed.
    manual,
};

pub fn printInstruction(dis: *const Disassemble, inst: Instruction, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    @setEvalBranchQuota(3000);
    const mnemonic = decodeMnemonic(inst) orelse return try writer.print("(UNKNOWN: 0x{x:0>8})", .{inst.word});

    inline for (@typeInfo(Mnemonic).@"enum".field_names) |mnemonic_field| try_mnemonic: {
        if (@field(Mnemonic, mnemonic_field) != mnemonic) break :try_mnemonic;

        const inst_info = @field(inst_formats.instructions, mnemonic_field);
        const InstInfo = @TypeOf(inst_info);

        switch (dis.preferred_style) {
            .encoding => {
                try writer.writeAll(mnemonic_field);
                const format = inst_info.format;
                if (format != .EMPTY) try writer.writeAll(dis.mnemonic_operands_separator);
                try dis.printOperands(@field(inst_formats.formats, @tagName(format)), inst, writer);
            },
            .manual => {
                try writer.writeAll(if (@hasField(InstInfo, "orig_name")) inst_info.orig_name else mnemonic_field);
                const format = if (@hasField(InstInfo, "orig_format")) inst_info.orig_format else inst_info.format;
                if (format != .EMPTY) try writer.writeAll(dis.mnemonic_operands_separator);
                try dis.printOperands(@field(inst_formats.formats, @tagName(format)), inst, writer);
            },
        }
        return;
    }
}

pub fn printInstructionAlloc(dis: *const Disassemble, inst: Instruction, gpa: std.mem.Allocator) (std.Io.Writer.Error || std.mem.Allocator.Error)![]u8 {
    var writer: std.Io.Writer.Allocating = .init(gpa);
    defer writer.deinit();
    try dis.printInstruction(inst, &writer.writer);
    return try writer.toOwnedSlice();
}

test printInstruction {
    const dis: Disassemble = .{};

    const testDisasm = struct {
        fn testDisasm(expected: []const u8, inst: u32) !void {
            const assembly = try dis.printInstructionAlloc(.{ .word = inst }, std.testing.allocator);
            defer std.testing.allocator.free(assembly);
            try std.testing.expectEqualStrings(expected, assembly);
        }
    }.testDisasm;

    try testDisasm("fcmp.caf.s $fcc0, $f1, $f2", 0x0c100820);
    try testDisasm("ertn", 0x06483800);
    try testDisasm("addi.d $r8, $r0, 0xa", 0x02c02808);
}

pub fn fmtInstruction(dis: Disassemble, inst: Instruction) struct {
    dis: Disassemble,
    inst: Instruction,

    pub fn format(data: @This(), w: *std.Io.Writer) std.Io.Writer.Error!void {
        try data.dis.printInstruction(data.inst, w);
    }
} {
    return .{ .dis = dis, .inst = inst };
}

pub fn decodeMnemonic(inst: Instruction) ?Mnemonic {
    return decodeMnemonicWithTree(decode_tree, inst);
}

/// Decodes mnemonics with a node in the decode tree.
fn decodeMnemonicWithTree(comptime tree: anytype, inst: Instruction) ?Mnemonic {
    const Tree = @TypeOf(tree);
    if (@hasField(Tree, "instruction")) {
        return @field(Mnemonic, @tagName(tree.instruction));
    } else if (@hasField(Tree, "mask")) {
        const value = inst.word & tree.mask;
        inline for (tree.cases) |case| try_case: {
            if (@hasField(@TypeOf(case), "value")) {
                if (value != case.value) break :try_case;
            }
            const then = case.then;

            if (@hasField(@TypeOf(then), "instruction")) {
                // manually inline here to reduce decoder functions of leaf nodes
                return @field(Mnemonic, @tagName(then.instruction));
            } else return decodeMnemonicWithTree(then, inst);
        }
        return null;
    } else {
        @compileLog("Current decode-tree node:", tree);
        @compileError("Invalid decode-tree node");
    }
}

test decodeMnemonic {
    try std.testing.expectEqual(Mnemonic.@"fcmp.caf.s", decodeMnemonic(.{ .word = 0x0c100820 }).?);
    try std.testing.expectEqual(Mnemonic.eret, decodeMnemonic(.{ .word = 0x06483800 }).?);
    try std.testing.expectEqual(Mnemonic.@"addi.d", decodeMnemonic(.{ .word = 0x02c02808 }).?);
}

pub fn printOperands(dis: *const Disassemble, comptime format: anytype, inst: Instruction, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    const word = inst.word;
    inline for (format.slots, 0..) |slot, slot_i| {
        if (slot_i != 0) try writer.writeAll(dis.operands_separator);

        const Slot = @TypeOf(slot);
        if (@hasField(Slot, "reg")) {
            const location = slot.reg.location;
            const class = slot.reg.class;

            const reg: u5 = if (class == .fcc)
                @as(u3, @truncate(word >> location))
            else
                @as(u5, @truncate(word >> location));

            try dis.printRegister(writer, class, reg);
        } else if (@hasField(Slot, "imm")) {
            const signedness = @field(std.builtin.Signedness, @tagName(slot.imm.signedness));
            const ImmValue = @Int(signedness, slot.imm.length);
            const UnsignedImmValue = @Int(.unsigned, slot.imm.length);
            const Imm32 = @Int(signedness, 32);
            // extend to 32-bit so postprocess won't overflow
            var value: Imm32 = @as(ImmValue, @bitCast(@as(UnsignedImmValue, @truncate(word >> slot.imm.location))));

            if (@hasField(@TypeOf(slot.imm), "post_proc")) {
                const postproc = slot.imm.post_proc;
                const PostProc = @TypeOf(postproc);
                if (@hasField(PostProc, "shl")) value <<= postproc.shl;
                if (@hasField(PostProc, "add")) value += postproc.add;
            }

            if (signedness == .unsigned) {
                try writer.print("0x{x}", .{value});
            } else {
                if (value >= 0)
                    try writer.print("0x{x}", .{value})
                else
                    try writer.print("-0x{x}", .{@abs(value)});
            }
        } else {
            @compileLog("Current slot:", slot);
            @compileError("Invalid operand slot info");
        }
    }
}

fn printRegister(dis: *const Disassemble, writer: *std.Io.Writer, comptime class: anytype, orig_reg: u5) std.Io.Writer.Error!void {
    var reg = orig_reg;
    const reg_prefix = prefix: {
        if (dis.enable_aliases) {
            switch (class) {
                .int => switch (reg) {
                    1 => return try writer.print("$ra", .{}),
                    3 => return try writer.print("$sp", .{}),
                    4...11 => {
                        reg -= 4;
                        break :prefix "a";
                    },
                    12...20 => {
                        reg -= 12;
                        break :prefix "t";
                    },
                    22 => return try writer.print("$fp", .{}),
                    23...31 => {
                        reg -= 23;
                        break :prefix "s";
                    },
                    else => {},
                },
                .fp => switch (reg) {
                    0...7 => break :prefix "fa",
                    8...23 => {
                        reg -= 8;
                        break :prefix "ft";
                    },
                    24...31 => {
                        reg -= 24;
                        break :prefix "fs";
                    },
                },
                else => {},
            }
        }
        break :prefix switch (class) {
            .int => "r",
            .fp => "f",
            .fcc => "fcc",
            .lsx => "v",
            .lasx => "x",
            else => unreachable,
        };
    };

    try writer.print("${s}{d}", .{ reg_prefix, reg });
}

const std = @import("std");
