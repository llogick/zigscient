const std = @import("std");

const compiler_rt = @import("../compiler_rt.zig");
const symbol = compiler_rt.symbol;

comptime {
    if (compiler_rt.want_aeabi) {
        if (compiler_rt.gnu_f16_abi) {
            symbol(&__aeabi_h2f, "__gnu_h2f_ieee");
        } else {
            symbol(&__aeabi_h2f, "__aeabi_h2f");
        }
    } else if (compiler_rt.gnu_f16_abi) {
        symbol(&__extendhfsf2, "__gnu_h2f_ieee");
    }
    symbol(&__extendhfsf2, "__extendhfsf2");
    symbol(&__extendhfdf2, "__extendhfdf2");
    symbol(&__extendhfxf2, "__extendhfxf2");
    if (compiler_rt.want_ppc_abi) {
        symbol(&__extendhftf2, "__extendhfkf2");
    } else {
        symbol(&__extendhftf2, "__extendhftf2");
    }

    if (compiler_rt.want_aeabi) {
        symbol(&__aeabi_f2d, "__aeabi_f2d");
    } else {
        symbol(&__extendsfdf2, "__extendsfdf2");
    }
    symbol(&__extendsfxf2, "__extendsfxf2");
    if (compiler_rt.want_ppc_abi) {
        symbol(&__extendsftf2, "__extendsfkf2");
    } else if (compiler_rt.want_sparc64_abi) {
        symbol(&_Qp_stoq, "_Qp_stoq");
    } else if (compiler_rt.want_sparc32_abi) {
        symbol(&__extendsftf2, "_Q_stoq");
    } else {
        symbol(&__extendsftf2, "__extendsftf2");
    }

    symbol(&__extenddfxf2, "__extenddfxf2");
    if (compiler_rt.want_ppc_abi) {
        symbol(&__extenddftf2, "__extenddfkf2");
    } else if (compiler_rt.want_sparc64_abi) {
        symbol(&_Qp_dtoq, "_Qp_dtoq");
    } else if (compiler_rt.want_sparc32_abi) {
        symbol(&__extenddftf2, "_Q_dtoq");
    } else {
        symbol(&__extenddftf2, "__extenddftf2");
    }

    if (compiler_rt.want_ppc_abi) {
        symbol(&__extendxftf2, "__extendxfkf2");
    } else {
        symbol(&__extendxftf2, "__extendxftf2");
    }
}

fn __extendhfsf2(a: compiler_rt.f16Conv(f32).Abi) callconv(.c) compiler_rt.f32.Abi {
    return compiler_rt.f32.toAbi(f32_floatCast_f16(compiler_rt.f16Conv(f32).fromAbi(a)));
}
fn __aeabi_h2f(a: u16) callconv(.{ .arm_aapcs = .{} }) u32 {
    return @bitCast(f32_floatCast_f16(@bitCast(a)));
}
pub fn f32_floatCast_f16(a: f16) f32 {
    return extendf(f32, f16, a);
}

fn __extendhfdf2(a: compiler_rt.f16Conv(f64).Abi) callconv(.c) compiler_rt.f64.Abi {
    return compiler_rt.f64.toAbi(f64_floatCast_f16(compiler_rt.f16Conv(f64).fromAbi(a)));
}
pub fn f64_floatCast_f16(a: f16) f64 {
    return extendf(f64, f16, a);
}

fn __extendhfxf2(a: compiler_rt.f16Conv(f80).Abi) callconv(.c) compiler_rt.f80.Abi {
    return compiler_rt.f80.toAbi(f80_floatCast_f16(compiler_rt.f16Conv(f80).fromAbi(a)));
}
pub fn f80_floatCast_f16(a: f16) f80 {
    return extend_f80(f16, a);
}

fn __extendhftf2(a: compiler_rt.f16Conv(f128).Abi) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(f128_floatCast_f16(compiler_rt.f16Conv(f128).fromAbi(a)));
}
pub fn f128_floatCast_f16(a: f16) f128 {
    return extendf(f128, f16, a);
}

fn __extendsfdf2(a: compiler_rt.f32.Abi) callconv(.c) compiler_rt.f64.Abi {
    return compiler_rt.f64.toAbi(f64_floatCast_f32(compiler_rt.f32.fromAbi(a)));
}
fn __aeabi_f2d(a: f32) callconv(.{ .arm_aapcs = .{} }) f64 {
    return f64_floatCast_f32(a);
}
pub fn f64_floatCast_f32(a: f32) f64 {
    return extendf(f64, f32, a);
}

fn __extendsfxf2(a: compiler_rt.f32.Abi) callconv(.c) compiler_rt.f80.Abi {
    return compiler_rt.f80.toAbi(f80_floatCast_f32(compiler_rt.f32.fromAbi(a)));
}
pub fn f80_floatCast_f32(a: f32) f80 {
    return extend_f80(f32, a);
}

