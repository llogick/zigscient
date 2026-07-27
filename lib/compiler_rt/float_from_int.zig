const builtin = @import("builtin");
const std = @import("std");
const math = std.math;

const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;

comptime {
    symbol(&__floatsihf, "__floatsihf");
    symbol(&__floatdihf, "__floatdihf");
    symbol(&__floattihf, "__floattihf");
    symbol(&__floateihf, "__floateihf");

    if (compiler_rt.want_aeabi) {
        symbol(&__aeabi_i2f, "__aeabi_i2f");
        symbol(&__aeabi_l2f, "__aeabi_l2f");
    } else {
        symbol(&__floatsisf, "__floatsisf");
        symbol(&__floatdisf, "__floatdisf");
        if (compiler_rt.want_windows_arm_abi) symbol(&__floatdisf, "__i64tos");
    }
    symbol(&__floattisf, "__floattisf");
    symbol(&__floateisf, "__floateisf");

    if (compiler_rt.want_aeabi) {
        symbol(&__aeabi_i2d, "__aeabi_i2d");
        symbol(&__aeabi_l2d, "__aeabi_l2d");
    } else {
        symbol(&__floatsidf, "__floatsidf");
        symbol(&__floatdidf, "__floatdidf");
        if (compiler_rt.want_windows_arm_abi) symbol(&__floatdidf, "__i64tod");
    }
    symbol(&__floattidf, "__floattidf");
    symbol(&__floateidf, "__floateidf");

    symbol(&__floatsixf, "__floatsixf");
    symbol(&__floatdixf, "__floatdixf");
    symbol(&__floattixf, "__floattixf");
    symbol(&__floateixf, "__floateixf");

    if (compiler_rt.want_ppc_abi) {
        symbol(&__floatsitf, "__floatsikf");
        symbol(&__floatditf, "__floatdikf");
    } else if (compiler_rt.want_sparc64_abi) {
        symbol(&_Qp_itoq, "_Qp_itoq");
        symbol(&_Qp_xtoq, "_Qp_xtoq");
    } else if (compiler_rt.want_sparc32_abi) {
        symbol(&__floatsitf, "_Q_itoq");
        symbol(&__floatditf, "_Q_lltoq");
    } else {
        symbol(&__floatsitf, "__floatsitf");
        symbol(&__floatditf, "__floatditf");
    }
    if (compiler_rt.want_ppc_abi) {
        symbol(&__floattitf, "__floattikf");
        symbol(&__floateitf, "__floateikf");
    } else {
        if (builtin.cpu.arch == .x86) {
            symbol(&__floattitf_x86, "__floattitf");
        } else {
            symbol(&__floattitf, "__floattitf");
        }
        symbol(&__floateitf, "__floateitf");
    }
}

fn __floatsihf(a: i32) callconv(.c) compiler_rt.f16.Abi {
    return compiler_rt.f16.toAbi(f16_floatFromInt_i32(a));
}
pub fn f16_floatFromInt_i32(a: i32) f16 {
    return floatFromInt(f16, a);
}

fn __floatdihf(a: i64) callconv(.c) compiler_rt.f16.Abi {
    return compiler_rt.f16.toAbi(f16_floatFromInt_i64(a));
}
pub fn f16_floatFromInt_i64(a: i64) f16 {
    return floatFromInt(f16, a);
}

fn __floattihf(a: i128) callconv(.c) compiler_rt.f16.Abi {
    return compiler_rt.f16.toAbi(f16_floatFromInt_i128(a));
}
pub fn f16_floatFromInt_i128(a: i128) f16 {
    return floatFromInt(f16, a);
}

fn __floateihf(a: [*]const u8, bits: usize) callconv(.c) compiler_rt.f16.Abi {
    const byte_size = std.zig.target.intByteSize(&builtin.target, @intCast(bits));
    return compiler_rt.f16.toAbi(f16_floatFromInt_signed(a[0..byte_size]));
}
pub fn f16_floatFromInt_signed(a: []const u8) f16 {
    return floatFromBigInt(f16, .signed, @ptrCast(@alignCast(a)));
}

fn __floatsisf(a: i32) callconv(.c) compiler_rt.f32.Abi {
    return compiler_rt.f32.toAbi(f32_floatFromInt_i32(a));
}
fn __aeabi_i2f(a: i32) callconv(.{ .arm_aapcs = .{} }) f32 {
    return f32_floatFromInt_i32(a);
}
pub fn f32_floatFromInt_i32(a: i32) f32 {
    return floatFromInt(f32, a);
}

