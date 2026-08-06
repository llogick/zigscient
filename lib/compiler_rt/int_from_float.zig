const builtin = @import("builtin");
const std = @import("std");
const math = std.math;
const Log2Int = std.math.Log2Int;

const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;

comptime {
    symbol(&__fixhfsi, "__fixhfsi");
    symbol(&__fixhfdi, "__fixhfdi");
    symbol(&__fixhfti, "__fixhfti");
    symbol(&__fixhfei, "__fixhfei");

    if (compiler_rt.want_aeabi) {
        symbol(&__aeabi_f2iz, "__aeabi_f2iz");
        symbol(&__aeabi_f2lz, "__aeabi_f2lz");
        symbol(&__aeabi_fixsfti, "__fixsfti");
    } else {
        symbol(&__fixsfsi, "__fixsfsi");
        symbol(&__fixsfdi, "__fixsfdi");
        if (compiler_rt.want_windows_arm_abi) symbol(&__fixsfdi, "__stoi64");
        symbol(&__fixsfti, "__fixsfti");
    }
    symbol(&__fixsfei, "__fixsfei");

    if (compiler_rt.want_aeabi) {
        symbol(&__aeabi_d2iz, "__aeabi_d2iz");
        symbol(&__aeabi_d2lz, "__aeabi_d2lz");
        symbol(&__aeabi_fixdfti, "__fixdfti");
    } else {
        symbol(&__fixdfsi, "__fixdfsi");
        symbol(&__fixdfdi, "__fixdfdi");
        if (compiler_rt.want_windows_arm_abi) symbol(&__fixdfdi, "__dtoi64");
        symbol(&__fixdfti, "__fixdfti");
    }
    symbol(&__fixdfei, "__fixdfei");

    symbol(&__fixxfsi, "__fixxfsi");
    symbol(&__fixxfdi, "__fixxfdi");
    symbol(&__fixxfti, "__fixxfti");
    symbol(&__fixxfei, "__fixxfei");

    if (compiler_rt.want_ppc_abi) {
        symbol(&__fixtfsi, "__fixkfsi");
        symbol(&__fixtfdi, "__fixkfdi");
    } else if (compiler_rt.want_sparc64_abi) {
        symbol(&_Qp_qtoi, "_Qp_qtoi");
        symbol(&_Qp_qtox, "_Qp_qtox");
    } else if (compiler_rt.want_sparc32_abi) {
        symbol(&__fixtfsi, "_Q_qtoi");
        symbol(&__fixtfdi, "_Q_qtoll");
    } else {
        symbol(&__fixtfsi, "__fixtfsi");
        symbol(&__fixtfdi, "__fixtfdi");
    }
    if (compiler_rt.want_ppc_abi) {
        symbol(&__fixtfti, "__fixkfti");
        symbol(&__fixtfei, "__fixkfei");
    } else {
        symbol(&__fixtfti, "__fixtfti");
        symbol(&__fixtfei, "__fixtfei");
    }
}

fn __fixhfsi(a: compiler_rt.f16.Abi) callconv(.c) i32 {
    return i32_intFromFloat_f16(compiler_rt.f16.fromAbi(a));
}
pub fn i32_intFromFloat_f16(a: f16) i32 {
    return intFromFloat(i32, a);
}

fn __fixhfdi(a: compiler_rt.f16.Abi) callconv(.c) i64 {
    return i64_intFromFloat_f16(compiler_rt.f16.fromAbi(a));
}
pub fn i64_intFromFloat_f16(a: f16) i64 {
    return intFromFloat(i64, a);
}

fn __fixhfti(a: compiler_rt.f16.Abi) callconv(.c) i128 {
    return i128_intFromFloat_f16(compiler_rt.f16.fromAbi(a));
}
pub fn i128_intFromFloat_f16(a: f16) i128 {
    return intFromFloat(i128, a);
}

fn __fixhfei(r: [*]u8, bits: usize, a: compiler_rt.f16.Abi) callconv(.c) void {
    const byte_size = std.zig.target.intByteSize(&builtin.target, @intCast(bits));
    return signed_intFromFloat_f16(r[0..byte_size], compiler_rt.f16.fromAbi(a));
}
pub fn signed_intFromFloat_f16(result: []u8, a: f16) void {
    bigIntFromFloat(.signed, @ptrCast(@alignCast(result)), a);
}

