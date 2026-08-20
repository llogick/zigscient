source: []const u8,
args: std.StringHashMapUnmanaged(Operand) = .empty,

pub const Operand = union(enum) {
    register: Register,
    signed_imm: i64,
    unsigned_imm: u64,
};

pub fn deinit(as: *Assemble, gpa: std.mem.Allocator) void {
    as.args.deinit(gpa);
}

pub fn nextLine(as: *Assemble) []const u8 {
    const line_len = std.mem.findScalar(u8, as.source, '\n') orelse {
        const line = as.source;
        as.source = "";
        return line;
    };
    const line = as.source[0..line_len];
    as.source = as.source[line_len + 1 ..];
    return line;
}

pub fn parseLine(as: *Assemble, orig_line: []const u8) !?Instruction {
    var line = orig_line;

    // strip comment
    if (std.mem.find(u8, line, "//")) |comment_i| line = line[comment_i..];

    var token_it = std.mem.tokenizeAny(u8, line, " \t");
    if (token_it.next()) |mnemonic_str| {
        log.debug("- '{s}'", .{line});
        log.debug("  - mnemonic: {s}", .{mnemonic_str});
        var op_it: OperandIterator = .init(as, token_it.rest());
        const instruction = parseInstruction(mnemonic_str, &op_it) orelse return error.InvalidSyntax;
        if (!op_it.isEnd()) {
            log.debug("find unrecognized operands", .{});
            return error.InvalidSyntax;
        }
        return instruction;
    } else return null;
}

const OperandIterator = struct {
    as: *Assemble,
    iter: std.mem.SplitIterator(u8, .scalar),

    fn init(as: *Assemble, ops: []const u8) OperandIterator {
        log.debug("  - operands: {s}", .{ops});
        return .{
            .as = as,
            .iter = std.mem.splitScalar(u8, ops, ','),
        };
    }

    fn isEnd(it: *OperandIterator) bool {
        return it.iter.peek() == null;
    }

    fn next(it: *OperandIterator) ?[]const u8 {
        if (it.iter.next()) |op| {
            const res = std.mem.trim(u8, op, " \t");
            log.debug("  - {s}", .{res});
            return res;
        }
        return null;
    }

    fn tryResolveArg(it: *OperandIterator, tmpl: []const u8) !?*Operand {
        if (tmpl.len < 2)
            return null;
        if (tmpl[0] == '%' and tmpl[1] == '[' and tmpl[tmpl.len - 1] == ']') {
            const arg_name = tmpl[2..][0 .. tmpl.len - 3];
            if (it.as.args.getPtr(arg_name)) |arg_op|
                return arg_op;
        }
        return null;
    }

    fn nextReg(it: *OperandIterator) ?Register {
        if (it.next()) |name| {
            return if (try it.tryResolveArg(name)) |arg_op|
                switch (arg_op.*) {
                    .register => |reg| reg,
                    else => null,
                }
            else
                Register.parse(name);
        }
        return null;
    }

    fn nextImm(it: *OperandIterator, T: type) ?T {
        if (it.next()) |imm_str| {
            return if (try it.tryResolveArg(imm_str)) |arg_op|
                switch (arg_op.*) {
                    inline .signed_imm, .unsigned_imm => |imm| if (std.math.cast(T, imm)) |imm_cast|
                        imm_cast
                    else
                        null,
                    else => null,
                }
            else
                std.fmt.parseInt(T, imm_str, 0) catch null;
        }
        return null;
    }
};

fn parseInstruction(mnemonic: []const u8, ops: *OperandIterator) ?Instruction {
    @setEvalBranchQuota(3_000);

    // find override matchers
    inline for (@typeInfo(matcher_overrides).@"struct".decl_names) |decl| {
        if (mnemonicEql(decl, mnemonic)) {
            const matcher = @field(matcher_overrides, decl);
            return switch (@typeInfo(@TypeOf(matcher))) {
                .@"fn" => matcher(ops),
                .enum_literal => defaultMatcher(@field(Mnemonic, decl), ops),
                .null => return null,
                else => unreachable,
            };
        }
    }

    // find default matchers
    inline for (@typeInfo(@TypeOf(inst_formats.instructions)).@"struct".field_names) |decl| {
        if (@hasDecl(matcher_overrides, decl)) continue;
        if (mnemonicEql(decl, mnemonic))
            return defaultMatcher(@field(Mnemonic, decl), ops);
    }

    log.debug("  unmatched mnemonic", .{});
    return null;
}

