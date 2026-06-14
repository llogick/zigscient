const builtin = @import("builtin");
const endian = builtin.cpu.arch.endian();

const std = @import("std");

const compiler_rt = @import("../compiler_rt.zig");
const udivmod = @import("udivmodei4.zig").divmod;
const symbol = @import("../compiler_rt.zig").symbol;

comptime {
    symbol(&__divei4, "__divei4");
    symbol(&__modei4, "__modei4");
    symbol(&__divei5, "__divei5");
    symbol(&__modei5, "__modei5");
}

inline fn limb(i: usize, len: usize) usize {
    return if (endian == .little) i else len - 1 - i;
}

inline fn neg(out: []u32, in: []const u32) void {
    var ov: u1 = 1;
    for (0..in.len) |limb_index| {
        const new, ov = @addWithOverflow(~in[limb(limb_index, in.len)], ov);
        out[limb(limb_index, out.len)] = new;
    }
}

fn divmod(q: ?[]u32, r: ?[]u32, u: []const u32, v: []const u32, tu: []u32, tv: []u32) !void {
    const u_sign: i32 = @bitCast(u[limb(u.len - 1, u.len)]);
    const v_sign: i32 = @bitCast(v[limb(v.len - 1, v.len)]);
    if (u_sign < 0) neg(tu, u);
    if (v_sign < 0) neg(tv, v);
    try @call(.always_inline, udivmod, .{ q, r, if (u_sign < 0) tu else u, if (v_sign < 0) tv else v });
    if (q) |x| if (u_sign ^ v_sign < 0) neg(x, x);
    if (r) |x| if (u_sign < 0) neg(x, x);
}

pub fn __divei4(q_p: [*]u8, u_p: [*]u8, v_p: [*]u8, bits: usize) callconv(.c) void {
    @setRuntimeSafety(compiler_rt.test_safety);
    const byte_size = std.zig.target.intByteSize(&builtin.target, @intCast(bits));
    const q: []u32 = @ptrCast(@alignCast(q_p[0..byte_size]));
    const u: []u32 = @ptrCast(@alignCast(u_p[0..byte_size]));
    const v: []u32 = @ptrCast(@alignCast(v_p[0..byte_size]));
    @call(.always_inline, divmod, .{ q, null, u, v, u, v }) catch unreachable;
}

pub fn __modei4(r_p: [*]u8, u_p: [*]u8, v_p: [*]u8, bits: usize) callconv(.c) void {
    @setRuntimeSafety(compiler_rt.test_safety);
    const byte_size = std.zig.target.intByteSize(&builtin.target, @intCast(bits));
    const r: []u32 = @ptrCast(@alignCast(r_p[0..byte_size]));
    const u: []u32 = @ptrCast(@alignCast(u_p[0..byte_size]));
    const v: []u32 = @ptrCast(@alignCast(v_p[0..byte_size]));
    @call(.always_inline, divmod, .{ null, r, u, v, u, v }) catch unreachable;
}

pub fn __divei5(q_p: [*]u8, u_p: [*]const u8, v_p: [*]const u8, t_p: [*]u8, bits: usize) callconv(.c) void {
    @setRuntimeSafety(compiler_rt.test_safety);
    const byte_size = std.zig.target.intByteSize(&builtin.target, @intCast(bits));
    const q: []u32 = @ptrCast(@alignCast(q_p[0..byte_size]));
    const u: []const u32 = @ptrCast(@alignCast(u_p[0..byte_size]));
    const v: []const u32 = @ptrCast(@alignCast(v_p[0..byte_size]));
    const tu: []u32 = @ptrCast(@alignCast(t_p[0..byte_size]));
    const tv: []u32 = @ptrCast(@alignCast(t_p[byte_size..][0..byte_size]));
    @call(.always_inline, divmod, .{ q, null, u, v, tu, tv }) catch unreachable;
}

pub fn __modei5(r_p: [*]u8, u_p: [*]const u8, v_p: [*]const u8, t_p: [*]u8, bits: usize) callconv(.c) void {
    @setRuntimeSafety(compiler_rt.test_safety);
    const byte_size = std.zig.target.intByteSize(&builtin.target, @intCast(bits));
    const r: []u32 = @ptrCast(@alignCast(r_p[0..byte_size]));
    const u: []const u32 = @ptrCast(@alignCast(u_p[0..byte_size]));
    const v: []const u32 = @ptrCast(@alignCast(v_p[0..byte_size]));
    const tu: []u32 = @ptrCast(@alignCast(t_p[0..byte_size]));
    const tv: []u32 = @ptrCast(@alignCast(t_p[byte_size..][0..byte_size]));
    @call(.always_inline, divmod, .{ null, r, u, v, tu, tv }) catch unreachable;
}