fn __fixsfsi(a: compiler_rt.f32.Abi) callconv(.c) i32 {
    return i32_intFromFloat_f32(compiler_rt.f32.fromAbi(a));
}
fn __aeabi_f2iz(a: f32) callconv(.{ .arm_aapcs = .{} }) i32 {
    return i32_intFromFloat_f32(a);
}
pub fn i32_intFromFloat_f32(a: f32) i32 {
    return intFromFloat(i32, a);
}

fn __fixsfdi(a: compiler_rt.f32.Abi) callconv(.c) i64 {
    return i64_intFromFloat_f32(compiler_rt.f32.fromAbi(a));
}
fn __aeabi_f2lz(a: f32) callconv(.{ .arm_aapcs = .{} }) i64 {
    return i64_intFromFloat_f32(a);
}
pub fn i64_intFromFloat_f32(a: f32) i64 {
    return intFromFloat(i64, a);
}

fn __fixsfti(a: compiler_rt.f32.Abi) callconv(.c) i128 {
    return i128_intFromFloat_f32(compiler_rt.f32.fromAbi(a));
}
fn __aeabi_fixsfti(_: compiler_rt.f32.Abi) callconv(.naked) i128 {
    switch (builtin.abi.float()) {
        .soft => asm volatile (
            \\ push {r0-r4, lr}
            \\ movs r1, r0
            \\ mov r0, sp
            \\ bl %[__fixsfti]
            \\ pop {r0-r4, pc}
            :
            : [__fixsfti] "X" (&__fixsfti),
        ),
        .hard => asm volatile (
            \\ push {r0-r4, lr}
            \\ mov r0, sp
            \\ bl %[__fixsfti]
            \\ pop {r0-r4, pc}
            :
            : [__fixsfti] "X" (&__fixsfti),
        ),
    }
}
pub fn i128_intFromFloat_f32(a: f32) i128 {
    return intFromFloat(i128, a);
}

fn __fixsfei(r: [*]u8, bits: usize, a: compiler_rt.f32.Abi) callconv(.c) void {
    const byte_size = std.zig.target.intByteSize(&builtin.target, @intCast(bits));
    return signed_intFromFloat_f32(r[0..byte_size], compiler_rt.f32.fromAbi(a));
}
pub fn signed_intFromFloat_f32(result: []u8, a: f32) void {
    bigIntFromFloat(.signed, @ptrCast(@alignCast(result)), a);
}

fn __fixdfsi(a: compiler_rt.f64.Abi) callconv(.c) i32 {
    return i32_intFromFloat_f64(compiler_rt.f64.fromAbi(a));
}
fn __aeabi_d2iz(a: f64) callconv(.{ .arm_aapcs = .{} }) i32 {
    return i32_intFromFloat_f64(a);
}
pub fn i32_intFromFloat_f64(a: f64) i32 {
    return intFromFloat(i32, a);
}

fn __fixdfdi(a: compiler_rt.f64.Abi) callconv(.c) i64 {
    return i64_intFromFloat_f64(compiler_rt.f64.fromAbi(a));
}
fn __aeabi_d2lz(a: f64) callconv(.{ .arm_aapcs = .{} }) i64 {
    return i64_intFromFloat_f64(a);
}
pub fn i64_intFromFloat_f64(a: f64) i64 {
    return intFromFloat(i64, a);
}

fn __fixdfti(a: compiler_rt.f64.Abi) callconv(.c) i128 {
    return i128_intFromFloat_f64(compiler_rt.f64.fromAbi(a));
}
fn __aeabi_fixdfti(_: compiler_rt.f64.Abi) callconv(.naked) i128 {
    switch (builtin.abi.float()) {
        .soft => asm volatile (
            \\ push {r0-r4, lr}
            \\ movs r3, r1
            \\ movs r2, r0
            \\ mov r0, sp
            \\ bl %[__fixdfti]
            \\ pop {r0-r4, pc}
            :
            : [__fixdfti] "X" (&__fixdfti),
        ),
        .hard => asm volatile (
            \\ push {r0-r4, lr}
            \\ mov r0, sp
            \\ bl %[__fixdfti]
            \\ pop {r0-r4, pc}
            :
            : [__fixdfti] "X" (&__fixdfti),
        ),
    }
}
pub fn i128_intFromFloat_f64(a: f64) i128 {
    return intFromFloat(i128, a);
}

