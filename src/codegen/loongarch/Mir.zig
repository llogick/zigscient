const Mir = @This();
const Instruction = @import("encoding.zig").Instruction;
const Disassemble = @import("Disassemble.zig");

prologue: []const Instruction,
body: []const Instruction,
epilogue: []const Instruction,
nav_relocs: []const Reloc.Nav,
uav_relocs: []const Reloc.Uav,
lazy_relocs: []const Reloc.Lazy,
global_relocs: []const Reloc.Global,
internal_relocs: []const Reloc.Internal,

pub const Reloc = struct {
    label: u32,
    type: std.elf.R_LARCH,
    addend: i64 = 0,

    pub const Nav = struct {
        nav: InternPool.Nav.Index,
        reloc: Reloc,
    };

    pub const Uav = struct {
        uav: InternPool.Key.Ptr.BaseAddr.Uav,
        reloc: Reloc,
    };

    pub const Lazy = struct {
        symbol: link.File.LazySymbol,
        reloc: Reloc,
    };

    pub const Global = struct {
        name: [*:0]const u8,
        reloc: Reloc,
    };

    pub const Internal = struct {
        // Target MIR index
        target: usize = 0,
        reloc: Reloc,
    };
};

pub fn deinit(mir: *Mir, gpa: std.mem.Allocator) void {
    assert(mir.body.ptr + mir.body.len == mir.prologue.ptr);
    assert(mir.prologue.ptr + mir.prologue.len == mir.epilogue.ptr);
    gpa.free(mir.body.ptr[0 .. mir.body.len + mir.prologue.len + mir.epilogue.len]);
    gpa.free(mir.nav_relocs);
    gpa.free(mir.uav_relocs);
    gpa.free(mir.lazy_relocs);
    gpa.free(mir.global_relocs);
    gpa.free(mir.internal_relocs);
    mir.* = undefined;
}

pub fn emit(
    mir: Mir,
    lf: *link.File,
    pt: Zcu.PerThread,
    func_index: InternPool.Index,
    atom_index: link.File.AtomId,
    w: *std.Io.Writer,
    debug_output: link.File.DebugInfoOutput,
) !void {
    _ = debug_output;
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const func = zcu.funcInfo(func_index);
    const nav = ip.getNav(func.owner_nav);
    mir_log.debug("{f}:", .{nav.fqn.fmt(ip)});

    const code_len = mir.prologue.len + mir.body.len + mir.epilogue.len;
    try w.rebase(w.end, @sizeOf(Instruction) * code_len);
    emitInstructionsBackward(w, mir.prologue) catch unreachable;
    emitInstructionsBackward(w, mir.body) catch unreachable;
    const body_end: u32 = @intCast(w.end);
    emitInstructionsBackward(w, mir.epilogue) catch unreachable;
    mir_log.debug("", .{});

    for (mir.nav_relocs) |nav_reloc| emitReloc(
        lf,
        zcu,
        atom_index,
        try @import("../../codegen.zig").genNavRef(
            lf,
            pt,
            nav_reloc.nav,
        ),
        nav_reloc.reloc.type,
        body_end - @sizeOf(Instruction) * (1 + nav_reloc.reloc.label),
        nav_reloc.reloc.addend,
    ) catch |err|
        return zcu.codegenFail(func.owner_nav, "emit reloc failed: {t}", .{err});
    for (mir.uav_relocs) |uav_reloc| emitReloc(
        lf,
        zcu,
        atom_index,
        try lf.lowerUav(
            pt,
            uav_reloc.uav.val,
            ZigType.fromInterned(uav_reloc.uav.orig_ty).ptrAlignment(zcu),
        ),
        uav_reloc.reloc.type,
        body_end - @sizeOf(Instruction) * (1 + uav_reloc.reloc.label),
        uav_reloc.reloc.addend,
    ) catch |err|
        return zcu.codegenFail(func.owner_nav, "emit reloc failed: {t}", .{err});
    for (mir.lazy_relocs) |lazy_reloc| emitReloc(
        lf,
        zcu,
        atom_index,
        if (lf.cast(.elf)) |ef|
            @fromBackingInt(ef.zigObjectPtr().?.getOrCreateMetadataForLazySymbol(ef, pt, lazy_reloc.symbol) catch |err|
                return zcu.codegenFail(func.owner_nav, "{s} creating lazy symbol", .{@errorName(err)}))
        else if (lf.cast(.elf2)) |elf|
            elf.lazySymbol(lazy_reloc.symbol) catch |err|
                return zcu.codegenFail(func.owner_nav, "emit lazy symbol: {t}", .{err})
        else
            return zcu.codegenFail(func.owner_nav, "external symbols unimplemented for {s}", .{@tagName(lf.tag)}),
        lazy_reloc.reloc.type,
        body_end - @sizeOf(Instruction) * (1 + lazy_reloc.reloc.label),
        lazy_reloc.reloc.addend,
    ) catch |err|
        return zcu.codegenFail(func.owner_nav, "emit reloc failed: {t}", .{err});
    for (mir.global_relocs) |global_reloc| emitReloc(
        lf,
        zcu,
        atom_index,
        if (lf.cast(.elf)) |ef|
            @fromBackingInt(try ef.getGlobalSymbol(std.mem.span(global_reloc.name), null))
        else if (lf.cast(.elf2)) |elf| elf.externSymbol(.{
            .name = std.mem.span(global_reloc.name),
            .lib_name = null,
            .type = .FUNC,
        }) catch |err|
            return zcu.codegenFail(func.owner_nav, "emit global symbol failed: {t}", .{err}) else return zcu.codegenFail(func.owner_nav, "external symbols unimplemented for {s}", .{@tagName(lf.tag)}),
        global_reloc.reloc.type,
        body_end - @sizeOf(Instruction) * (1 + global_reloc.reloc.label),
        global_reloc.reloc.addend,
    ) catch |err|
        return zcu.codegenFail(func.owner_nav, "emit reloc failed: {t}", .{err});

    const func_nav = try @import("../../codegen.zig").genNavRef(
        lf,
        pt,
        func.owner_nav,
    );
    for (mir.internal_relocs) |internal_reloc| emitReloc(
        lf,
        zcu,
        atom_index,
        func_nav,
        internal_reloc.reloc.type,
        body_end - @sizeOf(Instruction) * (1 + internal_reloc.reloc.label),
        @sizeOf(Instruction) * (@as(i64, @intCast(mir.prologue.len + mir.body.len - internal_reloc.target))),
    ) catch |err|
        return zcu.codegenFail(func.owner_nav, "emit reloc failed: {t}", .{err});
}