fn __floatdisf(a: i64) callconv(.c) compiler_rt.f32.Abi {
    return compiler_rt.f32.toAbi(f32_floatFromInt_i64(a));
}
fn __aeabi_l2f(a: i64) callconv(.{ .arm_aapcs = .{} }) f32 {
    return f32_floatFromInt_i64(a);
}
pub fn f32_floatFromInt_i64(a: i64) f32 {
    return floatFromInt(f32, a);
}

fn __floattisf(a: i128) callconv(.c) compiler_rt.f32.Abi {
    return compiler_rt.f32.toAbi(f32_floatFromInt_i128(a));
}
pub fn f32_floatFromInt_i128(a: i128) f32 {
    return floatFromInt(f32, a);
}

fn __floateisf(a: [*]const u8, bits: usize) callconv(.c) compiler_rt.f32.Abi {
    const byte_size = std.zig.target.intByteSize(&builtin.target, @intCast(bits));
    return compiler_rt.f32.toAbi(f32_floatFromInt_signed(a[0..byte_size]));
}
pub fn f32_floatFromInt_signed(a: []const u8) f32 {
    return floatFromBigInt(f32, .signed, @ptrCast(@alignCast(a)));
}

fn __floatsidf(a: i32) callconv(.c) compiler_rt.f64.Abi {
    return compiler_rt.f64.toAbi(f64_floatFromInt_i32(a));
}
fn __aeabi_i2d(a: i32) callconv(.{ .arm_aapcs = .{} }) f64 {
    return f64_floatFromInt_i32(a);
}
pub fn f64_floatFromInt_i32(a: i32) f64 {
    return floatFromInt(f64, a);
}

fn __floatdidf(a: i64) callconv(.c) compiler_rt.f64.Abi {
    return compiler_rt.f64.toAbi(f64_floatFromInt_i64(a));
}
fn __aeabi_l2d(a: i64) callconv(.{ .arm_aapcs = .{} }) f64 {
    return f64_floatFromInt_i64(a);
}
pub fn f64_floatFromInt_i64(a: i64) f64 {
    return floatFromInt(f64, a);
}

fn __floattidf(a: i128) callconv(.c) compiler_rt.f64.Abi {
    return compiler_rt.f64.toAbi(f64_floatFromInt_i128(a));
}
pub fn f64_floatFromInt_i128(a: i128) f64 {
    return floatFromInt(f64, a);
}

fn __floateidf(a: [*]const u8, bits: usize) callconv(.c) compiler_rt.f64.Abi {
    const byte_size = std.zig.target.intByteSize(&builtin.target, @intCast(bits));
    return compiler_rt.f64.toAbi(f64_floatFromInt_signed(a[0..byte_size]));
}
pub fn f64_floatFromInt_signed(a: []const u8) f64 {
    return floatFromBigInt(f64, .signed, @ptrCast(@alignCast(a)));
}

fn __floatsixf(a: i32) callconv(.c) compiler_rt.f80.Abi {
    return compiler_rt.f80.toAbi(f80_floatFromInt_i32(a));
}
pub fn f80_floatFromInt_i32(a: i32) f80 {
    return floatFromInt(f80, a);
}

fn __floatdixf(a: i64) callconv(.c) compiler_rt.f80.Abi {
    return compiler_rt.f80.toAbi(f80_floatFromInt_i64(a));
}
pub fn f80_floatFromInt_i64(a: i64) f80 {
    return floatFromInt(f80, a);
}

fn __floattixf(a: i128) callconv(.c) compiler_rt.f80.Abi {
    return compiler_rt.f80.toAbi(f80_floatFromInt_i128(a));
}
pub fn f80_floatFromInt_i128(a: i128) f80 {
    return floatFromInt(f80, a);
}

fn __floateixf(a: [*]const u8, bits: usize) callconv(.c) compiler_rt.f80.Abi {
    const byte_size = std.zig.target.intByteSize(&builtin.target, @intCast(bits));
    return compiler_rt.f80.toAbi(f80_floatFromInt_signed(a[0..byte_size]));
}
pub fn f80_floatFromInt_signed(a: []const u8) f80 {
    return floatFromBigInt(f80, .signed, @ptrCast(@alignCast(a)));
}