fn __fixdfei(r: [*]u8, bits: usize, a: compiler_rt.f64.Abi) callconv(.c) void {
    const byte_size = std.zig.target.intByteSize(&builtin.target, @intCast(bits));
    return signed_intFromFloat_f64(r[0..byte_size], compiler_rt.f64.fromAbi(a));
}
pub fn signed_intFromFloat_f64(result: []u8, a: f64) void {
    bigIntFromFloat(.signed, @ptrCast(@alignCast(result)), a);
}

fn __fixxfsi(a: compiler_rt.f80.Abi) callconv(.c) i32 {
    return i32_intFromFloat_f80(compiler_rt.f80.fromAbi(a));
}
pub fn i32_intFromFloat_f80(a: f80) i32 {
    return intFromFloat(i32, a);
}

fn __fixxfdi(a: compiler_rt.f80.Abi) callconv(.c) i64 {
    return i64_intFromFloat_f80(compiler_rt.f80.fromAbi(a));
}
pub fn i64_intFromFloat_f80(a: f80) i64 {
    return intFromFloat(i64, a);
}

fn __fixxfti(a: compiler_rt.f80.Abi) callconv(.c) i128 {
    return i128_intFromFloat_f80(compiler_rt.f80.fromAbi(a));
}
pub fn i128_intFromFloat_f80(a: f80) i128 {
    return intFromFloat(i128, a);
}

fn __fixxfei(r: [*]u8, bits: usize, a: compiler_rt.f80.Abi) callconv(.c) void {
    const byte_size = std.zig.target.intByteSize(&builtin.target, @intCast(bits));
    return signed_intFromFloat_f80(r[0..byte_size], compiler_rt.f80.fromAbi(a));
}
pub fn signed_intFromFloat_f80(result: []u8, a: f80) void {
    bigIntFromFloat(.signed, @ptrCast(@alignCast(result)), a);
}

fn __fixtfsi(a: compiler_rt.f128.Abi) callconv(.c) i32 {
    return i32_intFromFloat_f128(compiler_rt.f128.fromAbi(a));
}
fn _Qp_qtoi(a: *const f128) callconv(.c) i32 {
    return i32_intFromFloat_f128(a.*);
}
pub fn i32_intFromFloat_f128(a: f128) i32 {
    return intFromFloat(i32, a);
}

fn __fixtfdi(a: compiler_rt.f128.Abi) callconv(.c) i64 {
    return i64_intFromFloat_f128(compiler_rt.f128.fromAbi(a));
}
fn _Qp_qtox(a: *const f128) callconv(.c) i64 {
    return i64_intFromFloat_f128(a.*);
}
pub fn i64_intFromFloat_f128(a: f128) i64 {
    return intFromFloat(i64, a);
}

fn __fixtfti(a: compiler_rt.f128.Abi) callconv(.c) i128 {
    return i128_intFromFloat_f128(compiler_rt.f128.fromAbi(a));
}
pub fn i128_intFromFloat_f128(a: f128) i128 {
    return intFromFloat(i128, a);
}

fn __fixtfei(r: [*]u8, bits: usize, a: compiler_rt.f128.Abi) callconv(.c) void {
    const byte_size = std.zig.target.intByteSize(&builtin.target, @intCast(bits));
    return signed_intFromFloat_f128(r[0..byte_size], compiler_rt.f128.fromAbi(a));
}
pub fn signed_intFromFloat_f128(result: []u8, a: f128) void {
    bigIntFromFloat(.signed, @ptrCast(@alignCast(result)), a);
}

