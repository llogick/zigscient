const Register = @import("bits.zig").Register;
const encoding = @import("encoding.zig");
const Instruction = encoding.Instruction;
const Mir = @import("Mir.zig");
const Assemble = @import("Assemble.zig");
const Disassemble = @import("Disassemble.zig");

const verify_target_features = false;
const assume_memmove_no_overlap = true;
/// https://github.com/ziglang/zig/issues/11307
/// Enabling this flag generates "break 0xAA" for unimplemented things.
const debug_trap_unimplemented_code = false;
/// Saves AIR index to $r21 for debugging.
const debug_r21_as_air = false;

pt: Zcu.PerThread,
target: *const std.Target,
opt_mode: std.builtin.OptimizeMode,
air: Air,
nav_index: InternPool.Nav.Index,

// WIP MIR
saved_registers: RegisterSet = .empty,
instructions: std.ArrayList(Instruction) = .empty,
nav_relocs: std.ArrayList(Mir.Reloc.Nav) = .empty,
uav_relocs: std.ArrayList(Mir.Reloc.Uav) = .empty,
lazy_relocs: std.ArrayList(Mir.Reloc.Lazy) = .empty,
global_relocs: std.ArrayList(Mir.Reloc.Global) = .empty,
internal_relocs: std.ArrayList(Mir.Reloc.Internal) = .empty,

// Stack Frame
returns: bool = false,
stack_size: u24 = 0,
stack_align: InternPool.Alignment = .@"16",
/// Relocations for reading incoming registers.
///
/// The instruction must be `ori rd, rj, 0`.
/// These relocations are applied in `Select.layout`,
/// and the instruction may be replaced with `ld.[w/d] rd, sp, ?`
/// if `rj` is spilled to stack.
///
/// See `Select.ldIncoming`.
layout_relocs: std.ArrayList(usize) = .empty,

// Value Tracking
live_registers: LiveRegisters = .initFill(.free),
live_values: std.AutoHashMapUnmanaged(Air.Inst.Index, Value.Index) = .empty,
values: std.ArrayList(Value) = .empty,
value_types: std.ArrayList(ZigType) = .empty,

// Calling Convention
arg_layouts: []const Value.Index = &.{},

// Analysis
/// Definition order of AIR instructions.
def_order: std.AutoArrayHashMapUnmanaged(Air.Inst.Index, void) = .empty,
/// Stack of active blocks. Value is undefined during analysis.
active_blocks: std.AutoArrayHashMapUnmanaged(Air.Inst.Index, Block) = .empty,
/// Loops. The last entry is Loop.invalid, which is added in `finishAnalysis`.
loops: std.AutoArrayHashMapUnmanaged(Air.Inst.Index, Loop) = .empty,
/// Stack of active loops.
active_loops: std.ArrayList(Loop.Index) = .empty,
/// Loop liveness
loop_outer_live: struct {
    /// Pairs of loops and AIRs that is used in the loop body but is defined
    /// earlier than the loop entry.
    /// Populated during analysis phase, in analyseUse.
    ///
    /// Includes only references where the loop and the AIR are in the same upper loop.
    /// For example, in the following structure:
    /// %1 arg
    /// %2 arg
    /// %3 arg
    /// %4 loop (loop 0)
    ///    %5 add %1 %2
    ///    %6 loop (loop 1)
    ///       %7 add %3 %5
    ///       %8 add %2 %5
    /// Only (loop 0, %1), (loop 0, %2), (loop 0, %3), (loop 1, %5) will be recorded, because,
    /// although %2 and %3 are used in loop 1, they are in the outer layer of loop 0, not loop 1.
    set: std.AutoArrayHashMapUnmanaged(struct { Loop.Index, Air.Inst.Index }, void) = .empty,
    /// List representation of `loop_live.set`, for faster indexing.
    list: std.ArrayList(Air.Inst.Index) = .empty,
} = .{},

pub const RegisterSet = std.enums.EnumSet(Register);
pub const LiveRegisters = std.enums.EnumArray(Register, Value.Index);

pub const Block = struct {
    snapshot: LocationSnapshot = .empty,
    target_label: u32,

    pub const main: Air.Inst.Index = @fromBackingInt(
        std.math.maxInt(@typeInfo(Air.Inst.Index).@"enum".tag_type),
    );

    pub fn deinit(target_block: *Block, isel: *Select) void {
        target_block.snapshot.deinit(isel);
    }

    fn branch(target_block: *Block, isel: *Select) !void {
        if (isel.instructions.items.len > target_block.target_label) {
            try isel.internal_relocs.append(isel.pt.zcu.gpa, .{
                .label = @intCast(isel.instructions.items.len),
                .target = target_block.target_label,
            });
            try isel.emit(.b(0, 0));
        }
        try target_block.snapshot.merge(isel);
    }
};

pub const Loop = struct {
    def_order: u32,
    outer_live: u32,
    repeat_list: u32,
    /// Used during code selection. Location snapshot before entering loop bodyies.
    /// Cleared after leaving the loop body.
    snapshot: LocationSnapshot = .empty,
    /// Used during code selection. Registers that are written during a loop body.
    /// See Select.markRegWritten.
    /// After leaving a loop, written register set is copied to the outer loop.
    written_regs: RegisterSet = .empty,

    pub const invalid: Air.Inst.Index = @fromBackingInt(
        std.math.maxInt(@typeInfo(Air.Inst.Index).@"enum".tag_type),
    );

    pub const Index = enum(u32) {
        _,

        fn inst(li: Loop.Index, isel: *Select) Air.Inst.Index {
            return isel.loops.keys()[@backingInt(li)];
        }

        fn get(li: Loop.Index, isel: *Select) *Loop {
            return &isel.loops.values()[@backingInt(li)];
        }
    };

    pub const empty_list: u32 = std.math.maxInt(u32);

    fn branch(target_loop: *Loop, isel: *Select) !void {
        try isel.instructions.ensureUnusedCapacity(isel.pt.zcu.gpa, 1);
        const repeat_list_tail = target_loop.repeat_list;
        target_loop.repeat_list = @intCast(isel.instructions.items.len);
        isel.instructions.appendAssumeCapacity(@bitCast(repeat_list_tail));
        try target_loop.snapshot.merge(isel);
    }
};

pub fn deinit(isel: *Select) void {
    const gpa = isel.pt.zcu.gpa;

    isel.instructions.deinit(gpa);
    isel.nav_relocs.deinit(gpa);
    isel.uav_relocs.deinit(gpa);
    isel.lazy_relocs.deinit(gpa);
    isel.global_relocs.deinit(gpa);
    isel.internal_relocs.deinit(gpa);

    isel.layout_relocs.deinit(gpa);

    isel.live_values.deinit(gpa);
    isel.values.deinit(gpa);
    isel.value_types.deinit(gpa);

    if (isel.arg_layouts.len != 0) gpa.free(isel.arg_layouts);

    isel.def_order.deinit(gpa);
    isel.active_blocks.deinit(gpa);
    isel.loops.deinit(gpa);
    isel.active_loops.deinit(gpa);
    isel.loop_outer_live.set.deinit(gpa);
    isel.loop_outer_live.list.deinit(gpa);

    isel.* = undefined;
}

