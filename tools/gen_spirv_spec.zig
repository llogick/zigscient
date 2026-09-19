const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const ExtendedStructSet = std.StringHashMapUnmanaged(void);
const assert = std.debug.assert;
const g = @import("spirv/grammar.zig");
const CoreRegistry = g.CoreRegistry;
const ExtensionRegistry = g.ExtensionRegistry;
const Instruction = g.Instruction;
const OperandKind = g.OperandKind;
const Enumerant = g.Enumerant;
const Operand = g.Operand;

const allowed_vendors = [_][]const u8{ "KHR", "EXT" };
const set_names = std.StaticStringMap(struct { []const u8, []const u8 }).initComptime(.{
    .{ "opencl.std.100", .{ "OpenCL.std", "OpenClOpcode" } },
    .{ "glsl.std.450", .{ "GLSL.std.450", "GlslOpcode" } },
});

const Extension = struct {
    name: []const u8,
    opcode_name: []const u8,
    spec: ExtensionRegistry,
};
const CmpInst = struct {
    fn lt(_: CmpInst, a: Instruction, b: Instruction) bool {
        return a.opcode < b.opcode;
    }
};
const StringPair = struct { []const u8, []const u8 };
const StringPairContext = struct {
    pub fn hash(_: @This(), a: StringPair) u32 {
        var hasher = std.hash.Wyhash.init(0);
        const x, const y = a;
        hasher.update(x);
        hasher.update(y);
        return @truncate(hasher.final());
    }

    pub fn eql(_: @This(), a: StringPair, b: StringPair, b_index: usize) bool {
        _ = b_index;
        const a_x, const a_y = a;
        const b_x, const b_y = b;
        return std.mem.eql(u8, a_x, b_x) and std.mem.eql(u8, a_y, b_y);
    }
};
const OperandKindMap = std.array_hash_map.Custom(StringPair, OperandKind, StringPairContext, true);

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 2) {
        usageAndExit(args[0], 1);
    }

    const json_path = try Io.Dir.path.join(arena, &.{ args[1], "include/spirv/unified1/" });
    const dir = try Io.Dir.cwd().openDir(io, json_path, .{ .iterate = true });

    var core_spec = try readRegistry(io, arena, CoreRegistry, dir, "spirv.core.grammar.json");
    std.mem.sortUnstable(Instruction, core_spec.instructions, CmpInst{}, CmpInst.lt);
    keepEnabled(&core_spec.instructions, core_spec.operand_kinds);

    var exts: std.ArrayList(Extension) = .empty;

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) {
            continue;
        }

        try readExtRegistry(io, arena, &exts, dir, entry.name);
    }

    var allocating: std.Io.Writer.Allocating = .init(arena);
    defer allocating.deinit();
    try render(arena, &allocating.writer, core_spec, exts.items);
    try allocating.writer.writeByte(0);
    const output = allocating.written()[0 .. allocating.written().len - 1 :0];

    var tree = try std.zig.Ast.parse(arena, output, .{});
    if (tree.errors.len != 0) {
        try std.zig.printAstErrorsToStderr(arena, io, tree, "", .auto);
        return;
    }

    var zir = try std.zig.AstGen.generate(arena, tree);
    if (zir.hasCompileErrors()) {
        var wip_errors: std.zig.ErrorBundle.Wip = undefined;
        try wip_errors.init(arena);
        defer wip_errors.deinit();
        try wip_errors.addZirErrorMessages(zir, tree, output, "");
        var error_bundle = try wip_errors.toOwnedBundle("");
        defer error_bundle.deinit(arena);
        try error_bundle.renderToStderr(io, .{}, .auto);
    }

    const formatted_output = try tree.renderAlloc(arena);
    try Io.File.stdout().writeStreamingAll(io, formatted_output);
}

fn readExtRegistry(io: Io, arena: Allocator, exts: *std.ArrayList(Extension), dir: Io.Dir, sub_path: []const u8) !void {
    const filename = Io.Dir.path.basename(sub_path);
    if (!std.mem.startsWith(u8, filename, "extinst.")) {
        return;
    }

    assert(std.mem.endsWith(u8, filename, ".grammar.json"));
    const name = filename["extinst.".len .. filename.len - ".grammar.json".len];
    var spec = try readRegistry(io, arena, ExtensionRegistry, dir, sub_path);

    const set_name = set_names.get(name) orelse {
        std.log.info("ignored instruction set '{s}'", .{name});
        return;
    };

    std.mem.sort(Instruction, spec.instructions, CmpInst{}, CmpInst.lt);
    keepEnabled(&spec.instructions, spec.operand_kinds);

    try exts.append(arena, .{
        .name = set_name.@"0",
        .opcode_name = set_name.@"1",
        .spec = spec,
    });
}