comptime {
    symbol(&__fixunshfsi, "__fixunshfsi");
    symbol(&__fixunshfdi, "__fixunshfdi");
    symbol(&__fixunshfti, "__fixunshfti");
    symbol(&__fixunshfei, "__fixunshfei");

    if (compiler_rt.want_aeabi) {
        symbol(&__aeabi_f2uiz, "__aeabi_f2uiz");
        symbol(&__aeabi_f2ulz, "__aeabi_f2ulz");
        symbol(&__aeabi_fixunssfti, "__fixunssfti");
    } else {
        symbol(&__fixunssfsi, "__fixunssfsi");
        symbol(&__fixunssfdi, "__fixunssfdi");
        if (compiler_rt.want_windows_arm_abi) symbol(&__fixunssfdi, "__stou64");
        symbol(&__fixunssfti, "__fixunssfti");
    }
    symbol(&__fixunssfei, "__fixunssfei");

    if (compiler_rt.want_aeabi) {
        symbol(&__aeabi_d2uiz, "__aeabi_d2uiz");
        symbol(&__aeabi_d2ulz, "__aeabi_d2ulz");
        symbol(&__aeabi_fixunsdfti, "__fixunsdfti");
    } else {
        symbol(&__fixunsdfsi, "__fixunsdfsi");
        symbol(&__fixunsdfdi, "__fixunsdfdi");
        if (compiler_rt.want_windows_arm_abi) symbol(&__fixunsdfdi, "__dtou64");
        symbol(&__fixunsdfti, "__fixunsdfti");
    }
    symbol(&__fixunsdfei, "__fixunsdfei");

    symbol(&__fixunsxfsi, "__fixunsxfsi");
    symbol(&__fixunsxfdi, "__fixunsxfdi");
    symbol(&__fixunsxfti, "__fixunsxfti");
    symbol(&__fixunsxfei, "__fixunsxfei");

    if (compiler_rt.want_ppc_abi) {
        symbol(&__fixunstfsi, "__fixunskfsi");
        symbol(&__fixunstfdi, "__fixunskfdi");
    } else if (compiler_rt.want_sparc64_abi) {
        symbol(&_Qp_qtoui, "_Qp_qtoui");
        symbol(&_Qp_qtoux, "_Qp_qtoux");
    } else if (compiler_rt.want_sparc32_abi) {
        symbol(&__fixunstfsi, "_Q_qtou");
        symbol(&__fixunstfdi, "_Q_qtoull");
    } else {
        symbol(&__fixunstfsi, "__fixunstfsi");
        symbol(&__fixunstfdi, "__fixunstfdi");
    }
    if (compiler_rt.want_ppc_abi) {
        symbol(&__fixunstfti, "__fixunskfti");
        symbol(&__fixunstfei, "__fixunskfei");
    } else {
        symbol(&__fixunstfti, "__fixunstfti");
        symbol(&__fixunstfei, "__fixunstfei");
    }
}

fn __fixunshfsi(a: compiler_rt.f16.Abi) callconv(.c) u32 {
    return u32_intFromFloat_f16(compiler_rt.f16.fromAbi(a));
}
pub fn u32_intFromFloat_f16(a: f16) u32 {
    return intFromFloat(u32, a);
}

fn __fixunshfdi(a: compiler_rt.f16.Abi) callconv(.c) u64 {
    return u64_intFromFloat_f16(compiler_rt.f16.fromAbi(a));
}
pub fn u64_intFromFloat_f16(a: f16) u64 {
    return intFromFloat(u64, a);
}

fn __fixunshfti(a: compiler_rt.f16.Abi) callconv(.c) u128 {
    return u128_intFromFloat_f16(compiler_rt.f16.fromAbi(a));
}
pub fn u128_intFromFloat_f16(a: f16) u128 {
    return intFromFloat(u128, a);
}

fn __fixunshfei(r: [*]u8, bits: usize, a: compiler_rt.f16.Abi) callconv(.c) void {
    const byte_size = std.zig.target.intByteSize(&builtin.target, @intCast(bits));
    return unsigned_intFromFloat_f16(r[0..byte_size], compiler_rt.f16.fromAbi(a));
}
pub fn unsigned_intFromFloat_f16(result: []u8, a: f16) void {
    bigIntFromFloat(.unsigned, @ptrCast(@alignCast(result)), a);
}