/// A node in the value tree.
pub const Value = struct {
    refs: u32,
    flags: Flags,
    offset_from_parent: u64,
    parent_payload: Parent.Payload,
    location_payload: LocationInfo.Payload,
    parts: Value.Index,

    /// Must be at least 16 to compute call ABI.
    /// Must be at least 16, the largest hardware alignment.
    pub const max_parts = 16;
    pub const PartsLen = std.math.IntFittingRange(0, Value.max_parts);

    comptime {
        if (!std.debug.runtime_safety) assert(@sizeOf(Value) == 32);
    }

    pub const Flags = packed struct(u32) {
        alignment: InternPool.Alignment,
        parent_tag: Parent.Tag,
        location_tag: LocationInfo.Tag,
        parts_len_minus_one: std.math.IntFittingRange(0, Value.max_parts - 1),
        splitted: bool,
        unused: u17 = 0,
    };

    pub const Parent = union(enum(u2)) {
        none: void,
        value: Value.Index,
        constant: Constant,
        /// Dereferencing. Only used for layout values at ABI boundaries.
        address: Value.Index,

        pub const Tag = @typeInfo(Parent).@"union".tag_type.?;
        pub const Payload = Payload: {
            const info = @typeInfo(Parent).@"union";
            break :Payload @Union(.auto, null, info.field_names, info.field_types[0..], &@splat(.{}));
        };
    };

    pub const LocationInfo = union(enum(u2)) {
        /// Small values that fit into a register
        small: struct {
            flags: packed struct {
                /// Byte-size of the part
                size: u6,
                /// Way in which the unused bits are filled
                /// For subtrees whose root has Parent.address, immutable after initialization
                extension: Extension,
                /// Register access modifier
                hint_modifier: Register.Modifier,
                /// Preferred register, maybe ignore, $zero = unset
                hint_register: Register,
                /// The current expected location
                location_tag: Location.Tag,
            },
            location_payload: Location.Payload,
        },
        /// Large values that can only be stored in stack slots
        large: struct {
            /// Byte-size of the part
            size: u32,
            /// The current expected location
            /// Well-shaped values are always in pcs extended, ill-shaped are garbage extended
            stack_slot: Indirect,
        },
        /// Extreme values that are too large to be materialized in stack slots
        extreme: struct {
            size: u64,
        },

        pub const Tag = @typeInfo(LocationInfo).@"union".tag_type.?;
        pub const Payload = Payload: {
            const info = @typeInfo(LocationInfo).@"union";
            break :Payload @Union(.auto, null, info.field_names, info.field_types[0..], &@splat(.{}));
        };
    };

    pub const Location = union(enum(u1)) {
        register: Register.Alias,
        stack_slot: Indirect,

        pub const unallocated: Location = .{ .register = .zero };

        pub inline fn isUnallocated(loc: Location) bool {
            return switch (loc) {
                .register => |ra| ra.reg == Register.zero,
                else => false,
            };
        }

        fn tryLock(loc: Location, isel: *Select) RegLock {
            return if (loc.asRegister()) |reg| isel.tryLockReg(reg) else .empty;
        }

        pub fn asRegisterAlias(loc: Location) ?Register.Alias {
            return switch (loc) {
                .register => |ra| if (ra.reg == Register.zero) null else ra,
                else => null,
            };
        }

        pub fn asRegister(loc: Location) ?Register {
            return if (loc.asRegisterAlias()) |ra| ra.reg else null;
        }

        pub fn asStackSlot(loc: Location) ?Indirect {
            return switch (loc) {
                .stack_slot => |stack_slot| stack_slot,
                else => null,
            };
        }

        pub fn format(loc: Location, w: *std.Io.Writer) std.Io.Writer.Error!void {
            if (loc.isUnallocated()) return w.writeAll("unallocated");
            switch (loc) {
                inline else => |loc_pl| try loc_pl.format(w),
            }
        }

        pub fn markRegWritten(loc: Location, isel: *Select) void {
            if (loc.asRegister()) |loc_reg| isel.markRegWritten(loc_reg);
        }

        pub const Tag = @typeInfo(Location).@"union".tag_type.?;
        pub const Payload = Payload: {
            const info = @typeInfo(Location).@"union";
            break :Payload @Union(.auto, null, info.field_names, info.field_types[0..], &@splat(.{}));
        };
    };

    // TODO far indirect
    pub const Indirect = packed struct(u32) {
        base: Register,
        offset: i25,

        pub const unallocated: Indirect = .{ .base = .zero, .offset = 0 };

        pub fn withOffset(ind: Indirect, offset: i25) Indirect {
            return .{
                .base = ind.base,
                .offset = ind.offset + offset,
            };
        }

        pub fn format(self: Indirect, w: *std.Io.Writer) std.Io.Writer.Error!void {
            try w.print("[${t}, #{s}0x{x}]", .{
                self.base,
                if (self.offset < 0) "-" else "",
                @abs(self.offset),
            });
        }
    };

    pub const Extension = enum(u2) {
        garbage,
        sign_ext,
        zero_ext,

        pub fn fromSignedness(signedness: std.builtin.Signedness) Extension {
            return switch (signedness) {
                .signed => .sign_ext,
                .unsigned => .zero_ext,
            };
        }

        fn signednessForLoad(fill_mode: Extension) std.builtin.Signedness {
            return switch (fill_mode) {
                .garbage, .zero_ext => .unsigned,
                .sign_ext => .signed,
            };
        }

        pub fn mix(a: Extension, b: Extension) Extension {
            if (a == b) return a;
            return .garbage;
        }

        fn pcsMode(isel: *Select, ty: ZigType) Extension {
            const zcu = isel.pt.zcu;
            const int_info = switch (ty.zigTypeTag(zcu)) {
                .bool => ZigType.u1.intInfo(zcu),
                .int, .@"enum", .error_set => ty.intInfo(zcu),
                else => return .garbage,
            };
            return switch (int_info.bits) {
                32 => .sign_ext,
                else => .fromSignedness(int_info.signedness),
            };
        }
    };

    pub const Index = enum(u32) {
        allocating = std.math.maxInt(u32) - 1,
        free = std.math.maxInt(u32) - 0,
        _,

        fn get(vi: Value.Index, isel: *Select) *Value {
            return &isel.values.items[@backingInt(vi)];
        }

        fn typeOf(vi: Value.Index, isel: *Select) ?ZigType {
            const ty = isel.value_types.items[@backingInt(vi)];
            if (ty.ip_index == .none) return null;
            return ty;
        }

        pub fn format(vi: Value.Index, w: *std.Io.Writer) std.Io.Writer.Error!void {
            return switch (vi) {
                _ => w.print("${d}", .{@backingInt(vi)}),
                .allocating => w.writeAll("(allocating)"),
                .free => w.writeAll("(free)"),
            };
        }

        fn setAlignment(vi: Value.Index, isel: *Select, new_alignment: InternPool.Alignment) void {
            vi.get(isel).flags.alignment = new_alignment;
        }

        pub fn alignment(vi: Value.Index, isel: *Select) InternPool.Alignment {
            return vi.get(isel).flags.alignment;
        }

        pub fn setParent(vi: Value.Index, isel: *Select, new_parent: Parent) void {
            const value = vi.get(isel);
            if (value.refs > 0) {
                switch (value.flags.parent_tag) {
                    .none, .constant => {},
                    inline .address, .value => |tag| @field(value.parent_payload, @tagName(tag)).deref(isel),
                }
                switch (new_parent) {
                    .none => unreachable,
                    .constant => {},
                    .address, .value => |parent_vi| _ = parent_vi.ref(isel),
                }
            }
            value.flags.parent_tag = new_parent;
            value.parent_payload = switch (new_parent) {
                .none => unreachable,
                inline else => |payload, tag| @unionInit(Parent.Payload, @tagName(tag), payload),
            };
        }

        pub fn parent(vi: Value.Index, isel: *Select) Parent {
            const value = vi.get(isel);
            return switch (value.flags.parent_tag) {
                inline else => |tag| @unionInit(
                    Parent,
                    @tagName(tag),
                    @field(value.parent_payload, @tagName(tag)),
                ),
            };
        }

        pub fn parentValue(vi: Value.Index, isel: *Select) ?Value.Index {
            const value = vi.get(isel);
            return switch (value.flags.parent_tag) {
                .value => value.parent_payload.value,
                else => null,
            };
        }

        pub fn valueRoot(initial_vi: Value.Index, isel: *Select) struct { u64, Value.Index } {
            var offset: u64 = 0;
            var vi = initial_vi;
            parent: switch (vi.parent(isel)) {
                else => return .{ offset, vi },
                .value => |parent_vi| {
                    offset += vi.get(isel).offset_from_parent;
                    vi = parent_vi;
                    continue :parent parent_vi.parent(isel);
                },
            }
        }

        pub fn locationInfo(vi: Value.Index, isel: *Select) LocationInfo {
            const value = vi.get(isel);
            return switch (value.flags.location_tag) {
                inline else => |tag| @unionInit(
                    LocationInfo,
                    @tagName(tag),
                    @field(value.location_payload, @tagName(tag)),
                ),
            };
        }

        pub fn isSmall(vi: Value.Index, isel: *Select) bool {
            return vi.get(isel).flags.location_tag == .small;
        }

        pub fn setSmallLocation(vi: Value.Index, isel: *Select, new_location: Location) void {
            const value = vi.get(isel);
            value.location_payload.small.flags.location_tag = new_location;
            value.location_payload.small.location_payload = switch (new_location) {
                inline else => |payload, tag| @unionInit(Location.Payload, @tagName(tag), payload),
            };
        }

        pub fn smallLocation(vi: Value.Index, isel: *Select) Location {
            const value = vi.get(isel);
            return switch (value.location_payload.small.flags.location_tag) {
                inline else => |tag| @unionInit(
                    Location,
                    @tagName(tag),
                    @field(value.location_payload.small.location_payload, @tagName(tag)),
                ),
            };
        }

        pub fn positionInParent(vi: Value.Index, isel: *Select) struct { u64, u64 } {
            return .{ vi.get(isel).offset_from_parent, vi.size(isel) };
        }

        pub fn offsetIn(initial_vi: Value.Index, isel: *Select, ancestor_vi: Value.Index) u64 {
            if (initial_vi == ancestor_vi) return 0;
            var offset: u64 = 0;
            var vi = initial_vi;
            parent: switch (vi.parent(isel)) {
                else => unreachable, // ancestor_vi is not an ancestor of initial_vi
                .value => |parent_vi| {
                    offset += vi.get(isel).offset_from_parent;
                    if (parent_vi != ancestor_vi) {
                        vi = parent_vi;
                        continue :parent parent_vi.parent(isel);
                    } else return offset;
                },
            }
        }

        pub fn size(vi: Value.Index, isel: *Select) u64 {
            return switch (vi.locationInfo(isel)) {
                .small => |loc| loc.flags.size,
                inline else => |loc| loc.size,
            };
        }

        pub fn bitSize(vi: Value.Index, isel: *Select) u64 {
            if (vi.typeOf(isel)) |init_ty| bit_size: {
                const zcu = isel.pt.zcu;
                var ty = init_ty;
                check_ty: while (true) {
                    switch (ty.zigTypeTag(zcu)) {
                        else => {},
                        .error_union => break :bit_size,
                        .@"struct", .@"union" => if (ty.containerLayout(zcu) != .@"packed") break :bit_size,
                        .pointer, .optional => if (!ty.isPtrAtRuntime(zcu)) break :bit_size,
                        .array, .vector => {
                            ty = ty.childType(zcu);
                            continue :check_ty;
                        },
                    }
                    break :check_ty;
                }
                return init_ty.bitSize(zcu);
            }
            return vi.size(isel) * 8;
        }

        fn setExtension(vi: Value.Index, isel: *Select, new_mode: Extension) void {
            const value = vi.get(isel);
            if (value.flags.location_tag == .small)
                value.location_payload.small.flags.extension = new_mode;
        }

        /// For values on stack, unused bits are the highest ((size * 8) - bit_size) bits.
        /// For values on registers, unused bits are the highest (ra_width - bit_size) bits.
        /// That is, for a u3 (3b, 1B) stored in LA64 GPR (64b, 8B), the unused bits to be filled
        /// are reg[3..63] instead of reg[3..7].
        pub fn extension(vi: Value.Index, isel: *Select) Extension {
            const value = vi.get(isel);
            return switch (value.flags.location_tag) {
                .small => value.location_payload.small.flags.extension,
                .large, .extreme => if (vi.typeOf(isel)) |ty| .pcsMode(isel, ty) else .garbage,
            };
        }

        fn setHintModifier(vi: Value.Index, isel: *Select, new_modifier: Register.Modifier) void {
            vi.get(isel).location_payload.small.flags.hint_modifier = new_modifier;
        }

        pub fn hintModifier(vi: Value.Index, isel: *Select) Register.Modifier {
            return switch (vi.locationInfo(isel)) {
                .small => |loc| loc.flags.hint_modifier,
                .large, .extreme => .undef,
            };
        }

        fn setHintRegister(vi: Value.Index, isel: *Select, new_hint: Register) void {
            vi.get(isel).location_payload.small.flags.hint_register = new_hint;
        }

        pub fn hintRegister(vi: Value.Index, isel: *Select) ?Register {
            return switch (vi.locationInfo(isel)) {
                .small => |loc| switch (loc.flags.hint_register) {
                    Register.zero => null,
                    else => |hint_reg| hint_reg,
                },
                .large, .extreme => null,
            };
        }

        pub fn hintRegisterAlias(vi: Value.Index, isel: *Select) ?Register.Alias {
            return switch (vi.locationInfo(isel)) {
                .small => |loc| switch (loc.flags.hint_register) {
                    Register.zero => null,
                    else => |hint_reg| .{ .mod = vi.hintModifier(isel), .reg = hint_reg },
                },
                .large, .extreme => null,
            };
        }

        pub fn location(vi: Value.Index, isel: *Select) ?Location {
            return switch (vi.locationInfo(isel)) {
                .small => |loc| if (loc.flags.location_tag == .register and loc.location_payload.register.reg == Register.zero)
                    null
                else switch (loc.flags.location_tag) {
                    inline else => |tag| @unionInit(
                        Location,
                        @tagName(tag),
                        @field(loc.location_payload, @tagName(tag)),
                    ),
                },
                .large => |loc| if (loc.stack_slot == Indirect.unallocated)
                    null
                else
                    .{ .stack_slot = loc.stack_slot },
                .extreme => null,
            };
        }

        pub fn register(vi: Value.Index, isel: *Select) ?Register.Alias {
            return switch (vi.location(isel) orelse return null) {
                .register => |ra| ra,
                .stack_slot => null,
            };
        }

        pub fn stackSlot(vi: Value.Index, isel: *Select) ?Indirect {
            return switch (vi.location(isel) orelse return null) {
                .register => null,
                .stack_slot => |slot| slot,
            };
        }

        /// Takes the expected location. Registers are free.
        fn takeLocation(vi: Value.Index, isel: *Select) ?Location {
            const value = vi.get(isel);
            return switch (value.flags.location_tag) {
                .small => loc: {
                    const loc = vi.smallLocation(isel);
                    if (loc.isUnallocated()) break :loc null;
                    if (loc.asRegister()) |reg| {
                        const live_vi = isel.live_registers.getPtr(reg);
                        assert(live_vi.* == vi);
                        live_vi.* = .free;
                    }
                    vi.setSmallLocation(isel, .unallocated);
                    break :loc loc;
                },
                .large => loc: {
                    const stack_slot = value.location_payload.large.stack_slot;
                    if (stack_slot == Indirect.unallocated) break :loc null;
                    value.location_payload.large.stack_slot = .unallocated;
                    break :loc .{ .stack_slot = stack_slot };
                },
                .extreme => null,
            };
        }

        /// Takes the expected location. Registers are free and marked written.
        fn takeLocationMarkWritten(vi: Value.Index, isel: *Select) ?Location {
            const maybe_loc = vi.takeLocation(isel);
            if (maybe_loc) |loc| loc.markRegWritten(isel);
            return maybe_loc;
        }

        fn setStackSlot(vi: Value.Index, isel: *Select, new_slot: Indirect) void {
            const value = vi.get(isel);
            return switch (value.flags.location_tag) {
                .small => vi.setSmallLocation(isel, .{ .stack_slot = new_slot }),
                .large => value.location_payload.large.stack_slot = new_slot,
                .extreme => unreachable,
            };
        }

        pub fn isUsed(vi: Value.Index, isel: *Select) bool {
            return vi.valueRoot(isel)[1].parent(isel) != .none or vi.hasLocationRecursive(isel);
        }

        fn hasLocationRecursive(vi: Value.Index, isel: *Select) bool {
            if (vi.location(isel) != null) return true;
            var part_it = vi.parts(isel);
            if (part_it.only() == null)
                while (part_it.next()) |part_vi|
                    if (part_vi.hasLocationRecursive(isel)) return true;
            return false;
        }

        fn setParts(vi: Value.Index, isel: *Select, parts_len: Value.PartsLen) void {
            assert(parts_len > 1);
            const value = vi.get(isel);
            assert(value.flags.parts_len_minus_one == 0);
            value.parts = @fromBackingInt(@intCast(isel.values.items.len));
            value.flags.parts_len_minus_one = @intCast(parts_len - 1);
        }

        fn addPart(vi: Value.Index, isel: *Select, part_offset: u64, part_size: u64, maybe_ty: ?ZigType) Value.Index {
            const part_vi = isel.initValueAdvanced(
                vi.alignment(isel),
                part_offset,
                part_size,
                maybe_ty,
            );
            if (maybe_ty) |ty|
                tracking_log.debug("{f} <- {f}[{d}] ({d}B, {f})", .{ part_vi, vi, part_offset, part_size, isel.fmtType(ty) })
            else
                tracking_log.debug("{f} <- {f}[{d}] ({d}B, untyped)", .{ part_vi, vi, part_offset, part_size });
            part_vi.setParent(isel, .{ .value = vi });
            return part_vi;
        }

        fn addIntPart(vi: Value.Index, isel: *Select, part_offset: u64, part_size: u64, part_bit_size: u9) !Value.Index {
            const part_vi = isel.initValueAdvanced(vi.alignment(isel), part_offset, part_size, try isel.pt.intType(.unsigned, part_bit_size));
            tracking_log.debug("{f} <- {f}[{d}] ({d}B, {d}b)", .{ part_vi, vi, part_offset, part_size, part_bit_size });
            part_vi.setParent(isel, .{ .value = vi });
            return part_vi;
        }

        pub fn parts(vi: Value.Index, isel: *Select) Value.PartIterator {
            const value = vi.get(isel);
            return switch (value.flags.parts_len_minus_one) {
                0 => .initOne(vi),
                else => |parts_len_minus_one| .{
                    .vi = value.parts,
                    .remaining = @as(Value.PartsLen, parts_len_minus_one) + 1,
                },
            };
        }

        pub fn hasParts(vi: Value.Index, isel: *Select) bool {
            return vi.get(isel).flags.parts_len_minus_one != 0;
        }

        fn partAtOffset(vi: Value.Index, isel: *Select, offset: u64) Value.Index {
            const SearchPartIndex = std.math.IntFittingRange(0, Value.max_parts * 2 - 1);
            const value = vi.get(isel);
            var last: SearchPartIndex = value.flags.parts_len_minus_one;
            if (last == 0) return vi;
            var first: SearchPartIndex = 0;
            last += 1;
            while (true) {
                const mid = (first + last) / 2;
                const mid_vi: Value.Index = @fromBackingInt(@backingInt(value.parts) + mid);
                if (mid == first) return mid_vi;
                if (offset < mid_vi.get(isel).offset_from_parent) last = mid else first = mid;
            }
        }

        fn partExact(vi: Value.Index, isel: *Select, offset: u64, part_size: u64) !Value.Index {
            try vi.split(isel, false);
            const part_vi = vi.partAtOffset(isel, offset);
            if (part_vi.offsetIn(isel, vi) != offset or part_vi.size(isel) != part_size) {
                isel.dumpValues(.all);
                tracking_log.debug("{f}.partExact({}, {}) selected {f}", .{ vi, offset, part_size, part_vi });
                unreachable;
            }
            return part_vi;
        }

        fn partExactRecursive(vi: Value.Index, isel: *Select, init_offset: u64, part_size: u64) !Value.Index {
            if (init_offset == 0 and vi.size(isel) == part_size) return vi;
            var part_vi = vi;
            var offset = init_offset;
            while (true) {
                try part_vi.split(isel, false);
                const subpart_vi = part_vi.partAtOffset(isel, offset);
                if (subpart_vi == part_vi) {
                    isel.dumpValues(.all);
                    tracking_log.debug("{f}.partExactRecursive({}, {}) selected {f}", .{ vi, init_offset, part_size, part_vi });
                    unreachable;
                }
                const subpart_offset = subpart_vi.get(isel).offset_from_parent;
                offset -= subpart_offset;
                if (offset == 0 and subpart_vi.size(isel) == part_size) return subpart_vi;
                part_vi = subpart_vi;
            }
        }

        fn partAtLargerThan(vi: Value.Index, isel: *Select, offset: u64, part_size: u64) !Value.Index {
            try vi.split(isel, false);
            const part_vi = vi.partAtOffset(isel, offset);
            if (part_vi.offsetIn(isel, vi) != offset or part_vi.size(isel) < part_size) {
                isel.dumpValues(.all);
                tracking_log.debug("{f}.partAtLargerThan({}, {}) selected {f}", .{ vi, offset, part_size, part_vi });
                unreachable;
            }
            return part_vi;
        }

        fn walk(vi: Value.Index, isel: *Select, opts: Walk.Options) Walk {
            return .{ .isel = isel, .root_vi = vi, .next_vi = vi, .opts = opts };
        }

        fn ref(initial_vi: Value.Index, isel: *Select) Value.Index {
            var vi = initial_vi;
            while (true) {
                const refs = &vi.get(isel).refs;
                refs.* += 1;
                if (refs.* > 1) return initial_vi;
                switch (vi.parent(isel)) {
                    .none, .constant => {},
                    .address, .value => |parent_vi| {
                        vi = parent_vi;
                        continue;
                    },
                }
                return initial_vi;
            }
        }

        pub fn deref(initial_vi: Value.Index, isel: *Select) void {
            var vi = initial_vi;
            while (true) {
                const refs = &vi.get(isel).refs;
                refs.* -= 1;
                if (refs.* > 0) return;
                switch (vi.parent(isel)) {
                    .none, .constant => {},
                    .address, .value => |parent_vi| {
                        vi = parent_vi;
                        continue;
                    },
                }
                return;
            }
        }

        /// Allocates a stack slot for this value, not updating the value location.
        fn allocStackSlot(vi: Value.Index, isel: *Select) Indirect {
            const offset = vi.alignment(isel).forward(isel.stack_size);
            isel.stack_size = @intCast(offset + vi.size(isel));
            tracking_log.debug("[sp, #0x{x}] -> allocated for {f}", .{ @abs(offset), vi });
            return .{
                .base = .sp,
                .offset = @intCast(offset),
            };
        }

        /// Allocates a register for this value, not updating the value location.
        fn allocRegister(vi: Value.Index, isel: *Select) !?Register.Alias {
            // Try to allocate hint register
            if (vi.hintRegister(isel)) |hint_reg| {
                const live_vi = isel.live_registers.getPtr(hint_reg);
                if (live_vi.* == .free) {
                    live_vi.* = .allocating;
                    isel.saved_registers.insert(hint_reg);
                    return .{ .reg = hint_reg, .mod = vi.hintModifier(isel) };
                }
            }
            // Try to allocate a register
            const value = vi.get(isel);
            switch (value.flags.location_tag) {
                .small => {
                    const reg_mod = vi.hintModifier(isel);
                    const reg = try isel.allocReg(reg_mod.class());
                    return .{ .reg = reg, .mod = reg_mod };
                },
                .large, .extreme => return null,
            }
        }

        fn reextend(vi: Value.Index, isel: *Select, new_ext: Extension) !void {
            if (!vi.isSmall(isel)) return;
            return vi.reextendAdvanced(isel, vi.bitSize(isel), null, new_ext);
        }

        fn reextendToGarbage(vi: Value.Index, isel: *Select) !void {
            if (!vi.isSmall(isel)) return;
            return vi.reextendAdvanced(isel, vi.bitSize(isel), null, .garbage);
        }

        fn reextendToPcs(vi: Value.Index, isel: *Select) !void {
            if (!vi.isSmall(isel)) return;
            const ty = vi.typeOf(isel) orelse unreachable; // cannot reextend ill-shaped values to PCS mode
            return vi.reextendAdvanced(isel, vi.bitSize(isel), null, .pcsMode(isel, ty));
        }

        fn reextendAdvanced(
            vi: Value.Index,
            isel: *Select,
            old_bits: u64,
            override_old_ext: ?Extension,
            new_ext: Extension,
        ) !void {
            if (vi.location(isel) == null) return;
            const value = vi.get(isel);
            const old_ext = override_old_ext orelse vi.extension(isel);
            const bit_size = vi.bitSize(isel);
            if (bit_size == 0) return;
            const vi_bits = vi.size(isel) * 8;
            const old_unused_bits = vi_bits - @min(old_bits, vi_bits);
            const new_unused_bits = vi_bits - bit_size;
            const dst_ext, const src_ext = if (bit_size == old_bits)
                .{ old_ext, new_ext }
            else if (bit_size < old_bits)
                .{ .garbage, new_ext }
            else ext_config: {
                // To cast an ABI int to a wider one, signedness of the int must be specified
                // in new_ext, so bits that are previously unused but now used can be properly
                // re-filled.
                if (old_ext != .garbage)
                    break :ext_config .{ old_ext, new_ext }
                else
                    break :ext_config .{ .zero_ext, new_ext };
            };
            const unused_bits = @max(new_unused_bits, old_unused_bits);
            if (dst_ext == src_ext and bit_size <= old_bits) return;
            tracking_log.debug("{f}: {t} ({t}) -> {t} ({t}), {d}b -> {d}b", .{ vi, src_ext, new_ext, dst_ext, old_ext, old_bits, bit_size });

            // avoid setting extension to .garbage to reduce MIR for sequences like
            // zero_ext -> garbage -> zero_ext
            if (dst_ext == .garbage) return;
            if (value.flags.location_tag == .small)
                value.location_payload.small.flags.extension = new_ext;
            if (vi_bits <= isel.gprBits()) {
                const vi_mat = try vi.mat(isel, .{ .pref = .only_reg });
                try isel.fillUnusedBits(
                    vi_mat.reg(),
                    vi_mat.reg(),
                    dst_ext,
                    src_ext,
                    @intCast(vi_mat.ra().mod.bitSize(isel.target) - vi_bits + unused_bits),
                );
                try vi_mat.finish(isel);
            } else {
                const unused_bytes = std.math.divCeil(u64, unused_bits, 8) catch unreachable;
                assert(unused_bytes <= isel.gprSize()); // TODO larger extending
                const used_bytes = vi.size(isel) - unused_bytes;

                var hit = false;
                var walker = vi.walk(isel, .{});
                while (walker.next()) |part_vi| {
                    const part_offset = part_vi.offsetIn(isel, vi);
                    const part_size = part_vi.size(isel);
                    const part_end = part_offset + part_size;
                    if (part_end <= used_bytes) continue;
                    if (part_size > isel.gprSize()) continue;

                    walker.skipChildren(part_vi);

                    const part_mat = try part_vi.mat(isel, .{ .pref = .only_reg });
                    try isel.fillUnusedBits(
                        part_mat.reg(),
                        part_mat.reg(),
                        dst_ext,
                        src_ext,
                        @intCast(unused_bits - ((vi.size(isel) - part_end) * 8)),
                    );
                    try part_mat.finish(isel);
                    if (hit) unreachable; // TODO
                    hit = true;
                }
            }
        }

        /// Defines ancestors by combining their children
        fn defChildren(def_vi: Value.Index, isel: *Select) !void {
            if (def_vi.parentValue(isel)) |parent_vi|
                try parent_vi.defChildren(isel);
            assert(def_vi.hasParts(isel));
            if (def_vi.location(isel) == null) return;
            wip_mir_log.debug("  | # merge children -> {f}", .{def_vi});
            const def_bit_size = def_vi.bitSize(isel);

            // If def_vi fits into a register, reextend def_vi
            var reextend_parts = true;
            if (def_vi.isSmall(isel)) {
                const maybe_mixed_ext = mix_ext: {
                    var maybe_mixed_ext: ?Extension = null;
                    var part_it = def_vi.parts(isel);
                    while (part_it.next()) |part_vi| {
                        const part_offset, const part_size = part_vi.positionInParent(isel);
                        if ((part_offset + part_size) * 8 > def_bit_size) {
                            if (maybe_mixed_ext) |mixed_ext|
                                maybe_mixed_ext = mixed_ext.mix(part_vi.extension(isel))
                            else
                                maybe_mixed_ext = part_vi.extension(isel);
                        }
                    }
                    break :mix_ext maybe_mixed_ext;
                };
                if (maybe_mixed_ext) |mixed_ext| {
                    try def_vi.reextend(isel, mixed_ext);
                    reextend_parts = false;
                }
            }

            const def_loc = def_vi.takeLocationMarkWritten(isel).?;
            const def_reg_lock = def_loc.tryLock(isel);
            defer def_reg_lock.unlock(isel);
            const def_ext = def_vi.extension(isel);
            var part_it = def_vi.parts(isel);
            while (part_it.next()) |part_vi| {
                const part_offset, const part_size = part_vi.positionInParent(isel);
                const part_mat = try part_vi.mat(isel, .{});
                try isel.moveLoc(def_loc, part_offset, part_mat.loc(), 0, part_size, .preserved);
                try part_mat.finish(isel);
                if (reextend_parts)
                    try part_vi.reextend(isel, def_ext);
            }
        }

        /// Defines descendants by deriving from their parents
        fn defParent(def_vi: Value.Index, isel: *Select) !void {
            if (def_vi.hasParts(isel)) {
                // DFS descendants
                var part_it = def_vi.parts(isel);
                while (part_it.next()) |part_vi| try part_vi.defParent(isel);
            }
            wip_mir_log.debug("  | # derive parent -> {f}", .{def_vi});
            const parent_vi = def_vi.parentValue(isel).?;
            try def_vi.reextendAdvanced(isel, parent_vi.bitSize(isel), null, parent_vi.extension(isel));
            const def_loc = def_vi.takeLocationMarkWritten(isel) orelse return;
            const def_offset, const def_size = def_vi.positionInParent(isel);
            const parent_mat = try parent_vi.mat(isel, .{});
            try isel.moveLoc(def_loc, 0, parent_mat.loc(), def_offset, def_size, .none);
            try parent_mat.finish(isel);
        }

        /// Defines ancestors and descendants
        fn collectDefs(vi: Value.Index, isel: *Select) !void {
            if (vi.parentValue(isel)) |parent_vi|
                try parent_vi.defChildren(isel);
            if (vi.hasParts(isel)) {
                var part_it = vi.parts(isel);
                while (part_it.next()) |part_vi| try part_vi.defParent(isel);
            }
        }

        /// Defines a value with a location.
        /// Returned location must be free-ed by caller.
        /// Extension unchanged.
        fn def(vi: Value.Index, isel: *Select) error{ AlreadyReported, OutOfMemory }!?Location {
            try vi.collectDefs(isel);
            return vi.takeLocationMarkWritten(isel);
        }

        /// Defines a value with a register.
        /// Returned registers are free-ed.
        /// Extension unchanged.
        fn defReg(vi: Value.Index, isel: *Select) !?Register.Alias {
            const value = vi.get(isel);
            assert(value.flags.location_tag == .small); // must fit into a register
            try vi.collectDefs(isel);

            const loc = vi.takeLocationMarkWritten(isel) orelse return null;
            switch (loc) {
                .register => |ra| return ra,
                .stack_slot => |stack| {
                    const reg_mod = vi.hintModifier(isel);
                    const reg = try isel.allocRegForWrite(reg_mod.class());
                    defer isel.freeReg(reg);
                    const ra: Register.Alias = .{ .mod = reg_mod, .reg = reg };
                    try isel.storeReg(reg, vi.size(isel), stack.base, stack.offset);
                    return ra;
                },
            }
        }

        /// Defines a value with a register.
        /// Returned registers are free-ed.
        /// Extension unchanged.
        fn defRegMod(vi: Value.Index, isel: *Select, mod: Register.Modifier) !?Register {
            assert(mod != .undef);
            const loc = try vi.defReg(isel) orelse return null;
            if (loc.mod == mod) return loc.reg;
            const new_reg = try isel.allocRegForWrite(mod.class());
            try isel.moveReg(
                loc,
                0,
                .{ .reg = new_reg, .mod = mod },
                0,
                @min(loc.mod.bitSize(isel.target), mod.bitSize(isel.target)),
                .none,
            );
            return new_reg;
        }

        /// Defines a value with a stack slot.
        /// Reextended in PCS mode.
        fn defStack(vi: Value.Index, isel: *Select) !?Indirect {
            try vi.reextendToPcs(isel);
            try vi.collectDefs(isel);
            const loc = vi.takeLocationMarkWritten(isel) orelse return null;
            switch (loc) {
                .register => |ra| {
                    const stack_slot = vi.allocStackSlot(isel);
                    try isel.loadReg(ra.reg, vi.size(isel), vi.extension(isel).signednessForLoad(), stack_slot.base, stack_slot.offset);
                    return stack_slot;
                },
                .stack_slot => |stack| return stack,
            }
        }

        /// Defines a value with undefined bytes.
        fn defUndef(vi: Value.Index, isel: *Select) !void {
            try vi.reextendToGarbage(isel);
            try vi.collectDefs(isel);
            const loc = vi.takeLocationMarkWritten(isel) orelse return;
            wip_mir_log.debug("  | # undef -> {f}", .{vi});
            try isel.moveUndef(loc, vi.size(isel));
        }

        /// Defines a value by loading from memory.
        /// Reextended to PCS mode.
        ///
        /// Returns true if vi has a location.
        fn defLoad(
            vi: Value.Index,
            isel: *Select,
            base_reg: Register,
            offset: u64,
            opts: MemoryAccessOptions,
        ) !bool {
            try vi.reextendToPcs(isel);
            try vi.collectDefs(isel);
            const loc = vi.takeLocationMarkWritten(isel) orelse return false;
            wip_mir_log.debug("  | # load {f} <- [${t}, #{d}] ({d}B)", .{ vi, base_reg, offset, vi.size(isel) });
            _ = opts;

            try isel.moveLoc(
                loc,
                0,
                .{ .stack_slot = .{ .base = base_reg, .offset = 0 } },
                offset,
                vi.size(isel),
                .none,
            );
            return true;
        }

        /// Defines a value by copying another value.
        /// PCS aware.
        fn defMove(dst_vi: Value.Index, isel: *Select, src_ref: Air.Inst.Ref) !void {
            try dst_vi.defCopy(isel, try isel.use(src_ref));
        }

        /// Defines a value by copying another value.
        /// PCS aware.
        fn defCopy(dst_vi: Value.Index, isel: *Select, src_vi: Value.Index) !void {
            try dst_vi.collectDefs(isel);
            wip_mir_log.debug("  | # copy {f} <- {f}", .{ dst_vi, src_vi });
            const copy_size = @min(dst_vi.size(isel), src_vi.size(isel));

            // select reextension strategy
            const ext_strat: enum { dst_to_src, src_to_dst } = ext_strat: {
                const dst_has_loc = dst_vi.location(isel) != null;
                const src_has_loc = src_vi.location(isel) != null;
                if (dst_has_loc and !src_has_loc and src_vi.isSmall(isel)) break :ext_strat .src_to_dst;
                if (src_has_loc and !dst_has_loc) break :ext_strat .dst_to_src;
                break :ext_strat .dst_to_src; // random choice
            };

            // reextend dst
            if (ext_strat == .dst_to_src) {
                try dst_vi.reextendAdvanced(
                    isel,
                    dst_vi.bitSize(isel),
                    null,
                    src_vi.extension(isel),
                );
            }

            // do copy
            {
                const loc = dst_vi.takeLocation(isel) orelse return;
                const src_mat = try src_vi.mat(isel, .{
                    .size = @intCast(copy_size),
                    .pref = switch (loc) {
                        .register => .prefer_reg,
                        .stack_slot => .prefer_stack,
                    },
                    .hint_ra = loc.asRegisterAlias() orelse .zero,
                    .hint_stack = loc.asStackSlot() orelse .unallocated,
                });
                const src_loc = src_mat.loc();
                if (!std.meta.eql(loc, src_loc)) {
                    loc.markRegWritten(isel);
                    try isel.moveLoc(loc, 0, src_mat.loc(), 0, copy_size, .none);
                }
                try src_mat.finish(isel);
            }

            // reextend src
            if (ext_strat == .src_to_dst) {
                try src_vi.reextend(isel, dst_vi.extension(isel));
            }
        }

        /// Defines a value in a certain layout, commonly used near basic block boundaries.
        /// Reextends to PCS mode.
        pub fn defLiveIn(def_vi: Value.Index, isel: *Select, layout_vi: Value.Index, opts: struct {
            /// Whether registers should be freed.
            fill_regs: bool = true,
        }) !void {
            wip_mir_log.debug("  | # live in {f}, layout={f}", .{ def_vi, layout_vi });
            assert(def_vi.size(isel) == layout_vi.size(isel));
            const gpa = isel.pt.zcu.gpa;

            var maybe_def_addr_mat: ?Value.Mat = null;
            switch (def_vi.parent(isel)) {
                .none => {},
                .value => |parent_vi| try parent_vi.defChildren(isel),
                .address => |def_addr_vi| {
                    switch (layout_vi.parent(isel)) {
                        .address => |layout_addr_vi| {
                            try def_addr_vi.defLiveIn(isel, layout_addr_vi, opts);
                        },
                        .none, .value => {
                            maybe_def_addr_mat = try def_vi.parent(isel).address.matIntRegZeroExt(isel);
                        },
                        .constant => unreachable,
                    }
                },
                .constant => unreachable,
            }

            // TODO optimize this O(n^2)
            var def_walk = def_vi.walk(isel, .{});
            while (def_walk.next()) |def_part_vi| {
                const part_offset = def_part_vi.offsetIn(isel, def_vi);
                const part_size = def_part_vi.size(isel);
                const part_end_plus1 = part_offset + part_size;

                var layout_walk = layout_vi.walk(isel, .{});
                var layout_parts: std.ArrayList(struct {
                    vi: Value.Index,
                    offset: u64,
                    end_plus1: u64,
                }) = .empty;
                defer layout_parts.deinit(gpa);
                var maybe_mixed_layout_ext: ?Extension = null;
                while (layout_walk.next()) |layout_part_vi| {
                    if (layout_part_vi.location(isel) == null and layout_part_vi.hintRegister(isel) == null) continue;
                    const layout_part_offset = layout_part_vi.offsetIn(isel, layout_vi);
                    const layout_part_size = layout_part_vi.size(isel);
                    const layout_part_end_plus1 = layout_part_offset + layout_part_size;
                    if (layout_part_end_plus1 <= part_offset or
                        layout_part_offset >= part_end_plus1) continue;

                    try layout_parts.append(gpa, .{
                        .vi = layout_part_vi,
                        .offset = layout_part_offset,
                        .end_plus1 = layout_part_end_plus1,
                    });

                    const layout_part_ext = layout_part_vi.extension(isel);
                    if (maybe_mixed_layout_ext) |mixed_layout_ext| {
                        maybe_mixed_layout_ext = mixed_layout_ext.mix(layout_part_ext);
                    } else {
                        maybe_mixed_layout_ext = layout_part_ext;
                    }
                }
                if (maybe_mixed_layout_ext) |mixed_layout_ext| {
                    try def_part_vi.reextend(isel, mixed_layout_ext);
                } else unreachable;

                const def_part_loc = if (maybe_def_addr_mat == null or def_part_vi != def_vi) def_part_loc: {
                    break :def_part_loc def_part_vi.takeLocationMarkWritten(isel) orelse continue;
                } else def_part_loc: {
                    break :def_part_loc maybe_def_addr_mat.?.loc();
                };
                const def_part_lock = def_part_loc.tryLock(isel);
                defer def_part_lock.unlock(isel);

                for (layout_parts.items) |layout_part| {
                    const dst_offset = layout_part.offset -| part_offset;
                    const src_offset = part_offset -| layout_part.offset;

                    const mat_size = @min(part_end_plus1, layout_part.end_plus1) - @max(part_offset, layout_part.offset);
                    assert(mat_size != 0);
                    const src_loc: Location = if (layout_part.vi.location(isel)) |loc|
                        loc
                    else if (layout_part.vi.hintRegisterAlias(isel)) |hint_ra|
                        .{ .register = hint_ra }
                    else
                        unreachable;
                    if (opts.fill_regs) {
                        if (src_loc.asRegister()) |src_reg|
                            _ = try isel.fillReg(src_reg);
                    }
                    // TODO: replace reextending def_part_vi to .zero_ext with moveLoc .wipe when applicable
                    try isel.moveLoc(def_part_loc, dst_offset, src_loc, src_offset, mat_size, .preserved);
                }
            }
            if (maybe_def_addr_mat) |def_addr_mat| try def_addr_mat.finish(isel);
        }

        const MemoryAccessOptions = struct {
            // TODO unimplemented, remove?
            @"volatile": bool = false,
        };

        const MatOptions = struct {
            /// Offset of materialized part
            offset: u64 = 0,
            /// Size, coerced to [0, part size - offset]
            size: u32 = std.math.maxInt(u32),
            /// Location preference
            pref: LocPreference = .none,
            reg_mod: Register.Modifier = .undef,
            /// Expected extension mode
            extension: Extension = .garbage,
            hint_ra: Register.Alias = .zero,
            hint_stack: Indirect = .unallocated,

            const LocPreference = enum {
                none,
                /// Loads value to a register if possible, otherwise returns a stack slot
                prefer_reg,
                /// Loads value to a register, asserts the value fitting into a register
                only_reg,
                /// If there isn't an exisiting location, allocate a stack slot
                prefer_stack,
                /// Stores value to a stack slot
                only_stack,
            };
        };

        /// Materializes a value
        fn mat(vi: Value.Index, isel: *Select, opts: MatOptions) Mat.Error!Mat {
            // try vi.split(isel, true);
            const mat_size = @min(opts.size, @as(u32, @intCast(vi.size(isel) - opts.offset)));
            const loc_pref = if (opts.extension == .garbage)
                opts.pref
            else switch (opts.pref) {
                .none, .prefer_reg, .prefer_stack => .prefer_reg,
                .only_reg, .only_stack => |loc_pref| loc_pref,
            };
            var maybe_prev_loc: ?Location = null;
            const loc: Location, var full = loc: {
                // Try to reuse existing location
                if (vi.location(isel)) |loc| {
                    maybe_prev_loc = loc;
                    switch (loc) {
                        .register => |loc_ra| if (opts.offset == 0 and (opts.reg_mod == .undef or opts.reg_mod == loc_ra.mod)) {
                            switch (loc_pref) {
                                .none, .prefer_reg, .only_reg, .prefer_stack => break :loc .{ loc, false },
                                .only_stack => {},
                            }
                        },
                        .stack_slot => switch (loc_pref) {
                            .none, .prefer_stack, .only_stack => break :loc .{ loc, true },
                            .prefer_reg, .only_reg => {},
                        },
                    }
                }
                if (loc_pref != .only_stack and loc_pref != .prefer_stack) {
                    // Try to allocate hint RA
                    if (opts.hint_ra.reg != Register.zero) {
                        if (isel.live_registers.get(opts.hint_ra.reg) == .free) {
                            isel.saved_registers.insert(opts.hint_ra.reg);
                            break :loc .{ .{ .register = opts.hint_ra }, false };
                        }
                    }
                    // Try to allocate a register
                    if (opts.reg_mod == .undef or opts.reg_mod == vi.hintModifier(isel)) {
                        if (try vi.allocRegister(isel)) |ra|
                            break :loc .{ .{ .register = ra }, false };
                    } else try_alloc: {
                        const reg = isel.allocReg(opts.reg_mod.class()) catch break :try_alloc;
                        break :loc .{ .{ .register = .{ .reg = reg, .mod = opts.reg_mod } }, false };
                    }
                }
                // Use existing stack slot if cannot mat into regs
                switch (loc_pref) {
                    .none, .prefer_stack, .only_stack => {},
                    .prefer_reg => if (maybe_prev_loc) |loc| break :loc .{ loc, true },
                    .only_reg => unreachable, // too large to fit in registers
                }
                // Use hint stack slot
                if (false) {
                    // TODO needs stack slot tracking
                    if (opts.hint_stack != .unallocated) {
                        break :loc .{ .{ .stack_slot = opts.hint_stack }, false };
                    }
                }
                // Allocate on stack
                break :loc .{ .{ .stack_slot = vi.allocStackSlot(isel) }, true };
            };
            if (maybe_prev_loc) |prev_loc| {
                if (std.meta.eql(loc, prev_loc)) {
                    if (opts.extension != .garbage) {
                        try vi.reextendAdvanced(isel, vi.bitSize(isel), null, opts.extension);
                    }
                    _ = vi.takeLocation(isel);
                }
            }
            if (loc.asRegister()) |reg| {
                const live_vi = isel.live_registers.getPtr(reg);
                switch (live_vi.*) {
                    _ => unreachable,
                    .allocating => {},
                    .free => live_vi.* = .allocating,
                }
                full = opts.offset == 0 and mat_size == vi.size(isel);
            }
            if (full) {
                tracking_log.debug("{f}[{d}..{d}] -> {f}[...] (mat, {t})", .{ vi, opts.offset, opts.offset + mat_size - 1, loc, opts.extension });
            } else {
                tracking_log.debug("{f}[{d}..{d}] -> {f} (mat, {t})", .{ vi, opts.offset, opts.offset + mat_size - 1, loc, opts.extension });
            }
            return .{
                .vi = vi,
                .location = loc,
                .offset = opts.offset,
                .size = mat_size,
                .extension = opts.extension,
                .full = full,
            };
        }

        fn matReg(vi: Value.Index, isel: *Select) !Mat {
            return vi.mat(isel, .{ .pref = .only_reg });
        }

        fn matRegMod(vi: Value.Index, isel: *Select, mod: Register.Modifier) !Mat {
            return vi.mat(isel, .{ .pref = .only_reg, .reg_mod = mod });
        }

        fn matIntRegZeroExt(vi: Value.Index, isel: *Select) !Mat {
            return vi.mat(isel, .{
                .pref = .only_reg,
                .reg_mod = .integer,
                .extension = .zero_ext,
            });
        }

        /// Moves the address of vi, plus offset, to ptr_reg
        fn matAddress(vi: Value.Index, isel: *Select, ptr_reg: Register, offset: u64) !void {
            wip_mir_log.debug("  | # address ${t} <- (&{f} + {d})", .{ ptr_reg, vi, offset });
            const offset_from_root, const root_vi = vi.valueRoot(isel);
            const total_root_offset = offset_from_root + offset;
            switch (root_vi.parent(isel)) {
                .none => {
                    const value_mat = try vi.mat(isel, .{ .pref = .only_stack });
                    const value_stack = value_mat.loc().stack_slot;
                    try isel.addImm(ptr_reg, value_stack.base, @as(i65, value_stack.offset) + offset);
                    try value_mat.finish(isel);
                },
                .address => |addr_vi| {
                    const addr_mat = try addr_vi.mat(isel, .{
                        .pref = .only_reg,
                        .hint_ra = .{ .mod = .integer, .reg = ptr_reg },
                    });
                    try isel.addImm(ptr_reg, addr_mat.reg(), total_root_offset);
                    try addr_mat.finish(isel);
                },
                .value => unreachable,
                .constant => |constant| {
                    const pt = isel.pt;
                    const zcu = pt.zcu;

                    try isel.uav_relocs.append(zcu.gpa, .{
                        .uav = .{
                            .val = constant.toIntern(),
                            .orig_ty = (try pt.singleConstPtrType(constant.typeOf(zcu))).toIntern(),
                        },
                        .reloc = .{
                            .label = @intCast(isel.instructions.items.len),
                            .addend = @intCast(total_root_offset),
                        },
                    });
                    try isel.emit(.@"addi.d"(ptr_reg, ptr_reg, 0));
                    try isel.uav_relocs.append(zcu.gpa, .{
                        .uav = .{
                            .val = constant.toIntern(),
                            .orig_ty = (try pt.singleConstPtrType(constant.typeOf(zcu))).toIntern(),
                        },
                        .reloc = .{
                            .label = @intCast(isel.instructions.items.len),
                            .addend = @intCast(total_root_offset),
                        },
                    });
                    try isel.emit(.pcalau12i(ptr_reg, 0));
                },
            }
        }

        /// Stores a value to memory.
        fn matStore(
            vi: Value.Index,
            isel: *Select,
            base_reg: Register,
            offset: u64,
            opts: MemoryAccessOptions,
        ) !void {
            wip_mir_log.debug("  | # store {f} -> [${t}, #{d}]", .{ vi, base_reg, offset });
            _ = opts;

            const hint_stack: Indirect = if (std.math.cast(@FieldType(Indirect, "offset"), offset)) |stack_off|
                .{ .base = base_reg, .offset = stack_off }
            else
                .unallocated;
            const value_mat = try vi.mat(isel, .{ .hint_stack = hint_stack });
            try isel.moveLoc(
                .{ .stack_slot = .{ .base = base_reg, .offset = 0 } },
                offset,
                value_mat.loc(),
                0,
                vi.size(isel),
                .none,
            );
            try value_mat.finish(isel);
        }

        /// Stores a value in a certain layout, commonly used near basic block boundaries.
        /// Reextends to PCS mode.
        fn matLiveOut(
            vi: Value.Index,
            isel: *Select,
            layout_vi: Value.Index,
            opts: struct {
                mode: enum { param, ret },
            },
        ) !void {
            wip_mir_log.debug("  | # live out {f}, layout={f}, opts: regs={t}", .{ vi, layout_vi, opts.mode });

            wip_mir_log.debug("  | # live out {f}: fill registers", .{vi});
            switch (opts.mode) {
                .param => {
                    var layout_walk = layout_vi.walk(isel, .{});
                    while (layout_walk.next()) |part_vi| {
                        if (part_vi.hintRegister(isel)) |part_reg| {
                            _ = try isel.fillReg(part_reg);
                        }
                    }
                },
                .ret => {
                    var layout_walk = layout_vi.walk(isel, .{});
                    while (layout_walk.next()) |part_vi| {
                        if (part_vi.hintRegister(isel)) |part_reg| {
                            assert(try isel.forgetReg(part_reg));
                            _ = isel.lockReg(part_reg);
                        }
                    }
                },
            }

            wip_mir_log.debug("  | # live out {f}: move values", .{vi});
            var layout_walk = layout_vi.walk(isel, .{});
            while (layout_walk.next()) |part_vi| {
                if (part_vi.hintRegisterAlias(isel)) |part_ra| {
                    const part_offset = part_vi.offsetIn(isel, layout_vi);
                    const part_size = part_vi.size(isel);

                    if (opts.mode == .ret) isel.freeReg(part_ra.reg);
                    const value_mat = try vi.mat(isel, .{
                        .hint_ra = part_ra,
                        .offset = part_offset,
                        .size = @intCast(part_size),
                        .extension = part_vi.extension(isel),
                    });
                    try isel.moveLoc(.{ .register = part_ra }, 0, value_mat.loc(), 0, part_size, .none);
                    try value_mat.finish(isel);
                }

                if (part_vi.location(isel)) |layout_part_loc| {
                    const layout_part_stack = layout_part_loc.asStackSlot().?;
                    const part_offset = part_vi.offsetIn(isel, layout_vi);
                    const part_size = part_vi.size(isel);

                    const value_mat = try vi.mat(isel, .{
                        .hint_stack = layout_part_stack,
                        .offset = part_offset,
                        .size = @intCast(part_size),
                        .extension = part_vi.extension(isel),
                    });
                    try isel.moveLoc(.{ .stack_slot = layout_part_stack }, 0, value_mat.loc(), 0, part_size, .none);
                    try value_mat.finish(isel);
                }
            }
        }

        /// Moves the expected location to another location.
        fn moveTo(vi: Value.Index, isel: *Select, src_loc: Location) !void {
            if (src_loc.asRegister()) |src_reg| _ = try isel.fillReg(src_reg);
            tracking_log.debug("{f} -> {f} (move to)", .{ vi, src_loc });
            if (vi.takeLocationMarkWritten(isel)) |dst_loc|
                try isel.moveLoc(dst_loc, 0, src_loc, 0, vi.size(isel), .none);
            if (vi.isSmall(isel)) {
                vi.setSmallLocation(isel, src_loc);
                if (src_loc.asRegister()) |src_reg| {
                    const src_live_vi = isel.live_registers.getPtr(src_reg);
                    assert(src_live_vi.* == .free);
                    src_live_vi.* = vi;
                }
            } else {
                switch (src_loc) {
                    .register => unreachable, // large values cannot be moved into a register
                    .stack_slot => |src_stack| vi.setStackSlot(isel, src_stack),
                }
            }
        }

        pub fn isSplitted(vi: Value.Index, isel: *Select) bool {
            const value = vi.get(isel);
            return value.flags.parts_len_minus_one != 0 or value.flags.splitted;
        }

        pub fn split(vi: Value.Index, isel: *Select, force: bool) !void {
            const zcu = isel.pt.zcu;
            const ip = &zcu.intern_pool;

            const value1 = vi.get(isel);
            if (value1.flags.splitted and !force) return;
            value1.flags.splitted = true;
            if (value1.flags.parts_len_minus_one != 0) return;
            var ty = vi.typeOf(isel) orelse {
                if (force)
                    return vi.splitBlindly(isel)
                else
                    return;
            };

            try isel.values.ensureUnusedCapacity(zcu.gpa, Value.max_parts);
            try isel.value_types.ensureUnusedCapacity(zcu.gpa, Value.max_parts);
            const value = vi.get(isel);
            type_key: switch (ip.indexToKey(ty.toIntern())) {
                else => return isel.fail("unimplemented Value.split({f})", .{isel.fmtType(ty)}),
                .int_type => |int_type| {
                    const gpr_size = isel.gprSize();
                    const gpr_bits = isel.gprBits();
                    const parts_len = std.math.divCeil(u16, int_type.bits, gpr_bits) catch unreachable;
                    if (parts_len == 1) break :type_key;
                    vi.setParts(isel, @intCast(parts_len));
                    for (0..parts_len) |part_index|
                        _ = try vi.addIntPart(
                            isel,
                            part_index * gpr_size,
                            gpr_size,
                            @intCast(@min(int_type.bits - (part_index * gpr_bits), gpr_bits)),
                        );
                },
                .ptr_type => |ptr_type| switch (ptr_type.flags.size) {
                    .one, .many, .c => break :type_key,
                    .slice => {
                        const ptr_size = isel.gprSize();
                        vi.setParts(isel, 2);
                        _ = vi.addPart(isel, 0, ptr_size, ty.slicePtrFieldType(zcu));
                        _ = vi.addPart(isel, ptr_size, ptr_size, .usize);
                    },
                },
                .opt_type => |child_type| if (ty.optionalReprIsPayload(zcu)) {
                    ty = .fromInterned(child_type);
                    continue :type_key ip.indexToKey(child_type);
                } else {
                    const child_ty: ZigType = .fromInterned(child_type);
                    const child_size = child_ty.abiSize(zcu);
                    vi.setParts(isel, 2);
                    _ = vi.addPart(isel, 0, child_size, child_ty);
                    _ = vi.addPart(isel, child_size, 1, .bool);
                },
                .array_type => |array_type| {
                    const full_len = array_type.lenIncludingSentinel();
                    const child_ty: ZigType = .fromInterned(array_type.child);
                    const child_size = child_ty.abiSize(zcu);
                    const aligned_size = child_ty.abiAlignment(zcu).forward(child_size);
                    if (full_len == 1) {
                        continue :type_key ip.indexToKey(child_ty.ip_index);
                    } else if (full_len <= Value.max_parts) {
                        vi.setParts(isel, @intCast(full_len));
                        for (0..@intCast(full_len)) |part_i| {
                            _ = vi.addPart(
                                isel,
                                @intCast(part_i * aligned_size),
                                child_size,
                                child_ty,
                            );
                        }
                    } else {
                        // Construct a tree with minimum nodes and depth
                        // Minimum number of direct/indirect intermediate nodes to contain full_len leaf nodes
                        const min_intermediate_nodes = (std.math.divCeil(u64, full_len - 1, Value.max_parts - 1) catch unreachable) - 1;
                        assert(min_intermediate_nodes >= 1);
                        // Number of direct intermediate children
                        const intermediate_children = @min(Value.max_parts, min_intermediate_nodes);
                        // Number of direct leaf children
                        const leaf_children = @as(u64, Value.max_parts) - intermediate_children;
                        // Number of indirect leaf children
                        const indirect_leaf_children = full_len - leaf_children;
                        // Length of each intermediate children
                        const group_len = indirect_leaf_children / intermediate_children;
                        const group_tail = indirect_leaf_children % intermediate_children;
                        const tail_group_len = group_len + group_tail;
                        const group_size = group_len * child_size;
                        const tail_group_size = tail_group_len * child_size;
                        const group_aligned_size = group_len * aligned_size;
                        const group_ty: ZigType = if (intermediate_children == 1) undefined else try isel.pt.arrayType(.{
                            .child = child_ty.ip_index,
                            .len = group_len,
                        });
                        const tail_group_ty = if (array_type.sentinel == .none) try isel.pt.arrayType(.{
                            .child = child_ty.ip_index,
                            .len = tail_group_len,
                        }) else try isel.pt.arrayType(.{
                            .child = child_ty.ip_index,
                            .len = tail_group_len - 1,
                            .sentinel = array_type.sentinel,
                        });

                        vi.setParts(isel, Value.max_parts);
                        for (0..@intCast(leaf_children)) |part_i| {
                            _ = vi.addPart(
                                isel,
                                @intCast(part_i * aligned_size),
                                child_size,
                                child_ty,
                            );
                        }
                        const leaf_offset = leaf_children * aligned_size;
                        for (0..@intCast(intermediate_children - 1)) |part_i| {
                            _ = vi.addPart(
                                isel,
                                @intCast(leaf_offset + (part_i * group_aligned_size)),
                                group_size,
                                group_ty,
                            );
                        }
                        _ = vi.addPart(
                            isel,
                            @intCast(leaf_offset + ((intermediate_children - 1) * group_aligned_size)),
                            tail_group_size,
                            tail_group_ty,
                        );
                    }
                },
                .anyframe_type => unreachable,
                .error_union_type => |error_union_type| {
                    const payload_ty: ZigType = .fromInterned(error_union_type.payload_type);
                    const error_set_offset = codegen.errUnionErrorOffset(payload_ty, zcu);
                    const payload_offset = codegen.errUnionPayloadOffset(payload_ty, zcu);

                    var fields: [2]SplitStructField = undefined;
                    var part_len: usize = 0;
                    for (0..2) |field_index| {
                        const field_name: enum { error_set, payload } = switch (field_index) {
                            0 => if (error_set_offset < payload_offset) .error_set else .payload,
                            1 => if (error_set_offset < payload_offset) .payload else .error_set,
                            else => unreachable,
                        };
                        const field_ty: ZigType, const field_begin = switch (field_name) {
                            .error_set => .{ .fromInterned(error_union_type.error_set_type), error_set_offset },
                            .payload => .{ payload_ty, payload_offset },
                        };
                        const field_size = field_ty.abiSize(zcu);
                        if (field_size == 0) continue;

                        fields[part_len] = .{ .offset = field_begin, .size = field_size };
                        part_len += 1;
                    }

                    try vi.splitStruct(isel, fields[0..part_len], .{
                        .ty_size = vi.size(isel),
                        .ty_alignment = vi.alignment(isel),
                        .combine = false,
                    });
                },
                .simple_type => |simple_type| switch (simple_type) {
                    .f16, .f32, .f64, .f128, .c_longdouble => return isel.fail("Value.FieldPartIterator.next({f})", .{isel.fmtType(ty)}),
                    .f80 => continue :type_key .{ .int_type = .{ .signedness = .unsigned, .bits = 80 } },
                    .usize,
                    .isize,
                    .c_char,
                    .c_short,
                    .c_ushort,
                    .c_int,
                    .c_uint,
                    .c_long,
                    .c_ulong,
                    .c_longlong,
                    .c_ulonglong,
                    => continue :type_key .{ .int_type = ty.intInfo(zcu) },
                    .anyopaque,
                    .void,
                    .type,
                    .comptime_int,
                    .comptime_float,
                    .noreturn,
                    .null,
                    .undefined,
                    .enum_literal,
                    .adhoc_inferred_error_set,
                    .generic_poison,
                    => unreachable,
                    .bool => continue :type_key .{ .int_type = .{ .signedness = .unsigned, .bits = 1 } },
                    .anyerror => continue :type_key .{ .int_type = .{
                        .signedness = .unsigned,
                        .bits = zcu.errorSetBits(),
                    } },
                },
                .struct_type => {
                    const loaded_struct = ip.loadStructType(ty.toIntern());
                    switch (loaded_struct.layout) {
                        .auto, .@"extern" => {},
                        .@"packed" => {
                            ty = .fromInterned(loaded_struct.packed_backing_int_type);
                            continue :type_key ip.indexToKey(loaded_struct.packed_backing_int_type);
                        },
                    }

                    var field_end: u64 = 0;
                    var field_it = loaded_struct.iterateRuntimeOrder(ip);
                    var fields: []SplitStructField = try zcu.gpa.alloc(SplitStructField, loaded_struct.field_types.len);
                    defer zcu.gpa.free(fields);
                    var part_len: usize = 0;
                    while (field_it.next()) |field_index| {
                        const field_ty: ZigType = .fromInterned(loaded_struct.field_types.get(ip)[field_index]);
                        const field_begin = switch (loaded_struct.field_aligns.getOrNone(ip, field_index)) {
                            .none => field_ty.abiAlignment(zcu),
                            else => |field_align| field_align,
                        }.forward(field_end);
                        const field_size = field_ty.abiSize(zcu);
                        if (field_size == 0) continue;
                        field_end = field_begin + field_size;

                        fields[part_len] = .{ .offset = field_begin, .size = field_size, .ty = field_ty };
                        part_len += 1;
                    }

                    try vi.splitStruct(isel, fields[0..part_len], .{
                        .ty_size = vi.size(isel),
                        .ty_alignment = vi.alignment(isel),
                        .combine = true,
                    });
                },
                .tuple_type => |tuple_type| {
                    var field_end: u64 = 0;
                    var fields: []SplitStructField = try zcu.gpa.alloc(SplitStructField, tuple_type.types.len);
                    defer zcu.gpa.free(fields);
                    var part_len: usize = 0;

                    for (tuple_type.types.get(ip), tuple_type.values.get(ip)) |field_type, field_value| {
                        if (field_value != .none) continue;
                        const field_ty: ZigType = .fromInterned(field_type);
                        const field_begin = field_ty.abiAlignment(zcu).forward(field_end);
                        const field_size = field_ty.abiSize(zcu);
                        if (field_size == 0) continue;
                        field_end = field_begin + field_size;

                        fields[part_len] = .{ .offset = field_begin, .size = field_size, .ty = field_ty };
                        part_len += 1;
                    }

                    try vi.splitStruct(isel, fields[0..part_len], .{
                        .ty_size = vi.size(isel),
                        .ty_alignment = vi.alignment(isel),
                        .combine = true,
                    });
                },
                .union_type => {
                    const loaded_union = ip.loadUnionType(ty.toIntern());
                    switch (loaded_union.layout) {
                        .auto, .@"extern" => {},
                        .@"packed" => continue :type_key .{ .int_type = .{
                            .signedness = .unsigned,
                            .bits = @intCast(ty.bitSize(zcu)),
                        } },
                    }

                    const union_layout = ZigType.getUnionLayout(loaded_union, zcu);
                    const tag_offset = union_layout.tagOffset();
                    const payload_offset = union_layout.payloadOffset();

                    var field_end: u64 = 0;
                    var fields: [2]SplitStructField = undefined;
                    var part_len: usize = 0;

                    for (0..2) |field_index| {
                        const field_name: enum { tag, payload } = switch (field_index) {
                            0 => if (tag_offset < payload_offset) .tag else .payload,
                            1 => if (tag_offset < payload_offset) .payload else .tag,
                            else => unreachable,
                        };
                        const field_size, const field_begin = switch (field_name) {
                            .tag => .{ union_layout.tag_size, tag_offset },
                            .payload => .{ union_layout.payload_size, payload_offset },
                        };
                        if (field_size == 0) continue;
                        field_end = field_begin + field_size;

                        fields[part_len] = .{ .offset = field_begin, .size = field_size };
                        part_len += 1;
                    }

                    try vi.splitStruct(isel, fields[0..part_len], .{
                        .ty_size = vi.size(isel),
                        .ty_alignment = vi.alignment(isel),
                        .combine = false,
                    });
                },
                .opaque_type, .func_type => continue :type_key .{ .simple_type = .anyopaque },
                .enum_type => continue :type_key ip.indexToKey(ip.loadEnumType(ty.toIntern()).int_tag_type),
                .error_set_type,
                .inferred_error_set_type,
                => continue :type_key .{ .simple_type = .anyerror },
            }

            if (force and value.flags.parts_len_minus_one == 0) try vi.splitBlindly(isel);
        }

        pub fn splitBlindly(vi: Value.Index, isel: *Select) !void {
            const value = vi.get(isel);
            value.flags.splitted = true;
            if (value.flags.parts_len_minus_one != 0) return;

            return isel.fail("splitBlindly unimplemented", .{});
        }

        const SplitStructField = struct {
            offset: u64,
            size: u64,
            ty: ZigType = .void,
        };

        const SplitStructOpts = struct {
            ty_size: u64,
            ty_alignment: InternPool.Alignment,
            combine: bool,
        };

        fn splitStruct(vi: Value.Index, isel: *Select, fields: []SplitStructField, opts: SplitStructOpts) !void {
            const min_part_log2_stride: u5 = switch (opts.ty_size) {
                0...4 => 0,
                5...8 => 2,
                9...16 => 3,
                else => 4,
            };
            if (fields.len > Value.max_parts and
                (std.math.divCeil(u64, opts.ty_size, @as(u64, 1) << min_part_log2_stride) catch unreachable) > Value.max_parts)
            {
                // fast path for structs with too many parts
                return;
            }

            // split parts with combination
            const Part = struct {
                offset: u64,
                size: u64,
                ty: ZigType,
                vi: Value.Index,
                subparts: Value.PartsLen,
            };
            var new_parts: [Value.max_parts]Part = undefined;
            var parts_len: Value.PartsLen = 0;
            var field_end: u64 = 0;
            for (fields) |*struct_field| {
                const field_ty = struct_field.ty;
                const field_begin = struct_field.offset;
                const field_size = struct_field.size;
                field_end = field_begin + field_size;
                if (opts.combine and parts_len > 0) combine: {
                    const prev_part = &new_parts[parts_len - 1];
                    const combined_size = field_end - prev_part.offset;
                    if (combined_size > @as(u64, 1) << @min(
                        min_part_log2_stride,
                        opts.ty_alignment.toLog2Units(),
                        @ctz(prev_part.offset),
                    )) break :combine;
                    prev_part.size = combined_size;
                    prev_part.ty = undefined;
                    prev_part.subparts += 1;
                    continue;
                }
                if (parts_len == Value.max_parts) return;
                new_parts[parts_len] = .{
                    .offset = field_begin,
                    .size = field_size,
                    .ty = field_ty,
                    .vi = undefined,
                    .subparts = 1,
                };
                parts_len += 1;
            }
            if (parts_len <= 1) return;
            vi.setParts(isel, parts_len);
            for (new_parts[0..parts_len]) |*part| {
                part.vi = vi.addPart(
                    isel,
                    part.offset,
                    part.size,
                    if (part.subparts == 1 and part.ty.ip_index != .void_type) part.ty else null,
                );
            }
            const last_part = new_parts[parts_len - 1];
            const remaining_size = opts.ty_size - last_part.offset - last_part.size;
            if (remaining_size != 0)
                _ = vi.addPart(isel, last_part.offset, remaining_size, null);

            // split combined parts
            var part_index: Value.PartsLen = 0;
            for (fields) |*struct_field| {
                const field_ty = struct_field.ty;
                const field_begin = struct_field.offset;
                const field_size = struct_field.size;

                var new_part = &new_parts[part_index];
                while (new_part.offset + new_part.size <= field_begin) {
                    part_index += 1;
                    new_part = &new_parts[part_index];
                }
                if (new_part.subparts == 1) continue;
                if (!new_part.vi.hasParts(isel))
                    new_part.vi.setParts(isel, new_part.subparts);
                _ = new_part.vi.addPart(
                    isel,
                    field_begin - new_part.offset,
                    field_size,
                    if (field_ty.ip_index != .void_type) field_ty else null,
                );
            }
        }
    };

    pub const PartIterator = struct {
        vi: Value.Index,
        remaining: Value.PartsLen,

        fn initOne(vi: Value.Index) PartIterator {
            return .{ .vi = vi, .remaining = 1 };
        }

        pub fn next(it: *PartIterator) ?Value.Index {
            if (it.remaining == 0) return null;
            it.remaining -= 1;
            defer it.vi = @fromBackingInt(@backingInt(it.vi) + 1);
            return it.vi;
        }

        pub fn peek(it: PartIterator) ?Value.Index {
            var it_mut = it;
            return it_mut.next();
        }

        pub fn only(it: PartIterator) ?Value.Index {
            return if (it.remaining == 1) it.vi else null;
        }
    };

    const Mat = struct {
        vi: Value.Index,
        /// Position of the materialized part
        offset: u64,
        /// Size of the materialized part
        size: u32,
        /// Expected live-in extension mode
        extension: Extension,
        /// Register are locked.
        location: Location,
        /// Whether the location stores the whole value or the materialized part
        full: bool,

        comptime {
            if (!std.debug.runtime_safety) assert(@sizeOf(Mat) <= 32);
        }

        const Error = error{ OutOfMemory, AlreadyReported };

        pub fn ra(mat: Value.Mat) Register.Alias {
            return mat.location.register;
        }

        pub fn reg(mat: Value.Mat) Register {
            return mat.location.register.reg;
        }

        pub fn loc(mat: Value.Mat) Location {
            return switch (mat.location) {
                .register => |loc_ra| .{ .register = loc_ra },
                .stack_slot => |stack_slot| if (mat.full)
                    .{ .stack_slot = stack_slot.withOffset(@intCast(mat.offset)) }
                else
                    .{ .stack_slot = stack_slot },
            };
        }

        fn finish(mat: Value.Mat, isel: *Select) Mat.Error!void {
            const vi = mat.vi;
            const value = vi.get(isel);
            tracking_log.debug("{f}[{d}..{d}] <- {f} (mat finish)", .{ vi, mat.offset, mat.offset + mat.size - 1, mat.loc() });

            if (mat.location.asRegister()) |mat_reg|
                isel.freeReg(mat_reg);

            const offset_from_root, const root_vi = vi.valueRoot(isel);
            switch (root_vi.parent(isel)) {
                .none => {
                    // Try to set the location as expected
                    if (mat.full and vi.location(isel) == null) {
                        switch (value.flags.location_tag) {
                            .extreme => unreachable,
                            .small => {
                                vi.setSmallLocation(isel, mat.location);
                                vi.setExtension(isel, mat.extension);
                                if (mat.location.asRegister()) |loc_reg|
                                    isel.live_registers.set(loc_reg, vi);
                                return;
                            },
                            .large => switch (mat.location) {
                                .stack_slot => |stack_slot| {
                                    value.location_payload.large.stack_slot = stack_slot;
                                    try vi.reextendAdvanced(isel, vi.bitSize(isel), mat.extension, vi.extension(isel));
                                    return;
                                },
                                else => {},
                            },
                        }
                    }

                    // Initialize a location and copy
                    if (vi.location(isel) == null) {
                        switch (value.flags.location_tag) {
                            .extreme => unreachable,
                            .small => {
                                const new_ra = (try vi.allocRegister(isel)).?;
                                vi.setSmallLocation(isel, .{ .register = new_ra });
                                isel.live_registers.set(new_ra.reg, vi);
                            },
                            .large => value.location_payload.large.stack_slot = vi.allocStackSlot(isel),
                        }
                    }
                    switch (value.flags.location_tag) {
                        .extreme => unreachable,
                        .small => {},
                        .large => {
                            try vi.reextendAdvanced(isel, vi.bitSize(isel), mat.extension, vi.extension(isel));
                        },
                    }
                    const vi_loc = vi.location(isel).?;
                    const maybe_loc_reg = vi_loc.asRegister();
                    if (maybe_loc_reg) |loc_reg| {
                        const loc_live = isel.live_registers.getPtr(loc_reg);
                        assert(loc_live.* == vi);
                        loc_live.* = .allocating;
                    }
                    vi_loc.markRegWritten(isel);
                    try isel.moveLoc(
                        mat.location,
                        if (mat.full) mat.offset else 0,
                        vi_loc,
                        mat.offset,
                        mat.size,
                        .preserved,
                    );
                    if (maybe_loc_reg) |loc_reg| {
                        const loc_live = isel.live_registers.getPtr(loc_reg);
                        assert(loc_live.* == .allocating);
                        loc_live.* = vi;
                    }
                },
                .value => unreachable,
                .address => |addr_vi| {
                    try vi.reextendAdvanced(isel, vi.bitSize(isel), mat.extension, vi.extension(isel));

                    // reextend
                    reextend: {
                        const dst_ext = vi.extension(isel);
                        const src_ext = mat.extension;
                        if (dst_ext == src_ext or dst_ext == .garbage) break :reextend;

                        const bit_size = vi.bitSize(isel);
                        if (bit_size == 0) break :reextend;

                        switch (mat.location) {
                            .register => |loc_ra| {
                                const offset_fixup = if (mat.full) 0 else mat.offset;
                                const reg_bits = loc_ra.mod.bitSize(isel.target);
                                const unused_bits = reg_bits - @min(bit_size - (offset_fixup * 8), reg_bits);
                                try isel.fillUnusedBits(loc_ra.reg, loc_ra.reg, dst_ext, src_ext, @intCast(unused_bits));
                            },
                            .stack_slot => |stack| {
                                const total_size = vi.size(isel);
                                const unused_bits = (total_size * 8) - bit_size;
                                const reg_mod: Register.Modifier = if (vi.isSmall(isel)) vi.hintModifier(isel) else .integer;
                                const reg_class = reg_mod.class();
                                const reg_size = reg_mod.byteSize(isel.target);
                                const reg_alignment: InternPool.Alignment = .fromByteUnits(reg_size);
                                const base_offset = @as(i65, stack.offset) - (if (mat.full) 0 else mat.offset);

                                var offset = reg_alignment.backward(bit_size / 8);
                                const tmp_reg = try isel.allocRegForWrite(reg_class);
                                defer isel.freeReg(tmp_reg);
                                while (offset < total_size) {
                                    const part_size = @min(reg_size, total_size - offset);
                                    defer offset += part_size;

                                    try isel.storeReg(tmp_reg, part_size, stack.base, base_offset + offset);
                                    try isel.fillUnusedBits(tmp_reg, tmp_reg, dst_ext, src_ext, @intCast(unused_bits));
                                    try isel.loadReg(tmp_reg, part_size, vi.extension(isel).signednessForLoad(), stack.base, base_offset + offset);
                                }
                            },
                        }
                    }

                    const addr_mat = try addr_vi.matIntRegZeroExt(isel);
                    assert(addr_mat.ra().mod == .integer);
                    try isel.moveLoc(
                        mat.location,
                        if (mat.full) mat.offset else 0,
                        .{ .stack_slot = .{ .base = addr_mat.reg(), .offset = 0 } },
                        offset_from_root + mat.offset,
                        mat.size,
                        .none,
                    );
                    try addr_mat.finish(isel);
                },
                .constant => |constant| {
                    const mat_loc = mat.loc();
                    mat_loc.markRegWritten(isel);
                    try isel.moveConstant(mat_loc, constant, offset_from_root + mat.offset, mat.size);
                },
            }
        }
    };

    /// DFS iterator over a sub-tree.
    const Walk = struct {
        isel: *Select,
        root_vi: Value.Index,
        next_vi: Value.Index,
        opts: Options,

        const Options = packed struct {
            /// Reversed order
            reverse: bool = true,
            /// Whether to include root nodes
            root: bool = true,
            /// Whether to include intermdiate nodes
            /// (i.e. nodes that are not leaf vertexes)
            intermdiate: bool = true,
            /// Whether to include leaf vertexes
            leaves: bool = true,
        };

        pub fn next(it: *Walk) ?Value.Index {
            const isel = it.isel;
            const opts = it.opts;
            while (it.next_vi != .free) {
                const node_vi = it.next_vi;

                // find next node
                next_node: {
                    // go to the first child
                    if (node_vi.hasParts(isel)) {
                        it.next_vi = if (!opts.reverse)
                            node_vi.get(isel).parts
                        else last_child: {
                            const node_value = node_vi.get(isel);
                            break :last_child @fromBackingInt(@backingInt(node_value.parts) + node_value.flags.parts_len_minus_one);
                        };
                        break :next_node;
                    }
                    if (node_vi.parentValue(isel) != null) {
                        var iter_vi = node_vi;
                        while (true) {
                            // go to the next sibling
                            const parent_vi = iter_vi.get(isel).parent_payload.value;
                            const parent_value = parent_vi.get(isel);
                            if (!opts.reverse) {
                                const last_sibling = @backingInt(parent_value.parts) + parent_value.flags.parts_len_minus_one;
                                if (@backingInt(iter_vi) < last_sibling) {
                                    it.next_vi = @fromBackingInt(@backingInt(iter_vi) + 1);
                                    break :next_node;
                                }
                            } else {
                                if (@backingInt(iter_vi) > @backingInt(parent_value.parts)) {
                                    it.next_vi = @fromBackingInt(@backingInt(iter_vi) - 1);
                                    break :next_node;
                                }
                            }
                            // return to ancestor's sibling
                            if (parent_value.flags.parent_tag == .value)
                                iter_vi = parent_vi
                            else
                                break;
                        }
                    }
                    it.next_vi = .free;
                }

                // filter nodes
                if (!it.opts.root and node_vi == it.root_vi) continue;
                if (!it.opts.intermdiate and node_vi.hasParts(isel)) continue;
                if (!it.opts.leaves and !node_vi.hasParts(isel)) continue;
                return node_vi;
            }
            return null;
        }

        pub fn skipChildren(it: *Walk, current_vi: Value.Index) void {
            const isel = it.isel;
            const current_value = current_vi.get(isel);
            if (current_value.flags.parts_len_minus_one != 0) {
                const last_part = @backingInt(current_value.parts) + current_value.flags.parts_len_minus_one;
                it.next_vi = @fromBackingInt(last_part);
                _ = it.next();
            }
        }

        pub fn peek(it: Walk) ?Value.Index {
            var it_mut = it;
            return it_mut.next();
        }
    };
};