fn readRegistry(io: Io, arena: Allocator, comptime RegistryType: type, dir: Io.Dir, path: []const u8) !RegistryType {
    const spec = try dir.readFileAlloc(io, path, arena, .unlimited);
    @setEvalBranchQuota(10000);

    var scanner = std.json.Scanner.initCompleteInput(arena, spec);
    var diagnostics = std.json.Diagnostics{};
    scanner.enableDiagnostics(&diagnostics);
    const parsed = std.json.parseFromTokenSource(RegistryType, arena, &scanner, .{}) catch |err| {
        std.debug.print("{s}:{}:{}:\n", .{ path, diagnostics.getLine(), diagnostics.getColumn() });
        return err;
    };
    return parsed.value;
}

fn extendedStructs(arena: Allocator, kinds: []const OperandKind) !ExtendedStructSet {
    var map: ExtendedStructSet = .empty;
    try map.ensureTotalCapacity(arena, @as(u32, @intCast(kinds.len)));

    for (kinds) |kind| {
        const enumerants = kind.enumerants orelse continue;

        for (enumerants) |enumerant| {
            if (enumerant.parameters.len > 0) {
                break;
            }
        } else continue;

        map.putAssumeCapacity(kind.kind, {});
    }

    return map;
}

fn tagPriorityScore(tag: []const u8) usize {
    if (tag.len == 0) {
        return 1;
    } else if (std.mem.eql(u8, tag, "EXT")) {
        return 2;
    } else if (std.mem.eql(u8, tag, "KHR")) {
        return 3;
    } else {
        return 4;
    }
}

fn render(
    arena: Allocator,
    writer: *std.Io.Writer,
    registry: CoreRegistry,
    extensions: []const Extension,
) !void {
    try writer.writeAll(
        \\//! This file is auto-generated by tools/gen_spirv_spec.zig.
        \\const std = @import("std");
        \\
        \\pub const Word = u32;
        \\pub const Version = packed struct(Word) {
        \\    padding: u8 = 0,
        \\    minor: u8,
        \\    major: u8,
        \\    padding0: u8 = 0,
        \\};
        \\pub const Generator = packed struct(Word) {
        \\    version: u16,
        \\    tool: u16,
        \\};
        \\pub const Header = extern struct {
        \\    magic: Word,
        \\    version: Version,
        \\    generator: Generator,
        \\    id_bound: Word,
        \\    schema: Word,
        \\};
        \\pub const InstructionHeader = packed struct(Word) {
        \\    opcode: Opcode,
        \\    word_count: u16,
        \\};
        \\pub const Id = enum(Word) {
        \\    none,
        \\    _,
        \\
        \\    pub fn format(id: Id, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        \\        switch (id) {
        \\            .none => try writer.writeAll("(none)"),
        \\            else => try writer.print("%{d}", .{@backingInt(id)}),
        \\        }
        \\    }
        \\};
        \\pub const IdRange = struct {
        \\    base: u32,
        \\    len: u32,
        \\
        \\    pub fn at(range: IdRange, i: usize) Id {
        \\        std.debug.assert(i < range.len);
        \\        return @fromBackingInt(@intCast(range.base + i));
        \\    }
        \\};
        \\
        \\pub const LiteralInteger = Word;
        \\pub const LiteralString = []const u8;
        \\pub const LiteralContextDependentNumber = union(enum) {
        \\    int32: i32,
        \\    uint32: u32,
        \\    int64: i64,
        \\    uint64: u64,
        \\    float32: f32,
        \\    float64: f64,
        \\};
        \\pub const LiteralExtInstInteger = struct{ inst: Word };
        \\pub const LiteralSpecConstantOpInteger = struct { opcode: Opcode };
        \\pub const PairLiteralIntegerIdRef = struct { value: LiteralInteger, label: Id };
        \\pub const PairIdRefLiteralInteger = struct { target: Id, member: LiteralInteger };
        \\pub const PairIdRefIdRef = [2]Id;
        \\
        \\pub const Quantifier = enum {
        \\    required,
        \\    optional,
        \\    variadic,
        \\};
        \\
        \\pub const Operand = struct {
        \\    kind: OperandKind,
        \\    quantifier: Quantifier = .required,
        \\};
        \\
        \\pub const OperandCategory = enum {
        \\    bit_enum,
        \\    value_enum,
        \\    id,
        \\    literal,
        \\    composite,
        \\};
        \\
        \\pub const Enumerant = struct {
        \\    name: []const u8,
        \\    value: Word,
        \\    parameters: []const Operand,
        \\};
        \\
        \\pub const zig_generator_id: u16 = 41;
        \\
    );

    try writer.print(
        \\pub const version: Version = .{{ .major = {}, .minor = {}, .patch = {} }};
        \\pub const magic_number: Word = {s};
        \\
        \\
    ,
        .{ registry.major_version, registry.minor_version, registry.revision, registry.magic_number },
    );

    var all_operand_kinds: OperandKindMap = .empty;
    for (registry.operand_kinds) |kind| {
        try all_operand_kinds.putNoClobber(arena, .{ "core", kind.kind }, kind);
    }
    for (extensions) |ext| {
        try all_operand_kinds.ensureUnusedCapacity(arena, ext.spec.operand_kinds.len);
        for (ext.spec.operand_kinds) |kind| {
            var new_kind = kind;
            new_kind.kind = try std.mem.join(arena, ".", &.{ ext.name, kind.kind });
            try all_operand_kinds.putNoClobber(arena, .{ ext.name, kind.kind }, new_kind);
        }
    }

    const kinds = all_operand_kinds.values();
    const extended_structs = try extendedStructs(arena, kinds);
    try renderClass(arena, writer, registry.instructions);
    try renderOperandKind(writer, kinds);

    try renderOpcodes(arena, writer, "core", "Opcode", true, registry.instructions, extended_structs, all_operand_kinds);
    for (extensions) |ext| {
        try renderOpcodes(arena, writer, ext.name, ext.opcode_name, false, ext.spec.instructions, extended_structs, all_operand_kinds);
    }

    try renderOperandKinds(arena, writer, kinds, extended_structs);
    try renderInstructionSet(writer, extensions);
    try renderExtension(arena, writer, kinds);
}

