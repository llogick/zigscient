const std = @import("std");
const Allocator = std.mem.Allocator;
const Path = std.Build.Cache.Path;
const assert = std.debug.assert;
const Zcu = @import("../Zcu.zig");
const InternPool = @import("../InternPool.zig");
const Compilation = @import("../Compilation.zig");
const link = @import("../link.zig");
const codegen = @import("../codegen.zig");
const CodeGen = @import("../codegen/spirv/CodeGen.zig");
const Mir = @import("../codegen/spirv/Mir.zig");
const spec = @import("../codegen/spirv/spec.zig");
const Section = @import("../codegen/spirv/Section.zig");
const Flush = @import("Spirv/Flush.zig");
const Word = spec.Word;
const Linker = @This();

base: link.File,
mirs: std.array_hash_map.Auto(InternPool.Nav.Index, Mir),
objects: std.ArrayList(Object),
exports: std.array_hash_map.Auto(InternPool.Nav.Index, InternPool.NullTerminatedString),

pub const Object = struct { path: Path, mir: Mir };

pub fn createEmpty(
    arena: Allocator,
    comp: *Compilation,
    emit: Path,
    options: link.File.OpenOptions,
) !*Linker {
    const file = try emit.root_dir.handle.createFile(comp.io, emit.sub_path, .{});
    errdefer file.close(comp.io);
    const linker = try arena.create(Linker);
    linker.* = .{
        .base = .{
            .tag = .spirv,
            .comp = comp,
            .emit = emit,
            .gc_sections = options.gc_sections orelse false,
            .print_gc_sections = options.print_gc_sections,
            .stack_size = options.stack_size orelse 0,
            .allow_shlib_undefined = options.allow_shlib_undefined orelse false,
            .file = file,
            .build_id = options.build_id,
        },
        .mirs = .empty,
        .objects = .empty,
        .exports = .empty,
    };
    return linker;
}

pub fn open(
    arena: Allocator,
    comp: *Compilation,
    emit: Path,
    options: link.File.OpenOptions,
) !*Linker {
    return createEmpty(arena, comp, emit, options);
}

pub fn deinit(linker: *Linker) void {
    const gpa = linker.base.comp.gpa;
    for (linker.mirs.values()) |*mir| mir.deinit(gpa);
    linker.mirs.deinit(gpa);
    for (linker.objects.items) |*object| object.mir.deinit(gpa);
    linker.objects.deinit(gpa);
    linker.exports.deinit(gpa);
}

pub fn loadInput(linker: *Linker, input: link.Input) !void {
    const diags = &linker.base.comp.link_diags;
    switch (input) {
        .object => |obj| try linker.loadObject(obj),
        else => return diags.fail("unsupported link input for SPIR-V target", .{}),
    }
}

fn loadObject(linker: *Linker, obj: link.Input.Object) !void {
    const comp = linker.base.comp;
    const gpa = comp.gpa;
    const io = comp.io;
    const diags = &comp.link_diags;

    const file_size = obj.file.length(io) catch |err| {
        return diags.failParse(obj.path, "failed to get file size: {t}", .{err});
    };
    if (file_size % @sizeOf(Word) != 0) {
        return diags.failParse(obj.path, "file size is not a multiple of {d}", .{
            @sizeOf(Word),
        });
    }

    const words = try gpa.alloc(Word, @intCast(file_size / @sizeOf(Word)));
    defer gpa.free(words);
    const bytes = std.mem.sliceAsBytes(words);
    const n_read = obj.file.readPositionalAll(io, bytes, 0) catch |err| {
        return diags.failParse(obj.path, "failed to read: {t}", .{err});
    };

    if (n_read != bytes.len) {
        return diags.failParse(obj.path, "incomplete read", .{});
    }
    const header_len = @sizeOf(spec.Header) / @sizeOf(Word);
    if (words.len < header_len) {
        return diags.failParse(obj.path, "header too small", .{});
    }
    const header = std.mem.bytesToValue(spec.Header, std.mem.sliceAsBytes(words[0..header_len]));
    if (header.magic != spec.magic_number) {
        return diags.failParse(obj.path, "invalid magic number", .{});
    }
    if (header.id_bound == 0) {
        return diags.failParse(obj.path, "invalid id bound", .{});
    }

    const instructions = words[header_len..];
    var module = Section.fromWords(gpa, instructions, header.id_bound) catch |err| switch (err) {
        error.OutOfMemory => |e| return e,
        else => return diags.failParse(obj.path, "failed to parse instructions: {t}", .{err}),
    };
    errdefer module.deinit(gpa);
    try linker.objects.append(gpa, .{ .path = obj.path, .mir = .{
        .id_bound = header.id_bound,
        .module = module,
        .nav_refs = &.{},
        .externs = &.{},
        .entry_points = &.{},
    } });
}