fn __fixunssfsi(a: compiler_rt.f32.Abi) callconv(.c) u32 {
    return u32_intFromFloat_f32(compiler_rt.f32.fromAbi(a));
}
fn __aeabi_f2uiz(a: f32) callconv(.{ .arm_aapcs = .{} }) u32 {
    return u32_intFromFloat_f32(a);
}
pub fn u32_intFromFloat_f32(a: f32) u32 {
    return intFromFloat(u32, a);
}

fn __fixunssfdi(a: compiler_rt.f32.Abi) callconv(.c) u64 {
    return u64_intFromFloat_f32(compiler_rt.f32.fromAbi(a));
}
fn __aeabi_f2ulz(a: f32) callconv(.{ .arm_aapcs = .{} }) u64 {
    return u64_intFromFloat_f32(a);
}
pub fn u64_intFromFloat_f32(a: f32) u64 {
    return intFromFloat(u64, a);
}

fn __fixunssfti(a: compiler_rt.f32.Abi) callconv(.c) u128 {
    return u128_intFromFloat_f32(compiler_rt.f32.fromAbi(a));
}
fn __aeabi_fixunssfti(_: compiler_rt.f32.Abi) callconv(.naked) u128 {
    switch (builtin.abi.float()) {
        .soft => asm volatile (
            \\ push {r0-r4, lr}
            \\ movs r1, r0
            \\ mov r0, sp
            \\ bl %[__fixunssfti]
            \\ pop {r0-r4, pc}
            :
            : [__fixunssfti] "X" (&__fixunssfti),
        ),
        .hard => asm volatile (
            \\ push {r0-r4, lr}
            \\ mov r0, sp
            \\ bl %[__fixunssfti]
            \\ pop {r0-r4, pc}
            :
            : [__fixunssfti] "X" (&__fixunssfti),
        ),
    }
}
pub fn u128_intFromFloat_f32(a: f32) u128 {
    return intFromFloat(u128, a);
}

fn __fixunssfei(r: [*]u8, bits: usize, a: compiler_rt.f32.Abi) callconv(.c) void {
    const byte_size = std.zig.target.intByteSize(&builtin.target, @intCast(bits));
    return unsigned_intFromFloat_f32(r[0..byte_size], compiler_rt.f32.fromAbi(a));
}
pub fn unsigned_intFromFloat_f32(result: []u8, a: f32) void {
    bigIntFromFloat(.unsigned, @ptrCast(@alignCast(result)), a);
}

fn __fixunsdfsi(a: compiler_rt.f64.Abi) callconv(.c) u32 {
    return u32_intFromFloat_f64(compiler_rt.f64.fromAbi(a));
}
fn __aeabi_d2uiz(a: f64) callconv(.{ .arm_aapcs = .{} }) u32 {
    return u32_intFromFloat_f64(a);
}
pub fn u32_intFromFloat_f64(a: f64) u32 {
    return intFromFloat(u32, a);
}

fn __fixunsdfdi(a: compiler_rt.f64.Abi) callconv(.c) u64 {
    return u64_intFromFloat_f64(compiler_rt.f64.fromAbi(a));
}
fn __aeabi_d2ulz(a: f64) callconv(.{ .arm_aapcs = .{} }) u64 {
    return u64_intFromFloat_f64(a);
}
pub fn u64_intFromFloat_f64(a: f64) u64 {
    return intFromFloat(u64, a);
}

fn __fixunsdfti(a: compiler_rt.f64.Abi) callconv(.c) u128 {
    return u128_intFromFloat_f64(compiler_rt.f64.fromAbi(a));
}
fn __aeabi_fixunsdfti(_: compiler_rt.f64.Abi) callconv(.naked) u128 {
    switch (builtin.abi.float()) {
        .soft => asm volatile (
            \\ push {r0-r4, lr}
            \\ movs r3, r1
            \\ movs r2, r0
            \\ mov r0, sp
            \\ bl %[__fixunsdfti]
            \\ pop {r0-r4, pc}
            :
            : [__fixunsdfti] "X" (&__fixunsdfti),
        ),
        .hard => asm volatile (
            \\ push {r0-r4, lr}
            \\ mov r0, sp
            \\ bl %[__fixunsdfti]
            \\ pop {r0-r4, pc}
            :
            : [__fixunsdfti] "X" (&__fixunsdfti),
        ),
    }
}
pub fn u128_intFromFloat_f64(a: f64) u128 {
    return intFromFloat(u128, a);
}