fn __floatsitf(a: i32) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(f128_floatFromInt_i32(a));
}
fn _Qp_itoq(c: *f128, a: i32) callconv(.c) void {
    c.* = f128_floatFromInt_i32(a);
}
pub fn f128_floatFromInt_i32(a: i32) f128 {
    return floatFromInt(f128, a);
}

fn __floatditf(a: i64) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(f128_floatFromInt_i64(a));
}
fn _Qp_xtoq(c: *f128, a: i64) callconv(.c) void {
    c.* = f128_floatFromInt_i64(a);
}
pub fn f128_floatFromInt_i64(a: i64) f128 {
    return floatFromInt(f128, a);
}

fn __floattitf(a: i128) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(f128_floatFromInt_i128(a));
}
fn __floattitf_x86(a: f128) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(f128_floatFromInt_i128(@bitCast(a)));
}
pub fn f128_floatFromInt_i128(a: i128) f128 {
    return floatFromInt(f128, a);
}

fn __floateitf(a: [*]const u8, bits: usize) callconv(.c) compiler_rt.f128.Abi {
    const byte_size = std.zig.target.intByteSize(&builtin.target, @intCast(bits));
    return compiler_rt.f128.toAbi(f128_floatFromInt_signed(a[0..byte_size]));
}
pub fn f128_floatFromInt_signed(a: []const u8) f128 {
    return floatFromBigInt(f128, .signed, @ptrCast(@alignCast(a)));
}

comptime {
    symbol(&__floatunsihf, "__floatunsihf");
    symbol(&__floatundihf, "__floatundihf");
    symbol(&__floatuntihf, "__floatuntihf");
    symbol(&__floatuneihf, "__floatuneihf");

    if (compiler_rt.want_aeabi) {
        symbol(&__aeabi_ui2f, "__aeabi_ui2f");
        symbol(&__aeabi_ul2f, "__aeabi_ul2f");
    } else {
        symbol(&__floatunsisf, "__floatunsisf");
        symbol(&__floatundisf, "__floatundisf");
        if (compiler_rt.want_windows_arm_abi) symbol(&__floatundisf, "__u64tos");
    }
    symbol(&__floatuntisf, "__floatuntisf");
    symbol(&__floatuneisf, "__floatuneisf");

    if (compiler_rt.want_aeabi) {
        symbol(&__aeabi_ui2d, "__aeabi_ui2d");
    } else {
        symbol(&__floatunsidf, "__floatunsidf");
    }
    if (compiler_rt.want_aeabi) {
        symbol(&__aeabi_ul2d, "__aeabi_ul2d");
    } else {
        if (compiler_rt.want_windows_arm_abi) {
            symbol(&__floatundidf, "__u64tod");
        }
        symbol(&__floatundidf, "__floatundidf");
    }
    symbol(&__floatuntidf, "__floatuntidf");
    symbol(&__floatuneidf, "__floatuneidf");

    symbol(&__floatunsixf, "__floatunsixf");
    symbol(&__floatundixf, "__floatundixf");
    symbol(&__floatuntixf, "__floatuntixf");
    symbol(&__floatuneixf, "__floatuneixf");

    if (compiler_rt.want_ppc_abi) {
        symbol(&__floatunsitf, "__floatunsikf");
        symbol(&__floatunditf, "__floatundikf");
    } else if (compiler_rt.want_sparc64_abi) {
        symbol(&_Qp_uitoq, "_Qp_uitoq");
        symbol(&_Qp_uxtoq, "_Qp_uxtoq");
    } else if (compiler_rt.want_sparc32_abi) {
        symbol(&__floatunsitf, "_Q_utoq");
        symbol(&__floatunditf, "_Q_ulltoq");
    } else {
        symbol(&__floatunsitf, "__floatunsitf");
        symbol(&__floatunditf, "__floatunditf");
    }
    if (compiler_rt.want_ppc_abi) {
        symbol(&__floatuntitf, "__floatuntikf");
        symbol(&__floatuneitf, "__floatuneikf");
    } else {
        if (builtin.cpu.arch == .x86) {
            symbol(&__floatuntitf_x86, "__floatuntitf");
        } else if (builtin.cpu.arch == .x86_64 and
            (builtin.os.tag == .windows or builtin.os.tag == .uefi))
        {
            symbol(&__floatuntitf_x86_64_windows, "__floatuntitf");
        } else {
            symbol(&__floatuntitf, "__floatuntitf");
        }
        symbol(&__floatuneitf, "__floatuneitf");
    }
}