fn fail(isel: *Select, comptime format: []const u8, args: anytype) error{ OutOfMemory, AlreadyReported } {
    @branchHint(.cold);
    wip_mir_log.debug("codegen error: " ++ format, args);
    return isel.pt.zcu.codegenFail(isel.nav_index, format, args);
}

fn failUnimplemented(isel: *Select, comptime format: []const u8, args: anytype) error{ OutOfMemory, AlreadyReported }!void {
    @branchHint(.cold);
    if (debug_trap_unimplemented_code) {
        const gpa = isel.pt.zcu.gpa;

        const msg = try std.fmt.allocPrintSentinel(gpa, format, args, 0);
        defer gpa.free(msg);
        wip_mir_log.err("{s}", .{msg});
        try isel.emit(.@"break"(0xaa));
        try isel.moveDebugString(.r22, msg);
    } else return isel.fail(format, args);
}

fn moveDebugString(isel: *Select, reg: Register, msg: [:0]const u8) error{ OutOfMemory, AlreadyReported }!void {
    @branchHint(.cold);
    assert(debug_trap_unimplemented_code);

    const pt = isel.pt;
    const zcu = pt.zcu;
    const ip = &zcu.intern_pool;
    const gpa = zcu.gpa;

    const msg_ty = try pt.arrayType(.{
        .len = msg.len,
        .child = .u8_type,
        .sentinel = .zero_u8,
    });
    const msg_str = try ip.getOrPutString(gpa, zcu.comp.io, pt.tid, msg, .maybe_embedded_nulls);
    const msg_val = try pt.intern(.{ .aggregate = .{
        .ty = msg_ty.ip_index,
        .storage = .{ .bytes = msg_str },
    } });
    const msg_ptr = try pt.intern(.{ .ptr = .{
        .ty = .manyptr_const_u8_sentinel_0_type,
        .base_addr = .{ .uav = .{
            .val = msg_val,
            .orig_ty = .manyptr_const_u8_sentinel_0_type,
        } },
        .byte_offset = 0,
    } });
    try isel.moveConstant(
        .{ .register = .{ .reg = reg, .mod = .integer } },
        .fromInterned(msg_ptr),
        0,
        isel.gprSize(),
    );
}

pub fn analyze(isel: *Select, air_body: []const Air.Inst.Index) !void {
    const zcu = isel.pt.zcu;
    const ip = &zcu.intern_pool;
    const gpa = zcu.gpa;
    const air_tags = isel.air.instructions.items(.tag);
    const air_data = isel.air.instructions.items(.data);
    const initial_def_order_len = isel.def_order.count();

    for (air_body) |air_inst_index| {
        switch (air_tags[@backingInt(air_inst_index)]) {
            else => |air_tag| return isel.fail("unimplemented analyze for {t}", .{air_tag}),
            .arg,
            .ret_addr,
            .frame_addr,
            .err_return_trace,
            .save_err_return_trace_index,
            .runtime_nav_ptr,
            .c_va_start,
            => {
                try isel.def_order.putNoClobber(gpa, air_inst_index, {});
            },
            .add,
            .add_safe,
            .add_optimized,
            .add_wrap,
            .add_sat,
            .sub,
            .sub_safe,
            .sub_optimized,
            .sub_wrap,
            .sub_sat,
            .mul,
            .mul_safe,
            .mul_optimized,
            .mul_wrap,
            .mul_sat,
            .div_float,
            .div_float_optimized,
            .div_trunc,
            .div_trunc_optimized,
            .div_floor,
            .div_floor_optimized,
            .div_exact,
            .div_exact_optimized,
            .rem,
            .rem_optimized,
            .mod,
            .mod_optimized,
            .max,
            .min,
            .bit_and,
            .bit_or,
            .shr,
            .shr_exact,
            .shl,
            .shl_exact,
            .shl_sat,
            .xor,
            .cmp_lt,
            .cmp_lt_optimized,
            .cmp_lte,
            .cmp_lte_optimized,
            .cmp_eq,
            .cmp_eq_optimized,
            .cmp_gte,
            .cmp_gte_optimized,
            .cmp_gt,
            .cmp_gt_optimized,
            .cmp_neq,
            .cmp_neq_optimized,
            .array_elem_val,
            .slice_elem_val,
            .ptr_elem_val,
            => {
                const bin_op = air_data[@backingInt(air_inst_index)].bin_op;

                try isel.analyzeUse(bin_op.lhs);
                try isel.analyzeUse(bin_op.rhs);
                try isel.def_order.putNoClobber(gpa, air_inst_index, {});
            },
            .ptr_add,
            .ptr_sub,
            .add_with_overflow,
            .sub_with_overflow,
            .mul_with_overflow,
            .shl_with_overflow,
            .slice,
            .slice_elem_ptr,
            .ptr_elem_ptr,
            => {
                const ty_pl = air_data[@backingInt(air_inst_index)].ty_pl;
                const bin_op = isel.air.extraData(Air.Bin, ty_pl.payload).data;

                try isel.analyzeUse(bin_op.lhs);
                try isel.analyzeUse(bin_op.rhs);
                try isel.def_order.putNoClobber(gpa, air_inst_index, {});
            },
            .alloc => {
                const ty = air_data[@backingInt(air_inst_index)].ty;

                isel.stack_align = isel.stack_align.maxStrict(ty.ptrAlignment(zcu));
                try isel.def_order.putNoClobber(gpa, air_inst_index, {});
            },
            .inferred_alloc,
            .inferred_alloc_comptime,
            .wasm_memory_size,
            .wasm_memory_grow,
            .work_item_id,
            .work_group_size,
            .work_group_id,
            => unreachable,
            .ret, .ret_safe, .ret_load => {
                const un_op = air_data[@backingInt(air_inst_index)].un_op;
                isel.returns = true;

                assert(isel.active_blocks.keys()[0] == Block.main);

                try isel.analyzeUse(un_op);
            },
            .ret_ptr => {
                const ty = air_data[@backingInt(air_inst_index)].ty;

                if (isel.live_values.get(Block.main)) |ret_vi| {
                    switch (ret_vi.parent(isel)) {
                        .none => isel.stack_align = isel.stack_align.maxStrict(ty.ptrAlignment(zcu)),
                        .value, .constant => unreachable,
                        .address => |address_vi| try isel.live_values.putNoClobber(gpa, air_inst_index, address_vi.ref(isel)),
                    }
                    if (ret_vi.stackSlot(isel) != null)
                        isel.stack_align = isel.stack_align.maxStrict(ty.ptrAlignment(zcu));
                }
                try isel.def_order.putNoClobber(gpa, air_inst_index, {});
            },
            .assembly => {
                const ty_pl = air_data[@backingInt(air_inst_index)].ty_pl;
                const extra = isel.air.extraData(Air.Asm, ty_pl.payload);
                const operands: []const Air.Inst.Ref = @ptrCast(isel.air.extra.items[extra.end..][0 .. extra.data.flags.outputs_len + extra.data.inputs_len]);

                for (operands) |operand| if (operand != .none) try isel.analyzeUse(operand);
                if (ty_pl.ty != .void_type) try isel.def_order.putNoClobber(gpa, air_inst_index, {});
            },
            .not,
            .clz,
            .ctz,
            .popcount,
            .byte_swap,
            .bit_reverse,
            .abs,
            .load,
            .fptrunc,
            .fpext,
            .int_cast,
            .int_cast_safe,
            .trunc,
            .optional_payload,
            .optional_payload_ptr,
            .optional_payload_ptr_set,
            .wrap_optional,
            .unwrap_errunion_payload,
            .unwrap_errunion_err,
            .unwrap_errunion_payload_ptr,
            .unwrap_errunion_err_ptr,
            .errunion_payload_ptr_set,
            .wrap_errunion_payload,
            .wrap_errunion_err,
            .struct_field_ptr_index_0,
            .struct_field_ptr_index_1,
            .struct_field_ptr_index_2,
            .struct_field_ptr_index_3,
            .get_union_tag,
            .ptr_slice_len_ptr,
            .ptr_slice_ptr_ptr,
            .array_to_slice,
            .int_from_float,
            .int_from_float_optimized,
            .int_from_float_safe,
            .int_from_float_optimized_safe,
            .float_from_int,
            .splat,
            .error_set_has_value,
            .addrspace_cast,
            .c_va_arg,
            .c_va_copy,
            .bit_cast,
            .ptr_cast,
            .ptr_from_int,
            .int_from_ptr,
            .error_cast,
            .error_from_int,
            .int_from_error,
            .union_from_enum,
            => {
                const ty_op = air_data[@backingInt(air_inst_index)].ty_op;

                try isel.analyzeUse(ty_op.operand);
                try isel.def_order.putNoClobber(gpa, air_inst_index, {});
            },
            .loop => {
                const ty_pl = air_data[@backingInt(air_inst_index)].ty_pl;
                const extra = isel.air.extraData(Air.Block, ty_pl.payload);

                try isel.active_loops.append(gpa, @fromBackingInt(@intCast(isel.loops.count())));
                try isel.loops.putNoClobber(gpa, air_inst_index, .{
                    .def_order = @intCast(isel.def_order.count()),
                    .outer_live = 0,
                    .repeat_list = undefined,
                });
                try isel.analyze(@ptrCast(isel.air.extra.items[extra.end..][0..extra.data.body_len]));
                assert(isel.active_loops.pop().?.inst(isel) == air_inst_index);
            },
            .repeat, .trap, .unreach => {},
            .br => {
                const br = air_data[@backingInt(air_inst_index)].br;
                try isel.analyzeUse(br.operand);
            },
            .breakpoint, .dbg_stmt, .dbg_empty_stmt, .dbg_var_ptr, .dbg_var_val, .dbg_arg_inline, .c_va_end => {},
            .sqrt,
            .sin,
            .cos,
            .tan,
            .exp,
            .exp2,
            .log,
            .log2,
            .log10,
            .floor,
            .ceil,
            .round,
            .trunc_float,
            .neg,
            .neg_optimized,
            .is_null,
            .is_non_null,
            .is_null_ptr,
            .is_non_null_ptr,
            .is_err,
            .is_non_err,
            .is_err_ptr,
            .is_non_err_ptr,
            .is_named_enum_value,
            .tag_name,
            .error_name,
            => {
                const un_op = air_data[@backingInt(air_inst_index)].un_op;

                try isel.analyzeUse(un_op);
                try isel.def_order.putNoClobber(gpa, air_inst_index, {});
            },
            .cmp_vector, .cmp_vector_optimized => {
                const ty_pl = air_data[@backingInt(air_inst_index)].ty_pl;
                const extra = isel.air.extraData(Air.VectorCmp, ty_pl.payload).data;

                try isel.analyzeUse(extra.lhs);
                try isel.analyzeUse(extra.rhs);
                try isel.def_order.putNoClobber(gpa, air_inst_index, {});
            },
            .store,
            .store_safe,
            .set_union_tag,
            .memset,
            .memset_safe,
            .memcpy,
            .memmove,
            .atomic_store_unordered,
            .atomic_store_monotonic,
            .atomic_store_release,
            .atomic_store_seq_cst,
            => {
                const bin_op = air_data[@backingInt(air_inst_index)].bin_op;

                try isel.analyzeUse(bin_op.lhs);
                try isel.analyzeUse(bin_op.rhs);
            },
            .struct_field_ptr, .agg_field_val => {
                const ty_pl = air_data[@backingInt(air_inst_index)].ty_pl;
                const extra = isel.air.extraData(Air.StructField, ty_pl.payload).data;

                try isel.analyzeUse(extra.struct_operand);
                try isel.def_order.putNoClobber(gpa, air_inst_index, {});
            },
            .aggregate_init => {
                const ty_pl = air_data[@backingInt(air_inst_index)].ty_pl;
                const elements: []const Air.Inst.Ref = @ptrCast(isel.air.extra.items[ty_pl.payload..][0..@intCast(ty_pl.ty.toType().arrayLen(zcu))]);

                for (elements) |element| try isel.analyzeUse(element);
                try isel.def_order.putNoClobber(gpa, air_inst_index, {});
            },
            .union_init => {
                const ty_pl = air_data[@backingInt(air_inst_index)].ty_pl;
                const extra = isel.air.extraData(Air.UnionInit, ty_pl.payload).data;

                try isel.analyzeUse(extra.init);
                try isel.def_order.putNoClobber(gpa, air_inst_index, {});
            },
            .prefetch => {
                const prefetch = air_data[@backingInt(air_inst_index)].prefetch;
                try isel.analyzeUse(prefetch.ptr);
            },
            .field_parent_ptr => {
                const ty_pl = air_data[@backingInt(air_inst_index)].ty_pl;
                const extra = isel.air.extraData(Air.FieldParentPtr, ty_pl.payload).data;

                try isel.analyzeUse(extra.field_ptr);
                try isel.def_order.putNoClobber(gpa, air_inst_index, {});
            },
            .set_err_return_trace => {
                const un_op = air_data[@backingInt(air_inst_index)].un_op;
                try isel.analyzeUse(un_op);
            },
            inline .block, .dbg_inline_block => |air_tag| {
                const ty_pl = air_data[@backingInt(air_inst_index)].ty_pl;
                const extra = isel.air.extraData(switch (air_tag) {
                    else => comptime unreachable,
                    .block => Air.Block,
                    .dbg_inline_block => Air.DbgInlineBlock,
                }, ty_pl.payload);
                const result_ty = ty_pl.ty.toInterned().?;

                if (result_ty == .noreturn_type) {
                    try isel.analyze(@ptrCast(isel.air.extra.items[extra.end..][0..extra.data.body_len]));
                    break;
                }

                assert(!(try isel.active_blocks.getOrPut(gpa, air_inst_index)).found_existing);
                try isel.analyze(@ptrCast(isel.air.extra.items[extra.end..][0..extra.data.body_len]));
                const block_entry = isel.active_blocks.pop().?;
                assert(block_entry.key == air_inst_index);

                if (result_ty != .void_type) try isel.def_order.putNoClobber(gpa, air_inst_index, {});
            },
            .call,
            .call_always_tail,
            .call_never_tail,
            .call_never_inline,
            => {
                const pl_op = air_data[@backingInt(air_inst_index)].pl_op;
                const extra = isel.air.extraData(Air.Call, pl_op.payload);
                const args: []const Air.Inst.Ref = @ptrCast(isel.air.extra.items[extra.end..][0..extra.data.args_len]);
                isel.saved_registers.insert(.ra);
                const callee_ty = isel.air.typeOf(pl_op.operand, ip);
                const func_info = switch (ip.indexToKey(callee_ty.toIntern())) {
                    else => unreachable,
                    .func_type => |func_type| func_type,
                    .ptr_type => |ptr_type| ip.indexToKey(ptr_type.child).func_type,
                };

                try isel.analyzeUse(pl_op.operand);
                var cc_it: CallAbiIterator = .{ .isel = isel, .cc = &func_info.cc };

                const ret_ty = isel.air.typeOfIndex(air_inst_index, ip);
                if (try cc_it.resolve(ret_ty, true)) |ret_vi| {
                    tracking_log.debug("{f} <- %{d} (call return)", .{ ret_vi, @backingInt(air_inst_index) });
                    switch (ret_vi.parent(isel)) {
                        .none => {},
                        .value, .constant => unreachable,
                        .address => |address_vi| {
                            defer address_vi.deref(isel);
                            const ret_value = ret_vi.get(isel);
                            ret_value.flags.parent_tag = .none;
                            ret_value.parent_payload = .{ .none = {} };
                        },
                    }
                    try isel.live_values.putNoClobber(gpa, air_inst_index, ret_vi);

                    try isel.def_order.putNoClobber(gpa, air_inst_index, {});
                }

                for (args) |arg| {
                    {
                        const restore_values_len = isel.values.items.len;
                        defer isel.values.shrinkRetainingCapacity(restore_values_len);
                        defer isel.value_types.shrinkRetainingCapacity(restore_values_len);

                        const param_ty = isel.air.typeOf(arg, ip);
                        const param_vi = try cc_it.resolve(param_ty, false) orelse continue;
                        defer param_vi.deref(isel);

                        const passed_vi = switch (param_vi.parent(isel)) {
                            .none => param_vi,
                            .value, .constant => unreachable,
                            .address => |address_vi| address_vi,
                        };
                        if (passed_vi.stackSlot(isel)) |stack_slot| {
                            assert(stack_slot.base == Register.sp);
                            isel.stack_size = @max(
                                isel.stack_size,
                                stack_slot.offset + @as(u24, @intCast(passed_vi.size(isel))),
                            );
                        }
                    }

                    try isel.analyzeUse(arg);
                }
            },
            .cond_br => {
                const pl_op = air_data[@backingInt(air_inst_index)].pl_op;
                const extra = isel.air.extraData(Air.CondBr, pl_op.payload);

                try isel.analyzeUse(pl_op.operand);

                try isel.analyze(@ptrCast(isel.air.extra.items[extra.end..][0..extra.data.then_body_len]));
                try isel.analyze(@ptrCast(isel.air.extra.items[extra.end + extra.data.then_body_len ..][0..extra.data.else_body_len]));
            },
            .switch_br => {
                const switch_br = isel.air.unwrapSwitch(air_inst_index);

                try isel.analyzeUse(switch_br.operand);

                var cases_it = switch_br.iterateCases();
                while (cases_it.next()) |case| try isel.analyze(case.body);
                if (switch_br.else_body_len > 0) try isel.analyze(cases_it.elseBody());
            },
            .loop_switch_br => {
                const switch_br = isel.air.unwrapSwitch(air_inst_index);

                try isel.active_loops.append(gpa, @fromBackingInt(@intCast(isel.loops.count())));
                try isel.loops.putNoClobber(gpa, air_inst_index, .{
                    .def_order = @intCast(isel.def_order.count()),
                    .outer_live = 0,
                    .repeat_list = undefined,
                });

                var cases_it = switch_br.iterateCases();
                while (cases_it.next()) |case| try isel.analyze(case.body);
                if (switch_br.else_body_len > 0) try isel.analyze(cases_it.elseBody());

                assert(isel.active_loops.pop().?.inst(isel) == air_inst_index);
            },
            .switch_dispatch => {
                const br = air_data[@backingInt(air_inst_index)].br;
                try isel.analyzeUse(br.operand);
            },
            .slice_ptr => {
                const ty_op = air_data[@backingInt(air_inst_index)].ty_op;

                try isel.analyzeUse(ty_op.operand);
                try isel.def_order.putNoClobber(gpa, air_inst_index, {});

                const slice_vi = try isel.use(ty_op.operand);
                const ptr_part_vi = try slice_vi.partExact(isel, 0, 8);
                try isel.live_values.putNoClobber(gpa, air_inst_index, ptr_part_vi.ref(isel));
            },
            .slice_len => {
                const ty_op = air_data[@backingInt(air_inst_index)].ty_op;

                try isel.analyzeUse(ty_op.operand);
                try isel.def_order.putNoClobber(gpa, air_inst_index, {});

                const slice_vi = try isel.use(ty_op.operand);
                const len_part_vi = try slice_vi.partExact(isel, 8, 8);
                try isel.live_values.putNoClobber(gpa, air_inst_index, len_part_vi.ref(isel));
            },
            .reduce, .reduce_optimized => {
                const reduce = air_data[@backingInt(air_inst_index)].reduce;

                try isel.analyzeUse(reduce.operand);
                try isel.def_order.putNoClobber(gpa, air_inst_index, {});
            },
            .shuffle_one => {
                const extra = isel.air.unwrapShuffleOne(zcu, air_inst_index);

                try isel.analyzeUse(extra.operand);
                try isel.def_order.putNoClobber(gpa, air_inst_index, {});
            },
            .shuffle_two => {
                const extra = isel.air.unwrapShuffleTwo(zcu, air_inst_index);

                try isel.analyzeUse(extra.operand_a);
                try isel.analyzeUse(extra.operand_b);
                try isel.def_order.putNoClobber(gpa, air_inst_index, {});
            },
            .@"try", .try_cold => {
                const pl_op = air_data[@backingInt(air_inst_index)].pl_op;
                const extra = isel.air.extraData(Air.Try, pl_op.payload);

                try isel.analyzeUse(pl_op.operand);
                try isel.analyze(@ptrCast(isel.air.extra.items[extra.end..][0..extra.data.body_len]));
                try isel.def_order.putNoClobber(gpa, air_inst_index, {});
            },
            .try_ptr, .try_ptr_cold => {
                const ty_pl = air_data[@backingInt(air_inst_index)].ty_pl;
                const extra = isel.air.extraData(Air.TryPtr, ty_pl.payload);

                try isel.analyzeUse(extra.data.ptr);
                try isel.analyze(@ptrCast(isel.air.extra.items[extra.end..][0..extra.data.body_len]));
                try isel.def_order.putNoClobber(gpa, air_inst_index, {});
            },
            .cmpxchg_weak, .cmpxchg_strong => {
                const ty_pl = air_data[@backingInt(air_inst_index)].ty_pl;
                const extra = isel.air.extraData(Air.Cmpxchg, ty_pl.payload).data;

                try isel.analyzeUse(extra.ptr);
                try isel.analyzeUse(extra.expected_value);
                try isel.analyzeUse(extra.new_value);
                try isel.def_order.putNoClobber(gpa, air_inst_index, {});
            },
            .atomic_load => {
                const atomic_load = air_data[@backingInt(air_inst_index)].atomic_load;

                try isel.analyzeUse(atomic_load.ptr);
                try isel.def_order.putNoClobber(gpa, air_inst_index, {});
            },
            .atomic_rmw => {
                const pl_op = air_data[@backingInt(air_inst_index)].pl_op;
                const extra = isel.air.extraData(Air.AtomicRmw, pl_op.payload).data;

                try isel.analyzeUse(extra.operand);
                try isel.def_order.putNoClobber(gpa, air_inst_index, {});
            },
        }
    }
    isel.def_order.shrinkRetainingCapacity(initial_def_order_len);
}

fn analyzeUse(isel: *Select, air_ref: Air.Inst.Ref) !void {
    const air_inst_index = air_ref.toIndex() orelse return;
    const def_order_index = isel.def_order.getIndex(air_inst_index).?;

    // Loop liveness
    var active_loop_index = isel.active_loops.items.len;
    while (active_loop_index > 0) {
        const prev_active_loop_index = active_loop_index - 1;
        const active_loop = isel.active_loops.items[prev_active_loop_index];
        if (def_order_index >= active_loop.get(isel).def_order) break;
        active_loop_index = prev_active_loop_index;
    }
    if (active_loop_index < isel.active_loops.items.len) {
        const active_loop = isel.active_loops.items[active_loop_index];
        const loop_live_gop =
            try isel.loop_outer_live.set.getOrPut(isel.pt.zcu.gpa, .{ active_loop, air_inst_index });
        if (!loop_live_gop.found_existing) active_loop.get(isel).outer_live += 1;
    }
}

pub fn finishAnalysis(isel: *Select) !void {
    const gpa = isel.pt.zcu.gpa;

    // Loop liveness
    if (isel.loops.count() > 0) {
        try isel.loops.ensureUnusedCapacity(gpa, 1);

        const loop_live_len: u32 = @intCast(isel.loop_outer_live.set.count());
        if (loop_live_len > 0) {
            try isel.loop_outer_live.list.resize(gpa, loop_live_len);

            // prefix sum
            const loops = isel.loops.values();
            for (loops[1..], loops[0 .. loops.len - 1]) |*loop, prev_loop| loop.outer_live += prev_loop.outer_live;
            assert(loops[loops.len - 1].outer_live == loop_live_len);

            for (isel.loop_outer_live.set.keys()) |entry| {
                const loop, const inst = entry;
                const loop_live = &loop.get(isel).outer_live;
                loop_live.* -= 1;
                isel.loop_outer_live.list.items[loop_live.*] = inst;
            }
            assert(loops[0].outer_live == 0);
        }

        const invalid_gop = isel.loops.getOrPutAssumeCapacity(Loop.invalid);
        assert(!invalid_gop.found_existing);
        invalid_gop.value_ptr.* = .{
            .def_order = undefined,
            .outer_live = loop_live_len,
            .repeat_list = undefined,
        };
    }

    assert(isel.active_blocks.count() == 1 and isel.active_blocks.keys()[0] == Select.Block.main);
    assert(isel.active_loops.items.len == 0);
}

pub fn verify(isel: *Select, check_values: bool) void {
    if (!std.debug.runtime_safety) return;
    assert(isel.active_blocks.count() == 1 and isel.active_blocks.keys()[0] == Select.Block.main);
    assert(isel.active_loops.items.len == 0);
    assert(isel.values.items.len == isel.value_types.items.len);

    // Verify register state
    var live_reg_it = isel.live_registers.iterator();
    while (live_reg_it.next()) |live_reg_entry| switch (live_reg_entry.value.*) {
        _ => {
            tracking_log.err("{f}: still using ${t}", .{ live_reg_entry.value.*, live_reg_entry.key });
            isel.dumpValues(.all);
            unreachable;
        },
        .allocating, .free => {},
    };

    // Check values state
    if (!check_values) return;
    for (isel.values.items, 0..) |value, vi_i| {
        const vi: Value.Index = @fromBackingInt(@as(@typeInfo(Value.Index).@"enum".tag_type, @intCast(vi_i)));
        if (value.refs != 0) {
            tracking_log.err("{f}: still referenced", .{vi});
            isel.dumpValues(.all);
            unreachable;
        }
        if (value.flags.parent_tag == .none and value.offset_from_parent != 0) {
            tracking_log.err("{f}: values without none cannot have offset from parent", .{vi});
            isel.dumpValues(.all);
            unreachable;
        }
        // Stack slot locations are allowed because layout values use them
        if (vi.register(isel) != null) {
            tracking_log.err("{f}: still has a location", .{vi});
            isel.dumpValues(.all);
            unreachable;
        }
    }
}