pub fn __extendsftf2(a: compiler_rt.f32.Abi) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(f128_floatCast_f32(compiler_rt.f32.fromAbi(a)));
}
fn _Qp_stoq(c: *f128, a: f32) callconv(.c) void {
    c.* = f128_floatCast_f32(a);
}
pub fn f128_floatCast_f32(a: f32) f128 {
    return extendf(f128, f32, a);
}

fn __extenddfxf2(a: compiler_rt.f64.Abi) callconv(.c) compiler_rt.f80.Abi {
    return compiler_rt.f80.toAbi(f80_floatCast_f64(compiler_rt.f64.fromAbi(a)));
}
pub fn f80_floatCast_f64(a: f64) f80 {
    return extend_f80(f64, a);
}

fn __extenddftf2(a: compiler_rt.f64.Abi) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(f128_floatCast_f64(compiler_rt.f64.fromAbi(a)));
}
fn _Qp_dtoq(c: *f128, a: f64) callconv(.c) void {
    c.* = f128_floatCast_f64(a);
}
pub fn f128_floatCast_f64(a: f64) f128 {
    return extendf(f128, f64, a);
}

fn __extendxftf2(a: compiler_rt.f80.Abi) callconv(.c) compiler_rt.f128.Abi {
    return compiler_rt.f128.toAbi(f128_floatCast_f80(compiler_rt.f80.fromAbi(a)));
}
pub fn f128_floatCast_f80(a: f80) f128 {
    const src_int_bit: u64 = 0x8000000000000000;
    const src_sig_mask = ~src_int_bit;
    const src_sig_bits = std.math.floatMantissaBits(f80) - 1; // -1 for the integer bit
    const dst_sig_bits = std.math.floatMantissaBits(f128);

    const dst_bits = @bitSizeOf(f128);

    // Break a into a sign and representation of the absolute value
    var a_rep: std.math.F80 = .fromFloat(a);
    const sign = a_rep.exp & 0x8000;
    a_rep.exp &= 0x7FFF;
    var abs_result: u128 = undefined;

    if (a_rep.exp == 0 and a_rep.fraction == 0) {
        // zero
        abs_result = 0;
    } else if (a_rep.exp == 0x7FFF) {
        // a is nan or infinite
        abs_result = @as(u128, a_rep.fraction) << (dst_sig_bits - src_sig_bits);
        abs_result |= @as(u128, a_rep.exp) << dst_sig_bits;
    } else if (a_rep.fraction & src_int_bit != 0) {
        // a is a normal value
        abs_result = @as(u128, a_rep.fraction & src_sig_mask) << (dst_sig_bits - src_sig_bits);
        abs_result |= @as(u128, a_rep.exp) << dst_sig_bits;
    } else {
        // a is denormal
        abs_result = @as(u128, a_rep.fraction) << (dst_sig_bits - src_sig_bits);
    }

    // Apply the signbit to (dst_t)abs(a).
    const result: u128 = abs_result | @as(u128, sign) << (dst_bits - 16);
    return @bitCast(result);
}

inline fn extendf(comptime dst_t: type, comptime src_t: type, f: src_t) dst_t {
    const src_rep_t = @Int(.unsigned, @typeInfo(src_t).float.bits);
    const dst_rep_t = @Int(.unsigned, @typeInfo(dst_t).float.bits);
    const srcSigBits = std.math.floatMantissaBits(src_t);
    const dstSigBits = std.math.floatMantissaBits(dst_t);

    // Various constants whose values follow from the type parameters.
    // Any reasonable optimizer will fold and propagate all of these.
    const srcBits = @bitSizeOf(src_t);
    const srcExpBits = srcBits - srcSigBits - 1;
    const srcInfExp = (1 << srcExpBits) - 1;
    const srcExpBias = srcInfExp >> 1;

    const srcMinNormal = 1 << srcSigBits;
    const srcInfinity = srcInfExp << srcSigBits;
    const srcSignMask = 1 << (srcSigBits + srcExpBits);
    const srcAbsMask = srcSignMask - 1;
    const srcQNaN = 1 << (srcSigBits - 1);
    const srcNaNCode = srcQNaN - 1;

    const dstBits = @bitSizeOf(dst_t);
    const dstExpBits = dstBits - dstSigBits - 1;
    const dstInfExp = (1 << dstExpBits) - 1;
    const dstExpBias = dstInfExp >> 1;

    const dstMinNormal: dst_rep_t = @as(dst_rep_t, 1) << dstSigBits;

    const a: src_rep_t = @bitCast(f);
    // Break a into a sign and representation of the absolute value
    const aRep: src_rep_t = @bitCast(a);
    const aAbs: src_rep_t = aRep & srcAbsMask;
    const sign: src_rep_t = aRep & srcSignMask;
    var absResult: dst_rep_t = undefined;

    if (aAbs -% srcMinNormal < srcInfinity - srcMinNormal) {
        // a is a normal number.
        // Extend to the destination type by shifting the significand and
        // exponent into the proper position and rebiasing the exponent.
        absResult = @as(dst_rep_t, aAbs) << (dstSigBits - srcSigBits);
        absResult += (dstExpBias - srcExpBias) << dstSigBits;
    } else if (aAbs >= srcInfinity) {
        // a is NaN or infinity.
        // Conjure the result by beginning with infinity, then setting the qNaN
        // bit (if needed) and right-aligning the rest of the trailing NaN
        // payload field.
        absResult = dstInfExp << dstSigBits;
        absResult |= @as(dst_rep_t, aAbs & srcQNaN) << (dstSigBits - srcSigBits);
        absResult |= @as(dst_rep_t, aAbs & srcNaNCode) << (dstSigBits - srcSigBits);
    } else if (aAbs != 0) {
        // a is denormal.
        // renormalize the significand and clear the leading bit, then insert
        // the correct adjusted exponent in the destination type.
        const scale: u32 = @clz(aAbs) - @clz(@as(src_rep_t, srcMinNormal));
        absResult = @as(dst_rep_t, aAbs) << @intCast(dstSigBits - srcSigBits + scale);
        absResult ^= dstMinNormal;
        const resultExponent: u32 = dstExpBias - srcExpBias - scale + 1;
        absResult |= @as(dst_rep_t, @intCast(resultExponent)) << dstSigBits;
    } else {
        // a is zero.
        absResult = 0;
    }

    // Apply the signbit to (dst_t)abs(a).
    const result: dst_rep_t = absResult | @as(dst_rep_t, sign) << (dstBits - srcBits);
    return @bitCast(result);
}