fn __floatunsihf(a: u32) callconv(.c) compiler_rt.f16.Abi {
    return compiler_rt.f16.toAbi(f16_floatFromInt_u32(a));
}
pub fn f16_floatFromInt_u32(a: u32) f16 {
    return floatFromInt(f16, a);
}

fn __floatundihf(a: u64) callconv(.c) compiler_rt.f16.Abi {
    return compiler_rt.f16.toAbi(f16_floatFromInt_u64(a));
}
pub fn f16_floatFromInt_u64(a: u64) f16 {
    return floatFromInt(f16, a);
}

fn __floatuntihf(a: u128) callconv(.c) compiler_rt.f16.Abi {
    return compiler_rt.f16.toAbi(f16_floatFromInt_u128(a));
}
pub fn f16_floatFromInt_u128(a: u128) f16 {
    return floatFromInt(f16, a);
}

fn __floatuneihf(a: [*]const u8, bits: usize) callconv(.c) compiler_rt.f16.Abi {
    const byte_size = std.zig.target.intByteSize(&builtin.target, @intCast(bits));
    return compiler_rt.f16.toAbi(f16_floatFromInt_unsigned(a[0..byte_size]));
}
pub fn f16_floatFromInt_unsigned(a: []const u8) f16 {
    return floatFromBigInt(f16, .unsigned, @ptrCast(@alignCast(a)));
}

fn __floatunsisf(a: u32) callconv(.c) compiler_rt.f32.Abi {
    return compiler_rt.f32.toAbi(f32_floatFromInt_u32(a));
}
fn __aeabi_ui2f(a: u32) callconv(.{ .arm_aapcs = .{} }) f32 {
    return f32_floatFromInt_u32(a);
}
pub fn f32_floatFromInt_u32(a: u32) f32 {
    return floatFromInt(f32, a);
}

fn __floatundisf(a: u64) callconv(.c) compiler_rt.f32.Abi {
    return compiler_rt.f32.toAbi(f32_floatFromInt_u64(a));
}
fn __aeabi_ul2f(a: u64) callconv(.{ .arm_aapcs = .{} }) f32 {
    return f32_floatFromInt_u64(a);
}
pub fn f32_floatFromInt_u64(a: u64) f32 {
    return floatFromInt(f32, a);
}

fn __floatuntisf(a: u128) callconv(.c) compiler_rt.f32.Abi {
    return compiler_rt.f32.toAbi(f32_floatFromInt_u128(a));
}
pub fn f32_floatFromInt_u128(a: u128) f32 {
    return floatFromInt(f32, a);
}

fn __floatuneisf(a: [*]const u8, bits: usize) callconv(.c) compiler_rt.f32.Abi {
    const byte_size = std.zig.target.intByteSize(&builtin.target, @intCast(bits));
    return compiler_rt.f32.toAbi(f32_floatFromInt_unsigned(a[0..byte_size]));
}
pub fn f32_floatFromInt_unsigned(a: []const u8) f32 {
    return floatFromBigInt(f32, .unsigned, @ptrCast(@alignCast(a)));
}

fn __floatunsidf(a: u32) callconv(.c) compiler_rt.f64.Abi {
    return compiler_rt.f64.toAbi(f64_floatFromInt_u32(a));
}
fn __aeabi_ui2d(a: u32) callconv(.{ .arm_aapcs = .{} }) f64 {
    return f64_floatFromInt_u32(a);
}
pub fn f64_floatFromInt_u32(a: u32) f64 {
    return floatFromInt(f64, a);
}

fn __floatundidf(a: u64) callconv(.c) compiler_rt.f64.Abi {
    return compiler_rt.f64.toAbi(f64_floatFromInt_u64(a));
}
fn __aeabi_ul2d(a: u64) callconv(.{ .arm_aapcs = .{} }) f64 {
    return f64_floatFromInt_u64(a);
}
pub fn f64_floatFromInt_u64(a: u64) f64 {
    return floatFromInt(f64, a);
}