fn renderExtension(
    arena: Allocator,
    writer: *std.Io.Writer,
    kinds: []const OperandKind,
) !void {
    try writer.writeAll(
        \\pub const Extension = enum {
        \\v1_0,
        \\v1_1,
        \\v1_2,
        \\v1_3,
        \\v1_4,
        \\v1_5,
        \\v1_6,
        \\
    );

    var seen_extensions: std.StringHashMapUnmanaged(void) = .empty;
    defer seen_extensions.deinit(arena);

    for (kinds) |kind| {
        if (std.mem.eql(u8, "Capability", kind.kind)) {
            for (kind.enumerants.?) |enumerant| {
                for (enumerant.extensions) |ext| {
                    if (!isAllowedExtension(ext)) continue;
                    if (seen_extensions.contains(ext)) continue;
                    try seen_extensions.put(arena, ext, {});
                    try writer.print("{s},\n", .{ext});
                }
            }
        }
    }
    try writer.writeAll("};\n");
}

fn renderInstructionSet(
    writer: *std.Io.Writer,
    extensions: []const Extension,
) !void {
    try writer.writeAll(
        \\pub const InstructionSet = enum {
        \\    core,
    );

    for (extensions) |ext| {
        try writer.print("{f},\n", .{std.zig.fmtId(ext.name)});
    }

    try writer.writeAll(
        \\
        \\    pub fn operands(inst_set: InstructionSet, opcode: Word) ?[]const Operand {
        \\        return switch (inst_set) {
        \\            .core => if (std.enums.fromInt(Opcode, opcode)) |op| op.operands() else null,
        \\
    );

    for (extensions) |ext| {
        try writer.print(
            "            .{f} => if (std.enums.fromInt({f}, opcode)) |op| op.operands() else null,\n",
            .{ std.zig.fmtId(ext.name), std.zig.fmtId(ext.opcode_name) },
        );
    }

    try writer.writeAll(
        \\        };
        \\    }
        \\};
        \\
    );
}

fn renderClass(arena: Allocator, writer: *std.Io.Writer, instructions: []const Instruction) !void {
    var class_map: std.array_hash_map.String(void) = .empty;

    for (instructions) |inst| {
        if (std.mem.eql(u8, inst.class.?, "@exclude")) continue;
        try class_map.put(arena, inst.class.?, {});
    }

    try writer.writeAll("pub const Class = enum {\n");
    for (class_map.keys()) |class| {
        try writer.print("{f},\n", .{formatId(class)});
    }
    try writer.writeAll("};\n\n");
}

const Formatter = struct {
    data: []const u8,

    fn format(f: Formatter, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        var id_buf: [128]u8 = undefined;
        var fw: std.Io.Writer = .fixed(&id_buf);
        for (f.data, 0..) |c, i| {
            switch (c) {
                '-', '_', '.', '~', ' ' => fw.writeByte('_') catch return error.WriteFailed,
                'a'...'z', '0'...'9' => fw.writeByte(c) catch return error.WriteFailed,
                'A'...'Z' => {
                    if ((i > 0 and std.ascii.isLower(f.data[i - 1])) or
                        (i > 0 and std.ascii.isUpper(f.data[i - 1]) and
                            i + 1 < f.data.len and std.ascii.isLower(f.data[i + 1])))
                    {
                        _ = fw.write(&.{ '_', std.ascii.toLower(c) }) catch return error.WriteFailed;
                    } else {
                        fw.writeByte(std.ascii.toLower(c)) catch return error.WriteFailed;
                    }
                },
                else => unreachable,
            }
        }

        try writer.print("{f}", .{std.zig.fmtId(fw.buffered())});
    }
};

fn formatId(identifier: []const u8) std.fmt.Alt(Formatter, Formatter.format) {
    return .{ .data = .{ .data = identifier } };
}

fn renderOperandKind(writer: *std.Io.Writer, operands: []const OperandKind) !void {
    try writer.writeAll(
        \\pub const OperandKind = enum {
        \\    opcode,
        \\
    );
    for (operands) |operand| {
        try writer.print("{f},\n", .{formatId(operand.kind)});
    }
    try writer.writeAll(
        \\
        \\pub fn category(operand_kind: OperandKind) OperandCategory {
        \\    return switch (operand_kind) {
        \\        .opcode => .literal,
        \\
    );
    for (operands) |operand| {
        const cat = switch (operand.category) {
            .BitEnum => "bit_enum",
            .ValueEnum => "value_enum",
            .Id => "id",
            .Literal => "literal",
            .Composite => "composite",
        };
        try writer.print(".{f} => .{s},\n", .{ formatId(operand.kind), cat });
    }
    try writer.writeAll(
        \\    };
        \\}
        \\pub fn enumerants(operand_kind: OperandKind) []const Enumerant {
        \\    return switch (operand_kind) {
        \\        .opcode => unreachable,
        \\
    );
    for (operands) |operand| {
        switch (operand.category) {
            .BitEnum, .ValueEnum => {},
            else => {
                try writer.print(".{f} => unreachable,\n", .{formatId(operand.kind)});
                continue;
            },
        }

        try writer.print(".{f} => &.{{", .{formatId(operand.kind)});
        for (operand.enumerants.?) |enumerant| {
            if (enumerant.value == .bitflag and std.mem.eql(u8, enumerant.enumerant, "None")) {
                continue;
            }
            try renderEnumerant(writer, enumerant);
            try writer.writeAll(",");
        }
        try writer.writeAll("},\n");
    }
    try writer.writeAll(
        \\};
        \\}
        \\
        \\pub fn bases(operand_kind: OperandKind) []const OperandKind {
        \\    return switch (operand_kind) {
        \\
    );
    for (operands) |operand| {
        if (operand.category != .Composite) continue;
        try writer.print(".{f} => &.{{", .{formatId(operand.kind)});
        for (operand.bases.?, 0..) |base, i| {
            if (i != 0) try writer.writeAll(", ");
            try writer.print(".{f}", .{formatId(base)});
        }
        try writer.writeAll("},\n");
    }
    try writer.writeAll("else => unreachable,\n};\n}\n};\n");
}

fn renderEnumerant(writer: *std.Io.Writer, enumerant: Enumerant) !void {
    try writer.print(".{{.name = \"{s}\", .value = ", .{enumerant.enumerant});
    switch (enumerant.value) {
        .bitflag => |flag| try writer.writeAll(flag),
        .int => |int| try writer.print("{}", .{int}),
    }
    try writer.writeAll(", .parameters = &.{");
    for (enumerant.parameters, 0..) |param, i| {
        if (i != 0)
            try writer.writeAll(", ");
        try writer.print(".{{ .kind = .{f} }}", .{formatId(param.kind)});
    }
    try writer.writeAll("}}");
}

fn renderOpcodes(
    arena: Allocator,
    writer: *std.Io.Writer,
    set_name: []const u8,
    opcode_type_name: []const u8,
    want_operands: bool,
    instructions: []const Instruction,
    extended_structs: ExtendedStructSet,
    all_operand_kinds: OperandKindMap,
) !void {
    var inst_map: std.array_hash_map.Auto(u32, usize) = .empty;
    try inst_map.ensureTotalCapacity(arena, instructions.len);

    var aliases: std.ArrayList(struct { inst: usize, alias: usize }) = .empty;
    try aliases.ensureTotalCapacity(arena, instructions.len);

    for (instructions, 0..) |inst, i| {
        if (inst.class) |class| {
            if (std.mem.eql(u8, class, "@exclude")) continue;
        }

        const result = inst_map.getOrPutAssumeCapacity(inst.opcode);
        if (!result.found_existing) {
            result.value_ptr.* = i;
            continue;
        }

        const existing = instructions[result.value_ptr.*];

        const tag_index = std.mem.indexOfDiff(u8, inst.opname, existing.opname).?;
        const inst_priority = tagPriorityScore(inst.opname[tag_index..]);
        const existing_priority = tagPriorityScore(existing.opname[tag_index..]);

        if (inst_priority < existing_priority) {
            aliases.appendAssumeCapacity(.{ .inst = result.value_ptr.*, .alias = i });
            result.value_ptr.* = i;
        } else {
            aliases.appendAssumeCapacity(.{ .inst = i, .alias = result.value_ptr.* });
        }
    }

    const instructions_indices = inst_map.values();

    try writer.print("\npub const {f} = enum(u16) {{\n", .{std.zig.fmtId(opcode_type_name)});
    for (instructions_indices) |i| {
        const inst = instructions[i];
        try writer.print("{f} = {},\n", .{ std.zig.fmtId(inst.opname), inst.opcode });
    }

    try writer.writeAll("\n");

    for (aliases.items) |alias| {
        try writer.print("pub const {f} = {f}.{f};\n", .{
            formatId(instructions[alias.inst].opname),
            std.zig.fmtId(opcode_type_name),
            formatId(instructions[alias.alias].opname),
        });
    }

    try writer.print(
        \\
        \\pub fn operands(opcode: {f}) []const Operand {{
        \\    return switch (opcode) {{
        \\
    , .{std.zig.fmtId(opcode_type_name)});

    for (instructions_indices) |i| {
        const inst = instructions[i];
        try writer.print(".{f} => &.{{", .{std.zig.fmtId(inst.opname)});
        for (inst.operands, 0..) |operand, j| {
            const kind = all_operand_kinds.get(.{ set_name, operand.kind }) orelse
                all_operand_kinds.get(.{ "core", operand.kind }).?;
            if (j != 0) try writer.writeAll(", ");
            try writer.print(".{{ .kind = .{f}", .{formatId(kind.kind)});
            if (operand.quantifier) |quantifier| {
                try writer.print(", .quantifier = .{s}", .{switch (quantifier) {
                    .@"?" => "optional",
                    .@"*" => "variadic",
                }});
            }
            try writer.writeAll(" }");
        }
        try writer.writeAll("},\n");
    }

    try writer.writeAll(
        \\    };
        \\}
        \\
    );

    if (want_operands) {
        try writer.writeAll(
            \\
            \\pub fn Operands(comptime opcode: Opcode) type {
            \\    return switch (opcode) {
            \\
        );

        for (instructions_indices) |i| {
            const inst = instructions[i];
            try renderOperand(writer, .instruction, inst.opname, inst.operands, extended_structs, false);
        }

        try writer.writeAll(
            \\    };
            \\}
            \\
        );

        try writer.writeAll(
            \\
            \\pub fn class(opcode: Opcode) Class {
            \\    return switch (@backingInt(opcode)) {
            \\
        );

        var first: usize = 0;
        while (first < instructions_indices.len) {
            const class = instructions[instructions_indices[first]].class.?;
            var last = first;
            while (last + 1 < instructions_indices.len and
                std.mem.eql(u8, instructions[instructions_indices[last + 1]].class.?, class)) last += 1;
            const lo = instructions[instructions_indices[first]].opcode;
            const hi = instructions[instructions_indices[last]].opcode;
            if (lo == hi) {
                try writer.print("{d} => .{f},\n", .{ lo, formatId(class) });
            } else {
                try writer.print("{d}...{d} => .{f},\n", .{ lo, hi, formatId(class) });
            }
            first = last + 1;
        }

        try writer.writeAll(
            \\        else => unreachable,
            \\    };
            \\}
            \\
            \\pub fn resultIndex(opcode: Opcode) ?u8 {
            \\    const list = opcode.operands();
            \\    if (list.len == 0) return null;
            \\    return switch (list[0].kind) {
            \\        .id_result => 1,
            \\        .id_result_type => 2,
            \\        else => null,
            \\    };
            \\}
            \\
            \\pub fn instructionSize(comptime opcode: Opcode, ops: opcode.Operands()) usize {
            \\    return operandsSize(opcode.Operands(), ops) + 1;
            \\}
            \\
            \\fn operandsSize(comptime T: type, ops: T) usize {
            \\    const info = switch (@typeInfo(T)) {
            \\        .@"struct" => |info| info,
            \\        .void => return 0,
            \\        else => unreachable,
            \\    };
            \\
            \\    var total: usize = 0;
            \\    inline for (info.field_names, info.field_types) |field_name, field_type| {
            \\        total += operandSize(field_type, @field(ops, field_name));
            \\    }
            \\
            \\    return total;
            \\}
            \\
            \\fn operandSize(comptime T: type, operand: T) usize {
            \\    return switch (T) {
            \\        LiteralSpecConstantOpInteger => unreachable,
            \\        Id, LiteralInteger, LiteralExtInstInteger => 1,
            \\        LiteralString => @divCeil(operand.len + 1, @sizeOf(Word)),
            \\        LiteralContextDependentNumber => switch (operand) {
            \\            .int32, .uint32, .float32 => 1,
            \\            .int64, .uint64, .float64 => 2,
            \\        },
            \\        PairLiteralIntegerIdRef, PairIdRefLiteralInteger, PairIdRefIdRef => 2,
            \\        else => switch (@typeInfo(T)) {
            \\            .@"enum" => 1,
            \\            .optional => |info| if (operand) |child| operandSize(info.child, child) else 0,
            \\            .pointer => |info| blk: {
            \\                std.debug.assert(info.size == .slice);
            \\                var total: usize = 0;
            \\                for (operand) |item| {
            \\                    total += operandSize(info.child, item);
            \\                }
            \\                break :blk total;
            \\            },
            \\            .@"struct" => |struct_info| {
            \\                if (struct_info.layout == .@"packed") return 1;
            \\                var total: usize = 0;
            \\                inline for (struct_info.field_names, struct_info.field_types) |field_name, field_type| {
            \\                    switch (@typeInfo(field_type)) {
            \\                        .optional => |info| if (@field(operand, field_name)) |child| {
            \\                            total += operandsSize(info.child, child);
            \\                        },
            \\                        .bool, .int => {},
            \\                        else => unreachable,
            \\                    }
            \\                }
            \\                return total + 1;
            \\            },
            \\            .@"union" => switch (operand) {
            \\                inline else => |op, tag| operandsSize(@FieldType(T, @tagName(tag)), op) + 1,
            \\            },
            \\            else => unreachable,
            \\        },
            \\    };
            \\}
            \\
        );
    }

    try writer.writeAll(
        \\};
        \\
    );
}

fn renderOperandKinds(
    arena: Allocator,
    writer: *std.Io.Writer,
    kinds: []const OperandKind,
    extended_structs: ExtendedStructSet,
) !void {
    for (kinds) |kind| {
        switch (kind.category) {
            .ValueEnum => try renderValueEnum(arena, writer, kind, extended_structs),
            .BitEnum => try renderBitEnum(arena, writer, kind, extended_structs),
            else => {},
        }
    }
}

fn renderValueEnum(
    arena: Allocator,
    writer: *std.Io.Writer,
    enumeration: OperandKind,
    extended_structs: ExtendedStructSet,
) !void {
    const enumerants = enumeration.enumerants orelse return error.InvalidRegistry;

    var enum_map: std.array_hash_map.Auto(u32, usize) = .empty;
    try enum_map.ensureTotalCapacity(arena, enumerants.len);

    var aliases: std.ArrayList(struct { enumerant: usize, alias: usize }) = .empty;
    try aliases.ensureTotalCapacity(arena, enumerants.len);

    for (enumerants, 0..) |enumerant, i| {
        const value: u31 = switch (enumerant.value) {
            .int => |value| value,
            .bitflag => |value| try std.fmt.parseInt(u31, value, 10),
        };
        const result = enum_map.getOrPutAssumeCapacity(value);
        if (!result.found_existing) {
            result.value_ptr.* = i;
            continue;
        }

        const existing = enumerants[result.value_ptr.*];

        const tag_index = std.mem.indexOfDiff(u8, enumerant.enumerant, existing.enumerant).?;
        const enum_priority = tagPriorityScore(enumerant.enumerant[tag_index..]);
        const existing_priority = tagPriorityScore(existing.enumerant[tag_index..]);

        if (enum_priority < existing_priority) {
            aliases.appendAssumeCapacity(.{ .enumerant = result.value_ptr.*, .alias = i });
            result.value_ptr.* = i;
        } else {
            aliases.appendAssumeCapacity(.{ .enumerant = i, .alias = result.value_ptr.* });
        }
    }

    const enum_indices = enum_map.values();

    try writer.print("pub const {f} = enum(u32) {{\n", .{std.zig.fmtId(enumeration.kind)});

    for (enum_indices) |i| {
        const enumerant = enumerants[i];
        switch (enumerant.value) {
            .int => |value| try writer.print("{f} = {},\n", .{ formatId(enumerant.enumerant), value }),
            .bitflag => |value| try writer.print("{f} = {s},\n", .{ formatId(enumerant.enumerant), value }),
        }
    }

    try writer.writeByte('\n');

    for (aliases.items) |alias| {
        try writer.print("pub const {f} = {f}.{f};\n", .{
            formatId(enumerants[alias.enumerant].enumerant),
            std.zig.fmtId(enumeration.kind),
            formatId(enumerants[alias.alias].enumerant),
        });
    }

    if (std.mem.eql(u8, "Capability", enumeration.kind)) {
        try writer.writeAll(
            \\
            \\pub fn dependencies(self: Capability) []const Extension {
            \\ return switch (self) {
        );
        for (enum_indices) |i| {
            const enumerant = enumerants[i];
            const enum_version = enumerant.version.?;
            const minor = if (enum_version[0] == 'N') '0' else enum_version[2];
            try writer.print("\n.{f} => &.{{.v1_{c}", .{ formatId(enumerant.enumerant), minor });
            for (enumerant.extensions) |extension| {
                if (!isAllowedExtension(extension)) continue;
                try writer.print(", .{s}", .{extension});
            }
            try writer.writeAll("},");
        }
        try writer.writeAll(
            \\};
            \\}
            \\};
            \\
        );
        return;
    }

    if (!extended_structs.contains(enumeration.kind)) {
        try writer.writeAll("};\n");
        return;
    }

    try writer.print("\npub const Extended = union({f}) {{\n", .{std.zig.fmtId(enumeration.kind)});

    for (enum_indices) |i| {
        const enumerant = enumerants[i];
        try renderOperand(writer, .@"union", enumerant.enumerant, enumerant.parameters, extended_structs, true);
    }

    try writer.writeAll("};\n};\n");
}

fn renderBitEnum(
    arena: Allocator,
    writer: *std.Io.Writer,
    enumeration: OperandKind,
    extended_structs: ExtendedStructSet,
) !void {
    try writer.print("pub const {f} = packed struct(Word) {{\n", .{std.zig.fmtId(enumeration.kind)});

    var flags_by_bitpos: [32]?usize = @splat(null);
    const enumerants = enumeration.enumerants orelse return error.InvalidRegistry;

    var aliases: std.ArrayList(struct { flag: usize, alias: u5 }) = .empty;
    try aliases.ensureTotalCapacity(arena, enumerants.len);

    for (enumerants, 0..) |enumerant, i| {
        if (enumerant.value != .bitflag) return error.InvalidRegistry;
        const value = try parseHexInt(enumerant.value.bitflag);
        if (value == 0) {
            continue;
        } else if (std.mem.eql(u8, enumerant.enumerant, "FlagIsPublic")) {
            continue;
        }

        assert(@popCount(value) == 1);

        const bitpos = std.math.log2_int(u32, value);
        if (flags_by_bitpos[bitpos]) |*existing| {
            const tag_index = std.mem.indexOfDiff(u8, enumerant.enumerant, enumerants[existing.*].enumerant).?;
            const enum_priority = tagPriorityScore(enumerant.enumerant[tag_index..]);
            const existing_priority = tagPriorityScore(enumerants[existing.*].enumerant[tag_index..]);

            if (enum_priority < existing_priority) {
                aliases.appendAssumeCapacity(.{ .flag = existing.*, .alias = bitpos });
                existing.* = i;
            } else {
                aliases.appendAssumeCapacity(.{ .flag = i, .alias = bitpos });
            }
        } else {
            flags_by_bitpos[bitpos] = i;
        }
    }

    var bitpos: usize = 0;
    while (bitpos < flags_by_bitpos.len) {
        const flag_index = flags_by_bitpos[bitpos] orelse {
            bitpos = try renderReservedBits(writer, flags_by_bitpos, bitpos);
            continue;
        };
        try writer.print("{f}: bool = false,\n", .{formatId(enumerants[flag_index].enumerant)});
        bitpos += 1;
    }

    try writer.writeByte('\n');

    for (aliases.items) |alias| {
        try writer.print("pub const {f}: {f} = .{{.{f} = true}};\n", .{
            formatId(enumerants[alias.flag].enumerant),
            std.zig.fmtId(enumeration.kind),
            formatId(enumerants[flags_by_bitpos[alias.alias].?].enumerant),
        });
    }

    if (!extended_structs.contains(enumeration.kind)) {
        try writer.writeAll("};\n");
        return;
    }

    try writer.print("\npub const Extended = struct {{\n", .{});

    bitpos = 0;
    while (bitpos < flags_by_bitpos.len) {
        const flag_index = flags_by_bitpos[bitpos] orelse {
            bitpos = try renderReservedBits(writer, flags_by_bitpos, bitpos);
            continue;
        };
        const enumerant = enumerants[flag_index];
        try renderOperand(writer, .mask, enumerant.enumerant, enumerant.parameters, extended_structs, true);
        bitpos += 1;
    }

    try writer.writeAll("};\n};\n");
}

fn renderReservedBits(writer: *std.Io.Writer, flags_by_bitpos: [32]?usize, start: usize) !usize {
    var end = start + 1;
    while (end < flags_by_bitpos.len and flags_by_bitpos[end] == null) end += 1;
    if (end == start + 1) {
        try writer.print("_reserved_bit_{}: bool = false,\n", .{start});
    } else {
        try writer.print("_reserved_bits_{}_to_{}: u{} = 0,\n", .{ start, end - 1, end - start });
    }
    return end;
}

fn renderOperand(
    writer: *std.Io.Writer,
    kind: enum {
        @"union",
        instruction,
        mask,
    },
    field_name: []const u8,
    parameters: []const Operand,
    extended_structs: ExtendedStructSet,
    snake_case: bool,
) !void {
    if (kind == .instruction) {
        try writer.writeByte('.');
    }

    if (snake_case) {
        try writer.print("{f}", .{formatId(field_name)});
    } else {
        try writer.print("{f}", .{std.zig.fmtId(field_name)});
    }

    if (parameters.len == 0) {
        switch (kind) {
            .@"union" => try writer.writeAll(",\n"),
            .instruction => try writer.writeAll(" => void,\n"),
            .mask => try writer.writeAll(": bool = false,\n"),
        }
        return;
    }

    if (kind == .instruction) {
        try writer.writeAll(" => ");
    } else {
        try writer.writeAll(": ");
    }

    if (kind == .mask) {
        try writer.writeByte('?');
    }

    try writer.writeAll("struct {");

    for (parameters, 0..) |param, j| {
        if (j != 0) {
            try writer.writeAll(", ");
        }

        try renderFieldName(writer, parameters, j);
        try writer.writeAll(": ");

        if (param.quantifier) |q| {
            switch (q) {
                .@"?" => try writer.writeByte('?'),
                .@"*" => try writer.writeAll("[]const "),
            }
        }

        if (std.mem.startsWith(u8, param.kind, "Id")) {
            _ = try writer.write("Id");
        } else {
            try writer.print("{f}", .{std.zig.fmtId(param.kind)});
        }

        if (extended_structs.contains(param.kind)) {
            try writer.writeAll(".Extended");
        }

        if (param.quantifier) |q| {
            switch (q) {
                .@"?" => try writer.writeAll(" = null"),
                .@"*" => try writer.writeAll(" = &.{}"),
            }
        }
    }

    try writer.writeAll("}");

    if (kind == .mask) {
        try writer.writeAll(" = null");
    }

    try writer.writeAll(",\n");
}

fn renderFieldName(writer: *std.Io.Writer, operands: []const Operand, field_index: usize) !void {
    const operand = operands[field_index];

    derive_from_kind: {
        const name = std.mem.trim(u8, operand.name, "'~");
        if (name.len == 0) break :derive_from_kind;

        for (name) |c| {
            switch (c) {
                'a'...'z', '0'...'9', 'A'...'Z', ' ', '~' => continue,
                else => break :derive_from_kind,
            }
        }

        try writer.print("{f}", .{formatId(name)});
        return;
    }

    try writer.print("{f}", .{formatId(operand.kind)});

    const need_extra_index = for (operands, 0..) |other_operand, i| {
        if (i != field_index and std.mem.eql(u8, operand.kind, other_operand.kind)) {
            break true;
        }
    } else false;

    if (need_extra_index) {
        try writer.print("_{}", .{field_index});
    }
}

fn isAllowedCapability(name: []const u8) bool {
    const last = name[name.len - 1];
    if (std.ascii.isLower(last) or std.ascii.isDigit(last)) return true;
    for (allowed_vendors) |vendor| {
        if (std.mem.endsWith(u8, name, vendor)) return true;
    }
    return false;
}

fn isAllowedExtension(name: []const u8) bool {
    const spv_prefix = "SPV_";
    if (!std.mem.startsWith(u8, name, spv_prefix)) return false;
    const tail = name[spv_prefix.len..];
    for (allowed_vendors) |vendor| {
        if (std.mem.startsWith(u8, tail, vendor) and
            tail.len > vendor.len and tail[vendor.len] == '_')
            return true;
    }
    return false;
}

fn isEnabled(version: ?[]const u8, capabilities: []const []const u8, extensions: []const []const u8) bool {
    if (version) |v| if (!std.mem.eql(u8, v, "None")) return true;
    if (extensions.len != 0) {
        for (extensions) |ext| if (isAllowedExtension(ext)) return true;
        return false;
    }
    if (capabilities.len == 0) return true;
    for (capabilities) |cap| if (isAllowedCapability(cap)) return true;
    return false;
}

fn keepEnabled(instructions: *[]Instruction, kinds: []OperandKind) void {
    var kept: usize = 0;
    for (instructions.*) |inst| {
        if (!isEnabled(inst.version, inst.capabilities, inst.extensions)) continue;
        instructions.*[kept] = inst;
        kept += 1;
    }
    instructions.* = instructions.*[0..kept];
    for (kinds) |*kind| {
        const enumerants = kind.enumerants orelse continue;
        var kept_enumerants: usize = 0;
        for (enumerants) |enumerant| {
            const enabled = if (std.mem.eql(u8, kind.kind, "Capability"))
                isAllowedCapability(enumerant.enumerant)
            else
                isEnabled(enumerant.version, enumerant.capabilities, enumerant.extensions);
            if (!enabled) continue;
            enumerants[kept_enumerants] = enumerant;
            kept_enumerants += 1;
        }
        kind.enumerants = enumerants[0..kept_enumerants];
    }
}

fn parseHexInt(text: []const u8) !u31 {
    const prefix = "0x";
    if (!std.mem.startsWith(u8, text, prefix))
        return error.InvalidHexInt;
    return try std.fmt.parseInt(u31, text[prefix.len..], 16);
}

fn usageAndExit(arg0: []const u8, code: u8) noreturn {
    const stderr = std.debug.lockStderr(&.{});
    const w = &stderr.file_writer.interface;
    w.print(
        \\Usage: {s} <SPIRV-Headers repository path>
        \\
        \\Generates Zig bindings for SPIR-V specifications found in the SPIRV-Headers
        \\repository. The result, printed to stdout, should be used to update
        \\src/codegen/spirv/spec.zig.
        \\
        \\<SPIRV-Headers repository path> should point to a clone of
        \\https://github.com/KhronosGroup/SPIRV-Headers/
        \\
    , .{arg0}) catch std.process.exit(1);
    std.process.exit(code);
}
