pub const Mir = @import("loongarch/Mir.zig");
const Select = @import("loongarch/Select.zig");
const bits = @import("loongarch/bits.zig");
pub const Disassemble = @import("loongarch/Disassemble.zig");
pub const encoding = @import("loongarch/encoding.zig");

test {
    _ = bits;
    _ = Disassemble;
}

pub fn legalizeFeatures(_: *const std.Target) ?*const Air.Legalize.Features {
    return comptime &.initMany(&.{
        .expand_bit_cast_safe,
        .expand_int_cast_safe,
        .expand_int_from_float_safe,
        .expand_int_from_float_optimized_safe,
        .expand_add_safe,
        .expand_sub_safe,
        .expand_mul_safe,
        .expand_packed_load,
        .expand_packed_store,
        .expand_packed_agg_field_val,
        .expand_packed_aggregate_init,
        .soft_f16,
        .soft_f32,
        .soft_f64,
        .soft_f80,
    });
}

pub fn generate(
    _: *link.File,
    pt: Zcu.PerThread,
    func_index: InternPool.Index,
    air: *const Air,
    liveness: *const ?Air.Liveness,
) !Mir {
    const zcu = pt.zcu;
    const gpa = zcu.gpa;
    const ip = &zcu.intern_pool;
    const func = zcu.funcInfo(func_index);
    const func_zir = func.zir_body_inst.resolveFull(ip).?;
    const file = zcu.fileByIndex(func_zir.file);
    const named_params_len = file.zir.?.getParamBody(func_zir.inst).len;
    const func_type = ip.indexToKey(func.ty).func_type;
    assert(liveness.* == null);

    // Initialize ISel
    const mod = zcu.navFileScope(func.owner_nav).mod.?;
    var isel: Select = .{
        .pt = pt,
        .target = &mod.resolved_target.result,
        .opt_mode = mod.optimize_mode,
        .air = air.*,
        .nav_index = zcu.funcInfo(func_index).owner_nav,
    };
    defer isel.deinit();
    assert(try isel.active_blocks.fetchPut(gpa, Select.Block.main, .{ .target_label = 0 }) == null);
    defer isel.active_blocks.entries.items(.value)[0].deinit(&isel);

    const air_main_body = air.getMainBody();

    // Calculate parameter & return hints and layouts
    var cc_it1: Select.CallAbiIterator = .{
        .cc = &func_type.cc,
        .isel = &isel,
        .stack_pointer = .fp,
    };
    var cc_it2 = cc_it1;

    switch (func_type.cc) {
        // naked functions cannot have any arguments
        // Otherwise, SP will always be moved to allocate space for the saved FP and _start will be broken.
        .naked => {},
        // FP is required to load byval arguments passed on stack now
        // TODO: use FP only when necessary
        else => isel.saved_registers.insert(.fp),
    }

    const ret_layout_vi: ?Select.Value.Index = ret: {
        const ret_vi1 = try cc_it1.resolve(.fromInterned(func_type.return_type), true) orelse break :ret null;
        const ret_vi2 = try cc_it2.resolve(.fromInterned(func_type.return_type), true) orelse unreachable;
        ret_vi2.deref(&isel);
        tracking_log.debug("{f} <- %main", .{ret_vi1});
        try isel.live_values.putNoClobber(gpa, Select.Block.main, ret_vi1);
        break :ret ret_vi2;
    };

    var arg_layouts: std.ArrayList(Select.Value.Index) = .empty;
    defer arg_layouts.deinit(gpa);
    for (air_main_body) |air_inst_index| {
        if (air.instructions.items(.tag)[@backingInt(air_inst_index)] != .arg) break;
        const arg = air.instructions.items(.data)[@backingInt(air_inst_index)].arg;
        const param_ty = arg.ty;
        if (arg.zir_param_index >= named_params_len)
            assert(func_type.is_var_args);
        const param_vi1 = try cc_it1.resolve(param_ty, false) orelse unreachable;
        const param_vi2 = try cc_it2.resolve(param_ty, false) orelse unreachable;
        tracking_log.debug("{f} <- %{d}", .{ param_vi1, @backingInt(air_inst_index) });
        try isel.live_values.putNoClobber(gpa, air_inst_index, param_vi1);
        try arg_layouts.append(gpa, param_vi2);
    }
    if (arg_layouts.items.len != 0)
        isel.arg_layouts = try arg_layouts.toOwnedSlice(gpa);

    // Analyze
    try isel.analyze(air_main_body);
    try isel.finishAnalysis();
    isel.verify(false);

    // Generate body
    assert(isel.instructions.items.len == 0);
    try isel.body(air_main_body);
    if (isel.live_values.fetchRemove(Select.Block.main)) |ret_vi| {
        defer ret_vi.value.deref(&isel);

        switch (ret_vi.value.parent(&isel)) {
            .none, .value => {},
            .address => |ret_addr_vi| {
                tracking_log.debug("live-in by-ref return address", .{});
                try ret_addr_vi.defLiveIn(&isel, ret_layout_vi.?.parent(&isel).address, .{});
            },
            .constant => unreachable,
        }
    }

    // Generate prologue and epilogue
    const prologue = isel.instructions.items.len;
    const epilogue = try isel.layout(cc_it1, mod);

    // Verification
    isel.verify(true);
    try isel.verifyTargetFeatures();

    // Finalization
    const instructions = try isel.instructions.toOwnedSlice(gpa);
    var mir: Mir = .{
        .prologue = instructions[prologue..epilogue],
        .body = instructions[0..prologue],
        .epilogue = instructions[epilogue..],
        .nav_relocs = &.{},
        .uav_relocs = &.{},
        .lazy_relocs = &.{},
        .global_relocs = &.{},
        .internal_relocs = &.{},
    };
    errdefer mir.deinit(gpa);
    mir.nav_relocs = try isel.nav_relocs.toOwnedSlice(gpa);
    mir.uav_relocs = try isel.uav_relocs.toOwnedSlice(gpa);
    mir.lazy_relocs = try isel.lazy_relocs.toOwnedSlice(gpa);
    mir.global_relocs = try isel.global_relocs.toOwnedSlice(gpa);
    mir.internal_relocs = try isel.internal_relocs.toOwnedSlice(gpa);
    return mir;
}

const Air = @import("../Air.zig");
const assert = std.debug.assert;
const InternPool = @import("../InternPool.zig");
const link = @import("../link.zig");
const std = @import("std");
const tracking_log = std.log.scoped(.tracking);
const Zcu = @import("../Zcu.zig");