fn __floatuntidf(a: u128) callconv(.c) compiler_rt.f64.Abi {
    return compiler_rt.f64.toAbi(f64_floatFromInt_u128(a));
}
pub fn f64_floatFromInt_u128(a: u128) f64 {
    return floatFromInt(f64, a);
}

fn __floatuneidf(a: [*]const u8, bits: usize) callconv(.c) compiler_rt.f64.Abi {
    const byte_size = std.zig.target.intByteSize(&builtin.target, @intCast(bits));
    return compiler_rt.f64.toAbi(f64_floatFromInt_unsigned(a[0..byte_size]));
}
pub fn f64_floatFromInt_unsigned(a: []const u8) f64 {
    return floatFromBigInt(f64, .unsigned, @ptrCast(@alignCast(a)));
}

fn __floatunsixf(a: u32) callconv(.c) compiler_rt.f80.Abi {
    return compiler_rt.f80.toAbi(f80_floatFromInt_u32(a));
}
pub fn f80_floatFromInt_u32(a: u32) f80 {
    return floatFromInt(f80, a);
}

fn __floatundixf(a: u64) callconv(.c) compiler_rt.f80.Abi {
    return compiler_rt.f80.toAbi(f80_floatFromInt_u64(a));
}
pub fn f80_floatFromInt_u64(a: u64) f80 {
    return floatFromInt(f80, a);
}

fn __floatuntixf(a: u128) callconv(.c) compiler_rt.f80.Abi {
    return compiler_rt.f80.toAbi(f80_floatFromInt_u128(a));
}
pub fn f80_floatFromInt_u128(a: u128) f80 {
    return floatFromInt(f80, a);
}

fn __floatuneixf(a: [*]const u8, bits: usize) callconv(.c) compiler_rt.f80.Abi {
    const byte_size = std.zig.target.intByteSize(&builtin.target, @intCast(bits));
    return compiler_rt.f80.toAbi(f80_floatFromInt_unsigned(a[0..byte_size]));
}
pub fn f80_floatFromInt_unsigned(a: []const u8) f80 {
    return floatFromBigInt(f80, .unsigned, @ptrCast(@alignCast(a)));
}

fn __floatunsitf(a: u32) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(f128_floatFromInt_u32(a));
}
fn _Qp_uitoq(c: *f128, a: u32) callconv(.c) void {
    c.* = f128_floatFromInt_u32(a);
}
pub fn f128_floatFromInt_u32(a: u32) f128 {
    return floatFromInt(f128, a);
}

fn __floatunditf(a: u64) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(f128_floatFromInt_u64(a));
}
fn _Qp_uxtoq(c: *f128, a: u64) callconv(.c) void {
    c.* = f128_floatFromInt_u64(a);
}
pub fn f128_floatFromInt_u64(a: u64) f128 {
    return floatFromInt(f128, a);
}

fn __floatuntitf(a: u128) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(f128_floatFromInt_u128(a));
}
fn __floatuntitf_x86(a: f128) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(f128_floatFromInt_u128(@bitCast(a)));
}
fn __floatuntitf_x86_64_windows(a_lo: u64, a_hi: u64) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(f128_floatFromInt_u128(@bitCast(
        packed struct { lo: u64, hi: u64 }{ .lo = a_lo, .hi = a_hi },
    )));
}
pub fn f128_floatFromInt_u128(a: u128) f128 {
    return floatFromInt(f128, a);
}

fn __floatuneitf(a: [*]const u8, bits: usize) callconv(.c) compiler_rt.f128.Abi {
    const byte_size = std.zig.target.intByteSize(&builtin.target, @intCast(bits));
    return compiler_rt.f128.toAbi(f128_floatFromInt_unsigned(a[0..byte_size]));
}
pub fn f128_floatFromInt_unsigned(a: []const u8) f128 {
    return floatFromBigInt(f128, .unsigned, @ptrCast(@alignCast(a)));
}

