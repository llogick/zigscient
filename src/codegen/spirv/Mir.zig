const std = @import("std");
const Allocator = std.mem.Allocator;
const spec = @import("spec.zig");
const Word = spec.Word;
const Id = spec.Id;
const Section = @import("Section.zig");
const InternPool = @import("../../InternPool.zig");
const Mir = @This();

id_bound: Word,
module: Section,
nav_refs: []const NavRef,
externs: []const Extern,
entry_points: []const EntryPoint,

pub const NavRef = struct {
    id: Id,
    nav: InternPool.Nav.Index,
};

pub const Extern = struct {
    id: Id,
    name: []const u8,
};

pub const EntryPoint = struct {
    id: Id,
    name: []const u8,
    cc: std.builtin.CallingConvention,
};

pub fn deinit(mir: *Mir, gpa: Allocator) void {
    mir.module.deinit(gpa);
    gpa.free(mir.nav_refs);
    gpa.free(mir.externs);
    for (mir.entry_points) |ep| gpa.free(ep.name);
    gpa.free(mir.entry_points);
    mir.* = undefined;
}