inline fn extend_f80(comptime src_t: type, f: src_t) f80 {
    const src_rep_t = @Int(.unsigned, @typeInfo(src_t).float.bits);
    const src_sig_bits = std.math.floatMantissaBits(src_t);
    const dst_int_bit = 0x8000000000000000;
    const dst_sig_bits = std.math.floatMantissaBits(f80) - 1; // -1 for the integer bit

    const dst_exp_bias = 16383;

    const src_bits = @bitSizeOf(src_t);
    const src_exp_bits = src_bits - src_sig_bits - 1;
    const src_inf_exp = (1 << src_exp_bits) - 1;
    const src_exp_bias = src_inf_exp >> 1;

    const src_min_normal = 1 << src_sig_bits;
    const src_inf = src_inf_exp << src_sig_bits;
    const src_sign_mask = 1 << (src_sig_bits + src_exp_bits);
    const src_abs_mask = src_sign_mask - 1;
    const src_qnan = 1 << (src_sig_bits - 1);
    const src_nan_code = src_qnan - 1;

    var dst: std.math.F80 = undefined;

    const a: src_rep_t = @bitCast(f);
    // Break a into a sign and representation of the absolute value
    const a_abs = a & src_abs_mask;
    const sign: u16 = if (a & src_sign_mask != 0) 0x8000 else 0;

    if (a_abs -% src_min_normal < src_inf - src_min_normal) {
        // a is a normal number.
        // Extend to the destination type by shifting the significand and
        // exponent into the proper position and rebiasing the exponent.
        dst.exp = @intCast(a_abs >> src_sig_bits);
        dst.exp += dst_exp_bias - src_exp_bias;
        dst.fraction = @as(u64, a_abs) << (dst_sig_bits - src_sig_bits);
        dst.fraction |= dst_int_bit; // bit 64 is always set for normal numbers
    } else if (a_abs >= src_inf) {
        // a is NaN or infinity.
        // Conjure the result by beginning with infinity, then setting the qNaN
        // bit (if needed) and right-aligning the rest of the trailing NaN
        // payload field.
        dst.exp = 0x7fff;
        dst.fraction = dst_int_bit;
        dst.fraction |= @as(u64, a_abs & src_qnan) << (dst_sig_bits - src_sig_bits);
        dst.fraction |= @as(u64, a_abs & src_nan_code) << (dst_sig_bits - src_sig_bits);
    } else if (a_abs != 0) {
        // a is denormal.
        // renormalize the significand and clear the leading bit, then insert
        // the correct adjusted exponent in the destination type.
        const scale: u16 = @clz(a_abs) - @clz(@as(src_rep_t, src_min_normal));

        dst.fraction = @as(u64, a_abs) << @intCast(dst_sig_bits - src_sig_bits + scale);
        dst.fraction |= dst_int_bit; // bit 64 is always set for normal numbers
        dst.exp = @truncate(a_abs >> @intCast(src_sig_bits - scale));
        dst.exp ^= 1;
        dst.exp |= dst_exp_bias - src_exp_bias - scale + 1;
    } else {
        // a is zero.
        dst.exp = 0;
        dst.fraction = 0;
    }

    dst.exp |= sign;
    return dst.toFloat();
}

test {
    _ = @import("extendf_test.zig");
}