inline fn floatFromInt(comptime T: type, x: anytype) T {
    if (x == 0) return 0;

    // Various constants whose values follow from the type parameters.
    // Any reasonable optimizer will fold and propagate all of these.
    const Z = @Int(.unsigned, @bitSizeOf(@TypeOf(x)));
    const uT = @Int(.unsigned, @bitSizeOf(T));
    const inf = math.inf(T);
    const float_bits = @bitSizeOf(T);
    const int_bits = @bitSizeOf(@TypeOf(x));
    const exp_bits = math.floatExponentBits(T);
    const fractional_bits = math.floatFractionalBits(T);
    const exp_bias = math.maxInt(@Int(.unsigned, exp_bits - 1));
    const implicit_bit = if (T != f80) @as(uT, 1) << fractional_bits else 0;
    const max_exp = exp_bias;

    // Sign
    const abs_val = @abs(x);
    const sign_bit = if (x < 0) @as(uT, 1) << (float_bits - 1) else 0;
    var result: uT = sign_bit;

    // Compute significand
    const exp = int_bits - @clz(abs_val) - 1;
    if (int_bits <= fractional_bits or exp <= fractional_bits) {
        const shift_amt = fractional_bits - @as(math.Log2Int(uT), @intCast(exp));

        // Shift up result to line up with the significand - no rounding required
        result = @as(uT, @intCast(abs_val)) << shift_amt;
        result ^= implicit_bit; // Remove implicit integer bit
    } else {
        const shift_amt: math.Log2Int(Z) = @intCast(exp - fractional_bits);
        const exact_tie: bool = @ctz(abs_val) == shift_amt - 1;

        // Shift down result and remove implicit integer bit
        result = @as(uT, @intCast((abs_val >> (shift_amt - 1)))) ^ (implicit_bit << 1);

        // Round result, including round-to-even for exact ties
        result = ((result + 1) >> 1) & ~@as(uT, @intFromBool(exact_tie));
    }

    // Compute exponent
    if ((int_bits > max_exp) and (exp > max_exp)) // If exponent too large, overflow to infinity
        return @bitCast(sign_bit | @as(uT, @bitCast(inf)));

    result += (@as(uT, exp) + exp_bias) << math.floatMantissaBits(T);

    // If the result included a carry, we need to restore the explicit integer bit
    if (T == f80) result |= 1 << fractional_bits;

    return @bitCast(sign_bit | result);
}

const endian = builtin.cpu.arch.endian();
inline fn limb(limbs: []const u32, index: usize) u32 {
    return switch (endian) {
        .little => limbs[index],
        .big => limbs[limbs.len - 1 - index],
    };
}

inline fn floatFromBigInt(comptime T: type, comptime signedness: std.lang.Signedness, x: []const u32) T {
    switch (x.len) {
        0 => return 0,
        inline 1...4 => |limbs_len| {
            const low_to_high: [limbs_len]u32 = switch (endian) {
                .little => x[0..limbs_len].*,
                .big => switch (limbs_len) {
                    1 => .{x[0]},
                    2 => .{ x[1], x[0] },
                    3 => .{ x[2], x[1], x[0] },
                    4 => .{ x[3], x[2], x[1], x[0] },
                    else => comptime unreachable,
                },
            };
            const I = @Int(signedness, 32 * limbs_len);
            const int: I = @bitCast(low_to_high);
            return @floatFromInt(int);
        },
        else => {},
    }

    // sign implicit fraction round sticky
    const I = comptime @Int(
        signedness,
        @as(u16, @intFromBool(signedness == .signed)) + 1 + math.floatFractionalBits(T) + 1 + 1,
    );

    const clrsb = clrsb: {
        var clsb: usize = 0;
        const sign_bits: u32 = switch (signedness) {
            .signed => @bitCast(@as(i32, @bitCast(limb(x, x.len - 1))) >> 31),
            .unsigned => 0,
        };
        for (0..x.len) |limb_index| {
            const l = limb(x, x.len - 1 - limb_index) ^ sign_bits;
            clsb += @clz(l);
            if (l != 0) break;
        }
        break :clrsb clsb - @intFromBool(signedness == .signed);
    };
    const active_bits = 32 * x.len - clrsb;
    const exponent = active_bits -| @bitSizeOf(I);
    const exponent_limb = exponent / 32;
    const sticky = for (0..exponent_limb) |limb_index| {
        if (limb(x, limb_index) != 0) break true;
    } else limb(x, exponent_limb) & ((@as(u32, 1) << @truncate(exponent)) - 1) != 0;
    return math.ldexp(@as(T, @floatFromInt(
        std.mem.readPackedInt(I, std.mem.sliceAsBytes(x), exponent, .native) | @intFromBool(sticky),
    )), @intCast(exponent));
}

test {
    _ = @import("float_from_int_test.zig");
}