fn __fixunsdfei(r: [*]u8, bits: usize, a: compiler_rt.f64.Abi) callconv(.c) void {
    const byte_size = std.zig.target.intByteSize(&builtin.target, @intCast(bits));
    return unsigned_intFromFloat_f64(r[0..byte_size], compiler_rt.f64.fromAbi(a));
}
pub fn unsigned_intFromFloat_f64(result: []u8, a: f64) void {
    bigIntFromFloat(.unsigned, @ptrCast(@alignCast(result)), a);
}

fn __fixunsxfsi(a: compiler_rt.f80.Abi) callconv(.c) u32 {
    return u32_intFromFloat_f80(compiler_rt.f80.fromAbi(a));
}
pub fn u32_intFromFloat_f80(a: f80) u32 {
    return intFromFloat(u32, a);
}

fn __fixunsxfdi(a: compiler_rt.f80.Abi) callconv(.c) u64 {
    return u64_intFromFloat_f80(compiler_rt.f80.fromAbi(a));
}
pub fn u64_intFromFloat_f80(a: f80) u64 {
    return intFromFloat(u64, a);
}

fn __fixunsxfti(a: compiler_rt.f80.Abi) callconv(.c) u128 {
    return u128_intFromFloat_f80(compiler_rt.f80.fromAbi(a));
}
pub fn u128_intFromFloat_f80(a: f80) u128 {
    return intFromFloat(u128, a);
}

fn __fixunsxfei(r: [*]u8, bits: usize, a: compiler_rt.f80.Abi) callconv(.c) void {
    const byte_size = std.zig.target.intByteSize(&builtin.target, @intCast(bits));
    return unsigned_intFromFloat_f80(r[0..byte_size], compiler_rt.f80.fromAbi(a));
}
pub fn unsigned_intFromFloat_f80(result: []u8, a: f80) void {
    bigIntFromFloat(.unsigned, @ptrCast(@alignCast(result)), a);
}

fn __fixunstfsi(a: compiler_rt.f128.Abi) callconv(.c) u32 {
    return u32_intFromFloat_f128(compiler_rt.f128.fromAbi(a));
}
fn _Qp_qtoui(a: *const f128) callconv(.c) u32 {
    return u32_intFromFloat_f128(a.*);
}
pub fn u32_intFromFloat_f128(a: f128) u32 {
    return intFromFloat(u32, a);
}

fn __fixunstfdi(a: compiler_rt.f128.Abi) callconv(.c) u64 {
    return u64_intFromFloat_f128(compiler_rt.f128.fromAbi(a));
}
fn _Qp_qtoux(a: *const f128) callconv(.c) u64 {
    return u64_intFromFloat_f128(a.*);
}
pub fn u64_intFromFloat_f128(a: f128) u64 {
    return intFromFloat(u64, a);
}

fn __fixunstfti(a: compiler_rt.f128.Abi) callconv(.c) u128 {
    return u128_intFromFloat_f128(compiler_rt.f128.fromAbi(a));
}
pub fn u128_intFromFloat_f128(a: f128) u128 {
    return intFromFloat(u128, a);
}

fn __fixunstfei(r: [*]u8, bits: usize, a: compiler_rt.f128.Abi) callconv(.c) void {
    const byte_size = std.zig.target.intByteSize(&builtin.target, @intCast(bits));
    return unsigned_intFromFloat_f128(r[0..byte_size], compiler_rt.f128.fromAbi(a));
}
pub fn unsigned_intFromFloat_f128(result: []u8, a: f128) void {
    bigIntFromFloat(.unsigned, @ptrCast(@alignCast(result)), a);
}