pub fn body(isel: *Select, air_body: []const Air.Inst.Index) error{ OutOfMemory, AlreadyReported }!void {
    const zcu = isel.pt.zcu;
    const ip = &zcu.intern_pool;
    const gpa = zcu.gpa;

    {
        var live_reg_it = isel.live_registers.iterator();
        while (live_reg_it.next()) |live_reg_entry| switch (live_reg_entry.value.*) {
            .allocating => {
                tracking_log.err("${t} is allocated", .{live_reg_entry.key});
                isel.dumpValues(.all);
                unreachable;
            },
            _, .free => {},
        };
    }

    var air: struct {
        isel: *Select,
        tag_items: []const Air.Inst.Tag,
        data_items: []const Air.Inst.Data,
        body: []const Air.Inst.Index,
        body_index: u32,
        inst_index: Air.Inst.Index,

        fn tag(it: *@This(), inst_index: Air.Inst.Index) Air.Inst.Tag {
            return it.tag_items[@backingInt(inst_index)];
        }

        fn data(it: *@This(), inst_index: Air.Inst.Index) Air.Inst.Data {
            return it.data_items[@backingInt(inst_index)];
        }

        fn next(it: *@This()) ?Air.Inst.Tag {
            if (it.body_index == 0) {
                @branchHint(.unlikely);
                return null;
            }
            it.body_index -= 1;
            it.inst_index = it.body[it.body_index];
            wip_mir_log.debug("{f}", .{it.fmtAir(it.inst_index)});
            if (@import("builtin").mode == .debug) {
                if (it.isel.live_values.get(it.inst_index)) |def_vi| {
                    wip_mir_log.debug("   <- {f}", .{it.isel.fmtValue(def_vi)});
                }
            }
            return it.tag(it.inst_index);
        }

        fn fmtAir(it: @This(), inst: Air.Inst.Index) struct {
            isel: *Select,
            inst: Air.Inst.Index,
            pub fn format(fmt_air: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
                fmt_air.isel.air.writeInst(writer, fmt_air.inst, fmt_air.isel.pt, null);
            }
        } {
            return .{ .isel = it.isel, .inst = inst };
        }
    } = .{
        .isel = isel,
        .tag_items = isel.air.instructions.items(.tag),
        .data_items = isel.air.instructions.items(.data),
        .body = air_body,
        .body_index = @intCast(air_body.len),
        .inst_index = undefined,
    };
    while (air.next()) |air_tag| {
        switch (air_tag) {
            else => if (debug_trap_unimplemented_code) {
                if (isel.live_values.fetchRemove(air.inst_index)) |vi| {
                    vi.value.deref(isel);
                    isel.wipeLocationDfs(vi.value);
                }
                try isel.failUnimplemented("unimplemented select for {s}", .{@tagName(air_tag)});
            } else return isel.fail("unimplemented select for {s}", .{@tagName(air_tag)}),

            // Misc
            .unreach => {},
            .trap, .breakpoint => try isel.emit(.@"break"(0)),

            // Arguments & return
            .arg => {
                const arg_vi = isel.live_values.fetchRemove(air.inst_index).?.value;
                defer arg_vi.deref(isel);
                const layout_vi = isel.arg_layouts[@backingInt(air.inst_index)];
                layout_vi.deref(isel);
                switch (layout_vi.parent(isel)) {
                    .none => try arg_vi.defLiveIn(isel, layout_vi, .{}),
                    .value, .constant => unreachable,
                    .address => |layout_addr_vi| {
                        switch (arg_vi.parent(isel)) {
                            else => unreachable,
                            .address => |arg_addr_vi| {
                                try arg_addr_vi.defLiveIn(isel, layout_addr_vi, .{});
                            },
                        }
                    },
                }
            },
            .ret, .ret_safe => {
                assert(isel.active_blocks.keys()[0] == Block.main);
                try isel.active_blocks.values()[0].branch(isel);
                if (isel.live_values.get(Block.main)) |ret_vi| {
                    const un_op = air.data(air.inst_index).un_op;
                    const src_vi = try isel.use(un_op);
                    switch (ret_vi.parent(isel)) {
                        .none => try src_vi.matLiveOut(isel, ret_vi, .{ .mode = .ret }),
                        .value, .constant => unreachable,
                        .address => |addr_vi| {
                            const addr_mat = try addr_vi.matIntRegZeroExt(isel);
                            try src_vi.matStore(isel, addr_mat.reg(), 0, .{});
                            try addr_mat.finish(isel);
                        },
                    }
                }
            },
            .ret_load => {
                const un_op = air.data(air.inst_index).un_op;
                const ptr_ty = isel.air.typeOf(un_op, ip);
                const ptr_info = ptr_ty.ptrInfo(zcu);
                if (ptr_info.packed_offset.host_size > 0) return isel.fail("packed load ret_load", .{});

                assert(isel.active_blocks.keys()[0] == Block.main);
                try isel.active_blocks.values()[0].branch(isel);
                if (isel.live_values.get(Block.main)) |layout_vi| switch (layout_vi.parent(isel)) {
                    .none => {
                        const ptr_vi = try isel.use(un_op);
                        const ret_ty = ptr_ty.childType(zcu);
                        const ret_vi = try isel.initValue(ret_ty);
                        ret_vi.setParent(isel, .{ .address = ptr_vi });
                        try ret_vi.matLiveOut(isel, layout_vi, .{ .mode = .ret });
                    },
                    .value, .constant => unreachable,
                    .address => {},
                };
            },

            // Frame addresses
            .ret_addr => if (isel.live_values.fetchRemove(air.inst_index)) |addr_vi| unused: {
                defer addr_vi.value.deref(isel);
                const addr_reg = try addr_vi.value.defRegMod(isel, .integer) orelse break :unused;
                try isel.ldIncoming(addr_reg, .ra);
            },
            .frame_addr => if (isel.live_values.fetchRemove(air.inst_index)) |addr_vi| unused: {
                defer addr_vi.value.deref(isel);
                const addr_reg = try addr_vi.value.defRegMod(isel, .integer) orelse break :unused;
                isel.saved_registers.insert(.fp);
                try isel.emit(.ori(addr_reg, .fp, 0));
            },

            // Debugging
            .dbg_stmt, .dbg_var_ptr, .dbg_var_val, .dbg_arg_inline => {},
            .dbg_empty_stmt => try isel.emit(.andi(.r0, .r0, 0)),

            // Control-flows
            .dbg_inline_block => {
                const ty_pl = air.data(air.inst_index).ty_pl;
                const extra = isel.air.extraData(Air.DbgInlineBlock, ty_pl.payload);
                try isel.block(air.inst_index, ty_pl.ty.toType(), @ptrCast(
                    isel.air.extra.items[extra.end..][0..extra.data.body_len],
                ));
            },
            .block => {
                const ty_pl = air.data(air.inst_index).ty_pl;
                const extra = isel.air.extraData(Air.Block, ty_pl.payload);
                try isel.block(air.inst_index, ty_pl.ty.toType(), @ptrCast(
                    isel.air.extra.items[extra.end..][0..extra.data.body_len],
                ));
            },
            .loop => {
                const ty_pl = air.data(air.inst_index).ty_pl;
                const extra = isel.air.extraData(Air.Block, ty_pl.payload);
                const loops = isel.loops.values();
                const loop_index = isel.loops.getIndex(air.inst_index).?;
                const loop = &loops[loop_index];

                tracking_log.debug("{f}", .{isel.fmtLoopLive(air.inst_index)});
                loop.snapshot = try isel.takeLocationSnapshot();
                tracking_log.debug("loop snapshot taken:\n{f}", .{loop.snapshot});
                loop.repeat_list = Loop.empty_list;

                try isel.active_loops.append(gpa, @fromBackingInt(@intCast(loop_index)));
                try isel.body(@ptrCast(isel.air.extra.items[extra.end..][0..extra.data.body_len]));
                assert(isel.active_loops.pop().?.inst(isel) == air.inst_index);

                tracking_log.debug("loop %{d}: merge snapshot after loop body", .{@backingInt(air.inst_index)});
                try loop.snapshot.merge(isel);
                loop.snapshot.deinit(isel);
                loop.snapshot = .empty;

                tracking_log.debug("loop %{d}: kill registers written in loop body", .{@backingInt(air.inst_index)});
                try isel.fillRegsBatch(loop.written_regs, false);
                // copy written registers to outer loops
                isel.markRegsWritten(loop.written_regs);

                // relocate branches
                var repeat_label = loop.repeat_list;
                assert(repeat_label != Loop.empty_list);
                while (repeat_label != Loop.empty_list) {
                    const instruction = &isel.instructions.items[repeat_label];
                    const next_repeat_label = instruction.*;
                    instruction.* = .b(0, 0);
                    try isel.internal_relocs.append(gpa, .{
                        .label = repeat_label,
                        .target = isel.instructions.items.len,
                    });
                    repeat_label = @bitCast(next_repeat_label);
                }
            },
            .repeat => {
                const repeat = air.data(air.inst_index).repeat;
                try isel.loops.getPtr(repeat.loop_inst).?.branch(isel);
            },
            .br => {
                const br = air.data(air.inst_index).br;
                try isel.active_blocks.getPtr(br.block_inst).?.branch(isel);
                if (isel.live_values.get(br.block_inst)) |dst_vi| try dst_vi.defMove(isel, br.operand);
            },
            .cond_br => {
                const pl_op = air.data(air.inst_index).pl_op;
                const extra = isel.air.extraData(Air.CondBr, pl_op.payload);

                try isel.body(@ptrCast(isel.air.extra.items[extra.end + extra.data.then_body_len ..][0..extra.data.else_body_len]));
                const else_label = isel.instructions.items.len;
                var else_snapshot = try isel.takeLocationSnapshot();
                defer else_snapshot.deinit(isel);
                tracking_log.debug("if-body snapshot taken:\n{f}", .{else_snapshot});
                try isel.body(@ptrCast(isel.air.extra.items[extra.end..][0..extra.data.then_body_len]));
                try else_snapshot.merge(isel);

                const cond_vi = try isel.use(pl_op.operand);
                const cond_mat = try cond_vi.mat(isel, .{
                    .pref = .only_reg,
                    .extension = .zero_ext,
                });
                try isel.internal_relocs.append(gpa, .{
                    .label = @intCast(isel.instructions.items.len),
                    .target = else_label,
                });
                try isel.emit(.beqz(cond_mat.reg(), 0, 0));
                try cond_mat.finish(isel);
            },
            .switch_br, .loop_switch_br => {
                // TODO loop switch br and switch dispatch
                if (air_tag == .loop_switch_br) try isel.failUnimplemented("TODO loop_switch_br", .{});
                const switch_br = isel.air.unwrapSwitch(air.inst_index);

                var final_case = true;
                if (switch_br.else_body_len > 0) {
                    var cases_it = switch_br.iterateCases();
                    while (cases_it.next()) |_| {}
                    try isel.body(cases_it.elseBody());
                    assert(final_case);
                    final_case = false;
                }
                var cases_it = switch_br.iterateCases();
                while (cases_it.next()) |case| {
                    wip_mir_log.debug("  case {d}:", .{case.idx});

                    const next_label = isel.instructions.items.len;
                    var next_snapshot = try isel.takeLocationSnapshot();
                    defer next_snapshot.deinit(isel);
                    tracking_log.debug("switch case snapshot taken:\n{f}", .{next_snapshot});
                    try isel.body(case.body);
                    try next_snapshot.merge(isel);
                    if (final_case) {
                        final_case = false;
                        continue;
                    }

                    const case_label = isel.instructions.items.len;

                    var cond_vi = try isel.use(switch_br.operand);
                    const cond_mat = try cond_vi.mat(isel, .{
                        .pref = .only_reg,
                        .reg_mod = .integer,
                        .extension = .zero_ext,
                    });

                    try isel.internal_relocs.append(gpa, .{
                        .label = @intCast(isel.instructions.items.len),
                        .target = next_label,
                    });
                    try isel.emit(.b(0, 0));

                    var case_range_index = case.ranges.len;
                    while (case_range_index > 0) {
                        case_range_index -= 1;
                        try isel.failUnimplemented("TODO switch_br range", .{});
                    }
                    var case_item_index = case.items.len;
                    while (case_item_index > 0) {
                        case_item_index -= 1;

                        const item_val: Constant = .fromInterned(case.items[case_item_index].toInterned().?);
                        var item_bigint_space: Constant.BigIntSpace = undefined;
                        const item_bigint = item_val.toBigInt(&item_bigint_space, zcu);
                        const item_int: i64 = if (item_bigint.positive) @bitCast(
                            item_bigint.toInt(u64) catch
                                return isel.fail("too big case item: {f}", .{isel.fmtConstant(item_val)}),
                        ) else item_bigint.toInt(i64) catch
                            return isel.fail("too big case item: {f}", .{isel.fmtConstant(item_val)});

                        const item_reg = try isel.allocRegForWrite(.int);
                        defer isel.freeReg(item_reg);

                        try isel.internal_relocs.append(gpa, .{
                            .label = @intCast(isel.instructions.items.len),
                            .target = case_label,
                        });
                        try isel.emit(.beq(cond_mat.reg(), item_reg, 0));
                        try isel.moveIntImm(item_reg, @bitCast(item_int));
                    }

                    try cond_mat.finish(isel);
                }
            },

            // Procedure call
            .call => {
                const pl_op = air.data(air.inst_index).pl_op;
                const extra = isel.air.extraData(Air.Call, pl_op.payload);
                const args: []const Air.Inst.Ref = @ptrCast(isel.air.extra.items[extra.end..][0..extra.data.args_len]);
                const callee_ty = isel.air.typeOf(pl_op.operand, ip);
                const func_info = switch (ip.indexToKey(callee_ty.toIntern())) {
                    else => unreachable,
                    .func_type => |func_type| func_type,
                    .ptr_type => |ptr_type| ip.indexToKey(ptr_type.child).func_type,
                };

                var cc_it: CallAbiIterator = .{ .isel = isel, .cc = &func_info.cc };

                // return
                try call.prepareReturn(isel);
                const ret_ty = isel.air.typeOfIndex(air.inst_index, ip);
                const maybe_def_ret_vi = isel.live_values.fetchRemove(air.inst_index);
                const ret_vi = try cc_it.resolve(ret_ty, true) orelse .free;
                defer if (ret_vi != .free) ret_vi.deref(isel);

                var def_ret_stack: Value.Indirect = .unallocated;
                if (maybe_def_ret_vi) |def_ret_vi| {
                    defer def_ret_vi.value.deref(isel);
                    assert(ret_vi != .free);
                    switch (ret_vi.parent(isel)) {
                        else => {
                            try def_ret_vi.value.defLiveIn(isel, ret_vi, .{});
                        },
                        .address => {
                            def_ret_stack = try def_ret_vi.value.defStack(isel) orelse ret_vi.allocStackSlot(isel);
                        },
                    }
                }
                try call.finishReturn(isel);

                // call
                try call.prepareCallee(isel);
                if (pl_op.operand.toInterned()) |ct_callee| {
                    try isel.emit(.jirl(.ra, .ra, 0));
                    try isel.nav_relocs.append(gpa, switch (ip.indexToKey(ct_callee)) {
                        else => unreachable,
                        inline .@"extern", .func => |func| .{
                            .nav = func.owner_nav,
                            .reloc = .{ .label = @intCast(isel.instructions.items.len) },
                        },
                        .ptr => |ptr| .{
                            .nav = ptr.base_addr.nav,
                            .reloc = .{
                                .label = @intCast(isel.instructions.items.len),
                                .addend = @intCast(ptr.byte_offset),
                            },
                        },
                    });
                    try isel.emit(.pcaddu18i(.ra, 0));
                } else {
                    const callee_vi = try isel.use(pl_op.operand);
                    const callee_mat = try callee_vi.matIntRegZeroExt(isel);
                    try isel.emit(.jirl(.ra, callee_mat.reg(), 0));
                    try callee_mat.finish(isel);
                }
                try call.finishCallee(isel);

                // params
                try call.prepareParams(isel);
                if (ret_vi != .free) switch (ret_vi.parent(isel)) {
                    else => {},
                    .address => |addr_vi| try call.paramAddress(isel, def_ret_stack, addr_vi),
                };
                for (args) |arg| {
                    const param_ty = isel.air.typeOf(arg, ip);
                    const param_vi = try cc_it.resolve(param_ty, false) orelse continue;
                    defer param_vi.deref(isel);
                    const arg_vi = try isel.use(arg);
                    try call.paramLiveOut(isel, arg_vi, param_vi);
                }
                try call.finishParams(isel);
            },

            // Stack allocation
            .alloc, .ret_ptr => if (isel.live_values.fetchRemove(air.inst_index)) |ptr_vi| unused: {
                defer ptr_vi.value.deref(isel);
                switch (air_tag) {
                    else => unreachable,
                    .alloc => {},
                    .ret_ptr => if (isel.live_values.get(Block.main)) |ret_vi| switch (ret_vi.parent(isel)) {
                        .none => {},
                        .value, .constant => unreachable,
                        .address => break :unused,
                    },
                }
                const ptr_reg = try ptr_vi.value.defRegMod(isel, .integer) orelse break :unused;

                const ty = air.data(air.inst_index).ty;
                const slot_size = ty.childType(zcu).abiSize(zcu);
                const slot_align = ty.ptrAlignment(zcu);
                const slot_offset = slot_align.forward(isel.stack_size);
                isel.stack_size = @intCast(slot_offset + slot_size);

                try isel.addImm(ptr_reg, .sp, slot_offset);
            },
            .inferred_alloc, .inferred_alloc_comptime => unreachable,

            // Assembly
            .assembly => {
                const unwrapped_asm = isel.air.unwrapAsm(air.inst_index);
                const inputs = unwrapped_asm.inputs;

                var as: Assemble = .{ .source = unwrapped_asm.source };
                defer as.deinit(gpa);

                var it = unwrapped_asm.iterateOutputs();
                while (it.next()) |output| {
                    const constraint = output.constraint;
                    const name = output.name;

                    switch (output.operand) {
                        else => return isel.fail("invalid constraint: '{s}'", .{constraint}),
                        .none => {
                            const output_reg = output_reg: {
                                if (std.mem.startsWith(u8, constraint, "={") and std.mem.endsWith(u8, constraint, "}")) {
                                    const output_reg = Register.parse(constraint["={".len .. constraint.len - "}".len]) orelse
                                        return isel.fail("invalid constraint: '{s}'", .{constraint});
                                    assert(try isel.fillReg(output_reg));
                                    isel.markRegWritten(output_reg);
                                    if (isel.live_values.fetchRemove(air.inst_index)) |output_vi| {
                                        defer output_vi.value.deref(isel);
                                        try output_vi.value.reextendToPcs(isel);
                                        if (try output_vi.value.def(isel)) |output_loc|
                                            try isel.moveLoc(
                                                .{ .register = .{ .mod = .integer, .reg = output_reg } },
                                                0,
                                                output_loc,
                                                0,
                                                output_vi.value.size(isel),
                                                .none,
                                            );
                                    }
                                    break :output_reg output_reg;
                                } else if (std.mem.eql(u8, constraint, "=r")) {
                                    if (isel.live_values.fetchRemove(air.inst_index)) |output_vi| {
                                        defer output_vi.value.deref(isel);
                                        try output_vi.value.reextendToPcs(isel);
                                        break :output_reg try output_vi.value.defRegMod(isel, .integer) orelse try isel.allocRegForWrite(.int);
                                    } else break :output_reg try isel.allocRegForWrite(.int);
                                } else return isel.fail("invalid constraint: '{s}'", .{constraint});
                            };
                            if (!std.mem.eql(u8, name, "_")) {
                                const arg_gop = try as.args.getOrPut(gpa, name);
                                if (arg_gop.found_existing) return isel.fail("duplicate output name: '{s}'", .{name});
                                arg_gop.value_ptr.* = .{ .register = output_reg };
                            }
                        },
                    }
                }

                const clobbers_val: Constant = .fromInterned(unwrapped_asm.clobbers);
                const clobbers_ty = clobbers_val.typeOf(zcu);
                var clobbers_bigint_buf: Constant.BigIntSpace = undefined;
                const clobbers_bigint = clobbers_val.toBigInt(&clobbers_bigint_buf, zcu);
                var clobbered_regs: RegisterSet = .empty;
                for (0..clobbers_ty.structFieldCount(zcu)) |field_index| {
                    assert(clobbers_ty.fieldType(field_index, zcu).toIntern() == .bool_type);
                    const limb_bits = @bitSizeOf(std.math.big.Limb);
                    if (field_index / limb_bits >= clobbers_bigint.limbs.len) continue; // field is false
                    switch (@as(u1, @truncate(clobbers_bigint.limbs[field_index / limb_bits] >> @intCast(field_index % limb_bits)))) {
                        0 => continue, // field is false
                        1 => {}, // field is true
                    }

                    const clobber_name = clobbers_ty.structFieldName(field_index, zcu).toSlice(ip).?;
                    if (std.mem.eql(u8, clobber_name, "memory")) continue;
                    if (std.mem.startsWith(u8, clobber_name, "fcsr")) continue;
                    const clobber_reg = Register.parse(clobber_name) orelse
                        return isel.fail("unable to parse clobber: '{s}'", .{clobber_name});
                    if (clobbered_regs.contains(clobber_reg))
                        return isel.fail("clobbered twice: '{t}'", .{clobber_reg});
                    clobbered_regs.insert(clobber_reg);
                }
                try isel.fillRegsBatch(clobbered_regs, true);
                isel.markRegsWritten(clobbered_regs);

                const InputMat = union(enum(u1)) {
                    reg: Register.Alias,
                    mat: Value.Mat,
                };
                const input_mats = try gpa.alloc(InputMat, inputs.len);
                defer gpa.free(input_mats);
                var index: u32 = 0;
                it = unwrapped_asm.iterateInputs();
                while (it.next()) |input| : (index += 1) {
                    const constraint = input.constraint;
                    const name = input.name;
                    const input_mat = &input_mats[index];

                    const input_vi = try isel.use(input.operand);
                    try input_vi.reextendToPcs(isel);

                    // TODO support X constraint
                    if (std.mem.startsWith(u8, constraint, "{") and std.mem.endsWith(u8, constraint, "}")) {
                        const input_reg = Register.parse(constraint["{".len .. constraint.len - "}".len]) orelse
                            return isel.fail("invalid constraint: '{s}'", .{constraint});
                        input_mat.* = .{ .reg = .{ .mod = .integer, .reg = input_reg } };
                    } else if (std.mem.eql(u8, constraint, "r")) {
                        const input_value_mat = try input_vi.mat(isel, .{
                            .pref = .only_reg,
                            .reg_mod = .integer,
                            .extension = if (input_vi.typeOf(isel)) |input_ty|
                                .pcsMode(isel, input_ty)
                            else
                                .zero_ext,
                        });
                        input_mat.* = .{ .mat = input_value_mat };
                    } else if (std.mem.eql(u8, name, "_")) {
                        input_mat.* = .{ .reg = .zero };
                    } else return isel.fail("invalid constraint: '{s}'", .{constraint});

                    if (!std.mem.eql(u8, name, "_")) {
                        const arg_gop = try as.args.getOrPut(gpa, name);
                        if (arg_gop.found_existing) return isel.fail("duplicate input name: '{s}'", .{name});
                        arg_gop.value_ptr.* = .{ .register = switch (input_mat.*) {
                            .reg => |input_ra| input_ra.reg,
                            .mat => |input_val_mat| input_val_mat.reg(),
                        } };
                    }
                }

                const asm_start = isel.instructions.items.len;
                while (instruction: {
                    const line = as.nextLine();
                    break :instruction as.parseLine(line) catch |err| switch (err) {
                        error.InvalidSyntax => {
                            if (debug_trap_unimplemented_code) {
                                wip_mir_log.err("unable to assemble: '{s}'", .{std.mem.trim(
                                    u8,
                                    line,
                                    &std.ascii.whitespace,
                                )});
                                break :instruction Instruction.@"break"(0xaa);
                            } else return isel.fail("unable to assemble: '{s}'", .{std.mem.trim(
                                u8,
                                line,
                                &std.ascii.whitespace,
                            )});
                        },
                    };
                }) |instruction| try isel.emit(instruction);
                std.mem.reverse(Instruction, isel.instructions.items[asm_start..]);

                it = unwrapped_asm.iterateInputs();
                index = 0;
                while (it.next()) |input| : (index += 1) {
                    const input_mat = &input_mats[index];
                    const input_vi = try isel.use(input.operand);
                    switch (input_mat.*) {
                        .reg => |input_ra| {
                            const input_val_mat = try input_vi.mat(isel, .{
                                .pref = .prefer_reg,
                                .hint_ra = input_ra,
                            });
                            const input_val_loc = input_val_mat.loc();
                            const dst_loc: Value.Location = .{ .register = input_ra };
                            if (!std.meta.eql(input_val_loc, dst_loc)) {
                                dst_loc.markRegWritten(isel);
                                try isel.moveLoc(dst_loc, 0, input_val_loc, 0, input_ra.mod.byteSize(isel.target), .none);
                            }
                            try input_val_mat.finish(isel);
                        },
                        .mat => |input_val_mat| try input_val_mat.finish(isel),
                    }
                }

                var clobber_regs_it = clobbered_regs.iterator();
                while (clobber_regs_it.next()) |clobber_reg| isel.freeReg(clobber_reg);
            },

            // Arithmetic
            .add, .add_safe, .add_optimized, .add_wrap, .sub, .sub_safe, .sub_optimized, .sub_wrap => if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| {
                defer res_vi.value.deref(isel);

                const bin_op = air.data(air.inst_index).bin_op;
                const ty = isel.air.typeOf(bin_op.lhs, ip);
                if (!ty.isRuntimeFloat()) try isel.addOrSubtract(ty, res_vi.value, switch (air_tag) {
                    else => unreachable,
                    .add, .add_safe, .add_wrap => .add,
                    .sub, .sub_safe, .sub_wrap => .sub,
                }, try isel.use(bin_op.lhs), try isel.use(bin_op.rhs), .{
                    .overflow = switch (air_tag) {
                        else => unreachable,
                        .add, .sub => .@"unreachable",
                        .add_safe, .sub_safe => .{ .panic = .integer_overflow },
                        .add_wrap, .sub_wrap => .wrap,
                    },
                }) else return isel.fail("unimplemented float", .{});
            },
            .not => if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const src_vi = try isel.use(ty_op.operand);
                const ty = ty_op.ty.toType();
                switch (ty.zigTypeTag(zcu)) {
                    .bool => {
                        // boolean not
                        try res_vi.value.reextend(isel, .zero_ext);
                        const res_reg = try res_vi.value.defRegMod(isel, .integer) orelse break :unused;
                        // TODO optimize fcc path
                        const src_mat = try src_vi.matIntRegZeroExt(isel);
                        const src_reg = src_mat.reg();
                        try isel.emit(.xori(res_reg, src_reg, 1));
                        try src_mat.finish(isel);
                    },
                    .int => {
                        // bitwise not
                        var res_walk = res_vi.value.walk(isel, .{});
                        const gpr_size = isel.gprSize();
                        while (res_walk.next()) |res_part_vi| {
                            if (res_part_vi.size(isel) > gpr_size) continue;
                            res_walk.skipChildren(res_part_vi);
                            const res_part_ra = try res_part_vi.defReg(isel) orelse continue;
                            const src_part_mat = try src_vi.mat(isel, .{
                                .offset = res_part_vi.offsetIn(isel, res_vi.value),
                                .size = @intCast(res_part_vi.size(isel)),
                                .pref = .only_reg,
                                .reg_mod = res_part_ra.mod,
                            });
                            const src_part_reg = src_part_mat.reg();
                            switch (res_part_ra.mod) {
                                .undef => unreachable,
                                .integer => try isel.emit(.nor(res_part_ra.reg, src_part_reg, .zero)),
                                else => return isel.fail("unimplemented not {t}", .{res_part_ra.mod}),
                            }
                            try src_part_mat.finish(isel);
                        }
                    },
                    else => |ty_tag| return isel.fail("unimplemented not on {t}", .{ty_tag}),
                }
            },
            .trunc => if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| {
                defer res_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const src_vi = try isel.use(ty_op.operand);
                const src_ty = ty_op.ty.toType();
                const src_bits = src_ty.bitSize(zcu);
                try res_vi.value.reextendAdvanced(
                    isel,
                    src_bits,
                    src_vi.extension(isel),
                    res_vi.value.extension(isel),
                );
                try res_vi.value.defCopy(isel, src_vi);
            },
            .div_trunc, .div_trunc_optimized, .div_floor, .div_floor_optimized, .div_exact, .div_exact_optimized => if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const bin_op = air.data(air.inst_index).bin_op;
                const ty = isel.air.typeOf(bin_op.lhs, ip);
                if (!ty.isRuntimeFloat()) {
                    if (!ty.isAbiInt(zcu)) return isel.fail("bad {t} {f}", .{ air_tag, isel.fmtType(ty) });
                    const int_info = ty.intInfo(zcu);
                    switch (int_info.bits) {
                        0 => unreachable,
                        1...64 => |bits| {
                            const res_reg = try res_vi.value.defRegMod(isel, .integer) orelse break :unused;
                            const lhs_vi = try isel.use(bin_op.lhs);
                            const rhs_vi = try isel.use(bin_op.rhs);
                            const mat_opts: Value.Index.MatOptions = .{
                                .pref = .only_reg,
                                .reg_mod = .integer,
                                .extension = ext_mode: {
                                    if (bits == 32 and isel.hasCpuFeature(.@"64bit") and isel.hasCpuFeature(.div32)) {
                                        break :ext_mode .garbage;
                                    }
                                    break :ext_mode .fromSignedness(int_info.signedness);
                                },
                            };
                            const lhs_mat = try lhs_vi.mat(isel, mat_opts);
                            const rhs_mat = try rhs_vi.mat(isel, mat_opts);
                            const lhs_reg = lhs_mat.reg();
                            const rhs_reg = rhs_mat.reg();

                            switch (bits) {
                                else => unreachable,
                                1...32 => try isel.emit(switch (int_info.signedness) {
                                    .signed => .@"div.w"(res_reg, lhs_reg, rhs_reg),
                                    .unsigned => .@"div.wu"(res_reg, lhs_reg, rhs_reg),
                                }),
                                33...64 => if (isel.hasCpuFeature(.@"64bit")) {
                                    try isel.emit(switch (int_info.signedness) {
                                        .signed => .@"div.d"(res_reg, lhs_reg, rhs_reg),
                                        .unsigned => .@"div.du"(res_reg, lhs_reg, rhs_reg),
                                    });
                                } else return isel.fail("unimplemented 64bit division on LA32", .{}),
                            }
                            try rhs_mat.finish(isel);
                            try lhs_mat.finish(isel);
                        },
                        else => try isel.failUnimplemented("too big {t} {f}", .{ air_tag, isel.fmtType(ty) }),
                    }
                } else try isel.failUnimplemented("unimplemented float div", .{});
            },
            .bit_cast,
            .ptr_cast,
            .ptr_from_int,
            .int_from_ptr,
            .error_cast,
            .error_from_int,
            .int_from_error,
            .union_from_enum,
            => if (isel.live_values.fetchRemove(air.inst_index)) |dst_vi| unused: {
                defer dst_vi.value.deref(isel);
                const ty_op = air.data(air.inst_index).ty_op;
                const dst_ty = ty_op.ty.toType();
                const dst_tag = dst_ty.zigTypeTag(zcu);
                const src_ty = isel.air.typeOf(ty_op.operand, ip);
                const src_tag = src_ty.zigTypeTag(zcu);

                if ((dst_tag == .bool or dst_ty.isAbiInt(zcu)) and (src_tag == .bool or src_ty.isAbiInt(zcu))) {
                    const dst_int_info: std.builtin.Type.Int = if (dst_tag == .bool) .{ .signedness = .unsigned, .bits = 1 } else dst_ty.intInfo(zcu);
                    const src_int_info: std.builtin.Type.Int = if (src_tag == .bool) .{ .signedness = .unsigned, .bits = 1 } else src_ty.intInfo(zcu);
                    assert(dst_int_info.bits == src_int_info.bits);
                    if (dst_tag != .@"struct" and src_tag != .@"struct") {
                        try dst_vi.value.defMove(isel, ty_op.operand);
                    } else switch (dst_int_info.bits) {
                        0 => unreachable,
                        1...31, 33...63 => |bits| {
                            try dst_vi.value.reextendToGarbage(isel);
                            const dst_reg = try dst_vi.value.defRegMod(isel, .integer) orelse break :unused;
                            const src_vi = try isel.use(ty_op.operand);
                            const src_mat = try src_vi.matReg(isel);
                            try isel.fillUnusedBits(
                                dst_reg,
                                src_mat.reg(),
                                .fromSignedness(dst_int_info.signedness),
                                .fromSignedness(src_int_info.signedness),
                                @intCast(bits),
                            );
                            try src_mat.finish(isel);
                        },
                        32, 64 => try dst_vi.value.defMove(isel, ty_op.operand),
                        else => return isel.fail("unimplemented {t} {f} {f}", .{ air_tag, isel.fmtType(dst_ty), isel.fmtType(src_ty) }),
                    }
                } else if ((dst_ty.isPtrAtRuntime(zcu) or dst_ty.isAbiInt(zcu)) and (src_ty.isPtrAtRuntime(zcu) or src_ty.isAbiInt(zcu))) {
                    try dst_vi.value.defMove(isel, ty_op.operand);
                } else if (dst_ty.isSliceAtRuntime(zcu) and src_ty.isSliceAtRuntime(zcu)) {
                    try dst_vi.value.defMove(isel, ty_op.operand);
                } else if (dst_tag == .error_union and src_tag == .error_union) {
                    assert(dst_ty.errorUnionSet(zcu).hasRuntimeBits(zcu) ==
                        src_ty.errorUnionSet(zcu).hasRuntimeBits(zcu));
                    if (dst_ty.errorUnionPayload(zcu).toIntern() == src_ty.errorUnionPayload(zcu).toIntern()) {
                        try dst_vi.value.defMove(isel, ty_op.operand);
                    } else return isel.fail("bad {t} {f} {f}", .{ air_tag, isel.fmtType(dst_ty), isel.fmtType(src_ty) });
                } else if (dst_tag == .float and src_tag == .float) {
                    assert(dst_ty.floatBits(isel.target) == src_ty.floatBits(isel.target));
                    try dst_vi.value.defMove(isel, ty_op.operand);
                } else if (dst_ty.isAbiInt(zcu) and src_tag == .float) {
                    const dst_int_info = dst_ty.intInfo(zcu);
                    assert(dst_int_info.bits == src_ty.floatBits(isel.target));

                    try dst_vi.value.reextendToGarbage(isel);
                    const dst_reg = try dst_vi.value.defRegMod(isel, .fromFloating(dst_int_info.bits)) orelse break :unused;
                    const src_vi = try isel.use(ty_op.operand);
                    const src_mat = try src_vi.matReg(isel);
                    const src_reg = src_mat.reg();
                    try isel.emit(switch (dst_int_info.bits) {
                        else => unreachable,
                        32 => .@"movfr2gr.s"(dst_reg, src_reg),
                        64 => .@"movfr2gr.d"(dst_reg, src_reg),
                    });
                    try src_mat.finish(isel);
                } else if (dst_tag == .float and src_ty.isAbiInt(zcu)) {
                    const src_int_info = src_ty.intInfo(zcu);
                    assert(dst_ty.floatBits(isel.target) == src_int_info.bits);

                    try dst_vi.value.reextendToGarbage(isel);
                    const dst_reg = try dst_vi.value.defRegMod(isel, .fromFloating(src_int_info.bits)) orelse break :unused;
                    const src_vi = try isel.use(ty_op.operand);
                    const src_mat = try src_vi.matReg(isel);
                    const src_reg = src_mat.reg();
                    try isel.emit(switch (src_int_info.bits) {
                        else => unreachable,
                        32 => .@"movgr2fr.w"(dst_reg, src_reg),
                        64 => .@"movfr2gr.d"(dst_reg, src_reg),
                    });
                    try src_mat.finish(isel);
                } else if (dst_ty.isAbiInt(zcu) and src_tag == .array and src_ty.childType(zcu).isAbiInt(zcu)) {
                    const dst_int_info = dst_ty.intInfo(zcu);
                    const src_child_int_info = src_ty.childType(zcu).intInfo(zcu);
                    const src_len = src_ty.arrayLenIncludingSentinel(zcu);
                    assert(dst_int_info.bits == src_child_int_info.bits * src_len);
                    const src_child_size = src_ty.childType(zcu).abiSize(zcu);
                    if (8 * src_child_size == src_child_int_info.bits) {
                        const src_vi = try isel.use(ty_op.operand);
                        try dst_vi.value.defCopy(isel, src_vi);
                    } else return isel.fail("bad {t} {f} {f}", .{ air_tag, isel.fmtType(dst_ty), isel.fmtType(src_ty) });
                } else if (dst_tag == .array and dst_ty.childType(zcu).isAbiInt(zcu) and src_ty.isAbiInt(zcu)) {
                    const dst_child_int_info = dst_ty.childType(zcu).intInfo(zcu);
                    const src_int_info = src_ty.intInfo(zcu);
                    const dst_len = dst_ty.arrayLenIncludingSentinel(zcu);
                    assert(dst_child_int_info.bits * dst_len == src_int_info.bits);
                    const dst_child_size = dst_ty.childType(zcu).abiSize(zcu);
                    if (8 * dst_child_size == dst_child_int_info.bits) {
                        const src_vi = try isel.use(ty_op.operand);
                        try dst_vi.value.defCopy(isel, src_vi);
                    } else return isel.fail("bad {t} {f} {f}", .{ air_tag, isel.fmtType(dst_ty), isel.fmtType(src_ty) });
                } else if (dst_tag == .array and dst_ty.childType(zcu).isAbiInt(zcu) and
                    src_tag == .array and src_ty.childType(zcu).isAbiInt(zcu))
                {
                    const dst_child_int_info = dst_ty.childType(zcu).intInfo(zcu);
                    const dst_len = dst_ty.arrayLenIncludingSentinel(zcu);
                    const src_child_int_info = src_ty.childType(zcu).intInfo(zcu);
                    const src_len = src_ty.arrayLenIncludingSentinel(zcu);
                    assert(dst_child_int_info.bits * dst_len == src_child_int_info.bits * src_len);
                    const dst_child_size = dst_ty.childType(zcu).abiSize(zcu);
                    const src_child_size = src_ty.childType(zcu).abiSize(zcu);
                    if (8 * dst_child_size == dst_child_int_info.bits and 8 * src_child_size == src_child_int_info.bits) {
                        const src_vi = try isel.use(ty_op.operand);
                        try dst_vi.value.defCopy(isel, src_vi);
                    } else return isel.fail("bad {t} {f} {f}", .{ air_tag, isel.fmtType(dst_ty), isel.fmtType(src_ty) });
                } else return isel.fail("unimplemented {t} {f} {f}", .{ air_tag, isel.fmtType(dst_ty), isel.fmtType(src_ty) });
            },
            .bit_and, .bit_or, .xor => if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| {
                defer res_vi.value.deref(isel);

                const bin_op = air.data(air.inst_index).bin_op;

                const lhs_vi = try isel.use(bin_op.lhs);
                const rhs_vi = try isel.use(bin_op.rhs);

                const lhs_ext_mode = lhs_vi.extension(isel);
                const rhs_ext_mode = rhs_vi.extension(isel);
                try res_vi.value.reextend(isel, res_ext_mode: switch (air_tag) {
                    else => unreachable,
                    .bit_and => {
                        if (lhs_ext_mode == rhs_ext_mode) break :res_ext_mode lhs_ext_mode;
                        if (lhs_ext_mode == .zero_ext or rhs_ext_mode == .zero_ext) break :res_ext_mode .zero_ext;
                        break :res_ext_mode .garbage;
                    },
                    .bit_or => if (lhs_ext_mode == rhs_ext_mode) lhs_ext_mode else .garbage,
                    .xor => .garbage,
                });

                var res_walk = res_vi.value.walk(isel, .{});
                const gpr_size = isel.gprSize();
                while (res_walk.next()) |res_part_vi| {
                    if (res_part_vi.size(isel) > gpr_size) continue;
                    res_walk.skipChildren(res_part_vi);
                    const part_offset = res_part_vi.offsetIn(isel, res_vi.value);
                    const part_size = res_part_vi.size(isel);
                    // TODO implement vectors
                    const res_part_ra = try res_part_vi.defReg(isel) orelse continue;
                    const res_part_reg = res_part_ra.reg;
                    const lhs_part_mat = try lhs_vi.mat(isel, .{
                        .offset = part_offset,
                        .size = @intCast(part_size),
                        .pref = .only_reg,
                        .reg_mod = res_part_ra.mod,
                    });
                    const lhs_part_reg = lhs_part_mat.reg();
                    const rhs_part_mat = try lhs_vi.mat(isel, .{
                        .offset = part_offset,
                        .size = @intCast(part_size),
                        .pref = .only_reg,
                        .reg_mod = res_part_ra.mod,
                    });
                    const rhs_part_reg = rhs_part_mat.reg();

                    try isel.emit(switch (air_tag) {
                        else => unreachable,
                        .bit_and => .@"and"(res_part_reg, lhs_part_reg, rhs_part_reg),
                        .bit_or => .@"or"(res_part_reg, lhs_part_reg, rhs_part_reg),
                        .xor => .xor(res_part_reg, lhs_part_reg, rhs_part_reg),
                    });
                    try rhs_part_mat.finish(isel);
                    try lhs_part_mat.finish(isel);
                }
            },
            .cmp_lt, .cmp_lte, .cmp_eq, .cmp_gte, .cmp_gt, .cmp_neq => if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const bin_op = air.data(air.inst_index).bin_op;
                const ty = isel.air.typeOf(bin_op.lhs, ip);
                const lhs_vi = try isel.use(bin_op.lhs);
                const rhs_vi = try isel.use(bin_op.rhs);

                switch (ip.indexToKey(ty.toIntern())) {
                    else => {},
                    .opt_type => |payload_ty| switch (air_tag) {
                        else => unreachable,
                        .cmp_eq, .cmp_neq => if (!ty.optionalReprIsPayload(zcu)) {
                            const payload_size = ZigType.abiSize(.fromInterned(payload_ty), zcu);
                            try res_vi.value.reextendToGarbage(isel);
                            const res_reg = try res_vi.value.defRegMod(isel, .integer) orelse break :unused;

                            const cmp_label = isel.instructions.items.len;
                            try isel.cmp(
                                res_reg,
                                .fromInterned(payload_ty),
                                try lhs_vi.partExact(isel, 0, payload_size),
                                air_tag.toCmpOp().?,
                                try rhs_vi.partExact(isel, 0, payload_size),
                            );
                            const lhs_tag_mat = try lhs_vi.mat(isel, .{
                                .offset = payload_size,
                                .size = 1,
                                .pref = .only_reg,
                                .reg_mod = .integer,
                                .extension = .zero_ext,
                            });
                            const rhs_tag_mat = try rhs_vi.mat(isel, .{
                                .offset = payload_size,
                                .size = 1,
                                .pref = .only_reg,
                                .reg_mod = .integer,
                                .extension = .zero_ext,
                            });
                            try isel.internal_relocs.append(gpa, .{
                                .label = @intCast(isel.instructions.items.len),
                                .target = cmp_label,
                            });
                            try isel.emit(.beqz(lhs_tag_mat.reg(), 0, 0));
                            try isel.internal_relocs.append(gpa, .{
                                .label = @intCast(isel.instructions.items.len),
                                .target = cmp_label,
                            });
                            try isel.emit(.beqz(res_reg, 0, 0));

                            try isel.emit(.xori(res_reg, res_reg, 1));
                            try isel.emit(.xor(res_reg, lhs_tag_mat.reg(), rhs_tag_mat.reg()));
                            try rhs_tag_mat.finish(isel);
                            try lhs_tag_mat.finish(isel);
                            break :unused;
                        },
                    },
                }

                // TODO optimize fcc path
                try res_vi.value.reextendToPcs(isel);
                try isel.cmp(
                    try res_vi.value.defRegMod(isel, .integer) orelse break :unused,
                    ty,
                    lhs_vi,
                    air_tag.toCmpOp().?,
                    rhs_vi,
                );
            },
            .store, .store_safe, .atomic_store_unordered => unused: {
                const bin_op = air.data(air.inst_index).bin_op;
                const ptr_ty = isel.air.typeOf(bin_op.lhs, ip);
                const ptr_info = ptr_ty.ptrInfo(zcu);
                if (ptr_info.packed_offset.host_size > 0) return isel.fail("packed store", .{});
                if (bin_op.rhs.toInterned()) |rhs_val| if (ip.isUndef(rhs_val)) break :unused;

                const src_vi = try isel.use(bin_op.rhs);
                const ptr_vi = try isel.use(bin_op.lhs);
                const ptr_mat = try ptr_vi.matReg(isel);
                try src_vi.matStore(isel, ptr_mat.reg(), 0, .{
                    .@"volatile" = ptr_info.flags.is_volatile,
                });
                try ptr_mat.finish(isel);
            },
            .load => {
                const ty_op = air.data(air.inst_index).ty_op;
                const ptr_ty = isel.air.typeOf(ty_op.operand, ip);
                const ptr_info = ptr_ty.ptrInfo(zcu);
                if (ptr_info.packed_offset.host_size > 0) return isel.fail("packed load", .{});

                if (ptr_info.flags.is_volatile) _ = try isel.use(air.inst_index.toRef());
                if (isel.live_values.fetchRemove(air.inst_index)) |dst_vi| {
                    defer dst_vi.value.deref(isel);

                    // TODO unaligned loads
                    assert(isel.target.cpu.has(.loongarch, .ual));
                    const ptr_vi = try isel.use(ty_op.operand);
                    const ptr_mat = try ptr_vi.matIntRegZeroExt(isel);
                    _ = try dst_vi.value.defLoad(isel, ptr_mat.reg(), 0, .{
                        .@"volatile" = ptr_info.flags.is_volatile,
                    });
                    try ptr_mat.finish(isel);
                }
            },
            .int_cast => if (isel.live_values.fetchRemove(air.inst_index)) |dst_vi| {
                defer dst_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const dst_ty = ty_op.ty.toType();
                const dst_int_info = dst_ty.intInfo(zcu);
                const src_ty = isel.air.typeOf(ty_op.operand, ip);
                const src_int_info = src_ty.intInfo(zcu);

                if (dst_int_info.bits == src_int_info.bits) {
                    try dst_vi.value.defMove(isel, ty_op.operand);
                } else {
                    const src_vi = try isel.use(ty_op.operand);
                    try dst_vi.value.reextendAdvanced(isel, src_int_info.bits, null, src_vi.extension(isel));
                    try dst_vi.value.defCopy(isel, src_vi);
                }
            },
            .is_null, .is_non_null => if (isel.live_values.fetchRemove(air.inst_index)) |is_vi| unused: {
                defer is_vi.value.deref(isel);
                const is_reg = try is_vi.value.defRegMod(isel, .integer) orelse break :unused;

                const un_op = air.data(air.inst_index).un_op;
                const opt_ty = isel.air.typeOf(un_op, ip);
                const payload_ty = opt_ty.optionalChild(zcu);
                const payload_size = payload_ty.abiSize(zcu);
                const has_value_offset, const has_value_size = if (!opt_ty.optionalReprIsPayload(zcu))
                    .{ payload_size, 1 }
                else if (payload_ty.isSlice(zcu))
                    .{ 0, 8 }
                else
                    .{ 0, @as(u32, @intCast(payload_size)) };

                const opt_vi = try isel.use(un_op);
                const has_value_mat = try opt_vi.mat(isel, .{
                    .offset = has_value_offset,
                    .size = has_value_size,
                    .pref = .only_reg,
                    .reg_mod = .integer,
                    .extension = .zero_ext,
                    .hint_ra = .{ .reg = is_reg, .mod = .integer },
                });
                const has_value_reg = has_value_mat.reg();
                try isel.emit(switch (air_tag) {
                    else => unreachable,
                    .is_null => .sltui(is_reg, has_value_reg, 1),
                    .is_non_null => .sltu(is_reg, .zero, has_value_reg),
                });
                try has_value_mat.finish(isel);
            },
            .is_err, .is_non_err => if (isel.live_values.fetchRemove(air.inst_index)) |is_vi| unused: {
                defer is_vi.value.deref(isel);
                const is_reg = try is_vi.value.defRegMod(isel, .integer) orelse break :unused;

                const un_op = air.data(air.inst_index).un_op;
                const error_union_ty = isel.air.typeOf(un_op, ip);
                const error_union_info = ip.indexToKey(error_union_ty.toIntern()).error_union_type;
                const error_set_ty: ZigType = .fromInterned(error_union_info.error_set_type);
                const payload_ty: ZigType = .fromInterned(error_union_info.payload_type);
                const error_set_offset = codegen.errUnionErrorOffset(payload_ty, zcu);
                const error_set_size = error_set_ty.abiSize(zcu);

                const error_union_vi = try isel.use(un_op);
                const error_set_mat = try error_union_vi.mat(isel, .{
                    .offset = error_set_offset,
                    .size = @intCast(error_set_size),
                    .pref = .only_reg,
                    .reg_mod = .integer,
                    .hint_ra = .{ .reg = is_reg, .mod = .integer },
                });
                try isel.emit(switch (air_tag) {
                    else => unreachable,
                    .is_err => .sltu(is_reg, .zero, is_reg),
                    .is_non_err => .sltui(is_reg, is_reg, 1),
                });
                try error_set_mat.finish(isel);
            },
            .max, .min => if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);

                const bin_op = air.data(air.inst_index).bin_op;
                const ty = isel.air.typeOf(bin_op.lhs, ip);
                if (!ty.isRuntimeFloat()) {
                    if (!ty.isAbiInt(zcu)) return isel.fail("bad {t} {f}", .{ air_tag, isel.fmtType(ty) });
                    const int_info = ty.intInfo(zcu);
                    if (int_info.bits > 64) return isel.fail("too big {t} {f}", .{ air_tag, isel.fmtType(ty) });

                    try res_vi.value.reextendToGarbage(isel);
                    const res_reg = try res_vi.value.defRegMod(isel, .integer) orelse break :unused;
                    const lhs_vi = try isel.use(bin_op.lhs);
                    // TODO: relax LHS and RHS requirements to "not garbage filled"
                    const lhs_mat = try lhs_vi.matIntRegZeroExt(isel);
                    const lhs_reg = lhs_mat.reg();
                    const rhs_vi = try isel.use(bin_op.rhs);
                    const rhs_mat = try rhs_vi.matIntRegZeroExt(isel);
                    const rhs_reg = rhs_mat.reg();

                    const tmp_reg = try isel.allocRegForWrite(.int);
                    defer isel.freeReg(tmp_reg);
                    const cond_reg = try isel.allocRegForWrite(.int);
                    defer isel.freeReg(cond_reg);

                    try isel.emit(.@"or"(res_reg, res_reg, tmp_reg));
                    try isel.emit(.maskeqz(res_reg, lhs_reg, cond_reg));
                    try isel.emit(.masknez(tmp_reg, rhs_reg, cond_reg));
                    switch (air_tag) {
                        else => unreachable,
                        .min => try isel.emit(.sltu(cond_reg, lhs_reg, rhs_reg)),
                        .max => try isel.emit(.sltu(cond_reg, rhs_reg, lhs_reg)),
                    }

                    try rhs_mat.finish(isel);
                    try lhs_mat.finish(isel);
                } else switch (ty.floatBits(isel.target)) {
                    else => unreachable,
                    32, 64 => return isel.fail("TODO float min/max", .{}),
                }
            },
            .slice => if (isel.live_values.fetchRemove(air.inst_index)) |slice_vi| {
                defer slice_vi.value.deref(isel);
                const ty_pl = air.data(air.inst_index).ty_pl;
                const bin_op = isel.air.extraData(Air.Bin, ty_pl.payload).data;
                const gpr_size = isel.gprSize();
                const ptr_part_vi = try slice_vi.value.partExact(isel, 0, gpr_size);
                try ptr_part_vi.defMove(isel, bin_op.lhs);
                const len_part_vi = try slice_vi.value.partExact(isel, gpr_size, gpr_size);
                try len_part_vi.defMove(isel, bin_op.rhs);
            },
            .slice_ptr => if (isel.live_values.fetchRemove(air.inst_index)) |ptr_vi| {
                defer ptr_vi.value.deref(isel);
                const ty_op = air.data(air.inst_index).ty_op;
                const gpr_size = isel.gprSize();
                const slice_vi = try isel.use(ty_op.operand);
                const ptr_part_vi = try slice_vi.partExact(isel, 0, gpr_size);
                try ptr_vi.value.defCopy(isel, ptr_part_vi);
            },
            .slice_len => if (isel.live_values.fetchRemove(air.inst_index)) |len_vi| {
                defer len_vi.value.deref(isel);
                const ty_op = air.data(air.inst_index).ty_op;
                const gpr_size = isel.gprSize();
                const slice_vi = try isel.use(ty_op.operand);
                const len_part_vi = try slice_vi.partExact(isel, gpr_size, gpr_size);
                try len_vi.value.defCopy(isel, len_part_vi);
            },
            .ptr_slice_ptr_ptr => if (isel.live_values.fetchRemove(air.inst_index)) |dst_vi| {
                defer dst_vi.value.deref(isel);
                const ty_op = air.data(air.inst_index).ty_op;
                try dst_vi.value.defMove(isel, ty_op.operand);
            },
            .ptr_slice_len_ptr => if (isel.live_values.fetchRemove(air.inst_index)) |dst_vi| unused: {
                defer dst_vi.value.deref(isel);
                const ty_op = air.data(air.inst_index).ty_op;
                const dst_reg = try dst_vi.value.defRegMod(isel, .integer) orelse break :unused;
                const src_vi = try isel.use(ty_op.operand);
                const src_mat = try src_vi.matIntRegZeroExt(isel);
                const src_reg = src_mat.reg();
                switch (isel.gprSize()) {
                    else => unreachable,
                    4 => try isel.emit(.@"addi.w"(dst_reg, src_reg, 4)),
                    8 => try isel.emit(.@"addi.d"(dst_reg, src_reg, 8)),
                }
                try src_mat.finish(isel);
            },
            .slice_elem_val => if (isel.live_values.fetchRemove(air.inst_index)) |elem_vi| unused: {
                defer elem_vi.value.deref(isel);

                const bin_op = air.data(air.inst_index).bin_op;
                const slice_ty = isel.air.typeOf(bin_op.lhs, ip);
                const ptr_info = slice_ty.ptrInfo(zcu);
                const elem_size = elem_vi.value.size(isel);

                const elem_ptr_reg = try isel.allocRegForWrite(.int);
                defer isel.freeReg(elem_ptr_reg);

                if (!try elem_vi.value.defLoad(isel, elem_ptr_reg, 0, .{
                    .@"volatile" = ptr_info.flags.is_volatile,
                })) break :unused;

                const slice_vi = try isel.use(bin_op.lhs);
                const base_ptr_mat = try slice_vi.mat(isel, .{
                    .offset = 0,
                    .size = isel.gprSize(),
                    .pref = .only_reg,
                    .reg_mod = .integer,
                });
                const index_vi = try isel.use(bin_op.rhs);
                try isel.elemPtr(elem_ptr_reg, base_ptr_mat.reg(), .add, elem_size, index_vi);
                try base_ptr_mat.finish(isel);
            },
            .slice_elem_ptr => if (isel.live_values.fetchRemove(air.inst_index)) |elem_ptr_vi| unused: {
                defer elem_ptr_vi.value.deref(isel);
                const elem_ptr_reg = try elem_ptr_vi.value.defRegMod(isel, .integer) orelse break :unused;

                const ty_pl = air.data(air.inst_index).ty_pl;
                const bin_op = isel.air.extraData(Air.Bin, ty_pl.payload).data;
                const elem_size = ty_pl.ty.toType().childType(zcu).abiSize(zcu);

                const slice_vi = try isel.use(bin_op.lhs);
                const base_ptr_mat = try slice_vi.mat(isel, .{
                    .offset = 0,
                    .size = isel.gprSize(),
                    .pref = .only_reg,
                    .reg_mod = .integer,
                });
                const index_vi = try isel.use(bin_op.rhs);
                try isel.elemPtr(elem_ptr_reg, base_ptr_mat.reg(), .add, elem_size, index_vi);
                try base_ptr_mat.finish(isel);
            },
            .ptr_add, .ptr_sub => if (isel.live_values.fetchRemove(air.inst_index)) |res_vi| unused: {
                defer res_vi.value.deref(isel);
                const res_reg = try res_vi.value.defRegMod(isel, .integer) orelse break :unused;

                const ty_pl = air.data(air.inst_index).ty_pl;
                const bin_op = isel.air.extraData(Air.Bin, ty_pl.payload).data;
                const elem_size = ty_pl.ty.toType().childType(zcu).abiSize(zcu);

                const base_vi = try isel.use(bin_op.lhs);
                const base_ptr_mat = try base_vi.mat(isel, .{
                    .offset = 0,
                    .size = isel.gprSize(),
                    .pref = .only_reg,
                    .reg_mod = .integer,
                });
                const index_vi = try isel.use(bin_op.rhs);
                try isel.elemPtr(res_reg, base_ptr_mat.reg(), switch (air_tag) {
                    else => unreachable,
                    .ptr_add => .add,
                    .ptr_sub => .sub,
                }, elem_size, index_vi);
                try base_ptr_mat.finish(isel);
            },
            .ptr_elem_ptr => if (isel.live_values.fetchRemove(air.inst_index)) |elem_ptr_vi| unused: {
                defer elem_ptr_vi.value.deref(isel);
                const elem_ptr_reg = try elem_ptr_vi.value.defRegMod(isel, .integer) orelse break :unused;

                const ty_pl = air.data(air.inst_index).ty_pl;
                const bin_op = isel.air.extraData(Air.Bin, ty_pl.payload).data;
                const elem_size = ty_pl.ty.toType().childType(zcu).abiSize(zcu);

                const base_vi = try isel.use(bin_op.lhs);
                const base_mat = try base_vi.matIntRegZeroExt(isel);
                const index_vi = try isel.use(bin_op.rhs);
                try isel.elemPtr(elem_ptr_reg, base_mat.reg(), .add, elem_size, index_vi);
                try base_mat.finish(isel);
            },
            .array_to_slice => if (isel.live_values.fetchRemove(air.inst_index)) |slice_vi| {
                defer slice_vi.value.deref(isel);
                const ty_op = air.data(air.inst_index).ty_op;
                const gpr_size = isel.gprSize();
                const array_len = isel.air.typeOf(ty_op.operand, ip).childType(zcu).arrayLen(zcu);

                const len_part_vi = try slice_vi.value.partExact(isel, gpr_size, gpr_size);
                if (try len_part_vi.defRegMod(isel, .integer)) |len_reg|
                    try isel.moveIntImm(len_reg, @bitCast(array_len));

                const ptr_part_vi = try slice_vi.value.partExact(isel, 0, gpr_size);
                try ptr_part_vi.defMove(isel, ty_op.operand);
            },
            .@"try", .try_cold => {
                const pl_op = air.data(air.inst_index).pl_op;
                const extra = isel.air.extraData(Air.Try, pl_op.payload);
                const error_union_ty = isel.air.typeOf(pl_op.operand, ip);
                const error_union_info = ip.indexToKey(error_union_ty.toIntern()).error_union_type;
                const payload_ty: ZigType = .fromInterned(error_union_info.payload_type);

                const error_union_vi = try isel.use(pl_op.operand);
                if (isel.live_values.fetchRemove(air.inst_index)) |payload_vi| {
                    defer payload_vi.value.deref(isel);

                    const payload_part_vi = try error_union_vi.partExact(
                        isel,
                        codegen.errUnionPayloadOffset(payload_ty, zcu),
                        payload_vi.value.size(isel),
                    );
                    try payload_vi.value.defCopy(isel, payload_part_vi);
                }

                const cont_label = isel.instructions.items.len;
                var cont_snapshot = try isel.takeLocationSnapshot();
                defer cont_snapshot.deinit(isel);
                tracking_log.debug("try-continue snapshot taken:\n{f}", .{cont_snapshot});
                try isel.body(@ptrCast(isel.air.extra.items[extra.end..][0..extra.data.body_len]));
                try cont_snapshot.merge(isel);

                const error_set_part_vi = try error_union_vi.partExact(
                    isel,
                    codegen.errUnionErrorOffset(payload_ty, zcu),
                    ZigType.fromInterned(error_union_info.error_set_type).abiSize(zcu),
                );
                const error_set_part_mat = try error_set_part_vi.matIntRegZeroExt(isel);
                try isel.internal_relocs.append(gpa, .{
                    .label = @intCast(isel.instructions.items.len),
                    .target = cont_label,
                });
                try isel.emit(.beqz(error_set_part_mat.reg(), 0, 0));
                try error_set_part_mat.finish(isel);
            },
            .try_ptr, .try_ptr_cold => {
                const unwrapped_try = isel.air.unwrapTryPtr(air.inst_index);
                const error_union_ty = isel.air.typeOf(unwrapped_try.error_union_ptr, ip).childType(zcu);
                const error_union_info = ip.indexToKey(error_union_ty.toIntern()).error_union_type;
                const payload_ty: ZigType = .fromInterned(error_union_info.payload_type);

                const error_union_ptr_vi = try isel.use(unwrapped_try.error_union_ptr);
                if (isel.live_values.fetchRemove(air.inst_index)) |payload_ptr_vi| unused: {
                    defer payload_ptr_vi.value.deref(isel);

                    const payload_offset = codegen.errUnionPayloadOffset(unwrapped_try.error_union_payload_ptr_ty.toType().childType(zcu), zcu);
                    if (payload_offset == 0) {
                        try payload_ptr_vi.value.defMove(isel, unwrapped_try.error_union_ptr);
                    } else {
                        const payload_ptr_reg = try payload_ptr_vi.value.defRegMod(isel, .integer) orelse break :unused;
                        const error_union_ptr_mat = try error_union_ptr_vi.matIntRegZeroExt(isel);
                        try isel.addImm(payload_ptr_reg, error_union_ptr_mat.reg(), payload_offset);
                        try error_union_ptr_mat.finish(isel);
                    }
                }

                const cont_label = isel.instructions.items.len;
                var cont_snapshot = try isel.takeLocationSnapshot();
                defer cont_snapshot.deinit(isel);
                tracking_log.debug("try_ptr-continue snapshot taken:\n{f}", .{cont_snapshot});
                try isel.body(unwrapped_try.else_body);
                try cont_snapshot.merge(isel);

                const tmp_reg = try isel.allocRegForWrite(.int);
                defer isel.freeReg(tmp_reg);

                try isel.internal_relocs.append(gpa, .{
                    .label = @intCast(isel.instructions.items.len),
                    .target = cont_label,
                });
                try isel.emit(.beqz(tmp_reg, 0, 0));

                const error_union_ptr_mat = try error_union_ptr_vi.matIntRegZeroExt(isel);
                try isel.loadReg(
                    tmp_reg,
                    ZigType.fromInterned(error_union_info.error_set_type).abiSize(zcu),
                    .unsigned,
                    error_union_ptr_mat.reg(),
                    codegen.errUnionErrorOffset(payload_ty, zcu),
                );
                try error_union_ptr_mat.finish(isel);
            },
            .aggregate_init => if (isel.live_values.fetchRemove(air.inst_index)) |agg_vi| {
                defer agg_vi.value.deref(isel);

                const ty_pl = air.data(air.inst_index).ty_pl;
                const agg_ty = ty_pl.ty.toType();
                switch (ip.indexToKey(agg_ty.toIntern())) {
                    .array_type => |array_type| {
                        const elem_ty = ZigType.fromInterned(array_type.child);
                        const elem_size = elem_ty.abiSize(zcu);
                        const elems: []const Air.Inst.Ref =
                            @ptrCast(isel.air.extra.items[ty_pl.payload..][0..@intCast(array_type.len)]);
                        var elem_offset: u64 = 0;

                        try agg_vi.value.split(isel, false);
                        for (elems) |elem| {
                            const agg_part_vi = try agg_vi.value.partExactRecursive(isel, elem_offset, elem_size);
                            try agg_part_vi.defMove(isel, elem);
                            elem_offset += elem_size;
                        }
                        switch (array_type.sentinel) {
                            .none => {},
                            else => |sentinel| {
                                const agg_part_vi = try agg_vi.value.partExactRecursive(isel, elem_offset, elem_size);
                                try agg_part_vi.defMove(isel, .fromIntern(sentinel));
                            },
                        }
                    },
                    .struct_type => {
                        const loaded_struct = ip.loadStructType(agg_ty.toIntern());
                        const elems: []const Air.Inst.Ref =
                            @ptrCast(isel.air.extra.items[ty_pl.payload..][0..loaded_struct.field_types.len]);
                        var field_offset: u64 = 0;
                        var field_it = loaded_struct.iterateRuntimeOrder(ip);
                        while (field_it.next()) |field_index| {
                            const field_ty: ZigType = .fromInterned(loaded_struct.field_types.get(ip)[field_index]);
                            field_offset = loaded_struct.field_offsets.get(ip)[field_index];
                            const field_size = field_ty.abiSize(zcu);
                            if (field_size == 0) continue;
                            const agg_part_vi = try agg_vi.value.partExactRecursive(isel, field_offset, field_size);
                            try agg_part_vi.defMove(isel, elems[field_index]);
                            field_offset += field_size;
                        }
                        assert(loaded_struct.alignment.forward(field_offset) == agg_vi.value.size(isel));
                    },
                    .tuple_type => |tuple_type| {
                        const elems: []const Air.Inst.Ref =
                            @ptrCast(isel.air.extra.items[ty_pl.payload..][0..tuple_type.types.len]);
                        var tuple_align: InternPool.Alignment = .@"1";
                        var field_offset: u64 = 0;
                        for (
                            tuple_type.types.get(ip),
                            tuple_type.values.get(ip),
                            elems,
                        ) |field_ty_index, field_val, elem| {
                            if (field_val != .none) continue;
                            const field_ty: ZigType = .fromInterned(field_ty_index);
                            const field_align = field_ty.abiAlignment(zcu);
                            tuple_align = tuple_align.maxStrict(field_align);
                            field_offset = field_align.forward(field_offset);
                            const field_size = field_ty.abiSize(zcu);
                            if (field_size == 0) continue;
                            const agg_part_vi = try agg_vi.value.partExactRecursive(isel, field_offset, field_size);
                            try agg_part_vi.defMove(isel, elem);
                            field_offset += field_size;
                        }
                        assert(tuple_align.forward(field_offset) == agg_vi.value.size(isel));
                    },
                    .vector_type => try isel.failUnimplemented("agg init vector", .{}),
                    else => unreachable,
                }
            },
            .struct_field_ptr => if (isel.live_values.fetchRemove(air.inst_index)) |dst_vi| unused: {
                defer dst_vi.value.deref(isel);
                const ty_pl = air.data(air.inst_index).ty_pl;
                const extra = isel.air.extraData(Air.StructField, ty_pl.payload).data;
                switch (codegen.fieldOffset(
                    isel.air.typeOf(extra.struct_operand, ip),
                    ty_pl.ty.toType(),
                    extra.field_index,
                    zcu,
                )) {
                    0 => try dst_vi.value.defMove(isel, extra.struct_operand),
                    else => |field_offset| {
                        const dst_reg = try dst_vi.value.defRegMod(isel, .integer) orelse break :unused;
                        const src_vi = try isel.use(extra.struct_operand);
                        const src_mat = try src_vi.matIntRegZeroExt(isel);
                        try isel.addImm(dst_reg, src_mat.reg(), field_offset);
                        try src_mat.finish(isel);
                    },
                }
            },
            .struct_field_ptr_index_0,
            .struct_field_ptr_index_1,
            .struct_field_ptr_index_2,
            .struct_field_ptr_index_3,
            => if (isel.live_values.fetchRemove(air.inst_index)) |dst_vi| unused: {
                defer dst_vi.value.deref(isel);
                const ty_op = air.data(air.inst_index).ty_op;
                switch (codegen.fieldOffset(
                    isel.air.typeOf(ty_op.operand, ip),
                    ty_op.ty.toType(),
                    switch (air_tag) {
                        else => unreachable,
                        .struct_field_ptr_index_0 => 0,
                        .struct_field_ptr_index_1 => 1,
                        .struct_field_ptr_index_2 => 2,
                        .struct_field_ptr_index_3 => 3,
                    },
                    zcu,
                )) {
                    0 => try dst_vi.value.defMove(isel, ty_op.operand),
                    else => |field_offset| {
                        const dst_reg = try dst_vi.value.defRegMod(isel, .integer) orelse break :unused;
                        const src_vi = try isel.use(ty_op.operand);
                        const src_mat = try src_vi.matIntRegZeroExt(isel);
                        try isel.addImm(dst_reg, src_mat.reg(), field_offset);
                        try src_mat.finish(isel);
                    },
                }
            },
            .agg_field_val => if (isel.live_values.fetchRemove(air.inst_index)) |field_vi| {
                defer field_vi.value.deref(isel);

                const ty_pl = air.data(air.inst_index).ty_pl;
                const extra = isel.air.extraData(Air.StructField, ty_pl.payload).data;
                const agg_ty = isel.air.typeOf(extra.struct_operand, ip);
                const field_ty = ty_pl.ty.toType();

                const field_bit_offset, const field_bit_size, const is_packed = switch (agg_ty.containerLayout(zcu)) {
                    .auto, .@"extern" => .{
                        8 * agg_ty.structFieldOffset(extra.field_index, zcu),
                        8 * field_ty.abiSize(zcu),
                        false,
                    },
                    .@"packed" => .{
                        if (zcu.typeToPackedStruct(agg_ty)) |loaded_struct|
                            zcu.structPackedFieldBitOffset(loaded_struct, extra.field_index)
                        else
                            0,
                        field_ty.bitSize(zcu),
                        true,
                    },
                };
                if (is_packed) return isel.fail("packed field of {f}", .{
                    isel.fmtType(agg_ty),
                });

                const agg_vi = try isel.use(extra.struct_operand);
                switch (agg_ty.zigTypeTag(zcu)) {
                    else => unreachable,
                    .@"struct" => {
                        const agg_part_vi = try agg_vi.partExactRecursive(
                            isel,
                            @divExact(field_bit_offset, 8),
                            @divExact(field_bit_size, 8),
                        );
                        try field_vi.value.defCopy(isel, agg_part_vi);
                    },
                    .@"union" => {
                        const agg_part_vi = try agg_vi.partAtLargerThan(
                            isel,
                            @divExact(field_bit_offset, 8),
                            @divExact(field_bit_size, 8),
                        );
                        try field_vi.value.defCopy(isel, agg_part_vi);
                    },
                }
            },
            .union_init => if (isel.live_values.fetchRemove(air.inst_index)) |union_vi| {
                defer union_vi.value.deref(isel);

                const ty_pl = air.data(air.inst_index).ty_pl;
                const extra = isel.air.extraData(Air.UnionInit, ty_pl.payload).data;
                const union_ty = ty_pl.ty.toType();
                const loaded_union = ip.loadUnionType(union_ty.toIntern());
                const union_layout = ZigType.getUnionLayout(loaded_union, zcu);

                if (union_layout.tag_size > 0) unused_tag: {
                    const loaded_tag = ip.loadEnumType(loaded_union.enum_tag_type);
                    const tag_vi = try union_vi.value.partExact(
                        isel,
                        union_layout.tagOffset(),
                        union_layout.tag_size,
                    );
                    if (tag_vi.extension(isel) == .sign_ext)
                        try tag_vi.reextendToGarbage(isel);
                    const tag_reg = try tag_vi.defRegMod(isel, .integer) orelse break :unused_tag;
                    const tag_val: i64 = switch (loaded_tag.field_values.len) {
                        0 => extra.field_index,
                        else => switch (ip.indexToKey(loaded_tag.field_values.get(ip)[extra.field_index]).int.storage) {
                            .u64 => |imm| @bitCast(imm),
                            .i64 => |imm| imm,
                            else => unreachable,
                        },
                    };
                    try isel.moveIntImm(tag_reg, tag_val);
                }
                const payload_vi = try union_vi.value.partExact(
                    isel,
                    union_layout.payloadOffset(),
                    union_layout.payload_size,
                );
                try payload_vi.defMove(isel, extra.init);
            },
            .set_union_tag => {
                const bin_op = air.data(air.inst_index).bin_op;
                const union_ty = isel.air.typeOf(bin_op.lhs, ip).childType(zcu);
                const union_layout = union_ty.unionGetLayout(zcu);
                const tag_vi = try isel.use(bin_op.rhs);
                const union_ptr_vi = try isel.use(bin_op.lhs);
                const union_ptr_mat = try union_ptr_vi.matIntRegZeroExt(isel);
                try tag_vi.matStore(isel, union_ptr_mat.reg(), union_layout.tagOffset(), .{});
                try union_ptr_mat.finish(isel);
            },
            .get_union_tag => if (isel.live_values.fetchRemove(air.inst_index)) |tag_vi| {
                defer tag_vi.value.deref(isel);
                const ty_op = air.data(air.inst_index).ty_op;
                const union_ty = isel.air.typeOf(ty_op.operand, ip);
                const union_layout = union_ty.unionGetLayout(zcu);
                const union_vi = try isel.use(ty_op.operand);
                const tag_part_vi = try union_vi.partExact(isel, union_layout.tagOffset(), union_layout.tag_size);
                try tag_vi.value.defCopy(isel, tag_part_vi);
            },
            .optional_payload => if (isel.live_values.fetchRemove(air.inst_index)) |payload_vi| unused: {
                defer payload_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const opt_ty = isel.air.typeOf(ty_op.operand, ip);
                if (opt_ty.optionalReprIsPayload(zcu)) {
                    try payload_vi.value.defMove(isel, ty_op.operand);
                    break :unused;
                }

                const opt_vi = try isel.use(ty_op.operand);
                const payload_part_vi = try opt_vi.partExact(isel, 0, payload_vi.value.size(isel));
                try payload_vi.value.defCopy(isel, payload_part_vi);
            },
            .optional_payload_ptr => if (isel.live_values.fetchRemove(air.inst_index)) |payload_ptr_vi| {
                defer payload_ptr_vi.value.deref(isel);
                const ty_op = air.data(air.inst_index).ty_op;
                try payload_ptr_vi.value.defMove(isel, ty_op.operand);
            },
            .wrap_optional => if (isel.live_values.fetchRemove(air.inst_index)) |opt_vi| unused: {
                defer opt_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                if (ty_op.ty.toType().optionalReprIsPayload(zcu)) {
                    try opt_vi.value.defMove(isel, ty_op.operand);
                    break :unused;
                }

                const payload_size = isel.air.typeOf(ty_op.operand, ip).abiSize(zcu);

                const payload_part_vi = try opt_vi.value.partExact(isel, 0, payload_size);
                const has_value_part_vi = try opt_vi.value.partExact(isel, payload_size, 1);
                try payload_part_vi.defMove(isel, ty_op.operand);
                const maybe_has_value_part_reg = try has_value_part_vi.defRegMod(isel, .integer);
                if (maybe_has_value_part_reg) |has_value_part_reg|
                    try isel.emit(.ori(has_value_part_reg, .zero, 0));
            },
            .field_parent_ptr => if (isel.live_values.fetchRemove(air.inst_index)) |dst_vi| unused: {
                defer dst_vi.value.deref(isel);
                const ty_pl = air.data(air.inst_index).ty_pl;
                const extra = isel.air.extraData(Air.FieldParentPtr, ty_pl.payload).data;
                switch (codegen.fieldOffset(
                    ty_pl.ty.toType(),
                    isel.air.typeOf(extra.field_ptr, ip),
                    extra.field_index,
                    zcu,
                )) {
                    0 => try dst_vi.value.defMove(isel, extra.field_ptr),
                    else => |field_offset| {
                        const dst_reg = try dst_vi.value.defRegMod(isel, .integer) orelse break :unused;
                        const src_vi = try isel.use(extra.field_ptr);
                        const src_mat = try src_vi.matIntRegZeroExt(isel);
                        try isel.addImm(dst_reg, src_mat.reg(), -@as(i65, field_offset));
                        try src_mat.finish(isel);
                    },
                }
            },
            .unwrap_errunion_payload => if (isel.live_values.fetchRemove(air.inst_index)) |payload_vi| {
                defer payload_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const error_union_vi = try isel.use(ty_op.operand);
                try payload_vi.value.defCopy(
                    isel,
                    try error_union_vi.partExact(
                        isel,
                        codegen.errUnionPayloadOffset(ty_op.ty.toType(), zcu),
                        payload_vi.value.size(isel),
                    ),
                );
            },
            .unwrap_errunion_err => if (isel.live_values.fetchRemove(air.inst_index)) |error_set_vi| {
                defer error_set_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const error_union_ty = isel.air.typeOf(ty_op.operand, ip);
                const error_union_vi = try isel.use(ty_op.operand);
                try error_set_vi.value.defCopy(
                    isel,
                    try error_union_vi.partExact(
                        isel,
                        codegen.errUnionErrorOffset(error_union_ty.errorUnionPayload(zcu), zcu),
                        error_set_vi.value.size(isel),
                    ),
                );
            },
            .wrap_errunion_payload => if (isel.live_values.fetchRemove(air.inst_index)) |error_union_vi| {
                defer error_union_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const error_union_ty = ty_op.ty.toType();
                const error_union_info = ip.indexToKey(error_union_ty.toIntern()).error_union_type;
                const error_set_ty: ZigType = .fromInterned(error_union_info.error_set_type);
                const payload_ty: ZigType = .fromInterned(error_union_info.payload_type);
                const error_set_offset = codegen.errUnionErrorOffset(payload_ty, zcu);
                const payload_offset = codegen.errUnionPayloadOffset(payload_ty, zcu);
                const error_set_size = error_set_ty.abiSize(zcu);
                const payload_size = payload_ty.abiSize(zcu);

                try error_union_vi.value.collectDefs(isel);

                if (payload_size > 0) {
                    const payload_part_vi = try error_union_vi.value.partExact(isel, payload_offset, payload_size);
                    try payload_part_vi.defMove(isel, ty_op.operand);
                }
                const error_set_part_vi = try error_union_vi.value.partExact(isel, error_set_offset, error_set_size);
                if (try error_set_part_vi.defRegMod(isel, .integer)) |error_set_part_reg|
                    try isel.emit(.ori(error_set_part_reg, .zero, 0));
            },
            .wrap_errunion_err => if (isel.live_values.fetchRemove(air.inst_index)) |error_union_vi| {
                defer error_union_vi.value.deref(isel);

                const ty_op = air.data(air.inst_index).ty_op;
                const error_union_ty = ty_op.ty.toType();
                const error_union_info = ip.indexToKey(error_union_ty.toIntern()).error_union_type;
                const error_set_ty: ZigType = .fromInterned(error_union_info.error_set_type);
                const payload_ty: ZigType = .fromInterned(error_union_info.payload_type);
                const error_set_offset = codegen.errUnionErrorOffset(payload_ty, zcu);
                const payload_offset = codegen.errUnionPayloadOffset(payload_ty, zcu);
                const error_set_size = error_set_ty.abiSize(zcu);
                const payload_size = payload_ty.abiSize(zcu);

                const error_set_part_vi = try error_union_vi.value.partExact(isel, error_set_offset, error_set_size);
                try error_set_part_vi.defMove(isel, ty_op.operand);
                if (payload_size > 0) {
                    const payload_part_vi = try error_union_vi.value.partExact(isel, payload_offset, payload_size);
                    try payload_part_vi.defUndef(isel);
                }
            },
            .errunion_payload_ptr_set => if (isel.live_values.fetchRemove(air.inst_index)) |payload_ptr_vi| unused: {
                defer payload_ptr_vi.value.deref(isel);
                const ty_op = air.data(air.inst_index).ty_op;
                const payload_ty = ty_op.ty.toType().childType(zcu);
                const eu_ty = isel.air.typeOf(ty_op.operand, ip).childType(zcu);
                const error_set_size = eu_ty.errorUnionSet(zcu).abiSize(zcu);

                const eu_ptr_vi = try isel.use(ty_op.operand);
                const error_union_ptr_mat = try eu_ptr_vi.matIntRegZeroExt(isel);
                if (error_set_size != 0) {
                    try isel.storeReg(
                        .zero,
                        error_set_size,
                        error_union_ptr_mat.reg(),
                        codegen.errUnionErrorOffset(payload_ty, zcu),
                    );
                }
                const payload_offset = codegen.errUnionPayloadOffset(payload_ty, zcu);
                if (payload_offset == 0) {
                    try error_union_ptr_mat.finish(isel);
                    try payload_ptr_vi.value.defMove(isel, ty_op.operand);
                } else {
                    const payload_ptr_reg = try payload_ptr_vi.value.defRegMod(isel, .integer) orelse break :unused;
                    try isel.addImm(payload_ptr_reg, error_union_ptr_mat.reg(), payload_offset);
                    try error_union_ptr_mat.finish(isel);
                }
            },
        }
        if (air_tag != .arg) {
            var live_reg_it = isel.live_registers.iterator();
            while (live_reg_it.next()) |live_reg_entry| switch (live_reg_entry.value.*) {
                .allocating => {
                    tracking_log.err("${t} is still allocated", .{live_reg_entry.key});
                    isel.dumpValues(.all);
                    unreachable;
                },
                _, .free => {},
            };
        }
        if (debug_r21_as_air) {
            try isel.moveIntImm(.r21, @backingInt(air.inst_index));
        }
    }
    assert(air.body_index == 0);
}