fn mnemonicEql(mnemonic: []const u8, rhs: []const u8) bool {
    if (mnemonic.len != rhs.len) return false;
    for (mnemonic, rhs) |l, r| {
        assert(!std.ascii.isUpper(l));
        if (l != std.ascii.toLower(r)) return false;
    }
    return true;
}

fn defaultMatcher(comptime mnemonic: Mnemonic, ops: *OperandIterator) ?Instruction {
    const inst_info = @field(inst_formats.instructions, @tagName(mnemonic));
    const format = if (@hasField(@TypeOf(inst_info), "orig_format") and !@hasField(@TypeOf(inst_info), "orig_name"))
        inst_info.orig_format
    else
        inst_info.format;
    // TODO check features
    return defaultMatcherFormat(@tagName(format), inst_info.word, ops);
}

fn defaultMatcherFormat(comptime format: []const u8, word: u32, ops: *OperandIterator) ?Instruction {
    const format_info = @field(inst_formats.formats, format);
    const encodeFn = @field(encoding.Instruction, "encode" ++ format);
    const EncodeArgs = std.meta.ArgsTuple(@TypeOf(encodeFn));
    var encode_args: EncodeArgs = undefined;
    encode_args[0] = word;
    inline for (format_info.slots, 1..) |slot, slot_i| {
        const Slot = @TypeOf(slot);
        if (@hasField(Slot, "reg")) {
            const class = slot.reg.class;
            const reg = ops.nextReg() orelse return null;
            if (reg.class() != switch (class) {
                .int => .int,
                .fp, .lsx, .lasx => .fp,
                .fcc => .fcc,
                .lbt_scratch => .int,
                else => unreachable,
            })
                return null;
            encode_args[slot_i] = reg;
        } else if (@hasField(Slot, "imm")) {
            const signedness = @field(std.builtin.Signedness, @tagName(slot.imm.signedness));
            const ImmValue = @Int(signedness, slot.imm.length);
            encode_args[slot_i] = ops.nextImm(ImmValue) orelse return null;
        } else {
            @compileLog("Current slot:", slot);
            @compileError("Invalid operand slot info");
        }
    }
    return @call(.always_inline, encodeFn, encode_args);
}

const matcher_overrides = struct {
    const b = null;
    const bl = null;
    const beqz = null;
    const bnez = null;
    const bceqz = null;
    const bcnez = null;
    const bgt = null;
    const bgtu = null;
    const ble = null;
    const bleu = null;

    const @"xxx.unknown.1" = null;
    const csrrd = null;
    const csrwr = null;
    const gcsrrd = null;
    const gcsrwr = null;
    const csrxchg = null;
    const cacop = null;
    const invtlb = null;
    const tlbinv = null;
    const preld = null;
    const preldx = null;
    const dbcl = null;
    const ertn = null;
    const pcaddi = null;
    const @"ext.w.b" = null;
    const @"ext.w.h" = null;
    const @"ldptr.w" = null;
    const @"ldptr.d" = null;
    const @"stptr.w" = null;
    const @"stptr.d" = null;
    const @"bitrev.w" = null;
    const @"bitrev.d" = null;
    const @"bitrev.4b" = null;
    const @"bitrev.8b" = null;
    const @"asrtle.d" = null;
    const @"asrtgt.d" = null;
    const @"lu32i.d" = null;
    const lu52i = null;
    const @"alsl.w" = null;
    const @"alsl.wu" = null;
    const @"alsl.d" = null;
    const @"bytepick.w" = null;
    const @"bytepick.d" = null;

    pub fn move(ops: *OperandIterator) ?Instruction {
        const rd = ops.nextReg() orelse return null;
        const rj = ops.nextReg() orelse return null;
        return .ori(rd, rj, 0);
    }

    pub fn nop(_: *OperandIterator) ?Instruction {
        return .andi(.zero, .zero, 0);
    }
};

const Assemble = @This();
const assert = std.debug.assert;
const encoding = @import("encoding.zig");
const bits = @import("bits.zig");
const Instruction = encoding.Instruction;
const Mnemonic = encoding.Mnemonic;
const Register = bits.Register;
const std = @import("std");
const log = std.log.scoped(.@"asm");
const inst_formats = @import("inst_formats.zon");
