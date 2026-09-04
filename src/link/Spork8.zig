const Spork8 = @This();
const builtin = @import("builtin");
const build_options = @import("build_options");

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const Path = std.Build.Cache.Path;
const log = std.log.scoped(.link);

const Air = @import("../Air.zig");
const InternPool = @import("../InternPool.zig");
const Zcu = @import("../Zcu.zig");
const CodeGen = @import("../codegen/spork8/CodeGen.zig");
const codegen = @import("../codegen.zig");
const Mir = @import("../codegen/spork8/Mir.zig");
const link = @import("../link.zig");
const Compilation = @import("../Compilation.zig");
const Liveness = @import("../Air/Liveness.zig");
const Value = @import("../Value.zig");

base: link.File,
/// All MIR instructions for all Zcu functions.
mir_instructions: std.MultiArrayList(Mir.Inst) = .{},
/// Corresponds to `mir_instructions`.
mir_extra: std.ArrayListUnmanaged(u32) = .empty,
/// When the key is an enum type, this represents a `@tagName` function.
zcu_funcs: std.array_hash_map.Auto(InternPool.Index, ZcuFunc) = .empty,

pub fn open(
    arena: Allocator,
    comp: *Compilation,
    emit: Path,
    options: link.File.OpenOptions,
) !*Spork8 {
    // TODO: restore saved linker state, don't truncate the file, and
    // participate in incremental compilation.
    return createEmpty(arena, comp, emit, options);
}

pub fn createEmpty(
    arena: Allocator,
    comp: *Compilation,
    emit: Path,
    options: link.File.OpenOptions,
) !*Spork8 {
    const target = comp.root_mod.resolved_target.result;
    assert(target.ofmt == .raw);
    assert(comp.config.output_mode == .Exe);
    const io = comp.io;

    const spork8 = try arena.create(Spork8);
    spork8.* = .{
        .base = .{
            .tag = .spork8,
            .comp = comp,
            .emit = emit,
            .gc_sections = options.gc_sections orelse true,
            .print_gc_sections = options.print_gc_sections,
            .stack_size = options.stack_size orelse switch (target.os.tag) {
                .freestanding => 1 * 1024 * 1024, // 1 MiB
                else => 16 * 1024 * 1024, // 16 MiB
            },
            .allow_shlib_undefined = options.allow_shlib_undefined orelse false,
            .file = null,
            .build_id = options.build_id,
        },
    };
    errdefer spork8.base.destroy();

    spork8.base.file = try emit.root_dir.handle.createFile(io, emit.sub_path, .{
        .truncate = true,
        .read = true,
    });

    return spork8;
}

pub fn deinit(spork8: *Spork8) void {
    const gpa = spork8.base.comp.gpa;
    _ = gpa;
}

pub fn updateFunc(
    spork8: *Spork8,
    pt: Zcu.PerThread,
    func_index: InternPool.Index,
    any_mir: *const codegen.AnyMir,
) !void {
    // This linker implementation only works with `std.lang.CompilerBackend.zsf_spork8`.
    const mir = &any_mir.spork8;
    const zcu = pt.zcu;
    const gpa = zcu.gpa;
    const ip = &zcu.intern_pool;
    const owner_nav = zcu.funcInfo(func_index).owner_nav;

    log.debug("updateFunc {f}", .{ip.getNav(owner_nav).fqn.fmt(ip)});

    // For Spork8, we do not lower the MIR to code just yet. That lowering happens during `flush`,
    // after garbage collection, which can affect function and global indexes, which affects the
    // LEB integer encoding, which affects the output binary size.

    // However, we do move the MIR into a more efficient in-memory representation, where the arrays
    // for all functions are packed together rather than keeping them each in their own `Mir`.
    const mir_instructions_off: u32 = @intCast(spork8.mir_instructions.len);
    const mir_extra_off: u32 = @intCast(spork8.mir_extra.items.len);
    {
        // Copying MultiArrayList data is a little non-trivial. Resize, then memcpy both slices.
        const old_len = spork8.mir_instructions.len;
        try spork8.mir_instructions.resize(gpa, old_len + mir.instructions.len);
        const dest_slice = spork8.mir_instructions.slice().subslice(old_len, mir.instructions.len);
        const src_slice = mir.instructions;
        @memcpy(dest_slice.items(.tag), src_slice.items(.tag));
        @memcpy(dest_slice.items(.data), src_slice.items(.data));
    }
    try spork8.mir_extra.appendSlice(gpa, mir.extra);

    try spork8.zcu_funcs.ensureUnusedCapacity(gpa, 1);

    // This converts AIR to MIR but does not yet lower to Spork8 code.
    spork8.zcu_funcs.putAssumeCapacity(func_index, .{ .function = .{
        .instructions_off = mir_instructions_off,
        .instructions_len = @intCast(mir.instructions.len),
        .extra_off = mir_extra_off,
        .extra_len = @intCast(mir.extra.len),
    } });
}