/// Generates prologue and epilogue. Returns the length of epilogue.
///
///           Stack Frame Layout
/// +-+-----------------------------------+
/// |R| caller frame                      |
/// +-+-----------------------------------+
/// |S| incoming stack arguments          |   +---------------+
/// +-+-----------------------------------+ <-| align(16)     |
/// |L| callee saved FP                   |   | entry/exit SP |
/// +-+-----------------------------------+   | FP            |
/// |L| callee saved GPR area             |   +---------------+
/// +-+-----------------------------------+
/// |L| callee saved FPR area             |   +-----------------+
/// +-+-----------------------------------+ <-| FP - saves_size |
/// |L| realignment gap                   |   +-----------------+
/// +-+-----------------------------------+ <-| align(16)       |
/// |L| locals                            |   +-----------------+
/// +-+-----------------------------------+
/// |S| outgoing stack arguments          |   +----+
/// +-+-----------------------------------+ <-| SP |
///                                           +----+
/// [S] Size computed by `analyze`, can be used by the body.
/// [L] Size computed by `layout`, can be used by the prologue/epilogue.
/// [R] Size unknown until runtime, can vary from one call to the next.
///
/// FP saving/restoring is not yet implemented.
pub fn layout(isel: *Select, cc_it: CallAbiIterator, mod: *const Module) !usize {
    _ = cc_it;
    _ = mod;
    const zcu = isel.pt.zcu;
    const ip = &zcu.intern_pool;
    const nav = ip.getNav(isel.nav_index);
    wip_mir_log.debug("{f}<body>:\n", .{nav.fqn.fmt(ip)});

    const gpr_size = isel.gprSize();

    var saves_buf: [10 + 2 + 8]struct {
        register: Register,
        needs_restore: bool,
        offset: u11,
        size: u5,
    } = undefined;
    var saved_offset: std.EnumArray(Register, u11) = .initUndefined();
    const saves, const saves_size = saves: {
        var saves_len: usize = 0;
        var saves_size: u11 = 0;
        var save_reg: Register = undefined;

        // callee saved GPR area
        save_reg = .r23;
        while (true) : (save_reg = @fromBackingInt(@backingInt(save_reg) + 1)) {
            if (isel.saved_registers.contains(save_reg)) {
                saves_size = std.mem.alignForward(u11, saves_size, gpr_size);
                saves_buf[saves_len] = .{
                    .register = save_reg,
                    .needs_restore = true,
                    .offset = saves_size,
                    .size = gpr_size,
                };
                saved_offset.set(save_reg, saves_size);
                saves_len += 1;
                saves_size += gpr_size;
            }
            if (save_reg == .r31) break;
        }
        inline for (.{ Register.ra, Register.fp }) |reg| {
            if (isel.saved_registers.contains(reg)) {
                saves_size = std.mem.alignForward(u11, saves_size, gpr_size);
                saves_buf[saves_len] = .{
                    .register = reg,
                    .needs_restore = true,
                    .offset = saves_size,
                    .size = gpr_size,
                };
                saved_offset.set(reg, saves_size);
                saves_len += 1;
                saves_size += gpr_size;
            }
        }

        // callee saved FPR area
        save_reg = .f24;
        while (true) : (save_reg = @fromBackingInt(@backingInt(save_reg) + 1)) {
            if (isel.saved_registers.contains(save_reg)) {
                saves_size = std.mem.alignForward(u11, saves_size, 8);
                saves_buf[saves_len] = .{
                    .register = save_reg,
                    .needs_restore = true,
                    .offset = saves_size,
                    .size = 8,
                };
                saved_offset.set(save_reg, saves_size);
                saves_len += 1;
                saves_size += 8;
            }
            if (save_reg == .f31) break;
        }
        break :saves .{ saves_buf[0..saves_len], std.mem.Alignment.@"16".forward(saves_size) };
    };

    const stack_frame_size = isel.stack_align.forward(saves_size + isel.stack_size);

    // apply layout relocs
    for (isel.layout_relocs.items) |label| {
        const instruction = isel.instructions.items[label];
        const rj: Register = .decode(.int, instruction.DJUk12.rj);
        if (isel.saved_registers.contains(rj)) {
            const rd: Register = .decode(.int, instruction.DJUk12.rd);
            const offset = saved_offset.get(rj);
            isel.instructions.items[label] = switch (gpr_size) {
                else => unreachable,
                4 => .@"ld.w"(rd, .sp, @intCast(stack_frame_size - 8 - offset)),
                8 => .@"ld.d"(rd, .sp, @intCast(stack_frame_size - 8 - offset)),
            };
        }
    }

    // prologue
    {
        // move SP
        if (stack_frame_size == 0) {} else if (std.math.cast(i12, stack_frame_size)) |stack_size12| {
            switch (gpr_size) {
                4 => try isel.emit(.@"addi.w"(.sp, .sp, -stack_size12)),
                8 => try isel.emit(.@"addi.d"(.sp, .sp, -stack_size12)),
                else => unreachable,
            }
        } else {
            switch (gpr_size) {
                4 => try isel.emit(.@"sub.w"(.sp, .sp, .t0)),
                8 => try isel.emit(.@"sub.d"(.sp, .sp, .t0)),
                else => unreachable,
            }
            try isel.moveIntImm(.t0, @intCast(stack_frame_size));
        }

        // set FP
        if (isel.saved_registers.contains(.fp))
            try isel.emit(.ori(.fp, .sp, 0));

        // save registers
        for (saves) |save| {
            switch (save.register.class()) {
                .int => switch (gpr_size) {
                    4 => try isel.emit(.@"st.h"(save.register, .sp, -8 - @as(i12, save.offset))),
                    8 => try isel.emit(.@"st.d"(save.register, .sp, -8 - @as(i12, save.offset))),
                    else => unreachable,
                },
                .fp => try isel.emit(.@"fst.d"(save.register, .sp, -8 - @as(i12, save.offset))),
                .fcc => unreachable,
            }
        }
        wip_mir_log.debug("{f}<prologue>:", .{nav.fqn.fmt(ip)});
    }

    // epilogue
    const epilogue = isel.instructions.items.len;
    if (isel.returns) {
        // return
        try isel.emit(.jirl(.zero, .ra, 0));

        // restore registers
        for (saves) |save| {
            if (!save.needs_restore) continue;
            switch (save.register.class()) {
                .int => switch (gpr_size) {
                    4 => try isel.emit(.@"ld.h"(save.register, .sp, -8 - @as(i12, save.offset))),
                    8 => try isel.emit(.@"ld.d"(save.register, .sp, -8 - @as(i12, save.offset))),
                    else => unreachable,
                },
                .fp => try isel.emit(.@"fld.d"(save.register, .sp, -8 - @as(i12, save.offset))),
                .fcc => unreachable,
            }
        }

        // restore SP
        if (stack_frame_size == 0) {} else if (std.math.cast(i12, stack_frame_size)) |stack_size12| {
            switch (gpr_size) {
                4 => try isel.emit(.@"addi.w"(.sp, .sp, stack_size12)),
                8 => try isel.emit(.@"addi.d"(.sp, .sp, stack_size12)),
                else => unreachable,
            }
        } else {
            switch (gpr_size) {
                4 => try isel.emit(.@"add.w"(.sp, .sp, .t0)),
                8 => try isel.emit(.@"add.d"(.sp, .sp, .t0)),
                else => unreachable,
            }
            try isel.moveIntImm(.t0, @intCast(stack_frame_size));
        }

        wip_mir_log.debug("{f}<epilogue>:\n", .{nav.fqn.fmt(ip)});
    }
    return epilogue;
}

