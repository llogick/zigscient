const std = @import("std");
const Allocator = std.mem.Allocator;

const spec = @import("spec.zig");
const Word = spec.Word;
const Id = spec.Id;

const InternPool = @import("../../InternPool.zig");
const Module = @import("Module.zig");

const Mir = @This();

id_bound: Word,
owner_nav: InternPool.Nav.Index,
kind: Module.Decl.Kind,
decl_result_id: Id,
extended_instruction_set: []const Word,
globals: []const Word,
functions: []const Word,
annotations: []const Word,
debug_names: []const Word,
debug_strings: []const Word,
execution_modes: []const Word,
nav_refs: []const NavRef,
uav_refs: []const UavRef,
decl_deps: []const DeclDep,
internal_globals: []const Id,
entry_points: []const EntryPoint,

pub const NavRef = struct {
    local_id: Id,
    nav: InternPool.Nav.Index,
    kind: Module.Decl.Kind,
};

pub const UavRef = struct {
    local_id: Id,
    val: InternPool.Index,
    storage_class: spec.StorageClass,
    kind: Module.Decl.Kind,
};

pub const DeclDep = struct {
    kind: Module.Decl.Kind,
    nav: InternPool.Nav.Index,
};

pub const EntryPoint = struct {
    local_id: Id,
    name: []const u8,
    cc: std.builtin.CallingConvention,
};

pub fn deinit(mir: *Mir, gpa: Allocator) void {
    gpa.free(mir.extended_instruction_set);
    gpa.free(mir.globals);
    gpa.free(mir.functions);
    gpa.free(mir.annotations);
    gpa.free(mir.debug_names);
    gpa.free(mir.debug_strings);
    gpa.free(mir.execution_modes);
    gpa.free(mir.nav_refs);
    gpa.free(mir.uav_refs);
    gpa.free(mir.decl_deps);
    gpa.free(mir.internal_globals);
    for (mir.entry_points) |ep| {
        gpa.free(ep.name);
    }
    gpa.free(mir.entry_points);
    mir.* = undefined;
}