pub const ZcuFunc = union {
    function: Function,

    pub const Function = extern struct {
        /// Index into `Spork8.mir_instructions`.
        instructions_off: u32,
        /// This is unused except for as a safety slice bound and could be removed.
        instructions_len: u32,
        /// Index into `Spork8.mir_extra`.
        extra_off: u32,
        /// This is unused except for as a safety slice bound and could be removed.
        extra_len: u32,
    };

    /// Index into `Spork8.zcu_funcs`.
    /// Note that swapRemove is sometimes performed on `zcu_funcs`.
    pub const Index = enum(u32) {
        _,

        pub fn key(i: @This(), spork8: *const Spork8) *InternPool.Index {
            return &spork8.zcu_funcs.keys()[@backingInt(i)];
        }

        pub fn value(i: @This(), spork8: *const Spork8) *ZcuFunc {
            return &spork8.zcu_funcs.values()[@backingInt(i)];
        }
    };
};

// Generate code for the "Nav", storing it in memory to be later written to
// the file on flush().
pub fn updateNav(spork8: *Spork8, pt: Zcu.PerThread, nav_index: InternPool.Nav.Index) !void {
    _ = spork8;
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const nav = ip.getNav(nav_index);
    log.debug("updateNav {f}", .{nav.fqn.fmt(ip)});
}

pub fn updateLineNumber(spork8: *Spork8, pt: Zcu.PerThread, inst: InternPool.TrackedInst.Index, line: u32) !void {
    _ = spork8;
    _ = pt;
    _ = inst;
    _ = line;
}

pub fn deleteExport(
    spork8: *Spork8,
    exported: Zcu.Exported,
    name: InternPool.NullTerminatedString,
) void {
    const zcu = spork8.base.comp.zcu.?;
    const ip = &zcu.intern_pool;
    const name_slice = name.toSlice(ip);
    switch (exported) {
        .nav => |nav_index| {
            log.debug("deleteExport '{s}' nav={d}", .{ name_slice, @backingInt(nav_index) });
        },
        .uav => |uav_index| {
            log.debug("deleteExport '{s}' uav={d}", .{ name_slice, @backingInt(uav_index) });
        },
    }
}

pub fn updateExports(
    spork8: *Spork8,
    pt: Zcu.PerThread,
    export_indices: []const Zcu.Export.Index,
) !void {
    _ = spork8;
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;

    for (export_indices) |export_idx| {
        const exp = export_idx.ptr(zcu);
        const name_slice = exp.opts.name.toSlice(ip);
        switch (exp.exported) {
            .nav => |nav_index| {
                log.debug("updateExports {q} nav={d}", .{ name_slice, @backingInt(nav_index) });
            },
            .uav => |uav_index| {
                log.debug("updateExports {q} uav={d}", .{ name_slice, @backingInt(uav_index) });
            },
        }
    }
}

pub fn loadInput(spork8: *Spork8, input: link.Input) !void {
    _ = input;
    const comp = spork8.base.comp;
    const diags = &comp.link_diags;
    return diags.failParse("spork8 does not support linking files together", .{});
}

pub fn flush(
    spork8: *Spork8,
    arena: Allocator,
    tid: Zcu.PerThread.Id,
    prog_node: std.Progress.Node,
) link.Error!void {
    const sub_prog_node = prog_node.start("Spork8 Flush", 0);
    defer sub_prog_node.end();
    const io = spork8.base.comp.io;
    const diags = &spork8.base.comp.link_diags;

    _ = arena;
    _ = tid;

    // Finally, write the entire binary into the file.
    var buffer: [1000]u8 = undefined;
    var file_writer = spork8.base.file.?.writer(io, &buffer);
    mirToMC(spork8, &file_writer.interface) catch |err| switch (err) {
        error.WriteFailed => return diags.fail("failed writing to file: {t}", .{file_writer.err.?}),
    };
    file_writer.end() catch |err| switch (err) {
        error.WriteFailed => return diags.fail("failed writing to file: {t}", .{file_writer.err.?}),
        else => |e| return diags.fail("failed writing to file: {t}", .{e}),
    };
}

fn mirToMC(spork8: *Spork8, w: *Io.Writer) !void {
    for (spork8.mir_instructions.items(.tag), spork8.mir_instructions.items(.data)) |tag, data| {
        switch (tag) {
            .set_page_i => @panic("TODO"),
            .set_addr_i => @panic("TODO"),
            .load_i_outa => {
                try w.writeByte(@backingInt(tag));
                try w.writeByte(data.imm8);
            },
            .jump => @panic("TODO"),
            .halt => try w.writeByte(@backingInt(tag)),
        }
    }
}

pub fn prelink(spork8: *Spork8, prog_node: std.Progress.Node) link.Error!void {
    const sub_prog_node = prog_node.start("Spork8 Prelink", 0);
    defer sub_prog_node.end();

    _ = spork8;
}