fn emit(isel: *Select, instruction: Instruction) !void {
    wip_mir_log.debug("  | {f}", .{(Disassemble{}).fmtInstruction(instruction)});
    try isel.instructions.append(isel.pt.zcu.gpa, instruction);
}

pub fn verifyTargetFeatures(isel: *Select) !void {
    if (!verify_target_features) return;

    for (isel.instructions.items) |inst| {
        if (Disassemble.decodeMnemonic(inst)) |decoded_mnemonic| {
            switch (decoded_mnemonic) {
                inline else => |mnemonic| {
                    const expected_features = @field(@import("inst_formats.zon").instructions, @tagName(mnemonic)).features;
                    inline for (@typeInfo(expected_features).@"struct".fields) |expected_feature_field| {
                        const expected_feature = @tagName(@field(expected_features, expected_feature_field.name));
                        const std_feature = @field(std.Target.loongarch.Feature, expected_feature);
                        if (!isel.hasCpuFeature(std_feature)) {
                            wip_mir_log.err("emitted instruction {t} requires feature {t} which is not available", .{ mnemonic, std_feature });
                            unreachable;
                        }
                    }
                },
            }
        } else {
            wip_mir_log.err("invalid instruction was emitted in Select: {x}", .{inst.word});
            unreachable;
        }
    }
}

fn hasCpuFeature(isel: *Select, feature: std.Target.loongarch.Feature) bool {
    return std.Target.loongarch.featureSetHas(isel.target.cpu.features, feature);
}

fn block(
    isel: *Select,
    air_inst_index: Air.Inst.Index,
    res_ty: ZigType,
    air_body: []const Air.Inst.Index,
) !void {
    if (res_ty.toIntern() != .noreturn_type) {
        const snapshot = try isel.takeLocationSnapshot();
        tracking_log.debug("block snapshot taken:\n{f}", .{snapshot});
        isel.active_blocks.putAssumeCapacityNoClobber(air_inst_index, .{
            .snapshot = snapshot,
            .target_label = @intCast(isel.instructions.items.len),
        });
    }
    try isel.body(air_body);
    if (res_ty.toIntern() != .noreturn_type) {
        var block_entry = isel.active_blocks.pop().?;
        assert(block_entry.key == air_inst_index);
        block_entry.value.deinit(isel);
        if (isel.live_values.fetchRemove(air_inst_index)) |result_vi| {
            var res_walk = result_vi.value.walk(isel, .{});
            while (res_walk.next()) |res_part_vi|
                _ = res_part_vi.takeLocationMarkWritten(isel);
            result_vi.value.deref(isel);
        }
    }
}

fn initValue(isel: *Select, ty: ZigType) error{OutOfMemory}!Value.Index {
    const zcu = isel.pt.zcu;
    try isel.values.ensureUnusedCapacity(zcu.gpa, 1);
    try isel.value_types.ensureUnusedCapacity(zcu.gpa, 1);
    return isel.initValueAdvanced(ty.abiAlignment(zcu), 0, ty.abiSize(zcu), ty);
}

fn initValueAssumeCapacity(isel: *Select, ty: ZigType) Value.Index {
    const zcu = isel.pt.zcu;
    return isel.initValueAdvanced(ty.abiAlignment(zcu), 0, ty.abiSize(zcu), ty);
}

fn initValueAdvanced(
    isel: *Select,
    parent_alignment: InternPool.Alignment,
    offset_from_parent: u64,
    size: u64,
    ty: ?ZigType,
) Value.Index {
    defer isel.values.addOneAssumeCapacity().* = .{
        .refs = 0,
        .flags = .{
            .alignment = .fromLog2Units(@min(parent_alignment.toLog2Units(), @ctz(offset_from_parent))),
            .parent_tag = .none,
            // TODO size < 32 when vectors are supported
            .location_tag = if (size <= 8)
                .small
            else if (std.math.cast(u32, size) != null)
                .large
            else
                .extreme,
            .parts_len_minus_one = 0,
            .splitted = false,
        },
        .offset_from_parent = offset_from_parent,
        .parent_payload = .{ .none = {} },
        // TODO ditto
        .location_payload = if (size <= 8) .{ .small = .{
            .flags = .{
                .size = @intCast(size),
                .extension = .garbage,
                .hint_modifier = .integer,
                .hint_register = .zero,
                .location_tag = .register,
            },
            .location_payload = .{ .register = .zero },
        } } else if (std.math.cast(u32, size)) |size32| .{ .large = .{
            .size = size32,
            .stack_slot = .unallocated,
        } } else .{ .extreme = .{ .size = size } },
        .parts = undefined,
    };
    defer isel.value_types.appendAssumeCapacity(ty orelse .{ .ip_index = .none });
    return @fromBackingInt(@intCast(isel.values.items.len));
}

const WhichValues = enum { only_referenced, all };
pub fn dumpValues(isel: *Select, which: WhichValues) void {
    dumpValuesInner(isel, which) catch |err| @panic(@errorName(err));
}
fn dumpValuesInner(isel: *Select, which: WhichValues) !void {
    const zcu = isel.pt.zcu;
    const gpa = zcu.gpa;
    const ip = &zcu.intern_pool;
    const nav = ip.getNav(isel.nav_index);

    const locked_stderr = std.debug.lockStderr(&.{});
    defer std.debug.unlockStderr();
    const stderr = &locked_stderr.file_writer.interface;

    var reverse_live_values: std.AutoArrayHashMapUnmanaged(Value.Index, std.ArrayList(Air.Inst.Index)) = .empty;
    defer {
        for (reverse_live_values.values()) |*list| list.deinit(gpa);
        reverse_live_values.deinit(gpa);
    }
    {
        try reverse_live_values.ensureTotalCapacity(gpa, isel.live_values.count());
        var live_val_it = isel.live_values.iterator();
        while (live_val_it.next()) |live_val_entry| switch (live_val_entry.value_ptr.*) {
            _ => {
                const gop = reverse_live_values.getOrPutAssumeCapacity(live_val_entry.value_ptr.*);
                if (!gop.found_existing) gop.value_ptr.* = .empty;
                try gop.value_ptr.append(gpa, live_val_entry.key_ptr.*);
            },
            .allocating, .free => unreachable,
        };
    }

    var reverse_live_registers: std.AutoHashMapUnmanaged(Value.Index, Register) = .empty;
    defer reverse_live_registers.deinit(gpa);
    {
        try reverse_live_registers.ensureTotalCapacity(gpa, @typeInfo(Register).@"enum".field_names.len);
        var live_reg_it = isel.live_registers.iterator();
        while (live_reg_it.next()) |live_reg_entry| switch (live_reg_entry.value.*) {
            _ => reverse_live_registers.putAssumeCapacityNoClobber(live_reg_entry.value.*, live_reg_entry.key),
            .allocating, .free => {},
        };
    }

    var roots: std.AutoArrayHashMapUnmanaged(Value.Index, u32) = .empty;
    defer roots.deinit(gpa);
    {
        try roots.ensureTotalCapacity(gpa, isel.values.items.len);
        var vi: Value.Index = @fromBackingInt(@intCast(isel.values.items.len));
        iter_values: while (@backingInt(vi) > 0) {
            vi = @fromBackingInt(@backingInt(vi) - 1);
            if (which == .only_referenced and vi.get(isel).refs == 0) continue;
            switch (vi.parent(isel)) {
                .none, .constant => {},
                .value => continue :iter_values,
                .address => |address_vi| roots.putAssumeCapacity(address_vi, 0),
            }
            roots.putAssumeCapacity(vi, 0);
        }
    }

    try stderr.print("# Begin LA ISelect Value Dump: {f}:\n", .{nav.fqn.fmt(ip)});
    while (roots.pop()) |root_entry| {
        const vi = root_entry.key;
        try stderr.splatByteAll(' ', 2 * (@as(usize, 1) + root_entry.value));
        try vi.format(stderr);
        {
            var first = true;
            if (reverse_live_values.get(vi)) |aiis| for (aiis.items) |aii| {
                if (aii == Block.main) {
                    try stderr.print("{s}%main", .{if (first) " <- " else ", "});
                } else {
                    try stderr.print("{s}%{d}", .{ if (first) " <- " else ", ", @backingInt(aii) });
                }
                first = false;
            };
            if (reverse_live_registers.get(vi)) |ra| {
                try stderr.print("{s}{t}", .{ if (first) " <- " else ", ", ra });
                first = false;
            }
        }
        try stderr.writeByte(':');
        try isel.printValueInfo(stderr, vi);
        try stderr.writeByte('\n');

        const value = vi.get(isel);
        var part_index = value.flags.parts_len_minus_one;
        if (part_index > 0) while (true) : (part_index -= 1) {
            try roots.put(
                gpa,
                @fromBackingInt(@backingInt(value.parts) + part_index),
                root_entry.value + 1,
            );
            if (part_index == 0) break;
        };
    }
    try stderr.print("# End LA ISelect Value Dump: {f}\n", .{nav.fqn.fmt(ip)});
}

fn printValueAndParts(isel: *Select, writer: *std.Io.Writer, target_vi: Value.Index) !void {
    const zcu = isel.pt.zcu;
    const gpa = zcu.gpa;

    var roots: std.AutoArrayHashMapUnmanaged(Value.Index, u32) = .empty;
    defer roots.deinit(gpa);

    var root_vi = target_vi;
    while (true) switch (root_vi.parent(isel)) {
        .none, .constant => break,
        .value => |parent_vi| root_vi = parent_vi,
        .address => |address_vi| break try roots.put(gpa, address_vi, 0),
    };
    try roots.put(gpa, root_vi, 0);

    while (roots.pop()) |root_entry| {
        const vi = root_entry.key;
        try writer.splatByteAll(' ', 2 * root_entry.value);
        try vi.format(writer);
        try writer.writeByte(':');
        try isel.printValueInfo(writer, vi);

        const value = vi.get(isel);
        var part_index = value.flags.parts_len_minus_one;
        if (part_index > 0) while (true) : (part_index -= 1) {
            try roots.put(
                gpa,
                @fromBackingInt(@backingInt(value.parts) + part_index),
                root_entry.value + 1,
            );
            if (part_index == 0) break;
        };

        if (roots.count() != 0)
            try writer.writeByte('\n');
    }
}

fn printValueInfo(isel: *Select, writer: *std.Io.Writer, vi: Value.Index) !void {
    const zcu = isel.pt.zcu;

    const value = vi.get(isel);
    switch (value.flags.parent_tag) {
        .none => {},
        .value => try writer.print(" {f}+0x{x}", .{ value.parent_payload.value, value.offset_from_parent }),
        .address => try writer.print(" {f}[0x{x}]", .{ value.parent_payload.address, value.offset_from_parent }),
        .constant => try writer.print(" <{f}, {f}>", .{
            isel.fmtType(value.parent_payload.constant.typeOf(zcu)),
            isel.fmtConstant(value.parent_payload.constant),
        }),
    }
    try writer.print(" align({s})", .{@tagName(value.flags.alignment)});
    switch (value.flags.location_tag) {
        .small => {
            const loc_info = value.location_payload.small;
            try writer.print(" {d}B", .{loc_info.flags.size});
            if (loc_info.flags.extension != .garbage) try writer.print(" {t}", .{loc_info.flags.extension});

            var hints: u8 = 0;
            if (loc_info.flags.hint_modifier != .integer) hints += 1;
            if (loc_info.flags.hint_register != Register.zero) hints += 1;
            if (hints != 0) try writer.writeAll(" hint=");
            if (loc_info.flags.hint_modifier != .integer) try writer.print("{t}", .{loc_info.flags.hint_modifier});
            if (loc_info.flags.hint_register != Register.zero) try writer.print("{s}${t}", .{ if (hints != 1) "," else "", loc_info.flags.hint_register });

            switch (loc_info.flags.location_tag) {
                .register => {
                    if (loc_info.location_payload.register.reg != Register.zero) {
                        try writer.print(" loc={f}", .{loc_info.location_payload.register});
                    }
                },
                .stack_slot => try writer.print(" loc={f}", .{loc_info.location_payload.stack_slot}),
            }
        },
        .large => {
            try writer.print(" {d}B large", .{value.location_payload.large.size});
            if (value.location_payload.large.stack_slot != Value.Indirect.unallocated)
                try writer.print(" loc={f}", .{value.location_payload.large.stack_slot});
        },
        .extreme => try writer.print(" {d}B extreme", .{value.location_payload.large.size}),
    }
    if (value.flags.splitted)
        try writer.writeAll(" splitted");
    if (value.refs != 0)
        try writer.print(" refs={d}", .{value.refs});
    if (vi.typeOf(isel)) |ty| try writer.print(" {f}", .{isel.fmtType(ty)});
}

fn fmtValue(isel: *Select, vi: Value.Index) struct {
    isel: *Select,
    vi: Value.Index,
    pub fn format(data: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        data.isel.printValueAndParts(writer, data.vi) catch |err| switch (err) {
            error.OutOfMemory => try writer.writeAll("OOM"),
            error.WriteFailed => return error.WriteFailed,
        };
    }
} {
    return .{ .isel = isel, .vi = vi };
}

fn fmtLoopLive(isel: *Select, loop_inst: Air.Inst.Index) struct {
    isel: *Select,
    inst: Air.Inst.Index,
    pub fn format(data: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const loops = data.isel.loops.values();
        const loop_index = data.isel.loops.getIndex(data.inst).?;
        const live_insts =
            data.isel.loop_outer_live.list.items[loops[loop_index].outer_live..loops[loop_index + 1].outer_live];

        try writer.print("%{d} <- {{", .{@backingInt(data.inst)});
        var first = true;
        for (live_insts) |live_inst| {
            if (first) first = false else try writer.writeByte(',');
            try writer.print(" %{d}", .{@backingInt(live_inst)});
        }
        if (!first) try writer.writeByte(' ');
        try writer.writeByte('}');
    }
} {
    return .{ .isel = isel, .inst = loop_inst };
}

fn fmtType(isel: *Select, ty: ZigType) ZigType.Formatter {
    return ty.fmt(isel.pt);
}

fn fmtConstant(isel: *Select, constant: Constant) @typeInfo(@TypeOf(Constant.fmtValue)).@"fn".return_type.? {
    return constant.fmtValue(isel.pt);
}

fn fmtRegisterSet(regs: RegisterSet) struct {
    regs: RegisterSet,
    pub fn format(data: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        var it = data.regs.iterator();
        var first = true;
        while (it.next()) |reg| {
            if (first) first = false else try writer.writeAll(", ");
            try writer.print("${t}", .{reg});
        }
        if (first) try writer.writeAll("(empty)");
    }
} {
    return .{ .regs = regs };
}

fn use(isel: *Select, air_ref: Air.Inst.Ref) !Value.Index {
    const zcu = isel.pt.zcu;
    const ip = &zcu.intern_pool;
    const vi, const ty = if (air_ref.toIndex()) |air_inst_index| vi_ty: {
        const live_gop = try isel.live_values.getOrPut(zcu.gpa, air_inst_index);
        if (live_gop.found_existing) return live_gop.value_ptr.*;
        const ty = isel.air.typeOf(air_ref, ip);
        const vi = try isel.initValue(ty);
        tracking_log.debug("{f} <- %{d}", .{ vi, @backingInt(air_inst_index) });
        live_gop.value_ptr.* = vi.ref(isel);
        break :vi_ty .{ vi, ty };
    } else vi_ty: {
        const constant: Constant = .fromInterned(air_ref.toInterned().?);
        const ty = constant.typeOf(zcu);
        const vi = try isel.initValue(ty);
        tracking_log.debug("{f} <- <{f}, {f}>", .{
            vi,
            isel.fmtType(ty),
            isel.fmtConstant(constant),
        });
        vi.setParent(isel, .{ .constant = constant });
        break :vi_ty .{ vi, ty };
    };
    if (ty.isAbiInt(zcu)) {
        const int_info = ty.intInfo(zcu);
        if (int_info.bits <= 16) vi.setExtension(isel, .fromSignedness(int_info.signedness));
    }
    return vi;
}

// TODO: make r22 allocatable
fn isRegisterAllocatable(rd: Register) bool {
    return switch (rd) {
        else => true,
        Register.zero, Register.tp, Register.sp, Register.fp, .r21 => false,
    };
}

/// Frees a register by forgetting it.
/// Returns true on success, false on failure (i.e. dst_reg is locked/allocated or unallocatable).
fn forgetReg(isel: *Select, dst_reg: Register) error{ OutOfMemory, AlreadyReported }!bool {
    if (!isRegisterAllocatable(dst_reg)) return false;
    const dst_live_vi = isel.live_registers.getPtr(dst_reg);
    const dst_vi = switch (dst_live_vi.*) {
        _ => |dst_vi| dst_vi,
        .allocating => return false,
        .free => return true,
    };
    tracking_log.debug("{f} -> location forgotten", .{dst_vi});
    _ = dst_vi.takeLocation(isel);
    assert(dst_live_vi.* == .free);
    return true;
}

/// Frees a register by moving it to another place.
/// Returns true on success, false on failure (i.e. dst_reg is locked/allocated or unallocatable).
fn fillReg(isel: *Select, dst_reg: Register) error{ OutOfMemory, AlreadyReported }!bool {
    if (!isRegisterAllocatable(dst_reg)) return false;
    const dst_live_vi = isel.live_registers.getPtr(dst_reg);
    const dst_vi = switch (dst_live_vi.*) {
        _ => |dst_vi| dst_vi,
        .allocating => return false,
        .free => return true,
    };
    const src_loc: Value.Location = src: {
        if (dst_vi.hintRegister(isel)) |hint_reg| {
            dst_live_vi.* = .allocating;
            defer dst_live_vi.* = dst_vi;
            if (try isel.fillReg(hint_reg)) {
                isel.saved_registers.insert(hint_reg);
                break :src .{ .register = .{ .mod = dst_vi.hintModifier(isel), .reg = hint_reg } };
            }
        }
        if (dst_vi.isSmall(isel)) {
            switch (isel.tryAllocReg(dst_vi.hintModifier(isel).class())) {
                .allocated => |reg| {
                    isel.freeReg(reg);
                    break :src .{ .register = .{ .mod = dst_vi.hintModifier(isel), .reg = reg } };
                },
                .fill_candidate, .out_of_registers => {},
            }
        }
        break :src .{ .stack_slot = dst_vi.allocStackSlot(isel) };
    };
    try dst_vi.moveTo(isel, src_loc);
    assert(dst_live_vi.* == .free);
    return true;
}

/// Frees a set of register. If locked is true, these registers are then locked.
/// Requires all registers to be unlocked.
/// Returns true on success.
fn fillRegsBatch(isel: *Select, regs: RegisterSet, locking: bool) error{ OutOfMemory, AlreadyReported }!void {
    tracking_log.debug("batch fill: {f}", .{fmtRegisterSet(regs)});
    // lock free registers
    var regs_it = regs.iterator();
    while (regs_it.next()) |reg| {
        const live_vi = isel.live_registers.getPtr(reg);
        switch (live_vi.*) {
            .allocating => unreachable,
            .free => live_vi.* = .allocating,
            _ => {}, // fill_candidate will be ignored by fillReg so there is no need to protect these values
        }
    }

    // fill registers
    regs_it = regs.iterator();
    while (regs_it.next()) |reg| {
        const live_vi = isel.live_registers.getPtr(reg);
        switch (live_vi.*) {
            .free => unreachable,
            .allocating => {},
            _ => {
                assert(try isel.fillReg(reg));
                live_vi.* = .allocating;
            },
        }
    }

    // unlock registers
    if (!locking) {
        regs_it = regs.iterator();
        while (regs_it.next()) |reg| {
            const live_vi = isel.live_registers.getPtr(reg);
            assert(live_vi.* == .allocating);
            live_vi.* = .free;
        }
    }

    return;
}

/// Frees a register by moving it to stack.
/// Returns true on success, false on failure (i.e. dst_reg is locked/allocated or unallocatable).
fn fillRegToMemory(isel: *Select, dst_reg: Register) error{ OutOfMemory, AlreadyReported }!bool {
    if (!isRegisterAllocatable(dst_reg)) return false;
    const dst_live_vi = isel.live_registers.getPtr(dst_reg);
    const dst_vi = switch (dst_live_vi.*) {
        _ => |dst_vi| dst_vi,
        .allocating => return false,
        .free => return true,
    };
    try dst_vi.moveTo(isel, .{ .stack_slot = dst_vi.allocStackSlot(isel) });
    assert(dst_live_vi.* == .free);
    return true;
}

const TryAllocRegResult = union(enum) {
    allocated: Register,
    fill_candidate: Register,
    out_of_registers,
};

fn tryAllocReg(isel: *Select, class: Register.Class) TryAllocRegResult {
    return switch (class) {
        .int => isel.tryAllocRegInRanges(&.{
            .{ .r4, .r11 }, // argument registers
            .{ .r12, .r20 }, // temporary registers
            .{ .r23, .r31 }, // static registers
            .{ .r0, .r31 },
        }),
        .fp => isel.tryAllocRegInRange(.{ .f0, .f31 }),
        .fcc => isel.tryAllocRegInRange(.{ .fcc0, .fcc7 }),
    };
}

fn tryAllocRegInRanges(isel: *Select, comptime ranges: []const struct { Register, Register }) TryAllocRegResult {
    inline for (ranges[0 .. ranges.len - 1]) |range| {
        switch (isel.tryAllocRegInRange(range)) {
            .allocated => |reg| return .{ .allocated = reg },
            else => {},
        }
    }
    return isel.tryAllocRegInRange(ranges[ranges.len - 1]);
}

fn tryAllocRegInRange(isel: *Select, range: struct { Register, Register }) TryAllocRegResult {
    var failed_result: TryAllocRegResult = .out_of_registers;
    var reg, const last_reg = range;
    while (true) : (reg = @fromBackingInt(@backingInt(reg) + 1)) {
        if (!isRegisterAllocatable(reg)) continue;
        const live_vi = isel.live_registers.getPtr(reg);
        switch (live_vi.*) {
            _ => switch (failed_result) {
                .allocated => unreachable,
                .fill_candidate => {},
                .out_of_registers => failed_result = .{ .fill_candidate = reg },
            },
            .allocating => {},
            .free => {
                live_vi.* = .allocating;
                isel.saved_registers.insert(reg);
                return .{ .allocated = reg };
            },
        }
        if (reg == last_reg) return failed_result;
    }
}

fn allocReg(isel: *Select, class: Register.Class) !Register {
    switch (isel.tryAllocReg(class)) {
        .allocated => |reg| return reg,
        .fill_candidate => |reg| {
            assert(try isel.fillRegToMemory(reg));
            const live_vi = isel.live_registers.getPtr(reg);
            assert(live_vi.* == .free);
            live_vi.* = .allocating;
            return reg;
        },
        .out_of_registers => return isel.fail("ran out of {t} registers", .{class}),
    }
}

fn allocRegForWrite(isel: *Select, class: Register.Class) !Register {
    const reg = try isel.allocReg(class);
    isel.markRegWritten(reg);
    return reg;
}

fn markRegWritten(isel: *Select, reg: Register) void {
    if (isel.active_loops.last()) |loop_index| {
        const loop = loop_index.get(isel);
        tracking_log.debug("${t} <- written", .{reg});
        loop.written_regs.insert(reg);
    }
}

fn markRegsWritten(isel: *Select, regs: RegisterSet) void {
    if (isel.active_loops.last()) |loop_index| {
        const loop = loop_index.get(isel);
        tracking_log.debug("{f} <- written", .{fmtRegisterSet(regs)});
        loop.written_regs.setUnion(regs);
    }
}

const RegLock = struct {
    reg: Register,
    const empty: RegLock = .{ .reg = .zero };
    fn unlock(lock: RegLock, isel: *Select) void {
        switch (lock.reg) {
            else => |reg| isel.freeReg(reg),
            Register.zero => {},
        }
    }
};

fn lockReg(isel: *Select, reg: Register) RegLock {
    assert(reg != Register.zero);
    const live_vi = isel.live_registers.getPtr(reg);
    assert(live_vi.* == .free);
    live_vi.* = .allocating;
    return .{ .reg = reg };
}

fn tryLockReg(isel: *Select, reg: Register) RegLock {
    assert(reg != Register.zero);
    const live_vi = isel.live_registers.getPtr(reg);
    switch (live_vi.*) {
        _ => {
            isel.dumpValues(.all);
            unreachable;
        },
        .allocating => return .empty,
        .free => {
            live_vi.* = .allocating;
            return .{ .reg = reg };
        },
    }
}

fn freeReg(isel: *Select, reg: Register) void {
    assert(reg != Register.zero);
    const live_vi = isel.live_registers.getPtr(reg);
    assert(live_vi.* == .allocating);
    live_vi.* = .free;
}

/// A snapshot of unresolved locations.
const LocationSnapshot = struct {
    value_locs: std.MultiArrayList(Entry),

    const Entry = union(enum(u2)) {
        none,
        register: Register.Alias,
        stack_slot: Value.Indirect,
    };

    const empty: LocationSnapshot = .{ .value_locs = .empty };

    fn deinit(snap: *LocationSnapshot, isel: *Select) void {
        const gpa = isel.pt.zcu.gpa;
        snap.value_locs.deinit(gpa);
        snap.* = undefined;
    }

    /// Merges the captured locations and current expected locations.
    fn merge(snap: *const LocationSnapshot, isel: *Select) !void {
        const captured_locs = snap.value_locs.slice();
        for (0..snap.value_locs.len) |i| {
            const vi: Value.Index = @fromBackingInt(@intCast(i));
            const captured_loc: Value.Location = switch (captured_locs.get(i)) {
                .none => continue,
                .register => |captured_ra| .{ .register = captured_ra },
                .stack_slot => |captured_stack| .{ .stack_slot = captured_stack },
            };
            if (vi.location(isel)) |current_loc| {
                if (std.meta.eql(captured_loc, current_loc)) continue;
            }
            tracking_log.debug("{f} <- {f} (snapshot merge)", .{ vi, captured_loc });

            if (captured_loc.asRegister()) |captured_reg| assert(try isel.fillReg(captured_reg));
            try vi.moveTo(isel, captured_loc);
        }
    }

    pub fn format(snap: LocationSnapshot, w: *std.Io.Writer) std.Io.Writer.Error!void {
        const captured_locs = snap.value_locs.slice();
        var first = true;
        for (0..snap.value_locs.len) |i| {
            const vi: Value.Index = @fromBackingInt(@intCast(i));
            const captured_loc = captured_locs.get(i);
            if (captured_loc == .none) continue;
            if (first) first = false else try w.writeAll("\n");
            switch (captured_loc) {
                .none => unreachable,
                .register => |captured_ra| try w.print("  {f} <- {f}", .{ vi, captured_ra }),
                .stack_slot => |captured_stack| try w.print("  {f} <- {f}", .{ vi, captured_stack }),
            }
        }
        if (first) return w.writeAll("(empty)");
    }
};

fn takeLocationSnapshot(isel: *Select) !LocationSnapshot {
    const gpa = isel.pt.zcu.gpa;
    var snapshot: LocationSnapshot = .empty;
    try snapshot.value_locs.resize(gpa, isel.values.items.len);

    for (0..isel.values.items.len) |i| {
        const vi: Value.Index = @fromBackingInt(@intCast(i));
        if (vi.location(isel)) |vi_loc| {
            snapshot.value_locs.set(i, switch (vi_loc) {
                .register => |vi_ra| if (vi_ra.reg == Register.zero) .none else .{ .register = vi_ra },
                .stack_slot => |vi_stack| .{ .stack_slot = vi_stack },
            });
        } else {
            snapshot.value_locs.set(i, .none);
        }
    }

    if (std.debug.runtime_safety) {
        var live_vi_it = isel.live_registers.iterator();
        while (live_vi_it.next()) |live_vi| {
            if (live_vi.value.* == .allocating) {
                tracking_log.debug("{t} is still locked when taking snapshot", .{live_vi.key});
                unreachable;
            }
        }
    }

    return snapshot;
}

/// Ways to treat bits in destination registers that may not be affected by an operation.
const DestProtection = enum {
    /// Unrelated bits must be preserved.
    preserved,
    /// Unrelated bits may be destroyed.
    none,
    /// Unrelated bits must be filled with 0.
    wiped,
};

fn fillUnusedBits(isel: *Select, rd: Register, rj: Register, dst_mode: Value.Extension, src_mode: Value.Extension, unused_bits: u9) !void {
    const gpr_bits = isel.gprBits();
    const used_bits = gpr_bits - unused_bits;
    wip_mir_log.debug("  | # fillUnusedBits {t}, {t}, {d} bits, {t} -> {t}", .{ rd, rj, used_bits, src_mode, dst_mode });

    if (used_bits == gpr_bits or src_mode == dst_mode) {
        if (rd != rj) try isel.emit(.ori(rd, rj, 0));
        return;
    }
    switch (dst_mode) {
        .garbage => {},
        .sign_ext => {
            if (used_bits >= gpr_bits) return isel.fail("too many used bits", .{});
            switch (used_bits) {
                8 => try isel.emit(.@"sext.b"(rd, rj)),
                16 => try isel.emit(.@"sext.h"(rd, rj)),
                32 => try isel.emit(.@"addi.w"(rd, rj, 0)),
                0...7, 9...15, 17...31, 33...63 => {
                    try isel.emit(.@"srai.d"(rd, rd, @intCast(gpr_bits - used_bits)));
                    try isel.emit(.@"slli.d"(rd, rj, @intCast(gpr_bits - used_bits)));
                },
                else => unreachable,
            }
        },
        .zero_ext => {
            if (used_bits >= gpr_bits) return isel.fail("too many used bits", .{});
            switch (used_bits) {
                1...31 => try isel.emit(.@"bstrpick.w"(rd, rj, @intCast(used_bits - 1), 0)),
                32...63 => try isel.emit(.@"bstrpick.d"(rd, rj, @intCast(used_bits - 1), 0)),
                else => unreachable,
            }
        },
    }
}

