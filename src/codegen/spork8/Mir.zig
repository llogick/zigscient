const Mir = @This();
const InternPool = @import("../../InternPool.zig");

const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;

instructions: std.MultiArrayList(Inst).Slice,

extra: []const u32,

pub const Inst = struct {
    tag: Tag,
    data: Data,

    /// The position of a given MIR isntruction with the instruction list.
    pub const Index = enum(u32) {
        _,
    };

    pub const Tag = enum(u8) {
        /// imm8
        set_page_i = 0x04,
        /// imm8
        set_addr_i = 0x09,
        /// imm8
        load_i_outa = 0x15,
        /// index
        jump = 0x68,
        /// nothing
        halt = 0xE3,
    };

    /// All instructions contain a 4-byte payload, which is contained within
    /// this union. `Tag` determines which union tag is active, as well as
    /// how to interpret the data within.
    pub const Data = union {
        imm8: u8,
        index: Index,
        nothing: void,

        comptime {
            switch (builtin.mode) {
                .Debug, .ReleaseSafe => {},
                .ReleaseFast, .ReleaseSmall => assert(@sizeOf(Data) == 4),
            }
        }
    };
};

pub fn deinit(mir: *Mir, gpa: std.mem.Allocator) void {
    mir.instructions.deinit(gpa);
    mir.* = undefined;
}