pub fn updateFunc(
    linker: *Linker,
    pt: Zcu.PerThread,
    func_index: InternPool.Index,
    mir: *codegen.AnyMir,
) !void {
    const gpa = linker.base.comp.gpa;
    const nav_index = pt.zcu.funcInfo(func_index).owner_nav;
    const gop = try linker.mirs.getOrPut(gpa, nav_index);
    if (gop.found_existing) gop.value_ptr.deinit(gpa);
    gop.value_ptr.* = mir.spirv;
    mir.spirv = .{
        .id_bound = 1,
        .module = .empty,
        .nav_refs = &.{},
        .externs = &.{},
        .entry_points = &.{},
    };
}

pub fn updateNav(
    linker: *Linker,
    pt: Zcu.PerThread,
    nav_index: InternPool.Nav.Index,
) link.Error!void {
    const gpa = linker.base.comp.gpa;
    const ip = &pt.zcu.intern_pool;
    const resolved = ip.getNav(nav_index).resolved.?;
    switch (ip.indexToKey(resolved.value)) {
        .func => return,
        .@"extern" => |@"extern"| if (ip.isFunctionType(@"extern".ty)) return,
        else => if (!resolved.@"const") assert(resolved.@"threadlocal") else return,
    }
    var mir = CodeGen.generateNav(pt, nav_index) catch |err| switch (err) {
        error.AlreadyReported => return,
        else => |e| return e,
    };
    errdefer mir.deinit(gpa);
    const gop = try linker.mirs.getOrPut(gpa, nav_index);
    if (gop.found_existing) gop.value_ptr.deinit(gpa);
    gop.value_ptr.* = mir;
}

pub fn updateExports(
    linker: *Linker,
    pt: Zcu.PerThread,
    export_indices: []const Zcu.Export.Index,
) link.Error!void {
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const gpa = linker.base.comp.gpa;
    const diags = &linker.base.comp.link_diags;

    linker.exports.clearRetainingCapacity();
    try linker.exports.ensureUnusedCapacity(gpa, export_indices.len);
    for (export_indices) |exp_index| {
        const exp = exp_index.ptr(zcu);
        const nav_index = switch (exp.exported) {
            .nav => |nav| nav,
            .uav => return diags.fail("cannot export a uav constant for SPIR-V target", .{}),
        };
        const nav = ip.getNav(nav_index);
        const resolved = nav.resolved.?;
        if (!ip.isFunctionType(resolved.type) and !resolved.@"threadlocal") {
            return diags.fail("cannot export constant '{f}' for SPIR-V target", .{
                nav.fqn.fmt(ip),
            });
        }
        linker.exports.putAssumeCapacity(nav_index, exp.opts.name);
    }
}

pub fn flush(
    linker: *Linker,
    arena: Allocator,
    tid: Zcu.PerThread.Id,
    prog_node: std.Progress.Node,
) link.Error!void {
    _ = tid;
    const comp = linker.base.comp;
    const gpa = comp.gpa;
    const diags = &comp.link_diags;

    const sub_node = prog_node.start("Flush Module", 1);
    defer sub_node.end();

    var f: Flush = .{
        .linker = linker,
        .arena = arena,
        .id_bound = 1,
        .navs = .empty,
        .symbols = .empty,
        .interned = .empty,
        .variables = .empty,
        .function_references = .empty,
        .entry_points = .empty,
        .deps = .empty,
        .scratch = .empty,
        .extended_instruction_sets = .empty,
        .object_entry_points = .empty,
        .object_execution_modes = .empty,
        .debug_strings = .empty,
        .names = .empty,
        .decorations = .empty,
        .globals = .empty,
        .declarations = .empty,
        .functions = .empty,
    };
    var out: Section = .empty;
    defer out.deinit(gpa);

    try f.emitModule(&out);
    sub_node.completeOne();

    var writer = linker.base.file.?.writer(comp.io, &.{});
    writer.interface.writeSliceEndian(Word, out.instructions.items, .little) catch {
        return diags.fail("failed to write {f}: {t}", .{ linker.base.emit, writer.err.? });
    };
    writer.end() catch |err| {
        return diags.fail("failed to write {f}: {t}", .{ linker.base.emit, err });
    };
}