/// Loads from memory [base + offset] to register
fn loadReg(
    isel: *Select,
    dst: Register,
    size: u64,
    signedness: std.builtin.Signedness,
    base: Register,
    offset: i65,
) !void {
    if (dst.class() != .int) return isel.fail("TODO loadReg {t}", .{dst});
    switch (size) {
        0 => unreachable,
        1 => {
            if (std.math.cast(i12, offset)) |small_off| return isel.emit(switch (signedness) {
                .signed => .@"ld.b"(dst, base, small_off),
                .unsigned => .@"ld.bu"(dst, base, small_off),
            });
        },
        2 => {
            if (std.math.cast(i12, offset)) |small_off| return isel.emit(switch (signedness) {
                .signed => .@"ld.h"(dst, base, small_off),
                .unsigned => .@"ld.hu"(dst, base, small_off),
            });
        },
        4 => {
            if (std.math.cast(i12, offset)) |small_off| return isel.emit(switch (signedness) {
                .signed => .@"ld.w"(dst, base, small_off),
                .unsigned => .@"ld.wu"(dst, base, small_off),
            });
            if (signedness == .signed) if (std.math.cast(i16, offset)) |small_off| {
                if ((small_off & 0b11) == 0) {
                    return isel.emit(.@"ldox4.w"(dst, base, @intCast(@divExact(small_off, 4))));
                }
            };
        },
        8 => {
            if (std.math.cast(i12, offset)) |small_off| return isel.emit(.@"ld.d"(dst, base, small_off));
            if (std.math.cast(i16, offset)) |small_off| {
                if ((small_off & 0b11) == 0) {
                    return isel.emit(.@"ldox4.d"(dst, base, @intCast(@divExact(small_off, 4))));
                }
            }
        },
        else => return try isel.failUnimplemented("bad load size: {d}", .{size}),
    }

    const ptr_reg = try isel.allocRegForWrite(.int);
    defer isel.freeReg(ptr_reg);
    switch (size) {
        1 => try isel.emit(switch (signedness) {
            .signed => .@"ldx.b"(dst, base, ptr_reg),
            .unsigned => .@"ldx.bu"(dst, base, ptr_reg),
        }),
        2 => try isel.emit(switch (signedness) {
            .signed => .@"ldx.h"(dst, base, ptr_reg),
            .unsigned => .@"ldx.hu"(dst, base, ptr_reg),
        }),
        4 => try isel.emit(switch (signedness) {
            .signed => .@"ldx.w"(dst, base, ptr_reg),
            .unsigned => .@"ldx.wu"(dst, base, ptr_reg),
        }),
        8 => try isel.emit(.@"ldx.d"(dst, base, ptr_reg)),
        else => {
            try isel.loadReg(dst, size, signedness, ptr_reg, 0);
            try isel.emit(.@"add.d"(ptr_reg, ptr_reg, base));
        },
    }
    try isel.moveIntImm(ptr_reg, std.math.cast(i64, offset) orelse return isel.fail("unimplemented load with large offset", .{}));
}

/// Stores a register to memory [base + offset]
fn storeReg(
    isel: *Select,
    src: Register,
    size: u64,
    base: Register,
    offset: i65,
) !void {
    if (src.class() != .int) return isel.fail("TODO storeReg {t}", .{src});
    switch (size) {
        0 => unreachable,
        1 => {
            if (std.math.cast(i12, offset)) |small_off| return isel.emit(.@"st.b"(src, base, small_off));
        },
        2 => {
            if (std.math.cast(i12, offset)) |small_off| return isel.emit(.@"st.h"(src, base, small_off));
        },
        4 => {
            if (std.math.cast(i12, offset)) |small_off| return isel.emit(.@"st.w"(src, base, small_off));
            if (std.math.cast(i16, offset)) |small_off| {
                if ((small_off & 0b11) == 0) {
                    return isel.emit(.@"stox4.w"(src, base, @intCast(@divExact(small_off, 4))));
                }
            }
        },
        8 => {
            if (std.math.cast(i12, offset)) |small_off| return isel.emit(.@"st.d"(src, base, small_off));
            if (std.math.cast(i16, offset)) |small_off| {
                if ((small_off & 0b11) == 0) {
                    return isel.emit(.@"stox4.d"(src, base, @intCast(@divExact(small_off, 4))));
                }
            }
        },
        else => return try isel.failUnimplemented("bad store size: {d}", .{size}),
    }

    if (std.math.cast(i64, offset)) |offset64| stx: {
        const ptr_reg = try isel.allocRegForWrite(.int);
        defer isel.freeReg(ptr_reg);
        switch (size) {
            1 => try isel.emit(.@"stx.b"(src, base, ptr_reg)),
            2 => try isel.emit(.@"stx.h"(src, base, ptr_reg)),
            4 => try isel.emit(.@"stx.w"(src, base, ptr_reg)),
            8 => try isel.emit(.@"stx.d"(src, base, ptr_reg)),
            else => break :stx,
        }
        try isel.moveIntImm(ptr_reg, offset64);
    }

    const ptr_reg = try isel.allocRegForWrite(.int);
    defer isel.freeReg(ptr_reg);
    try isel.storeReg(src, size, ptr_reg, 0);
    try isel.emit(if (offset > 0) .@"add.d"(ptr_reg, ptr_reg, base) else .@"sub.d"(ptr_reg, ptr_reg, base));
    try isel.moveIntImm(ptr_reg, @intCast(@abs(offset)));
}

/// Copies a part of a register to another.
fn moveReg(
    isel: *Select,
    dst_ra: Register.Alias,
    dst_bit_off: u9,
    src_ra: Register.Alias,
    src_bit_off: u9,
    bit_size: u16,
    init_dst_prot: DestProtection,
) !void {
    if (dst_ra.reg == src_ra.reg and dst_bit_off == src_bit_off) return;
    if (bit_size == 0) return;
    assert(init_dst_prot != .preserved or (isel.live_registers.get(dst_ra.reg) == .allocating));
    assert(isel.live_registers.get(src_ra.reg) == .allocating);

    const dst_ra_bit_size = dst_ra.mod.bitSize(isel.target);
    const src_ra_bit_size = src_ra.mod.bitSize(isel.target);
    const dst_msb_plus_one = dst_bit_off + bit_size;
    const src_msb_plus_one = src_bit_off + bit_size;
    assert(dst_msb_plus_one <= dst_ra_bit_size and src_msb_plus_one <= src_ra_bit_size);

    const dst_prot: DestProtection = switch (init_dst_prot) {
        .preserved => if (bit_size == dst_ra_bit_size) .none else .preserved,
        else => init_dst_prot,
    };

    const dst_lock = isel.tryLockReg(dst_ra.reg);
    defer dst_lock.unlock(isel);
    const src_lock = isel.tryLockReg(src_ra.reg);
    defer src_lock.unlock(isel);

    switch (dst_ra.mod) {
        .integer => switch (src_ra.mod) {
            .integer => {
                if (dst_bit_off == src_bit_off and dst_prot == .none)
                    return try isel.emit(.ori(dst_ra.reg, src_ra.reg, 0));
                // bstrins
                const tmp_reg = tmp_reg: {
                    if (dst_bit_off == 0 and dst_prot != .none) break :tmp_reg dst_ra.reg;
                    const tmp_reg = if (src_bit_off == 0) src_ra.reg else try isel.allocRegForWrite(.int);
                    const dst_msbw = dst_msb_plus_one - 1;
                    try isel.emit(switch (dst_ra_bit_size) {
                        32 => .@"bstrins.w"(dst_ra.reg, tmp_reg, @intCast(dst_msbw), @intCast(dst_bit_off)),
                        64 => .@"bstrins.d"(dst_ra.reg, tmp_reg, @intCast(dst_msbw), @intCast(dst_bit_off)),
                        else => unreachable,
                    });
                    break :tmp_reg tmp_reg;
                };
                defer if (tmp_reg != dst_ra.reg and tmp_reg != src_ra.reg) isel.freeReg(tmp_reg);
                // bstrpick
                const src_msbw = src_msb_plus_one - 1;
                try isel.emit(switch (dst_ra_bit_size) {
                    32 => .@"bstrpick.w"(tmp_reg, src_ra.reg, @intCast(src_msbw), @intCast(src_bit_off)),
                    64 => .@"bstrpick.d"(tmp_reg, src_ra.reg, @intCast(src_msbw), @intCast(src_bit_off)),
                    else => unreachable,
                });
            },
            else => return isel.fail("unimplemented non-integral moveReg", .{}),
        },
        else => return isel.fail("unimplemented non-integral moveReg", .{}),
    }
}

/// Moves an immediate to a register.
fn moveIntImm(isel: *Select, rd: Register, si64: i64) !void {
    wip_mir_log.debug("  | # moveImm {t} <- 0x{x}", .{ rd, si64 });
    if (std.math.cast(u12, si64)) |imm12| return isel.emit(.ori(rd, .zero, imm12));

    const ori12: u12 = @truncate(@as(u64, @bitCast(si64)));
    const lu12i20: i20 = @truncate(si64 >> 12);
    const use_lu12iw = lu12i20 != 0;
    const lu32i20: i20 = @truncate(si64 >> 32);
    const use_lu32id = lu32i20 != hi: {
        if (use_lu12iw) break :hi @as(i20, @intCast(@as(i1, @truncate(si64 >> 31))));
        break :hi 0;
    };
    const lu52i12: i12 = @truncate(si64 >> 52);
    const use_lu52id = lu52i12 != hi: {
        if (use_lu32id) break :hi @as(i12, @intCast(@as(i1, @truncate(si64 >> 51))));
        if (use_lu12iw) break :hi @as(i12, @intCast(@as(i1, @truncate(si64 >> 31))));
        break :hi 0;
    };
    const use_ori = (ori12 != 0) or (!use_lu12iw and use_lu32id) or si64 == 0;
    const ori_rj = if (use_lu12iw) rd else Register.zero;
    const lu52id_rj = if (use_ori or use_lu12iw) rd else Register.zero;

    if (use_lu52id) try isel.emit(.@"cu52i.d"(rd, lu52id_rj, lu52i12));
    if (use_lu32id) try isel.emit(.@"cu32i.d"(rd, lu32i20));
    if (use_ori) try isel.emit(.ori(rd, ori_rj, ori12));
    if (use_lu12iw) try isel.emit(.@"lu12i.w"(rd, lu12i20));
}

fn addImm(isel: *Select, rd: Register, rj: Register, si65: i65) !void {
    const gpr_size = isel.gprSize();
    if (si65 == 0) {
        try isel.emit(.ori(rd, rj, 0));
    } else if (std.math.cast(i12, si65)) |si12| {
        switch (gpr_size) {
            4 => try isel.emit(.@"addi.w"(rd, rj, si12)),
            8 => try isel.emit(.@"addi.d"(rd, rj, si12)),
            else => unreachable,
        }
    } else {
        if (si65 >= 0) switch (gpr_size) {
            4 => try isel.emit(.@"add.w"(rd, rd, rj)),
            8 => try isel.emit(.@"add.d"(rd, rd, rj)),
            else => unreachable,
        } else switch (gpr_size) {
            4 => try isel.emit(.@"sub.w"(rd, rd, rj)),
            8 => try isel.emit(.@"sub.d"(rd, rd, rj)),
            else => unreachable,
        }
        try isel.moveIntImm(rd, @bitCast(@as(u64, @truncate(@as(u65, @bitCast(si65))))));
    }
}

/// Loads the incoming value of a register.
fn ldIncoming(isel: *Select, rd: Register, rj: Register) !void {
    wip_mir_log.debug("  | # ldIncoming {t} <- {t}", .{ rd, rj });
    try isel.layout_relocs.append(isel.pt.zcu.gpa, @intCast(isel.instructions.items.len));
    try isel.emit(.ori(rd, rj, 0));
}

fn cmp(
    isel: *Select,
    res_reg: Register,
    ty: ZigType,
    lhs_vi: Value.Index,
    op: std.math.CompareOperator,
    rhs_vi: Value.Index,
) !void {
    wip_mir_log.debug("  | # cmp {f}, {t}, {f}, {t}, {f}", .{ isel.fmtType(ty), res_reg, lhs_vi, op, rhs_vi });
    if (!ty.isRuntimeFloat() and !ty.isArrayOrVector(isel.pt.zcu)) {
        // integeral comparison
        const int_info: std.builtin.Type.Int = if (ty.toIntern() == .bool_type)
            .{ .signedness = .unsigned, .bits = 1 }
        else if (ty.isAbiInt(isel.pt.zcu))
            ty.intInfo(isel.pt.zcu)
        else if (ty.isPtrAtRuntime(isel.pt.zcu))
            .{ .signedness = .unsigned, .bits = 64 }
        else
            return isel.fail("bad cmp_{t} {f}", .{ op, isel.fmtType(ty) });

        var part_offset = lhs_vi.size(isel);
        while (part_offset > 0) {
            const part_size = @min(part_offset, isel.gprSize());
            part_offset -= part_size;
            // TODO optimize constant cmp
            // TODO relax LHS and RHS extension mode requirements to != .garbage
            const lhs_part_vi = try lhs_vi.partExact(isel, part_offset, part_size);
            const lhs_part_mat = try lhs_part_vi.matIntRegZeroExt(isel);
            const lhs_part_reg = lhs_part_mat.reg();
            const rhs_part_vi = try rhs_vi.partExact(isel, part_offset, part_size);
            const rhs_part_mat = try rhs_part_vi.matIntRegZeroExt(isel);
            const rhs_part_reg = rhs_part_mat.reg();

            const res_part_reg = if (part_offset == 0) res_reg else res_part_reg: {
                const res_part_reg = try isel.allocRegForWrite(.int);
                try isel.emit(.@"or"(res_reg, res_reg, res_part_reg));
                break :res_part_reg res_part_reg;
            };
            defer if (res_part_reg != res_reg) isel.freeReg(res_part_reg);

            switch (op) {
                .eq => {
                    try isel.emit(.sltui(res_part_reg, res_part_reg, 1));
                    try isel.emit(.xor(res_part_reg, lhs_part_reg, rhs_part_reg));
                },
                .neq => {
                    try isel.emit(.sltu(res_part_reg, .zero, res_part_reg));
                    try isel.emit(.xor(res_part_reg, lhs_part_reg, rhs_part_reg));
                },
                .lt, .lte, .gt, .gte => {
                    var rj = lhs_part_reg;
                    var rk = rhs_part_reg;

                    switch (op) {
                        .lte, .gt => std.mem.swap(Register, &rj, &rk),
                        else => {},
                    }
                    switch (op) {
                        .lte, .gte => try isel.emit(.xori(res_part_reg, res_part_reg, 1)),
                        else => {},
                    }

                    try isel.emit(switch (int_info.signedness) {
                        .signed => .slt(res_part_reg, rj, rk),
                        .unsigned => .sltu(res_part_reg, rj, rk),
                    });
                },
            }
            try rhs_part_mat.finish(isel);
            try lhs_part_mat.finish(isel);
        }
    } else return isel.fail("bad cmp_{t} {f}", .{ op, isel.fmtType(ty) });
}

const AddOrSubtractOptions = struct {
    overflow: Overflow,

    const Overflow = union(enum) {
        @"unreachable",
        panic: Zcu.SimplePanicId,
        wrap,
        reg: Register,
    };
};

// TODO optimize constant add/sub
fn addOrSubtract(
    isel: *Select,
    ty: ZigType,
    res_vi: Value.Index,
    op: enum { add, sub },
    lhs_vi: Value.Index,
    rhs_vi: Value.Index,
    opts: AddOrSubtractOptions,
) !void {
    wip_mir_log.debug("  | # {t} ty = {f}, res = {f}, lhs = {f}, rhs = {f}, overflow = {t}", .{ op, isel.fmtType(ty), res_vi, lhs_vi, rhs_vi, opts.overflow });
    // TODO: implement opts.overflow
    const zcu = isel.pt.zcu;
    assert(ty.isAbiInt(zcu));
    const int_info = ty.intInfo(zcu);

    if (int_info.bits <= 32) {
        try res_vi.reextendToGarbage(isel); // TODO optimize
        const res_reg = try res_vi.defRegMod(isel, .integer) orelse return;
        const lhs_mat = try lhs_vi.matIntRegZeroExt(isel);
        const rhs_mat = try rhs_vi.matIntRegZeroExt(isel);

        switch (op) {
            .add => try isel.emit(.@"add.w"(res_reg, lhs_mat.reg(), rhs_mat.reg())),
            .sub => try isel.emit(.@"sub.w"(res_reg, lhs_mat.reg(), rhs_mat.reg())),
        }

        try lhs_mat.finish(isel);
        try rhs_mat.finish(isel);
    } else if (int_info.bits <= 64) {
        try res_vi.reextendToGarbage(isel); // TODO optimize
        const res_reg = try res_vi.defRegMod(isel, .integer) orelse return;
        const lhs_mat = try lhs_vi.matIntRegZeroExt(isel);
        const rhs_mat = try rhs_vi.matIntRegZeroExt(isel);

        switch (op) {
            .add => try isel.emit(.@"add.d"(res_reg, lhs_mat.reg(), rhs_mat.reg())),
            .sub => try isel.emit(.@"sub.d"(res_reg, lhs_mat.reg(), rhs_mat.reg())),
        }

        try lhs_mat.finish(isel);
        try rhs_mat.finish(isel);
    } else {
        if (debug_trap_unimplemented_code) {
            isel.wipeLocationDfs(res_vi);
        }
        return try isel.failUnimplemented("unimplemented {t} {f}", .{ op, isel.fmtType(ty) });
    }
}

/// elem_ptr = base +- elem_size * index
/// elem_ptr, base, and index may alias. base_reg must be locked.
fn elemPtr(
    isel: *Select,
    rd: Register,
    base_reg: Register,
    op: enum { add, sub },
    elem_size: u64,
    index_vi: Value.Index,
) !void {
    assert(isel.live_registers.get(base_reg) == .allocating);
    wip_mir_log.debug("  | # elemPtr {t} = {t} {s} {f} * {d} (= 0b{b})", .{ rd, base_reg, switch (op) {
        .add => "+",
        .sub => "-",
    }, index_vi, elem_size, elem_size });
    switch (@popCount(elem_size)) {
        0 => unreachable, // Sema should optimize this
        1 => {
            const shift = @ctz(elem_size);
            if (shift == 0) {
                const index_mat = try index_vi.matIntRegZeroExt(isel);
                const index_reg = index_mat.reg();
                try isel.emit(switch (op) {
                    .add => switch (isel.gprBits()) {
                        else => unreachable,
                        32 => .@"add.w"(rd, base_reg, index_reg),
                        64 => .@"add.d"(rd, base_reg, index_reg),
                    },
                    .sub => switch (isel.gprBits()) {
                        else => unreachable,
                        32 => .@"sub.w"(rd, base_reg, index_reg),
                        64 => .@"sub.d"(rd, base_reg, index_reg),
                    },
                });
                try index_mat.finish(isel);
                return;
            } else if (std.math.cast(u2, shift - 1)) |sa2| {
                switch (op) {
                    .add => {
                        const index_mat = try index_vi.matIntRegZeroExt(isel);
                        const index_reg = index_mat.reg();
                        try isel.emit(switch (isel.gprBits()) {
                            else => unreachable,
                            32 => .@"sladd.w"(rd, index_reg, base_reg, sa2),
                            64 => .@"sladd.d"(rd, index_reg, base_reg, sa2),
                        });
                        try index_mat.finish(isel);
                        return;
                    },
                    .sub => {
                        if (base_reg != rd) {
                            const index_mat = try index_vi.matIntRegZeroExt(isel);
                            const index_reg = index_mat.reg();
                            switch (isel.gprBits()) {
                                else => unreachable,
                                32 => {
                                    try isel.emit(.@"sladd.w"(rd, rd, base_reg, sa2));
                                    try isel.emit(.@"sub.w"(rd, .zero, index_reg));
                                },
                                64 => {
                                    try isel.emit(.@"sladd.d"(rd, rd, base_reg, sa2));
                                    try isel.emit(.@"sub.d"(rd, .zero, index_reg));
                                },
                            }
                            try index_mat.finish(isel);
                            return;
                        }
                    },
                }
            }
        },
        2 => {
            const shift1 = @ctz(elem_size);
            const mask1 = @as(u64, 1) << @intCast(shift1);
            const mask2 = elem_size & ~mask1;

            if ((op == .add or base_reg != rd) and mask1 <= 4 and mask2 <= 4) {
                try isel.elemPtr(rd, rd, op, mask2, index_vi);
                try isel.elemPtr(rd, base_reg, op, mask1, index_vi);
                return;
            }
        },
        else => {},
    }

    const index_mat = try index_vi.matIntRegZeroExt(isel);
    const index_reg = index_mat.reg();
    const offset_reg = if (base_reg != rd) rd else try isel.allocRegForWrite(.int);
    defer if (offset_reg != rd) isel.freeReg(offset_reg);
    try isel.emit(switch (op) {
        .add => switch (isel.gprBits()) {
            else => unreachable,
            32 => .@"add.w"(rd, base_reg, offset_reg),
            64 => .@"add.d"(rd, base_reg, offset_reg),
        },
        .sub => switch (isel.gprBits()) {
            else => unreachable,
            32 => .@"sub.w"(rd, base_reg, offset_reg),
            64 => .@"sub.d"(rd, base_reg, offset_reg),
        },
    });
    try isel.emit(switch (isel.gprBits()) {
        else => unreachable,
        32 => .@"mul.w"(offset_reg, offset_reg, index_reg),
        64 => .@"mul.d"(offset_reg, offset_reg, index_reg),
    });
    try isel.moveIntImm(offset_reg, @bitCast(elem_size));
    try index_mat.finish(isel);
}

fn moveLoc(
    isel: *Select,
    dst_loc: Value.Location,
    dst_off: u64,
    src_loc: Value.Location,
    src_off: u64,
    size: u64,
    dst_prot: DestProtection,
) !void {
    if (dst_loc.isUnallocated()) return;
    if (std.meta.eql(dst_loc, src_loc) and dst_off == src_off) return;
    if (size == 0) return;
    assert(!src_loc.isUnallocated());
    wip_mir_log.debug("  | # move {f}[{d}] <- {f}[{d}], {d}B, dst prot={t}", .{
        dst_loc,
        dst_off,
        src_loc,
        src_off,
        size,
        dst_prot,
    });

    const dst_lock: RegLock = if (dst_prot != .preserved) .empty else dst_loc.tryLock(isel);
    defer dst_lock.unlock(isel);
    const src_lock = src_loc.tryLock(isel);
    defer src_lock.unlock(isel);

    switch (dst_loc) {
        .register => |dst_ra| switch (src_loc) {
            .register => |src_ra| try isel.moveReg(
                dst_ra,
                @intCast(dst_off * 8),
                src_ra,
                @intCast(src_off * 8),
                @intCast(size * 8),
                dst_prot,
            ),
            .stack_slot => |src_stack| {
                const tmp_reg = if (dst_ra.mod == .integer and dst_off == 0)
                    dst_ra.reg
                else
                    try isel.allocRegForWrite(.int);
                defer if (tmp_reg != dst_ra.reg) isel.freeReg(tmp_reg);
                try isel.moveReg(
                    dst_ra,
                    @intCast(dst_off * 8),
                    .{ .reg = tmp_reg, .mod = .integer },
                    0,
                    @intCast(size * 8),
                    dst_prot,
                );
                try isel.loadReg(
                    tmp_reg,
                    memOpSizeFitting(size),
                    .unsigned,
                    src_stack.base,
                    src_stack.offset + @as(i65, src_off),
                );
            },
        },
        .stack_slot => |dst_stack| {
            if (size > isel.gprSize()) {
                // large memory copies, src must be stack_slot
                const src_stack = src_loc.stack_slot;
                // TODO optimize to memmove call

                const known_direction, const gen_low_to_high, const gen_high_to_low = move_dir: {
                    if (dst_stack.base == src_stack.base) {
                        if (dst_stack.offset == src_stack.offset) return;
                        break :move_dir if (dst_stack.offset < src_stack.offset)
                            .{ true, false, true }
                        else
                            .{ true, true, false };
                    }
                    // cannot determine direction
                    if (assume_memmove_no_overlap)
                        break :move_dir .{ true, true, false };
                    break :move_dir .{ false, true, true };
                };
                if (!known_direction) {
                    return isel.failUnimplemented("TODO moveLoc memmove", .{});
                }

                const gpr_size = isel.gprSize();
                const steps = std.math.divCeil(u64, size, gpr_size) catch unreachable;
                if (gen_low_to_high) {
                    var off: u64 = 0;
                    for (0..@intCast(steps)) |_| {
                        try isel.moveLoc(dst_loc, dst_off + off, src_loc, src_off + off, gpr_size, dst_prot);
                        off += gpr_size;
                    }
                }
                if (gen_high_to_low) {
                    var off: u64 = steps * gpr_size;
                    for (0..@intCast(steps)) |_| {
                        off -= gpr_size;
                        try isel.moveLoc(dst_loc, dst_off + off, src_loc, src_off + off, gpr_size, dst_prot);
                    }
                }

                return;
            }

            // Move to a temp reg + store
            // If size is not direct mem op size and !kill_dst, old values have to
            // be loaded first.
            const memop_size = memOpSizeFitting(size);
            const need_load = memop_size != size;
            const tmp_reg, const tmp_allocated = tmp_reg: {
                if (src_off == 0 and !need_load) {
                    switch (src_loc) {
                        .register => |src_ra| if (src_ra.mod == .integer)
                            break :tmp_reg .{ src_ra.reg, false },
                        else => {},
                    }
                }
                break :tmp_reg .{ try isel.allocRegForWrite(.int), true };
            };
            defer if (tmp_allocated) isel.freeReg(tmp_reg);

            const dst_stack_off = dst_stack.offset + @as(i65, dst_off);
            try isel.storeReg(tmp_reg, memop_size, dst_stack.base, dst_stack_off);
            if (tmp_allocated)
                try isel.moveLoc(
                    .{ .register = .{ .reg = tmp_reg, .mod = .integer } },
                    0,
                    src_loc,
                    src_off,
                    size,
                    if (need_load) .preserved else .none,
                );
            if (need_load)
                try isel.loadReg(tmp_reg, memop_size, .unsigned, dst_stack.base, dst_stack_off);
        },
    }
}

fn moveUndef(isel: *Select, dst_loc: Value.Location, size: u64) !void {
    if (isel.opt_mode == .fast or isel.opt_mode == .small) return;
    wip_mir_log.debug("  | # move {f} ({d}B) <- undef", .{ dst_loc, size });
    switch (dst_loc) {
        .register => |dst_ra| {
            assert(dst_ra.mod == .integer); // TODO
            try isel.moveIntImm(dst_ra.reg, switch (isel.gprBits()) {
                32 => 0xAAAAAAAA,
                64 => @bitCast(@as(u64, 0xAAAAAAAAAAAAAAAA)),
                else => unreachable,
            });
        },
        .stack_slot => {
            // TODO write undef to memory
        },
    }
}

fn moveConstant(isel: *Select, dst: Value.Location, init_constant: Constant, init_offset: u64, size: u64) !void {
    wip_mir_log.debug("  | # move {f} <- {f} [{d}..{d}]", .{ dst, isel.fmtConstant(init_constant), init_offset, init_offset + size - 1 });
    var offset = init_offset;
    const zcu = isel.pt.zcu;
    const ip = &zcu.intern_pool;
    var constant = init_constant.toIntern();
    var constant_key = ip.indexToKey(constant);
    while (true) {
        // Try to coerce the constant value
        // also try better codegen
        constant_key: switch (constant_key) {
            else => {},
            .undef => return try isel.moveUndef(dst, size),
            .simple_value => |simple_value| switch (simple_value) {
                .void => {},
                .null, .@"unreachable" => unreachable,
                .true => continue :constant_key .{ .int = .{ .ty = .bool_type, .storage = .{ .u64 = 1 } } },
                .false => continue :constant_key .{ .int = .{ .ty = .bool_type, .storage = .{ .u64 = 0 } } },
            },
            .int => |int| if (dst.asRegisterAlias()) |dst_ra| {
                if (dst_ra.mod != .integer) break :constant_key;
                const dst_reg = dst_ra.reg;
                return switch (int.storage) {
                    .u64 => |imm| try isel.moveIntImm(dst_reg, @bitCast(std.math.shr(u64, imm, 8 * offset))),
                    .i64 => |imm| switch (size) {
                        else => unreachable,
                        1...4 => try isel.moveIntImm(dst_reg, @as(u32, @bitCast(@as(i32, @truncate(std.math.shr(i64, imm, 8 * offset)))))),
                        5...8 => try isel.moveIntImm(dst_reg, @bitCast(std.math.shr(i64, imm, 8 * offset))),
                    },
                    .big_int => |big_int| {
                        assert(size == isel.gprSize());
                        var imm: u64 = 0;
                        const limb_bits = @bitSizeOf(std.math.big.Limb);
                        const limbs = @divExact(64, limb_bits);
                        var limb_index: usize = @intCast(@divExact(offset, @divExact(limb_bits, 8)) + limbs);
                        for (0..limbs) |_| {
                            limb_index -= 1;
                            if (limb_index >= big_int.limbs.len) continue;
                            if (limb_bits < 64) imm <<= limb_bits;
                            imm |= big_int.limbs[limb_index];
                        }
                        if (!big_int.positive) {
                            limb_index = @min(limb_index, big_int.limbs.len);
                            imm = while (limb_index > 0) {
                                limb_index -= 1;
                                if (big_int.limbs[limb_index] != 0) break ~imm;
                            } else -%imm;
                        }
                        try isel.moveIntImm(dst_reg, @bitCast(imm));
                    },
                };
            },
            .err => |err| continue :constant_key .{ .int = .{
                .ty = err.ty,
                .storage = .{ .u64 = ip.getErrorValueIfExists(err.name).? },
            } },
            .error_union => |error_union| {
                const error_union_type = ip.indexToKey(error_union.ty).error_union_type;
                const error_set_ty: ZigType = .fromInterned(error_union_type.error_set_type);
                const payload_ty: ZigType = .fromInterned(error_union_type.payload_type);
                const error_set_offset = codegen.errUnionErrorOffset(payload_ty, zcu);
                const error_set_size = error_set_ty.abiSize(zcu);
                if (offset >= error_set_offset and offset + size <= error_set_offset + error_set_size) {
                    offset -= error_set_offset;
                    continue :constant_key switch (error_union.val) {
                        .err_name => |err_name| .{ .err = .{
                            .ty = error_union_type.error_set_type,
                            .name = err_name,
                        } },
                        .payload => .{ .int = .{
                            .ty = error_union_type.error_set_type,
                            .storage = .{ .u64 = 0 },
                        } },
                    };
                }
                const payload_offset = codegen.errUnionPayloadOffset(payload_ty, zcu);
                const payload_size = payload_ty.abiSize(zcu);
                if (offset >= payload_offset and offset + size <= payload_offset + payload_size) {
                    offset -= payload_offset;
                    switch (error_union.val) {
                        .err_name => continue :constant_key .{ .undef = error_union_type.payload_type },
                        .payload => |payload| {
                            constant = payload;
                            constant_key = ip.indexToKey(constant);
                            continue :constant_key constant_key;
                        },
                    }
                }
            },
            .enum_tag => |enum_tag| continue :constant_key .{ .int = ip.indexToKey(enum_tag.int).int },
            .float => return isel.fail("float unimplemented", .{}),
            .ptr => |ptr| {
                assert(offset == 0 and size == isel.gprSize());
                const dst_ra: Register.Alias, const use_tmp_reg = select_tmp: {
                    if (dst.asRegisterAlias()) |dst_ra| {
                        if (dst_ra.mod == .integer) break :select_tmp .{ dst_ra, false };
                    }
                    break :select_tmp .{ .{ .reg = try isel.allocRegForWrite(.int), .mod = .integer }, true };
                };
                const rd = dst_ra.reg;
                defer if (use_tmp_reg) isel.freeReg(rd);

                if (use_tmp_reg) try isel.moveLoc(dst, 0, .{ .register = dst_ra }, 0, isel.gprSize(), .none);
                return switch (ptr.base_addr) {
                    .nav => |nav| if (ZigType.fromInterned(ip.getNav(nav).resolved.?.type).isRuntimeFnOrHasRuntimeBits(zcu)) {
                        // TODO code model
                        try isel.nav_relocs.append(zcu.gpa, .{
                            .nav = nav,
                            .reloc = .{
                                .label = @intCast(isel.instructions.items.len),
                                .addend = @intCast(ptr.byte_offset),
                            },
                        });
                        try isel.emit(.@"addi.d"(rd, rd, 0));
                        try isel.nav_relocs.append(zcu.gpa, .{
                            .nav = nav,
                            .reloc = .{
                                .label = @intCast(isel.instructions.items.len),
                                .addend = @intCast(ptr.byte_offset),
                            },
                        });
                        try isel.emit(.pcalau12i(rd, 0));
                    } else continue :constant_key .{ .int = .{
                        .ty = .usize_type,
                        .storage = .{ .u64 = isel.pt.zcu.navAlignment(nav).forward(0xaaaaaaaaaaaaaaaa) },
                    } },
                    .uav => |uav| if (ZigType.fromInterned(ip.typeOf(uav.val)).isRuntimeFnOrHasRuntimeBits(zcu)) {
                        // TODO code model
                        try isel.uav_relocs.append(zcu.gpa, .{
                            .uav = uav,
                            .reloc = .{
                                .label = @intCast(isel.instructions.items.len),
                                .addend = @intCast(ptr.byte_offset),
                            },
                        });
                        try isel.emit(.@"addi.d"(rd, rd, 0));
                        try isel.uav_relocs.append(zcu.gpa, .{
                            .uav = uav,
                            .reloc = .{
                                .label = @intCast(isel.instructions.items.len),
                                .addend = @intCast(ptr.byte_offset),
                            },
                        });
                        try isel.emit(.pcalau12i(rd, 0));
                    } else continue :constant_key .{ .int = .{
                        .ty = .usize_type,
                        .storage = .{ .u64 = ZigType.fromInterned(uav.orig_ty).ptrAlignment(zcu).forward(0xaaaaaaaaaaaaaaaa) },
                    } },
                    .int => continue :constant_key .{ .int = .{
                        .ty = .usize_type,
                        .storage = .{ .u64 = ptr.byte_offset },
                    } },
                    .eu_payload => |base| {
                        var base_ptr = ip.indexToKey(base).ptr;
                        const eu_ty = ip.indexToKey(base_ptr.ty).ptr_type.child;
                        const payload_ty = ip.indexToKey(eu_ty).error_union_type.payload_type;
                        base_ptr.byte_offset += codegen.errUnionPayloadOffset(.fromInterned(payload_ty), zcu) + ptr.byte_offset;
                        continue :constant_key .{ .ptr = base_ptr };
                    },
                    .opt_payload => |base| {
                        var base_ptr = ip.indexToKey(base).ptr;
                        base_ptr.byte_offset += ptr.byte_offset;
                        continue :constant_key .{ .ptr = base_ptr };
                    },
                    .field => |field_idx| {
                        var base_ptr = ip.indexToKey(field_idx.base).ptr;
                        const agg_ty: ZigType = .fromInterned(ip.indexToKey(base_ptr.ty).ptr_type.child);
                        base_ptr.byte_offset += agg_ty.structFieldOffset(@intCast(field_idx.index), zcu) + ptr.byte_offset;
                        continue :constant_key .{ .ptr = base_ptr };
                    },
                    .comptime_alloc, .comptime_field, .arr_elem => unreachable,
                };
            },
            .slice => |slice| {
                const ptr_size = isel.gprSize();
                if (offset == 0 and size == ptr_size) {
                    constant = slice.ptr;
                    continue :constant_key switch (ip.indexToKey(slice.ptr)) {
                        else => unreachable,
                        .undef => |undef| .{ .undef = undef },
                        .ptr => |ptr| .{ .ptr = ptr },
                    };
                } else if (offset == ptr_size) {
                    offset = 0;
                    constant = slice.len;
                    continue :constant_key ip.indexToKey(slice.len);
                } else if (offset == 0 and size == (@as(u64, ptr_size) * 2)) {
                    const dst_stack = dst.asStackSlot().?;
                    try moveConstant(
                        isel,
                        .{ .stack_slot = dst_stack },
                        .fromInterned(slice.ptr),
                        0,
                        ptr_size,
                    );
                    try moveConstant(
                        isel,
                        .{ .stack_slot = dst_stack.withOffset(ptr_size) },
                        .fromInterned(slice.len),
                        0,
                        ptr_size,
                    );
                    return;
                }
            },
            .opt => |opt| {
                const child_ty = ip.indexToKey(opt.ty).opt_type;
                const child_size = ZigType.fromInterned(child_ty).abiSize(zcu);
                if (offset == child_size and size == 1) {
                    offset = 0;
                    continue :constant_key .{ .simple_value = switch (opt.val) {
                        .none => .false,
                        else => .true,
                    } };
                }
                const opt_ty: ZigType = .fromInterned(opt.ty);
                if (offset + size <= child_size) continue :constant_key switch (opt.val) {
                    .none => if (opt_ty.optionalReprIsPayload(zcu)) .{ .int = .{
                        .ty = opt.ty,
                        .storage = .{ .u64 = 0 },
                    } } else .{ .undef = child_ty },
                    else => |child| {
                        constant = child;
                        constant_key = ip.indexToKey(constant);
                        continue :constant_key constant_key;
                    },
                };
            },
            .aggregate => |aggregate| switch (ip.indexToKey(aggregate.ty)) {
                else => unreachable,
                .array_type => |array_type| {
                    const elem_size = ZigType.fromInterned(array_type.child).abiSize(zcu);
                    const elem_offset = @mod(offset, elem_size);
                    if (size <= elem_size - elem_offset) {
                        defer offset = elem_offset;
                        continue :constant_key switch (aggregate.storage) {
                            .bytes => |bytes| .{ .int = .{ .ty = .u8_type, .storage = .{
                                .u64 = bytes.toSlice(array_type.lenIncludingSentinel(), ip)[@intCast(@divFloor(offset, elem_size))],
                            } } },
                            .elems => |elems| {
                                constant = elems[@intCast(@divFloor(offset, elem_size))];
                                constant_key = ip.indexToKey(constant);
                                continue :constant_key constant_key;
                            },
                            .repeated_elem => |repeated_elem| {
                                constant = repeated_elem;
                                constant_key = ip.indexToKey(constant);
                                continue :constant_key constant_key;
                            },
                        };
                    }
                },
                .vector_type => {},
                .struct_type => {
                    const loaded_struct = ip.loadStructType(aggregate.ty);
                    switch (loaded_struct.layout) {
                        .auto => {
                            var field_it = loaded_struct.iterateRuntimeOrder(ip);
                            while (field_it.next()) |field_index| {
                                if (loaded_struct.field_is_comptime_bits.get(ip, field_index)) continue;
                                const field_ty: ZigType = .fromInterned(loaded_struct.field_types.get(ip)[field_index]);
                                const field_offset = loaded_struct.field_offsets.get(ip)[field_index];
                                const field_size = field_ty.abiSize(zcu);
                                if (offset >= field_offset and offset + size <= field_offset + field_size) {
                                    offset -= field_offset;
                                    constant = switch (aggregate.storage) {
                                        .bytes => unreachable,
                                        .elems => |elems| elems[field_index],
                                        .repeated_elem => |repeated_elem| repeated_elem,
                                    };
                                    constant_key = ip.indexToKey(constant);
                                    continue :constant_key constant_key;
                                }
                            }
                        },
                        .@"extern", .@"packed" => {},
                    }
                },
                .tuple_type => |tuple_type| {
                    var field_offset: u64 = 0;
                    for (tuple_type.types.get(ip), tuple_type.values.get(ip), 0..) |field_type, field_value, field_index| {
                        if (field_value != .none) continue;
                        const field_ty: ZigType = .fromInterned(field_type);
                        field_offset = field_ty.abiAlignment(zcu).forward(field_offset);
                        const field_size = field_ty.abiSize(zcu);
                        if (offset >= field_offset and offset + size <= field_offset + field_size) {
                            offset -= field_offset;
                            constant = switch (aggregate.storage) {
                                .bytes => unreachable,
                                .elems => |elems| elems[field_index],
                                .repeated_elem => |repeated_elem| repeated_elem,
                            };
                            constant_key = ip.indexToKey(constant);
                            continue :constant_key constant_key;
                        }
                        field_offset += field_size;
                    }
                },
            },
            .un => |un| {
                const loaded_union = ip.loadUnionType(un.ty);
                const union_layout = ZigType.getUnionLayout(loaded_union, zcu);
                if (loaded_union.has_runtime_tag) {
                    const tag_offset = union_layout.tagOffset();
                    if (offset >= tag_offset and offset + size <= tag_offset + union_layout.tag_size) {
                        offset -= tag_offset;
                        continue :constant_key switch (ip.indexToKey(un.tag)) {
                            else => unreachable,
                            .int => |int| .{ .int = int },
                            .enum_tag => |enum_tag| .{ .enum_tag = enum_tag },
                        };
                    }
                }
                const payload_offset = union_layout.payloadOffset();
                if (offset >= payload_offset and offset + size <= payload_offset + union_layout.payload_size) {
                    offset -= payload_offset;
                    constant = un.val;
                    constant_key = ip.indexToKey(constant);
                    continue :constant_key constant_key;
                }
            },
        }
        const constant_size = ZigType.fromInterned(constant_key.typeOf()).abiSize(zcu);
        var buffer: [128]u8 align(8) = @splat(0);
        // Large constants should have been coerced to smaller ones, so use a buffer with fixed-size
        if (constant_size <= buffer.len and
            try isel.writeConstantToMemory(.fromInterned(constant), &buffer))
        {
            // TODO lower to literals or lazy symbols and memcpy for larger constants
            assert(offset + size <= buffer.len);
            const part_buffer = buffer[@intCast(offset)..];
            const gpr_size = isel.gprSize();

            const tmp_reg, const tmp_lock: RegLock = tmp_reg: {
                if (dst.asRegisterAlias()) |dst_ra| {
                    if (dst_ra.mod == .integer) break :tmp_reg .{ dst_ra.reg, isel.tryLockReg(dst_ra.reg) };
                }
                const tmp_reg = try isel.allocRegForWrite(.int);
                break :tmp_reg .{ tmp_reg, .{ .reg = tmp_reg } };
            };
            defer tmp_lock.unlock(isel);
            const tmp_ra: Register.Alias = .{ .mod = .integer, .reg = tmp_reg };

            var part_offset = size & (0 -% gpr_size);
            while (true) {
                const part_size = @min(size - part_offset, gpr_size);
                const part_value: u64 = switch (part_size) {
                    else => unreachable,
                    0 => {
                        part_offset -= gpr_size;
                        continue;
                    },
                    inline 1...8 => |ct_size| std.mem.readInt(
                        @Int(.unsigned, 8 * @as(u16, ct_size)),
                        part_buffer[0..ct_size],
                        .little,
                    ),
                };

                try isel.moveLoc(dst, part_offset, .{ .register = tmp_ra }, 0, part_size, .preserved);
                try isel.moveIntImm(tmp_reg, @bitCast(part_value));

                if (part_offset == 0) break else part_offset -= gpr_size;
            }

            return;
        }
        if (ZigType.fromInterned(ip.typeOf(constant)).isRuntimeFnOrHasRuntimeBits(zcu)) {
            const ptr_ty = try isel.pt.singleConstPtrType(.fromInterned(ip.typeOf(constant)));
            const uav: InternPool.Key.Ptr.BaseAddr.Uav = .{
                .val = constant,
                .orig_ty = ptr_ty.ip_index,
            };

            // allocate temporary register for pointers
            const tmp_reg, const allocated_tmp_reg = tmp_reg: {
                if (dst.asRegisterAlias()) |dst_ra| {
                    if (dst_ra.mod == .integer) break :tmp_reg .{ dst_ra.reg, false };
                }
                break :tmp_reg .{ try isel.allocRegForWrite(.int), true };
            };
            defer if (allocated_tmp_reg) isel.freeReg(tmp_reg);

            // load from the pointer
            try isel.moveLoc(
                dst,
                0,
                .{ .stack_slot = .{ .base = tmp_reg, .offset = 0 } },
                offset,
                size,
                .none,
            );

            // load constant pointer
            try isel.uav_relocs.append(zcu.gpa, .{
                .uav = uav,
                .reloc = .{ .label = @intCast(isel.instructions.items.len), .addend = 0 },
            });
            try isel.emit(.@"addi.d"(tmp_reg, tmp_reg, 0));
            try isel.uav_relocs.append(zcu.gpa, .{
                .uav = uav,
                .reloc = .{
                    .label = @intCast(isel.instructions.items.len),
                    .addend = 0,
                },
            });
            try isel.emit(.pcalau12i(tmp_reg, 0));

            return;
        }
        return isel.fail("unsupported value <{f}, {f}>[{d}..{d}] (full size={d}), from <{f}, {f}>[{d}..{d}]", .{
            isel.fmtType(.fromInterned(constant_key.typeOf())),
            isel.fmtConstant(.fromInterned(constant)),
            offset,
            offset + size - 1,
            constant_size,
            isel.fmtType(init_constant.typeOf(zcu)),
            isel.fmtConstant(init_constant),
            init_offset,
            init_offset + size - 1,
        });
    }
}

