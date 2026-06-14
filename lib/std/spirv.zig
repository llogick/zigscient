const std = @import("std.zig");

pub const position_in = @extern(*addrspace(.input) @Vector(4, f32), .{ .name = "position" });
pub const position_out = @extern(*addrspace(.output) @Vector(4, f32), .{ .name = "position" });
pub const point_size_in = @extern(*addrspace(.input) f32, .{ .name = "point_size" });
pub const point_size_out = @extern(*addrspace(.output) f32, .{ .name = "point_size" });
pub extern const invocation_id: u32 addrspace(.input);
pub extern const frag_coord: @Vector(4, f32) addrspace(.input);
pub extern const point_coord: @Vector(2, f32) addrspace(.input);
// TODO: direct/indirect values
// pub extern const front_facing: bool addrspace(.input);
// TODO: runtime array
// pub extern const sample_mask;
pub extern var frag_depth: f32 addrspace(.output);
pub extern const num_workgroups: @Vector(3, u32) addrspace(.input);
pub extern const workgroup_size: @Vector(3, u32) addrspace(.input);
pub extern const workgroup_id: @Vector(3, u32) addrspace(.input);
pub extern const local_invocation_id: @Vector(3, u32) addrspace(.input);
pub extern const global_invocation_id: @Vector(3, u32) addrspace(.input);
pub extern const vertex_index: u32 addrspace(.input);
pub extern const instance_index: u32 addrspace(.input);

pub const Scope = enum(u32) {
    cross_device = 0,
    device = 1,
    workgroup = 2,
    subgroup = 3,
    invocation = 4,
    queue_family = 5,
    shader_call_khr = 6,
};

pub const MemorySemantics = packed struct(u32) {
    _reserved_bit_0: bool = false,
    acquire: bool = false,
    release: bool = false,
    acquire_release: bool = false,
    sequentially_consistent: bool = false,
    _reserved_bit_5: bool = false,
    uniform_memory: bool = false,
    subgroup_memory: bool = false,
    workgroup_memory: bool = false,
    cross_workgroup_memory: bool = false,
    atomic_counter_memory: bool = false,
    image_memory: bool = false,
    output_memory: bool = false,
    make_available: bool = false,
    make_visible: bool = false,
    @"volatile": bool = false,
    _reserved: u16 = 0,

    pub const none: MemorySemantics = .{};
};

pub fn controlBarrier(
    comptime execution: Scope,
    comptime memory: Scope,
    comptime semantics: MemorySemantics,
) void {
    asm volatile (
        \\OpControlBarrier %exec %mem %sem
        :
        : [exec] "" (@as(u32, @intFromEnum(execution))),
          [mem] "" (@as(u32, @intFromEnum(memory))),
          [sem] "" (@as(u32, @bitCast(semantics))),
    );
}

pub fn memoryBarrier(comptime memory: Scope, comptime semantics: MemorySemantics) void {
    asm volatile (
        \\OpMemoryBarrier %mem %sem
        :
        : [mem] "" (@as(u32, @intFromEnum(memory))),
          [sem] "" (@as(u32, @bitCast(semantics))),
    );
}

pub fn workgroupBarrier() void {
    controlBarrier(
        .workgroup,
        .workgroup,
        .{ .acquire_release = true, .workgroup_memory = true },
    );
}