inline fn intFromFloat(comptime I: type, a: anytype) I {
    const F = @TypeOf(a);
    const float_bits = @typeInfo(F).float.bits;
    const int_bits = @typeInfo(I).int.bits;
    const rep_t = @Int(.unsigned, float_bits);
    const sig_bits = math.floatMantissaBits(F);
    const exp_bits = math.floatExponentBits(F);
    const fractional_bits = math.floatFractionalBits(F);

    const implicit_bit = if (F != f80) (@as(rep_t, 1) << sig_bits) else 0;
    const max_exp = (1 << (exp_bits - 1));
    const exp_bias = max_exp - 1;
    const sig_mask = (@as(rep_t, 1) << sig_bits) - 1;

    // Break a into sign, exponent, significand
    const a_rep: rep_t = @bitCast(a);
    const negative = (a_rep >> (float_bits - 1)) != 0;
    const exponent = @as(i32, @intCast((a_rep << 1) >> (sig_bits + 1))) - exp_bias;
    const significand: rep_t = (a_rep & sig_mask) | implicit_bit;

    // If the exponent is negative, the result rounds to zero.
    if (exponent < 0) return 0;

    // If the value is too large for the integer type, saturate.
    switch (@typeInfo(I).int.signedness) {
        .unsigned => {
            if (negative) return 0;
            if (@as(c_uint, @intCast(exponent)) >= @min(int_bits, max_exp)) return math.maxInt(I);
        },
        .signed => if (@as(c_uint, @intCast(exponent)) >= @min(int_bits - 1, max_exp)) {
            return if (negative) math.minInt(I) else math.maxInt(I);
        },
    }

    // If 0 <= exponent < sig_bits, right shift to get the result.
    // Otherwise, shift left.
    var result: I = undefined;
    if (exponent < fractional_bits) {
        result = @intCast(significand >> @intCast(fractional_bits - exponent));
    } else {
        result = @as(I, @intCast(significand)) << @intCast(exponent - fractional_bits);
    }

    if ((@typeInfo(I).int.signedness == .signed) and negative)
        return ~result +% 1;
    return result;
}

inline fn bigIntFromFloat(comptime signedness: std.lang.Signedness, result: []u32, a: anytype) void {
    const endian = builtin.cpu.arch.endian();
    switch (result.len) {
        0 => return,
        inline 1...4 => |limbs_len| {
            const I = @Int(signedness, 32 * limbs_len);
            const low_to_high: [limbs_len]u32 = @bitCast(@as(I, @intFromFloat(a)));
            result[0..limbs_len].* = switch (endian) {
                .little => low_to_high,
                .big => switch (limbs_len) {
                    1 => .{low_to_high[0]},
                    2 => .{ low_to_high[1], low_to_high[0] },
                    3 => .{ low_to_high[2], low_to_high[1], low_to_high[0] },
                    4 => .{ low_to_high[3], low_to_high[2], low_to_high[1], low_to_high[0] },
                    else => comptime unreachable,
                },
            };
            return;
        },
        else => {},
    }

    // sign implicit fraction
    const significand_bits = 1 + math.floatFractionalBits(@TypeOf(a));
    const I = @Int(signedness, @as(u16, @intFromBool(signedness == .signed)) + significand_bits);

    const parts = math.frexp(a);
    const significand_bits_adjusted_to_handle_smin = @as(i32, significand_bits) +
        @intFromBool(signedness == .signed and parts.exponent == 32 * result.len);
    const exponent: usize = @intCast(@max(parts.exponent - significand_bits_adjusted_to_handle_smin, 0));
    const int: I = @intFromFloat(switch (exponent) {
        0 => a,
        else => math.ldexp(parts.significand, significand_bits_adjusted_to_handle_smin),
    });
    switch (signedness) {
        .signed => {
            const exponent_limb = switch (endian) {
                .little => exponent / 32,
                .big => result.len - 1 - exponent / 32,
            };
            const sign_bits: u32 = if (int < 0) math.maxInt(u32) else 0;
            @memset(result[0..exponent_limb], switch (endian) {
                .little => 0,
                .big => sign_bits,
            });
            result[exponent_limb] = sign_bits << @truncate(exponent);
            @memset(result[exponent_limb + 1 ..], switch (endian) {
                .little => sign_bits,
                .big => 0,
            });
        },
        .unsigned => @memset(result, 0),
    }
    std.mem.writePackedInt(I, std.mem.sliceAsBytes(result), exponent, int, .native);
}

test {
    _ = @import("int_from_float_test.zig");
}