/// Returns the minimum legal memory operation size that is equal or greater than the given size.
fn memOpSizeFitting(size: u64) u64 {
    return switch (size) {
        0 => unreachable,
        1 => 1,
        2 => 2,
        3...4 => 4,
        5...8 => 8,
        9...16 => 16,
        17...32 => 32,
        else => unreachable,
    };
}

pub const CallAbiIterator = struct {
    isel: *Select,
    cc: *const std.builtin.CallingConvention,
    next_reg: std.EnumArray(RegisterClass, Register) = .init(.{
        .gpr = .r4,
        .fpr = .f0,
        .ret_byref = .r4,
    }),
    next_stack: usize = 0,
    // TODO optimize, use SP to read incoming arguments when possible
    stack_pointer: Register = .sp,

    const RegisterClass = enum {
        gpr,
        fpr,
        /// Virtual register class, for allocating GPRs for by-reference returning.
        ret_byref,
    };

    fn allocReg(it: *CallAbiIterator, class: RegisterClass) ?Register {
        const last_reg: Register = switch (class) {
            .gpr, .ret_byref => .r11,
            .fpr => .f7,
        };
        const next = it.next_reg.getPtr(class);
        if (@backingInt(last_reg) >= @backingInt(next.*)) {
            const allocated = next.*;
            next.* = @fromBackingInt(@backingInt(allocated) + 1);
            return allocated;
        } else return null;
    }

    /// Trys to allocate some registers, returning amount of allocated registers.
    fn allocRegs(it: *CallAbiIterator, class: RegisterClass, result: []Register) usize {
        const last_reg: Register = switch (class) {
            .gpr, .ret_byref => .r11,
            .fpr => .f7,
        };
        const next = it.next_reg.getPtr(class);
        const remaining = @backingInt(last_reg) - @backingInt(next.*) + 1;
        if (remaining >= result.len) {
            for (result, @backingInt(next.*)..) |*v, reg|
                v.* = @fromBackingInt(@intCast(reg));
            next.* = @fromBackingInt(@intCast(@backingInt(next.*) + result.len));
            return result.len;
        } else {
            for (@backingInt(next.*)..@backingInt(last_reg) + 1, result[0..remaining]) |reg, *v|
                v.* = @fromBackingInt(@intCast(reg));
            next.* = @fromBackingInt(@backingInt(last_reg) + 1);
            return remaining;
        }
    }

    fn assignStack(it: *CallAbiIterator, wip_vi: Value.Index) void {
        const isel = it.isel;
        assert(wip_vi.stackSlot(isel) == null);
        it.next_stack = @intCast(wip_vi.alignment(isel).forward(it.next_stack));
        wip_vi.setStackSlot(isel, .{
            .base = it.stack_pointer,
            .offset = @intCast(it.next_stack),
        });
        it.next_stack += @intCast(wip_vi.size(isel));
    }

    fn assignUsize(it: *CallAbiIterator, isel: *Select, wip_vi: Value.Index) void {
        if (it.allocReg(.gpr)) |reg| {
            wip_vi.setHintRegister(isel, reg);
        } else it.assignStack(wip_vi);
    }

    fn assignGprPair(it: *CallAbiIterator, isel: *Select, wip_vi: Value.Index, part_sizes: [2]u64, part_bit_size: [2]u9) !void {
        const grsize: u8 = isel.gprSize();
        var regs: [2]Register = undefined;
        const allocated_regs = it.allocRegs(.gpr, &regs);
        switch (allocated_regs) {
            0 => it.assignStack(wip_vi),
            1 => {
                wip_vi.setParts(isel, 2);
                (try wip_vi.addIntPart(isel, 0, part_sizes[0], part_bit_size[0])).setHintRegister(isel, regs[0]);
                it.assignStack(try wip_vi.addIntPart(isel, grsize, part_sizes[1], part_bit_size[1]));
            },
            2 => {
                wip_vi.setParts(isel, 2);
                (try wip_vi.addIntPart(isel, 0, part_sizes[0], part_bit_size[0])).setHintRegister(isel, regs[0]);
                (try wip_vi.addIntPart(isel, grsize, part_sizes[1], part_bit_size[1])).setHintRegister(isel, regs[1]);
            },
            else => unreachable,
        }
    }

    fn assignIndirect(it: *CallAbiIterator, isel: *Select, wip_vi: Value.Index, is_return: bool) void {
        const wip_address_vi = isel.initValueAssumeCapacity(.usize);
        wip_vi.setParent(isel, .{ .address = wip_address_vi });

        if (it.allocReg(if (is_return) .ret_byref else .gpr)) |reg| {
            wip_address_vi.setHintRegister(isel, reg);
        } else it.assignStack(wip_address_vi);
    }

    pub fn resolve(it: *CallAbiIterator, ty: ZigType, is_return: bool) !?Value.Index {
        const isel = it.isel;
        const zcu = isel.pt.zcu;
        const ip = &zcu.intern_pool;

        if (!ty.hasRuntimeBits(zcu)) return null;
        try isel.values.ensureUnusedCapacity(zcu.gpa, Value.max_parts);
        try isel.value_types.ensureUnusedCapacity(zcu.gpa, Value.max_parts);
        const wip_vi = isel.initValueAssumeCapacity(ty);
        wip_vi.setExtension(isel, .pcsMode(isel, ty));

        const grsize = isel.gprSize();
        const grlen: u8 = isel.gprBits();

        type_key: switch (ip.indexToKey(ty.toIntern())) {
            else => return isel.fail("CallAbiIterator.resolve({f})", .{isel.fmtType(ty)}),
            .int_type => |int_ty| {
                if (int_ty.bits <= grlen) {
                    it.assignUsize(isel, wip_vi);
                } else if (int_ty.bits <= 2 * grlen) {
                    try it.assignGprPair(isel, wip_vi, .{ grsize, ty.abiSize(zcu) - grsize }, .{ grlen, @intCast(int_ty.bits - grlen) });
                } else it.assignStack(wip_vi);
            },
            .ptr_type => |ptr_type| switch (ptr_type.flags.size) {
                .one, .many, .c => it.assignUsize(isel, wip_vi),
                .slice => continue :type_key .{ .int_type = .{
                    .signedness = .unsigned,
                    .bits = 2 * grlen,
                } },
            },
            .opt_type => |child_type| if (ty.optionalReprIsPayload(zcu))
                continue :type_key ip.indexToKey(child_type)
            else switch (ZigType.fromInterned(child_type).abiSize(zcu)) {
                0 => continue :type_key .{ .simple_type = .bool },
                1...7 => it.assignUsize(isel, wip_vi),
                8...15 => |child_size| {
                    try it.assignGprPair(isel, wip_vi, .{ child_size, 1 }, .{ @intCast(child_size * 8), 1 });
                },
                else => it.assignIndirect(isel, wip_vi, is_return),
            },
            .anyframe_type => unreachable,
            .error_union_type => switch (wip_vi.size(isel)) {
                0 => unreachable,
                1...8 => it.assignUsize(isel, wip_vi),
                // 9...16 => {}, TODO optimize
                else => it.assignIndirect(isel, wip_vi, is_return),
            },
            .simple_type => |simple_type| switch (simple_type) {
                .f80 => continue :type_key .{ .int_type = .{ .signedness = .unsigned, .bits = 80 } },
                .usize,
                .isize,
                .c_char,
                .c_short,
                .c_ushort,
                .c_int,
                .c_uint,
                .c_long,
                .c_ulong,
                .c_longlong,
                .c_ulonglong,
                => continue :type_key .{ .int_type = ty.intInfo(zcu) },
                .anyopaque, .bool => it.assignUsize(isel, wip_vi),
                .anyerror => continue :type_key .{ .int_type = .{
                    .signedness = .unsigned,
                    .bits = zcu.errorSetBits(),
                } },
                .f16, .f32, .f64, .f128, .c_longdouble => return isel.fail("CallAbiIterator.resolve({t})", .{simple_type}),
                else => return isel.fail("CallAbiIterator.resolve({t})", .{simple_type}),
            },
            .struct_type => {
                // TODO: implement floating-point structures rules defined in lapcs
                const loaded_struct = ip.loadStructType(ty.toIntern());
                switch (loaded_struct.layout) {
                    .auto, .@"extern" => {},
                    .@"packed" => continue :type_key ip.indexToKey(loaded_struct.packed_backing_int_type),
                }
                const size = wip_vi.size(isel);
                if (size == 0)
                    unreachable
                else if (size <= grsize)
                    it.assignUsize(isel, wip_vi)
                else if (size <= 2 * @as(u64, grsize))
                    try it.assignGprPair(isel, wip_vi, .{ grsize, size - grsize }, .{ grlen, @intCast((size * 8) - grlen) })
                else
                    // TODO flatten single-field structs
                    it.assignIndirect(isel, wip_vi, is_return);
            },
            .union_type => {
                const loaded_union = ip.loadUnionType(ty.toIntern());
                switch (loaded_union.layout) {
                    .auto, .@"extern" => {},
                    .@"packed" => continue :type_key .{ .int_type = .{
                        .signedness = .unsigned,
                        .bits = @intCast(ty.bitSize(zcu)),
                    } },
                }
                const size = wip_vi.size(isel);
                if (size == 0)
                    unreachable
                else if (size <= grsize)
                    it.assignUsize(isel, wip_vi)
                else if (size <= 2 * @as(u64, grsize)) {
                    const union_layout = ZigType.getUnionLayout(loaded_union, zcu);
                    var sizes: [2]u64 = @splat(0);
                    {
                        const offset = union_layout.tagOffset();
                        const end = offset % grsize + union_layout.tag_size;
                        const part_index: usize = @intCast(offset / grsize);
                        sizes[part_index] = @max(sizes[part_index], @min(end, grsize));
                        if (end > grsize) sizes[part_index + 1] = @max(sizes[part_index + 1], end - grsize);
                    }
                    {
                        const offset = union_layout.payloadOffset();
                        const end = offset % grsize + union_layout.payload_size;
                        const part_index: usize = @intCast(offset / grsize);
                        sizes[part_index] = @max(sizes[part_index], @min(end, grsize));
                        if (end > grsize) sizes[part_index + 1] = @max(sizes[part_index + 1], end - grsize);
                    }
                    try it.assignGprPair(isel, wip_vi, sizes, .{ @intCast(sizes[0] * 8), @intCast(sizes[1] * 8) });
                } else it.assignIndirect(isel, wip_vi, is_return);
            },
            .tuple_type => |tuple_ty| {
                assert(it.cc.* == .auto);
                const size = wip_vi.size(isel);
                switch (size) {
                    0 => unreachable,
                    1...8 => it.assignUsize(isel, wip_vi),
                    9...16 => {
                        var part_offset: u64 = 0;
                        var part_sizes: [2]u64 = undefined;
                        var parts_len: Value.PartsLen = 0;
                        var next_field_end: u64 = 0;
                        var field_index: usize = 0;
                        while (part_offset < size) {
                            const field_end = next_field_end;
                            const next_field_begin = while (field_index < tuple_ty.types.len) {
                                defer field_index += 1;
                                if (tuple_ty.values.get(ip)[field_index] != .none) continue;
                                const field_ty: ZigType = .fromInterned(tuple_ty.types.get(ip)[field_index]);
                                const next_field_begin = field_ty.abiAlignment(zcu).forward(field_end);
                                next_field_end = next_field_begin + field_ty.abiSize(zcu);
                                break next_field_begin;
                            } else std.mem.alignForward(u64, size, 8);
                            while (next_field_begin - part_offset >= 8) {
                                const part_size = @min(field_end - part_offset, 8);
                                part_sizes[parts_len] = part_size;
                                assert(part_offset + part_size <= size);
                                parts_len += 1;
                                part_offset += part_size;
                                if (part_offset >= field_end) part_offset = next_field_begin;
                            }
                        }
                        assert(parts_len == part_sizes.len);
                        try it.assignGprPair(isel, wip_vi, part_sizes, .{ @intCast(part_sizes[0] * 8), @intCast(part_sizes[1] * 8) });
                    },
                    else => it.assignIndirect(isel, wip_vi, is_return),
                }
            },
            // TODO: optimize chance
            .array_type => it.assignIndirect(isel, wip_vi, is_return),
            .opaque_type, .func_type => continue :type_key .{ .simple_type = .anyopaque },
            .enum_type => continue :type_key ip.indexToKey(ip.loadEnumType(ty.toIntern()).int_tag_type),
            .error_set_type,
            .inferred_error_set_type,
            => continue :type_key .{ .simple_type = .anyerror },
        }

        if (is_return) {
            it.next_reg = .init(.{
                .gpr = it.next_reg.get(.ret_byref), // skip registers for by-ref returning
                .fpr = .f0,
                .ret_byref = .zero,
            });
            it.next_stack = 0;
            abi_log.debug("| Return: {f} -> {f}", .{ isel.fmtType(ty), isel.fmtValue(wip_vi) });
        } else {
            abi_log.debug("| Param: {f} -> {f}", .{ isel.fmtType(ty), isel.fmtValue(wip_vi) });
        }

        return wip_vi.ref(isel);
    }
};

const call = struct {
    const param_reg: Value.Index = @fromBackingInt(@backingInt(Value.Index.allocating) - 2);
    const callee_clobbered_reg: Value.Index = @fromBackingInt(@backingInt(Value.Index.allocating) - 1);
    const caller_saved_regs: LiveRegisters = .init(.{
        .r0 = .free,
        .r1 = callee_clobbered_reg,
        .r2 = .free,
        .r3 = .free,
        .r4 = param_reg,
        .r5 = param_reg,
        .r6 = param_reg,
        .r7 = param_reg,
        .r8 = param_reg,
        .r9 = param_reg,
        .r10 = param_reg,
        .r11 = param_reg,
        .r12 = callee_clobbered_reg,
        .r13 = callee_clobbered_reg,
        .r14 = callee_clobbered_reg,
        .r15 = callee_clobbered_reg,
        .r16 = callee_clobbered_reg,
        .r17 = callee_clobbered_reg,
        .r18 = callee_clobbered_reg,
        .r19 = callee_clobbered_reg,
        .r20 = callee_clobbered_reg,
        .r21 = .free,
        .r22 = .free,
        .r23 = .free,
        .r24 = .free,
        .r25 = .free,
        .r26 = .free,
        .r27 = .free,
        .r28 = .free,
        .r29 = .free,
        .r30 = .free,
        .r31 = .free,

        .f0 = param_reg,
        .f1 = param_reg,
        .f2 = param_reg,
        .f3 = param_reg,
        .f4 = param_reg,
        .f5 = param_reg,
        .f6 = param_reg,
        .f7 = param_reg,
        .f8 = callee_clobbered_reg,
        .f9 = callee_clobbered_reg,
        .f10 = callee_clobbered_reg,
        .f11 = callee_clobbered_reg,
        .f12 = callee_clobbered_reg,
        .f13 = callee_clobbered_reg,
        .f14 = callee_clobbered_reg,
        .f15 = callee_clobbered_reg,
        .f16 = callee_clobbered_reg,
        .f17 = callee_clobbered_reg,
        .f18 = callee_clobbered_reg,
        .f19 = callee_clobbered_reg,
        .f20 = callee_clobbered_reg,
        .f21 = callee_clobbered_reg,
        .f22 = callee_clobbered_reg,
        .f23 = callee_clobbered_reg,
        .f24 = .free,
        .f25 = .free,
        .f26 = .free,
        .f27 = .free,
        .f28 = .free,
        .f29 = .free,
        .f30 = .free,
        .f31 = .free,

        .fcc0 = callee_clobbered_reg,
        .fcc1 = callee_clobbered_reg,
        .fcc2 = callee_clobbered_reg,
        .fcc3 = callee_clobbered_reg,
        .fcc4 = callee_clobbered_reg,
        .fcc5 = callee_clobbered_reg,
        .fcc6 = callee_clobbered_reg,
        .fcc7 = callee_clobbered_reg,
    });

    fn prepareReturn(_: *Select) !void {}

    fn finishReturn(isel: *Select) !void {
        // Lock remaining clobberred registers
        const locked_regs = comptime locked_regs: {
            var locked_regs: RegisterSet = .empty;
            for (std.enums.values(Register)) |reg| switch (caller_saved_regs.get(reg)) {
                else => unreachable,
                param_reg, callee_clobbered_reg => locked_regs.insert(reg),
                .free => {},
            };
            break :locked_regs locked_regs;
        };
        try isel.fillRegsBatch(locked_regs, true);
        isel.markRegsWritten(locked_regs);
    }

    fn prepareCallee(isel: *Select) !void {
        // Free clobbered registers
        var live_reg_it = isel.live_registers.iterator();
        while (live_reg_it.next()) |live_reg_entry| switch (caller_saved_regs.get(live_reg_entry.key)) {
            else => unreachable,
            param_reg => assert(live_reg_entry.value.* == .allocating),
            callee_clobbered_reg => isel.freeReg(live_reg_entry.key),
            .free => {},
        };
    }
    fn finishCallee(_: *Select) !void {}

    fn prepareParams(_: *Select) !void {}
    fn paramLiveOut(isel: *Select, vi: Value.Index, layout_vi: Value.Index) !void {
        switch (layout_vi.parent(isel)) {
            else => return vi.matLiveOut(isel, layout_vi, .{ .mode = .param }),
            .address => |addr_vi| return call.paramIndirect(isel, vi, addr_vi),
        }
    }
    fn paramIndirect(isel: *Select, vi: Value.Index, addr_vi: Value.Index) !void {
        const val_mat = try vi.mat(isel, .{ .pref = .only_stack });
        try paramAddress(
            isel,
            val_mat.loc().asStackSlot().?,
            addr_vi,
        );
        try val_mat.finish(isel);
    }
    fn paramAddress(isel: *Select, stack: Value.Indirect, addr_vi: Value.Index) !void {
        if (addr_vi.hintRegister(isel)) |addr_reg| {
            assert(isel.live_registers.get(addr_reg) == .allocating);
            try isel.addImm(addr_reg, stack.base, stack.offset);
        } else if (addr_vi.location(isel)) |addr_loc| {
            const tmp_reg = try isel.allocRegForWrite(.int);
            defer isel.freeReg(tmp_reg);
            try isel.addImm(tmp_reg, stack.base, stack.offset);
            try isel.moveLoc(
                addr_loc,
                0,
                .{ .register = .{ .mod = .integer, .reg = tmp_reg } },
                0,
                isel.gprSize(),
                .preserved,
            );
        } else unreachable;
    }
    fn finishParams(isel: *Select) !void {
        // Free parameter registers
        var live_reg_it = isel.live_registers.iterator();
        while (live_reg_it.next()) |live_reg_entry| switch (caller_saved_regs.get(live_reg_entry.key)) {
            else => unreachable,
            param_reg => switch (live_reg_entry.value.*) {
                _ => {},
                .allocating => live_reg_entry.value.* = .free,
                .free => unreachable,
            },
            callee_clobbered_reg, .free => {},
        };
    }
};

fn gprSize(isel: *Select) u4 {
    return switch (isel.target.cpu.arch) {
        .loongarch32 => 4,
        .loongarch64 => 8,
        else => unreachable,
    };
}

fn gprBits(isel: *Select) u7 {
    return switch (isel.target.cpu.arch) {
        .loongarch32 => 32,
        .loongarch64 => 64,
        else => unreachable,
    };
}

fn gprAlignment(isel: *Select) std.mem.Alignment {
    return switch (isel.target.cpu.arch) {
        .loongarch32 => .@"4",
        .loongarch64 => .@"8",
        else => unreachable,
    };
}

fn typeOfField(isel: *Select, ty: ZigType, offset: u64) ?ZigType {
    const zcu = isel.pt.zcu;
    const ip = &zcu.intern_pool;
    type_key: switch (ip.indexToKey(ty.toIntern())) {
        else => {},
        // TODO large int splitting
        .int_type => {
            if (ty.abiSize(zcu) > isel.gprSize() and offset % isel.gprSize() == 0) return .usize;
        },
        .ptr_type => |ptr_type| switch (ptr_type.flags.size) {
            .one, .many, .c => {},
            .slice => if (offset == 0)
                return ty.elemPtrType(null, isel.pt) catch unreachable
            else if (offset == isel.gprSize())
                return .usize,
        },
        .opt_type => |child_type| if (ty.optionalReprIsPayload(zcu))
            continue :type_key ip.indexToKey(child_type)
        else {
            const child_ty: ZigType = .fromInterned(child_type);
            if (offset == 0)
                return child_ty
            else if (offset == child_ty.abiSize(zcu))
                return .usize;
        },
        .array_type => unreachable, // TODO
        .anyframe_type => unreachable,
        .error_union_type => |error_union_type| {
            const payload_ty: ZigType = .fromInterned(error_union_type.payload_type);
            if (offset == codegen.errUnionErrorOffset(payload_ty, zcu))
                return .fromInterned(error_union_type.error_set_type)
            else if (offset == codegen.errUnionPayloadOffset(payload_ty, zcu))
                return payload_ty;
        },
        .simple_type => |simple_type| switch (simple_type) {
            else => {},
            .f80 => continue :type_key .{ .int_type = .{ .signedness = .unsigned, .bits = 80 } },
            .usize,
            .isize,
            .c_char,
            .c_short,
            .c_ushort,
            .c_int,
            .c_uint,
            .c_long,
            .c_ulong,
            .c_longlong,
            .c_ulonglong,
            => continue :type_key .{ .int_type = ty.intInfo(zcu) },
            .anyerror => continue :type_key .{ .int_type = .{ .signedness = .unsigned, .bits = zcu.errorSetBits() } },
        },
        .struct_type => {
            const loaded_struct = ip.loadStructType(ty.toIntern());
            switch (loaded_struct.layout) {
                .auto, .@"extern" => {},
                .@"packed" => continue :type_key ip.indexToKey(loaded_struct.backingIntTypeUnordered(ip)).int_type,
            }
            var field_end: u64 = 0;
            var field_it = loaded_struct.iterateRuntimeOrder(ip);
            while (field_it.next()) |field_index| {
                const field_ty: ZigType = .fromInterned(loaded_struct.field_types.get(ip)[field_index]);
                const field_begin = switch (loaded_struct.fieldAlign(ip, field_index)) {
                    .none => field_ty.abiAlignment(zcu),
                    else => |field_align| field_align,
                }.forward(field_end);
                const field_size = field_ty.abiSize(zcu);
                field_end = field_begin + field_size;
                if (field_begin > offset) break;
                if (field_begin == offset)
                    return field_ty
                else if (field_end > offset)
                    return isel.typeOfField(field_ty, offset - field_begin);
            }
        },
        .tuple_type => |tuple_type| {
            var field_end: u64 = 0;
            for (tuple_type.types.get(ip), tuple_type.values.get(ip)) |field_type, field_value| {
                if (field_value != .none) continue;
                const field_ty: ZigType = .fromInterned(field_type);
                const field_begin = field_ty.abiAlignment(zcu).forward(field_end);
                const field_size = field_ty.abiSize(zcu);
                if (field_size == 0) continue;
                field_end = field_begin + field_size;
                if (field_begin > offset) break;
                if (field_begin == offset)
                    return field_ty
                else if (field_end > offset)
                    return isel.typeOfField(field_ty, offset - field_begin);
            }
        },
        .union_type => {
            const loaded_union = ip.loadUnionType(ty.toIntern());
            switch (loaded_union.flagsUnordered(ip).layout) {
                .auto, .@"extern" => {},
                .@"packed" => continue :type_key .{ .int_type = .{
                    .signedness = .unsigned,
                    .bits = @intCast(ty.bitSize(zcu)),
                } },
            }
            const union_layout = ZigType.getUnionLayout(loaded_union, zcu);
            if (offset == union_layout.tagOffset())
                return .fromInterned(loaded_union.enum_tag_ty);
        },
        .opaque_type, .func_type => continue :type_key .{ .simple_type = .anyopaque },
        .enum_type => continue :type_key ip.indexToKey(ip.loadEnumType(ty.toIntern()).tag_ty),
        .error_set_type,
        .inferred_error_set_type,
        => continue :type_key .{ .simple_type = .anyerror },
    }
    tracking_log.debug("cannot split {f} at {d}", .{ isel.fmtType(ty), offset });
    return null;
}

fn hasRepeatedByteRepr(isel: *Select, constant: Constant) error{OutOfMemory}!?u8 {
    const zcu = isel.pt.zcu;
    const ty = constant.typeOf(zcu);
    const abi_size = std.math.cast(usize, ty.abiSize(zcu)) orelse return null;
    const byte_buffer = try zcu.gpa.alloc(u8, abi_size);
    defer zcu.gpa.free(byte_buffer);
    return if (try isel.writeConstantToMemory(constant, byte_buffer) and
        std.mem.allEqual(u8, byte_buffer[1..], byte_buffer[0])) byte_buffer[0] else null;
}

fn writeConstantToMemory(isel: *Select, constant: Constant, buffer: []u8) error{OutOfMemory}!bool {
    const zcu = isel.pt.zcu;
    const ip = &zcu.intern_pool;
    if (try isel.writeConstantKeyToMemory(ip.indexToKey(constant.toIntern()), buffer)) return true;
    constant.writeToMemory(isel.pt.zcu, buffer) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.ReinterpretDeclRef, error.IllDefinedMemoryLayout => return false,
    };
    return true;
}

fn writeConstantKeyToMemory(isel: *Select, constant_key: InternPool.Key, buffer: []u8) error{OutOfMemory}!bool {
    const zcu = isel.pt.zcu;
    const ip = &zcu.intern_pool;
    switch (constant_key) {
        .int_type,
        .ptr_type,
        .array_type,
        .vector_type,
        .opt_type,
        .anyframe_type,
        .error_union_type,
        .simple_type,
        .struct_type,
        .tuple_type,
        .union_type,
        .opaque_type,
        .enum_type,
        .func_type,
        .error_set_type,
        .inferred_error_set_type,

        .enum_literal,
        .memoized_call,
        => unreachable, // not a runtime value
        .err => |err| {
            const error_int = ip.getErrorValueIfExists(err.name).?;
            switch (buffer.len) {
                else => unreachable,
                inline 1...4 => |size| std.mem.writeInt(
                    @Int(.unsigned, 8 * size),
                    buffer[0..size],
                    @intCast(error_int),
                    isel.target.cpu.arch.endian(),
                ),
            }
        },
        .error_union => |error_union| {
            const error_union_type = ip.indexToKey(error_union.ty).error_union_type;
            const error_set_ty: ZigType = .fromInterned(error_union_type.error_set_type);
            const payload_ty: ZigType = .fromInterned(error_union_type.payload_type);
            const error_set = buffer[@intCast(codegen.errUnionErrorOffset(payload_ty, zcu))..][0..@intCast(error_set_ty.abiSize(zcu))];
            switch (error_union.val) {
                .err_name => |err_name| if (!try isel.writeConstantKeyToMemory(.{ .err = .{
                    .ty = error_set_ty.toIntern(),
                    .name = err_name,
                } }, error_set)) return false,
                .payload => |payload| {
                    if (!try isel.writeConstantToMemory(
                        .fromInterned(payload),
                        buffer[@intCast(codegen.errUnionPayloadOffset(payload_ty, zcu))..][0..@intCast(payload_ty.abiSize(zcu))],
                    )) return false;
                    @memset(error_set, 0);
                },
            }
        },
        .opt => |opt| {
            const child_size: usize = @intCast(ZigType.fromInterned(ip.indexToKey(opt.ty).opt_type).abiSize(zcu));
            switch (opt.val) {
                .none => if (!ZigType.fromInterned(opt.ty).optionalReprIsPayload(zcu)) {
                    buffer[child_size] = @intFromBool(false);
                } else @memset(buffer[0..child_size], 0x00),
                else => |child_constant| {
                    if (!try isel.writeConstantToMemory(.fromInterned(child_constant), buffer[0..child_size])) return false;
                    if (!ZigType.fromInterned(opt.ty).optionalReprIsPayload(zcu)) buffer[child_size] = @intFromBool(true);
                },
            }
        },
        .aggregate => |aggregate| switch (ip.indexToKey(aggregate.ty)) {
            else => unreachable,
            .array_type => |array_type| {
                var elem_offset: usize = 0;
                const elem_size: usize = @intCast(ZigType.fromInterned(array_type.child).abiSize(zcu));
                const len_including_sentinel: usize = @intCast(array_type.lenIncludingSentinel());
                switch (aggregate.storage) {
                    .bytes => |bytes| @memcpy(buffer[0..len_including_sentinel], bytes.toSlice(len_including_sentinel, ip)),
                    .elems => |elems| for (elems) |elem| {
                        if (!try isel.writeConstantToMemory(.fromInterned(elem), buffer[elem_offset..][0..elem_size])) return false;
                        elem_offset += elem_size;
                    },
                    .repeated_elem => |repeated_elem| for (0..len_including_sentinel) |_| {
                        if (!try isel.writeConstantToMemory(.fromInterned(repeated_elem), buffer[elem_offset..][0..elem_size])) return false;
                        elem_offset += elem_size;
                    },
                }
            },
            .vector_type => return false,
            .struct_type => {
                const loaded_struct = ip.loadStructType(aggregate.ty);
                switch (loaded_struct.layout) {
                    .auto => {
                        var field_it = loaded_struct.iterateRuntimeOrder(ip);
                        while (field_it.next()) |field_index| {
                            if (loaded_struct.field_is_comptime_bits.get(ip, field_index)) continue;
                            const field_ty: ZigType = .fromInterned(loaded_struct.field_types.get(ip)[field_index]);
                            const field_offset = loaded_struct.field_offsets.get(ip)[field_index];
                            const field_size = field_ty.abiSize(zcu);
                            if (!try isel.writeConstantToMemory(.fromInterned(switch (aggregate.storage) {
                                .bytes => unreachable,
                                .elems => |elems| elems[field_index],
                                .repeated_elem => |repeated_elem| repeated_elem,
                            }), buffer[@intCast(field_offset)..][0..@intCast(field_size)])) return false;
                        }
                    },
                    .@"extern", .@"packed" => return false,
                }
            },
            .tuple_type => |tuple_type| {
                var field_offset: u64 = 0;
                for (tuple_type.types.get(ip), tuple_type.values.get(ip), 0..) |field_type, field_value, field_index| {
                    if (field_value != .none) continue;
                    const field_ty: ZigType = .fromInterned(field_type);
                    field_offset = field_ty.abiAlignment(zcu).forward(field_offset);
                    const field_size = field_ty.abiSize(zcu);
                    if (!try isel.writeConstantToMemory(.fromInterned(switch (aggregate.storage) {
                        .bytes => unreachable,
                        .elems => |elems| elems[field_index],
                        .repeated_elem => |repeated_elem| repeated_elem,
                    }), buffer[@intCast(field_offset)..][0..@intCast(field_size)])) return false;
                    field_offset += field_size;
                }
            },
        },
        .un => |union_val| {
            const loaded_union = ip.loadUnionType(union_val.ty);
            switch (loaded_union.layout) {
                .auto => {},
                .@"extern", .@"packed" => return false,
            }
            const union_layout = ZigType.getUnionLayout(loaded_union, zcu);
            if (loaded_union.has_runtime_tag)
                if (!try isel.writeConstantToMemory(
                    .fromInterned(union_val.tag),
                    buffer[@intCast(union_layout.tagOffset())..][0..@intCast(union_layout.tag_size)],
                )) return false;
            if (!try isel.writeConstantToMemory(
                .fromInterned(union_val.val),
                buffer[@intCast(union_layout.payloadOffset())..][0..@intCast(union_layout.payload_size)],
            )) return false;
        },
        else => return false,
    }
    return true;
}

fn wipeLocationDfs(isel: *Select, vi: Value.Index) void {
    _ = vi.takeLocationMarkWritten(isel);
    var part_it = vi.parts(isel);
    while (part_it.next()) |part_vi| {
        if (part_vi != vi) isel.wipeLocationDfs(part_vi);
    }
}

const Air = @import("../../Air.zig");
const assert = std.debug.assert;
const codegen = @import("../../codegen.zig");
const Constant = @import("../../Value.zig");
const InternPool = @import("../../InternPool.zig");
const Module = @import("../../Module.zig");
const Select = @This();
const std = @import("std");
const tracking_log = std.log.scoped(.tracking);
const wip_mir_log = std.log.scoped(.@"wip-mir");
const abi_log = std.log.scoped(.abi);
const Zcu = @import("../../Zcu.zig");
const ZigType = @import("../../Type.zig");