fn emitInstructionsForward(w: *std.Io.Writer, instructions: []const Instruction) !void {
    for (instructions) |instruction| try emitInstruction(w, instruction);
}
fn emitInstructionsBackward(w: *std.Io.Writer, instructions: []const Instruction) !void {
    var instruction_index = instructions.len;
    while (instruction_index > 0) {
        instruction_index -= 1;
        try emitInstruction(w, instructions[instruction_index]);
    }
}
fn emitInstruction(w: *std.Io.Writer, instruction: Instruction) !void {
    mir_log.debug("    {f}", .{(Disassemble{}).fmtInstruction(instruction)});
    try w.writeInt(@FieldType(Instruction, "word"), instruction.word, .little);
}

fn emitReloc(
    lf: *link.File,
    zcu: *Zcu,
    atom_index: link.File.AtomId,
    sym_index: link.File.SymbolId,
    reloc_type: std.elf.R_LARCH,
    offset: u32,
    addend: i64,
) !void {
    if (lf.cast(.elf2)) |ef| {
        try ef.addReloc(atom_index, offset, sym_index, addend, .{ .LARCH = reloc_type });
    } else if (lf.cast(.elf)) |ef| {
        const zo = ef.zigObjectPtr().?;
        const atom = zo.symbol(@backingInt(atom_index)).atom(ef).?;
        try atom.addReloc(zcu.gpa, .{
            .r_offset = offset,
            .r_info = @as(u64, @backingInt(sym_index)) << 32 | @backingInt(reloc_type),
            .r_addend = @bitCast(addend),
        }, zo);
    } else unreachable;
}

const Air = @import("../../Air.zig");
const assert = std.debug.assert;
const mir_log = std.log.scoped(.mir);
const InternPool = @import("../../InternPool.zig");
const link = @import("../../link.zig");
const std = @import("std");
const target_util = @import("../../target.zig");
const Zcu = @import("../../Zcu.zig");
const ZigType = @import("../../Type.zig");
